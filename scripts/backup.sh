#!/usr/bin/env bash
# Nightly backup to Cloudflare R2 — run as root via cron.
set -euo pipefail

TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_DIR="/tmp/hashcode-backup-${TIMESTAMP}"
REPO_DIR="/home/brx/hashcode-vps-infra"
BUCKET="hashcode-backups"
SLACK_WEBHOOK="${SLACK_WEBHOOK_URL:-}"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

notify_slack() {
  local color="$1" message="$2"
  if [ -n "$SLACK_WEBHOOK" ]; then
    curl -s -X POST "$SLACK_WEBHOOK" \
      -H 'Content-type: application/json' \
      --data "{\"attachments\":[{\"color\":\"${color}\",\"text\":\"${message}\"}]}" > /dev/null
  fi
}

cleanup() { rm -rf "$BACKUP_DIR"; }
trap cleanup EXIT

mkdir -p "$BACKUP_DIR"

# 1. Postgres dump
log "Backing up Postgres..."
docker exec postgres pg_dumpall -U "${POSTGRES_USER}" | gzip > "${BACKUP_DIR}/postgres_${TIMESTAMP}.sql.gz"

# 2. Grafana volume
log "Backing up Grafana..."
docker run --rm \
  --volumes-from grafana \
  -v "${BACKUP_DIR}:/backup" \
  alpine tar czf "/backup/grafana_${TIMESTAMP}.tar.gz" /var/lib/grafana

# 3. Vault data
log "Backing up Vault..."
tar czf "${BACKUP_DIR}/vault_${TIMESTAMP}.tar.gz" -C "${REPO_DIR}/data" vault

# 4. Qdrant data
log "Backing up Qdrant..."
tar czf "${BACKUP_DIR}/qdrant_${TIMESTAMP}.tar.gz" -C "${REPO_DIR}/data" qdrant

# 5. Upload to R2 via rclone
log "Uploading to R2..."
rclone copy "$BACKUP_DIR" "r2:${BUCKET}/${TIMESTAMP}/" --s3-no-check-bucket

# 6. Delete R2 backups older than 30 days
log "Pruning old backups..."
rclone delete "r2:${BUCKET}" \
  --min-age 30d \
  --rmdirs

TOTAL_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
log "Backup complete. Size: ${TOTAL_SIZE}"
notify_slack "#00B32C" "✅ *VPS Backup Succeeded* — ${TIMESTAMP}\nSize: ${TOTAL_SIZE}\nStored in R2: ${BUCKET}/${TIMESTAMP}/"
