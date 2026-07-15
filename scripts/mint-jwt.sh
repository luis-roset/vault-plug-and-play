#!/usr/bin/env bash
# =============================================================================
# Mint a signed RS256 JWT for local AI agent testing.
#
# What this script does:
#   1. Generates a local RSA key pair (once) under keys/
#   2. Registers the public key in the Vault OAuth Resource Server profile
#   3. Mints a signed JWT with the claims Vault expects
#   4. Prints the token and a ready-to-run curl test command
#
# Usage:
#   ./scripts/mint-jwt.sh
#
# Prerequisites:
#   - Vault node1 running and unsealed (./deploy.sh)
#   - VAULT_TOKEN set (export VAULT_TOKEN="..." from data/vault-node1/init.json)
#   - The OAuth Resource Server feature activated (Step 1 of the AI use case)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."
KEYS_DIR="${ROOT_DIR}/keys"
KEY_FILE="${KEYS_DIR}/jwt-signing.key"
PUB_FILE="${KEYS_DIR}/jwt-signing.pub"

VAULT_ADDR="${VAULT_ADDR:-https://localhost:8200}"
VAULT_CACERT="${VAULT_CACERT:-${ROOT_DIR}/tls/ca.crt}"
VAULT_TOKEN="${VAULT_TOKEN:?VAULT_TOKEN must be set. Export it from data/vault-node1/init.json}"

PROFILE_NAME="my-ai-platform"
ISSUER="https://my-ai-platform.example.com"
AUDIENCE="${VAULT_ADDR}"
SUBJECT="my-ai-agent"
KEY_ID="dev-key-1"
TTL=3600   # token lifetime in seconds

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_section() { echo -e "\n${CYAN}${BOLD}══ $* ══${NC}"; }

# ── base64url encode (no padding, url-safe chars) ─────────────────────────────
b64url() {
  openssl base64 -e | tr -d '=\n' | tr '+/' '-_'
}

# =============================================================================
# STEP 1 — Generate RSA key pair (skip if already present)
# =============================================================================
log_section "JWT Signing Key"
mkdir -p "${KEYS_DIR}"

if [[ -f "${KEY_FILE}" && -f "${PUB_FILE}" ]]; then
  log_info "Key pair already exists at keys/ — reusing."
else
  log_info "Generating 2048-bit RSA key pair ..."
  openssl genrsa -out "${KEY_FILE}" 2048 2>/dev/null
  openssl rsa -in "${KEY_FILE}" -pubout -out "${PUB_FILE}" 2>/dev/null
  log_info "Private key : keys/jwt-signing.key"
  log_info "Public key  : keys/jwt-signing.pub"
fi

# =============================================================================
# STEP 2 — Register the public key in the Vault OAuth profile
# =============================================================================
log_section "Registering Public Key in Vault Profile"

PUB_PEM=$(jq -Rs . < "${PUB_FILE}")   # JSON-escape the PEM string

curl --silent --show-error --fail \
  --cacert "${VAULT_CACERT}" \
  --request POST \
  --header "X-Vault-Token: ${VAULT_TOKEN}" \
  --header "Content-Type: application/json" \
  --url "${VAULT_ADDR}/v1/sys/config/oauth-resource-server/${PROFILE_NAME}" \
  --data "{
    \"issuer_id\": \"${ISSUER}\",
    \"use_jwks\": false,
    \"public_keys\": [{\"key_id\": \"${KEY_ID}\", \"pem\": ${PUB_PEM}}],
    \"audiences\": [\"${AUDIENCE}\"],
    \"supported_algorithms\": [\"RS256\"],
    \"optional_authorization_details\": true
  }"

log_info "Profile '${PROFILE_NAME}' updated with static public key."

# =============================================================================
# STEP 3 — Mint the JWT
# =============================================================================
log_section "Minting JWT"

NOW=$(date +%s)
EXP=$(( NOW + TTL ))

HEADER=$(printf '{"alg":"RS256","typ":"JWT","kid":"%s"}' "${KEY_ID}" | b64url)

PAYLOAD=$(printf \
  '{"sub":"%s","iss":"%s","aud":"%s","iat":%d,"exp":%d}' \
  "${SUBJECT}" "${ISSUER}" "${AUDIENCE}" "${NOW}" "${EXP}" \
  | b64url)

SIG=$(printf '%s' "${HEADER}.${PAYLOAD}" \
  | openssl dgst -sha256 -sign "${KEY_FILE}" \
  | b64url)

JWT="${HEADER}.${PAYLOAD}.${SIG}"

# =============================================================================
# Output
# =============================================================================
log_section "Result"
echo
echo -e "${YELLOW}JWT (expires in ${TTL}s):${NC}"
echo "${JWT}"
echo
echo -e "${YELLOW}Test with curl:${NC}"
echo "curl --cacert ${VAULT_CACERT} \\"
echo "  --header \"Authorization: Bearer ${JWT}\" \\"
echo "  --url \"${VAULT_ADDR}/v1/auth/token/lookup-self\""
echo
echo -e "${YELLOW}Or export and use the Vault CLI:${NC}"
echo "export VAULT_TOKEN_FOR_AGENT=\"${JWT}\""
echo "curl --cacert ${VAULT_CACERT} -H \"Authorization: Bearer \$VAULT_TOKEN_FOR_AGENT\" ${VAULT_ADDR}/v1/sys/health"
echo
