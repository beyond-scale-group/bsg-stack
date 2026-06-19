---
name: security-report
description: >
  Security audit toolkit for the current GitHub repository. Produces a
  dated report covering dependency vulnerabilities (npm/pip/cargo/go),
  secret patterns in tracked files, security headers / config hardening,
  and an OWASP top-10 quick check. Use when the user asks to "scan for
  vulnerabilities", "check for leaked secrets", "run a security audit",
  "OWASP check", "CVE scan", or "are there known vulns". Heavy lifting
  happens in bash + jq scripts; the LLM narrates the findings.
model: sonnet
---

# Security Report

The security-audit skill for the **current repository**. Shipped as the
implementation layer behind the `@security` subagent — run directly when
you just need the raw data, or let `@security` orchestrate it for a
silent-by-default tick.

## Intent routing

| If the user asks about...                                        | Read this reference       |
| ---------------------------------------------------------------- | ------------------------- |
| Dependency vulnerabilities, CVEs, outdated packages              | `references/deps.md`      |
| Leaked secrets, committed `.env`, tokens in source               | `references/secrets.md`   |
| OWASP top-10, broken access control, injection, misconfig        | `references/owasp.md`     |
| Security headers (CSP, HSTS, CORS), cookie flags, HTTPS config   | `references/headers.md`   |

For a **full audit** (every dimension), run `generate-report.sh` — it
collects once, runs every reporter, and composes a single markdown file
under `security/reports/`.

## Hard rules

1. **Never invent findings.** Every CVE, severity, package name, or
   secret pattern must come from a script's JSON output — not from
   recognition or memory.
2. **Always write the final report to `security/reports/YYYY-MM-DD-*.md`**
   so the audit trail is dated and version-controllable.
3. **Run scripts from the repo root.** They auto-detect the package
   ecosystem via lockfiles (package-lock.json, Pipfile.lock, go.sum,
   Cargo.lock).
4. **Do not fix anything.** Reporting only. If a script has a `--fix`
   flag (it doesn't today), never pass it from a `tick`.
5. **Respect `.securityignore`** when scanning for secrets. Test
   fixtures and intentional sample credentials belong there.
6. **Confirm before posting** to GitHub (issue comment, labels, etc.).
   Default is local-only.

## Available scripts

All scripts live in `scripts/` and emit JSON on stdout (except
`generate-report.sh`, which emits markdown). `collect.sh` is the single
cross-tool fetch; every other reporter is a pure jq / grep transform of
that snapshot — pass it with `--snapshot <path>`, pipe it in, or let
the script auto-collect a fresh one.

| Script                | Purpose                                                                 |
| --------------------- | ----------------------------------------------------------------------- |
| `collect.sh`          | Auto-detect package ecosystem, run `npm audit` / `pip-audit` / `gh api /vulnerability-alerts`, gather tracked-file list for secret scan. One snapshot → `/tmp/security-snap.json`. |
| `deps.sh`             | Transform snapshot → dependency vulnerability table with severity, fix-available, and `noFix[]` summary. |
| `secrets.sh`          | Scan tracked files for secret patterns (AWS keys, GitHub tokens, generic `AKIA`/`sk-`/`ghp_` prefixes, private keys). Respects `.securityignore`. |
| `headers.sh`          | Inspect config files (nginx, Express, Flask, …) for required security headers (CSP, HSTS, X-Frame-Options). |
| `generate-report.sh`  | Collects once, runs every reporter, composes the full markdown audit. |

**Invocation patterns:**

```bash
# One-shot: full audit
bash scripts/generate-report.sh > security/reports/$(date +%F)-audit.md

# Reuse one snapshot across multiple reporters
bash scripts/collect.sh > /tmp/security-snap.json
bash scripts/deps.sh    --snapshot /tmp/security-snap.json
bash scripts/secrets.sh --snapshot /tmp/security-snap.json
bash scripts/headers.sh --snapshot /tmp/security-snap.json

# Deps only, fail-closed on critical CVEs (for a local guard, not CI)
bash scripts/deps.sh | jq -e '.summary.critical == 0'
```

## Output convention

Reports go to `security/reports/`. Filename pattern:

```
security/reports/2026-04-20-audit.md      # full audit from tick
security/reports/2026-04-20-deps.md       # deps-only slice
security/reports/2026-04-20-secrets.md    # secrets-only slice
```

Use today's date. After writing, print the file path and a one-line
verdict — do **not** dump the full report inline.

## Tick action

Users invoke `tick` (typically via `@security tick` from `/loop` or
`/schedule`) when they want the security audit to run now and the
result to be archived in the repo. It is **idempotent, repo-scoped,
and silent by default**.

This `tick` follows the BSG-wide convention documented in the top-level
[`CLAUDE.md`][claude-md] under "The `tick` convention" — silent-by-default,
human-initiated (no CI cron), repo-scoped (audits the current repo's
tree, writes to the current repo's `security/reports/`).

[claude-md]: https://github.com/beyond-scale-group/bsg-stack/blob/main/CLAUDE.md

### Steps

1. **Generate the full audit** — one invocation composes every reporter:

   ```bash
   mkdir -p security/reports
   bash ~/.claude/skills/security-report/scripts/generate-report.sh \
     > security/reports/$(date +%F)-audit.md
   ```

2. **Land the report via the shared helper** — never commit to `main`
   directly. The helper opens an auto-merge PR (or falls back to a
   direct squash merge if branch protection is not configured):

   ```bash
   bash ~/.claude/scripts/open-report-pr.sh \
     security/reports/$(date +%F)-audit.md \
     --agent security
   ```

3. **Evaluate silence-breakers** by parsing the snapshot JSON (not the
   rendered markdown — more robust). The `@security` agent owns the
   thresholds; this skill emits raw counts.

4. **Reply.** If no silence-breaker fires, a single line — e.g.
   `Tick: security posture clean, report at <PR url>` — is the whole
   reply. If a silence-breaker fires, summarize which ones (count
   critical CVEs, count secret findings, etc.) and link the PR.

### Silence is a feature

Do **not** pad the reply with "no issues found" narrative, next-step
suggestions, or reassurance when nothing fired. One-line receipts
only. The committed report PR is the full audit trail — the chat line
is just a receipt. Remediation (package upgrades, secret rotation,
header fixes) is **never** part of `tick` — the user explicitly opts
in to each remediation.

---

## How to improve this skill

This file is a cached copy of `claude-skills/skills/security-report/SKILL.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/skills/security-report/SKILL.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/skills/security-report/SKILL.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
