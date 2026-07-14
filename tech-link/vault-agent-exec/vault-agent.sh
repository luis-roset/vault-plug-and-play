export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root'

# 1. Make sure the secret id is in place when starting the Agent 
SECRET_ID=$(vault write -field=secret_id -f auth/approle/role/agent-role/secret-id)
echo "AppRole SecretID: $SECRET_ID"
echo "$SECRET_ID" > /etc/vault/secret_id

# 2. Start the agent in the background 
vault agent -config="config/vault-agent-config.hcl" > logs/vault-agent.log 2>&1 &
