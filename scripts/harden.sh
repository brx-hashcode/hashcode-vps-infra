#!/usr/bin/env bash
# VPS security hardening — run once as root after initial setup.
set -euo pipefail

SSH_PORT=${1:-22}

echo "==> [1/6] Updating system packages..."
apt-get update -qq && apt-get upgrade -y -qq

echo "==> [2/6] Installing security tools..."
apt-get install -y -qq ufw fail2ban unattended-upgrades

echo "==> [3/6] Hardening SSH..."
SSHD=/etc/ssh/sshd_config
cp "$SSHD" "$SSHD.bak.$(date +%s)"

sed -i "s/^#\?Port .*/Port ${SSH_PORT}/" "$SSHD"
sed -i "s/^#\?PermitRootLogin .*/PermitRootLogin no/" "$SSHD"
sed -i "s/^#\?PasswordAuthentication .*/PasswordAuthentication no/" "$SSHD"
sed -i "s/^#\?PubkeyAuthentication .*/PubkeyAuthentication yes/" "$SSHD"
sed -i "s/^#\?MaxAuthTries .*/MaxAuthTries 3/" "$SSHD"
sed -i "s/^#\?X11Forwarding .*/X11Forwarding no/" "$SSHD"
sed -i "s/^#\?AllowAgentForwarding .*/AllowAgentForwarding no/" "$SSHD"

systemctl restart sshd
echo "    SSH hardened on port ${SSH_PORT}. Make sure your key is loaded before closing this session!"

echo "==> [4/6] Configuring UFW firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow "${SSH_PORT}/tcp" comment "SSH"
ufw allow 80/tcp   comment "HTTP"
ufw allow 443/tcp  comment "HTTPS"
ufw allow 25/tcp   comment "SMTP (outbound mail)"
ufw allow 465/tcp  comment "SMTPS"
ufw allow 587/tcp  comment "SMTP Submission"
ufw allow 993/tcp  comment "IMAPS"
ufw --force enable
echo "    UFW enabled."

echo "==> [5/6] Configuring Fail2ban..."
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime  = 2h
findtime = 10m
maxretry = 5
backend  = systemd

[sshd]
enabled  = true
port     = ${SSH_PORT}
maxretry = 3
bantime  = 24h

[traefik-auth]
enabled  = true
port     = http,https
filter   = traefik-auth
logpath  = /root/hashcode-vps-infra/traefik/logs/access.log
maxretry = 10
bantime  = 1h
findtime = 5m
EOF

# Traefik auth filter
mkdir -p /etc/fail2ban/filter.d
cat > /etc/fail2ban/filter.d/traefik-auth.conf <<EOF
[Definition]
failregex = ^.*"(GET|POST|PUT|DELETE|PATCH).*" 401 .* "<HOST>".*$
ignoreregex =
EOF

systemctl enable fail2ban
systemctl restart fail2ban
echo "    Fail2ban configured."

echo "==> [6/6] Enabling automatic security updates..."
cat > /etc/apt/apt.conf.d/50unattended-upgrades <<EOF
Unattended-Upgrade::Allowed-Origins {
  "\${distro_id}:\${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

systemctl enable unattended-upgrades
echo "    Auto security updates enabled."

echo ""
echo "============================================"
echo " Security hardening complete!"
echo "============================================"
echo " SSH port     : ${SSH_PORT}"
echo " Firewall     : UFW active"
echo " Brute force  : Fail2ban active"
echo " Auto updates : enabled"
echo ""
echo " IMPORTANT: Update VPS_PORT secret in GitHub"
echo "            to ${SSH_PORT} if you changed it."
echo "============================================"
