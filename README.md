# hashcode-infra

Production infrastructure for the Rabotka platform, managed with Docker Compose and Traefik.

## Stack

| Service  | Image             | Exposed                         |
|----------|-------------------|---------------------------------|
| Traefik  | traefik:v3        | :80, :443 (reverse proxy + TLS) |
| Postgres | postgres:16       | internal only                   |
| Redis    | redis:7           | internal only                   |
| Qdrant   | qdrant/qdrant     | `qdrant.<DOMAIN>` (HTTPS)       |
| Grafana  | grafana/grafana   | `grafana.<DOMAIN>` (HTTPS)      |

TLS certificates are provisioned automatically via Let's Encrypt (HTTP challenge).

## Prerequisites

- Docker + Docker Compose v2
- A server with ports 80 and 443 open
- A domain with DNS A records pointing to the server:
  - `qdrant.<DOMAIN>`
  - `grafana.<DOMAIN>`

## Setup

**1. Clone the repo**

```bash
git clone <repo-url>
cd hashcode-infra
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
# Domain & TLS
DOMAIN=yourdomain.com
EMAIL=admin@yourdomain.com

# Postgres
POSTGRES_DB=rabotka
POSTGRES_USER=rabotka
POSTGRES_PASSWORD=<strong-password>

# Redis
REDIS_PASSWORD=<strong-password>
```

**4. Start the stack**

```bash
docker compose up -d
```

## Directory Structure

```
hashcode-infra/
├── docker-compose.yml      # Service definitions
├── .env.example            # Environment variable template
├── .gitignore
├── traefik/
│   └── acme.json           # Let's Encrypt certificate storage (gitignored)
├── data/                   # Persistent volume data (gitignored)
│   ├── postgres/
│   ├── redis/
│   ├── qdrant/
│   └── grafana/
└── scripts/
    └── setup.sh            # One-time server bootstrap
```

## Networking

- `rabotka-public` — Traefik and services that need external access (Qdrant, Grafana)
- `rabotka-internal` — Private network for Postgres, Redis, and internal service communication

## Common Commands

```bash
# Start all services
docker compose up -d

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
docker compose pull
docker compose up -d
```
