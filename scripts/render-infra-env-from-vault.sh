#!/usr/bin/env bash
set -euo pipefail

# Renders the infra VPS `.env` file by reading secrets from Vault.
#
# Vault setup assumed:
# - KV v2 mounted at `secret/`
# - Infra secrets stored at `secret/infra/<env>` with fields:
#   INFRA_DOMAIN, EMAIL, POSTGRES_USER, POSTGRES_PASSWORD, REDIS_PASSWORD,
#   GRAFANA_ADMIN_USER, GRAFANA_ADMIN_PASSWORD
#
# Auth assumed:
# - GitHub Actions OIDC JWT (preferred): login role in Vault `auth/jwt/<JWT_ROLE_NAME>`
# - Or fallback to AppRole at `auth/approle` (if `GITHUB_JWT` is not provided)
#
# Required environment variables:
# - If using GitHub JWT:
#   - GITHUB_JWT
#   - VAULT_JWT_ROLE (optional, default: infra-deployer)
# - If using AppRole (fallback):
#   - VAULT_ROLE_ID
#   - VAULT_SECRET_ID
#
# Usage:
#   VAULT_ROLE_ID=... VAULT_SECRET_ID=... ./scripts/render-infra-env-from-vault.sh prod .env

ENV_NAME="${1:-prod}"
OUT_FILE="${2:-.env}"

VAULT_JWT_ROLE="${VAULT_JWT_ROLE:-infra-deployer}"
VAULT_TOKEN_VALUE="${VAULT_TOKEN_VALUE:-}"

if [ -z "${GITHUB_JWT:-}" ]; then
  : "${VAULT_ROLE_ID:?VAULT_ROLE_ID is required unless GITHUB_JWT is provided}"
  : "${VAULT_SECRET_ID:?VAULT_SECRET_ID is required unless GITHUB_JWT is provided}"
fi

VAULT_CONTAINER_NAME="${VAULT_CONTAINER_NAME:-vault}"
VAULT_ADDR_INTERNAL="${VAULT_ADDR_INTERNAL:-http://127.0.0.1:8200}"
VAULT_ROLE_NAME="${VAULT_ROLE_NAME:-infra-deployer}"
VAULT_KV_MOUNT="${VAULT_KV_MOUNT:-secret}"

vault_exec() {
  # Run Vault CLI inside the Vault container (no host networking needed).
  docker exec "${VAULT_CONTAINER_NAME}" sh -lc "$1"
}

vault_login() {
  if [ -n "${GITHUB_JWT:-}" ]; then
    # GitHub Actions OIDC JWT -> Vault token
    VAULT_TOKEN_VALUE="$(vault_exec "export VAULT_ADDR='${VAULT_ADDR_INTERNAL}'; \
      vault write -field=token auth/jwt/login role='${VAULT_JWT_ROLE}' jwt='${GITHUB_JWT}'")"
    export VAULT_TOKEN_VALUE
    return 0
  fi

  vault_exec "export VAULT_ADDR='${VAULT_ADDR_INTERNAL}'; \
    vault login -method=approle role_id='${VAULT_ROLE_ID}' secret_id='${VAULT_SECRET_ID}' >/dev/null"
}

vault_get_field() {
  local field="$1"

  # KV v2 canonical form is still exposed by `vault kv get`:
  #   secret/data/<path> on the wire, but CLI expects `secret/<path>`.
  #
  # Example stored path: secret/infra/prod
  if [ -n "${VAULT_TOKEN_VALUE:-}" ]; then
    vault_exec "export VAULT_ADDR='${VAULT_ADDR_INTERNAL}'; \
      export VAULT_TOKEN='${VAULT_TOKEN_VALUE}'; \
      vault kv get -field='${field}' '${VAULT_KV_MOUNT}/infra/${ENV_NAME}'"
  else
    vault_exec "export VAULT_ADDR='${VAULT_ADDR_INTERNAL}'; \
      vault kv get -field='${field}' '${VAULT_KV_MOUNT}/infra/${ENV_NAME}'"
  fi
}

echo "==> Rendering '${OUT_FILE}' from Vault (env='${ENV_NAME}')"

vault_login

INFRA_DOMAIN="$(vault_get_field "INFRA_DOMAIN")"
EMAIL="$(vault_get_field "EMAIL")"

POSTGRES_USER="$(vault_get_field "POSTGRES_USER")"
POSTGRES_PASSWORD="$(vault_get_field "POSTGRES_PASSWORD")"

REDIS_PASSWORD="$(vault_get_field "REDIS_PASSWORD")"

GRAFANA_ADMIN_USER="$(vault_get_field "GRAFANA_ADMIN_USER")"
GRAFANA_ADMIN_PASSWORD="$(vault_get_field "GRAFANA_ADMIN_PASSWORD")"

cat > "${OUT_FILE}" <<EOF
# Rendered by render-infra-env-from-vault.sh (env=${ENV_NAME})
INFRA_DOMAIN=${INFRA_DOMAIN}
EMAIL=${EMAIL}

POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

REDIS_PASSWORD=${REDIS_PASSWORD}

GRAFANA_ADMIN_USER=${GRAFANA_ADMIN_USER}
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
EOF

chmod 600 "${OUT_FILE}"
echo "==> Wrote '${OUT_FILE}'"

