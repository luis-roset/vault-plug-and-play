#!/usr/bin/env bash
# =============================================================================
# Vault Enterprise — Teardown Script
# Removes all containers, the Podman network, and local data.
# =============================================================================
set -euo pipefail

NETWORK_NAME="vault-network"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${SCRIPT_DIR}/data"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }

echo -e "${RED}WARNING: This will permanently remove all Vault containers, the Podman"
echo -e "network '${NETWORK_NAME}', and all Vault data under ${DATA_DIR}.${NC}"
echo
read -rp "Are you sure you want to continue? [y/N] " confirm
if [[ "${confirm,,}" != "y" ]]; then
  echo "Aborted."
  exit 0
fi

echo

# ── Remove containers ─────────────────────────────────────────────────────────
for container in vault-node1 vault-node2; do
  if podman container exists "${container}" 2>/dev/null; then
    log_info "Stopping and removing container: ${container}"
    podman rm -f "${container}"
  else
    log_warn "Container '${container}' not found — skipping."
  fi
done

# ── Remove Podman network ─────────────────────────────────────────────────────
if podman network exists "${NETWORK_NAME}" 2>/dev/null; then
  log_info "Removing Podman network: ${NETWORK_NAME}"
  podman network rm "${NETWORK_NAME}"
else
  log_warn "Network '${NETWORK_NAME}' not found — skipping."
fi

# ── Remove data directory ─────────────────────────────────────────────────────
if [[ -d "${DATA_DIR}" ]]; then
  log_warn "Removing data directory: ${DATA_DIR}"
  rm -rf "${DATA_DIR}"
  log_info "Data directory removed."
else
  log_warn "Data directory '${DATA_DIR}' not found — skipping."
fi

echo
log_info "Teardown complete."
