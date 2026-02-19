# Stage 11 - Security Hardening (Local Deployment)

This stage applies security-focused Docker Compose asset changes aligned with
`alfresco-ubuntu-installer` security considerations, for **local deployment**.

Reference:
- https://github.com/aborroy/alfresco-ubuntu-installer/blob/main/README.md#security-considerations

## What Changed in Compose Assets

1. HTTPS reverse proxy (TLS 1.3 only)
- `proxy` now exposes HTTPS on `8443` (host port `${PROXY_HTTPS_PORT:-8443}`).
- Nginx config enforces `ssl_protocols TLSv1.3`.
- HTTP endpoint (`8080`) only redirects to HTTPS.

2. Secure external URL settings
- Repository public URL settings use HTTPS:
  - `alfresco.host=${NGINX_SERVER_NAME:-localhost}`
  - `alfresco.port=${PROXY_HTTPS_PORT:-8443}`
  - `alfresco.protocol=https`
- Share public URL settings use HTTPS:
  - `share.host=${NGINX_SERVER_NAME:-localhost}`
  - `share.port=${PROXY_HTTPS_PORT:-8443}`
  - `share.protocol=https`
- Share CSRF and ADW base URL switched to HTTPS.

3. Internal port exposure restricted
- ActiveMQ web console host port mapping was removed in Stage 11.
- Internal services stay reachable only on Docker internal networking.

4. Certificate assets mounted as read-only bind volume
- `./proxy/certs` -> `/etc/nginx/ssl:ro`
- Expected files:
  - `proxy/certs/alfresco.crt`
  - `proxy/certs/alfresco.key`

## Admin Password and Password Encoding

- In installer-based deployments, admin password is auto-generated and stored in
  `config/alfresco.env`.
- Password encoding policy (bcrypt10) is handled by Alfresco platform behavior,
  not by Docker Compose keys.
- For restore-based migration, keep the original admin credentials from the
  source system so connector services can authenticate.

## Keep Environment Secrets Secure

`.env` contains sensitive values (DB, broker, admin credentials).

```bash
chmod 600 .env
```

## Generate Local Self-Signed Certificate

Stage 11 includes helper script:

```bash
cd stages/11-security-local
NGINX_SERVER_NAME=localhost ./generate-certs.sh
```

Force regeneration:

```bash
cd stages/11-security-local
NGINX_SERVER_NAME=localhost ./generate-certs.sh --force
```

## Run Stage 11

```bash
docker compose --env-file ../../.env -f compose.yaml up -d --build
```

## Verify HTTPS and TLS 1.3

```bash
# Readiness over HTTPS (self-signed: -k)
curl -k https://localhost:${PROXY_HTTPS_PORT:-8443}/alfresco/api/-default-/public/alfresco/versions/1/probes/-ready-

# Confirm TLS 1.3 negotiation
openssl s_client -connect localhost:${PROXY_HTTPS_PORT:-8443} -tls1_3
```

## Backup Guidance

Regular backups remain mandatory. Keep using the backup process already defined
in Stage 10 migration docs.
