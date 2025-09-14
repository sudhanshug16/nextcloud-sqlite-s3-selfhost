#!/usr/bin/env bash
set -euo pipefail

echo "[hook] Checking primary object store configuration..."
OCC="php -f /var/www/html/occ"

# Only run inside the Nextcloud container as www-data
if [ "$(id -u)" != "33" ]; then
  echo "[hook] Warning: not running as www-data (uid 33). Continuing anyway."
fi

# If Nextcloud not installed yet, the install script will pick up envs automatically.
if ! $OCC status 1>/dev/null 2>&1; then
  echo "[hook] occ not ready yet; skipping."
  exit 0
fi

if ! $OCC status | grep -q 'installed: true'; then
  echo "[hook] Nextcloud not installed yet; skipping."
  exit 0
fi

FORCE=${OBJECTSTORE_FORCE:-false}
if $OCC config:system:get objectstore | grep -q .; then
  case "$FORCE" in
    true|TRUE|True|1)
      echo "[hook] OBJECTSTORE_FORCE set; will reapply objectstore config" ;;
    *)
      echo "[hook] Objectstore already configured; nothing to do."; exit 0 ;;
  esac
fi

reqs=(OBJECTSTORE_S3_BUCKET OBJECTSTORE_S3_KEY OBJECTSTORE_S3_SECRET OBJECTSTORE_S3_REGION OBJECTSTORE_S3_HOST)
for v in "${reqs[@]}"; do
  if [ -z "${!v:-}" ]; then
    echo "[hook] Missing env $v; skipping objectstore configuration."
    exit 0
  fi
done

# Booleans and defaults
to_bool() { case "${1:-}" in true|TRUE|True|1) echo true ;; *) echo false ;; esac; }
OBJ_AUTOCREATE=$(to_bool "${OBJECTSTORE_S3_AUTOCREATE:-true}")
OBJ_SSL=$(to_bool "${OBJECTSTORE_S3_SSL:-true}")
OBJ_USEPATH=$(to_bool "${OBJECTSTORE_S3_USEPATH_STYLE:-false}")
OBJ_LEGACY=$(to_bool "${OBJECTSTORE_S3_LEGACYAUTH:-false}")
OBJ_PREFIX=${OBJECTSTORE_S3_OBJECT_PREFIX:-urn:oid:}
OBJ_PORT=${OBJECTSTORE_S3_PORT:-443}

JSON=$(cat <<JSON
{"class":"\\\\OC\\\\Files\\\\ObjectStore\\\\S3","arguments":{"bucket":"$OBJECTSTORE_S3_BUCKET","autocreate":$OBJ_AUTOCREATE,"key":"$OBJECTSTORE_S3_KEY","secret":"$OBJECTSTORE_S3_SECRET","hostname":"$OBJECTSTORE_S3_HOST","port":$OBJ_PORT,"use_ssl":$OBJ_SSL,"region":"$OBJECTSTORE_S3_REGION","use_path_style":$OBJ_USEPATH,"legacy_auth":$OBJ_LEGACY,"objectPrefix":"$OBJ_PREFIX"}}
JSON
)

echo "[hook] Enabling maintenance mode..."
$OCC maintenance:mode --on || true

echo "[hook] Applying primary object store configuration..."
$OCC config:system:set objectstore --type json --value "$JSON"

echo "[hook] Current objectstore setting:"
$OCC config:system:get objectstore || true

echo "[hook] Disabling maintenance mode..."
$OCC maintenance:mode --off || true

echo "[hook] Done."
