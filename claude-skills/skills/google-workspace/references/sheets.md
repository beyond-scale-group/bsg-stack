# Sheets

Prefer the first-class `gog sheets` commands (`get`, `update`, `append`,
`clear`, `create`, `metadata`, `export`, plus `format`, `freeze`, `add-tab`,
`batch-request`, ...). Use `gog api call sheets v4 ...` for calls with no
dedicated command (`values.batchGet`, `developerMetadata`, ...);
`gog sheets raw <id>` gives a lossless spreadsheet dump.

Global flags: `--json` / `--plain`, `--results-only`, `--select`,
`--account <email|alias>` (or `GOG_ACCOUNT`), `--dry-run`, `--no-input`,
`--force`, `--readonly`. Exit codes: 0 ok, 2 usage, 3 empty results,
4 auth_required, 5 not_found, 6 permission_denied, 7 rate_limited,
8 retryable, 10 config.

## A1 notation (ranges)

```
Sheet1!A1             single cell
Sheet1!A1:D10         rectangular range
Sheet1!A:A            entire column
Sheet1!2:2            entire row
Sheet1                whole sheet
'Sales Data'!A1:C10   sheet name with space — single quotes around name
```

The range is a positional argument, so quote it for the shell, and keep
the single quotes around names with spaces:

```bash
gog sheets get ID "'Sales Data'!A1:C10"
```

A named range name is accepted anywhere an A1 range is.

## Read

```bash
gog sheets get ID 'Sheet1!A1:D10' --json
gog sheets get ID Sheet1                                # whole tab
gog sheets get ID 'Sheet1!A1:D10' --render FORMULA      # or FORMATTED_VALUE / UNFORMATTED_VALUE
gog sheets get ID 'Sheet1!A1:D10' --dimension COLUMNS   # column-major

# CSV-ish output for pipelines
gog sheets get ID 'Sheet1!A1:D10' --plain

# Multiple ranges in one call (no dedicated command)
gog api call sheets v4 spreadsheets.values.batchGet --json --params '{
  "spreadsheetId":"ID",
  "ranges":["Sheet1!A1:B10","Sheet2!C1:D5"]
}'
```

Response shape: `values` is an array of rows; each row is an array of
cells (as strings). Missing trailing cells are omitted.

## Append rows

```bash
# Inline values: rows separated by commas, cells by pipes
gog sheets append ID 'Sheet1!A:C' 'Alice|100|true'

# JSON 2D array (safest for text with commas/pipes); @file and @- (stdin) work too
gog sheets append ID 'Sheet1!A:C' --values-json '[["Alice",100],["Bob",200]]'

# Finer control
gog sheets append ID 'Sheet1!A:C' \
  --values-json '[["Alice",100,"=B1*2"]]' \
  --input USER_ENTERED --insert INSERT_ROWS
```

### `valueInputOption`

- `RAW` — values stored as-is. `"=A1+1"` becomes the literal string.
- `USER_ENTERED` — values parsed like typing in the UI: formulas, dates,
  currency strings become real values. **Default for almost everything** (`--input USER_ENTERED` is the `gog` default; pass `--input RAW` to store literally).

### `insertDataOption` (append only)

- `OVERWRITE` — writes over existing rows starting at the first
  empty row.
- `INSERT_ROWS` — (`--insert INSERT_ROWS`) inserts new rows, shifting existing rows down.

## Update (overwrite specific range)

```bash
gog sheets update ID 'Sheet1!B2' --values-json '[["=SUM(A:A)"]]' --input USER_ENTERED

# Inline form (cells separated by pipes)
gog sheets update ID 'Sheet1!A1:B1' 'Header 1|Header 2'

# Multiple ranges at once
gog sheets batch-update ID --data-json '[
  {"range":"Sheet1!A1","values":[["Header"]]},
  {"range":"Sheet2!B2:C2","values":[["x","y"]]}
]'
```

Add `--fail-on-formula-error` to `update` to read back the range and fail if
any cell shows a Sheets formula error (`#REF!`, `#NAME?`, ...).

## Clear

```bash
gog sheets clear ID 'Sheet1!A2:Z'
```

## Create a spreadsheet

```bash
gog sheets create "Q2 2026 Tracker" --sheets Summary,Raw --json
gog sheets create "Q2 2026 Tracker" --parent FOLDER_ID   # directly in a Drive folder
```

Returns `{ "spreadsheetId": "...", "spreadsheetUrl": "..." }` (use `--json`).
Other spreadsheet-level commands: `gog sheets copy ID "New title"`,
`gog sheets metadata ID`.

## Structural changes (batchUpdate)

Common changes have dedicated commands:

```bash
gog sheets add-tab ID "New tab" --index 0
gog sheets delete-tab ID "Old tab"                      # asks; --force skips
gog sheets rename-tab ID "Old name" "New name"
gog sheets freeze ID --rows 1 --sheet Summary          # 0 to unfreeze
gog sheets format ID 'Sheet1!A1:Z1' \
  --format-json '{"textFormat":{"bold":true}}' --format-fields textFormat.bold
gog sheets resize-columns ID 'Sheet1!A:E' --auto
```

For everything else, `gog sheets batch-request` submits an atomic array of
Sheets API `requests` (asks for confirmation; use `--force` to skip). Look
up a request's schema with `gog api describe sheets v4 spreadsheets.batchUpdate`.

Common requests:

```json
// Add a sheet/tab
{"addSheet":{"properties":{"title":"New tab","index":0}}}

// Delete a sheet
{"deleteSheet":{"sheetId":123456}}

// Freeze first row
{"updateSheetProperties":{
  "properties":{"sheetId":0,"gridProperties":{"frozenRowCount":1}},
  "fields":"gridProperties.frozenRowCount"
}}

// Bold the header row
{"repeatCell":{
  "range":{"sheetId":0,"startRowIndex":0,"endRowIndex":1},
  "cell":{"userEnteredFormat":{"textFormat":{"bold":true}}},
  "fields":"userEnteredFormat.textFormat.bold"
}}

// Auto-resize columns
{"autoResizeDimensions":{
  "dimensions":{"sheetId":0,"dimension":"COLUMNS","startIndex":0,"endIndex":5}
}}
```

Apply (the value is a JSON array of requests, or `@file` / `@-`):

```bash
gog sheets batch-request ID --requests-json '[ ... ]'
```

## Find sheetId (tab numeric ID)

Structural `requests` need `sheetId`, not the tab name:

```bash
gog sheets raw ID | jq '.sheets[] | {title: .properties.title, sheetId: .properties.sheetId}'
```

## Export

```bash
# Single sheet only (first tab) as CSV
gog sheets export ID --format csv --out ./data.csv

# Full workbook as xlsx (default format) or pdf
gog sheets export ID --format xlsx --out ./book.xlsx
gog sheets export ID --format pdf --out ./book.pdf
```

`--overwrite` replaces an existing output file. `gog drive download ID
--format csv|xlsx|pdf` is equivalent.
