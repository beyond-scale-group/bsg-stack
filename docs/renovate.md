# Renovate Presets

Shared Renovate configuration presets for repos in the BSG portfolio.

- **Component README:** [`renovate/README.md`](../renovate/README.md) — what each
  preset does, philosophy, how to add a new one.
- **Install snippet:** [`INSTALL.md` §2](../INSTALL.md#2-renovate-presets) —
  one-liner for your repo's `renovate.json`.

## Quick reference

| Preset | Use for |
|--------|---------|
| `github>beyond-scale-group/bsg-stack//renovate/scala_config` | sbt / Scala projects |
| `github>beyond-scale-group/bsg-stack//renovate/react_config` | npm / React projects |

Both presets automerge patch and minor updates, hold majors for human
review, and limit PR concurrency to avoid flooding CI.
