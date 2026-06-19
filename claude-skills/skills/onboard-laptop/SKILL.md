---
name: onboard-laptop
description: >-
  Generic, profile-driven onboarding for a new employee's laptop
  (macOS or Windows). Reads a YAML profile that lists what to install
  (CLI binaries, GUI apps, npm/pip packages) and walks the user through
  a guided checklist for OS-level setup, account creation, and security
  hardening (FileVault/BitLocker, MFA, password manager). Idempotent —
  rerun-safe; detects what's already installed. Ships example profiles
  (`developer`, `minimal`, `designer`, `sales`) that a team can clone
  and customize. Triggers include "onboard a new laptop", "new employee
  setup", "setup mac for new hire", "setup windows for new hire",
  "install dev environment for new employee", "onboarding ordinateur",
  "setup poste nouvel employé", "configure laptop for onboarding".
model: haiku
---

# onboard-laptop

Generic onboarding skill for a new employee's laptop. Works on **macOS**
(Homebrew-based) and **Windows** (winget-based). Driven by a YAML
**profile** that declares what to install — the skill does not bake in
any company-specific stack. Teams write their own profile and store it
wherever they want (their dotfiles repo, an IT-managed gist, this skill's
`references/profiles/` for the catalog defaults).

## The 30-second story

1. **Detect OS** → `scripts/detect-os.sh` returns `mac` | `windows` | `linux`.
2. **Pick or build a profile** → use one from `references/profiles/`, or
   run `scripts/interview.sh` to build one interactively.
3. **Apply the profile** → `scripts/apply-profile.sh <profile.yml>` reads
   the YAML and dispatches to the OS-specific installer.
4. **Walk the human checklists** → accounts (Google/GitHub/Slack/…),
   security hardening (disk encryption, MFA, password manager) — these
   stay manual because they require human decisions and credentials.
5. **Verify** → `scripts/doctor.sh <profile.yml>` re-reads the profile
   and confirms every declared item is now present.

## When to use this skill

Invoke when the user says any of:

- "onboard a new laptop", "setup mac for new hire", "configure windows
  for onboarding"
- "install the dev environment for [name]"
- "I just got a new MacBook, what do I install?"
- "setup poste nouvel employé", "onboarding ordinateur"
- "give me a Brewfile for our team"
- "doctor my laptop setup"

Do **not** invoke for: provisioning corporate identities (Active
Directory, Okta SCIM), bulk fleet management (MDM, JAMF), or
re-imaging — those need IT-admin tooling, not a local Claude session.

## Scope contract

What this skill **does**:

- Install CLI binaries (`git`, `node`, `python`, `gh`, …) declared in the profile
- Install GUI apps (VS Code, Slack, Chrome, …) via `brew --cask` / `winget`
- Install language-level packages (`npm install -g`, `pip install`)
- Print copy-paste account-creation checklists with sign-up URLs
- Print OS-level security checklists (FileVault/BitLocker, MFA, gestionnaire de mdp)
- Verify post-install state via `doctor.sh`

What this skill **does not** do** (these are out of scope, by design):

- Provision Google Workspace / GitHub org / Slack invites (use the
  org's IT-admin workflow — `google-workspace`, `github-compliance`,
  Slack admin console)
- Touch MDM-managed configuration (let JAMF / Intune do that)
- Manage SSH keys or signing keys (let the user do that interactively
  — automating it here would be a foot-gun)
- Decide what should be in your team's profile — that's a human call

## Quick start

### A. macOS — apply the bundled `developer` profile

```bash
# 1. Detect OS, ensure Homebrew is present (the script installs it if missing)
bash scripts/detect-os.sh

# 2. Apply the profile
bash scripts/apply-profile.sh references/profiles/developer.yml

# 3. Walk the human checklists
$EDITOR references/CHECKLIST-ACCOUNTS.md
$EDITOR references/CHECKLIST-SECURITY.md

# 4. Verify
bash scripts/doctor.sh references/profiles/developer.yml
```

### B. Windows — apply the bundled `developer` profile

Open **PowerShell as Administrator** (winget needs it for some packages):

```powershell
# 1. Detect OS, ensure winget is present
powershell -ExecutionPolicy Bypass -File scripts/detect-os.ps1

# 2. Apply the profile
powershell -ExecutionPolicy Bypass -File scripts/apply-profile.ps1 references/profiles/developer.yml

# 3. Walk the human checklists (open in Notepad or your editor)
notepad references/CHECKLIST-ACCOUNTS.md
notepad references/CHECKLIST-SECURITY.md

# 4. Verify
powershell -ExecutionPolicy Bypass -File scripts/doctor.ps1 references/profiles/developer.yml
```

### C. No profile? Build one interactively

```bash
bash scripts/interview.sh > /tmp/my-profile.yml
bash scripts/apply-profile.sh /tmp/my-profile.yml
```

The interview asks a handful of questions (role, languages, IDE, terminal
emulator, browsers, communication tools) and emits a fresh profile.

## The profile format

A profile is a YAML file with these top-level keys (all optional):

```yaml
name: developer
description: Standard developer onboarding for a backend-leaning role.

# CLI tools and runtimes
brew:                    # macOS — `brew install <pkg>`
  - git
  - gh
  - node
  - python@3.12
  - jq
winget:                  # Windows — `winget install <id>`
  - Git.Git
  - GitHub.cli
  - OpenJS.NodeJS.LTS
  - Python.Python.3.12
  - jqlang.jq

# GUI apps
brew_cask:               # macOS
  - visual-studio-code
  - iterm2
  - google-chrome
  - slack
winget_apps:             # Windows
  - Microsoft.VisualStudioCode
  - Microsoft.WindowsTerminal
  - Google.Chrome
  - SlackTechnologies.Slack

# Language-level packages (cross-OS)
npm_global:
  - "@anthropic-ai/claude-code"
  - typescript
pip_global:
  - black
  - ruff
  - virtualenv

# Mac App Store apps (macOS only — requires `mas` CLI)
mas:
  - { id: "497799835", name: "Xcode" }

# Post-install commands to run verbatim (idempotent only — last-resort hatch).
# $ONBOARD_SCRIPT_DIR and $ONBOARD_SKILL_DIR are exported by apply-profile.sh
# so a profile can call bundled helpers without hard-coding the install path.
post_install:
  - 'git config --global init.defaultBranch main'
  - 'git config --global pull.rebase true'
  - 'bash "$ONBOARD_SCRIPT_DIR/install-oh-my-zsh.sh"'

# Account checklist items — printed, never executed
accounts:
  - name: GitHub
    url: https://github.com/join
    notes: Ask your manager for the org invitation.
  - name: Slack
    url: https://yourcompany.slack.com
    notes: Use your work email.

# Security hardening checklist items — printed, never executed
security:
  - filevault          # macOS only
  - bitlocker          # Windows only
  - password_manager   # any (1Password / Bitwarden / Dashlane / …)
  - mfa_on_email
  - mfa_on_github
  - screen_lock_5min
```

The schema is documented in full at `references/PROFILE-SCHEMA.md`.
Unknown keys are ignored with a warning so older skill versions stay
forward-compatible.

## Bundled example profiles

Under `references/profiles/`:

| File | Audience | Roughly |
|------|----------|---------|
| `minimal.yml` | Anyone | Browser, password manager, communication app, OS security |
| `developer.yml` | Software engineers | + git, node, python, docker, IDE, terminal |
| `designer.yml` | Designers | + Figma, fonts, color tools |
| `sales.yml` | GTM / sales | + Notion, Loom, calendar tools |

These are **starting points** — copy one into your own dotfiles or IT
repo and edit. The schema is stable; the examples are opinionated.

## How `apply-profile.sh` decides what to do

1. Reads the YAML (uses `yq` if present, falls back to a vendored
   Python parser).
2. Detects OS via `detect-os.sh`.
3. Skips OS-specific keys when on the wrong OS (e.g. `brew:` is skipped
   on Windows, `winget:` is skipped on macOS) — printed as `skip:` lines
   so the operator sees what was deferred.
4. For each package: checks if it's already installed; installs only if
   missing. **Idempotent — safe to re-run.**
5. Account/security entries are printed as a checklist; nothing is
   executed.

## How `doctor.sh` works

Re-reads the same profile and confirms each declared item is present.
Exits `0` (everything found), `1` (warnings — e.g. a `post_install`
step's effect can't be verified), or `2` (a declared package is
missing).

```bash
$ bash scripts/doctor.sh references/profiles/developer.yml
=== Brew packages ===
✓ git              (2.43.0)
✓ node             (v20.10.0)
✗ python@3.12      MISSING — re-run apply-profile.sh
✓ jq               (1.7)
=== Brew casks ===
✓ visual-studio-code
✓ iterm2
=== npm global ===
✓ @anthropic-ai/claude-code
=== Account checklist ===
↻ 5 items — verify manually in references/CHECKLIST-ACCOUNTS.md
=== Security checklist ===
↻ 4 items — verify manually in references/CHECKLIST-SECURITY.md
Exit: 2 (1 missing package)
```

## Writing your own profile

The bundled profiles are deliberately small. Real teams will want a
profile that names their company-internal tools (the SSO portal, the
VPN client, the internal CLI). The recommended pattern:

1. Fork one of `references/profiles/*.yml` into your team's repo (e.g.
   `dotfiles/onboard/team-backend.yml`).
2. Customize the lists.
3. Onboard a new hire with:

   ```bash
   bash ~/.claude/skills/onboard-laptop/scripts/apply-profile.sh \
     /path/to/team-backend.yml
   ```

The skill never reads anything outside the path you pass it — there's
no implicit "BSG stack" or hidden default.

## Security considerations

- The skill runs as the current user. It does **not** request `sudo`
  except where the OS package manager intrinsically needs it (e.g.
  `brew install --cask` for some kernel-extension apps on macOS,
  most `winget` installers on Windows).
- The skill never reads or writes secrets. SSH keys, signing keys,
  cloud credentials, and password-manager vaults are out of scope —
  the human creates and stores them.
- `post_install:` commands are executed verbatim. Keep this list short
  and audit it before applying a third-party profile.

## Limits and known caveats

- **`brew --cask` on first run prompts for admin password** for some
  casks (e.g. Docker Desktop). The script does not auto-type the
  password — let the human supply it.
- **`winget` source acceptance**: on a fresh Windows install, the
  first `winget` call asks the user to accept the source agreement.
  The script pre-accepts via `--accept-source-agreements`.
- **App Store CLI (`mas`)** requires the Mac App Store to be signed in.
  The script checks for an existing session and prints instructions if
  not signed in.
- **Linux** is not supported in this version. The detection script
  reports `linux` and exits with a clear message. PRs welcome.

## Shell setup — Oh My Zsh and a starter `.zshrc`

The `developer` profile installs **Oh My Zsh** via a bundled
`scripts/install-oh-my-zsh.sh` wrapper called from `post_install:`.
The wrapper is intentionally conservative:

- **Idempotent.** Detects `~/.oh-my-zsh` and exits early when present.
- **Never overwrites your `.zshrc`.** Runs the official installer with
  `KEEP_ZSHRC=yes`, so an existing dotfile is left untouched.
- **Never calls `chsh`.** Runs with `CHSH=no`, so your login shell is
  not changed. Switch with `chsh -s "$(which zsh)"` when you're ready.
- **Optional starter `.zshrc`.** Pass `--with-starter-zshrc` to drop
  the bundled `references/dotfiles/zshrc-starter` at `~/.zshrc` —
  only when no `~/.zshrc` exists. The starter sources Homebrew, OMZ,
  `zsh-syntax-highlighting`, and `zsh-autosuggestions` (declared in
  the profile's `brew:` list) and exposes a `~/.zshrc.local` hook for
  machine-specific tweaks.

The `developer` profile pulls `zsh-syntax-highlighting` and
`zsh-autosuggestions` via `brew:`, then runs the wrapper. To opt
into the starter `.zshrc` too, change the `post_install:` line to:

```yaml
- 'bash "$ONBOARD_SCRIPT_DIR/install-oh-my-zsh.sh" --with-starter-zshrc'
```

`$ONBOARD_SCRIPT_DIR` (and `$ONBOARD_SKILL_DIR`) are exported by
`apply-profile.sh` so `post_install:` commands can reference bundled
helpers without hard-coding the install path.

## Default terminal — Ghostty

The `developer` profile ships **Ghostty** ([ghostty.org](https://ghostty.org/))
as the default GPU-accelerated terminal (Mac and Linux only — Windows
is not yet supported upstream; the profile keeps Windows Terminal /
Warp / Cursor as alternates). `iterm2` stays in the cask list as a
fallback for muscle-memory users. The `interview.sh` Q&A offers
`ghostty | iterm2 | warp | wt | none` and defaults to Ghostty.

## Mandatory 2-step verification on the Google account

Every profile that touches a Google Workspace email ships an explicit
checklist row for **2-step verification**:

```yaml
- { name: "Google Account — enable 2-step verification",
    url: "https://myaccount.google.com/signinoptions/two-step-verification",
    notes: "MANDATORY. Use an authenticator app (not SMS).
            Save backup codes in your password manager." }
```

The URL goes straight to the 2FA settings page — no clicking through
account settings to find it. The `security:` block also carries the
opaque `mfa_on_email` token; the step-by-step lives in
`references/CHECKLIST-SECURITY.md`.

## When something fails

- **`brew` not found on macOS** → `detect-os.sh` installs it. If the
  install fails (network, Xcode CLT missing), the script prints the
  Apple/Homebrew error verbatim — do not paper over it.
- **A package fails to install** → `apply-profile.sh` continues with
  the rest, logs the failure to `/tmp/onboard-laptop-failures.log`,
  and exits non-zero at the end. Re-run after fixing the cause.
- **`doctor.sh` says missing** → re-run `apply-profile.sh` with the
  same profile. Idempotency makes this safe.

---

## How to improve this skill

This file is a cached copy of `claude-skills/skills/onboard-laptop/SKILL.md` in
[beyond-scale-group/bsg-stack](https://github.com/beyond-scale-group/bsg-stack).
That repo is the single source of truth — `~/.claude/skills/onboard-laptop/SKILL.md` is
overwritten every time the BSG install flow runs.

If the user asks you to improve, fix, or extend this skill, do **not** edit
the local file. Instead:

1. `gh repo clone beyond-scale-group/bsg-stack` (or work in an existing clone)
2. Edit `claude-skills/skills/onboard-laptop/SKILL.md` on a feature branch
3. Open a pull request against `main`

Bug reports and ideas without a fix → open an issue on the same repo.
