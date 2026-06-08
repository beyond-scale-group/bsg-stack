# IMAP search query — operator reference

The `imap-search.py` and `imap-fetch.py` scripts pass their `--query`
verbatim to the server's IMAP `SEARCH` command. The full operator set is
defined in [RFC 3501 §6.4.4](https://www.rfc-editor.org/rfc/rfc3501#section-6.4.4).
The common ones, with examples:

## Date predicates

Dates use the format `dd-Mon-yyyy` (e.g. `01-Jun-2026`). `SINCE` is
inclusive, `BEFORE` is exclusive.

| Operator                      | Matches                                       |
|---|---|
| `SINCE 01-Jun-2026`           | messages received on or after that date       |
| `BEFORE 01-Jun-2026`          | messages received strictly before             |
| `ON 01-Jun-2026`              | messages received on that exact date          |
| `SENTSINCE 01-Jun-2026`       | uses `Date:` header instead of arrival time   |

## Sender / recipient

| Operator                      | Example                                       |
|---|---|
| `FROM "addr-or-name"`         | `FROM "client@example.com"`                   |
| `TO "addr-or-name"`           | `TO "grenoble@prizoners.com"`                 |
| `CC "addr-or-name"`           | `CC "team@x.com"`                             |
| `BCC "addr-or-name"`          | `BCC "archive@x.com"`                         |

Substring match on the header, so `FROM "client"` matches both
`client@a.com` and `realclient@b.com`. Wrap multi-word strings in
double quotes.

## Content

| Operator                      | Matches                                       |
|---|---|
| `SUBJECT "text"`              | substring in `Subject:` header                |
| `BODY "text"`                 | substring in the body                         |
| `TEXT "text"`                 | header OR body                                |
| `HEADER name "value"`         | arbitrary header (e.g. `HEADER X-Mailer "Outlook"`) |

## Flags

| Operator                      | Matches                                       |
|---|---|
| `UNSEEN` / `SEEN`             | unread / read                                  |
| `ANSWERED` / `UNANSWERED`     | replied / not replied                         |
| `FLAGGED` / `UNFLAGGED`       | starred                                       |
| `DELETED` / `UNDELETED`       | marked for expunge                            |
| `DRAFT` / `UNDRAFT`           | in drafts state                               |
| `RECENT`                      | newly arrived this session (RFC quirk)        |
| `KEYWORD "label"`             | matches custom label/keyword                  |

## Size

| Operator                      | Matches                                       |
|---|---|
| `LARGER 1000000`              | messages > 1 MB                               |
| `SMALLER 10000`               | messages < 10 KB                              |

## Combinators

By default, multiple predicates are AND'd together:

```
FROM "client@x.com" UNSEEN SINCE 01-Jun-2026
```

`OR` takes two args (binary, not n-ary):

```
OR (FROM "client@a.com") (FROM "client@b.com")
```

`NOT` negates the following predicate:

```
NOT FROM "newsletter@"
NOT (FROM "no-reply" OR FROM "automated")
```

Parens group; the outer parens are added by the script if missing.

## Recipes

| Goal                                          | Query                                            |
|---|---|
| Unread from this week                         | `UNSEEN SINCE 01-Jun-2026`                       |
| Email needing a reply, this month             | `UNANSWERED UNSEEN SINCE 01-Jun-2026`            |
| From a specific domain                        | `FROM "@prizoners.com"`                          |
| Customer reservations                         | `(SUBJECT "réservation" OR SUBJECT "reservation")` |
| Large attachments to triage                   | `LARGER 5000000`                                 |
| Sent to a specific client                     | `TO "client@example.com"` (in Sent folder)       |
| Anything with "facture" or "devis"            | `(BODY "facture" OR BODY "devis")`               |
| Forwarded auto-responses                      | `SUBJECT "Out of office"`                        |

## Gmail-specific extensions

Gmail's IMAP server accepts `X-GM-RAW`, which embeds the **full Gmail
search syntax** (the one you'd use in the Gmail web UI) as a single
predicate:

```
X-GM-RAW "label:cse newer_than:30d"
X-GM-RAW "has:attachment filename:pdf"
X-GM-RAW "from:client@x.com OR from:partner@y.com"
```

This is the most expressive option for Gmail accounts — Gmail's
free-text search beats raw IMAP for almost anything. Wrap the query in
double quotes; escape internal quotes by doubling them (`""`).

`X-GM-LABELS` matches by Gmail label:

```
X-GM-LABELS "Important"
X-GM-LABELS "Newsletter"
```

These extensions don't exist on Outlook/iCloud/Fastmail — stick to the
standard operators when writing portable queries.
