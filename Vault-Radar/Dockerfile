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

