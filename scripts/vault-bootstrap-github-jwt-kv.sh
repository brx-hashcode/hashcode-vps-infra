#!/usr/bin/env bash
set -euo pipefail

# One-time Vault bootstrap to allow GitHub Actions OIDC JWT auth.
#
# It creates:
# - KV v2 at `secret/`
# - policy `${POLICY_NAME}` that allows reading `secret/data/infra/*`
# - JWT auth role `${JWT_ROLE_NAME}` bound to `repository` claim
#
# Prerequisites:
# - Vault is reachable from inside the Vault container.
# - You provide a Vault token with permission to enable auth methods and write policies.
#
# Run on the VPS:
#   VAULT_TOKEN='<admin-token>' \
#     GITHUB_REPOSITORY='owner/repo' \
#     VAULT_JWT_ROLE_NAME='infra-deployer' \
#     VAULT_POLICY_NAME='infra-deployer' \
#     bash ./scripts/vault-bootstrap-github-jwt-kv.sh

VAULT_CONTAINER_NAME="${VAULT_CONTAINER_NAME:-vault}"
VAULT_ADDR_INTERNAL="${VAULT_ADDR_INTERNAL:-http://127.0.0.1:8200}"
KV_MOUNT="${VAULT_KV_MOUNT:-secret}"

POLICY_NAME="${VAULT_POLICY_NAME:-infra-deployer}"
JWT_ROLE_NAME="${VAULT_JWT_ROLE_NAME:-infra-deployer}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
GITHUB_AUDIENCE="${GITHUB_AUDIENCE:-vault}"

: "${VAULT_TOKEN:?VAULT_TOKEN is required (provide a token with admin rights)}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required (format: owner/repo)}"

vault_exec() {
  docker exec "${VAULT_CONTAINER_NAME}" sh -lc "$1"
}

vault_cli() {
  vault_exec "export VAULT_ADDR='${VAULT_ADDR_INTERNAL}'; export VAULT_TOKEN='${VAULT_TOKEN}'; $1"
}

echo "==> Enabling KV v2 at '${KV_MOUNT}/' (idempotent)"
vault_cli "vault secrets enable -path='${KV_MOUNT}' kv-v2 >/dev/null 2>&1 || true"

echo "==> Writing policy '${POLICY_NAME}'"
vault_cli "cat >/tmp/${POLICY_NAME}.hcl <<'POLICY'
path \"${KV_MOUNT}/data/infra/*\" {
  capabilities = [\"read\"]
}
POLICY"
vault_cli "vault policy write '${POLICY_NAME}' /tmp/${POLICY_NAME}.hcl"

echo "==> Enabling JWT auth (path: jwt)"
vault_cli "vault auth enable -path='jwt' jwt >/dev/null 2>&1 || true"

echo "==> Configuring JWT auth discovery (GitHub Actions)"
vault_cli "vault write auth/jwt/config \
  bound_issuer='https://token.actions.githubusercontent.com' \
  oidc_discovery_url='https://token.actions.githubusercontent.com' >/dev/null"

echo "==> Creating JWT role '${JWT_ROLE_NAME}'"
vault_cli "vault write auth/jwt/role/${JWT_ROLE_NAME} \
  role_type='jwt' \
  user_claim='actor' \
  bound_claims='{\"repository\":\"${GITHUB_REPOSITORY}\"}' \
  bound_audiences='${GITHUB_AUDIENCE}' \
  policies='${POLICY_NAME}' \
  ttl='10m' >/dev/null"

echo
echo "==> Done."
echo "Deploy workflow should request OIDC token with audience='${GITHUB_AUDIENCE}'."
echo "Vault JWT role name: ${JWT_ROLE_NAME}"

