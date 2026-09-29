# Drive

Prefer the first-class `gog drive` commands (`ls`, `search`, `get`,
`download`, `upload`, `mkdir`, `move`, `rename`, `copy`, `share`,
`permissions`, `delete`). Use `gog api call drive v3 ...` for anything they
do not cover (domain-wide permission rules, arbitrary `files.update`
payloads); `gog drive raw <fileId>` gives a lossless metadata dump.

Global flags: `--json` / `--plain`, `--results-only`, `--select`,
`--account <email|alias>` (or `GOG_ACCOUNT`), `--dry-run`, `--no-input`,
`--force`, `--readonly`. Exit codes: 0 ok, 2 usage, 3 empty results,
4 auth_required, 5 not_found, 6 permission_denied, 7 rate_limited,
8 retryable, 10 config.

## Drive query language (`q` param)

Pass it to `gog drive search --raw-query '<q>'`, to `gog drive ls --query '<q>'`,
or as `q` inside `--params` of `gog api call drive v3 files.list`. Without
`--raw-query`, `gog drive search` treats the argument as plain full-text.
String values are single-quoted.

```
name = 'Quarterly report.pdf'
name contains 'report'
fullText contains 'invoice 2026'        free-text search
mimeType = 'application/pdf'
mimeType != 'application/vnd.google-apps.folder'
'FOLDER_ID' in parents                   items inside a folder
'me' in owners
'alice@x.com' in writers
sharedWithMe = true
starred = true
trashed = false                          default includes trashed; filter explicitly
modifiedTime > '2026-01-01T00:00:00Z'
createdTime < '2026-04-01T00:00:00Z'
```

Operators: `=` `!=` `<` `<=` `>` `>=` `contains` · combine with `and` / `or`
/ `not` and parentheses.

## Common MIME types

```
folder                    application/vnd.google-apps.folder
google doc                application/vnd.google-apps.document
google sheet              application/vnd.google-apps.spreadsheet
google slides             application/vnd.google-apps.presentation
google form               application/vnd.google-apps.form
google drawing            application/vnd.google-apps.drawing
shortcut                  application/vnd.google-apps.shortcut
pdf                       application/pdf
word                      application/vnd.openxmlformats-officedocument.wordprocessingml.document
excel                     application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
image                     image/png, image/jpeg, image/webp
```

## List / search

```bash
# All PDFs modified in the last week
gog drive search "mimeType = 'application/pdf' and modifiedTime > '2026-04-09T00:00:00Z' and trashed = false" \
  --raw-query --max 50 --json

# Contents of a folder (newest first by default; --sort / --order to change)
gog drive ls --parent FOLDER_ID --max 100 --json
gog drive ls --parent FOLDER_ID --query "trashed = false" \
  --fields 'files(id,name,mimeType,size),nextPageToken'

# Plain full-text search
gog drive search 'invoice 2026' --max 20

# Paginate: --page <nextPageToken>, or use the raw call with a pageToken loop
gog drive ls --query 'trashed = false' --max 100 --page TOKEN
```

Shared drives are included by default (`--all-drives`); use
`--no-all-drives` for My Drive only, `--drive DRIVE_ID` to scope a search to
one shared drive, and `--parent FOLDER_ID` to scope it to a folder. Get
drive IDs with `gog drive drives`.

Raw equivalent (full control of `corpora`, `orderBy`, ...):

```bash
gog api call drive v3 files.list --json --params '{
  "q":"name contains '\''report'\''",
  "supportsAllDrives":true,
  "includeItemsFromAllDrives":true,
  "corpora":"allDrives",
  "pageSize":50,
  "fields":"files(id,name,modifiedTime,owners(emailAddress)),nextPageToken",
  "orderBy":"modifiedTime desc"
}'
```

## Create a folder

```bash
gog drive mkdir "New folder" --parent PARENT_FOLDER_ID
```

## Upload

```bash
gog drive upload ./report.pdf --parent FOLDER_ID
gog drive upload ./report.pdf --parent FOLDER_ID --name "Q2 report.pdf"

# Convert to a native Google format on upload (doc | sheet | slides)
gog drive upload ./notes.md --convert-to doc
gog drive upload ./data.csv --convert-to sheet

# Replace the content of an existing file (keeps link and permissions)
gog drive upload ./report-v2.pdf --replace FILE_ID
```

## Download / export

```bash
# Native Drive file (binary); default output dir is gog's config dir, so pass --out
gog drive download FILE_ID --out ./file.bin

# Export a Google Doc to PDF (--format pdf|csv|xlsx|pptx|txt|png|docx|md)
gog drive download DOC_ID --format pdf --out ./doc.pdf

# Export a Sheet to CSV (first sheet only, Drive export limitation)
gog drive download SHEET_ID --format csv --out ./sheet.csv
```

Add `--overwrite` to replace an existing output file. For an export MIME
type `--format` does not cover, call `files.export` directly
(`gog api call drive v3 files.export --params '{"fileId":"ID","mimeType":"..."}'`).

## Copy / move / rename

```bash
# Copy
gog drive copy FILE_ID "Copy of report.pdf" --parent FOLDER_ID

# Move (changes the parent folder)
gog drive move FILE_ID --parent NEW_PARENT

# Rename
gog drive rename FILE_ID "New name"
```

## Share / permissions

```bash
# List permissions
gog drive permissions FILE_ID --json

# Share with a user (reader/commenter/writer); --notify sends the invitation email
gog drive share FILE_ID --to user --email alice@x.com --role writer --notify

# Share a whole domain
gog drive share FILE_ID --to domain --domain the-shift.ai --role reader

# Anyone with the link
gog drive share FILE_ID --to anyone --role reader

# Remove a permission
gog drive unshare FILE_ID PERM_ID
```

`gog drive share` supports roles `reader` · `commenter` · `writer`. Ownership
transfer and shared-drive roles (`owner`, `organizer`, `fileOrganizer`) go
through the raw API:

```bash
gog api call drive v3 permissions.create --allow-write --force \
  --params '{"fileId":"FILE_ID","supportsAllDrives":true}' \
  --body '{"role":"fileOrganizer","type":"user","emailAddress":"alice@x.com"}'
```

Roles: `owner` · `organizer` (shared drives) · `fileOrganizer` · `writer` ·
`commenter` · `reader`.

## Trash / delete

```bash
# Trash (recoverable)
gog drive delete FILE_ID

# Permanent delete (no undo)
gog drive delete FILE_ID --permanent
```

Always prefer trash; use `--permanent` only on explicit user request.
Use `--dry-run` to preview and `--force` to skip the confirmation prompt
in non-interactive runs.

## Shared drives

```bash
# List shared drives the user can access
gog drive drives --max 50

# Create a file/folder in a shared drive (use the shared drive ID as parent)
gog drive mkdir "Doc folder" --parent SHARED_DRIVE_ID
gog drive upload ./doc.pdf --parent SHARED_DRIVE_ID
```
