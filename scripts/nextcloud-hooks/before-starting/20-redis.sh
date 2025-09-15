#!/usr/bin/env bash
set -euo pipefail

echo "[hook] Checking Redis configuration..."
OCC="php -f /var/www/html/occ"

if [ "$(id -u)" != "33" ]; then
  echo "[hook] Warning: not running as www-data (uid 33). Continuing anyway."
fi

# If Nextcloud not ready/installed, skip; initial install will apply envs.
if ! $OCC status 1>/dev/null 2>&1; then
  echo "[hook] occ not ready yet; skipping."
  exit 0
fi

if ! $OCC status | grep -q 'installed: true'; then
  echo "[hook] Nextcloud not installed yet; skipping."
  exit 0
fi

if [ -z "${REDIS_HOST:-}" ]; then
  echo "[hook] REDIS_HOST not set; skipping."
  exit 0
fi

PORT=${REDIS_HOST_PORT:-6379}
PASS=${REDIS_HOST_PASSWORD:-}

if [ -n "$PASS" ]; then
  REDIS_JSON=$(cat <<JSON
{"host":"$REDIS_HOST","port":$PORT,"password":"$PASS"}
JSON
)
else
  REDIS_JSON=$(cat <<JSON
{"host":"$REDIS_HOST","port":$PORT}
JSON
)
fi

echo "[hook] Enabling maintenance mode..."
$OCC maintenance:mode --on || true

echo "[hook] Applying Redis and memcache configuration..."
$OCC config:system:set redis --type json --value "$REDIS_JSON"
$OCC config:system:set memcache.locking --value "\\OC\\Memcache\\Redis"
# Optional distributed cache (harmless on single-node)
$OCC config:system:set memcache.distributed --value "\\OC\\Memcache\\Redis" || true

echo "[hook] Current redis setting:"
$OCC config:system:get redis || true

echo "[hook] Disabling maintenance mode..."
$OCC maintenance:mode --off || true

echo "[hook] Done."

