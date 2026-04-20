#!/usr/bin/env bash
# collect.sh — brand narrative snapshot.
#
# Parses brand/NARRATIVE.md, enumerates public-facing assets, computes
# voice signals (words / sentences / passive / jargon / Flesch).

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

NARRATIVE_PATH="brand/NARRATIVE.md"
NARRATIVE_FOUND="false"

# --------------------------------------------- narrative parsing

TONE_TARGET="7.0"
KEY_MESSAGES_JSON='[]'
BANNED_TERMS_JSON='[]'
PREFERRED_TERMS_JSON='[]'
CATEGORY=""
AUDIENCE=""
DIFFERENTIATORS_JSON='[]'
FEATURE_ANCHORS_JSON='[]'

if [[ -f "$NARRATIVE_PATH" ]]; then
  NARRATIVE_FOUND="true"

  # Tone target (e.g. "**Tone target:** 7.0")
  t=$(grep -m1 -iE '\*\*Tone target:\*\*[[:space:]]*[0-9]+(\.[0-9]+)?' "$NARRATIVE_PATH" 2>/dev/null || true)
  if [[ -n "$t" ]]; then
    TONE_TARGET=$(echo "$t" | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)
  fi

  extract_section_bullets() {
    local title=$1
    awk -v title="$title" '
      $0 ~ "^## " title "[[:space:]]*$" { in_section=1; next }
      in_section && /^## / { in_section=0 }
      in_section && /^[0-9]+\.[[:space:]]/ { sub(/^[0-9]+\.[[:space:]]+/, ""); print }
      in_section && /^-[[:space:]]/       { sub(/^-[[:space:]]+/, ""); print }
    ' "$NARRATIVE_PATH"
  }

  extract_kv_sublines() {
    local title=$1
    local key=$2
    awk -v title="$title" -v key="$key" '
      $0 ~ "^## " title "[[:space:]]*$" { in_section=1; next }
      in_section && /^## / { in_section=0 }
      in_section && $0 ~ "\\*\\*" key ":\\*\\*" {
        sub(".*\\*\\*" key ":\\*\\*[[:space:]]*", "")
        print
      }
    ' "$NARRATIVE_PATH"
  }

  KEY_MESSAGES_JSON=$(extract_section_bullets "Key Messages" | jq -Rn '[inputs | select(length>0)]' 2>/dev/null || echo '[]')
  DIFFERENTIATORS_JSON=$(extract_section_bullets "Value Proposition" | jq -Rn '[inputs | select(length>0)]' 2>/dev/null || echo '[]')

  BANNED_RAW=$(extract_kv_sublines "Voice Guidelines" "Banned vocabulary" || true)
  BANNED_TERMS_JSON=$(echo "$BANNED_RAW" | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | grep -v '^$' | jq -Rn '[inputs]' 2>/dev/null || echo '[]')

  PREF_RAW=$(extract_kv_sublines "Voice Guidelines" "Preferred vocabulary" || true)
  PREFERRED_TERMS_JSON=$(echo "$PREF_RAW" | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | grep -v '^$' | jq -Rn '[inputs]' 2>/dev/null || echo '[]')

  CATEGORY=$(extract_kv_sublines "Positioning" "Category" | head -1 || true)
  AUDIENCE=$(extract_kv_sublines "Positioning" "Target audience" | head -1 || true)
  FEATURE_ANCHORS_JSON=$(extract_kv_sublines "Positioning" "Feature anchors" | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | grep -v '^$' | jq -Rn '[inputs]' 2>/dev/null || echo '[]')
fi

# --------------------------------------------- jargon baseline

# Short static list of common "corporate" / marketing jargon that
# voice.sh will count as density. Banned-term matches stack on top.
BASE_JARGON=(synergy leverage paradigm robust seamless holistic \
  actionable scalable disruptive best-in-class world-class \
  cutting-edge next-generation enterprise-grade)

# ------------------------------------------ public-facing assets

ASSET_PATHS=()
[[ -f README.md ]] && ASSET_PATHS+=("README.md")
[[ -f CHANGELOG.md ]] && ASSET_PATHS+=("CHANGELOG.md")
if [[ -d docs ]]; then
  while IFS= read -r f; do
    ASSET_PATHS+=("$f")
  done < <(find docs -type f -name '*.md' 2>/dev/null | head -30)
fi
if [[ -d marketing ]]; then
  while IFS= read -r f; do
    ASSET_PATHS+=("$f")
  done < <(find marketing -type f -name '*.md' 2>/dev/null | head -30)
fi
if [[ -d blog ]] || [[ -d src/content/blog ]]; then
  while IFS= read -r f; do
    ASSET_PATHS+=("$f")
  done < <({ find blog src/content/blog -type f -name '*.md' 2>/dev/null || true; } | head -30)
fi

# -------------------------------- voice signals per asset

compute_signals() {
  local f=$1
  [[ -f "$f" ]] || return

  # Strip markdown syntax (heuristic: code fences, inline code, links).
  local text
  text=$(awk '
    BEGIN { in_code=0 }
    /^```/ { in_code = !in_code; next }
    { if (!in_code) print }
  ' "$f" \
    | sed -E 's/`[^`]*`//g' \
    | sed -E 's/!\[[^]]*\]\([^)]*\)//g' \
    | sed -E 's/\[([^]]+)\]\([^)]*\)/\1/g' \
    | sed -E 's/^#+[[:space:]]*//g')

  local words sentences
  words=$(echo "$text" | wc -w | tr -d ' ')
  sentences=$(echo "$text" | grep -oE '[.!?]' | wc -l | tr -d ' ')
  [[ "$sentences" -lt 1 ]] && sentences=1

  local passive_count
  passive_count=$(echo "$text" \
    | grep -iE '\b(is|are|was|were|be|been|being)\b[[:space:]]+[a-z]+ed\b' \
    | wc -l | tr -d ' ')

  # Jargon: base list + banned terms from bible.
  local jargon_count=0
  for term in "${BASE_JARGON[@]}"; do
    local c
    c=$(echo "$text" | grep -icE "\\b${term}\\b" || true)
    jargon_count=$(( jargon_count + c ))
  done
  while IFS= read -r banned; do
    [[ -z "$banned" ]] && continue
    local c
    c=$(echo "$text" | grep -icE "\\b${banned}\\b" 2>/dev/null || true)
    jargon_count=$(( jargon_count + c ))
  done < <(jq -r '.[]?' <<<"$BANNED_TERMS_JSON")

  # Rough syllable count: vowel groups per word.
  local syllables
  syllables=$(echo "$text" | tr '[:upper:]' '[:lower:]' \
    | grep -oE '[aeiouy]+' | wc -l | tr -d ' ')

  # Flesch reading ease — guard against zero words.
  local flesch="0"
  if [[ "$words" -gt 0 ]]; then
    flesch=$(awk -v w="$words" -v s="$sentences" -v sy="$syllables" \
      'BEGIN { printf "%.2f", 206.835 - 1.015*(w/s) - 84.6*(sy/w) }')
  fi

  jq -nc \
    --arg file "$f" \
    --argjson words "$words" \
    --argjson sentences "$sentences" \
    --argjson passive "$passive_count" \
    --argjson jargon "$jargon_count" \
    --argjson syllables "$syllables" \
    --argjson flesch "$flesch" \
    '{
      file: $file,
      words: $words,
      sentences: $sentences,
      sentenceAvg: (if $sentences == 0 then 0 else ($words / $sentences * 100 | floor / 100) end),
      passiveCount: $passive,
      passiveRatio: (if $sentences == 0 then 0 else ($passive / $sentences * 100 | floor / 100) end),
      jargonCount: $jargon,
      jargonDensity: (if $words == 0 then 0 else ($jargon / $words * 1000 | floor / 1000) end),
      fleschEase: $flesch
    }'
}

ASSETS_JSON='[]'
for f in "${ASSET_PATHS[@]:-}"; do
  [[ -z "$f" ]] && continue
  entry=$(compute_signals "$f" || true)
  [[ -z "$entry" ]] && continue
  ASSETS_JSON=$(jq --argjson e "$entry" '. + [$e]' <<<"$ASSETS_JSON")
done

# -------------------------------- releases

RELEASES_JSON='[]'
if command -v gh >/dev/null 2>&1; then
  RELEASES_JSON=$(gh release list --limit 20 \
    --json tagName,name,publishedAt,isDraft,isPrerelease,body 2>/dev/null \
    | jq '[.[] | select(.isDraft == false and .isPrerelease == false) |
        { tag: .tagName, title: (.name // .tagName), publishedAt: .publishedAt, body: (.body // "") }]' \
      2>/dev/null || echo '[]')
fi

# -------------------------------- existing talking points

TP_JSON='[]'
if [[ -d brand/talking-points ]]; then
  TP_JSON=$(find brand/talking-points -type f -name '*.md' 2>/dev/null | while IFS= read -r f; do
    release=$(grep -m1 -E '^release:' "$f" 2>/dev/null | sed -E 's/release:[[:space:]]*//' || echo "")
    status=$(grep -m1 -E '^status:' "$f" 2>/dev/null | sed -E 's/status:[[:space:]]*//' || echo "unknown")
    jq -nc --arg file "$f" --arg release "$release" --arg status "$status" \
      '{file: $file, release: $release, status: $status}'
  done | jq -sc '.' 2>/dev/null || echo '[]')
fi

# ---------------------------------------------------------- emit

jq -n \
  --arg repoRoot "$REPO_ROOT" \
  --arg generatedAt "$(date -u +%FT%TZ)" \
  --arg narrativePath "$NARRATIVE_PATH" \
  --arg narrativeFound "$NARRATIVE_FOUND" \
  --arg toneTarget "$TONE_TARGET" \
  --argjson keyMessages "$KEY_MESSAGES_JSON" \
  --argjson bannedTerms "$BANNED_TERMS_JSON" \
  --argjson preferredTerms "$PREFERRED_TERMS_JSON" \
  --arg category "$CATEGORY" \
  --arg audience "$AUDIENCE" \
  --argjson differentiators "$DIFFERENTIATORS_JSON" \
  --argjson featureAnchors "$FEATURE_ANCHORS_JSON" \
  --argjson assets "$ASSETS_JSON" \
  --argjson releases "$RELEASES_JSON" \
  --argjson talkingPoints "$TP_JSON" \
  '{
    repoRoot: $repoRoot,
    generatedAt: $generatedAt,
    narrative: {
      path: $narrativePath,
      found: ($narrativeFound == "true"),
      toneTarget: ($toneTarget | tonumber),
      keyMessages: $keyMessages,
      bannedTerms: $bannedTerms,
      preferredTerms: $preferredTerms,
      positioning: {
        category: $category,
        audience: $audience,
        differentiators: $differentiators,
        featureAnchors: $featureAnchors
      }
    },
    assets: $assets,
    releases: $releases,
    talkingPoints: $talkingPoints
  }'
