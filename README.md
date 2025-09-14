# Nextcloud + Traefik + Litestream (B2) — Compose Stack

This repository contains a Docker Compose setup for running Nextcloud behind Traefik with TLS, using SQLite in WAL mode and continuously replicating the database to Backblaze B2 via Litestream. It also includes a startup hook to configure a primary S3-compatible object store for Nextcloud (such as B2).

## Features
- Traefik reverse proxy with Let's Encrypt HTTP-01 challenge
- Nextcloud (stable-apache) with environment-driven configuration hooks
- SQLite database replicated to B2 using Litestream
- One-shot Litestream restore job for first-time recovery
- Primary object store configuration via env (S3-compatible / B2)

## Prerequisites
- Docker and Docker Compose
- A DNS record pointing `NEXTCLOUD_HOST` to your server
- Backblaze B2 (or S3-compatible) credentials

## Quick Start
1. Copy example files and fill in values:
   - `cp .env.example .env` and edit
   - `cp litestream.yml.example litestream.yml` and edit
   - `mkdir -p traefik && cp traefik/traefik.yml.example traefik/traefik.yml`
   - `touch traefik/acme.json && chmod 600 traefik/acme.json`

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

## Files and Structure
- `docker-compose.yml` — stack definition
- `scripts/nextcloud-hooks/before-starting/10-objectstore.sh` — applies primary object store config via `occ`
- `litestream.yml` — runtime Litestream config (ignored by git). Use `litestream.yml.example` to create it
- `traefik/traefik.yml` — runtime Traefik config (ignored by git). Use `traefik/traefik.yml.example` to create it
- `traefik/acme.json` — issued cert data (sensitive; ignored by git)

## Litestream Notes
- `litestream-init` is a one-shot job to restore if a replica exists and the DB file does not. Safe to run on first boot.
- Continuous replication runs in the `litestream` sidecar and uses `litestream.yml`.

## Verifications (optional)
- Check Litestream logs: `docker compose logs -f litestream`
- Check Nextcloud status: `docker compose exec nextcloud php occ status`
- Confirm object store: `docker compose exec nextcloud php occ config:system:get objectstore`

## Security
- Do not commit secrets. `.env`, `litestream.yml`, `traefik/acme.json`, and `traefik/traefik.yml` are ignored by default.
- Ensure `traefik/acme.json` has mode `0600`.

## License
No license specified. Add one if you plan to publish.
