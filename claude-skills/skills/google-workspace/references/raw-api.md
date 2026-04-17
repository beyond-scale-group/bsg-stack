# Raw API patterns

When no `+helper` fits, use the generic pattern:

```
gws <service> <resource> [sub-resource] <method> [--params JSON] [--json BODY] [FLAGS]
```

- `--params <JSON>` — URL path + query parameters (always JSON, one object)
- `--json <JSON>` — request body (for `POST` / `PUT` / `PATCH`)
- `--upload <PATH>` — media upload (multipart)
- `--upload-content-type <MIME>` — override auto-detect
- `--output <PATH>` — write binary response to file (`--format` ignored)
- `--format json|table|yaml|csv` — output shape
- `--api-version <VER>` — override API version
- `--dry-run` — build + validate locally, don't call Google
- `--sanitize <TEMPLATE>` — Model Armor content sanitization

## Always discover first

Before writing a raw call, fetch the live schema — **do not guess
parameter names**:

```bash
gws schema <service>.<resource>.<method>
gws schema <service>.<resource>.<method> --resolve-refs   # inline $ref
```

Examples:

```bash
gws schema gmail.users.messages.list
gws schema drive.files.create --resolve-refs
gws schema sheets.spreadsheets.batchUpdate
gws schema calendar.events.insert
```

The output is a Google Discovery Document fragment. Read
`parameters` (for `--params`) and `request.$ref`/`request` (for `--json`).

## Pagination

```bash
# Auto-paginate, emit one JSON object per page (NDJSON)
gws drive files list --params '{"pageSize":100}' --page-all --page-limit 10 --page-delay 200

# Collect all pages into a single array
gws drive files list --params '{"pageSize":100}' --page-all | jq -s '[.[].files[]]'

# Manual: use --params pageToken from the previous response
gws drive files list --params '{"pageSize":100,"pageToken":"TOKEN_FROM_PREV"}'
```

Guard rails: `--page-limit N` caps pages (default 10), `--page-delay MS`
slows between pages to respect quotas.

## Field selection (smaller responses)

Most list APIs accept `fields` to trim the response server-side:

```bash
gws drive files list --params '{"pageSize":20,"fields":"files(id,name,mimeType,modifiedTime)"}'
gws gmail users messages list --params '{"userId":"me","q":"is:unread","maxResults":50,"fields":"messages(id,threadId)"}'
```

Per-service syntax differs — check `gws schema` → `parameters.fields`.

## Uploads

```bash
# Simple upload (auto-detect MIME from extension)
gws drive files create \
  --json '{"name":"report.pdf","parents":["FOLDER_ID"]}' \
  --upload ./report.pdf

# Force content type
gws drive files create \
  --json '{"name":"blob.bin"}' \
  --upload ./blob.bin --upload-content-type application/octet-stream
```

## Downloads

```bash
# Export a Google Doc as PDF to a file
gws drive files export \
  --params '{"fileId":"DOC_ID","mimeType":"application/pdf"}' \
  --output ./doc.pdf

# Get binary file
gws drive files get --params '{"fileId":"FILE_ID","alt":"media"}' --output ./file.bin
```

## Exit codes

```
0   Success
1   API error (Google returned an error response)
2   Auth error (credentials missing / invalid)
3   Validation (bad arguments or input)
4   Discovery (could not fetch API schema)
5   Internal (unexpected failure)
```

Pattern in scripts:

```bash
if ! out=$(gws gmail +send --to a@x.com --subject hi --body hi 2>&1); then
  code=$?
  case $code in
    2) echo "auth — run: gws auth login" ;;
    1) echo "api — $out" ;;
    3) echo "validation — $out" ;;
    *) echo "error $code — $out" ;;
  esac
  exit $code
fi
```

## Model Armor sanitization (optional)

If the user's responses need content sanitization (e.g. PII redaction on
fetched email bodies), pass a Model Armor template:

```bash
gws gmail users messages get \
  --params '{"userId":"me","id":"MSG_ID","format":"full"}' \
  --sanitize projects/PROJECT/locations/LOCATION/templates/TEMPLATE
```

Env defaults: `GOOGLE_WORKSPACE_CLI_SANITIZE_TEMPLATE` and
`GOOGLE_WORKSPACE_CLI_SANITIZE_MODE=warn|block`. Requires the
`cloud-platform` OAuth scope (`gws auth login --full`).

## Minimal service vocabulary

```
gmail:    users.{labels,messages,threads,drafts,settings,history,watch,stop}
drive:    {files,permissions,comments,replies,revisions,drives,changes,about}
sheets:   spreadsheets + spreadsheets.values + spreadsheets.sheets + .developerMetadata
calendar: {events,calendars,calendarList,acl,freebusy,settings,colors,channels}
slides:   presentations + presentations.pages
tasks:    {tasklists,tasks}
people:   {people,contactGroups,otherContacts}
chat:     {spaces,spaces.members,spaces.messages,media,users,customEmojis}
meet:     {spaces,conferenceRecords}
forms:    forms + forms.responses + forms.watches
keep:     {notes,media}
```

For exact resource paths, always check `gws <service> --help`.
