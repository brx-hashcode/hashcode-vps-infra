#!/bin/bash
set -euo pipefail

MAILCOW_DIR="/opt/mailcow"
HOSTNAME="mail.hashcode.digital"
TIMEZONE="$(timedatectl show -p Timezone --value 2>/dev/null || echo 'Europe/Amsterdam')"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Cloning mailcow-dockerized to ${MAILCOW_DIR}..."
if [ -d "${MAILCOW_DIR}" ]; then
  echo "    Directory already exists, skipping clone."
else
  git clone https://github.com/mailcow/mailcow-dockerized "${MAILCOW_DIR}"
fi

echo "==> Running config generator..."
cd "${MAILCOW_DIR}"
./generate_config.sh <<EOF
${HOSTNAME}
${TIMEZONE}
EOF

echo "==> Configuring mailcow.conf for Traefik integration..."
# Disable Mailcow's built-in Let's Encrypt (Traefik handles TLS)
sed -i 's/^SKIP_LETS_ENCRYPT=.*/SKIP_LETS_ENCRYPT=y/' mailcow.conf

# Bind HTTP to all interfaces, disable HTTPS binding (Traefik terminates TLS)
sed -i 's/^HTTP_PORT=.*/HTTP_PORT=8080/' mailcow.conf
sed -i 's/^HTTP_BIND=.*/HTTP_BIND=0.0.0.0/' mailcow.conf
sed -i 's/^HTTPS_PORT=.*/HTTPS_PORT=8443/' mailcow.conf
sed -i 's/^HTTPS_BIND=.*/HTTPS_BIND=127.0.0.1/' mailcow.conf

echo "==> Copying docker-compose.override.yml..."
cp "${SCRIPT_DIR}/docker-compose.override.yml" "${MAILCOW_DIR}/docker-compose.override.yml"

echo "==> Setup complete!"
echo "    Start Mailcow with: ${SCRIPT_DIR}/start.sh"
echo "    Web UI will be at: https://${HOSTNAME}"
