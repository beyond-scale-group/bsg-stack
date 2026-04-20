#!/usr/bin/env bash
# talking-points.sh — draft talking-point stubs for unnarrated releases.

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
  SNAPSHOT=$(mktemp -t brand-snap.XXXXXX.json)
  trap 'rm -f "$SNAPSHOT"' EXIT
  SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
  bash "$SCRIPT_DIR/collect.sh" > "$SNAPSHOT"
fi

REPO_ROOT=$(jq -r '.repoRoot' "$SNAPSHOT")
TODAY=$(date +%F)

# Unnarrated = releases with no existing talking-point file containing
# the release tag.
UNNARRATED_JSON=$(jq '
  (.releases // []) as $releases
  | (.talkingPoints // []) as $tps
  | [ $releases[] as $r
      | select(
          [ $tps[] | select((.release // "") == $r.tag or (.file | contains($r.tag))) ] | length == 0
        )
    ]
' "$SNAPSHOT")

PLAN_JSON=$(jq -c --arg today "$TODAY" '
  [ .[]
    | (.tag | sub("^v"; "")) as $stripped
    | (.title | ascii_downcase | gsub("[^a-z0-9]+"; "-") | sub("-+$"; "")) as $slug
    | (.publishedAt // $today | split("T")[0]) as $date
    | {
        release: .tag,
        title: .title,
        publishedAt: .publishedAt,
        path: ("brand/talking-points/" + $date + "-v" + $stripped + "-" + $slug + ".md")
      }
  ]
' <<<"$UNNARRATED_JSON")

GENERATED_JSON='[]'
if [[ "$WRITE" == "true" ]]; then
  mkdir -p "$REPO_ROOT/brand/talking-points"
  tone_target=$(jq -r '.narrative.toneTarget' "$SNAPSHOT")
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    path=$(jq -r '.path' <<<"$entry")
    release=$(jq -r '.release' <<<"$entry")
    title=$(jq -r '.title' <<<"$entry")
    publishedAt=$(jq -r '.publishedAt' <<<"$entry")
    full="$REPO_ROOT/$path"
    if [[ ! -f "$full" ]]; then
      {
        printf -- '---\nrelease: %s\npublishedAt: %s\nstatus: draft\n---\n\n' "$release" "$publishedAt"
        printf '# Talking Points — %s %s\n\n' "$release" "$title"
        printf '## Headline\n_(One line the team leads with. User benefit first.)_\n\n'
        printf '## Core message\n_(One paragraph to reuse verbatim across assets.)_\n\n'
        printf '## Key quotes\n- _(Quote 1 — founder)_\n- _(Quote 2 — engineering)_\n\n'
        printf '## Voice notes\n- Tone target: %s\n- Preferred framing: user value first, mechanism second\n\n' "$tone_target"
        printf '## Distribution\n- [ ] Changelog entry\n- [ ] Blog post\n- [ ] Landing-page update\n- [ ] Social post(s)\n\n'
        printf -- '---\n\n*Auto-drafted by @storytelling on %s from release %s notes. Human review required.*\n' "$TODAY" "$release"
      } > "$full"
      GENERATED_JSON=$(jq --argjson e "$entry" '. + [$e]' <<<"$GENERATED_JSON")
    fi
  done < <(jq -c '.[]' <<<"$PLAN_JSON")
fi

jq -n \
  --argjson plan "$PLAN_JSON" \
  --argjson generated "$GENERATED_JSON" \
  --argjson existing "$(jq '.talkingPoints' "$SNAPSHOT")" \
  --argjson unnarrated "$UNNARRATED_JSON" \
  --arg today "$TODAY" \
  --arg write "$WRITE" \
  '{
    plan: $plan,
    generated: $generated,
    writeMode: ($write == "true"),
    existing: $existing,
    unnarratedReleases: [ $unnarrated[] | { release: .tag, publishedAt: .publishedAt } ]
  }'
