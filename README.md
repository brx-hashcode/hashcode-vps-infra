# hashcode-infra

Shared deployment infrastructure for the brx-hashcode organization, managed with Docker Compose and Traefik. Runs on a single VPS and routes traffic to any project deployed on the same server.

## Stack

| Service  | Image           | URL                              |
|----------|-----------------|----------------------------------|
| Traefik  | traefik:v3      | :80 / :443 (reverse proxy + TLS) |
| Postgres | postgres:16     | internal only                    |
| Redis    | redis:7         | internal only                    |
| Qdrant   | qdrant/qdrant   | `qdrant.hashcode.org`            |
| Grafana  | grafana/grafana | `grafana.hashcode.org`           |

TLS certificates are provisioned automatically via Let's Encrypt (HTTP challenge).

---

## Compose File Structure

The stack uses three compose files to separate concerns:

| File                        | Purpose                                      |
|-----------------------------|----------------------------------------------|
| `docker-compose.yml`        | Base — services, networks, volumes (no TLS)  |
| `docker-compose.prod.yml`   | Production overlay — adds TLS, HTTPS redirect, Let's Encrypt, Linux socket |
| `docker-compose.override.yml` | Local override — HTTP only, Docker Desktop (Windows), auto-loaded |

---

## Domain Strategy

This infra repo owns the **`hashcode.org`** domain for shared tooling.
Each project is deployed under its own domain with environment-based subdomains.

### Example — project `rabotka`

| Environment | Frontend         | Backend              |
|-------------|------------------|----------------------|
| Production  | `rabotka.co`     | `api.rabotka.co`     |
| Integration | `int-rabotka.co` | `int-api.rabotka.co` |
| Dev         | `dev-rabotka.co` | `dev-api.rabotka.co` |

All domains (infra + project) must have **DNS A records → this VPS's IP**.
Traefik issues a separate TLS cert per domain automatically.

### How app repos plug in

Each app's `docker-compose.yml` joins the shared networks and declares its route via Traefik labels:

```yaml
# example: rabotka-backend (prod)
networks:
  rabotka-public:
    external: true      # shared Traefik network
  rabotka-internal:
    external: true      # shared DB/Redis network

services:
  api:
    image: ghcr.io/brx-hashcode/rabotka-backend:latest
    networks:
      - rabotka-public
      - rabotka-internal
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=rabotka-public"
      - "traefik.http.routers.rabotka-api-prod.rule=Host(`api.rabotka.co`)"
      - "traefik.http.routers.rabotka-api-prod.entrypoints=websecure"
      - "traefik.http.routers.rabotka-api-prod.tls.certresolver=letsencrypt"
      - "traefik.http.services.rabotka-api-prod.loadbalancer.server.port=<app-port>"
```

> **Important:**
> - `traefik.docker.network=rabotka-public` is required when a container is on multiple networks — without it, Traefik may pick the wrong network IP and return 504.
> - `loadbalancer.server.port` must match the port your app listens on inside the container.
> - Router names (e.g. `rabotka-api-prod`) must be **unique** across all containers on the server.

---

## Prerequisites

- Docker + Docker Compose v2
- A server with ports 80 and 443 open
- DNS A records for all infra subdomains pointing to the VPS:
  - `qdrant.hashcode.org`
  - `grafana.hashcode.org`

---

## Setup

**1. Clone the repo**

```bash
git clone https://github.com/brx-hashcode/hashcode-vps-infra.git ~/hashcode-infra
cd ~/hashcode-infra
```

**2. Run the bootstrap script**

```bash
./scripts/setup.sh
```

This will:
- Copy `.env.example` → `.env` (if it doesn't exist yet)
- Create the `data/` directories for persistent volumes
- Create `traefik/acme.json` with the required `600` permissions

**3. Fill in `.env`**

```bash
INFRA_DOMAIN=hashcode.org
EMAIL=admin@hashcode.org

POSTGRES_USER=rabotka
POSTGRES_PASSWORD=<strong-password>

REDIS_PASSWORD=<strong-password>
```

> For **VPS + CI/CD** deployments: the workflow will **render `.env` from Vault** on the VPS, so the values you put here are mostly useful for **local/manual runs**.

**4. Start the stack**

```bash
# Production (VPS — Linux)
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# Local (Docker Desktop — Windows/macOS)
docker compose up -d
# docker-compose.override.yml is picked up automatically
```

---

## Directory Structure

```
hashcode-vps-infra/
├── docker-compose.yml          # Base service definitions (no TLS)
├── docker-compose.prod.yml     # Production overlay (TLS + Let's Encrypt)
├── docker-compose.override.yml # Local override — gitignored, auto-loaded
├── .env.example                # Environment variable template
├── .gitignore
├── traefik/
│   └── acme.json               # Let's Encrypt certificate storage (gitignored)
├── data/                       # Persistent volume data (gitignored)
│   ├── postgres/
│   ├── redis/
│   ├── qdrant/
│   └── grafana/
└── scripts/
    └── setup.sh                # One-time server bootstrap
```

---

## Networking

| Network            | Purpose                                                     |
|--------------------|-------------------------------------------------------------|
| `rabotka-public`   | Traefik + any container that needs an external URL          |
| `rabotka-internal` | Postgres, Redis — only containers that need DB/cache access |

> When a container is on both networks, always set `traefik.docker.network=rabotka-public` in its labels so Traefik routes through the correct interface.

---

## Local Development

The `docker-compose.override.yml` is auto-loaded by Docker Compose and replaces all production settings for local use:

- No TLS or Let's Encrypt
- Uses `//var/run/docker.sock` (Docker Desktop on Windows)
- Exposes Traefik dashboard at `http://localhost:8080`
- Services available at:

| Service | Local URL                  |
|---------|----------------------------|
| Grafana | http://grafana.localhost   |
| Qdrant  | http://qdrant.localhost    |
| Traefik | http://localhost:8080      |

> `*.localhost` subdomains resolve to `127.0.0.1` natively — no `/etc/hosts` edits needed.

```bash
docker compose up -d
```

---

## Common Commands

```bash
# Start (local)
docker compose up -d

# Start (production)
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# View logs
docker compose logs -f

# Restart a single service
docker compose restart grafana

# Stop everything
docker compose down

# Stop and remove volumes (destructive)
docker compose down -v
```

## Updating Services

```bash
# Production
docker compose -f docker-compose.yml -f docker-compose.prod.yml pull
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

---

## CI/CD — Automatic Deployment

The workflow at [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml) triggers on **pull requests targeting `main` or `develop`**.

It SSHs into the VPS, uses **GitHub Actions OIDC** to authenticate to **Vault**, renders the VPS `.env` from **Vault KV v2**, then redeploys the stack using the production overlay.

```
PR opened/updated → GitHub Actions (OIDC token) → SSH into VPS → git pull → Vault render `.env` → docker compose (prod) up -d
```

### One-time Vault setup (run on the VPS)

1. Start the Vault container (if not running):

```bash
docker compose -f docker-compose.yml up -d vault
```

2. Bootstrap **GitHub JWT auth** + **KV v2** for infra deploys:

```bash
cd ~/hashcode-infra

VAULT_TOKEN='<admin-token>' \
GITHUB_REPOSITORY='owner/repo' \
bash ./scripts/vault-bootstrap-github-jwt-kv.sh
```

Where:
- `VAULT_TOKEN` is a token with admin rights (used only during bootstrap).
- `GITHUB_REPOSITORY` is the exact repo that runs the workflow (format: `owner/repo`).
- The Vault role created by the bootstrap script is bound to that `owner/repo` via the GitHub JWT `repository` claim.
- The GitHub Actions workflow requests an OIDC token with audience `vault` (configured in the workflow).

3. Put infra secrets into Vault KV v2.

The workflow expects:
- Vault path: `secret/infra/prod`
- Fields: `INFRA_DOMAIN`, `EMAIL`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `REDIS_PASSWORD`, `GRAFANA_ADMIN_USER`, `GRAFANA_ADMIN_PASSWORD`

Example:

```bash
vault kv put secret/infra/prod \
  INFRA_DOMAIN='hashcode.org' \
  EMAIL='admin@hashcode.org' \
  POSTGRES_USER='rabotka' \
  POSTGRES_PASSWORD='...' \
  REDIS_PASSWORD='...' \
  GRAFANA_ADMIN_USER='admin' \
  GRAFANA_ADMIN_PASSWORD='...'
```

### Required GitHub Secrets

Go to **Settings → Secrets and variables → Actions** and add:

| Secret              | Description                            |
|---------------------|----------------------------------------|
| `VPS_HOST`          | VPS IP address or hostname             |
| `VPS_USER`          | SSH user (e.g. `ubuntu`, `root`)       |
| `VPS_SSH_KEY`       | Private SSH key (full PEM content)     |
| `VPS_PORT`          | SSH port (usually `22`)                |

Notes:
- No Vault credentials are stored as GitHub Secrets.
- The workflow requests a **GitHub OIDC token** and uses it to authenticate to Vault.
- The `.env` file is never stored in git — it is rendered on the VPS at deploy time from Vault.

### Branches

| Branch    | Trigger      |
|-----------|--------------|
| `main`    | PR → main    |
| `develop` | PR → develop |

### First-time VPS setup

Before the first automated deploy, SSH in manually and clone the repo:

```bash
git clone https://github.com/brx-hashcode/hashcode-vps-infra.git ~/hashcode-infra
cd ~/hashcode-infra
./scripts/setup.sh
```

After that, all subsequent deploys are handled automatically by the workflow.
