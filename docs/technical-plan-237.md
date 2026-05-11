# Technical Plan: #237 Implementation

**Issue:** #237  
**Date:** 2026-05-05  
**Estimated scope:** ~15 PRs, ~2500 LOC net additions

## Architecture

```
claude-skills/scripts/_bsg-paths.sh       ← universal path resolver (Phase 1)
     ↑ sourced by
claude-skills/scripts/*.sh                ← all scripts use resolved paths
claude-skills/skills/*/scripts/init-*.sh  ← per-agent init scripts (Phase 2)
     ↑ orchestrated by
claude-skills/skills/bsg-stack/scripts/   ← init.sh, update.sh, status.sh (Phase 3)
```

## Phase 1: Universal Path Resolution Layer

**PR:** 1 (self-contained)  
**Files modified:** 1 modified, 5-6 consumers updated  
**Estimated LOC:** ~120

### Changes to `claude-skills/scripts/_bsg-paths.sh`

Extend from single AUTOPILOT resolver to a universal resolver exporting:

```bash
BSG_PLAN_FILE         # .bsg/PLAN.md | po/PLAN.md
BSG_NARRATIVE_FILE    # .bsg/NARRATIVE.md | brand/NARRATIVE.md
BSG_KEYWORDS_FILE     # .bsg/KEYWORDS.md | seo/KEYWORDS.md
BSG_CALENDAR_FILE     # .bsg/CALENDAR.md | marketing/CALENDAR.md
BSG_ANNOUNCED_FILE    # .bsg/ANNOUNCED.md | comms/ANNOUNCED.md
BSG_SECURITYIGNORE    # .bsg/SECURITYIGNORE | .securityignore
BSG_ADR_DIR           # .bsg/adr/ | adr/
BSG_REPORT_DIR        # .bsg/reports/<agent>/ | <agent>/reports/
BSG_AUTOPILOT_FILE    # .bsg/AUTOPILOT.yml | .bsg-autopilot.yml (existing)
```

Each resolved via a `bsg_resolve()` function:
```bash
bsg_resolve() {
  local new_path="$1" legacy_path="$2"
  if [[ -e "$new_path" ]]; then echo "$new_path"
  elif [[ -n "$legacy_path" && -e "$legacy_path" ]]; then echo "$legacy_path"
  else echo "$new_path"  # default to new path for writes
  fi
}
```

Additionally export a `bsg_report_dir()` function that takes an agent bus
label and returns the correct report directory:

```bash
bsg_report_dir() {
  local bus="$1"
  bsg_resolve ".bsg/reports/$bus" "$bus/reports"
}
```

### Consumer updates

| File | Change |
|---|---|
| `claude-skills/scripts/validate-plan.sh` | Default `PLAN_PATH` from `$BSG_PLAN_FILE` |
| `claude-skills/skills/po/scripts/parse-plan.sh` | Default from `$BSG_PLAN_FILE` |
| `claude-skills/skills/po/scripts/reconcile-milestones.sh` | Source resolver |
| `claude-skills/skills/po/scripts/bootstrap-plan.sh` | Reference new path in output |
| `claude-skills/skills/po/scripts/adherence.sh` | Use `$BSG_PLAN_FILE` |
| `claude-skills/scripts/tick-fingerprint.sh` | Accept `bsg_report_dir` output |

### Key design decision: `tick-fingerprint.sh` report path

Currently: `REPORT_FILE="${REPO_ROOT}/${REPORT_DIR}/reports/${SLUG}.md"`

The `REPORT_DIR` arg is the agent's top-level folder (e.g., `po`), and the
script appends `/reports/`. After migration, when `REPORT_DIR` is
`.bsg/reports/po`, appending `/reports/` would produce a double path.

**Solution:** Change the path construction to detect when REPORT_DIR already
contains `/reports/`:

```bash
if [[ "$REPORT_DIR" == *"/reports/"* || "$REPORT_DIR" == *"/reports" ]]; then
  REPORT_FILE="${REPO_ROOT}/${REPORT_DIR}/${SLUG}.md"
else
  REPORT_FILE="${REPO_ROOT}/${REPORT_DIR}/reports/${SLUG}.md"
fi
```

This is backward-compatible: existing callers passing `po` still get
`po/reports/SLUG.md`; new callers passing `.bsg/reports/po` get
`.bsg/reports/po/SLUG.md`.

---

## Phase 2: Per-Agent `--init` Scripts

**PRs:** 8 (one per agent, parallelizable)  
**Files created:** 8 new scripts + 1 test update  
**Estimated LOC:** ~60-100 per script, ~600 total

### Pattern (all scripts follow this contract)

```bash
#!/usr/bin/env bash
# init-<artifact>.sh — generate a first-draft <DOC> from repo scan.
#
# Emits the draft document to stdout. Never writes to disk.
# The orchestrator (/bsg-stack init) captures output and opens a PR.
#
# Usage:
#   bash init-<artifact>.sh [--repo OWNER/NAME]
#
# Exit 0 + content on stdout: success
# Exit 0 + empty stdout: nothing to generate (repo has no relevant signals)
# Exit 1: error (missing tool, no gh auth, etc.)
```

### Per-agent implementations

#### `claude-skills/skills/po/scripts/init-plan.sh`

Wraps existing `bootstrap-plan.sh` (already 90% of the work):
1. Call `bootstrap-plan.sh` which scans milestones, issues, labels
2. Pipe output through minor formatting adjustments for `.bsg/PLAN.md` header
3. Emit to stdout

#### `claude-skills/skills/storytelling-report/scripts/init-narrative.sh`

1. Extract repo name from `gh repo view --json name`
2. Extract description from `gh repo view --json description`
3. Scan README.md first 50 lines for mission/about statement
4. Emit NARRATIVE.md template with:
   - Product name + one-line positioning from description
   - Voice guidelines placeholder (formal/informal, active/passive)
   - Key messages section with repo description as message #1
   - Target audience placeholder

#### `claude-skills/skills/marketing-report/scripts/init-calendar.sh`

1. `gh release list --limit 20 --json tagName,publishedAt,name`
2. `gh api repos/{owner}/{repo}/milestones --jq '.[].title'`
3. Emit CALENDAR.md with:
   - Past releases as "shipped" entries
   - Open milestones with due dates as "upcoming" entries
   - Placeholder rows for blog/social

#### `claude-skills/skills/seo-report/scripts/init-keywords.sh`

1. Extract repo topics via `gh repo view --json repositoryTopics`
2. Extract package name/description from package.json or setup.py
3. Scan README.md H1/H2 headings
4. Emit KEYWORDS.md with extracted keywords as seed list + coverage table template

#### `claude-skills/skills/security-report/scripts/init-securityignore.sh`

1. `find . -type d -name "test*" -o -name "fixture*" -o -name "__test*" -o -name "example*"`
2. `find . -name "*.example" -o -name "*.sample"`
3. Check for CI config paths (`.github/workflows/`)
4. Emit SECURITYIGNORE with discovered test/fixture paths

#### `claude-skills/skills/pr-comms-report/scripts/init-announced.sh`

1. `gh release list --limit 50 --json tagName,publishedAt,name`
2. Check for CHANGELOG.md existence and parse version headers
3. Emit ANNOUNCED.md listing all releases as already-communicated

#### `claude-skills/skills/tech-report/scripts/init-adr.sh`

1. Detect primary language/framework (package.json → node; setup.py → python; Cargo.toml → rust)
2. Detect CI system (`.github/workflows/` → GHA; `.gitlab-ci.yml` → GitLab)
3. Emit a `000-record-architecture-decisions.md` ADR template
4. If signals are strong enough, emit a `001-technology-stack.md` draft

#### `claude-skills/skills/qa-report/scripts/init-qa.sh`

1. Detect test framework (jest/vitest/pytest/go test/cargo test)
2. Detect coverage tool (lcov, coverage.py, istanbul)
3. Emit a summary doc to `.bsg/reports/qa/baseline.md` (what was detected)
4. Create `.gitkeep` placeholder for the reports dir

### Test enforcement

Add to `claude-skills/tests/test_skills.py`:

```python
def test_every_agent_has_init_script():
    """Every agent with a custom-doc must have a corresponding init script."""
    for agent in registry["agents"]:
        agent_file = parse_frontmatter(f"agents/{agent['name']}.md")
        if agent_file.get("custom-doc"):
            # Find the skill that owns this agent
            # Verify an init-*.sh exists in that skill's scripts/
            ...
```

---

## Phase 3: `/bsg-stack` Subcommands

**PR:** 1  
**Files created:** 3 new scripts  
**Estimated LOC:** ~250

### `claude-skills/skills/bsg-stack/scripts/init.sh`

```bash
#!/usr/bin/env bash
# init.sh — bootstrap .bsg/ directory for a fresh repo.
set -euo pipefail

# 1. Run doctor --json to identify gaps
gaps=$(bash "$(dirname "$0")/doctor.sh" --json 2>/dev/null || echo '{}')

# 2. Create .bsg/ skeleton
mkdir -p .bsg/adr .bsg/brand/templates .bsg/reports/{po,qa,security,tech,seo,marketing,storytelling,comms,cleaner}

# 3. For each agent with missing custom-doc, run its init script
# Map agent name → init script path (relative to claude-skills/)
declare -A INIT_SCRIPTS=(
  [po-manager]="skills/po/scripts/init-plan.sh"
  [storytelling]="skills/storytelling-report/scripts/init-narrative.sh"
  [marketing]="skills/marketing-report/scripts/init-calendar.sh"
  [seo]="skills/seo-report/scripts/init-keywords.sh"
  [security]="skills/security-report/scripts/init-securityignore.sh"
  [pr-comms]="skills/pr-comms-report/scripts/init-announced.sh"
  [tech-lead]="skills/tech-report/scripts/init-adr.sh"
  [qa]="skills/qa-report/scripts/init-qa.sh"
)

# Map agent name → output path
declare -A OUTPUT_PATHS=(
  [po-manager]=".bsg/PLAN.md"
  [storytelling]=".bsg/NARRATIVE.md"
  [marketing]=".bsg/CALENDAR.md"
  [seo]=".bsg/KEYWORDS.md"
  [security]=".bsg/SECURITYIGNORE"
  [pr-comms]=".bsg/ANNOUNCED.md"
  [tech-lead]=".bsg/adr/000-record-decisions.md"
  [qa]=".bsg/reports/qa/baseline.md"
)

# 4. Run each init, capture to file
for agent in "${!INIT_SCRIPTS[@]}"; do
  output_path="${OUTPUT_PATHS[$agent]}"
  if [[ -f "$output_path" ]]; then
    echo "  skip: $output_path (already exists)"
    continue
  fi
  script="${CATALOG_DIR}/${INIT_SCRIPTS[$agent]}"
  if [[ -f "$script" ]]; then
    content=$(bash "$script" 2>/dev/null || true)
    if [[ -n "$content" ]]; then
      mkdir -p "$(dirname "$output_path")"
      echo "$content" > "$output_path"
      echo "  created: $output_path"
    fi
  fi
done

# 5. Bootstrap GitHub labels
# ... (gh label create for each missing label)

# 6. Create .bsg/AUTOPILOT.yml scaffold if missing
if [[ ! -f .bsg/AUTOPILOT.yml && ! -f .bsg-autopilot.yml ]]; then
  cat > .bsg/AUTOPILOT.yml <<'YAML'
enabled: false
agents: []
budget:
  max_prs_per_tick: 3
  max_prs_per_day: 200
  max_loc_per_issue: 200
  max_files_per_issue: 8
YAML
  echo "  created: .bsg/AUTOPILOT.yml (disabled — edit to enable)"
fi

# 7. Summary
echo ""
echo "Done. Review the generated files, then commit and open a PR."
```

### `claude-skills/skills/bsg-stack/scripts/update.sh`

1. Run `doctor.sh --json` → identify stale docs (>90 days)
2. For each stale doc, re-run the corresponding init script
3. Write output to a temp file, diff against current
4. If meaningful diff, replace the file
5. Print summary of what was refreshed

### `claude-skills/skills/bsg-stack/scripts/status.sh`

Thin wrapper:
```bash
#!/usr/bin/env bash
exec bash "$(dirname "$0")/doctor.sh" --status "$@"
```

---

## Phase 4: Report Path Migration

**PRs:** 9 (one per agent)  
**Files modified:** Agent `.md` files + tick body references  
**Estimated LOC:** ~50 per agent (prose changes)

### Migration per agent

For each agent, one PR that:
1. Updates the agent's `tick:` body to pass `.bsg/reports/<bus>` to `tick-fingerprint.sh`
2. Updates `open-report-pr.sh` calls to write to `.bsg/reports/<bus>/`
3. Updates prose references in the agent `.md` from old paths to new
4. Updates the corresponding skill's report scripts if they hardcode paths

### Order

1. **tech-lead** first (output:commit, simplest tick body)
2. **qa**, **seo** (other output:commit agents)
3. **po-manager** (largest file, most references)
4. **security**, **marketing**, **storytelling**, **pr-comms**, **cleaner**

Each PR is mechanical and fits the autopilot budget (< 200 LOC, < 8 files).

---

## Phase 5: DESIGN.md Generation

**PR:** 1-2  
**Files modified/created:** 3  
**Estimated LOC:** ~200

### `claude-skills/skills/md-to-office/scripts/scan-brand.py`

Add `--emit design-md` flag:
- When set, output Stitch-format DESIGN.md to stdout instead of JSON
- Same scan logic (CSS vars, Tailwind config, logos, package.json)
- Different serialization target

### `claude-skills/skills/md-to-office/scripts/tokens-from-design.py` (new)

- Read `.bsg/DESIGN.md`, parse Markdown sections
- Extract colors, typography, spacing into the existing tokens.json schema
- Emit JSON to stdout (same shape as current `scan-brand.py` output)
- Header comment: "DERIVED FROM .bsg/DESIGN.md — do not edit by hand"

### `claude-skills/skills/md-to-office/scripts/init-design.sh` (new)

- Wrapper that calls `scan-brand.py --emit design-md`
- Follows the init script contract (stdout, no disk writes)

---

## Dependency Graph

```
Phase 1 ──────────────────┐
(path resolver)           │
                          ├──► Phase 3 (/bsg-stack init/update/status)
Phase 2 ──────────────────┘         │
(init scripts, parallel)            │
                                    ▼
                          Phase 4 (report migration, per-agent PRs)

Phase 5 (DESIGN.md) ─── independent, after Phase 1
```

## Testing Strategy

| Phase | Test |
|---|---|
| 1 | Unit test: source `_bsg-paths.sh` in temp dir, verify resolution for both paths |
| 2 | `test_skills.py`: verify every registered agent has an init script file |
| 2 | Each script: run with `--help` exits 0; run in empty dir exits 0 with empty or valid stdout |
| 3 | `init.sh` in temp dir: verify `.bsg/` skeleton created |
| 4 | Existing fingerprint tests pass with new report-dir format |
| 5 | `scan-brand.py --emit design-md` on a repo with Tailwind → valid Markdown output |

## Implementation Schedule

| Phase | PRs | Can parallelize? | Blocked by |
|---|---|---|---|
| 1 | 1 | — | Nothing |
| 2 | 8 | Yes (all parallel) | Phase 1 |
| 3 | 1 | — | Phase 1 + Phase 2 |
| 4 | 9 | Yes (all parallel) | Phase 1 |
| 5 | 1-2 | Yes | Phase 1 |

**Total: ~15 PRs.** Phases 2, 4, and 5 can run in parallel after Phase 1
lands, giving a critical path of: Phase 1 → Phase 2 → Phase 3.

## File Inventory (new files to create)

```
claude-skills/skills/po/scripts/init-plan.sh
claude-skills/skills/storytelling-report/scripts/init-narrative.sh
claude-skills/skills/marketing-report/scripts/init-calendar.sh
claude-skills/skills/seo-report/scripts/init-keywords.sh
claude-skills/skills/security-report/scripts/init-securityignore.sh
claude-skills/skills/pr-comms-report/scripts/init-announced.sh
claude-skills/skills/tech-report/scripts/init-adr.sh
claude-skills/skills/qa-report/scripts/init-qa.sh
claude-skills/skills/bsg-stack/scripts/init.sh
claude-skills/skills/bsg-stack/scripts/update.sh
claude-skills/skills/bsg-stack/scripts/status.sh
claude-skills/skills/md-to-office/scripts/init-design.sh
claude-skills/skills/md-to-office/scripts/tokens-from-design.py
```

## File Inventory (files to modify)

```
claude-skills/scripts/_bsg-paths.sh
claude-skills/scripts/tick-fingerprint.sh
claude-skills/scripts/validate-plan.sh
claude-skills/skills/po/scripts/parse-plan.sh
claude-skills/skills/po/scripts/reconcile-milestones.sh
claude-skills/skills/po/scripts/adherence.sh
claude-skills/skills/po/scripts/bootstrap-plan.sh
claude-skills/skills/bsg-stack/SKILL.md
claude-skills/agents/po-manager.md (Phase 4)
claude-skills/agents/tech-lead.md (Phase 4)
claude-skills/agents/qa.md (Phase 4)
claude-skills/agents/seo.md (Phase 4)
claude-skills/agents/security.md (Phase 4)
claude-skills/agents/marketing.md (Phase 4)
claude-skills/agents/storytelling.md (Phase 4)
claude-skills/agents/pr-comms.md (Phase 4)
claude-skills/agents/cleaner.md (Phase 4)
claude-skills/skills/md-to-office/scripts/scan-brand.py (Phase 5)
```
