# Dependency Vulnerability Analysis

How to run and interpret the dependency scan.

## Scope

Covers every ecosystem the collector detects via lockfiles:

| Lockfile              | Tool used              | Ecosystem |
| --------------------- | ---------------------- | --------- |
| `package-lock.json`   | `npm audit --json`     | Node.js   |
| `yarn.lock`           | `npm audit --json` (fallback) | Node.js |
| `pnpm-lock.yaml`      | `npm audit --json` (fallback) | Node.js |
| `Pipfile.lock`        | `pip-audit --format=json` | Python |
| `poetry.lock`         | `pip-audit --format=json` | Python |
| `go.sum`              | `gh api .../vulnerability-alerts` (GHSA) | Go |
| `Cargo.lock`          | `gh api .../vulnerability-alerts` (GHSA) | Rust |

GitHub Dependabot's Security Alerts API (`gh api /repos/{owner}/{repo}/vulnerability-alerts`)
is queried unconditionally as a cross-ecosystem safety net — it works
even when no local tool is installed.

## How to run

```bash
# From a fresh snapshot
bash scripts/deps.sh

# Against an existing snapshot
bash scripts/deps.sh --snapshot /tmp/security-snap.json

# Only critical severity
bash scripts/deps.sh | jq '.findings[] | select(.severity == "critical")'
```

## Output schema

```json
{
  "summary": {
    "total": 7,
    "critical": 2,
    "high": 1,
    "moderate": 4,
    "low": 0
  },
  "findings": [
    {
      "package": "lodash",
      "version": "4.17.19",
      "severity": "critical",
      "cve": "CVE-2021-23337",
      "fixedIn": "4.17.21",
      "source": "npm audit"
    }
  ],
  "noFix": [
    { "package": "foo", "severity": "high", "cve": "..." }
  ]
}
```

## How to interpret

- **`summary.critical > 0`** → silence-breaker fires. Reply with the
  package list and recommended upgrade; do **not** perform the upgrade.
- **`noFix[]` non-empty** → there are known-vulnerable deps with no
  upstream patch yet. Surface them once per tick, then keep quiet
  until the list changes (the agent, not the script, debounces).
- **`summary.total == 0`** → clean. One-line receipt.

## Common false positives

- **Dev-only packages with CVEs in transitive build tools.** Still
  reported, but the severity is usually informational. Let the user
  decide.
- **Vulnerabilities in lockfile-only versions that were pinned
  intentionally.** Respect `.securityignore` entries of the form
  `deps: <package>@<version> # reason`.

## What NOT to do

- Don't auto-upgrade. Reporting only.
- Don't open upstream issues from the tick — the user decides whether
  to escalate.
- Don't cite CVEs that aren't in the tool output, even if you "know"
  they exist.
