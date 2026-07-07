#!/usr/bin/env bash
# gbrain boot sequence on Clever Cloud. Run by `bun run start`.
# Everything before `exec` must be idempotent — Clever restarts rerun it.
set -euo pipefail

log() { echo "[boot] $*" >&2; }

# gbrain infers engine=postgres from DATABASE_URL (src/core/config.ts).
export DATABASE_URL="${DATABASE_URL:-${POSTGRESQL_ADDON_URI:?POSTGRESQL_ADDON_URI missing — is the Postgres add-on linked?}}"

# File-plane config (Cellar storage block), pgvector extension, Cellar bucket.
log "preflight: config.json + pgvector + Cellar bucket"
bun run preflight.ts

GBRAIN="./node_modules/.bin/gbrain"

# Managed Postgres has no BYPASSRLS role; neuter gbrain's Supabase-specific
# RLS gates (see patch-rls.ts header for why this is safe here).
bun run patch-rls.ts

# Bun blocks gbrain's postinstall hook (gbrain #218) — run migrations here.
log "applying migrations"
"$GBRAIN" apply-migrations --yes

# Brain repo on the FS Bucket mount — persists across redeploys.
# CC_FS_BUCKET=/data:<host> mounts at $APP_HOME/data (mount points are
# relative to the application folder, never the filesystem root).
BRAIN_DIR="${GBRAIN_BRAIN_DIR:-${APP_HOME:-$PWD}/data/brain}"
if [ ! -d "$BRAIN_DIR/.git" ]; then
  log "initialising brain repo at $BRAIN_DIR"
  mkdir -p "$BRAIN_DIR"
  git -C "$BRAIN_DIR" init -q
fi
"$GBRAIN" sources add default --path "$BRAIN_DIR" --name "Brain" 2>/dev/null \
  || log "source 'default' already registered"

# Repopulate db_only files missing from disk (container-restart recovery).
"$GBRAIN" export --restore-only --repo "$BRAIN_DIR" \
  || log "restore-only skipped (empty brain is fine on first boot)"

# One-time-ish retrieval cost/quality setting; idempotent to re-set.
"$GBRAIN" config set search.mode "${GBRAIN_SEARCH_MODE:-balanced}" \
  || log "could not set search.mode (non-fatal)"

# Admin SPA: serve-http resolves admin/dist relative to cwd; gbrain ships
# the built assets inside the package — expose them where it looks.
ln -sfn node_modules/gbrain/admin admin

# Minion job worker: /ingest and every queued job sit in `waiting` forever
# without one. The supervisor spawns `gbrain jobs work` and auto-restarts
# it on crash (see docs/guides/minions-deployment.md).
"$GBRAIN" jobs supervisor start --detach --json --concurrency 2 \
  || log "worker supervisor failed to start (non-fatal)"

log "starting HTTP MCP server on :${PORT:-8080}"
exec "$GBRAIN" serve --http \
  --port "${PORT:-8080}" \
  --bind 0.0.0.0 \
  ${GBRAIN_PUBLIC_URL:+--public-url "$GBRAIN_PUBLIC_URL"}
