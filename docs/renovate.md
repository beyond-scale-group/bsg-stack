# Renovate Presets

Shared Renovate configuration presets for repos in the BSG portfolio.

- **Component README:** [`renovate/README.md`](../renovate/README.md) — what each
  preset does, philosophy, how to add a new one.
- **Install snippet:** [`INSTALL.md` §2](../INSTALL.md#2-renovate-presets) —
  one-liner for your repo's `renovate.json`.

## Quick reference

| Preset | Use for |
|--------|---------|
| `github>beyond-scale-group/bsg-stack//renovate/scala` | sbt / Scala projects |
| `github>beyond-scale-group/bsg-stack//renovate/react` | npm / React projects |

Both presets automerge patch and minor updates, hold majors for human
review, and limit PR concurrency to avoid flooding CI.

> **Deprecation:** the old paths `renovate/scala_config` and
> `renovate/react_config` still work (they re-extend the new names) but
> will be removed in **`v2`**. Update your `renovate.json` at your
> convenience.
