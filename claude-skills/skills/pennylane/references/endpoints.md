# Pennylane External API v2 — resources & conventions

Base: `https://app.pennylane.com/api/external/v2`. Auth header on every call:
`Authorization: Bearer <access_token>`. v1 is deprecated — always use v2.

## Core resources

| Resource | Path | Methods | Notes |
|---|---|---|---|
| Companies | `/companies` | GET | Structures a firm token can reach |
| Whoami | `/me` | GET | id, email, role — verify a token |
| Customer invoices | `/customer_invoices` | GET, POST | invoices + credit notes |
| Customer invoice | `/customer_invoices/{id}` | GET | single |
| Invoice from quote | `/customer_invoices/create_from_quote` | POST | |
| Supplier invoices | `/supplier_invoices` | GET, POST | A/P side |
| Customers | `/customers` | GET, POST, PUT | |
| Suppliers | `/suppliers` | GET, POST, PUT | |
| Ledger entries | `/ledger_entries` | GET | journal lines |
| Ledger accounts | `/ledger_accounts` | GET | chart of accounts |
| Products | `/products` | GET, POST, PUT | |
| Categories | `/categories` | GET, POST | analytical/accounting categories |
| File attachments | `/file_attachments` | POST | files are a dedicated resource in v2 |

Endpoint names occasionally change; confirm exact paths/fields against the live
reference at `https://pennylane.readme.io/reference` before production use.

## Pagination — cursor based

`limit` (default 20, max 100) + opaque `cursor` from the previous response.
`scripts/pennylane.py get <path> --all` follows cursors automatically and
returns the flattened item list.

```bash
scripts/pennylane.py get customer_invoices --limit 100 --all
```

## Filtering — JSON array param

The `filter` query param is a URL-encoded JSON array of
`{field, operator, value}` objects (AND-combined). Operators: `eq`, `not_eq`,
`lt`, `lteq`, `gt`, `gteq`, `in`, `not_in`, `start_with`. Boolean fields
(`draft`, `credit_note`) only support `eq`.

Pass the *decoded* JSON to the script — it encodes for you:

```bash
scripts/pennylane.py get customer_invoices --all \
  --filter '[{"field":"date","operator":"gteq","value":"2026-01-01"},
             {"field":"date","operator":"lteq","value":"2026-03-31"}]'
```

## v2 gotchas (vs v1)

- **IDs are internal Pennylane IDs only** — v1 `source_id` no longer accepted.
- **Monetary amounts must be passed as strings**, not floats
  (`"amount": "1250.00"`), to avoid rounding drift.
- **One object per create call** — no multi-object batch creation.
- **Renamed fields**: `plan_item` → `ledger_account`, *Estimates* → *Quotes*.
- **Files** use the `file_attachment` resource, not inline base64.

## Rate limits

v2 enforces rate limiting (exact ceiling not published). On `429`, back off and
retry. Prefer `--all` with `--limit 100` over many small page requests, and
filter server-side rather than fetching everything and filtering locally.
