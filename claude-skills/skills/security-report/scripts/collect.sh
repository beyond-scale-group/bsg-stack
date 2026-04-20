#!/usr/bin/env bash
# collect.sh — one cross-ecosystem snapshot for the security-report skill.
#
# Auto-detects the package ecosystem (npm / pip / go / cargo), runs the
# available vulnerability tool, cross-checks with GitHub's Dependabot
# alerts, gathers tracked-file list for secret scanning, and inventories
# detectable HTTP-server config files. Emits a single JSON document on
# stdout that every reporter (deps.sh, secrets.sh, headers.sh) consumes
# with `--snapshot <path>`.
#
# Exits 0 on success, non-zero if the repo can't be located.

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

# ---------------------------------------------------------------- helpers

emit_jsonl_file() {
  # Read a possibly-missing JSON file, emit {} if missing/empty.
  local path=$1
  if [[ -s "$path" ]]; then
    cat "$path"
  else
    echo "{}"
  fi
}

json_null_if_empty() {
  local value=$1
  if [[ -z "$value" ]]; then
    echo "null"
  else
    printf '%s' "$value" | jq -Rs .
  fi
}

# ---------------------------------------------------------- ecosystems

ECOSYSTEMS=()
[[ -f package-lock.json || -f yarn.lock || -f pnpm-lock.yaml ]] && ECOSYSTEMS+=("node")
[[ -f Pipfile.lock || -f poetry.lock || -f requirements.txt ]]   && ECOSYSTEMS+=("python")
[[ -f go.sum || -f go.mod ]]                                     && ECOSYSTEMS+=("go")
[[ -f Cargo.lock ]]                                              && ECOSYSTEMS+=("rust")

NPM_AUDIT_JSON='{}'
if [[ " ${ECOSYSTEMS[*]} " == *" node "* ]] && command -v npm >/dev/null 2>&1; then
  NPM_AUDIT_JSON=$(npm audit --json 2>/dev/null || echo '{}')
fi

PIP_AUDIT_JSON='{}'
if [[ " ${ECOSYSTEMS[*]} " == *" python "* ]] && command -v pip-audit >/dev/null 2>&1; then
  PIP_AUDIT_JSON=$(pip-audit --format=json 2>/dev/null || echo '{}')
fi

# --------------------------------------------------------- gh dependabot

GHSA_JSON='[]'
if command -v gh >/dev/null 2>&1; then
  # Endpoint requires vulnerability-alerts to be enabled. Non-zero
  # exit just means "nothing to report" from our POV.
  GHSA_JSON=$(gh api /repos/{owner}/{repo}/dependabot/alerts --paginate 2>/dev/null || echo '[]')
fi

# ----------------------------------------------------------- tracked files

TRACKED_FILES_JSON=$(git ls-files 2>/dev/null | jq -Rn '[inputs]' || echo '[]')

# Files whose basename starts with .env — candidate leaked env files.
TRACKED_ENV_FILES_JSON=$(git ls-files 2>/dev/null \
  | awk -F/ '{base=$NF} base ~ /^\.env(\..+)?$/ {print}' \
  | jq -Rn '[inputs]' || echo '[]')

# .securityignore content (raw) for downstream reporters.
SECURITYIGNORE_JSON='""'
if [[ -f .securityignore ]]; then
  SECURITYIGNORE_JSON=$(jq -Rs . < .securityignore)
fi

# ---------------------------------------------------------- server kind

SERVER_KIND="unknown"
SERVER_APPLICABLE="false"
if [[ -f nginx.conf ]] || find . -maxdepth 3 -type f \( -name 'nginx.conf' -o -path '*/nginx/*.conf' \) 2>/dev/null | grep -q . ; then
  SERVER_KIND="nginx"; SERVER_APPLICABLE="true"
elif [[ -f apache2.conf || -f httpd.conf || -f .htaccess ]]; then
  SERVER_KIND="apache"; SERVER_APPLICABLE="true"
elif [[ -f Caddyfile ]]; then
  SERVER_KIND="caddy"; SERVER_APPLICABLE="true"
elif [[ -f vercel.json ]]; then
  SERVER_KIND="vercel"; SERVER_APPLICABLE="true"
elif [[ -f netlify.toml ]]; then
  SERVER_KIND="netlify"; SERVER_APPLICABLE="true"
elif [[ -f clevercloud.json ]]; then
  SERVER_KIND="clevercloud"; SERVER_APPLICABLE="true"
elif grep -RlE "require\(['\"]express['\"]\)|from ['\"]express['\"]|import express|fastify|koa|hono" \
        --include='*.js' --include='*.ts' --include='*.mjs' . 2>/dev/null | head -1 | grep -q . ; then
  SERVER_KIND="express"; SERVER_APPLICABLE="true"
elif grep -RlE "Flask|Django|from wsgi|from asgi|FastAPI" --include='*.py' . 2>/dev/null | head -1 | grep -q . ; then
  SERVER_KIND="python-web"; SERVER_APPLICABLE="true"
fi

# ---------------------------------------------------------- emit

jq -n \
  --arg repoRoot "$REPO_ROOT" \
  --arg generatedAt "$(date -u +%FT%TZ)" \
  --argjson ecosystems "$(printf '%s\n' "${ECOSYSTEMS[@]:-}" | jq -Rn '[inputs | select(length>0)]')" \
  --argjson npmAudit "$NPM_AUDIT_JSON" \
  --argjson pipAudit "$PIP_AUDIT_JSON" \
  --argjson ghsa "$GHSA_JSON" \
  --argjson trackedFiles "$TRACKED_FILES_JSON" \
  --argjson trackedEnvFiles "$TRACKED_ENV_FILES_JSON" \
  --argjson securityIgnore "$SECURITYIGNORE_JSON" \
  --arg serverKind "$SERVER_KIND" \
  --arg serverApplicable "$SERVER_APPLICABLE" \
  '{
    repoRoot: $repoRoot,
    generatedAt: $generatedAt,
    ecosystems: $ecosystems,
    deps: {
      npmAudit: $npmAudit,
      pipAudit: $pipAudit,
      dependabotAlerts: $ghsa
    },
    files: {
      tracked: $trackedFiles,
      envFiles: $trackedEnvFiles
    },
    securityIgnore: $securityIgnore,
    server: {
      applicable: ($serverApplicable == "true"),
      kind: $serverKind
    }
  }'
