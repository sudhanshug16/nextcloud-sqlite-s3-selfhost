# Nextcloud + Traefik + Litestream (B2) — Compose Stack

This repository contains a Docker Compose setup for running Nextcloud behind Traefik with TLS, using SQLite in WAL mode and continuously replicating the database to Backblaze B2 via Litestream. It also includes a startup hook to configure a primary S3-compatible object store for Nextcloud (such as B2).

## Features
- Traefik reverse proxy with Let's Encrypt HTTP-01 challenge
- Nextcloud (stable-apache) with environment-driven configuration hooks
- SQLite database replicated to B2 using Litestream
- One-shot Litestream restore job for first-time recovery
- Primary object store configuration via env (S3-compatible / B2)
- Redis for file locking and caching
- SMTP configuration (via env on first install, via occ later)

## Prerequisites
- Docker and Docker Compose
- A DNS record pointing `NEXTCLOUD_HOST` to your server
- Backblaze B2 (or S3-compatible) credentials

## Quick Start
1. Create a single env file and render configs:
   - `cp .env.example .env` and edit
   - `bash scripts/setup.sh` (generates `traefik/traefik.yml`, `litestream.yml`, `redis/redis.conf`, ensures `traefik/acme.json`)

2. (Optional) If restoring an existing database from B2, run the init job once:
   - `docker compose run --rm litestream-init`

3. Start services:
   - `docker compose up -d`

4. Access Nextcloud at: `https://$NEXTCLOUD_HOST`

## Environment Variables
See `.env.example` for all variables. Most important:
- `NEXTCLOUD_HOST`, `NEXTCLOUD_TRUSTED_DOMAINS`, `OVERWRITEPROTOCOL`
- `NEXTCLOUD_ADMIN_USER`, `NEXTCLOUD_ADMIN_PASSWORD` (first install only)
- `SQLITE_DB` (defaults to `owncloud.db`)
- Object store: `OBJECTSTORE_S3_*` (bucket, host, key, secret, etc.)
- Litestream: `AWS_REGION`, `LITESTREAM_ACCESS_KEY_ID`, `LITESTREAM_SECRET_ACCESS_KEY`
- Redis: `REDIS_HOST`, optional `REDIS_HOST_PORT`, optional `REDIS_PASSWORD`
- SMTP: `SMTP_HOST`, `SMTP_SECURE`, `SMTP_PORT`, `SMTP_AUTHTYPE`, `SMTP_NAME`, `SMTP_PASSWORD`, `MAIL_FROM_ADDRESS`, `MAIL_DOMAIN`

## Files and Structure
- `docker-compose.yml` — stack definition
- `scripts/nextcloud-hooks/before-starting/10-objectstore.sh` — applies primary object store config via `occ`
- `scripts/setup.sh` — generates runtime configs from `.env`
- `litestream.yml` — generated runtime Litestream config (ignored by git)
- `traefik/traefik.yml` — generated runtime Traefik config (ignored by git)
- `traefik/acme.json` — issued cert data (sensitive; ignored by git)
- `redis/redis.conf` — generated Redis config (ignored by git)

## Litestream Notes
- `litestream-init` is a one-shot job to restore if a replica exists and the DB file does not. Safe to run on first boot.
- Continuous replication runs in the `litestream` sidecar and uses `litestream.yml`.

## Verifications (optional)
- Check Litestream logs: `docker compose logs -f litestream`
- Check Nextcloud status: `docker compose exec nextcloud php occ status`
- Confirm object store: `docker compose exec nextcloud php occ config:system:get objectstore`

## Security
- Do not commit secrets. `.env`, `litestream.yml`, `traefik/acme.json`, and `traefik/traefik.yml` are ignored by default and are generated from `.env`.
- Ensure `traefik/acme.json` has mode `0600` (the setup script enforces this).

## Redis
- Enabled via `redis` service. Nextcloud auto-configures if `REDIS_HOST` is provided.
- A startup hook also applies/updates Redis + memcache settings for existing installs.
- Defaults: host `redis`, port `6379`. Optional password via `REDIS_PASSWORD`.
- The setup script writes `redis/redis.conf` (appendonly on; requires password if set).
- Important: Set a non-empty `REDIS_PASSWORD` when using Redis. The Nextcloud image
  enables Redis-backed PHP sessions when `REDIS_HOST` is set; if the password is
  empty, PHP can attempt `auth=` with a blank value and session startup fails,
  resulting in login loops. Either set `REDIS_PASSWORD` (recommended) or disable
  Redis sessions by overriding PHP to use file sessions instead.

  - Recommended: set `REDIS_PASSWORD` in `.env`, re-run `scripts/setup.sh`, and `docker compose up -d`.
  - Alternative (advanced): set `PHP_SESSION_SAVE_HANDLER=files` in the Nextcloud service
    environment to keep file-based sessions while still using Redis for locking via occ.

## SMTP setup and troubleshooting
- For new installs, the Nextcloud image reads SMTP envs on first boot: `SMTP_HOST`, `SMTP_SECURE`, `SMTP_PORT`, `SMTP_AUTHTYPE`, `SMTP_NAME`, `SMTP_PASSWORD`, `MAIL_FROM_ADDRESS`, `MAIL_DOMAIN`.
- For existing installs, change settings via `occ` (envs are not re-applied automatically):

  - `docker compose exec -u www-data nextcloud php occ config:system:set mail_smtpmode --value="smtp"`
  - `docker compose exec -u www-data nextcloud php occ config:system:set mail_smtphost --value="$SMTP_HOST"`
  - `docker compose exec -u www-data nextcloud php occ config:system:set mail_smtpport --value="$SMTP_PORT"`
  - `docker compose exec -u www-data nextcloud php occ config:system:set mail_smtpsecure --value="$SMTP_SECURE"` # ssl or tls
  - `docker compose exec -u www-data nextcloud php occ config:system:set mail_smtpauth --value="1"`
  - `docker compose exec -u www-data nextcloud php occ config:system:set mail_smtpauthtype --value="$SMTP_AUTHTYPE"`
  - `docker compose exec -u www-data nextcloud php occ config:system:set mail_smtpname --value="$SMTP_NAME"`
  - `docker compose exec -u www-data nextcloud php occ config:system:set mail_smtppassword --value="$SMTP_PASSWORD"`
  - `docker compose exec -u www-data nextcloud php occ config:system:set mail_from_address --value="$MAIL_FROM_ADDRESS"`
  - `docker compose exec -u www-data nextcloud php occ config:system:set mail_domain --value="$MAIL_DOMAIN"`

- Verify current values:
  - `docker compose exec -u www-data nextcloud php occ config:list system | grep -i mail`
- Common pitfalls:
  - Use matching `SMTP_SECURE`/`SMTP_PORT`: `ssl` + `465`, or `tls` + `587`.
  - `MAIL_FROM_ADDRESS` is the local-part only (no `@domain`). `MAIL_DOMAIN` is the domain.
  - Ensure credentials are correct and the provider allows SMTP from your server IP.
  - If you changed envs after first install, use the `occ` commands above and restart Nextcloud.


## License
No license specified. Add one if you plan to publish.
