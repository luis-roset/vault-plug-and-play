# Vault Enterprise — Plug and Play

A zero-friction deployment kit for **Vault Enterprise** using Podman. Run one script and get a fully initialized, TLS-enabled Vault environment in minutes — single node or two-node with Performance Replication.

---

## Table of Contents

1. [Overview](#overview)
2. [Repository Layout](#repository-layout)
3. [Prerequisites](#prerequisites)
4. [Quick Start](#quick-start)
5. [Topology Options](#topology-options)
6. [How It Works](#how-it-works)
7. [Ports Reference](#ports-reference)
8. [Teardown](#teardown)
9. [Use Cases](#use-cases)
   - [AI Integration — Native AI Agent Support](#use-case-1--ai-integration--native-ai-agent-support)
10. [Troubleshooting](#troubleshooting)
11. [Resources](#resources)

---

## Overview

`vault-plug-and-play` automates the full Vault Enterprise bootstrap lifecycle:

| Phase | What happens |
|---|---|
| **TLS** | Self-signed CA and per-node certificates are generated automatically |
| **Containers** | Vault Enterprise containers are pulled and started via Podman |
| **Init & Unseal** | Each node is initialized (1 key share / threshold 1) and unsealed |
| **Replication** | Performance Replication is activated between node1 and node2 (2-node only) |

Everything is local — no cloud account, no Kubernetes, no external dependencies beyond Podman and a valid Vault Enterprise license.

---

## Repository Layout

```
vault-plug-and-play/
├── deploy.sh               # Interactive deployment entry point
├── teardown.sh             # Full cleanup (containers, network, data, TLS)
├── config/
│   ├── vault-single.hcl   # Raft config for single-node mode
│   ├── vault-node1.hcl    # Raft config for node1 (primary, 2-node mode)
│   └── vault-node2.hcl    # Raft config for node2 (secondary, 2-node mode)
├── scripts/
│   ├── gen-certs.sh        # CA + per-node TLS certificate generation
│   ├── init-vault.sh       # Vault init + unseal automation
│   └── setup-replication.sh# Performance Replication setup (2-node only)
├── tls/                    # Generated at deploy time — do not commit
└── data/                   # Raft data + init.json credentials — do not commit
```

---

## Prerequisites

| Requirement | Notes |
|---|---|
| **Podman** | v4+ recommended; `podman` must be in `PATH` |
| **curl**, **jq**, **openssl** | Standard utilities used by the scripts |
| **vault CLI** | For manual operations after deployment |
| **Vault Enterprise license** | Set `VAULT_LICENSE` in `.env` or provide interactively |
| **Vault Enterprise 2.0.3+** | Required for AI Agent features (Use Case 1) |

### License setup (recommended)

Create a `.env` file in the repo root before running `deploy.sh`:

```bash
VAULT_LICENSE="<your-license-string>"
```

The script will also accept a file path or an inline paste if `.env` is absent.

---

## Quick Start

```bash
# Clone or download the repo, then:
./deploy.sh
```

`deploy.sh` is interactive — it will prompt for:

1. **Vault Enterprise version** (e.g. `2.0.3`, `latest`)
2. **Number of nodes** (`1` for single-node, `2` for Performance Replication)
3. **License** (if not already in `.env`)

After the script completes, Vault is initialized, unsealed, and ready.

```
  Node 1 API:  https://localhost:8200
  Node 1 UI:   https://localhost:8200/ui
  CA cert:     tls/ca.crt          ← trust this in your browser/CLI
  Credentials: data/vault-node1/init.json
```

Point the Vault CLI at node1:

```bash
export VAULT_ADDR="https://localhost:8200"
export VAULT_CACERT="tls/ca.crt"
export VAULT_TOKEN="$(jq -r '.root_token' data/vault-node1/init.json)"

vault status
```

---

## Topology Options

### Single node (`NODE_COUNT=1`)

One container (`vault-node1`) running a Raft single-node cluster. Good for development, demos, and feature testing.

```
vault-node1  →  localhost:8200  (API / UI)
             →  localhost:8201  (Raft cluster port)
```

### Two nodes (`NODE_COUNT=2`)

Two containers connected via Vault **Performance Replication**. Policies, auth methods, and secrets engines created on node1 replicate automatically to node2.

```
vault-node1 (primary)    →  localhost:8200 / 8201
vault-node2 (secondary)  →  localhost:8202 / 8203
```

---

## How It Works

`deploy.sh` orchestrates the following steps in order:

### Step 1 — TLS generation (`scripts/gen-certs.sh`)

A local CA (`tls/ca.crt` / `tls/ca.key`) is created once and reused on subsequent runs. Per-node certificates are signed by this CA with SANs covering both the container hostname and `localhost`, so the same cert works for internal Podman DNS and host-side CLI access.

```
tls/
├── ca.crt                 shared CA
├── vault-node1/
│   ├── ca.crt             CA copy (mounted into container at /vault/tls/)
│   ├── vault.crt          node server cert
│   └── vault.key          node private key
└── vault-node2/           (2-node only)
```

### Step 2 — Container deployment

Each node is started with `podman run`:

```bash
podman run -d \
  --name vault-node1 \
  --network vault-network \
  --hostname vault-node1 \
  --cap-add IPC_LOCK \
  -e VAULT_LICENSE="..." \
  -v config/vault-single.hcl:/vault/config/vault.hcl:ro \
  -v data/vault-node1:/vault/data \
  -v tls/vault-node1:/vault/tls:ro \
  -p 8200:8200 -p 8201:8201 \
  hashicorp/vault-enterprise:<version> \
  vault server -config=/vault/config/vault.hcl
```

All nodes share the `vault-network` Podman network. Container hostnames (`vault-node1`, `vault-node2`) are used for Raft peer discovery and replication addresses.

### Step 3 — Init and unseal (`scripts/init-vault.sh`)

The script polls `GET /v1/sys/health` until Vault responds, then:

1. Calls `PUT /v1/sys/init` with 1 key share / threshold 1
2. Saves the response (unseal key + root token) to `data/<node>/init.json`
3. Calls `PUT /v1/sys/unseal`

On re-runs, if a node is already initialized but sealed, it reads the existing `init.json` and unseals automatically.

> **Production note:** Use `secret_shares=5, secret_threshold=3` and distribute keys via PGP. The 1/1 split is for local use only.

### Step 4 — Performance Replication (`scripts/setup-replication.sh`, 2-node only)

1. Enables replication on node1 as primary
2. Generates a wrapped secondary activation token
3. Activates replication on node2 using that token
4. Verifies the replication state on both nodes

---

## Ports Reference

| Container | Host API port | Host cluster port | TLS |
|---|---|---|---|
| `vault-node1` | `8200` | `8201` | Yes |
| `vault-node2` | `8202` | `8203` | Yes (2-node only) |

```bash
# Target node1
export VAULT_ADDR="https://localhost:8200"
export VAULT_CACERT="tls/ca.crt"

# Target node2 (2-node setup)
export VAULT_ADDR="https://localhost:8202"
export VAULT_CACERT="tls/ca.crt"
```

---

## Teardown

```bash
./teardown.sh
```

This removes all containers, the `vault-network` Podman network, and the `data/` directory. TLS certificates are **not** removed — delete `tls/` manually if you want to regenerate them on the next run.

---

## Use Cases

### Use Case 1 — AI Integration: Native AI Agent Support

Vault Enterprise 2.0.3 introduces **Native AI Agent Support** — a built-in mechanism to enroll, govern, and authenticate AI agents without requiring them to perform a traditional Vault login. This use case walks through configuring it on top of this plug-and-play environment.

#### How it works

```
AI Agent (JWT access token from its identity provider)
      │
      ▼  Authorization: Bearer <jwt>
Vault matches JWT issuer to an OAuth Resource Server Profile
      │
      ▼
JWT signature and claims validated (audience, expiry, algorithms)
      │
      ▼
user_claim resolved to a Vault Identity Entity
      │
      ▼
Entity checked against Agent Registry
      │
      ▼
Authorization evaluated — baseline policies ∩ ceiling policies
      │
      (optional) authorization_details claim enforces path-level RAR constraints
```

Two components power this flow:

| Component | Purpose |
|---|---|
| **OAuth Resource Server** | Validates externally-issued JWTs — no `vault login` needed |
| **Agent Registry** | Enrolls, governs, and audits registered agentic identities |

All steps below target **node1** (`https://localhost:8200`). Set your environment first:

```bash
export VAULT_ADDR="https://localhost:8200"
export VAULT_CACERT="tls/ca.crt"
export VAULT_TOKEN="$(jq -r '.root_token' data/vault-node1/init.json)"
```

---

#### Step 1 — Activate the OAuth Resource Server feature

This is a **one-time, irreversible** activation per namespace.

```bash
vault write -f sys/activation-flags/oauth-resource-server/activate
```

Verify:

```bash
vault read sys/activation-flags/oauth-resource-server
```

Expected output:
```
Key        Value
---        -----
activated  true
```

> **Note:** Once activated, the namespace is permanently enabled. This cannot be undone.

---

#### Step 2 — Create an OAuth Resource Server Profile

A profile defines how Vault validates JWTs from a specific identity provider. Create one profile per issuer.

**Option A — JWKS endpoint (recommended for production)**

Vault fetches public keys automatically from the issuer's JWKS URI.

```bash
vault write sys/config/oauth-resource-server/my-ai-platform \
  issuer_id="https://my-ai-platform.example.com" \
  use_jwks=true \
  jwks_uri="https://my-ai-platform.example.com/.well-known/jwks" \
  audiences="https://vault-node1:8200" \
  supported_algorithms="RS256"
```

**Option B — Static public keys (for local/dev environments)**

Use when the issuer does not expose a JWKS endpoint. Provide one or more PEM keys as a JSON payload.

```bash
curl --request POST \
  --cacert tls/ca.crt \
  --header "X-Vault-Token: $VAULT_TOKEN" \
  --header "Content-Type: application/json" \
  --url "https://localhost:8200/v1/sys/config/oauth-resource-server/my-ai-platform" \
  --data '{
    "issuer_id": "https://my-ai-platform.example.com",
    "use_jwks": false,
    "public_keys": [
      {
        "key_id": "key-2026-01",
        "pem": "-----BEGIN PUBLIC KEY-----\n<base64-encoded-key>\n-----END PUBLIC KEY-----"
      }
    ],
    "audiences": ["https://vault-node1:8200"],
    "supported_algorithms": ["RS256"]
  }'
```

**List and read profiles**

```bash
vault list sys/config/oauth-resource-server
vault read sys/config/oauth-resource-server/my-ai-platform
```

**Profile parameters reference**

| Parameter | Type | Default | Description |
|---|---|---|---|
| `issuer_id` | string | required | The `iss` claim value Vault validates against. Must be unique per namespace. Vault normalizes it (trims trailing slashes, lowercases). |
| `use_jwks` | bool | required | `true` = fetch keys from `jwks_uri`; `false` = use `public_keys` list |
| `jwks_uri` | string | — | JWKS endpoint URL (required when `use_jwks=true`) |
| `jwks_ca_pem` | string | — | PEM certificate to validate TLS for the JWKS endpoint |
| `public_keys` | list | — | Array of `{key_id, pem}` objects (required when `use_jwks=false`) |
| `audiences` | list | — | Accepted `aud` claim values. JWTs without a matching audience are rejected. |
| `user_claim` | string | `sub` | JWT claim used to identify the agent's Vault Identity Entity |
| `supported_algorithms` | list | all asymmetric | Signing algorithms to accept (e.g. `RS256`, `ES256`). HMAC algorithms are not supported. |
| `jwt_type` | string | `access_token` | Expected JWT type: `access_token` or `transaction_token` |
| `clock_skew_leeway` | integer | `0` | Seconds of leeway for `exp`, `iat`, and `nbf` claim validation |
| `optional_authorization_details` | bool | `false` | When `false` (default), JWTs must include an `authorization_details` claim (RAR). Set to `true` to allow JWTs without it. |
| `no_default_policy` | bool | `false` | When `true`, the `default` policy is not attached to tokens issued via this profile |
| `enabled` | bool | `true` | Set to `false` to disable the profile without deleting it |

> Switching between `use_jwks=true` and `use_jwks=false` automatically clears the fields of the previous mode.

---

#### Step 3 — Configure Agent Policies

AI agents operate under two policy layers:

1. **Baseline policy** — what the agent's Vault identity is allowed to do
2. **Ceiling policy** — the upper bound of permissions that can ever be delegated to the agent (ceiling ⊆ baseline)

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

```hcl
# agent-ceiling.hcl
path "secret/data/ai-agents/readonly/*" {
  capabilities = ["read"]
}
```

```bash
vault policy write agent-ceiling agent-ceiling.hcl
```

Create a Vault Identity Entity for the agent:

```bash
vault write identity/entity \
  name="my-ai-agent" \
  policies="agent-baseline"
```

Note the `id` returned — you will need it in the next step.

---

#### Step 4 — Register the AI Agent

```bash
vault write agent-registry/agents \
  name="my-ai-agent" \
  entity_id="<entity-id-from-previous-step>" \
  description="Primary AI agent for data retrieval tasks" \
  ceiling_policies="agent-ceiling"
```

Verify the registration:

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
```

---

#### Step 5 — Agent Authentication

The agent obtains a JWT from its identity provider and presents it directly to any Vault API endpoint using the standard `Authorization` header. Vault matches the `iss` claim to the configured profile, validates the JWT, and enforces the agent's policies.

```bash
curl --cacert tls/ca.crt \
  --header "Authorization: Bearer <agent-jwt>" \
  --url "https://localhost:8200/v1/secret/data/ai-agents/config"
```

No `vault login` step is required. Vault resolves the JWT to the agent's Identity Entity, checks the Agent Registry, and applies baseline + ceiling policies for that request.

---

#### Step 6 — Rich Authorization Requests (RAR)

RAR embeds fine-grained path and capability constraints directly inside the JWT via an `authorization_details` claim. Vault enforces these on top of the agent's existing policies — the effective permission is the intersection of all three layers.

By default, `optional_authorization_details=false` on the profile, meaning every JWT **must** include an `authorization_details` claim.

**Example JWT payload with RAR**

```json
{
  "sub": "my-ai-agent",
  "iss": "https://my-ai-platform.example.com",
  "aud": "https://vault-node1:8200",
  "exp": 1752624000,
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

**Make RAR optional for a profile**

Set `optional_authorization_details=true` to allow JWTs that omit the claim:

```bash
vault write sys/config/oauth-resource-server/my-ai-platform \
  optional_authorization_details=true
```

**Disable a profile without deleting it**

```bash
vault write sys/config/oauth-resource-server/my-ai-platform \
  enabled=false
```

---

## Troubleshooting

### Container fails to start

```bash
podman logs vault-node1
```

Common causes: port already in use, license not loaded, data directory permissions.

### "Feature not activated" error

```
Error: oauth-resource-server feature is not activated
```

Run: `vault write -f sys/activation-flags/oauth-resource-server/activate`

### JWT signature validation failure

- Verify `issuer_id` in the profile exactly matches the `iss` claim in the JWT (Vault normalizes both by trimming trailing slashes and lowercasing)
- Confirm the `jwks_uri` endpoint is reachable from inside the Vault container (`podman exec vault-node1 curl <jwks_uri>`)
- Ensure the JWT signing algorithm is listed in `supported_algorithms` — HMAC algorithms are never accepted
- Check `clock_skew_leeway` if tokens are rejected due to timing (`exp`/`nbf` validation)

### Agent not found in registry

```
Error: no agent registry record found for entity
```

- Confirm the `entity_id` in `agent-registry/agents/<name>` matches the entity resolved from the JWT `user_claim`
- Run `vault read identity/entity/name/<entity-name>` to verify

### TLS errors from CLI

Always pass the CA cert:

```bash
export VAULT_CACERT="tls/ca.crt"
```

Or per command: `vault status --tls-skip-verify` (dev only — do not use in production).

### Ceiling policy error

The ceiling cannot grant more than the baseline allows. Check both:

```bash
vault read agent-registry/agents/my-ai-agent   # ceiling_policies
vault read identity/entity/name/my-ai-agent     # policies (baseline)
```

### Replication not syncing (2-node)

```bash
vault read sys/replication/performance/status
podman logs vault-node2
```

The secondary may briefly restart during activation — wait 15–20 seconds after `deploy.sh` completes.

---

## Resources

- [Vault Native AI Agent Support — Official Docs](https://developer.hashicorp.com/vault/docs/concepts/native-ai-agent-support)
- [Agent Registry API](https://developer.hashicorp.com/vault/api-docs/agent-registry)
- [OAuth Resource Server API](https://developer.hashicorp.com/vault/api-docs/system/config-oauth-resource-server)
- [Vault Enterprise Performance Replication](https://developer.hashicorp.com/vault/docs/enterprise/replication)
- [Vault Enterprise Licensing](https://developer.hashicorp.com/vault/docs/enterprise/license)
