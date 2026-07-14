username={{ with secret "kv/data/demo" }}{{ .Data.data.username }}{{ end }}
password={{ with secret "kv/data/demo" }}{{ .Data.data.password }}{{ end }}