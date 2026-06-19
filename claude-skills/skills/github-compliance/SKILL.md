---
name: github-compliance
description: >
  GitHub organization compliance checker for Beyond Scale Group. Ensures all
  non-archived private repositories have the required teams assigned with the
  correct permissions. Use this skill when the user asks to "check compliance",
  "vérifier la conformité GitHub", "assigner les teams aux repos", "audit GitHub org",
  "check team assignments", "fix repo permissions", "run compliance check", or
  "github-compliance tick". Works with the `beyond-scale-group` org and the
  `board` team by default.
model: haiku
---

# GitHub Compliance

Vérifie et corrige l'assignation des teams GitHub sur tous les repos privés
non-archivés de l'organisation.

## Check (audit seul)

```bash
bash ~/.claude/skills/github-compliance/scripts/check_compliance.sh
```

## Fix (audit + correction automatique)

```bash
bash ~/.claude/skills/github-compliance/scripts/check_compliance.sh --fix
```

## Options

| Flag | Défaut | Description |
|---|---|---|
| `--fix` | false | Corrige les repos non-conformes |
| `--org` | `beyond-scale-group` | Organisation GitHub |
| `--team` | `board` | Team à assigner |
| `--permission` | `admin` | Permission (`pull`, `push`, `admin`) |

## Exemples

```bash
# Audit only
bash ~/.claude/skills/github-compliance/scripts/check_compliance.sh

# Fix with default settings
bash ~/.claude/skills/github-compliance/scripts/check_compliance.sh --fix

# Custom org/team
bash ~/.claude/skills/github-compliance/scripts/check_compliance.sh --org my-org --team developers --permission push --fix
```

## Règles de conformité (Beyond Scale Group)

- Tous les repos **privés** et **non-archivés** doivent avoir la team `board` avec permission `admin`
- Les repos archivés sont ignorés
- Le repo public (`prompt-eng-interactive-tutorial`) est ignoré

## Tick action (periodic run)

The user invokes `tick` (typically via `@github-compliance tick` from
`/loop` or `/schedule`) when they want the compliance audit to run now and
the result to be archived in the repo. It is **idempotent, repo-scoped,
and silent by default** — when every repo is compliant, the chat reply
is one line; the full audit lives in the committed report.

This `tick` follows the BSG-wide convention documented in the top-level
[`CLAUDE.md`][claude-md] under "The `tick` convention" — silent-by-default,
human-initiated (no CI cron), repo-scoped (the audit targets one GitHub
org but the report lands in the current repo's `compliance/reports/`).

[claude-md]: https://github.com/beyond-scale-group/bsg-stack/blob/main/CLAUDE.md

### Steps

1. **Run the audit in capture mode** (no `--fix`) and write the raw output
   to a dated report file:

   ```bash
   mkdir -p compliance/reports
   bash ~/.claude/skills/github-compliance/scripts/check_compliance.sh \
     > compliance/reports/$(date +%F)-compliance.md
   ```

2. **Land the report via the shared helper** — never commit to `main`
   directly. The helper opens an auto-merge PR (or falls back to a direct
   squash merge if branch protection is not configured):

   ```bash
   bash ~/.claude/scripts/open-report-pr.sh \
     compliance/reports/$(date +%F)-compliance.md \
     --agent github-compliance
   ```

3. **Evaluate the silence-breaker** by parsing the report:

   ```bash
   non_compliant=$(grep -c '^    ' compliance/reports/$(date +%F)-compliance.md \
     | head -1 || echo 0)
   ```

   Or, more robustly, re-run the audit script and count the
   `Non-compliant (N repos)` line. The script exits 0 in both compliant
   and non-compliant states, so you must inspect its output rather than
   relying on the exit code.

4. **Reply.** If every repo is compliant, a single line — e.g.
   `Tick: all repos compliant, report at <PR url>` — is the whole reply.
   If any repo is non-compliant, list the offending repos and the PR url
   so the user can decide whether to re-run with `--fix`.

### Silence-breakers (what counts as "needs human attention")

Break silence if **any** of these hold for the audit you just produced:

| Signal                                  | Source                                                  | Threshold |
| --------------------------------------- | ------------------------------------------------------- | --------- |
| Any non-compliant repo                  | `check_compliance.sh` → `Non-compliant (N repos)` line  | `N > 0`   |
| Audit script failed to enumerate repos  | `gh api orgs/$ORG/repos` returned an error              | Any error |
| New repo appeared since the last tick   | Diff `compliance/reports/` between latest and previous  | First tick after a new repo lands — flag once so the user can confirm intent, then silent |

The "new repo" case is a one-shot: surface it once so the user notices a
fresh repo joined the org, then keep quiet on subsequent ticks (the
report itself still lists every repo each run).

### Silence is a feature

Do **not** pad the reply with "everything is compliant" narrative or
next-step suggestions when nothing fired. One-line acknowledgements only.
The committed report PR is the full audit trail — the chat line is just
a receipt. Auto-fixing (`--fix`) is **never** part of `tick` — `tick`
audits and reports; the user explicitly opts in to remediation.

## Références

- Voir `references/org_structure.md` pour la structure complète de l'organisation

---

## How to improve this skill

This file is a cached copy of `claude-skills/skills/github-compliance/SKILL.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/skills/github-compliance/SKILL.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/skills/github-compliance/SKILL.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
