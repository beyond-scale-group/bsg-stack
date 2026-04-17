# Drive

Prefer `+upload` for uploading. Raw API for search, permissions, folders,
shared drives, exports, and copies.

## Drive query language (`q` param)

Passed as `q` inside `--params`. Strings are quoted with escaped
double-quotes inside JSON.

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
gws drive files list --params '{
  "q":"mimeType=\"application/pdf\" and modifiedTime>\"2026-04-09T00:00:00Z\" and trashed=false",
  "pageSize":50,
  "fields":"files(id,name,modifiedTime,owners(emailAddress)),nextPageToken",
  "orderBy":"modifiedTime desc"
}'

# Contents of a folder
gws drive files list --params '{
  "q":"'"'"'FOLDER_ID'"'"' in parents and trashed=false",
  "pageSize":100,
  "fields":"files(id,name,mimeType,size)"
}'

# Paginate all results
gws drive files list --params '{"q":"trashed=false","pageSize":100}' \
  --page-all --page-limit 50
```

Include shared drives in listings:

```bash
gws drive files list --params '{
  "q":"name contains '\''report'\''",
  "supportsAllDrives":true,
  "includeItemsFromAllDrives":true,
  "corpora":"allDrives"
}'
```

## Create a folder

```bash
gws drive files create --json '{
  "name":"New folder",
  "mimeType":"application/vnd.google-apps.folder",
  "parents":["PARENT_FOLDER_ID"]
}'
```

## Upload

Prefer `+upload` helper. Raw:

```bash
gws drive files create \
  --json '{"name":"report.pdf","parents":["FOLDER_ID"]}' \
  --upload ./report.pdf
```

## Download / export

```bash
# Native Drive file (binary)
gws drive files get --params '{"fileId":"FILE_ID","alt":"media"}' --output ./file.bin

# Export a Google Doc to PDF
gws drive files export --params '{"fileId":"DOC_ID","mimeType":"application/pdf"}' --output ./doc.pdf

# Export a Sheet to CSV (first sheet only, Drive export limitation)
gws drive files export --params '{"fileId":"SHEET_ID","mimeType":"text/csv"}' --output ./sheet.csv
```

## Copy / move / rename

```bash
# Copy
gws drive files copy --params '{"fileId":"FILE_ID"}' \
  --json '{"name":"Copy of report.pdf","parents":["FOLDER_ID"]}'

# Move (update parents)
gws drive files update --params '{
  "fileId":"FILE_ID",
  "addParents":"NEW_PARENT",
  "removeParents":"OLD_PARENT"
}' --json '{}'

# Rename
gws drive files update --params '{"fileId":"FILE_ID"}' --json '{"name":"New name"}'
```

## Share / permissions

```bash
# List permissions
gws drive permissions list --params '{"fileId":"FILE_ID","fields":"permissions(id,type,role,emailAddress)"}'

# Share with a user (reader/commenter/writer)
gws drive permissions create --params '{"fileId":"FILE_ID","sendNotificationEmail":true}' \
  --json '{"role":"writer","type":"user","emailAddress":"alice@x.com"}'

# Share a whole domain
gws drive permissions create --params '{"fileId":"FILE_ID"}' \
  --json '{"role":"reader","type":"domain","domain":"the-shift.ai"}'

# Anyone with the link
gws drive permissions create --params '{"fileId":"FILE_ID"}' \
  --json '{"role":"reader","type":"anyone"}'

# Remove a permission
gws drive permissions delete --params '{"fileId":"FILE_ID","permissionId":"PERM_ID"}'
```

Roles: `owner` · `organizer` (shared drives) · `fileOrganizer` · `writer` ·
`commenter` · `reader`.

## Trash / delete

```bash
# Trash
gws drive files update --params '{"fileId":"FILE_ID"}' --json '{"trashed":true}'

# Permanent delete (no undo)
gws drive files delete --params '{"fileId":"FILE_ID"}'
```

Always prefer trash; use permanent delete only on explicit user request.

## Shared drives

```bash
# List shared drives the user can access
gws drive drives list --params '{"pageSize":50}'

# Create a file in a shared drive
gws drive files create --params '{"supportsAllDrives":true}' \
  --json '{"name":"Doc","parents":["SHARED_DRIVE_ID"]}'
```
