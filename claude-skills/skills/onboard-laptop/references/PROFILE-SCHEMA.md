# Profile schema

A profile is a YAML document with the keys below. All keys are
optional — emit only what the role actually needs.

## Top-level keys

| Key | Type | Used by | Notes |
|---|---|---|---|
| `name` | string | metadata | Short slug shown in headers (e.g. `developer`). |
| `description` | string | metadata | One-line human description. |
| `brew` | list of strings | macOS | Homebrew formula names (`git`, `node`, `python@3.12`). |
| `brew_cask` | list of strings | macOS | Homebrew cask names (`visual-studio-code`, `iterm2`). |
| `winget` | list of strings | Windows | Winget package IDs (`Git.Git`, `OpenJS.NodeJS.LTS`). |
| `winget_apps` | list of strings | Windows | Same as `winget`, separated for clarity in profiles. |
| `apt` | list of strings | Linux | APT package names (`build-essential`, `git`, `curl`). |
| `snap` | list of strings | Linux | Snap package names (`code`, `slack`, `1password`). |
| `flatpak` | list of strings | Linux | Flatpak app IDs (`com.google.Chrome`, `us.zoom.Zoom`). |
| `npm_global` | list of strings | both | `npm install -g <pkg>` — used as-is. |
| `pip_global` | list of strings | both | `pip install --user <pkg>`, fallback to `pip install`. |
| `mas` | list of `{id, name}` | macOS | Mac App Store apps — requires `mas` CLI + signed-in session. |
| `post_install` | list of strings | both | Shell commands run verbatim. **Must be idempotent.** |
| `accounts` | list of `{name, url, notes}` | both | Printed as a checklist — never executed. |
| `security` | list of strings | both | Free-form security tokens — also printed only. |

## Example

```yaml
name: developer
description: Backend-leaning developer onboarding.

brew:
  - git
  - node
  - python@3.12

brew_cask:
  - visual-studio-code
  - iterm2

winget:
  - Git.Git
  - OpenJS.NodeJS.LTS
  - Python.Python.3.12

winget_apps:
  - Microsoft.VisualStudioCode
  - Microsoft.WindowsTerminal

npm_global:
  - "@anthropic-ai/claude-code"

pip_global:
  - black

mas:
  - { id: "497799835", name: "Xcode" }

post_install:
  - 'git config --global init.defaultBranch main'

accounts:
  - { name: "GitHub", url: "https://github.com/join", notes: "Ask manager for invite." }

security:
  - disk_encryption
  - mfa_on_email
  - screen_lock_5min
```

## What the parser tolerates

- Comments (`# …`) anywhere.
- Inline-dict form for `mas` and `accounts`: `{ key: value, key2: "value2" }`.
- Double-quoted or single-quoted scalars.
- Unknown top-level keys → ignored with a `warn:` line in the parser
  output (forward-compat for future schema additions).

## What the parser does **not** support

- Nested mappings beyond the single inline-dict layer.
- YAML anchors / aliases.
- Multi-document streams.
- Numeric or boolean types (everything is a string).

If you need richer YAML, install `yq` and adapt the drivers — the
vendored parser is intentionally minimal so the skill has zero
third-party deps.

## Security tokens

`security:` entries are **opaque tokens** — the skill prints them and
points to `CHECKLIST-SECURITY.md` for human instructions. Use the
tokens consistently across profiles so the checklist stays meaningful.
Common tokens:

- `disk_encryption` — FileVault (mac) / BitLocker (win)
- `password_manager` — vault installed + logged in
- `mfa_on_email`, `mfa_on_github`, `mfa_on_<service>` — 2FA enabled
- `ssh_key_with_passphrase` — SSH key generated and passphrase-protected
- `signed_commits` — gpg or SSH signing configured
- `screen_lock_5min` — automatic lock after 5 min idle
- `automatic_updates` — OS auto-updates on
