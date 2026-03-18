#!/usr/bin/env bash
set -euo pipefail

# Bootstrap script — run once on a fresh server before starting the stack.

echo "==> Checking .env..."
if [ ! -f .env ]; then
  cp .env.example .env
  echo "    Created .env from .env.example — fill in your values before continuing."
  exit 1
fi

echo "==> Creating data directories..."
mkdir -p data/postgres data/redis data/qdrant data/grafana data/vault

echo "==> Creating traefik/acme.json..."
mkdir -p traefik
touch traefik/acme.json
chmod 600 traefik/acme.json

echo "==> Done. Start the stack with:"
echo "    Local:  docker compose up -d"
echo "    Prod:   docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d"
