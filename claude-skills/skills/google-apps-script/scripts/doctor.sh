#!/usr/bin/env bash
set -euo pipefail

# Health check for clasp / Google Apps Script setup.
# Exit codes: 0 = healthy, 1 = warnings, 2 = broken.
# Usage:
#   bash doctor.sh           # full report
#   bash doctor.sh --quiet   # exit codes only

QUIET=false
[ "${1:-}" = "--quiet" ] && QUIET=true

warnings=0
errors=0

check() {
  local label="$1" status="$2" detail="${3:-}"
  if [ "$status" = "ok" ]; then
    $QUIET || echo "  ✓ $label${detail:+ — $detail}"
  elif [ "$status" = "warn" ]; then
    warnings=$((warnings + 1))
    $QUIET || echo "  ⚠ $label${detail:+ — $detail}"
  else
    errors=$((errors + 1))
    $QUIET || echo "  ✗ $label${detail:+ — $detail}"
  fi
}

$QUIET || echo "Google Apps Script (clasp) health check"
$QUIET || echo "========================================"

# 1. Binary
if command -v clasp >/dev/null 2>&1; then
  ver=$(clasp --version 2>/dev/null || echo "unknown")
  check "clasp binary" ok "$ver"
else
  check "clasp binary" err "not found — npm install -g @google/clasp"
fi

# 2. Auth — resolve credentials file: CLASP_AUTH > local > global
if [ -n "${CLASP_AUTH:-}" ]; then
  creds_file="$CLASP_AUTH"
elif [ -f .clasprc.json ]; then
  creds_file=".clasprc.json"
else
  creds_file="$HOME/.clasprc.json"
fi

if [ -f "$creds_file" ]; then
  check "credentials" ok "$creds_file exists"
else
  check "credentials" err "missing ($creds_file) — run: clasp login"
fi

# 3. Project binding (optional — only relevant inside a project dir)
if [ -f .clasp.json ]; then
  script_id=$(grep -o '"scriptId"[[:space:]]*:[[:space:]]*"[^"]*"' .clasp.json 2>/dev/null | head -1 | sed 's/.*"scriptId"[[:space:]]*:[[:space:]]*"//' | sed 's/"//')
  if [ -n "$script_id" ]; then
    check "project binding" ok "scriptId=${script_id:0:12}..."
  else
    check "project binding" warn ".clasp.json exists but no scriptId found"
  fi
else
  check "project binding" ok "no .clasp.json (not inside a project — normal)"
fi

# 4. Manifest
if [ -f appsscript.json ]; then
  check "manifest" ok "appsscript.json present"
else
  if [ -f .clasp.json ]; then
    check "manifest" warn "missing appsscript.json (run clasp pull)"
  else
    check "manifest" ok "no manifest (not inside a project — normal)"
  fi
fi

# 5. Node / npm
if command -v node >/dev/null 2>&1; then
  check "node" ok "$(node --version 2>/dev/null)"
else
  check "node" err "node not found"
fi

if command -v npm >/dev/null 2>&1; then
  check "npm" ok "$(npm --version 2>/dev/null)"
else
  check "npm" err "npm not found"
fi

# 6. TypeScript types (optional)
if [ -f package.json ] && grep -q '@types/google-apps-script' package.json 2>/dev/null; then
  check "TS types" ok "@types/google-apps-script installed"
elif [ -f .clasp.json ]; then
  check "TS types" warn "@types/google-apps-script not found — npm install -D @types/google-apps-script"
fi

# Summary
$QUIET || echo ""
if [ "$errors" -gt 0 ]; then
  $QUIET || echo "Result: $errors error(s), $warnings warning(s)"
  exit 2
elif [ "$warnings" -gt 0 ]; then
  $QUIET || echo "Result: $warnings warning(s)"
  exit 1
else
  $QUIET || echo "Result: all green"
  exit 0
fi
