# _bsg-paths.sh — shared path resolution for BSG agent infrastructure.
#
# Sourced (not executed) by other scripts. Resolves every per-repo
# custom doc and the autopilot config to either the new `.bsg/`
# convention from ADR-001 or its legacy fallback path.
#
# Two surfaces:
#   1. `BSG_AUTOPILOT_FILE` env var — autopilot config (most common
#      caller pattern; pre-resolved at source time so `[[ -f
#      "$BSG_AUTOPILOT_FILE" ]]` doubles as a presence test).
#   2. `bsg_doc_path <kind>` function — resolves any custom doc to its
#      preferred path. Returns the `.bsg/` path if it exists, otherwise
#      the legacy path so callers can still presence-test the result.
#
# Resolution order for every doc is identical: prefer `.bsg/<NAME>` if
# it exists on disk, else the agent's legacy folder if THAT exists,
# else the `.bsg/` path unconditionally so first-write callers (like
# per-agent `--init`) land in the new tree without further wiring.
# Either return value is safe for `[[ -f "$path" ]]` presence tests.
#
# Usage from a sibling script:
#
#     # shellcheck source=_bsg-paths.sh disable=SC1091
#     source "$(dirname "${BASH_SOURCE[0]}")/_bsg-paths.sh"
#     plan="$(bsg_doc_path plan)"
#     [[ -f "$plan" ]] || { echo "no PLAN.md" >&2; exit 1; }
#
# Idempotent — sourcing twice does no harm.

# bsg_doc_path <kind> — print the preferred path for a known custom-doc
# kind. Adding a new doc is a one-line addition to the case below.
bsg_doc_path() {
  local kind="$1" new legacy
  case "$kind" in
    autopilot)     new=".bsg/AUTOPILOT.yml";    legacy=".bsg-autopilot.yml" ;;
    plan)          new=".bsg/PLAN.md";          legacy="po/PLAN.md" ;;
    narrative)     new=".bsg/NARRATIVE.md";     legacy="brand/NARRATIVE.md" ;;
    keywords)      new=".bsg/KEYWORDS.md";      legacy="seo/KEYWORDS.md" ;;
    calendar)      new=".bsg/CALENDAR.md";      legacy="marketing/CALENDAR.md" ;;
    announced)     new=".bsg/ANNOUNCED.md";     legacy="comms/ANNOUNCED.md" ;;
    securityignore) new=".bsg/SECURITYIGNORE";  legacy=".securityignore" ;;
    design)        new=".bsg/DESIGN.md";        legacy="" ;;  # net-new, ADR-003 (no legacy path)
    adr)           new=".bsg/adr";              legacy="adr" ;;
    brand)         new=".bsg/brand";            legacy="brand" ;;
    reports)       new=".bsg/reports";          legacy="" ;;
    *)
      echo "bsg_doc_path: unknown doc kind '$kind'" >&2
      return 2
      ;;
  esac
  # Resolution order: .bsg/ if it exists, else legacy if it exists,
  # else .bsg/ unconditionally so first writes go into the new tree.
  if [[ -e "$new" ]]; then
    printf '%s\n' "$new"
  elif [[ -n "$legacy" && -e "$legacy" ]]; then
    printf '%s\n' "$legacy"
  else
    printf '%s\n' "$new"
  fi
}

# bsg_autopilot_file — back-compat alias for the most common caller.
bsg_autopilot_file() {
  bsg_doc_path autopilot
}

BSG_AUTOPILOT_FILE="$(bsg_autopilot_file)"
export BSG_AUTOPILOT_FILE
