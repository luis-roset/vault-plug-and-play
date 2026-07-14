auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    config = {
      role_id_file_path   = "./role_id"
      secret_id_file_path = "./secret_id"
    }
  }
  sink "file" {
    config = {
      path = "./agent-token"
    }
  }
}

template {
  source      = "./secrets.tpl"
  destination = "./secrets.txt"
  perms       = "0600"
}

env_template "VAULT_PASSWORD" {
  contents = "{{ with secret \"kv/data/demo\" }}{{ .Data.data.password }}{{ end }}"
}

exec {
  command = ["./demo-app.sh"]
  restart_on_secret_changes = "always"
  restart_stop_signal = "SIGTERM"
}