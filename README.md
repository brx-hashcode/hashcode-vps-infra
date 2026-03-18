# hashcode-infra

Shared deployment infrastructure for the brx-hashcode organization, managed with Docker Compose and Traefik. Runs on a single VPS and routes traffic to any project deployed on the same server.

## Stack


| Service   | Image               | URL                                |
| --------- | ------------------- | ---------------------------------- |
| Traefik   | traefik:v3          | `traefik.hashcode.org` (dashboard) |
| Postgres  | postgres:16         | internal only                      |
| Redis     | redis:7             | internal only                      |
| Qdrant    | qdrant/qdrant       | `qdrant.hashcode.org`              |
| Grafana   | grafana/grafana     | `grafana.hashcode.org`             |
| SonarQube | sonarqube:community | `sonar.hashcode.org`               |
| Vault     | hashicorp/vault     | `vault.hashcode.org`               |


TLS certificates are provisioned automatically via Let's Encrypt (HTTP challenge).

---

## Compose File Structure


| File                          | Purpose                                                           |
| ----------------------------- | ----------------------------------------------------------------- |
| `docker-compose.yml`          | Base — services, networks, volumes (no TLS)                       |
| `docker-compose.prod.yml`     | Production overlay — adds TLS, HTTPS redirect, Let's Encrypt      |
| `docker-compose.override.yml` | Local override — HTTP only, Docker Desktop (Windows), auto-loaded |


---

## Domain Strategy

This infra repo owns the `**hashcode.org**` domain for shared tooling.
Each project is deployed under its own domain with environment-based subdomains.

### Example — project `rabotka`


| Environment | Frontend         | Backend              |
| ----------- | ---------------- | -------------------- |
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
>
> - `traefik.docker.network=rabotka-public` is required when a container is on multiple networks — without it, Traefik may pick the wrong network IP and return 504.
> - `loadbalancer.server.port` must match the port your app listens on inside the container.
> - Router names (e.g. `rabotka-api-prod`) must be **unique** across all containers on the server.

---

## Prerequisites

- Docker + Docker Compose v2
- A server with ports 80 and 443 open
- DNS A records for all infra subdomains pointing to the VPS:
  - `traefik.hashcode.org`
  - `grafana.hashcode.org`
  - `qdrant.hashcode.org`
  - `sonar.hashcode.org`
  - `vault.hashcode.org`

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

GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=<strong-password>

SONARQUBE_DB_NAME=sonarqube

# Generate with: htpasswd -nb admin yourpassword
TRAEFIK_DASHBOARD_AUTH=admin:$apr1$...
```

**4. Create the SonarQube database (first time only)**

```bash
docker exec -it postgres psql -U $POSTGRES_USER -c "CREATE DATABASE sonarqube;"
```

**5. Start the stack**

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
hashcode-infra/
├── docker-compose.yml          # Base service definitions (no TLS)
├── docker-compose.prod.yml     # Production overlay (TLS + Let's Encrypt)
├── docker-compose.override.yml # Local override — gitignored, auto-loaded
├── .env.example                # Environment variable template
├── .gitignore
├── traefik/
│   └── acme.json               # Let's Encrypt certificate storage (gitignored)
├── vault/
│   └── config.hcl              # Vault server configuration
├── data/                       # Persistent volume data (gitignored)
│   ├── postgres/
│   ├── redis/
│   ├── qdrant/
│   ├── grafana/
│   ├── sonarqube/
│   └── vault/
└── scripts/
    └── setup.sh                # One-time server bootstrap
```

---

## Networking


| Network            | Purpose                                                     |
| ------------------ | ----------------------------------------------------------- |
| `rabotka-public`   | Traefik + any container that needs an external URL          |
| `rabotka-internal` | Postgres, Redis — only containers that need DB/cache access |


> When a container is on both networks, always set `traefik.docker.network=rabotka-public` in its labels so Traefik routes through the correct interface.

---

## Local Development

The `docker-compose.override.yml` is auto-loaded by Docker Compose and replaces all production settings for local use:

- No TLS or Let's Encrypt
- Uses `//var/run/docker.sock` (Docker Desktop on Windows)
- Services available at:


| Service   | Local URL                                            |
| --------- | ---------------------------------------------------- |
| Traefik   | [http://localhost:8080](http://localhost:8080)       |
| Grafana   | [http://grafana.localhost](http://grafana.localhost) |
| Qdrant    | [http://qdrant.localhost](http://qdrant.localhost)   |
| SonarQube | [http://sonar.localhost](http://sonar.localhost)     |
| Vault     | [http://vault.localhost](http://vault.localhost)     |


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

The workflow at `[.github/workflows/deploy.yml](.github/workflows/deploy.yml)` triggers on **pull requests targeting `main` or `develop`**.

It SSHs into the VPS, writes the `.env` directly from **GitHub Secrets**, then redeploys the stack using the production overlay.

```
PR opened/updated → GitHub Actions → SSH into VPS → git pull → write .env → docker compose (prod) up -d
```

### Required GitHub Secrets

Go to **Settings → Secrets and variables → Actions** and add:


| Secret                   | Description                                           |
| ------------------------ | ----------------------------------------------------- |
| `VPS_HOST`               | VPS IP address or hostname                            |
| `VPS_USER`               | SSH user (e.g. `ubuntu`, `root`)                      |
| `VPS_SSH_KEY`            | Private SSH key (full PEM content)                    |
| `VPS_PORT`               | SSH port (usually `22`)                               |
| `INFRA_DOMAIN`           | Base domain (e.g. `hashcode.org`)                     |
| `EMAIL`                  | Let's Encrypt admin email                             |
| `POSTGRES_USER`          | Postgres username                                     |
| `POSTGRES_PASSWORD`      | Postgres password                                     |
| `REDIS_PASSWORD`         | Redis password                                        |
| `GRAFANA_ADMIN_USER`     | Grafana admin username                                |
| `GRAFANA_ADMIN_PASSWORD` | Grafana admin password                                |
| `SONARQUBE_DB_NAME`      | SonarQube database name (e.g. `sonarqube`)            |
| `TRAEFIK_DASHBOARD_AUTH` | Basic auth string (`htpasswd -nb admin yourpassword`) |


### Branches


| Branch    | Trigger      |
| --------- | ------------ |
| `main`    | PR → main    |
| `develop` | PR → develop |


### First-time VPS setup

Before the first automated deploy, SSH in manually and clone the repo:

```bash
git clone https://github.com/brx-hashcode/hashcode-vps-infra.git ~/hashcode-infra
cd ~/hashcode-infra
./scripts/setup.sh

# Create the SonarQube database
docker compose -f docker-compose.yml up -d postgres
docker exec -it postgres psql -U $POSTGRES_USER -c "CREATE DATABASE sonarqube;"
```

After that, all subsequent deploys are handled automatically by the workflow.