# Security checklist (manual)

This file is the human-facing companion of the `security:` block in a
profile. The skill prints the tokens; this file explains what to do
for each one.

## macOS

### `disk_encryption` → FileVault

- System Settings → Privacy & Security → FileVault → Turn on
- Save the recovery key in your password manager (**not** iCloud)
- Verify: `fdesetup status` reports `FileVault is On.`

### `screen_lock_5min`

- System Settings → Lock Screen → Require password after sleep / screen saver: **Immediately**
- System Settings → Lock Screen → Start Screen Saver after: **5 minutes**

### `automatic_updates`

- System Settings → General → Software Update → Automatic updates: **on**
- Allow security responses + system data files
- Verify: `softwareupdate --schedule` says `Automatic checking for updates is turned on.`

### `firewall`

- System Settings → Network → Firewall → On
- Block all incoming connections **except** for explicit services

## Windows

### `disk_encryption` → BitLocker

- Settings → Privacy & security → Device encryption → On
  (Pro/Enterprise: Manage BitLocker → Turn on)
- Save the recovery key in your password manager (**not** your Microsoft account alone)
- Verify (PowerShell, admin): `manage-bde -status C:` reports
  `Conversion Status: Fully Encrypted`

### `screen_lock_5min`

- Settings → Personalization → Lock screen → Screen timeout settings: **5 minutes**
- Settings → Accounts → Sign-in options → Require sign-in: **When PC wakes up from sleep**

### `automatic_updates`

- Settings → Windows Update → Advanced options → keep automatic updates
- Verify: `Get-Service wuauserv` reports `Running`

### `firewall`

- Windows Defender Firewall → On for all three profiles (Domain / Private / Public)

## Cross-platform

### `password_manager`

- Install the chosen manager (1Password / Bitwarden / Dashlane)
- Sign in
- Enable the browser extension
- Lock timeout ≤ 5 min when idle
- Master password stored in **two** physical safe places (paper + hardware token)

### `mfa_on_email`

- Workspace admin → 2-step verification → **Required**
- Authenticator app (Authy / 1Password / Aegis), **not** SMS
- Backup codes printed and stored in a safe

### `mfa_on_github`

- GitHub → Settings → Password & authentication → Two-factor → Enable
- Use authenticator app
- Save recovery codes in password manager

### `mfa_on_<service>`

- Repeat the same pattern for every SaaS that supports it (CRM,
  cloud consoles, Notion, Figma, Slack admin, …)

### `ssh_key_with_passphrase`

- Generate: `ssh-keygen -t ed25519 -C "you@company.com"`
- **Always set a passphrase** — empty passphrase = unencrypted key
- Add to ssh-agent: `ssh-add --apple-use-keychain ~/.ssh/id_ed25519`
  (mac) / `ssh-add ~/.ssh/id_ed25519` (win)
- Upload **public** key to GitHub / GitLab — never the private key

### `signed_commits`

- gpg or SSH commit signing
- gpg: `gpg --quick-generate-key "Your Name <you@company.com>" ed25519 sign 0`
  then `git config --global commit.gpgsign true`
- SSH: `git config --global gpg.format ssh` +
  `git config --global user.signingkey <path-to-pub>` +
  `git config --global commit.gpgsign true`
- GitHub: add the signing key under SSH and GPG keys → "Signing key"

### `browser_security`

- Block third-party cookies on the work browser profile
- Disable saved passwords (use the password manager)
- HTTPS-only mode on
- Limit extension count; review permissions yearly

### `backup`

- macOS: Time Machine on an encrypted external disk
- Windows: File History or a managed backup tool
- Cloud sync (Drive / OneDrive / Dropbox) is **not** a backup —
  it propagates deletions

## Compliance flags (org-specific — verify with IT)

- [ ] MDM enrollment confirmed
- [ ] EDR / antivirus agent installed and reporting
- [ ] Local admin account distinct from daily-driver account
- [ ] Personal data segregated from work data (separate user profile or device)

---

Once an item is true on this machine, tick it. Re-run `doctor.sh` /
`doctor.ps1` to confirm the apply-profile side stayed in shape; the
items in this file remain a human responsibility.
