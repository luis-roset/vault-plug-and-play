#!/usr/bin/env bash
set -euo pipefail

POLICY_NAME="admin-no-plaintext"

tmpfile="$(mktemp)"

cat > "$tmpfile" <<'EOF'
# Full admin access
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

EOF

vault namespace list -format=json \
  | jq -r '.data.keys[] | rtrimstr("/")' \
  | while read -r ns; do
    cat >> "$tmpfile" <<EOF
# Block plaintext KV v2 secret reads in ${ns}
path "${ns}/+/data/*" {
  capabilities = ["deny"]
}

# Allow KV v2 metadata browsing in ${ns}
path "${ns}/+/metadata/*" {
  capabilities = ["read", "list"]
}

EOF
  done

vault policy write "$POLICY_NAME" "$tmpfile"
rm "$tmpfile"