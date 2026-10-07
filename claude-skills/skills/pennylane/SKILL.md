---
name: pennylane
description: Firm-level connector for the Pennylane accounting & finance platform (pennylane.com) — a single OAuth 2.0 integration that reaches every company/structure a firm token can access. Use for Pennylane API integration (read/write customer & supplier invoices, customers, suppliers, ledger entries, ledger accounts, products, categories), data export & reporting across multiple companies, and bookkeeping workflows (A/R, A/P, chart of accounts, VAT). Triggers include "connect to Pennylane", "Pennylane API", "connecteur Pennylane", "export Pennylane invoices", "list all our Pennylane companies/structures", "pull the ledger from Pennylane", "create an invoice in Pennylane", "Pennylane OAuth", or any task against api/external/v2 on app.pennylane.com. Not for the PennyLane quantum-computing Python library.
---

# Pennylane connector

Connects to the **Pennylane** accounting/finance SaaS (`pennylane.com`) via the
External API **v2** using a **firm-level OAuth token** so one authorization
reaches all connected structures/companies. Stdlib-only client — no pip installs.

## Disambiguation

This is the French accounting platform, **not** the `pennylane` quantum-ML
Python library. If the user is doing quantum circuits/qubits, this skill does
not apply.

## The client

`scripts/pennylane.py` is the single entry point. It handles OAuth, refresh-
token rotation, a `0600` token store, cursor pagination, and v2 JSON filters.

```bash
S=scripts/pennylane.py
python3 $S doctor                                     # 0. check setup, print next step
python3 $S auth-url --state $(openssl rand -hex 16)   # 1. get consent URL
python3 $S exchange "<code-from-redirect>"            # 2. store tokens
python3 $S me                                         # verify (id, email, role)
python3 $S companies --all                            # every connected structure
python3 $S get customer_invoices --limit 100 --all    # paginated read
python3 $S post customer_invoices --data '{...}'       # write
```

## First-time setup (do this before anything else)

**Always run `python3 $S doctor` first.** It reports which credentials/tokens
are present (never printing secret values) and tells you the exact next step.
Use it to drive the setup conversation with the user — don't guess what's
configured.

1. **Credentials.** OAuth apps are provisioned by Pennylane's partnerships team
   (request a sandbox). Set, never commit:
   ```bash
   export PENNYLANE_CLIENT_ID=...
   export PENNYLANE_CLIENT_SECRET=...
   export PENNYLANE_REDIRECT_URI=https://your.app/callback
   ```
2. **Authorize** with `auth-url` → user approves → `exchange <code>`. Tokens
   land in `~/.config/pennylane/tokens.json` (override via
   `PENNYLANE_TOKEN_STORE`). Full flow: **[references/oauth.md](references/oauth.md)**.

**If credentials are missing, guide the user — don't stall and don't fabricate.**
`doctor` and every command now emit the exact env-var exports and OAuth steps
needed. Walk the user through them one at a time:
1. Ask them to obtain/confirm their `CLIENT_ID`, `CLIENT_SECRET`, and
   `REDIRECT_URI` from their Pennylane OAuth app (partnerships/sandbox).
2. Have them `export` the three vars in the shell running the skill.
3. Re-run `doctor`; when credentials are green, run `auth-url`, have them
   approve in the browser, paste the redirect `code`, then `exchange <code>`.
Never invent client ids, secrets, or redirect URIs.

## Critical rules

- **Refresh-token rotation:** each refresh invalidates the previous refresh
  token. The script persists atomically — but never run two processes against
  one token store, or the integration locks out and must re-authorize.
- **v2 money as strings:** pass amounts like `"1250.00"`, not floats.
- **Internal IDs only** (v1 `source_id` is gone); v1 is deprecated — use v2.
- **Least-privilege scopes** via `PENNYLANE_SCOPES` or `auth-url --scopes`.
- **Confirm exact paths/fields** against `https://pennylane.readme.io/reference`
  before production writes — endpoint shapes evolve.

## Reference material — read when relevant

- **[references/oauth.md](references/oauth.md)** — full firm OAuth flow, token
  lifetimes & rotation, scopes, revocation. Read for any auth/setup work.
- **[references/endpoints.md](references/endpoints.md)** — v2 resource table,
  cursor pagination, the JSON `filter` syntax + operators, v2-vs-v1 gotchas,
  rate limits. Read before constructing any request.
- **[references/workflows.md](references/workflows.md)** — multi-company
  iteration, data export/reporting with `jq`, and bookkeeping (A/R, A/P, ledger,
  invoice creation) recipes. Read when fulfilling a concrete user task.

For branded report output of exported data, hand off to the `md-to-word` /
`md-to-office` skills.

---

## How to improve this skill

This file is a cached copy of `claude-skills/skills/pennylane/SKILL.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — local copies are overwritten by
the BSG install flow. To improve the skill: clone bsg-stack, edit on a
branch, open a PR against `main`.
