auto_auth {
    method "approle" {
        config = {
            role_id_file_path = "/etc/vault.d/role"
            secret_id_file_path = "/etc/vault.d/secret"
            remove_secret_id_file_after_reading = false
        }
    }
    sink "file" {
        config = {
            path = "/etc/vault.d/.vault-token"
        }
    }
}

template {
    source = "/etc/vault.d/agent.tmpl"
    destination = "/etc/vault.d/output.yaml"
}
template_config {
  exit_on_retry_failure = true
  static_secret_render_interval = "10s"
}

vault {
    address = "https://server1:8200"
}