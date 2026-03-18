# Vault Setup Guide

Step-by-step guide to initialize, configure, and use HashiCorp Vault in this infra.

---

## Environments

| Environment | Context | Vault UI | Commands |
|---|---|---|---|
| **Local** | Docker Desktop, dev only | `http://vault.localhost` | `docker exec vault sh -c "VAULT_ADDR=http://127.0.0.1:8200 ..."` |
| **Production** | VPS (Linux), CI/CD managed | `https://vault.hashcode.org` | SSH into VPS first, same `docker exec` commands |

> In production, **never use the root token for day-to-day operations**. The root token is only for bootstrap. CI/CD authenticates via GitHub JWT (no stored credentials).

---

## Prerequisites

- Stack is running: `docker compose up -d` (local) or `docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d` (prod)
- Vault container is healthy: `docker ps --filter name=vault`
- Vault UI: `http://vault.localhost` (local) / `https://vault.hashcode.org` (prod)

---

## 1. Initialize Vault

Run **once** on a fresh Vault instance. This generates the unseal keys and root token.

```bash
docker exec vault sh -c "VAULT_ADDR=http://127.0.0.1:8200 vault operator init"
```

Output:
```
Unseal Key 1: <key-1>
Unseal Key 2: <key-2>
Unseal Key 3: <key-3>
Unseal Key 4: <key-4>
Unseal Key 5: <key-5>

Initial Root Token: hvs.XXXXXXXXXXXXXXXXXX
```

> **CRITICAL: Save all 5 unseal keys and the root token in a password manager immediately.**
> They are shown only once. If lost, all secrets are permanently locked.

---

## 2. Unseal Vault

Vault starts **sealed** after every restart. You need 3 of the 5 keys to unseal it.

Run this command **3 times**, entering a different unseal key each time:

```bash
docker exec -it vault sh -c "VAULT_ADDR=http://127.0.0.1:8200 vault operator unseal"
```

Verify it is unsealed:

```bash
docker exec vault sh -c "VAULT_ADDR=http://127.0.0.1:8200 vault status"
# Sealed: false  ← expected
```

> After a VPS reboot, you must unseal Vault again before any deploy can run.

---

## 3. Enable the KV v2 Secrets Engine

Run **once** after initialization.

```bash
docker exec vault sh -c \
  "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN='<root-token>' \
   vault secrets enable -path=secret kv-v2"
```

Or via UI: **Secrets Engines → Enable new engine → KV → Version 2 → path: `secret` → Enable**.

---

## 4. Store Secrets

### Convention

Secrets are stored at `secret/<project>/<environment>`:

| Path                   | Contents                            |
|------------------------|-------------------------------------|
| `secret/infra/prod`    | Infra secrets (Postgres, Redis, Grafana) |
| `secret/rabotka/prod`  | Rabotka app production secrets      |
| `secret/rabotka/dev`   | Rabotka app dev secrets             |
| `secret/hello-world`   | Example / test secret               |

### Write secrets (CLI)

```bash
# Infra secrets
docker exec vault sh -c \
  "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN='<root-token>' \
   vault kv put secret/infra/prod \
     INFRA_DOMAIN='hashcode.org' \
     EMAIL='admin@hashcode.org' \
     POSTGRES_USER='rabotka' \
     POSTGRES_PASSWORD='...' \
     REDIS_PASSWORD='...' \
     GRAFANA_ADMIN_USER='hashcode-admin' \
     GRAFANA_ADMIN_PASSWORD='...'"

# App secrets (example: rabotka)
docker exec vault sh -c \
  "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN='<root-token>' \
   vault kv put secret/rabotka/prod \
     DATABASE_URL='postgresql://rabotka:...@postgres:5432/rabotka_prod' \
     REDIS_URL='redis://:...@redis:6379/0' \
     SECRET_KEY='...' \
     JWT_SECRET='...'"
```

### Write secrets (UI)

**Secrets Engines → secret → Create secret** → fill in path + key/value pairs.

---

## 5. Read Secrets

### All fields at once

```bash
docker exec vault sh -c \
  "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN='<root-token>' \
   vault kv get secret/infra/prod"
```

### Single field

```bash
docker exec vault sh -c \
  "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN='<root-token>' \
   vault kv get -field=POSTGRES_PASSWORD secret/infra/prod"
```

### Via REST API

```bash
curl -s -H "X-Vault-Token: <root-token>" \
  http://localhost:8200/v1/secret/data/infra/prod | python -m json.tool
```

---

## 6. Production — First-Time VPS Setup

This is the exact order of operations when setting up Vault on the VPS for the first time.

### 6.1 SSH into the VPS and start the stack

```bash
ssh user@<vps-ip>
cd ~/hashcode-infra
./scripts/setup.sh
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d vault
```

### 6.2 Initialize Vault (run once on the VPS)

```bash
docker exec vault sh -c "VAULT_ADDR=http://127.0.0.1:8200 vault operator init"
```

**Save the 5 unseal keys and root token in your password manager immediately.**

### 6.3 Unseal Vault (run after every VPS reboot)

```bash
# Run 3 times with 3 different unseal keys
docker exec -it vault sh -c "VAULT_ADDR=http://127.0.0.1:8200 vault operator unseal"
```

### 6.4 Enable KV v2 (run once)

```bash
docker exec vault sh -c \
  "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN='<root-token>' \
   vault secrets enable -path=secret kv-v2"
```

### 6.5 Store production secrets

```bash
docker exec vault sh -c \
  "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN='<root-token>' \
   vault kv put secret/infra/prod \
     INFRA_DOMAIN='hashcode.org' \
     EMAIL='admin@hashcode.org' \
     POSTGRES_USER='rabotka' \
     POSTGRES_PASSWORD='<strong-password>' \
     REDIS_PASSWORD='<strong-password>' \
     GRAFANA_ADMIN_USER='hashcode-admin' \
     GRAFANA_ADMIN_PASSWORD='<strong-password>'"
```

### 6.6 Bootstrap GitHub JWT auth (run once)

```bash
VAULT_TOKEN='<root-token>' \
GITHUB_REPOSITORY='brx-hashcode/hashcode-infra' \
bash ./scripts/vault-bootstrap-github-jwt-kv.sh
```

### 6.7 Add required GitHub Secrets

Go to **GitHub → repo → Settings → Secrets and variables → Actions**:

| Secret | Value |
|---|---|
| `VPS_HOST` | VPS IP or hostname |
| `VPS_USER` | SSH user (e.g. `ubuntu`) |
| `VPS_SSH_KEY` | Full private SSH key (PEM) |
| `VPS_PORT` | SSH port (usually `22`) |

> No Vault credentials go into GitHub Secrets — auth is handled via OIDC JWT.

### 6.8 Start the full prod stack

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

From this point on, **every deploy is automated** — opening a PR against `main` triggers the workflow which renders `.env` from Vault and redeploys.

---

## 7. Production — Adding Secrets for a New App

Each app has its own path in Vault. The app's deploy workflow renders its own `.env` from that path.

```bash
# SSH into VPS, then:
docker exec vault sh -c \
  "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN='<root-token>' \
   vault kv put secret/rabotka/prod \
     DATABASE_URL='postgresql://rabotka:<password>@postgres:5432/rabotka_prod' \
     REDIS_URL='redis://:<password>@redis:6379/0' \
     SECRET_KEY='<strong-secret>' \
     JWT_SECRET='<strong-secret>'"
```

Then create a `render-<app>-env-from-vault.sh` script in the app's repo (same pattern as `render-infra-env-from-vault.sh`) that reads from `secret/<app>/prod`.

---

## 8. Production — Vault After a VPS Reboot

Vault is **always sealed after a reboot**. The deploy workflow will fail until you unseal it manually.

```bash
ssh user@<vps-ip>

# Check if sealed
docker exec vault sh -c "VAULT_ADDR=http://127.0.0.1:8200 vault status" | grep Sealed

# Unseal (run 3 times with 3 different keys)
docker exec -it vault sh -c "VAULT_ADDR=http://127.0.0.1:8200 vault operator unseal"
```

> **Automate this?** You can configure Vault auto-unseal using a cloud KMS (AWS KMS, GCP Cloud KMS). This means Vault unseals itself on restart without manual intervention. Ask for the auto-unseal setup guide if needed.

---

## 9. Bootstrap GitHub Actions JWT Auth

Allows GitHub Actions workflows to authenticate to Vault without storing any credentials in GitHub Secrets.

Run **once** on the VPS:

```bash
VAULT_TOKEN='<root-token>' \
GITHUB_REPOSITORY='brx-hashcode/hashcode-infra' \
bash ./scripts/vault-bootstrap-github-jwt-kv.sh
```

This creates:
- JWT auth method at `auth/jwt` bound to `https://token.actions.githubusercontent.com`
- Policy `infra-deployer` — read-only access to `secret/data/infra/*`
- JWT role `infra-deployer` — bound to your GitHub repository

---

## 10. How CI/CD Uses Vault

The deploy workflow in `.github/workflows/deploy.yml`:

1. Requests a GitHub OIDC token (audience: `vault`)
2. SSHs into the VPS
3. Calls `render-infra-env-from-vault.sh prod .env` which:
   - Exchanges the OIDC token for a short-lived Vault token (TTL: 10 min)
   - Reads all fields from `secret/infra/prod`
   - Writes `.env` on the VPS (`chmod 600`)
4. Runs `docker compose up -d` with the production overlay

The `.env` file is **never committed to git**.

---

## 11. Recover a Lost Root Token

If you lose the root token but still have 3 unseal keys:

```bash
# Step 1 — start root token generation
docker exec -it vault sh -c "VAULT_ADDR=http://127.0.0.1:8200 vault operator generate-root -init"

# Step 2 — provide 3 unseal keys (run 3 times)
docker exec -it vault sh -c "VAULT_ADDR=http://127.0.0.1:8200 vault operator generate-root"

# Step 3 — decode the generated token with the OTP from step 1
docker exec vault sh -c \
  "VAULT_ADDR=http://127.0.0.1:8200 vault operator generate-root \
   -decode='<encoded-token>' -otp='<otp>'"
```

---

## Quick Reference

| Task | Command |
|---|---|
| Check status | `docker exec vault sh -c "VAULT_ADDR=http://127.0.0.1:8200 vault status"` |
| Unseal | `docker exec -it vault sh -c "VAULT_ADDR=http://127.0.0.1:8200 vault operator unseal"` |
| List secrets | `docker exec vault sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN='...' vault kv list secret/"` |
| Get all fields | `docker exec vault sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN='...' vault kv get secret/<path>"` |
| Get one field | `docker exec vault sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN='...' vault kv get -field=KEY secret/<path>"` |
| Put / update | `docker exec vault sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN='...' vault kv put secret/<path> KEY=value"` |
| Delete secret | `docker exec vault sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN='...' vault kv delete secret/<path>"` |
| Open UI | http://vault.localhost |
