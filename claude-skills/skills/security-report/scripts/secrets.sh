#!/usr/bin/env bash
# secrets.sh — scan tracked files for secret patterns.
#
# Reads tracked-file list from the snapshot, applies a regex catalog,
# respects .securityignore, and emits findings[] + trackedEnvFiles[]
# lists.

set -euo pipefail

SNAPSHOT=""
REDACT=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --snapshot) SNAPSHOT="$2"; shift 2 ;;
    --redact)   REDACT=true;   shift   ;;
    *) shift ;;
  esac
done

if [[ -z "$SNAPSHOT" ]]; then
  SNAPSHOT=$(mktemp -t security-snap.XXXXXX.json)
  trap 'rm -f "$SNAPSHOT"' EXIT
  SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
  bash "$SCRIPT_DIR/collect.sh" > "$SNAPSHOT"
fi

REPO_ROOT=$(jq -r '.repoRoot' "$SNAPSHOT")
cd "$REPO_ROOT"

# Pattern catalog. Keep entries as "<kind>|<regex>" so bash arrays handle
# whitespace safely.
PATTERNS=(
  "AWS Access Key ID|AKIA[0-9A-Z]{16}"
  "AWS Secret Access Key|aws_secret_access_key[[:space:]]*=[[:space:]]*[A-Za-z0-9/+=]{40}"
  "GitHub personal token|ghp_[A-Za-z0-9]{36}"
  "GitHub server token|ghs_[A-Za-z0-9]{36}"
  "OpenAI/Anthropic API key|sk-[A-Za-z0-9]{20,}"
  "Slack bot token|xoxb-[0-9A-Za-z-]+"
  "Private key|-----BEGIN (RSA|OPENSSH|EC) PRIVATE KEY-----"
)

# Collect the list of files to skip and per-pattern exclusions from
# .securityignore.
SKIP_FILES_TMP=$(mktemp); trap 'rm -f "$SKIP_FILES_TMP"' EXIT
PATTERN_SKIPS_TMP=$(mktemp)
if jq -e '.securityignore | length > 0' "$SNAPSHOT" >/dev/null; then
  jq -r '.securityignore' "$SNAPSHOT" | while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    if [[ "$line" =~ ^pattern:[[:space:]]*(.+)[[:space:]]+in[[:space:]]+(.+)$ ]]; then
      echo "${BASH_REMATCH[1]}|${BASH_REMATCH[2]}" >> "$PATTERN_SKIPS_TMP"
    else
      echo "$line" >> "$SKIP_FILES_TMP"
    fi
  done
fi

FINDINGS_JSON="[]"

# Write tracked files list to a temp file to avoid a subshell that would
# lose findings accumulated in a pipe.
TRACKED_LIST=$(mktemp); trap 'rm -f "$TRACKED_LIST"' EXIT
jq -r '.files.tracked[]' "$SNAPSHOT" > "$TRACKED_LIST"

SCANNED=0
while IFS= read -r file; do
  [[ -f "$file" ]] || continue

  # Skip explicit .securityignore globs (naive prefix match).
  skip=0
  while IFS= read -r skip_pat; do
    [[ -z "$skip_pat" ]] && continue
    case "$file" in $skip_pat) skip=1; break ;; esac
  done < "$SKIP_FILES_TMP"
  [[ $skip -eq 1 ]] && continue

  SCANNED=$((SCANNED + 1))

  for entry in "${PATTERNS[@]}"; do
    kind="${entry%%|*}"
    regex="${entry#*|}"

    # grep -I skips binaries, -n adds line numbers, -H adds filename, -E extended regex.
    matches=$(grep -IHnE "$regex" "$file" 2>/dev/null || true)
    [[ -z "$matches" ]] && continue

    while IFS= read -r m; do
      # Format: <file>:<line>:<content>
      line_no=$(echo "$m" | awk -F: 'NR==1 {print $2}')
      content=$(echo "$m" | sed -E "s/^[^:]+:[0-9]+://")
      match_text=$(echo "$content" | grep -oE "$regex" | head -1)

      # Check pattern-scoped .securityignore exclusions.
      excluded=0
      while IFS='|' read -r pat pfile; do
        [[ -z "$pat" ]] && continue
        if [[ "$file" == "$pfile" && "$match_text" == *"$pat"* ]]; then
          excluded=1; break
        fi
      done < "$PATTERN_SKIPS_TMP"
      [[ $excluded -eq 1 ]] && continue

      if [[ "$REDACT" == true && ${#match_text} -gt 8 ]]; then
        head="${match_text:0:4}"
        tail="${match_text: -4}"
        match_text="${head}***${tail}"
      fi

      FINDINGS_JSON=$(jq --arg file "$file" --argjson line "$line_no" \
                         --arg kind "$kind" --arg match "$match_text" \
        '. + [{file: $file, line: $line, kind: $kind, match: $match}]' \
        <<<"$FINDINGS_JSON")
    done <<< "$matches"
  done
done < "$TRACKED_LIST"

TRACKED_ENV=$(jq '.files.envFiles' "$SNAPSHOT")

jq -n --argjson findings "$FINDINGS_JSON" \
      --argjson trackedEnv "$TRACKED_ENV" \
      --argjson scanned "$SCANNED" '
  {
    summary: {
      findings: ($findings | length),
      trackedEnvFiles: ($trackedEnv | length),
      scannedFiles: $scanned
    },
    findings: $findings,
    trackedEnvFiles: $trackedEnv
  }
'
