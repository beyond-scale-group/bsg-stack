#!/usr/bin/env bash
# Provision and deploy gbrain on Clever Cloud.
# Idempotent — safe to re-run after any failure; each phase skips what exists.
#
# Usage:
#   cp gbrain.env.example gbrain.env   # fill in API keys first
#   ./install.sh [--org ORG] [--name APP_NAME] [--region REGION]
#
# Requires: clever CLI >= 4.11 (logged in), jq, git, curl.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

APP_NAME="${APP_NAME:-gbrain}"
REGION="${REGION:-par}"
ORG="${ORG:-}"
PG_PLAN="${PG_PLAN:-xs_sml}"       # NOT dev: too small for a real brain
FLAVOR="${FLAVOR:-XS}"
DEPLOY_DIR="${GBRAIN_DEPLOY_DIR:-$HOME/gbrain-clever-deploy}"
ENV_FILE="$SCRIPT_DIR/gbrain.env"

while [ $# -gt 0 ]; do
  case "$1" in
    --org)    ORG="$2"; shift 2 ;;
    --name)   APP_NAME="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 1 ;;
  esac
done

ORG_FLAG=()
[ -n "$ORG" ] && ORG_FLAG=(--org "$ORG")

log()  { echo "==> $*" >&2; }
fail() { echo "ERROR: $*" >&2; exit 1; }

# --- Phase 0: preflight -------------------------------------------------------
command -v clever >/dev/null || fail "clever CLI not found (brew install clevercloud/tap/clever-tools)"
command -v jq >/dev/null || fail "jq not found"
clever profile >/dev/null 2>&1 || fail "not logged in — run: clever login"
[ -f "$ENV_FILE" ] || fail "$ENV_FILE missing — cp gbrain.env.example gbrain.env and fill in your keys"
grep -qE '^(ZEROENTROPY|OPENAI)_API_KEY=.+' "$ENV_FILE" \
  || log "WARNING: no embedding key in gbrain.env — vector search will be disabled"

# --- Phase 1: deploy workdir (wrapper repo lives outside bsg-stack) -----------
log "syncing wrapper app to $DEPLOY_DIR"
mkdir -p "$DEPLOY_DIR"
cp "$SCRIPT_DIR/app/package.json" "$SCRIPT_DIR/app/boot.sh" \
   "$SCRIPT_DIR/app/preflight.ts" "$SCRIPT_DIR/app/patch-rls.ts" \
   "$SCRIPT_DIR/app/.gitignore" "$DEPLOY_DIR/"
chmod +x "$DEPLOY_DIR/boot.sh"
cd "$DEPLOY_DIR"
[ -d .git ] || git init -q
git add -A
git diff --cached --quiet || git commit -qm "gbrain wrapper app (synced from bsg-stack deploy/gbrain)"

# --- Phase 2: application -----------------------------------------------------
if [ ! -f .clever.json ]; then
  log "creating app '$APP_NAME' (node/bun, $REGION)"
  clever create --type node "$APP_NAME" --region "$REGION" "${ORG_FLAG[@]}"
else
  log "app already linked ($(jq -r '.apps[0].name' .clever.json 2>/dev/null || echo '?')) — skipping create"
fi

# --- Phase 3: add-ons ---------------------------------------------------------
addon_id() { # addon_id <name> -> id or empty
  clever addon list --format json "${ORG_FLAG[@]}" 2>/dev/null \
    | jq -r --arg n "$1" '.[] | select(.name == $n) | .addonId' | head -1
}

ensure_addon() { # ensure_addon <provider> <name> [extra flags…]
  local provider="$1" name="$2"; shift 2
  if [ -n "$(addon_id "$name")" ]; then
    log "add-on '$name' exists — ensuring link"
    clever service link-addon "$name" 2>/dev/null || true
  else
    log "creating add-on '$name' ($provider)"
    clever addon create "$provider" "$name" --region "$REGION" "${ORG_FLAG[@]}" --yes "$@"
    clever service link-addon "$name" 2>/dev/null || true
  fi
}

ensure_addon postgresql-addon "${APP_NAME}-db" --plan "$PG_PLAN"
ensure_addon cellar-addon     "${APP_NAME}-cellar"
ensure_addon fs-bucket        "${APP_NAME}-fsdata"

# --- Phase 4: environment -----------------------------------------------------
FS_ID="$(addon_id "${APP_NAME}-fsdata")"
[ -n "$FS_ID" ] || fail "could not resolve fs-bucket add-on id"
BUCKET_HOST="$(clever addon env "$FS_ID" --format shell | sed -n 's/^export BUCKET_HOST="\{0,1\}\([^"]*\)"\{0,1\};*$/\1/p' | head -1)"
[ -n "$BUCKET_HOST" ] || fail "could not read BUCKET_HOST from fs-bucket add-on"

DOMAIN="$(clever domain | grep -m1 cleverapps.io | tr -d ' *' | sed -E 's#^https?://##; s#/+$##')"
[ -n "$DOMAIN" ] || fail "could not resolve cleverapps.io domain"
PUBLIC_URL="https://${DOMAIN}"

log "setting environment (public URL: $PUBLIC_URL)"
clever env set CC_NODE_BUILD_TOOL bun >/dev/null
clever env set CC_FS_BUCKET "/data:${BUCKET_HOST}" >/dev/null
clever env set GBRAIN_PUBLIC_URL "$PUBLIC_URL" >/dev/null
clever env set GBRAIN_HTTP_TRUST_PROXY 1 >/dev/null
clever env set GBRAIN_HTTP_CORS_ORIGIN "$PUBLIC_URL" >/dev/null

if ! clever env --format shell | grep -q '^export GBRAIN_ADMIN_BOOTSTRAP_TOKEN='; then
  ADMIN_TOKEN="$(openssl rand -hex 32)"
  clever env set GBRAIN_ADMIN_BOOTSTRAP_TOKEN "$ADMIN_TOKEN" >/dev/null
  log "generated admin bootstrap token: $ADMIN_TOKEN  (save it — shown once)"
fi

log "forwarding secrets from gbrain.env"
while IFS='=' read -r key value; do
  case "$key" in ''|\#*) continue ;; esac
  [ -n "$value" ] && clever env set "$key" "$value" >/dev/null && log "  set $key"
done < "$ENV_FILE"

# --- Phase 5: scale (single writer — never scale horizontally) ----------------
log "pinning scaler to 1x $FLAVOR"
clever scale --flavor "$FLAVOR" --min-instances 1 --max-instances 1 >/dev/null

# --- Phase 6: deploy + verify --------------------------------------------------
log "deploying"
clever deploy --force

log "waiting for $PUBLIC_URL/health"
for i in $(seq 1 36); do
  if curl -fsS --max-time 5 "$PUBLIC_URL/health" >/dev/null 2>&1; then
    log "health check green ✓"
    echo
    echo "gbrain is live: $PUBLIC_URL"
    echo "  admin dashboard: $PUBLIC_URL/admin (GBRAIN_ADMIN_BOOTSTRAP_TOKEN)"
    echo "  next: clever ssh  →  gbrain auth register-client <name> --grant-types client_credentials --scopes read,write,admin"
    echo "        gbrain connect $PUBLIC_URL/mcp --token <token>"
    exit 0
  fi
  sleep 5
done

fail "health check did not turn green in 3 min — inspect with: clever logs"
