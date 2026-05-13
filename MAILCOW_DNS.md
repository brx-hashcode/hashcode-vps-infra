# Mailcow DNS Records

## hashcode.digital zone (mail server host)

| Type | Name                  | Value              | Proxy        |
|------|-----------------------|--------------------|--------------|
| A    | mail.hashcode.digital | `<VPS_IP>`         | DNS only (OFF) |
| TXT  | mail.hashcode.digital | `v=spf1 mx ~all`   | DNS only     |

> ⚠️ `mail.hashcode.digital` **must** have the Cloudflare proxy disabled (grey cloud).
> Orange-cloud proxying blocks SMTP ports 25, 465, and 587 — TLS certs and mail delivery will fail.

---

## rabotka.work zone (sending domain)

| Type | Name                                    | Value                                                         | Priority |
|------|-----------------------------------------|---------------------------------------------------------------|----------|
| MX   | `rabotka.work`                          | `mail.hashcode.digital`                                       | 10       |
| TXT  | `rabotka.work`                          | `v=spf1 mx include:hashcode.digital ~all`                     | —        |
| TXT  | `_dmarc.rabotka.work`                   | `v=DMARC1; p=quarantine; rua=mailto:admin@rabotka.work`       | —        |
| TXT  | `<selector>._domainkey.rabotka.work`    | Retrieve from Mailcow admin → **Configuration → Domains → DKIM** | —   |

> Replace `<selector>` with the selector shown in the Mailcow admin UI after adding the domain.
> DKIM key format: `v=DKIM1; k=rsa; p=<long-base64-string>`
