#!/bin/bash

set -euo pipefail

# 0. Load the license
export VAULT_LICENSE=$(cat /Users/pnavascues/bin/licenses/vault.hclic)

# 1. Start Vault server in dev mode (insecure, for demo only)
vault server -dev -dev-root-token-id="root" > logs/vault.log 2>&1 &
VAULT_PID=$!
echo "Vault server started with PID $VAULT_PID"
sleep 3

export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root'

# 2. Enable AppRole auth method
vault auth enable approle

# 3. Enable KV secrets engine at secret/
# vault secrets enable -path=secret kv-v2

# 4. Write the connection_string secret
vault kv put secret/app/config connection_string="Server=db.example.com;Database=prod;User Id=app;Password=secret;"

# 5. Enable PKI secrets engine at pki/
vault secrets enable pki
vault secrets tune -max-lease-ttl=87600h pki

# 6. Generate root CA and configure URLs
vault write -field=certificate pki/root/generate/internal \
    common_name="example.com" ttl=87600h > CA_cert.crt

vault write pki/config/urls \
    issuing_certificates="$VAULT_ADDR/v1/pki/ca" \
    crl_distribution_points="$VAULT_ADDR/v1/pki/crl"

# 7. Create a PKI role for app-cert
vault write pki/roles/app-cert \
    allowed_domains="app.example.com" \
    allow_subdomains=true \
    allow_bare_domains=true \
    max_ttl="72h"

# 8. Create a policy for the agent
cat > agent-policy.hcl <<EOF
path "secret/data/app/config" {
  capabilities = ["read"]
}

path "pki/issue/app-cert" {
  capabilities = ["update"]
}
EOF

vault policy write agent-policy agent-policy.hcl

# 9. Create an AppRole with the policy
vault write auth/approle/role/agent-role \
    token_policies="agent-policy" \
    secret_id_ttl=60m \
    token_ttl=60m \
    token_max_ttl=120m

# 10. Fetch RoleID and SecretID for the agent
ROLE_ID=$(vault read -field=role_id auth/approle/role/agent-role/role-id)
SECRET_ID=$(vault write -field=secret_id -f auth/approle/role/agent-role/secret-id)

echo "AppRole RoleID: $ROLE_ID"
echo "AppRole SecretID: $SECRET_ID"

# 11. Save RoleID and SecretID to files for Vault Agent
echo "$ROLE_ID" > /etc/vault/role_id
echo "$SECRET_ID" > /etc/vault/secret_id

echo "Vault setup complete. Vault Agent can now authenticate and retrieve secrets."
echo "To stop the Vault server, run: kill $VAULT_PID"
