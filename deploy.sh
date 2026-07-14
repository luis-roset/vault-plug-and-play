#!/usr/bin/env bash
# =============================================================================
# Vault Enterprise — Podman Deployment Script
# =============================================================================
set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Constants ─────────────────────────────────────────────────────────────────
VAULT_IMAGE="hashicorp/vault-enterprise"
NETWORK_NAME="vault-network"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/config"
DATA_DIR="${SCRIPT_DIR}/data"
TLS_DIR="${SCRIPT_DIR}/tls"
ENV_FILE="${SCRIPT_DIR}/.env"

# ── Helpers ───────────────────────────────────────────────────────────────────
log_info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_section() { echo -e "\n${BLUE}${BOLD}══ $* ══${NC}"; }

# ── Dependency check ──────────────────────────────────────────────────────────
for cmd in podman curl jq openssl; do
  if ! command -v "${cmd}" &>/dev/null; then
    log_error "Required command '${cmd}' not found. Please install it before running this script."
    exit 1
  fi
done

# ── Load .env if present ──────────────────────────────────────────────────────
if [[ -f "${ENV_FILE}" ]]; then
  log_info "Loading configuration from .env"
  # shellcheck disable=SC1090
  set -a; source "${ENV_FILE}"; set +a
fi

# ── Banner ────────────────────────────────────────────────────────────────────
echo -e "${CYAN}${BOLD}"
cat << 'BANNER'
  ╦  ╦┌─┐┬ ┬┬ ┌┬┐  ╔═╗┌┐┌┌┬┐┌─┐┬─┐┌─┐┬─┐┬┌─┐┌─┐
  ╚╗╔╝├─┤│ ││  │   ║╣ │││ │ ├┤ ├┬┘├─┘├┬┘│└─┐├┤
   ╚╝ ┴ ┴└─┘┴─┘┴   ╚═╝┘└┘ ┴ └─┘┴└─┴  ┴└─┴└─┘└─┘
          Podman Deployment Script
BANNER
echo -e "${NC}"

# =============================================================================
# STEP 1 — Vault Enterprise version
# =============================================================================
log_section "Vault Enterprise Version"
if [[ -z "${VAULT_VERSION:-}" ]]; then
  read -rp "  Enter Vault Enterprise version [latest]: " VAULT_VERSION
  VAULT_VERSION="${VAULT_VERSION:-latest}"
fi

# Normalize version: append "-ent" suffix if needed (e.g. "1.18.4" → "1.18.4-ent")
if [[ "${VAULT_VERSION}" != "latest" && ! "${VAULT_VERSION}" =~ -ent$ ]]; then
  VAULT_VERSION="${VAULT_VERSION}-ent"
fi
log_info "Using image: ${VAULT_IMAGE}:${VAULT_VERSION}"

# =============================================================================
# STEP 2 — Number of nodes
# =============================================================================
log_section "Cluster Topology"
if [[ -z "${NODE_COUNT:-}" ]]; then
  while true; do
    read -rp "  How many nodes would you like to deploy? [1/2] (default: 1): " NODE_COUNT
    NODE_COUNT="${NODE_COUNT:-1}"
    if [[ "${NODE_COUNT}" == "1" || "${NODE_COUNT}" == "2" ]]; then
      break
    fi
    log_warn "  Please enter 1 or 2."
  done
fi
log_info "Deploying ${NODE_COUNT} node(s)"

if [[ "${NODE_COUNT}" == "2" ]]; then
  echo -e "  ${CYAN}2-node setup: node1 will be the Performance Replication primary,"
  echo -e "  node2 will be the secondary.${NC}"
fi

# =============================================================================
# STEP 3 — Enterprise License
# =============================================================================
log_section "Enterprise License"
if [[ -z "${VAULT_LICENSE:-}" ]]; then
  log_warn "No VAULT_LICENSE found in environment or .env file."
  echo
  echo    "  How would you like to provide the license?"
  echo    "    1) Path to a license file  (recommended)"
  echo    "    2) Paste the license string"
  echo    "    3) Abort — I will add VAULT_LICENSE=\"...\" to .env and re-run"
  echo
  read -rp "  Choice [1/2/3] (default: 1): " _lic_choice
  _lic_choice="${_lic_choice:-1}"

  case "${_lic_choice}" in
    1)
      read -rp "  License file path: " _lic_path
      _lic_path="${_lic_path//\~/${HOME}}"   # expand ~ manually
      if [[ ! -f "${_lic_path}" ]]; then
        log_error "File not found: ${_lic_path}"
        exit 1
      fi
      VAULT_LICENSE="$(< "${_lic_path}")"
      ;;
    2)
      echo    "  Paste the license string and press Enter."
      echo -e "  ${YELLOW}Tip: if the terminal freezes, use option 1 or set VAULT_LICENSE in .env.${NC}"
      IFS= read -r VAULT_LICENSE
      ;;
    3)
      echo
      log_info "Add the following line to .env and re-run ./deploy.sh:"
      echo    "    VAULT_LICENSE=\"<your-license-string>\""
      exit 0
      ;;
    *)
      log_error "Invalid choice. Aborting."
      exit 1
      ;;
  esac

  if [[ -z "${VAULT_LICENSE}" ]]; then
    log_error "A valid enterprise license is required. Aborting."
    exit 1
  fi
fi
# Strip any surrounding whitespace or newlines (common when pasting or reading from .env)
VAULT_LICENSE="${VAULT_LICENSE//[$'\t\r\n ']}"
log_info "License loaded (${#VAULT_LICENSE} chars)"

# =============================================================================
# STEP 4 — Pull image
# =============================================================================
log_section "Pulling Image"
if ! podman pull "${VAULT_IMAGE}:${VAULT_VERSION}"; then
  log_error "Failed to pull '${VAULT_IMAGE}:${VAULT_VERSION}'."
  log_error "Check that the version tag is correct: https://hub.docker.com/r/hashicorp/vault-enterprise/tags"
  exit 1
fi

# =============================================================================
# STEP 5 — Podman network
# =============================================================================
log_section "Network Setup"
if podman network exists "${NETWORK_NAME}" 2>/dev/null; then
  log_warn "Network '${NETWORK_NAME}' already exists — reusing it."
else
  podman network create "${NETWORK_NAME}"
  log_info "Created Podman network: ${NETWORK_NAME}"
fi

# =============================================================================
# STEP 5.5 — Generate TLS certificates
# =============================================================================
log_section "TLS Certificates"
bash "${SCRIPT_DIR}/scripts/gen-certs.sh" "${NODE_COUNT}"

# =============================================================================
# STEP 6 — Deploy containers
# =============================================================================
deploy_node() {
  local node_name="$1"
  local config_file="$2"
  local api_port="$3"
  local cluster_port="$4"

  local data_path="${DATA_DIR}/${node_name}"
  local tls_path="${TLS_DIR}/${node_name}"
  mkdir -p "${data_path}"

  # Make the data directory world-writable so Vault (UID 100 inside the
  # container) can create the Raft bolt file regardless of how the remote
  # Podman VM maps UIDs on the host bind-mount.
  # (podman unshare is not available with the remote Podman client)
  chmod -R 777 "${data_path}"
  chmod -R 777 "${tls_path}"

  if podman container exists "${node_name}" 2>/dev/null; then
    log_warn "Container '${node_name}' already exists — removing it."
    podman rm -f "${node_name}"
  fi

  log_info "Starting ${node_name}  (API: localhost:${api_port}, Cluster: localhost:${cluster_port})"

  podman run -d \
    --name "${node_name}" \
    --network "${NETWORK_NAME}" \
    --hostname "${node_name}" \
    --cap-add IPC_LOCK \
    -e VAULT_LICENSE="${VAULT_LICENSE}" \
    -e VAULT_ADDR="https://127.0.0.1:8200" \
    -e VAULT_CACERT="/vault/tls/ca.crt" \
    -v "${CONFIG_DIR}/${config_file}:/vault/config/vault.hcl:ro,Z" \
    -v "${data_path}:/vault/data:Z" \
    -v "${tls_path}:/vault/tls:ro,Z" \
    -p "${api_port}:8200" \
    -p "${cluster_port}:8201" \
    "${VAULT_IMAGE}:${VAULT_VERSION}" \
    vault server -config=/vault/config/vault.hcl

  log_info "Container '${node_name}' started."
}

log_section "Deploying Vault Node(s)"

if [[ "${NODE_COUNT}" == "1" ]]; then
  deploy_node "vault-node1" "vault-single.hcl" "8200" "8201"
else
  deploy_node "vault-node1" "vault-node1.hcl" "8200" "8201"
  deploy_node "vault-node2" "vault-node2.hcl" "8202" "8203"
fi

# =============================================================================
# STEP 7 — Initialize and unseal
# =============================================================================
log_section "Vault Initialization"
bash "${SCRIPT_DIR}/scripts/init-vault.sh" "${NODE_COUNT}"

# =============================================================================
# STEP 8 — Performance Replication (2-node only)
# =============================================================================
if [[ "${NODE_COUNT}" == "2" ]]; then
  log_section "Performance Replication Setup"
  bash "${SCRIPT_DIR}/scripts/setup-replication.sh"
fi

# =============================================================================
# Summary
# =============================================================================
log_section "Deployment Complete"
echo
echo -e "  ${GREEN}Node 1 API:${NC} https://localhost:8200"
echo -e "  ${GREEN}Node 1 UI: ${NC} https://localhost:8200/ui"
if [[ "${NODE_COUNT}" == "2" ]]; then
  echo -e "  ${GREEN}Node 2 API:${NC} https://localhost:8202"
  echo -e "  ${GREEN}Node 2 UI: ${NC} https://localhost:8202/ui"
  echo
  echo -e "  ${YELLOW}Replication:${NC} Performance Replication active"
  echo -e "                node1 = primary  |  node2 = secondary"
fi
echo
echo -e "  ${CYAN}CA certificate:${NC}   ${TLS_DIR}/ca.crt  (trust this in your browser/CLI)"
echo -e "  ${CYAN}Init credentials:${NC} ${DATA_DIR}/<node>/init.json"
echo -e "  ${CYAN}Teardown:${NC}         ./teardown.sh"
echo
