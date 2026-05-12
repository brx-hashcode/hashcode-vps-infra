#!/bin/sh
set -e

# Generate userlist.txt from env vars (scram-sha-256 hashes fetched from Postgres,
# or md5 as fallback). PgBouncer needs this file to authenticate clients.
# We use the same credentials the app uses to connect to Postgres.
cat > /etc/pgbouncer/userlist.txt <<EOF
"${POSTGRESQL_USERNAME}" "${POSTGRESQL_PASSWORD}"
EOF

exec pgbouncer /etc/pgbouncer/pgbouncer.ini
