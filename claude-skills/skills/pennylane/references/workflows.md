# Pennylane workflows — multi-company connector

The connector's job: one firm OAuth token, every structure reachable, data
pulled per-company on demand. All commands below assume tokens are stored (run
the OAuth flow in `oauth.md` once).

## 1. Enumerate structures, then iterate

```bash
# List every connected company and keep id + name
scripts/pennylane.py companies --all > /tmp/companies.json
jq -r '.[] | "\(.id)\t\(.name)"' /tmp/companies.json
```

How a firm token scopes a request to one company depends on the token context
and, where required, a company selector on the resource (e.g. a `company_id`
filter or path). Confirm the exact mechanism in the live reference; once known,
loop:

```bash
for id in $(jq -r '.[].id' /tmp/companies.json); do
  scripts/pennylane.py get customer_invoices --all \
    --query company_id="$id" > "/tmp/invoices_${id}.json"
done
```

## 2. Data export & reporting

Export a period and reshape with `jq` (or hand off to a sheet/CSV):

```bash
# All finalized customer invoices for Q1 2026
scripts/pennylane.py get customer_invoices --all \
  --filter '[{"field":"date","operator":"gteq","value":"2026-01-01"},
             {"field":"date","operator":"lteq","value":"2026-03-31"},
             {"field":"draft","operator":"eq","value":false}]' \
  | jq -r '.[] | [.id, .date, .label, .amount, .currency] | @csv'

# Trial-balance style pull from the ledger
scripts/pennylane.py get ledger_entries --all \
  --filter '[{"field":"date","operator":"gteq","value":"2026-01-01"}]'
```

For a branded Word/Excel/PPT report of the exported numbers, pipe the result
into the `md-to-word` / `md-to-office` skills.

## 3. Bookkeeping workflows

- **A/R review** — list draft vs finalized customer invoices, flag overdue by
  filtering on `date`/`deadline` and matching against payments.
- **A/P intake** — `POST /supplier_invoices` with a `file_attachment` for the
  source document; v2 requires the file as a dedicated resource, amounts as
  strings.
- **Chart of accounts** — `GET /ledger_accounts` to reconcile your mapping
  before posting entries.
- **Categories** — `GET /categories` to align analytical tagging across
  structures.

Create example (note: amount as a **string**, internal ids only):

```bash
scripts/pennylane.py post customer_invoices --data '{
  "customer_id": 12345,
  "date": "2026-06-30",
  "deadline": "2026-07-30",
  "draft": true,
  "currency": "EUR",
  "invoice_lines": [
    {"label": "Conseil", "quantity": "1", "unit_amount": "1250.00", "vat_rate": "FR_200"}
  ]
}'
```

Field names/VAT codes vary — validate the create payload against the live
`POST /customer_invoices` reference before relying on it.

## 4. Operational hygiene

- One process per token store (refresh rotation is not concurrency-safe).
- Verify a token with `scripts/pennylane.py me` before a long export.
- Keep `client_secret` and the token store out of git; both grant full access.
- On `401` mid-run, the script auto-refreshes; on persistent `401`, the refresh
  token was rotated out elsewhere — re-run the `auth-url` → `exchange` flow.
