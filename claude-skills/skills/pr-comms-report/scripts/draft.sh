#!/usr/bin/env bash
# draft.sh — generate press-release stubs for unannounced major/minor releases.

set -euo pipefail

SNAPSHOT=""
WRITE=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --snapshot) SNAPSHOT="$2"; shift 2 ;;
    --write)    WRITE=true;   shift   ;;
    *) shift ;;
  esac
done

if [[ -z "$SNAPSHOT" ]]; then
  SNAPSHOT=$(mktemp -t comms-snap.XXXXXX.json)
  trap 'rm -f "$SNAPSHOT"' EXIT
  SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
  bash "$SCRIPT_DIR/collect.sh" > "$SNAPSHOT"
fi

REPO_ROOT=$(jq -r '.repoRoot' "$SNAPSHOT")
VISIBILITY=$(jq -r '.visibility' "$SNAPSHOT")
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

EVENTS=$(bash "$SCRIPT_DIR/events.sh" --snapshot "$SNAPSHOT")
UNANNOUNCED_JSON=$(jq '.unannouncedMajor' <<<"$EVENTS")

PLAN_JSON=$(jq -c '
  [ .[]
    | (.release | sub("^v"; "")) as $stripped
    | (.title | ascii_downcase | gsub("[^a-z0-9]+"; "-") | sub("-+$"; "")) as $slug
    | (.publishedAt // "unknown" | split("T")[0]) as $date
    | {
        release: .release,
        title: .title,
        publishedAt: .publishedAt,
        type: .type,
        priority: .priority,
        path: ("comms/press-releases/" + $date + "-v" + $stripped + "-" + $slug + ".md")
      }
  ]
' <<<"$UNANNOUNCED_JSON")

# Pull boilerplate (if available).
BOILERPLATE_CONTENT=""
if [[ -f "$REPO_ROOT/comms/press-kit/boilerplate.md" ]]; then
  BOILERPLATE_CONTENT=$(cat "$REPO_ROOT/comms/press-kit/boilerplate.md")
fi
CONTACT_CONTENT=""
if [[ -f "$REPO_ROOT/comms/press-kit/contact.md" ]]; then
  CONTACT_CONTENT=$(cat "$REPO_ROOT/comms/press-kit/contact.md")
fi

GENERATED_JSON='[]'
if [[ "$WRITE" == "true" ]]; then
  mkdir -p "$REPO_ROOT/comms/press-releases"
  TODAY=$(date +%F)
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    path=$(jq -r '.path' <<<"$entry")
    release=$(jq -r '.release' <<<"$entry")
    title=$(jq -r '.title' <<<"$entry")
    publishedAt=$(jq -r '.publishedAt' <<<"$entry")
    full="$REPO_ROOT/$path"
    [[ -f "$full" ]] && continue
    confidential="false"
    if [[ "$VISIBILITY" == "private" ]]; then
      confidential="true"
    fi
    {
      printf -- '---\nrelease: %s\npublishedAt: %s\nstatus: draft\nconfidential: %s\n---\n\n' \
        "$release" "$publishedAt" "$confidential"
      if [[ "$confidential" == "true" ]]; then
        printf '> **CONFIDENTIAL — review before publishing.**\n\n'
      fi
      printf '# Press Release — %s %s\n\n' "$release" "$title"
      printf '## Headline\n_(One line. What changed that the world cares about.)_\n\n'
      printf '## Lead paragraph\n_(Company) today announced %s, introducing %s._ _(Continue with one more sentence of context.)_\n\n' "$release" "$title"
      printf '## Supporting paragraph\n_(Expand on user value. What can the user now do that they couldn'\''t before?)_\n\n'
      printf '## Quote\n> _(Founder / product lead quote. The agent will not write this.)_\n\n'
      printf '## Boilerplate\n'
      if [[ -n "$BOILERPLATE_CONTENT" ]]; then
        printf '%s\n\n' "$BOILERPLATE_CONTENT"
      else
        printf '_(Create `comms/press-kit/boilerplate.md` to inline company description here.)_\n\n'
      fi
      printf '## Contact\n'
      if [[ -n "$CONTACT_CONTENT" ]]; then
        printf '%s\n\n' "$CONTACT_CONTENT"
      else
        printf '_(Create `comms/press-kit/contact.md` with press contact name + email.)_\n\n'
      fi
      printf -- '---\n\n*Auto-drafted by @pr-comms on %s from release %s. Human review required before external distribution.*\n' "$TODAY" "$release"
    } > "$full"
    GENERATED_JSON=$(jq --argjson e "$entry" '. + [$e]' <<<"$GENERATED_JSON")
  done < <(jq -c '.[]' <<<"$PLAN_JSON")
fi

jq -n \
  --argjson plan "$PLAN_JSON" \
  --argjson generated "$GENERATED_JSON" \
  --argjson existing "$(jq '.existingDrafts' "$SNAPSHOT")" \
  --arg visibility "$VISIBILITY" \
  --arg write "$WRITE" \
  '{
    plan: $plan,
    generated: $generated,
    existing: $existing,
    confidential: ($visibility == "private"),
    writeMode: ($write == "true")
  }'
