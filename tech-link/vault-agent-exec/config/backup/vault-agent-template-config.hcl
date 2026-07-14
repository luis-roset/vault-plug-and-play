pid_file = "./pidfile"

vault {
  address = "http://localhost:8200"
  retry {
    num_retries = 10
    # Optional: backoff = "5s"
  }
}

auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    config = {
      role_id_file_path    = "/etc/vault/role_id"
      secret_id_file_path  = "/etc/vault/secret_id"
    }
  }
}

template_config {
  static_secret_render_interval = "5m"
  exit_on_retry_failure = true
}

template {
  contents = <<EOH
connection_string={{ with secret "secret/data/app/config" }}{{ .Data.data.connection_string }}{{ end }}
certificate={{ with secret "pki/issue/app-cert" "common_name=app.example.com" "ttl=24h" }}{{ .Data.certificate }}{{ end }}
EOH
  destination = "./app/app.properties"
  error_on_missing_key = true
  exec {
    command = ["python3", "./app/batch-process.py"]
    timeout = "10m"
  }
}
