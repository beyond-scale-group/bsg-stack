# `/bsg-stack status` — one-line summary

The terse cousin of `doctor`. Same read-only contract, single line of
output. Useful in `/loop`, status bars, and chat.

Implemented as `doctor.sh --status` — there is no separate script.

## When to invoke

- "BSG status"
- "What agents are configured?"
- "Quick health check"
- Anything that wants a glance, not a full table

## How to invoke

```bash
bash claude-skills/skills/bsg-stack/scripts/doctor.sh --status
```

## Output format

```
BSG: 7/9 ✓, 1 ⚠, 1 ✗ — run /bsg-stack init
```

The number triplet is `(ok / warn / missing)` across all checked
rows (agents + labels + autopilot). The trailing hint tells the user
the next remediation verb when something is missing.

When everything is `✓`:

```
BSG: 11/11 ✓
```

## Exit codes

Same as `doctor`:

| Code | Meaning |
|---|---|
| `0` | No `✗` rows |
| `1` | At least one `✗` row |
| `2` | Bad invocation |

## When to use `status` vs `doctor`

- `status` — quick yes/no signal. Fits in a notification or chat reply.
- `doctor` — when a row is `✗` and you want to know which one. Run it
  next; it shares the same scan, just renders fully.
