#!/usr/bin/env bash
# Run once on VPS to install rclone and set up the backup cron job.
# R2 credentials are read from ~/hashcode-vps-infra/.env at backup time.
# Usage: bash setup-backup.sh <postgres_user> <slack_webhook>
set -euo pipefail

POSTGRES_USER="${1:?POSTGRES_USER required}"
SLACK_WEBHOOK="${2:?SLACK_WEBHOOK required}"

# Install rclone
if ! command -v rclone &>/dev/null; then
  echo "Installing rclone..."
  curl -fsSL https://rclone.org/install.sh | bash
fi

# Store env vars for backup script
cat > /etc/hashcode-backup.env <<EOF
export POSTGRES_USER=${POSTGRES_USER}
export SLACK_WEBHOOK_URL=${SLACK_WEBHOOK}
EOF
chmod 600 /etc/hashcode-backup.env

# Install cron job — runs daily at 2:00 AM
CRON_JOB="0 2 * * * bash -c 'source /etc/hashcode-backup.env && bash /home/brx/hashcode-vps-infra/scripts/backup.sh' >> /var/log/hashcode-backup.log 2>&1"
{ crontab -l 2>/dev/null | grep -v 'backup.sh'; echo "$CRON_JOB"; } | crontab -

echo "============================================"
echo " Backup setup complete!"
echo " Schedule : daily at 02:00 AM"
echo " Logs     : /var/log/hashcode-backup.log"
echo " Storage  : Cloudflare R2 hashcode-backups"
echo " R2 keys  : read from ~/hashcode-vps-infra/.env"
echo "============================================"
echo ""
echo "Test with: sudo bash -c 'source /etc/hashcode-backup.env && bash /home/brx/hashcode-vps-infra/scripts/backup.sh'"
