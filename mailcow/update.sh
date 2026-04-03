#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

cd /opt/mailcow

echo "==> Updating Mailcow..."
./update.sh --skip-start

echo "==> Re-applying override..."
cp "${SCRIPT_DIR}/docker-compose.override.yml" /opt/mailcow/docker-compose.override.yml

echo "==> Starting Mailcow..."
docker compose -f docker-compose.yml -f docker-compose.override.yml up -d
