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

---

## Step 5 — CI/CD takes over

After the first manual deploy, all subsequent deploys are automated.
Merge any PR to `main` — the workflow at `.github/workflows/deploy.yml` will:

1. SSH into the VPS
2. Pull latest code
3. Write `.env` from GitHub Secrets
4. Run `docker compose ... up -d --remove-orphans`
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

---

## Mailcow — email server

Mailcow runs as an isolated Docker stack on the same VPS, separate from the main infra compose.

### Install

```bash
# Clone into /opt/mailcow
cd /opt
git clone https://github.com/mailcow/mailcow-dockerized mailcow
cd mailcow

# Generate config
MAILCOW_HOSTNAME=mail.hashcode.digital ./generate_config.sh
```

Edit `mailcow.conf` before starting:

```ini
MAILCOW_HOSTNAME=mail.hashcode.digital
MAILCOW_TZ=Africa/Brazzaville
HTTP_PORT=8080
HTTPS_PORT=8443
```

Start the stack:

```bash
docker compose up -d
```

### Post-install (admin UI at https://mail.hashcode.digital:8443)

Default credentials: **admin / moohoo** — change on first login.

1. **Add domain**: Configuration → Domains → Add domain → `rabotka.work`
2. **Create mailbox**: E-Mail → Mailboxes → Add mailbox → `noreply@rabotka.work`
3. **Retrieve DKIM key**: Configuration → Domains → DKIM → copy the TXT record value into Cloudflare (see `MAILCOW_DNS.md`)

### Verify

```bash
# Admin UI responds
curl -I https://mail.hashcode.digital:8443

# DNS checks
dig MX rabotka.work
dig TXT rabotka.work
dig TXT _dmarc.rabotka.work
```

Use [mxtoolbox.com](https://mxtoolbox.com) to verify MX, SPF, DKIM, and DMARC after DNS propagates.
