# Vault policy for the hascode-website AppRole.
# Grants read-only access to the website's KV v2 secrets path.
#
# Apply with:
#   vault policy write hascode-website vault/policies/hascode-website.hcl

path "secret/data/hascode-website" {
  capabilities = ["read"]
}

path "*" {
  capabilities = ["deny"]
}
