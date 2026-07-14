# =============================================================================
# Vault Enterprise — Single Node Configuration
# Storage: Raft (integrated storage)
# TLS: disabled (suitable for local/dev use)
# =============================================================================

ui             = true
cluster_name   = "vault-enterprise"
log_level      = "info"
disable_mlock  = true

# ── Integrated Raft Storage ───────────────────────────────────────────────────
storage "raft" {
  path    = "/vault/data"
  node_id = "vault-node1"
}

# ── TCP Listener ──────────────────────────────────────────────────────────────
listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/vault/tls/vault.crt"
  tls_key_file  = "/vault/tls/vault.key"
}

# ── Addresses ─────────────────────────────────────────────────────────────────
# api_addr is the address Vault advertises to other cluster members and clients.
# Uses the container hostname (set by --hostname in podman run).
api_addr     = "https://vault-node1:8200"
cluster_addr = "https://vault-node1:8201"
