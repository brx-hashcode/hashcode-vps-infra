#!/usr/bin/env bash
# Run once on VPS to install rclone and configure R2.
# Usage: bash setup-backup.sh <access_key_id> <secret_access_key> <account_id> <postgres_user> <slack_webhook>
set -euo pipefail

R2_ACCESS_KEY_ID="${1:?R2_ACCESS_KEY_ID required}"
R2_SECRET_ACCESS_KEY="${2:?R2_SECRET_ACCESS_KEY required}"
R2_ACCOUNT_ID="${3:?R2_ACCOUNT_ID required}"
POSTGRES_USER="${4:?POSTGRES_USER required}"
SLACK_WEBHOOK="${5:?SLACK_WEBHOOK required}"

# Install rclone
if ! command -v rclone &>/dev/null; then
  echo "Installing rclone..."
  curl -fsSL https://rclone.org/install.sh | bash
fi

# Configure rclone for R2
mkdir -p ~/.config/rclone
cat > ~/.config/rclone/rclone.conf <<EOF
[r2]
type = s3
provider = Cloudflare
access_key_id = ${R2_ACCESS_KEY_ID}
secret_access_key = ${R2_SECRET_ACCESS_KEY}
endpoint = https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com
acl = private
EOF
chmod 600 ~/.config/rclone/rclone.conf

# Store env vars for backup script
cat > /etc/hashcode-backup.env <<EOF
export POSTGRES_USER=${POSTGRES_USER}
export SLACK_WEBHOOK_URL=${SLACK_WEBHOOK}
EOF
chmod 600 /etc/hashcode-backup.env

# Install cron job — runs daily at 2:00 AM
CRON_JOB="0 2 * * * source /etc/hashcode-backup.env && bash /root/hashcode-vps-infra/scripts/backup.sh >> /var/log/hashcode-backup.log 2>&1"
(crontab -l 2>/dev/null | grep -v 'backup.sh'; echo "$CRON_JOB") | crontab -

echo "============================================"
echo " Backup setup complete!"
echo " Schedule : daily at 02:00 AM"
echo " Logs     : /var/log/hashcode-backup.log"
echo " Storage  : Cloudflare R2 hashcode-backups"
echo "============================================"
echo ""
echo "Test with: source /etc/hashcode-backup.env && bash /root/hashcode-vps-infra/scripts/backup.sh"
