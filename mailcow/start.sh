#!/bin/bash
set -euo pipefail

cd /opt/mailcow
docker compose -f docker-compose.yml -f docker-compose.override.yml up -d
