# Renovate Presets

Shared [Renovate](https://docs.renovatebot.com/) configuration for repos in
the BSG portfolio. Using a preset keeps dependency-update behaviour
consistent across acquisitions without copy-pasting config into every repo.

## Presets

| File | Use for | Notes |
|------|---------|-------|
| `scala_config.json` | sbt / Scala projects | Automerges patch + minor, holds majors, splits sbt minor/patch updates. Hourly PR limit: 2. |
| `react_config.json` | npm / React projects | Automerges patch + minor, holds majors, splits npm minor/patch updates. Hourly PR limit: 5. |

Common defaults in both presets:

- `baseBranches: ["main"]`
- `platformAutomerge: true`
- `rebaseWhen: "auto"`
- `prConcurrentLimit` set to avoid Renovate flooding CI

## How to install

In your repo's `renovate.json`:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "github>beyond-scale-group/bsg-stack//renovate/scala_config"
  ]
}
```

Replace `scala_config` with `react_config` for frontend repos. `extends`
is merged, not replaced — override any rule inline in your own
`renovate.json`.

See the root [`INSTALL.md`](../INSTALL.md#2-renovate-presets) for more
examples.

## Adding a new preset

1. Create `renovate/<stack>_config.json` in this directory.
2. Keep it minimal — only settings that should apply to every repo of that
   stack type. Repo-specific tuning belongs in the caller's `renovate.json`.
3. Add a row to the table above.
4. Update the root [`INSTALL.md`](../INSTALL.md#2-renovate-presets) with
   the new preset path.
5. Open a PR.

## Philosophy

Presets encode the group's default trust stance: minor and patch updates
are safe to automerge (backed by CI), majors are human-gated. If a repo
needs tighter or looser behaviour, override locally rather than forking
the preset.
