#!/usr/bin/env bash
set -euo pipefail

# Generate runtime configs from .env so users only edit one file.

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

if [ ! -f .env ]; then
  echo "[setup] .env not found. Copy .env.example to .env and fill values."
  exit 1
fi

# Load .env into environment (supports comments and blank lines)
set -o allexport
source ./.env
set +o allexport

# Ensure directories exist
mkdir -p traefik
mkdir -p redis
chmod +x scripts/nextcloud-hooks/before-starting/*.sh || true

# Defaults and helpers
to_bool() { case "${1:-}" in true|TRUE|True|1) echo true ;; *) echo false ;; esac; }

# --- Render Traefik static config ---
TRAEFIK_EMAIL=${TRAEFIK_ACME_EMAIL:-}
if [ -z "${TRAEFIK_EMAIL}" ]; then
  echo "[setup] Missing TRAEFIK_ACME_EMAIL in .env"
  exit 1
fi

cat > traefik/traefik.yml <<YAML
global:
  checkNewVersion: false
  sendAnonymousUsage: false

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https

  websecure:
    address: ":443"

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false

certificatesResolvers:
  letsresolver:
    acme:
      email: "${TRAEFIK_EMAIL}"
      storage: /etc/traefik/acme.json
      httpChallenge:
        entryPoint: web
YAML

# Ensure ACME store exists with correct perms
if [ ! -f traefik/acme.json ]; then
  touch traefik/acme.json
fi
chmod 600 traefik/acme.json || true

echo "[setup] Wrote traefik/traefik.yml and ensured acme.json"

# --- Render Litestream config ---
# Inputs from .env with sensible defaults
SQLITE_DB_NAME=${SQLITE_DB:-owncloud.db}
AWS_REGION_VAL=${AWS_REGION:-eu-central-003}
S3_BUCKET=${OBJECTSTORE_S3_BUCKET:-}
S3_REGION=${OBJECTSTORE_S3_REGION:-${AWS_REGION_VAL}}
S3_HOST=${OBJECTSTORE_S3_HOST:-}
S3_PORT=${OBJECTSTORE_S3_PORT:-}
S3_SSL=$(to_bool "${OBJECTSTORE_S3_SSL:-true}")
S3_PATH_STYLE=$(to_bool "${OBJECTSTORE_S3_USEPATH_STYLE:-true}")
REPLICA_PREFIX=${LITESTREAM_REPLICA_PREFIX:-litestream-sqlite}

if [ -z "${S3_BUCKET}" ] || [ -z "${S3_HOST}" ]; then
  echo "[setup] Missing OBJECTSTORE_S3_BUCKET or OBJECTSTORE_S3_HOST in .env (needed for litestream.yml)"
  exit 1
fi

PROTO=$($S3_SSL && echo https || echo http)
HOSTPORT=${S3_HOST}
if [ -n "${S3_PORT}" ]; then
  HOSTPORT="${HOSTPORT}:${S3_PORT}"
fi

cat > litestream.yml <<YAML
dbs:
  - path: /var/www/html/data/${SQLITE_DB_NAME}
    snapshots:
      interval: 1h
      retention: 72h
    replicas:
      - url: s3://${S3_BUCKET}/${REPLICA_PREFIX}/${SQLITE_DB_NAME}
        type: s3
        endpoint: ${PROTO}://${HOSTPORT}
        region: ${S3_REGION}
        force-path-style: ${S3_PATH_STYLE}
        sync-interval: 1s
YAML

echo "[setup] Wrote litestream.yml"

# --- Render Redis config ---
{
  echo "appendonly yes"
  if [ -n "${REDIS_PASSWORD:-}" ]; then
    echo "requirepass ${REDIS_PASSWORD}"
  fi
} > redis/redis.conf

echo "[setup] Wrote redis/redis.conf"

echo "[setup] All configs rendered from .env. You can now run:"
echo "  docker compose up -d"
