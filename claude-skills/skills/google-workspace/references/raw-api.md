# Raw API patterns

When no first-class `gog` command fits (see [workflows.md](workflows.md)),
use one of the escape hatches, in this order:

1. `gog <service> raw …` — lossless dump of one object as Google returns it
2. `gog api call …` — any Google Discovery API method (read or write)
3. `gog schema --json` — the command/flag contract of the CLI itself

## `gog api` — Discovery-backed generic calls

```
gog api list                                   # all Discovery APIs
gog api describe <api> <version>               # resources + methods of one API
gog api describe <api> <version> <method>      # one method: params, body, scopes
gog api call <api> <version> <resource.method> [flags]
```

`gog api call` flags:

- `--params '<json>'` — path + query parameters (one JSON object, default `{}`)
- `--body '<json>'` or `--body @file.json` — request body (POST/PUT/PATCH)
- `--scope <SCOPE>` — OAuth scope override (default: narrowest Discovery scope)
- `--allow-write` — required for any non-read HTTP method; also asks for
  confirmation unless `--force`
- `--no-cache` — bypass the 24h Discovery-document cache
- `--dry-run` (global) — print the intended request, call nothing
- `--json` (global) — machine output

### Always discover first

Do not guess parameter names — describe the method:

```bash
gog api list --json | jq -r '.items[] | "\(.name) \(.version)"'
gog api describe gmail v1
gog api describe gmail v1 users.messages.list
gog api describe drive v3 files.create
gog api describe sheets v4 spreadsheets.batchUpdate
gog api describe calendar v3 events.insert
```

The method description is the Discovery fragment: read `parameters` (for
`--params`) and `request` (for `--body`).

### Examples

```bash
# Read
gog api call gmail v1 users.messages.list \
  --params '{"userId":"me","q":"is:unread","maxResults":50}' --json

# Write: preview first, then execute
gog api call calendar v3 events.insert \
  --params '{"calendarId":"primary","conferenceDataVersion":1,"sendUpdates":"all"}' \
  --body @event.json --allow-write --dry-run
gog api call calendar v3 events.insert \
  --params '{"calendarId":"primary","conferenceDataVersion":1,"sendUpdates":"all"}' \
  --body @event.json --allow-write --force --json
```

Cases with no first-class command are the reason to reach for this
(e.g. Chat cards: `chat v1 spaces.messages.create`).

## `gog <service> raw` — lossless object dumps

Return the canonical Google API response instead of gog's curated output.
Available for: `calendar`, `contacts`, `docs`, `drive`, `forms`, `gmail`,
`people`, `sheets`, `slides`, `tasks`.

```bash
gog drive raw <fileId> --pretty
gog drive raw <fileId> --fields 'id,name,mimeType,owners(emailAddress)' --json
gog gmail raw <messageId> --format metadata --json
gog docs raw <docId> --json > doc-api.json
gog docs raw <docId> --tab "Notes" --pretty      # or --all-tabs
gog sheets raw <sheetId> --include-grid-data --json
gog sheets raw <sheetId> --sheet "Quarterly Data" --include-grid-data --json
gog calendar raw primary <eventId> --pretty
gog tasks raw <tasklistId> <taskId> --pretty
gog contacts raw people/c123 --person-fields names,emailAddresses --json
```

`raw` is a single-object `get`; for listing many objects use the service's
list/search command or `gog api call … .list`. Drive raw redacts capability
URLs (`webContentLink`, `exportLinks`, `thumbnailLink`, …) unless you pass
`--fields` explicitly. Raw output can contain private content — do not paste
it into logs or LLM context without `--wrap-untrusted`.

## Command contract — `gog schema`

```bash
gog schema --json                     # whole CLI (commands, flags, automation)
gog schema drive ls                   # one command path
gog schema --json | jq '.automation.exit_codes'
```

Use it to check that a flag exists before scripting it; `gog <cmd> --help`
gives the human view.

## Output flags

| Flag | Effect |
|---|---|
| `--json` / `-j` | JSON on stdout (best for scripts) |
| `--plain` / `-p` | stable TSV, no colors |
| `--results-only` | JSON: emit only the primary result (drops `nextPageToken` etc.) |
| `--select a,b.c` | JSON: keep only these fields (dot paths) |
| `--wrap-untrusted` | mark fetched free text as untrusted external content (use before feeding an LLM) |
| `--fields` | on commands with a Drive/Calendar field mask, trims the response server-side |

`--results-only` and `--select` require `--json`. Data goes to stdout;
prompts and diagnostics to stderr.

```bash
gog drive ls --max 20 --fields 'files(id,name,mimeType,modifiedTime),nextPageToken' --json
gog gmail search 'is:unread' --max 50 --json --results-only --select id,subject
```

## Safety flags

| Flag | Effect |
|---|---|
| `--readonly` | reject mutating API requests at runtime (`GOG_READONLY=1`) |
| `--gmail-no-send` | block Gmail send operations |
| `--enable-commands-exact a.b,c.d` | allow only these exact commands (`--enable-commands` = prefixes, `--disable-commands` = deny list) |
| `--dry-run` / `-n` | print intended actions, change nothing |
| `--no-input` | never prompt; fail instead (CI/agents) |
| `--force` / `-y` | skip confirmation on destructive commands |

For agent sessions: `gog --readonly --no-input --wrap-untrusted …`. Always
`--dry-run` a mutating command and show it to the user before running it.

## Pagination

There is no NDJSON `--page-all`. Use the command's own flags (verify with
`gog <cmd> --help`):

```bash
gog gmail search 'is:unread' --all --json --results-only      # all pages
gog drive ls --max 100 --page TOKEN --json                    # manual: --page <nextPageToken>
gog calendar events --week --all-pages --json
gog tasks list @default --all --json
```

Manual paging: read `nextPageToken` from the (non-`--results-only`) JSON
envelope and pass it as `--page`. With `gog api call`, pass `pageToken` /
`pageSize` inside `--params` and loop yourself.

## Uploads and downloads

Use the first-class commands rather than raw calls:

```bash
gog drive upload ./report.pdf --parent FOLDER_ID              # upload
gog drive download DOC_ID --format pdf --out ./doc.pdf        # export a Google Doc
gog drive download FILE_ID --out ./file.bin                   # binary file
gog gmail attachment MSG_ID ATT_ID --out ./file.pdf           # Gmail attachment
```

## Exit codes

```
0    ok                  success
1    error               generic / unclassified failure
2    usage               bad syntax, arguments or flags
3    empty_results       query succeeded with no results (--fail-empty)
4    auth_required       missing / expired / revoked credentials
5    not_found           resource does not exist
6    permission_denied   authenticated but not allowed
7    rate_limited        quota or rate limit reached
8    retryable           transient server / network / circuit-breaker failure
10   config              required local configuration missing
11   orphaned            Docs comment no longer attached to content
130  cancelled           interrupted (Ctrl-C)
```

Branch on the code, not on stderr text:

```bash
out=$(gog --no-input --json drive get "$FILE_ID" 2>&1); rc=$?
if [ $rc -ne 0 ]; then
  case $rc in
    4)  echo "auth — run: gog auth doctor" ;;
    5)  echo "not found" ;;
    6)  echo "permission denied" ;;
    7|8) echo "retry later" ;;
    2)  echo "usage — $out" ;;
    *)  echo "error — $out" ;;
  esac
fi
```

`gog auth list --check --json --no-input` and `gog auth doctor --check --json
--no-input` verify credentials without side effects.
