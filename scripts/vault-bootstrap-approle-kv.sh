#!/usr/bin/env bash
set -euo pipefail

# One-time Vault bootstrap (run on the VPS).
#
# What it does:
# - enables KV v2 at `secret/` (idempotent)
# - creates a policy that allows reading infra secrets under `secret/data/infra/*`
# - creates an AppRole `infra-deployer`
# - prints role_id and secret_id for you to put into GitHub Secrets
#
# Prerequisite:
# - Vault is unsealed and reachable from inside the Vault container.
# - You provide a Vault token with sufficient rights via VAULT_TOKEN.
#
# Usage on VPS:
#   VAULT_TOKEN='<root-or-admin-token>' ./scripts/vault-bootstrap-approle-kv.sh
#
# After it prints values, set these GitHub Secrets:
# - VAULT_ROLE_ID
# - VAULT_SECRET_ID

VAULT_CONTAINER_NAME="${VAULT_CONTAINER_NAME:-vault}"
VAULT_ADDR_INTERNAL="${VAULT_ADDR_INTERNAL:-http://127.0.0.1:8200}"

ROLE_PATH="auth/approle/role/infra-deployer"
POLICY_NAME="infra-deployer"
KV_MOUNT="secret"

: "${VAULT_TOKEN:?VAULT_TOKEN is required (provide a token with admin rights)}"

vault_exec() {
  docker exec "${VAULT_CONTAINER_NAME}" sh -lc "$1"
}

vault_cli() {
  # shellcheck disable=SC2029
  vault_exec "export VAULT_ADDR='${VAULT_ADDR_INTERNAL}'; export VAULT_TOKEN='${VAULT_TOKEN}'; $1"
}

echo "==> Enabling KV v2 at '${KV_MOUNT}/' (idempotent)"
vault_cli "vault secrets enable -path='${KV_MOUNT}' kv-v2 >/dev/null 2>&1 || true"

echo "==> Writing policy '${POLICY_NAME}'"
vault_cli "cat >/tmp/${POLICY_NAME}.hcl <<'POLICY'
path \"${KV_MOUNT}/data/infra/*\" {
  capabilities = [\"read\"]
}
POLICY
vault policy write '${POLICY_NAME}' /tmp/${POLICY_NAME}.hcl"

echo "==> Creating/updating AppRole 'infra-deployer'"
vault_cli "vault write '${ROLE_PATH}' \
  token_policies='${POLICY_NAME}' \
  token_ttl='1h' \
  token_max_ttl='4h' \
  secret_id_ttl='30m' \
  secret_id_num_uses='10' >/dev/null"

ROLE_ID="$(vault_cli "vault read -field=role_id auth/approle/role/infra-deployer/role-id")"
SECRET_ID="$(vault_cli "vault write -f -field=secret_id auth/approle/role/infra-deployer/secret-id")"

echo
echo "==> AppRole credentials"
echo "VAULT_ROLE_ID=${ROLE_ID}"
echo "VAULT_SECRET_ID=${SECRET_ID}"
echo
echo "==> Next: store infra secrets at Vault path:"
echo "  ${KV_MOUNT}/infra/prod"

