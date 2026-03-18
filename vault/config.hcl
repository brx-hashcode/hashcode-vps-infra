ui = true

storage "file" {
  path = "/vault/data"
}

auth "approle" {
  path = "auth/approle"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true  # TLS handled by Traefik
}

# Allow Vault to be reachable behind Traefik reverse proxy
api_addr = "http://0.0.0.0:8200"
