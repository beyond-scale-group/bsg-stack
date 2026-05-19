# Stale README commands

How `commands.sh` finds README commands that no longer exist.

## Scope

Scans every file in `.readmes[]` for shell-command patterns that
target a named script:

- `npm run X`, `pnpm run X`, `yarn run X` → checked against
  `package.json` `scripts.*`
- `pnpm X`, `yarn X` → same (those package managers run scripts
  directly without `run`)
- `make X` → checked against the targets parsed from `Makefile`

A command is flagged stale when `X` is not present in the relevant
list. Reserved verbs (`install`, `test`, `start`, …) are skipped
because they map to built-ins, not user scripts.

## How to run

```bash
bash scripts/commands.sh
bash scripts/commands.sh --snapshot /tmp/docs-snap.json
```

## Output schema

```json
{
  "summary": { "staleCommands": 2 },
  "staleCommands": [
    { "readme": "README.md", "tool": "npm run", "command": "watch" },
    { "readme": "subproj/README.md", "tool": "make", "command": "package" }
  ]
}
```

## Limitations

- Only triggers when `package.json` has a `scripts` block (otherwise
  the README may be documenting a globally-installed binary).
- Does not handle multi-line command invocations or shell `&&` chains
  beyond what grep can recognize.
- Does not check that the README's *flag set* still matches the
  script's flags — only that the command name still exists.
