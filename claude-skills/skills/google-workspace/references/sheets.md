# Sheets

Prefer `+read` and `+append` for simple cases. Raw API for bulk updates,
formulas, formatting, and anything involving batchUpdate.

## A1 notation (ranges)

```
Sheet1!A1             single cell
Sheet1!A1:D10         rectangular range
Sheet1!A:A            entire column
Sheet1!2:2            entire row
Sheet1                whole sheet
'Sales Data'!A1:C10   sheet name with space — single quotes around name
```

Always JSON-escape in `--params`:

```bash
gws sheets spreadsheets values get \
  --params '{"spreadsheetId":"ID","range":"'"'"'Sales Data'"'"'!A1:C10"}'
```

Shell escaping nightmare? Use the `+read` helper instead — it handles
quoting for you.

## Read

```bash
# Helper
gws sheets +read --spreadsheet ID --range 'Sheet1!A1:D10' --format csv
gws sheets +read --spreadsheet ID --range Sheet1                    # whole tab

# Raw
gws sheets spreadsheets values get --params '{"spreadsheetId":"ID","range":"Sheet1!A1:D10"}'

# Multiple ranges in one call
gws sheets spreadsheets values batchGet --params '{
  "spreadsheetId":"ID",
  "ranges":["Sheet1!A1:B10","Sheet2!C1:D5"]
}'
```

Response shape: `values` is an array of rows; each row is an array of
cells (as strings). Missing trailing cells are omitted.

## Append rows

```bash
# Helper
gws sheets +append --spreadsheet ID --values 'Alice,100,true'
gws sheets +append --spreadsheet ID --json-values '[["Alice",100],["Bob",200]]'

# Raw (finer control)
gws sheets spreadsheets values append \
  --params '{
    "spreadsheetId":"ID",
    "range":"Sheet1!A:C",
    "valueInputOption":"USER_ENTERED",
    "insertDataOption":"INSERT_ROWS"
  }' \
  --json '{"values":[["Alice",100,"=B1*2"]]}'
```

### `valueInputOption`

- `RAW` — values stored as-is. `"=A1+1"` becomes the literal string.
- `USER_ENTERED` — values parsed like typing in the UI: formulas, dates,
  currency strings become real values. **Default for almost everything.**

### `insertDataOption` (append only)

- `OVERWRITE` (default) — writes over existing rows starting at the first
  empty row.
- `INSERT_ROWS` — inserts new rows, shifting existing rows down.

## Update (overwrite specific range)

```bash
gws sheets spreadsheets values update \
  --params '{
    "spreadsheetId":"ID",
    "range":"Sheet1!B2",
    "valueInputOption":"USER_ENTERED"
  }' \
  --json '{"values":[["=SUM(A:A)"]]}'

# Multiple ranges at once
gws sheets spreadsheets values batchUpdate \
  --params '{"spreadsheetId":"ID"}' \
  --json '{
    "valueInputOption":"USER_ENTERED",
    "data":[
      {"range":"Sheet1!A1","values":[["Header"]]},
      {"range":"Sheet2!B2:C2","values":[["x","y"]]}
    ]
  }'
```

## Clear

```bash
gws sheets spreadsheets values clear --params '{"spreadsheetId":"ID","range":"Sheet1!A2:Z"}'
```

## Create a spreadsheet

```bash
gws sheets spreadsheets create --json '{
  "properties":{"title":"Q2 2026 Tracker"},
  "sheets":[{"properties":{"title":"Summary"}},{"properties":{"title":"Raw"}}]
}'
```

Returns `{ "spreadsheetId": "...", "spreadsheetUrl": "..." }`.

## Structural changes (batchUpdate)

`spreadsheets.batchUpdate` takes an array of `requests`, one per change.
Discover the request schema first:

```bash
gws schema sheets.spreadsheets.batchUpdate --resolve-refs | head -200
```

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

Apply:

```bash
gws sheets spreadsheets batchUpdate \
  --params '{"spreadsheetId":"ID"}' \
  --json '{"requests":[ ... ]}'
```

## Find sheetId (tab numeric ID)

Structural `requests` need `sheetId`, not the tab name:

```bash
gws sheets spreadsheets get --params '{"spreadsheetId":"ID"}' \
  | jq '.sheets[] | {title: .properties.title, sheetId: .properties.sheetId}'
```

## Export

```bash
# Via Drive export — single sheet only (first tab)
gws drive files export --params '{"fileId":"ID","mimeType":"text/csv"}' --output ./data.csv

# Full workbook as xlsx
gws drive files export --params '{
  "fileId":"ID",
  "mimeType":"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
}' --output ./book.xlsx
```
