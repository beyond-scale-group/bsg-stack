# PRD-001: Security Agent

**Status:** Draft
**Author:** Guillaume Badin
**Date:** 2026-04-20
**Priority:** P0 — Phase 1

---

## 1. Problem Statement

BSG repositories have no automated, recurring security posture assessment.
Dependency vulnerabilities accumulate silently, secrets occasionally slip into
committed code, and OWASP compliance is checked ad-hoc (if at all). Developers
discover security issues reactively — after a breach scare, a failed audit, or
a customer report — rather than through a systematic, repo-scoped review cadence.

## 2. Goal

Provide a Claude Code subagent that, on every `tick`, produces a dated security
audit report covering dependency vulnerabilities, secret detection, and
configuration hardening — and stays silent when the posture is clean.

## 3. Non-Goals

- **Runtime security monitoring** (WAF, IDS, SIEM). This agent audits source
  code and configuration at rest, not live traffic.
- **Penetration testing or exploit generation.** The agent flags risks; it does
  not attempt exploitation.
- **Fixing vulnerabilities automatically.** The agent reports; the developer (or
  another agent) remediates. The agent may suggest fixes in its narrative but
  must not commit code changes.
- **CI/CD pipeline integration.** Per BSG convention, no GitHub Actions or cron
  jobs. The agent runs on-demand via `@security tick`.

## 4. User Stories

| # | As a… | I want to… | So that… |
|---|-------|-----------|----------|
| S1 | Developer | Run `@security tick` and get a one-line receipt if everything is clean | I don't waste time reading "all good" reports |
| S2 | Developer | Get alerted when a critical CVE lands in my dependency tree | I can prioritize the upgrade before it's exploited |
| S3 | Tech lead | See a dated trail of security audits in `security/reports/` | I can demonstrate compliance to stakeholders |
| S4 | Developer | Run `@security secrets` to scan for leaked credentials | I can catch accidental commits before they reach production |
| S5 | Developer | Run `@security deps` to see just the dependency vulnerability summary | I can focus on one dimension without the full audit |
| S6 | Developer | Run `@security checklist` for an OWASP top-10 gap analysis | I can verify a feature against the standard before shipping |

## 5. Agent Design

### 5.1 Frontmatter

```yaml
---
name: security
description: >
  Security posture auditor for the current GitHub repository. Scans for
  dependency vulnerabilities, committed secrets, and OWASP top-10 gaps.
  Use when the user asks for "security audit", "vulnerability scan",
  "secret scan", "OWASP check", "dependency vulnerabilities", "security
  posture", "are we secure", "audit de sécurité", or "analyse des
  vulnérabilités".
tools: Read, Glob, Grep, Bash, Write
model: sonnet
skills: [security-report]
color: red
output: pr
tick: >
  Run the full security audit (deps + secrets + config), land it as
  security/reports/YYYY-MM-DD-audit.md via open-report-pr.sh, and stay
  silent in chat unless a silence-breaker fires.
---
```

### 5.2 Routing Table

| User intent | Action |
|---|---|
| "security audit", "full scan", "posture check" | Run all scripts, produce full report |
| "dependency scan", "CVEs", "vulnerabilities" | `security-report` -> `references/deps.md` |
| "secret scan", "leaked credentials", "tokens in code" | `security-report` -> `references/secrets.md` |
| "OWASP", "checklist", "top 10" | `security-report` -> `references/owasp.md` |
| "security headers", "CSP", "CORS", "HSTS" | `security-report` -> `references/headers.md` |
| "fix vulnerability X", "upgrade package Y" | Decline; hand back to main agent |

### 5.3 Tick Action

**Steps:**

1. Run `collect.sh` to gather a security snapshot (`/tmp/security-snap.json`):
   - `npm audit --json` / `pip-audit --format=json` (language-detected)
   - `gh api /repos/{owner}/{repo}/vulnerability-alerts`
   - Secret pattern grep results
   - Config file inventory (CSP headers, `.env.example` vs `.env`, etc.)

2. Run individual reporters against the snapshot:
   - `deps.sh --snapshot /tmp/security-snap.json` — dependency CVEs
   - `secrets.sh --snapshot /tmp/security-snap.json` — secret patterns
   - `headers.sh --snapshot /tmp/security-snap.json` — config hardening

3. `generate-report.sh` composes the full report:
   ```
   security/reports/2026-04-20-audit.md
   ```

4. Land via `open-report-pr.sh`:
   ```bash
   bash ~/.claude/scripts/open-report-pr.sh \
     security/reports/$(date +%F)-audit.md \
     --agent security
   ```

5. Evaluate silence-breakers. Reply with one-line receipt if none fire.

### 5.4 Silence-Breakers

| Signal | Source | Threshold |
|---|---|---|
| Critical/high CVE in dependencies | `deps.sh` -> `severity: critical\|high` | Any |
| Secret pattern detected in tracked files | `secrets.sh` -> `findings[]` | Non-empty |
| Missing security headers in config | `headers.sh` -> `missing[]` | Any critical header (CSP, HSTS) |
| Known-vulnerable dependency with no fix available | `deps.sh` -> `noFix[]` | Any critical |
| `.env` or credentials file tracked by git | `secrets.sh` -> `trackedEnvFiles[]` | Non-empty |

## 6. Skill Structure

```
skills/security-report/
├── SKILL.md                    # Intent routing + hard rules
├── references/
│   ├── deps.md                 # Dependency vulnerability analysis guide
│   ├── secrets.md              # Secret scanning guide
│   ├── owasp.md                # OWASP top-10 checklist guide
│   └── headers.md              # Security headers/config guide
└── scripts/
    ├── collect.sh              # Snapshot collector (language-aware)
    ├── deps.sh                 # Dependency vulnerability reporter
    ├── secrets.sh              # Secret pattern scanner
    ├── headers.sh              # Config/headers auditor
    └── generate-report.sh      # Full report composer
```

## 7. Report Format

```markdown
# Security Audit — 2026-04-20

## Dependency Vulnerabilities
| Package | Severity | CVE | Fix available |
|---------|----------|-----|---------------|
| …       | critical | …   | Yes — v2.3.1  |

**Summary:** 2 critical, 1 high, 4 moderate

## Secret Scan
- 0 secrets detected in tracked files
- .env is in .gitignore: YES

## Configuration Hardening
| Header/Config | Status |
|---------------|--------|
| CSP            | Present |
| HSTS           | Missing |

## OWASP Top-10 Quick Check
| Category | Status | Notes |
|----------|--------|-------|
| A01 Broken Access Control | … | … |
```

## 8. Dependencies

- `npm` or `pip` (language-detected per repo)
- `gh` CLI (authenticated)
- `jq` for JSON processing
- `grep` with PCRE support for secret patterns
- Optional: `pip-audit`, `npm audit` (bundled with their package managers)

## 9. Success Metrics

| Metric | Target |
|---|---|
| Time from CVE publication to developer notification | < 24h (with daily tick) |
| False positive rate on secret scanning | < 10% |
| Report generation time | < 30s for repos with < 500 dependencies |
| Adoption across BSG repos | 100% within 4 weeks of launch |

## 10. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| `npm audit` / `pip-audit` not installed | `collect.sh` detects available tools, skips gracefully, flags in report |
| Secret scanner false positives (test fixtures, examples) | Respect `.securityignore` file for exclusion patterns |
| Large repos slow to scan | `collect.sh` caps file count, uses `.gitignore`-aware search |
| Different repos use different languages | `collect.sh` auto-detects from lockfiles (package-lock.json, Pipfile.lock, go.sum, Cargo.lock) |
