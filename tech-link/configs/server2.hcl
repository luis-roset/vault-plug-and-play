ui            = true
cluster_addr  = "https://server2:8201"
api_addr      = "https://server2:8200"
disable_mlock = true

storage "raft" {
  path = "/raft"
  node_id = "server2"
}

seal "transit" {

  address            = "https://server1:8200"
  token              = "<TRANSIT_UNSEAL_TOKEN>"

  // Key configuration
  key_name           = "autounseal"
  mount_path         = "transit/"
  tls_ca_cert        = "/tls/ca.pem"
  tls_client_cert    = "/tls/cert.pem"
  tls_client_key     = "/tls/key.pem"
  tls_server_name    = "server1"
  tls_skip_verify    = "true"
}

listener "tcp" {
  address       = "0.0.0.0:8200"

  tls_disable = 0
  tls_cert_file = "/tls/cert.pem"
  tls_key_file  = "/tls/key.pem"
  tls_client_ca_file = "/tls/ca.pem"
}

telemetry {
  disable_hostname = true
  prometheus_retention_time = "12h"
}

license_path = "/etc/vault.d/vault.hclic"