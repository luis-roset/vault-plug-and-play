#!/usr/bin/env bash
# =============================================================================
# Vault Initialization & Unseal Helper
# Called by deploy.sh — not intended to be run standalone.
# =============================================================================
set -euo pipefail

NODE_COUNT="${1:-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${SCRIPT_DIR}/../data"
CACERT="${SCRIPT_DIR}/../tls/ca.crt"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── Wait until Vault API responds (any HTTP status is fine) ───────────────────
wait_for_vault() {
  local addr="$1"
  local name="$2"
  local max_attempts=30
  local attempt=0

  log_info "Waiting for ${name} to respond at ${addr} ..."
  while true; do
    local http_code
    http_code=$(curl -so /dev/null -w '%{http_code}' \
      --connect-timeout 2 --cacert "${CACERT}" \
      "${addr}/v1/sys/health" 2>/dev/null || true)

    # Any of these codes means Vault is up (various states)
    case "${http_code}" in
      200|429|472|473|501|503) break ;;
    esac

    attempt=$((attempt + 1))
    if [[ ${attempt} -ge ${max_attempts} ]]; then
      log_error "${name} did not become available after $((max_attempts * 2))s. Check container logs:"
      log_error "  podman logs ${name}"
      exit 1
    fi
    sleep 2
  done
  log_info "${name} is responding."
}

# ── Initialize a node and unseal it ──────────────────────────────────────────
init_and_unseal() {
  local addr="$1"
  local name="$2"
  local data_dir="$3"
  local init_file="${data_dir}/init.json"

  mkdir -p "${data_dir}"

  # Check current initialization state
  local init_status
  init_status=$(curl -sf --cacert "${CACERT}" "${addr}/v1/sys/init" | jq -r '.initialized')

  if [[ "${init_status}" == "true" ]]; then
    log_warn "${name} is already initialized."

    # Check if it's sealed
    local seal_status
    seal_status=$(curl -sf --cacert "${CACERT}" "${addr}/v1/sys/seal-status" | jq -r '.sealed')

    if [[ "${seal_status}" == "true" ]]; then
      if [[ -f "${init_file}" ]]; then
        log_info "Unsealing ${name} using existing init.json..."
        local unseal_key
        unseal_key=$(jq -r '.keys[0]' "${init_file}")
        curl -sf --cacert "${CACERT}" -X PUT "${addr}/v1/sys/unseal" \
          -H "Content-Type: application/json" \
          -d "{\"key\": \"${unseal_key}\"}" > /dev/null
        log_info "${name} unsealed."
      else
        log_warn "${name} is sealed and no init.json found. Manual unseal required."
      fi
    else
      log_info "${name} is already unsealed."
    fi
    return
  fi

  # ── Initialize ──────────────────────────────────────────────────────────────
  log_info "Initializing ${name} (1 key share, threshold 1) ..."
  curl -sf --cacert "${CACERT}" -X PUT "${addr}/v1/sys/init" \
    -H "Content-Type: application/json" \
    -d '{"secret_shares": 1, "secret_threshold": 1}' \
    -o "${init_file}"

  log_info "Init credentials saved to: ${init_file}"

  local unseal_key root_token
  unseal_key=$(jq -r '.keys[0]' "${init_file}")
  root_token=$(jq -r '.root_token' "${init_file}")

  # ── Unseal ──────────────────────────────────────────────────────────────────
  log_info "Unsealing ${name} ..."
  curl -sf --cacert "${CACERT}" -X PUT "${addr}/v1/sys/unseal" \
    -H "Content-Type: application/json" \
    -d "{\"key\": \"${unseal_key}\"}" > /dev/null

  log_info "${name} initialized and unsealed."
  echo -e "    ${GREEN}Root Token:${NC} ${root_token}"
  echo -e "    ${GREEN}Unseal Key:${NC} ${unseal_key}"
}

# =============================================================================
# Main
# =============================================================================
wait_for_vault "https://localhost:8200" "vault-node1"
init_and_unseal "https://localhost:8200" "vault-node1" "${DATA_DIR}/vault-node1"

if [[ "${NODE_COUNT}" == "2" ]]; then
  wait_for_vault "https://localhost:8202" "vault-node2"
  init_and_unseal "https://localhost:8202" "vault-node2" "${DATA_DIR}/vault-node2"
fi
