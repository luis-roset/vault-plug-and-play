# Guide to deploy a Vault cluster and connect it to a Grafana instance

## Vault cluster config file creation

```
cat > ./Prometheus/vault-config/server.hcl << EOF
api_addr  = "http://127.0.0.1:8200"

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = "true"
}

storage "file" {
  path = "/vault/data"
}

telemetry {
  disable_hostname = true
  prometheus_retention_time = "12h"
}
EOF
```

## Create the Vault cluster

``` 
docker run \
    --cap-add=IPC_LOCK \
    --detach \
    --ip 10.42.74.100 \
    --name learn-vault \
    --network learn-vault \
    -p 8200:8200 \
    --rm \
    --volume ./Prometheus/vault-config:/vault/config \
    --volume ./Prometheus/vault-data:/vault/data \
    hashicorp/vault server    
```

### Initialise the Vault cluster

```
vault operator init \
    -key-shares=1 \
    -key-threshold=1 \
    | head -n3 \
    | cat > ./Prometheus/.vault-init 
```

### Unseal the cluster
````
vault operator unseal
 ````
And provide the unseal key inside the vault-init file

### Login as root
```
vault login <ROOT_TOKEN>
```

## Prometheus - Grafana
 Define ACL policy so Prometheus can access the cluster metrics

 ```
 vault policy write prometheus-metrics - << EOF
path "/sys/metrics" {
  capabilities = ["read"]
}
EOF
```

### Create a token with the policy attached
```
vault token create \
  -field=token \
  -policy prometheus-metrics \
  > ./prometheus-config/prometheus-token
```

### Configure the prometheus.yml file and dowload latest prometheus image
```
cat > ./prometheus-config/prometheus.yml << EOF
scrape_configs:
  - job_name: vault
    metrics_path: /v1/sys/metrics
    params:
      format: ['prometheus']
    scheme: http
    authorization:
      credentials_file: /etc/prometheus/prometheus-token
    static_configs:
    - targets: ['10.42.74.100:8200']
EOF
```
```
docker pull prom/prometheus
```

### Create the Prometheus container with the defined configuration
```
docker run \
    --detach \
    --ip 10.42.74.110 \
    --name learn-prometheus \
    --network learn-vault \
    -p 9090:9090 \
    --rm \
    --volume ./prometheus-config/prometheus.yml:/etc/prometheus/prometheus.yml \
    --volume ./prometheus-config/prometheus-token:/etc/prometheus/prometheus-token \
    prom/prometheus
```

### Create the Grafana configuration and pull latest image
```
cat > ./grafana-config/datasource.yml << EOF
# config file version
apiVersion: 1

datasources:
- name: vault
  type: prometheus
  access: server
  orgId: 1
  url: http://10.42.74.110:9090
  password:
  user:
  database:
  basicAuth:
  basicAuthUser:
  basicAuthPassword:
  withCredentials:
  isDefault:
  jsonData:
     graphiteVersion: "1.1"
     tlsAuth: false
     tlsAuthWithCACert: false
  secureJsonData:
    tlsCACert: ""
    tlsClientCert: ""
    tlsClientKey: ""
  version: 1
  editable: true
EOF
```

```
docker pull grafana/grafana:latest
```

### Create the Grafana container
```
docker run \
    --detach \
    --ip 10.42.74.120 \
    --name learn-grafana \
    --network learn-vault \
    -p 3000:3000 \
    --rm \
    --volume ./grafana-config/datasource.yml:/etc/grafana/provisioning/datasources/prometheus_datasource.yml \
    grafana/grafana
```
