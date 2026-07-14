# HashiCorp Vault 2.0.3 — Native AI Agent Support Guide

A step-by-step guide to configure **Native AI Agent Support** in Vault Enterprise 2.0.3 using the setup in this repository: a 3-node Raft cluster with TLS (`server1`, `server2`, `server3`) plus a standalone MCP server instance.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [How the Setup Works](#how-the-setup-works)
5. [Step 1 — Start the Environment](#step-1--start-the-environment)
6. [Step 2 — Initialize and Unseal the Cluster](#step-2--initialize-and-unseal-the-cluster)
7. [Step 3 — Activate the OAuth Resource Server Feature](#step-3--activate-the-oauth-resource-server-feature)
8. [Step 4 — Create an OAuth Resource Server Profile](#step-4--create-an-oauth-resource-server-profile)
9. [Step 5 — Configure Agent Registry Policies](#step-5--configure-agent-registry-policies)
10. [Step 6 — Register an AI Agent](#step-6--register-an-ai-agent)
11. [Step 7 — Test Agent Authentication](#step-7--test-agent-authentication)
12. [Step 8 — Rich Authorization Requests (RAR)](#step-8--rich-authorization-requests-rar)
13. [Cluster Ports Reference](#cluster-ports-reference)
14. [Troubleshooting](#troubleshooting)

---

## Overview

Vault Enterprise 2.0.3 introduces **Native AI Agent Support** through two integrated components:

| Component | Purpose |
|---|---|
| **Agent Registry** | Enroll, govern, and audit agentic identities within Vault |
| **OAuth Resource Server** | Allow AI agents to authenticate using OAuth 2.0 JWT tokens — no separate Vault login required |

The flow works as follows:

```
AI Agent (JWT token)
      │
      ▼
Vault validates JWT via OAuth Resource Server Profile
      │
      ▼
Resolves to a Vault Identity Entity
      │
      ▼
Vault checks Agent Registry for a matching record
      │
      ▼
Authorization evaluated against baseline policies + delegation ceiling
```

---

## Architecture

This repository runs the following containers (see `tech-link/docker-compose.yaml`):

| Container | Role | Port (host) | TLS |
|---|---|---|---|
| `server1` | Raft leader (primary) | `8400` | Yes |
| `server2` | Raft peer | `8200` | Yes |
| `server3` | Raft peer | `8500` | Yes |
| `mcp-server` | Standalone MCP Vault | `8800` | No |
| `linux` | Client / testing node | `8700` | — |
| `ngrok` | External tunnel → server3 | — | — |

The Vault Raft cluster uses mutual TLS:

- **Cluster addr**: `https://server1:8201`
- **API addr**: `https://server1:8200`
- **TLS certs**: mounted at `/tls/` in each server container

The `mcp-server` is a separate standalone Vault instance (no TLS) used for MCP tool access.

---

## Prerequisites

- Docker and Docker Compose installed
- A valid **Vault Enterprise license** (`vault.hclic`) placed at `tech-link/configs/vault.hclic`
- TLS certificates generated and placed under `tech-link/tls/` (one set per server)
- `vault` CLI installed locally
- Vault Enterprise **2.0.3** or later

---

## How the Setup Works

**server1** (`tech-link/configs/server1.hcl`) is the primary node:

```hcl
ui            = true
cluster_addr  = "https://server1:8201"
api_addr      = "https://server1:8200"
disable_mlock = true

storage "raft" {
  path    = "/raft"
  node_id = "server1"
}

listener "tcp" {
  address            = "0.0.0.0:8200"
  tls_disable        = 0
  tls_cert_file      = "/tls/cert.pem"
  tls_key_file       = "/tls/key.pem"
  tls_client_ca_file = "/tls/ca.pem"
}

license_path = "/etc/vault.d/vault.hclic"
```

The **Vault Agent** (`tech-link/configs/agent/agent.hcl`) uses AppRole auth and points to `server1`:

```hcl
auto_auth {
  method "approle" {
    config = {
      role_id_file_path                = "/etc/vault.d/role"
      secret_id_file_path              = "/etc/vault.d/secret"
      remove_secret_id_file_after_reading = false
    }
  }
  sink "file" {
    config = { path = "/etc/vault.d/.vault-token" }
  }
}

vault {
  address = "https://server1:8200"
}
```

---

## Step 1 — Start the Environment

```bash
cd tech-link
docker compose up -d
```

Verify all containers are running:

```bash
docker compose ps
```

---

## Step 2 — Initialize and Unseal the Cluster

> Skip this if you already have an initialized cluster. Your init output is stored in `configs/init-1.txt/init.txt`.

**Initialize server1** (single key for dev simplicity, use 5/3 for production):

```bash
export VAULT_ADDR="https://127.0.0.1:8400"
export VAULT_CACERT="tech-link/tls/vault-ca.pem"

vault operator init -key-shares=1 -key-threshold=1
```

**Unseal server1**:

```bash
vault operator unseal <Unseal-Key-1>
```

**Join server2 and server3 to the Raft cluster**:

```bash
# From inside the server2 container
docker exec -it server2 vault operator raft join \
  -leader-ca-cert=@/tls/ca.pem \
  https://server1:8200

# From inside the server3 container
docker exec -it server3 vault operator raft join \
  -leader-ca-cert=@/tls/ca.pem \
  https://server1:8200
```

**Unseal server2 and server3** with the same unseal key.

**Login with root token**:

```bash
vault login <Initial-Root-Token>
```

---

## Step 3 — Activate the OAuth Resource Server Feature

This is a **one-time, irreversible** activation per namespace. Do this on `server1`.

```bash
export VAULT_ADDR="https://127.0.0.1:8400"
export VAULT_CACERT="tech-link/tls/vault-ca.pem"
export VAULT_TOKEN="<root-or-admin-token>"

vault write -f sys/activation-flags/oauth-resource-server/activate
```

Verify the activation:

```bash
vault read sys/activation-flags/oauth-resource-server
```

Expected output:
```
Key        Value
---        -----
activated  true
```

> **Note:** This action cannot be undone. Once activated, the namespace is permanently enabled for OAuth resource server functionality.

---

## Step 4 — Create an OAuth Resource Server Profile

An OAuth profile defines the trust relationship between Vault and your AI agent's identity provider (e.g., an external OAuth 2.0 server, your AI platform, or a custom issuer).

### Option A — JWKS (Recommended for production)

The issuer exposes a public JWKS endpoint that Vault fetches automatically.

```bash
vault write sys/config/oauth-resource-server/profiles/my-ai-platform \
  issuer="https://my-ai-platform.example.com" \
  jwks_url="https://my-ai-platform.example.com/.well-known/jwks.json" \
  allowed_audiences="https://server1:8200" \
  user_claim="sub"
```

### Option B — Static PEM keys

Use this when the issuer does not expose a JWKS endpoint (e.g., a local development environment).

```bash
vault write sys/config/oauth-resource-server/profiles/my-ai-platform \
  issuer="https://my-ai-platform.example.com" \
  jwt_validation_pubkeys=@/path/to/public-key.pem \
  allowed_audiences="https://server1:8200" \
  user_claim="sub"
```

### Profile parameters reference

| Parameter | Description |
|---|---|
| `issuer` | Unique URI identifying the OAuth 2.0 issuer (must be unique per namespace) |
| `jwks_url` | URL of the JWKS endpoint (JWKS mode) |
| `jwt_validation_pubkeys` | PEM-encoded public key(s) (static mode) |
| `allowed_audiences` | Accepted JWT `aud` claim values — typically your Vault API address |
| `user_claim` | JWT claim used to identify the agent's entity (commonly `sub`) |
| `allowed_algorithms` | Defaults to all supported asymmetric algorithms (see below) |

**Supported signing algorithms** (asymmetric only — HMAC is not supported):

| Family | Algorithms |
|---|---|
| RSA PKCS1 | RS256, RS384, RS512 |
| RSA PSS | PS256, PS384, PS512 |
| ECDSA | ES256, ES384, ES512 |

---

## Step 5 — Configure Agent Registry Policies

AI agents operate under **two policy layers**:

1. **Baseline policy** — what the agent's Vault identity is normally allowed to do
2. **Authorization ceiling** — the maximum permissions that can be delegated to the agent (ceiling ⊆ baseline)

### Create a baseline policy

```hcl
# agent-baseline.hcl
path "secret/data/ai-agents/*" {
  capabilities = ["read"]
}

path "database/creds/ai-role" {
  capabilities = ["read"]
}
```

```bash
vault policy write agent-baseline agent-baseline.hcl
```

### Create a ceiling policy

The ceiling restricts what the agent can further delegate. The `default-ceiling` policy is automatically included in all ceilings — it prevents agents from modifying their own governance constraints.

```hcl
# agent-ceiling.hcl
path "secret/data/ai-agents/readonly/*" {
  capabilities = ["read"]
}
```

```bash
vault policy write agent-ceiling agent-ceiling.hcl
```

### Create an Identity Entity for the agent

```bash
vault write identity/entity \
  name="my-ai-agent" \
  policies="agent-baseline"
```

Note the `id` returned — you will need it in the next step.

---

## Step 6 — Register an AI Agent

With the Identity Entity created, register it in the Agent Registry:

```bash
vault write agent-registry/agents \
  name="my-ai-agent" \
  entity_id="<entity-id-from-previous-step>" \
  description="Primary AI agent for data retrieval tasks" \
  ceiling_policies="agent-ceiling"
```

### Verify the registration

```bash
vault list agent-registry/agents
vault read agent-registry/agents/my-ai-agent
```

Expected output:
```
Key                  Value
---                  -----
name                 my-ai-agent
entity_id            <entity-id>
description          Primary AI agent for data retrieval tasks
ceiling_policies     [agent-ceiling default-ceiling]
created_time         2026-07-14T...
```

---

## Step 7 — Test Agent Authentication

When an AI agent makes a request, it presents a JWT token (obtained from its identity provider). Vault validates it against the configured OAuth profile.

### Simulate a token exchange

```bash
# The agent sends its JWT to Vault
vault write auth/token/lookup-self \
  -header "Authorization: Bearer <agent-jwt-token>"
```

Or using the OAuth token endpoint directly:

```bash
curl --request POST \
  --cacert tech-link/tls/vault-ca.pem \
  --url "https://127.0.0.1:8400/v1/sys/config/oauth-resource-server/token" \
  --header "Content-Type: application/json" \
  --data '{
    "jwt": "<agent-jwt-token>",
    "profile": "my-ai-platform"
  }'
```

A successful response returns a **Vault client token** scoped to the agent's baseline policy intersected with its ceiling.

### Using the Vault Agent (AppRole) alongside AI Agent support

Your existing `agent.hcl` uses AppRole for the Vault Agent process itself. For AI agents using OAuth JWTs, the flow is separate — the agent does **not** need to run `vault login`. It presents its JWT directly to Vault's OAuth endpoint and receives a scoped token.

```
Vault Agent (AppRole) ──▶ manages template rendering, token renewal
AI Agent (OAuth JWT)  ──▶ authenticates directly via OAuth Resource Server
```

---

## Step 8 — Rich Authorization Requests (RAR)

RAR allows an AI agent's JWT to encode **fine-grained path and capability constraints** inline. Vault enforces these on top of the agent's existing policies.

### RAR token claim format

Include an `authorization_details` claim in the JWT issued by your identity provider:

```json
{
  "sub": "my-ai-agent",
  "iss": "https://my-ai-platform.example.com",
  "aud": "https://server1:8200",
  "authorization_details": [
    {
      "type": "vault:path_access",
      "path": "secret/data/ai-agents/readonly/config",
      "capabilities": ["read"],
      "allowed_parameters": {
        "version": ["1"]
      }
    }
  ]
}
```

### RAR configuration options

RAR is **enabled by default**. You can control it at the profile level:

```bash
# Make RAR optional (agent can omit it)
vault write sys/config/oauth-resource-server/profiles/my-ai-platform \
  rar_required=false

# Require RAR for all tokens using this profile
vault write sys/config/oauth-resource-server/profiles/my-ai-platform \
  rar_required=true
```

Or override at the individual agent level:

```bash
vault write agent-registry/agents/my-ai-agent \
  rar_required=false
```

---

## Cluster Ports Reference

| Service | Host Port | Internal Port | Notes |
|---|---|---|---|
| server1 (Raft leader) | `8400` | `8200` | TLS enabled — primary target for AI agent config |
| server2 | `8200` | `8200` | TLS enabled |
| server3 | `8500` | `8200` | TLS enabled — exposed via ngrok |
| mcp-server | `8800` | `8200` | No TLS — MCP tool access only |

Set your environment variables accordingly:

```bash
# Targeting server1 (primary/leader)
export VAULT_ADDR="https://127.0.0.1:8400"
export VAULT_CACERT="tech-link/tls/vault-ca.pem"

# Targeting mcp-server
export VAULT_ADDR="http://127.0.0.1:8800"
```

---

## Troubleshooting

### "Feature not activated" error

```
Error: oauth-resource-server feature is not activated
```

Run: `vault write -f sys/activation-flags/oauth-resource-server/activate`

### JWT signature validation failure

- Verify the `issuer` in the profile exactly matches the `iss` claim in the JWT
- Confirm the JWKS endpoint is reachable from inside the Vault container
- Ensure the algorithm used to sign the JWT is in the supported list (no HMAC)

### Agent not found in registry

```
Error: no agent registry record found for entity
```

- Confirm the `entity_id` in `agent-registry/agents/<name>` matches the entity resolved from the JWT `user_claim`
- Run `vault read identity/entity/name/<entity-name>` to verify

### TLS handshake errors (server1/server2/server3)

- The CA cert is at `tech-link/tls/vault-ca.pem` — always pass it via `VAULT_CACERT` or `--cacert`
- Inside containers, it is mounted at `/tls/ca.pem`

### Ceiling policy more permissive than baseline

The ceiling cannot grant more than the baseline allows. If an agent receives fewer permissions than expected, check both:

```bash
vault read agent-registry/agents/my-ai-agent   # ceiling_policies
vault read identity/entity/name/my-ai-agent     # policies (baseline)
```

---

## Resources

- [Vault Native AI Agent Support — Official Docs](https://developer.hashicorp.com/vault/docs/concepts/native-ai-agent-support)
- [Agent Registry API](https://developer.hashicorp.com/vault/api-docs/agent-registry)
- [OAuth Resource Server API](https://developer.hashicorp.com/vault/api-docs/system/config-oauth-resource-server)
- [Vault Enterprise Licensing](https://developer.hashicorp.com/vault/docs/enterprise/license)
