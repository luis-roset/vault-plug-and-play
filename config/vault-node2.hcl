# =============================================================================
# Vault Enterprise — Node 2 (Performance Replication Secondary)
# Storage: Raft (integrated storage)
# TLS: disabled (suitable for local/dev use)
# =============================================================================

ui             = true
cluster_name   = "vault-secondary"
log_level      = "info"
disable_mlock  = true

# ── Integrated Raft Storage ───────────────────────────────────────────────────
storage "raft" {
  path    = "/vault/data"
  node_id = "vault-node2"
}

# ── TCP Listener ──────────────────────────────────────────────────────────────
listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/vault/tls/vault.crt"
  tls_key_file  = "/vault/tls/vault.key"
}

# ── Addresses ─────────────────────────────────────────────────────────────────
# Uses the container hostname (set by --hostname in podman run).
# Cluster port 8201 is used for Raft and replication traffic (always mTLS).
api_addr     = "https://vault-node2:8200"
cluster_addr = "https://vault-node2:8201"
