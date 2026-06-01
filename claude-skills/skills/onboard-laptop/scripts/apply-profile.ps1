# apply-profile.ps1 — Windows counterpart of apply-profile.sh.
#
# Reads a YAML profile and installs everything declared in it on Windows
# via winget + npm + pip. Idempotent: skips items already present.
#
# Usage (run in PowerShell, preferably as Administrator):
#   .\apply-profile.ps1 <profile.yml>
#   .\apply-profile.ps1 -DryRun <profile.yml>
#   .\apply-profile.ps1 -Only winget <profile.yml>

[CmdletBinding()]
param(
  [Parameter(Position=0, Mandatory=$true)][string]$Profile,
  [switch]$DryRun,
  [string]$Only = ''
)

$ErrorActionPreference = 'Continue'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Parser    = Join-Path $ScriptDir '_parse-profile.py'
$FailLog   = Join-Path $env:TEMP 'onboard-laptop-failures.log'
Set-Content -Path $FailLog -Value '' -Encoding UTF8

if (-not (Test-Path $Profile)) {
  Write-Error "Profile not found: $Profile"
  exit 2
}

# OS check
& (Join-Path $ScriptDir 'detect-os.ps1') -EnsureWinget | Out-Null
if ($LASTEXITCODE -ne 0) {
  Write-Error 'detect-os.ps1 failed — see message above.'
  exit 2
}

# Parse YAML via the vendored Python parser (Python 3 must be on PATH).
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
  $python = Get-Command python3 -ErrorAction SilentlyContinue
}
if (-not $python) {
  Write-Error 'Python 3 not found on PATH — install it first (winget install Python.Python.3.12) and re-run.'
  exit 2
}

$records = & $python.Path $Parser $Profile
if ($LASTEXITCODE -ne 0) {
  Write-Error 'Failed to parse profile.'
  exit 2
}

function Test-Section($section) {
  if (-not $Only) { return $true }
  return ($Only -eq $section)
}

function Invoke-Step($cmd) {
  if ($DryRun) {
    Write-Host "  [dry-run] $cmd"
    return $true
  }
  Write-Host "  -> $cmd"
  try {
    Invoke-Expression $cmd
    if ($LASTEXITCODE -ne 0) {
      Add-Content -Path $FailLog -Value "FAIL: $cmd"
      Write-Host "  ✗ failed (exit $LASTEXITCODE): $cmd"
      return $false
    }
  } catch {
    Add-Content -Path $FailLog -Value "FAIL: $cmd  ($_ )"
    Write-Host "  ✗ failed: $_"
    return $false
  }
  return $true
}

function Test-WingetInstalled($id) {
  # `winget list --id <id>` exits 0 when present, 1 when not.
  $null = winget list --id $id --exact 2>$null
  return ($LASTEXITCODE -eq 0)
}

function Test-NpmGlobalInstalled($pkg) {
  $null = npm ls -g --depth=0 $pkg 2>$null
  return ($LASTEXITCODE -eq 0)
}

function Test-PipInstalled($pkg) {
  $null = pip show $pkg 2>$null
  return ($LASTEXITCODE -eq 0)
}

# Parse records into arrays grouped by section.
$grouped = @{}
foreach ($line in $records) {
  if (-not $line) { continue }
  $parts = $line -split "`t"
  $section = $parts[0]
  if (-not $grouped.ContainsKey($section)) { $grouped[$section] = @() }
  $grouped[$section] += ,($parts[1..($parts.Length-1)])
}

# Header
$name = ($grouped['meta'] | Where-Object { $_[0] -eq 'name' } | ForEach-Object { $_[1] } | Select-Object -First 1)
$desc = ($grouped['meta'] | Where-Object { $_[0] -eq 'description' } | ForEach-Object { $_[1] } | Select-Object -First 1)
Write-Host ""
Write-Host "=== Applying profile: $($name -or '<unnamed>') ==="
if ($desc) { Write-Host "    $desc" }
Write-Host ""

# Warnings
foreach ($w in ($grouped['warn'] | ForEach-Object { $_[0] })) {
  Write-Host "⚠️  $w"
}

# winget formulae (declared as `winget:` in the YAML — confusingly named for parity with brew)
if (Test-Section 'winget') {
  Write-Host '--- winget CLI tools ---'
  foreach ($entry in $grouped['winget']) {
    $id = $entry[0]
    if (Test-WingetInstalled $id) {
      Write-Host "  ✓ $id (already installed)"
    } else {
      Invoke-Step "winget install --id $id --exact --silent --accept-source-agreements --accept-package-agreements" | Out-Null
    }
  }
}

# winget GUI apps
if (Test-Section 'winget_apps') {
  Write-Host '--- winget GUI apps ---'
  foreach ($entry in $grouped['winget_apps']) {
    $id = $entry[0]
    if (Test-WingetInstalled $id) {
      Write-Host "  ✓ $id (already installed)"
    } else {
      Invoke-Step "winget install --id $id --exact --silent --accept-source-agreements --accept-package-agreements" | Out-Null
    }
  }
}

# npm global
if (Test-Section 'npm_global') {
  Write-Host '--- npm global packages ---'
  if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Host '  ⚠️  npm not on PATH — install Node.js via winget first (OpenJS.NodeJS.LTS).'
    Add-Content -Path $FailLog -Value 'npm missing'
  } else {
    foreach ($entry in $grouped['npm_global']) {
      $pkg = $entry[0]
      if (Test-NpmGlobalInstalled $pkg) {
        Write-Host "  ✓ $pkg (already installed)"
      } else {
        Invoke-Step "npm install -g $pkg" | Out-Null
      }
    }
  }
}

# pip global
if (Test-Section 'pip_global') {
  Write-Host '--- pip packages ---'
  if (-not (Get-Command pip -ErrorAction SilentlyContinue)) {
    Write-Host '  ⚠️  pip not on PATH — install Python via winget first (Python.Python.3.12).'
    Add-Content -Path $FailLog -Value 'pip missing'
  } else {
    foreach ($entry in $grouped['pip_global']) {
      $pkg = $entry[0]
      if (Test-PipInstalled $pkg) {
        Write-Host "  ✓ $pkg (already installed)"
      } else {
        Invoke-Step "pip install --user $pkg" | Out-Null
      }
    }
  }
}

# mas → not applicable on Windows
if ($grouped.ContainsKey('mas') -and $grouped['mas'].Count -gt 0) {
  Write-Host '⚠️  mas entries skipped — Mac App Store is macOS-only.'
}

# post_install
if (Test-Section 'post_install' -and $grouped.ContainsKey('post_install')) {
  Write-Host '--- post_install commands ---'
  foreach ($entry in $grouped['post_install']) {
    Invoke-Step $entry[0] | Out-Null
  }
}

# accounts (printed only)
if (Test-Section 'accounts' -and $grouped.ContainsKey('accounts')) {
  Write-Host ''
  Write-Host '--- Account checklist (manual — printed for you) ---'
  foreach ($entry in $grouped['accounts']) {
    $n = $entry[0]; $u = $entry[1]; $note = $entry[2]
    Write-Host "  [ ] $n — $u"
    if ($note) { Write-Host "      note: $note" }
  }
  Write-Host '  → also see references/CHECKLIST-ACCOUNTS.md'
}

# security (printed only)
if (Test-Section 'security' -and $grouped.ContainsKey('security')) {
  Write-Host ''
  Write-Host '--- Security checklist (manual — printed for you) ---'
  foreach ($entry in $grouped['security']) {
    Write-Host "  [ ] $($entry[0])"
  }
  Write-Host '  → step-by-step instructions in references/CHECKLIST-SECURITY.md'
}

Write-Host ''
if ((Get-Item $FailLog).Length -gt 0) {
  Write-Host "⚠️  Some steps failed. See $FailLog"
  Write-Host '    Re-run after fixing — apply-profile.ps1 is idempotent.'
  exit 1
}
Write-Host '✓ Profile applied. Run doctor.ps1 to verify.'
