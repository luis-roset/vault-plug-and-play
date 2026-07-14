## Create a Linux VM on the same network than the Vault Enterprise Cluster

FROM debian:bullseye-slim

RUN apt-get update && apt-get install -y \
    curl unzip ca-certificates && \
    rm -rf /var/lib/apt/lists/*

ENV VAULT_RADAR_VERSION=0.26.0

RUN curl -sSL https://releases.hashicorp.com/vault-radar/${VAULT_RADAR_VERSION}/vault-radar_${VAULT_RADAR_VERSION}_linux_amd64.zip \
  -o vault-radar.zip && \
  unzip vault-radar.zip && \
  mv vault-radar /usr/local/bin/ && \
  chmod +x /usr/local/bin/vault-radar && \
  rm -f vault-radar.zip

ENTRYPOINT ["vault-radar"]

## Create a Service Principal from HCP and create a key to generate a client_id and client_secret
## Configure the Vault Radar Agent

docker run --rm -it \
  --network tech-link_default \
  -v ./tls/vault-ca.pem:/vault-ca.pem:ro \
  -e HCP_PROJECT_ID=<YOUR_HCP_PROJECT_ID> \
  -e HCP_RADAR_AGENT_POOL_ID=<YOUR_AGENT_POOL_ID> \
  -e HCP_CLIENT_ID=<YOUR_HCP_CLIENT_ID> \
  -e HCP_CLIENT_SECRET=<YOUR_HCP_CLIENT_SECRET> \
  -e VAULT_RADAR_VAULT_TLS_CA_CERT=/vault-ca.pem \
  -e VAULT_RADAR_VAULT_TOKEN=<YOUR_VAULT_TOKEN> \
  vault-radar \
  agent exec

## Configure ngrok or any service to have a public DNS if you don't have it to expose the service publicly
  ngrok:
    image: ngrok/ngrok:latest
    container_name: ngrok
    restart: unless-stopped
    command: http https://server3:8200
    environment:
      - NGROK_AUTHTOKEN=<YOUR_NGROK_AUTHTOKEN>
    depends_on:
      - server3

## Configure the Secret Manager from the UI in order to connect Vault Radar to your Vault Enterprise cluster

  