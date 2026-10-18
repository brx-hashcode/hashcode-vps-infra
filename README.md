# hashcode-infra

Shared deployment infrastructure for the brx-hashcode organization, managed with Docker Compose and Traefik. Runs on a single VPS and routes traffic to any project deployed on the same server.

## Stack


| Service    | Image                  | URL                                     |
| ---------- | ---------------------- | --------------------------------------- |
| Traefik    | traefik:v3             | `traefik.hashcode.digital` (dashboard)  |
| Postgres   | postgres:17            | internal only (direct: port 5432)       |
| Redis      | redis:7                | internal only                           |
| Qdrant     | qdrant/qdrant          | `qdrant.hashcode.digital`               |
| Portainer  | portainer/portainer-ce | `portainer.hashcode.digital`            |
| Vault      | hashicorp/vault        | `vault.hashcode.digital`               |

> Apps connect to Postgres directly at `postgres:5432` (there is no connection pooler).


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

This infra repo owns the `**hashcode.digital**` domain for shared tooling.
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
  hashcode-public:
    external: true      # shared Traefik network
  hashcode-internal:
    external: true      # shared DB/Redis network

services:
  api:
    image: ghcr.io/brx-hashcode/rabotka-backend:latest
    networks:
      - hashcode-public
      - hashcode-internal
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=hashcode-public"
      - "traefik.http.routers.rabotka-api-prod.rule=Host(`api.rabotka.co`)"
      - "traefik.http.routers.rabotka-api-prod.entrypoints=websecure"
      - "traefik.http.routers.rabotka-api-prod.tls.certresolver=letsencrypt"
      - "traefik.http.services.rabotka-api-prod.loadbalancer.server.port=<app-port>"
```

> **Important:**
>
> - `traefik.docker.network=hashcode-public` is required when a container is on multiple networks — without it, Traefik may pick the wrong network IP and return 504.
> - `loadbalancer.server.port` must match the port your app listens on inside the container.
> - Router names (e.g. `rabotka-api-prod`) must be **unique** across all containers on the server.

### Database connection pattern

Apps on `hashcode-internal` reach Postgres directly, for both runtime and
migrations:

```env
DATABASE_URL=postgresql://user:pass@postgres:5432/mydb
```

---

## Prerequisites

- Docker + Docker Compose v2
- A server with ports 80 and 443 open
- DNS A records for all infra subdomains pointing to the VPS:
  - `traefik.hashcode.digital`
  - `portainer.hashcode.digital`
  - `qdrant.hashcode.digital`
  - `sonar.hashcode.digital`
  - `vault.hashcode.digital`

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
INFRA_DOMAIN=hashcode.digital
EMAIL=admin@hashcode.digital

POSTGRES_USER=rabotka
POSTGRES_PASSWORD=<strong-password>

REDIS_PASSWORD=<strong-password>

# Generate with: htpasswd -nb admin yourpassword
TRAEFIK_DASHBOARD_AUTH=admin:$apr1$...
```

**4. Start the stack**

```bash
# Production (VPS — Linux)
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# Local (Docker Desktop — Windows/macOS) — NEVER on the VPS
docker compose up -d
# docker-compose.override.yml is picked up automatically
```

> **On the VPS, `.env` sets `COMPOSE_FILE=docker-compose.yml:docker-compose.prod.yml`**
> (written by the deploy workflow), so a bare `docker compose ...` there uses both
> files. The base file alone starts Traefik without its `websecure` entrypoint and
> certificate resolver, which takes every site down. Scripts still pass both `-f`
> flags explicitly. Don't put `COMPOSE_FILE` in a local `.env`: it would stop
> `docker-compose.override.yml` from being picked up.

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
│   └── vault/
└── scripts/
    ├── setup.sh                # One-time server bootstrap
    ├── hashcode-stack.service  # systemd unit: stack up + check after every boot
    └── post-boot-check.sh      # Traefik/ports, containers, public hosts → Slack
```

---

## Networking


| Network            | Purpose                                                     |
| ------------------ | ----------------------------------------------------------- |
| `hashcode-public`   | Traefik + any container that needs an external URL          |
| `hashcode-internal` | Postgres, Redis — only containers that need DB/cache access |


> When a container is on both networks, always set `traefik.docker.network=hashcode-public` in its labels so Traefik routes through the correct interface.

---

## Local Development

The `docker-compose.override.yml` is auto-loaded by Docker Compose and replaces all production settings for local use:

- No TLS or Let's Encrypt
- Uses `//var/run/docker.sock` (Docker Desktop on Windows)
- Services available at:


| Service   | Local URL                                            |
| --------- | ---------------------------------------------------- |
| Traefik   | [http://localhost:8080](http://localhost:8080)       |
| Portainer | [http://portainer.localhost](http://portainer.localhost) |
| Qdrant    | [http://qdrant.localhost](http://qdrant.localhost)   |
| Vault     | [http://vault.localhost](http://vault.localhost)     |


> `*.localhost` subdomains resolve to `127.0.0.1` natively — no `/etc/hosts` edits needed.

```bash
docker compose up -d
```

---

## Common Commands

```bash
# Start (local only — on the VPS, always pass both files)
docker compose up -d

# Start (production)
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# View logs
docker compose logs -f

# Restart a single service
docker compose restart portainer

# Stop everything
docker compose down

# Stop and remove volumes (destructive)
docker compose down -v
```

## After a reboot

On 2026-10-18 the VPS rebooted, a host package grabbed :80 first, Traefik
exited and every site stayed down for ~6 hours unnoticed. Three things now
cover that:

- **Restart policies**: every infra service is `restart: always`, the app
  stacks `unless-stopped`.
- **`hashcode-stack.service`** (in `scripts/`): after boot it waits 30s, runs
  `docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d`, then
  `scripts/post-boot-check.sh`, which checks Traefik and ports 80/443, every
  container's state and health, and every public `Host(...)` from the Traefik
  labels, and posts the result to Slack (`VPS_SLACK_ALERT_WEBHOOK`).
- **Traefik healthcheck**: `traefik healthcheck --ping` against the
  `websecure` entrypoint (prod file).

Install the unit once (root):

```bash
sudo ln -sf /home/brx/hashcode-vps-infra/scripts/hashcode-stack.service /etc/systemd/system/hashcode-stack.service
sudo systemctl daemon-reload && sudo systemctl enable hashcode-stack.service
# Keep host web servers from ever taking :80/:443 at boot
sudo systemctl mask apache2 nginx lighttpd caddy merecat
```

Run the check by hand at any time (`NO_SLACK=1` to only print):

```bash
CHECK_REASON="Manual check" scripts/post-boot-check.sh
journalctl -u hashcode-stack -b     # what the boot run did
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
| `INFRA_DOMAIN`           | Base domain (e.g. `hashcode.digital`)                     |
| `EMAIL`                  | Let's Encrypt admin email                             |
| `POSTGRES_USER`          | Postgres username                                     |
| `POSTGRES_PASSWORD`      | Postgres password                                     |
| `REDIS_PASSWORD`         | Redis password                                        |
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
```

After that, all subsequent deploys are handled automatically by the workflow.

---

## Deployment Flow

```
Push / PR → GitHub Actions → SSH into VPS → git pull → write .env → docker compose (prod) up -d
```

Portainer gives you a live view of all running containers, logs, and resource usage at `portainer.hashcode.digital`.

> **Two logins:** `portainer.hashcode.digital` first asks for the same basic-auth user/password as the Traefik and Prometheus dashboards (`TRAEFIK_DASHBOARD_AUTH`), then shows Portainer's own login. The extra login keeps Google's scanner away from the Portainer login page, which got `hashcode.digital` flagged as a "Dangerous site" in Chrome.

> **Patched image:** Portainer is built from [`portainer/Dockerfile`](portainer/Dockerfile), which removes a dead `googlecode.com` script tag that made Chrome flag the site as dangerous ([portainer#13118](https://github.com/portainer/portainer/issues/13118)). To upgrade, bump both `PORTAINER_VERSION` and the image tag in `docker-compose.yml`.

> **First-time Portainer setup:** On first access, Portainer will prompt you to create an admin account. Do this within 5 minutes of first boot — otherwise the container locks itself for security and needs a restart.