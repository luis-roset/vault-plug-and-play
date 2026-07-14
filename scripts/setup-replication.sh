#!/usr/bin/env bash
# =============================================================================
# Vault Enterprise — Performance Replication Setup
# Primary: vault-node1 (localhost:8200)
# Secondary: vault-node2 (localhost:8202)
# Called by deploy.sh — not intended to be run standalone.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${SCRIPT_DIR}/../data"
CACERT="${SCRIPT_DIR}/../tls/ca.crt"

PRIMARY_ADDR="https://localhost:8200"
SECONDARY_ADDR="https://localhost:8202"

# Container-internal addresses (used by Vault internals over the Podman network)
PRIMARY_CLUSTER_ADDR="https://vault-node1:8201"
PRIMARY_API_ADDR="https://vault-node1:8200"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── Read root tokens from init files ─────────────────────────────────────────
PRIMARY_INIT="${DATA_DIR}/vault-node1/init.json"
SECONDARY_INIT="${DATA_DIR}/vault-node2/init.json"

for f in "${PRIMARY_INIT}" "${SECONDARY_INIT}"; do
  if [[ ! -f "${f}" ]]; then
    log_error "Init file not found: ${f}"
    log_error "Run deploy.sh first to initialize both nodes."
    exit 1
  fi
done

PRIMARY_TOKEN=$(jq -r '.root_token' "${PRIMARY_INIT}")
SECONDARY_TOKEN=$(jq -r '.root_token' "${SECONDARY_INIT}")

# =============================================================================
# STEP 1 — Check if replication is already active on primary
# =============================================================================
REPL_STATE=$(curl -sf --cacert "${CACERT}" \
  -H "X-Vault-Token: ${PRIMARY_TOKEN}" \
  "${PRIMARY_ADDR}/v1/sys/replication/performance/status" \
  | jq -r '.data.mode // .mode // "unknown"')

if [[ "${REPL_STATE}" == "primary" ]]; then
  log_warn "Performance Replication is already enabled on node1 (primary). Skipping."
  exit 0
fi

# =============================================================================
# STEP 2 — Enable Performance Replication on primary
# =============================================================================
log_info "Enabling Performance Replication on primary (vault-node1) ..."

curl -sf --cacert "${CACERT}" \
  -H "X-Vault-Token: ${PRIMARY_TOKEN}" \
  -H "Content-Type: application/json" \
  -X POST "${PRIMARY_ADDR}/v1/sys/replication/performance/primary/enable" \
  -d "{\"primary_cluster_addr\": \"${PRIMARY_CLUSTER_ADDR}\"}" > /dev/null

log_info "Waiting for primary replication to initialize ..."
sleep 8

# =============================================================================
# STEP 3 — Generate secondary activation token
# =============================================================================
log_info "Generating secondary activation token for vault-node2 ..."

WRAP_RESPONSE=$(curl -sf --cacert "${CACERT}" \
  -H "X-Vault-Token: ${PRIMARY_TOKEN}" \
  -H "Content-Type: application/json" \
  -X POST "${PRIMARY_ADDR}/v1/sys/replication/performance/primary/secondary-token" \
  -d '{"id": "vault-node2", "ttl": "30m"}')

SECONDARY_ACT_TOKEN=$(echo "${WRAP_RESPONSE}" | jq -r '.wrap_info.token')

if [[ -z "${SECONDARY_ACT_TOKEN}" || "${SECONDARY_ACT_TOKEN}" == "null" ]]; then
  log_error "Failed to generate secondary activation token. Response:"
  echo "${WRAP_RESPONSE}" | jq .
  exit 1
fi

log_info "Secondary activation token obtained."

# =============================================================================
# STEP 4 — Activate secondary replication on node2
# =============================================================================
log_info "Activating Performance Replication on secondary (vault-node2) ..."

curl -sf --cacert "${CACERT}" \
  -H "X-Vault-Token: ${SECONDARY_TOKEN}" \
  -H "Content-Type: application/json" \
  -X POST "${SECONDARY_ADDR}/v1/sys/replication/performance/secondary/enable" \
  -d "{
    \"token\": \"${SECONDARY_ACT_TOKEN}\",
    \"primary_api_addr\": \"${PRIMARY_API_ADDR}\"
  }" > /dev/null

# =============================================================================
# STEP 5 — Wait and verify
# =============================================================================
log_info "Waiting for secondary to sync with primary ..."
sleep 15

log_info "Replication status — Primary (vault-node1):"
curl -sf --cacert "${CACERT}" \
  -H "X-Vault-Token: ${PRIMARY_TOKEN}" \
  "${PRIMARY_ADDR}/v1/sys/replication/performance/status" \
  | jq '{mode: .data.mode, state: .data.state, known_secondaries: .data.known_secondaries}'

echo
log_info "Replication status — Secondary (vault-node2):"
# The secondary re-issues its own root token; use a retry loop since the node
# may briefly restart during replication activation.
for i in {1..10}; do
  SEC_STATUS=$(curl -sf --cacert "${CACERT}" \
    -H "X-Vault-Token: ${SECONDARY_TOKEN}" \
    "${SECONDARY_ADDR}/v1/sys/replication/performance/status" 2>/dev/null || true)

  if [[ -n "${SEC_STATUS}" ]]; then
    echo "${SEC_STATUS}" | jq '{mode: .data.mode, state: .data.state, primary_cluster_addr: .data.primary_cluster_addr}'
    break
  fi
  sleep 3
done

echo
echo -e "  ${CYAN}Performance Replication is active.${NC}"
echo -e "  Changes to policies, auth methods, and secrets engines on node1"
echo -e "  will replicate automatically to node2."
echo
echo -e "  ${YELLOW}Note:${NC} The secondary may generate a new root token during activation."
echo -e "  Check ${DATA_DIR}/vault-node2/ or query the secondary's init status"
echo -e "  if you need to reauthenticate to node2."
