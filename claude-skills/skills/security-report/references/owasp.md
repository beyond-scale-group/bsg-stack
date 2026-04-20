# OWASP Top-10 Quick Check

A lightweight pass across the OWASP Top-10 categories (2021 edition),
intended as a gap-analysis surface, not a full audit.

## Scope and philosophy

The quick check is **signal, not certification.** Each category is
evaluated against 1–3 cheap heuristics the LLM can apply by reading
the repo. Detailed category analysis (fuzzing, DAST, full threat
modeling) is out of scope for this skill.

Categories with no actionable heuristic for a repo-at-rest audit (e.g.
A10 Server-Side Request Forgery, which needs runtime instrumentation)
are marked `n/a` rather than fabricated.

## Checklist

| ID  | Category                                    | Heuristic                                                                 |
| --- | ------------------------------------------- | ------------------------------------------------------------------------- |
| A01 | Broken Access Control                       | Auth middleware wired on every router branch? `@auth_required` coverage? |
| A02 | Cryptographic Failures                      | TLS enforced (HSTS)? Any MD5 / SHA1 / DES / ECB in source?                |
| A03 | Injection                                   | Parameterized queries / ORM? `eval`, `exec`, `os.system`, template-string SQL? |
| A04 | Insecure Design                             | Threat model documented? Rate limits on auth endpoints?                   |
| A05 | Security Misconfiguration                   | Verbose errors in prod? Default creds in config? Debug flags?             |
| A06 | Vulnerable & Outdated Components            | Covered by `deps.sh` — reference the count here, don't re-scan.           |
| A07 | Identification & Authentication Failures    | Password policy? MFA? Session timeout? Login throttling?                  |
| A08 | Software & Data Integrity Failures          | CI runs only pinned Actions? Lockfile committed? SRI on CDN scripts?      |
| A09 | Security Logging & Monitoring Failures      | Auth events logged? Log injection sanitization?                           |
| A10 | Server-Side Request Forgery                 | URL allow-list for outbound fetches? (often `n/a` at rest)                |

## How to run

There is no dedicated `owasp.sh` script — the check is LLM-driven on
top of `generate-report.sh`'s aggregated snapshot plus a targeted
Read/Grep pass. The result lands in the `## OWASP Top-10` section of
the composed audit report.

## How to interpret

Each category emits one of:

- **`pass`** — heuristic found no issue
- **`warn`** — heuristic found a smell; show the file(s)
- **`fail`** — heuristic found a concrete finding; silence-breaker at
  the agent's discretion
- **`n/a`** — heuristic not applicable to this repo (e.g. no auth
  surface, no web frontend)

The silence-breakers in `agents/security.md` do **not** currently
include OWASP `fail` counts — the heuristics are too coarse for
automatic alerting. Surface them in the report; the user decides.

## What NOT to do

- Don't claim a category passes if the heuristic wasn't applicable —
  use `n/a` instead. False confidence is worse than silence.
- Don't invent CVE IDs for A06. Defer to `deps.sh`.
- Don't promote `warn` to `fail` without a concrete file + line — the
  LLM must cite evidence.
