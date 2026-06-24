#!/usr/bin/env bash
# Nightly backup to Cloudflare R2 — run as root via cron.
#
# Backs up from LIVE containers/volumes (not the ./data bind stubs, which can be
# empty when a service uses a named volume) and FAILS LOUDLY if any artifact is
# empty — so the Slack "success" message can never lie about an empty backup.
set -euo pipefail

TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_DIR="/tmp/hashcode-backup-${TIMESTAMP}"
# Self-resolving repo dir — works regardless of clone name / user.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUCKET="hashcode-backups"
SLACK_WEBHOOK="${SLACK_WEBHOOK_URL:-}"
MIN_DB_DUMP_BYTES=200000   # a real per-DB dump (custom format) must exceed this

# Load R2 credentials + POSTGRES_USER from .env
set -a; source "${REPO_DIR}/.env"; set +a

# Configure rclone dynamically from env
mkdir -p /root/.config/rclone
cat > /root/.config/rclone/rclone.conf <<EOF
[r2]
type = s3
provider = Cloudflare
access_key_id = ${R2_ACCESS_KEY_ID}
secret_access_key = ${R2_SECRET_ACCESS_KEY}
endpoint = https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com
acl = private
EOF

CURRENT_STEP="init"
log() { echo "[$(date '+%H:%M:%S')] $*"; }

notify_slack() {
  local color="$1" message="$2"
  if [ -n "$SLACK_WEBHOOK" ]; then
    curl -s -X POST "$SLACK_WEBHOOK" \
      -H 'Content-type: application/json' \
      --data "{\"attachments\":[{\"color\":\"${color}\",\"text\":\"${message}\"}]}" > /dev/null || true
  fi
}

cleanup() { rm -rf "$BACKUP_DIR"; }
trap cleanup EXIT

on_error() {
  notify_slack "#B3000C" "❌ *VPS Backup Failed* — ${TIMESTAMP}\nStep: ${CURRENT_STEP}\nCheck: /var/log/hashcode-backup.log"
  exit 1
}
trap on_error ERR

# Fail loudly if an artifact is missing or smaller than expected.
require_min() {
  local f="$1" min="$2"
  local s; s=$(stat -c%s "$f" 2>/dev/null || echo 0)
  if [ "$s" -lt "$min" ]; then
    log "FATAL: $(basename "$f") is only ${s} bytes (< ${min}) — backup is empty/broken"
    return 1
  fi
  log "  ok: $(basename "$f") = $(numfmt --to=iec "$s")"
}

# tar a path from INSIDE a live container — captures the real mount whether it
# is a named volume or a bind. Errors if the container is not running.
backup_container_path() {
  local svc="$1" path="$2" out="$3"
  if ! docker ps --format '{{.Names}}' | grep -qx "$svc"; then
    log "FATAL: container '$svc' not running"; return 1
  fi
  docker run --rm --volumes-from "$svc" -v "${BACKUP_DIR}:/backup" \
    alpine tar czf "/backup/${out}" -C / "${path#/}"
}

mkdir -p "$BACKUP_DIR"

# ── 1. Postgres — logical dumps as the superuser (authoritative) ─────────────
CURRENT_STEP="postgres"
log "Backing up Postgres (logical, per database)..."
PG_SUPER="${POSTGRES_USER}"
# Roles / globals
docker exec postgres pg_dumpall -U "$PG_SUPER" --globals-only \
  | gzip > "${BACKUP_DIR}/pg_globals_${TIMESTAMP}.sql.gz"
# Each real database in custom format (compressed, restorable with pg_restore)
DBS=$(docker exec postgres psql -U "$PG_SUPER" -tAc \
  "SELECT datname FROM pg_database WHERE datistemplate=false AND datname<>'postgres';")
if [ -z "$DBS" ]; then log "FATAL: no databases returned by psql"; exit 1; fi
LARGEST_DB_DUMP=""
for db in $DBS; do
  log "  dumping ${db}..."
  out="${BACKUP_DIR}/pg_${db}_${TIMESTAMP}.dump"
  docker exec postgres pg_dump -U "$PG_SUPER" -Fc "$db" > "$out"
  gzip "$out"
  # track the largest dump so we can assert at least one DB has real data
  if [ -z "$LARGEST_DB_DUMP" ] || \
     [ "$(stat -c%s "${out}.gz")" -gt "$(stat -c%s "$LARGEST_DB_DUMP")" ]; then
    LARGEST_DB_DUMP="${out}.gz"
  fi
done
require_min "$LARGEST_DB_DUMP" "$MIN_DB_DUMP_BYTES"

# ── 2. Grafana volume (live) ─────────────────────────────────────────────────
CURRENT_STEP="grafana"
log "Backing up Grafana..."
backup_container_path grafana /var/lib/grafana "grafana_${TIMESTAMP}.tar.gz"

# ── 3. Qdrant storage (live volume) ──────────────────────────────────────────
CURRENT_STEP="qdrant"
log "Backing up Qdrant..."
backup_container_path qdrant /qdrant/storage "qdrant_${TIMESTAMP}.tar.gz"

# ── 4. Vault data (live volume) ──────────────────────────────────────────────
CURRENT_STEP="vault"
log "Backing up Vault..."
backup_container_path vault /vault/data "vault_${TIMESTAMP}.tar.gz"

# ── 5. Upload to R2 + verify size landed ─────────────────────────────────────
CURRENT_STEP="upload"
log "Uploading to R2..."
rclone copy "$BACKUP_DIR" "r2:${BUCKET}/${TIMESTAMP}/" --s3-no-check-bucket
LOCAL_BYTES=$(du -sb "$BACKUP_DIR" | cut -f1)
REMOTE_BYTES=$(rclone size "r2:${BUCKET}/${TIMESTAMP}" --json 2>/dev/null \
  | grep -oE '"bytes":[0-9]+' | grep -oE '[0-9]+' || echo 0)
log "  local=${LOCAL_BYTES}B remote=${REMOTE_BYTES}B"
if [ "${REMOTE_BYTES:-0}" -lt "$LOCAL_BYTES" ]; then
  log "FATAL: R2 upload incomplete (remote ${REMOTE_BYTES} < local ${LOCAL_BYTES})"; exit 1
fi

# ── 6. Prune backups older than 30 days ──────────────────────────────────────
CURRENT_STEP="prune"
log "Pruning old backups..."
rclone delete "r2:${BUCKET}" --min-age 30d --rmdirs

# ── 7. Report with per-file breakdown ────────────────────────────────────────
CURRENT_STEP="report"
TOTAL_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
BREAKDOWN=$(cd "$BACKUP_DIR" && du -h ./* | sort -rh | awk '{printf "%s  %s\\n", $1, $2}')
log "Backup complete. Size: ${TOTAL_SIZE}"
notify_slack "#00B32C" "✅ *VPS Backup Succeeded* — ${TIMESTAMP}\nTotal: ${TOTAL_SIZE}\n\`\`\`\n${BREAKDOWN}\`\`\`\nStored in R2: ${BUCKET}/${TIMESTAMP}/"
