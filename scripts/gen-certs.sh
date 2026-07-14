#!/usr/bin/env bash
# =============================================================================
# Generate self-signed CA and per-node TLS certificates.
# Called by deploy.sh — not intended to be run standalone.
#
# Output structure:
#   tls/
#   ├── ca.crt              shared CA certificate
#   ├── ca.key              CA private key
#   ├── vault-node1/
#   │   ├── ca.crt          copy of CA cert (mounted into container)
#   │   ├── vault.crt       node server certificate
#   │   └── vault.key       node private key
#   └── vault-node2/        (created only when NODE_COUNT=2)
#       ├── ca.crt
#       ├── vault.crt
#       └── vault.key
# =============================================================================
set -euo pipefail

NODE_COUNT="${1:-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TLS_DIR="${SCRIPT_DIR}/../tls"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }

mkdir -p "${TLS_DIR}"

# ── Generate CA (only once; skip if already present) ─────────────────────────
if [[ -f "${TLS_DIR}/ca.crt" && -f "${TLS_DIR}/ca.key" ]]; then
  log_warn "CA certificate already exists at tls/ca.crt — reusing it."
else
  log_info "Generating CA key and certificate ..."
  openssl genrsa -out "${TLS_DIR}/ca.key" 4096 2>/dev/null

  openssl req -new -x509 -days 3650 \
    -key  "${TLS_DIR}/ca.key" \
    -out  "${TLS_DIR}/ca.crt" \
    -subj "/CN=Vault CA/O=Vault Enterprise/OU=Local Dev" \
    2>/dev/null

  log_info "CA certificate written to tls/ca.crt"
fi

# ── Generate a server certificate for one node ───────────────────────────────
gen_node_cert() {
  local node_name="$1"
  local node_dir="${TLS_DIR}/${node_name}"

  if [[ -f "${node_dir}/vault.crt" && -f "${node_dir}/vault.key" ]]; then
    log_warn "Certificates for ${node_name} already exist — reusing them."
    return
  fi

  log_info "Generating TLS certificate for ${node_name} ..."
  mkdir -p "${node_dir}"

  # Private key
  openssl genrsa -out "${node_dir}/vault.key" 2048 2>/dev/null

  # CSR with SANs so both the container hostname AND localhost are valid
  openssl req -new \
    -key  "${node_dir}/vault.key" \
    -out  "${node_dir}/vault.csr" \
    -subj "/CN=${node_name}/O=Vault Enterprise/OU=Local Dev" \
    2>/dev/null

  # Extension file — SANs cover internal Podman DNS name and host-side access
  cat > "${node_dir}/san.ext" <<EOF
subjectAltName = DNS:${node_name},DNS:localhost,IP:127.0.0.1
EOF

  # Sign with the CA
  openssl x509 -req -days 3650 \
    -in      "${node_dir}/vault.csr" \
    -CA      "${TLS_DIR}/ca.crt" \
    -CAkey   "${TLS_DIR}/ca.key" \
    -CAcreateserial \
    -out     "${node_dir}/vault.crt" \
    -extfile "${node_dir}/san.ext" \
    2>/dev/null

  # Place the CA cert in the node dir so the container has it at /vault/tls/ca.crt
  cp "${TLS_DIR}/ca.crt" "${node_dir}/ca.crt"

  # Cleanup temp files
  rm -f "${node_dir}/vault.csr" "${node_dir}/san.ext"

  log_info "  ${node_dir}/vault.crt"
  log_info "  ${node_dir}/vault.key"
}

# ── Generate per-node certs ───────────────────────────────────────────────────
gen_node_cert "vault-node1"

if [[ "${NODE_COUNT}" == "2" ]]; then
  gen_node_cert "vault-node2"
fi

log_info "TLS certificate generation complete."
