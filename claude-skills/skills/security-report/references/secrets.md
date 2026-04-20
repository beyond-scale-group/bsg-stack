# Secret Scanning

How to find secrets that shouldn't be in the repo.

## Scope

Scans **tracked files only** (`git ls-files`) — untracked and gitignored
files are out of scope. If a secret is in `.env` but `.env` is gitignored,
that's fine; if `.env` is tracked, that's a silence-breaker.

## Patterns

Default regex catalog (defined in `scripts/secrets.sh`):

| Pattern                                   | Kind                      |
| ----------------------------------------- | ------------------------- |
| `AKIA[0-9A-Z]{16}`                        | AWS Access Key ID         |
| `aws_secret_access_key\s*=\s*[A-Za-z0-9/+=]{40}` | AWS Secret Access Key |
| `ghp_[A-Za-z0-9]{36}`                     | GitHub personal token     |
| `ghs_[A-Za-z0-9]{36}`                     | GitHub server token       |
| `sk-[A-Za-z0-9]{20,}`                     | OpenAI / Anthropic        |
| `xoxb-[0-9A-Za-z-]+`                      | Slack bot token           |
| `-----BEGIN (RSA|OPENSSH|EC) PRIVATE KEY-----` | Private key            |
| `eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+` | JWT (informational) |

JWT matches are informational by default — often legitimate test
fixtures. The silence-breaker only fires on actual credentials.

## Tracked env files

Independently of regex patterns, `secrets.sh` lists any tracked file
whose basename starts with `.env` (e.g. `.env`, `.env.local`,
`.env.production`). A tracked `.env.example` with placeholder values
is OK only if it explicitly contains no real secret patterns — the
regex scan still runs across it.

## How to run

```bash
bash scripts/secrets.sh                          # fresh scan
bash scripts/secrets.sh --snapshot /tmp/*.json   # use existing snapshot
```

## Output schema

```json
{
  "summary": {
    "findings": 1,
    "trackedEnvFiles": 0,
    "scannedFiles": 428
  },
  "findings": [
    {
      "file": "src/config.js",
      "line": 17,
      "kind": "AWS Access Key ID",
      "match": "AKIAIOSFODNN7EXAMPLE"
    }
  ],
  "trackedEnvFiles": []
}
```

Matches are returned with enough context for a reviewer to decide, but
the raw match is truncated or redacted in the public report —
`scripts/secrets.sh --redact` masks the middle of every match.

## `.securityignore`

A `.gitignore`-style file at the repo root. Each line is either a
glob (to skip the file entirely) or a `pattern:` directive for
fine-grained exclusion.

```
# Skip the whole file
tests/fixtures/fake-aws-keys.txt

# Skip a specific pattern in one file
pattern: AKIAIOSFODNN7EXAMPLE in docs/examples/aws-readme.md
```

The pattern-directive form catches test vectors that are genuinely
fake but otherwise match a regex.

## How to interpret

- **`findings[]` non-empty** → silence-breaker. Show each finding's
  file + line; let the user confirm whether it's real or a fixture.
- **`trackedEnvFiles[]` non-empty** → always a silence-breaker, even
  if the file has no regex matches. Tracked `.env` is an architectural
  smell.
- **`scannedFiles == 0`** → scan was skipped or misconfigured.
  Investigate.

## What NOT to do

- Don't rotate credentials as part of the tick.
- Don't commit a redacted copy to the report if the raw secret was
  already pushed — the audit trail links to the PR where it leaked.
  Rotation and git-history cleanup are separate explicit asks.
