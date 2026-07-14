ui            = true
cluster_addr  = "http://mcp-server:8201"
api_addr      = "http://mcp-server:8200"
disable_mlock = true

storage "raft" {
  path = "/raft"
  node_id = "mcp-server"
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_disable   = 1
}

license_path = "/etc/vault.d/vault.hclic"