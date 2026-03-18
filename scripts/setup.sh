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
mkdir -p data/postgres data/redis data/qdrant data/grafana

echo "==> Creating traefik/acme.json..."
mkdir -p traefik
touch traefik/acme.json
chmod 600 traefik/acme.json

echo "==> Done. Start the stack with: docker compose up -d"
