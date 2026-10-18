# Deploy Checklist

## Step 1 — DNS (do first, propagation takes time)

Add A records pointing to your VPS IP:

| Subdomain | Record |
|---|---|
| `traefik.hashcode.digital` | A → VPS IP |
| `portainer.hashcode.digital` | A → VPS IP |
| `qdrant.hashcode.digital` | A → VPS IP |
| `vault.hashcode.digital` | A → VPS IP |

---

## Step 2 — Set up SSH key authentication

GitHub Actions cannot SSH with a password — you need a key pair.

**On your local machine**, generate a dedicated key:
```bash
ssh-keygen -t ed25519 -C "github-actions" -f ~/.ssh/hashcode_vps
```

**Add the public key to the VPS** (SSH in with your password one more time):
```bash
ssh root@YOUR_VPS_IP
mkdir -p ~/.ssh
echo "PASTE_PUBLIC_KEY_HERE" >> ~/.ssh/authorized_keys
chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys
```

**Test it works:**
```bash
ssh -i ~/.ssh/hashcode_vps root@YOUR_VPS_IP
```

---

## Step 3 — GitHub Secrets

Go to the repo → **Settings → Secrets and variables → Actions**, add:

| Secret | Notes |
|---|---|
| `VPS_HOST` | VPS IP address |
| `VPS_USER` | `root` |
| `VPS_SSH_KEY` | Content of `~/.ssh/hashcode_vps` (private key) |
| `VPS_PORT` | `22` |
| `INFRA_DOMAIN` | `hashcode.digital` |
| `EMAIL` | Email for Let's Encrypt notifications |
| `POSTGRES_USER` | e.g. `hashcode` |
| `POSTGRES_PASSWORD` | Strong password |
| `REDIS_PASSWORD` | Strong password |
| `TRAEFIK_DASHBOARD_AUTH` | Output of `htpasswd -nb admin yourpass` |
| `TRAEFIK_DASHBOARD_AUTH_PLAIN` | `admin:yourpass` (plain, used by smoke test) |

> Generate the `TRAEFIK_DASHBOARD_AUTH` value:
> ```bash
> htpasswd -nb admin yourpassword
> ```
>
> Get the private key content:
> ```bash
> cat ~/.ssh/hashcode_vps
> ```

---

## Step 4 — First-time VPS bootstrap

SSH into the VPS once to clone the repo and run the bootstrap script:

```bash
git clone https://github.com/brx-hashcode/hashcode-vps-infra.git ~/hashcode-infra
cd ~/hashcode-infra
./scripts/setup.sh
```

`setup.sh` will create `data/` directories and `traefik/acme.json` with correct permissions.
Then fill in `.env` with real values and start the stack:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

Then install the boot safety net (README → *After a reboot*): the
`hashcode-stack.service` unit and the `systemctl mask` of host web servers.

---

## Step 5 — CI/CD takes over

After the first manual deploy, all subsequent deploys are automated.
Merge any PR to `main` — the workflow at `.github/workflows/deploy.yml` will:

1. SSH into the VPS
2. Pull latest code
3. Write `.env` from GitHub Secrets — including
   `COMPOSE_FILE=docker-compose.yml:docker-compose.prod.yml`, so a bare
   `docker compose` on the VPS can never start the base file alone
4. Run `docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --remove-orphans`
5. Run smoke tests against all public endpoints

---

## Vault — first boot

Vault starts **uninitialized**. After the first deploy, initialize it:

```bash
# SSH into VPS
docker exec -it vault vault operator init

# Save the unseal keys and root token securely — they are shown only once.

# Unseal (run 3 times with different keys)
docker exec -it vault vault operator unseal <key-1>
docker exec -it vault vault operator unseal <key-2>
docker exec -it vault vault operator unseal <key-3>
```

Vault UI is available at `https://vault.hashcode.digital`.

---

## Portainer — first boot

On first access, Portainer prompts you to create an admin account.
**Do this within 5 minutes** of first boot — otherwise it locks itself and needs a container restart.

```bash
docker compose restart portainer
```
