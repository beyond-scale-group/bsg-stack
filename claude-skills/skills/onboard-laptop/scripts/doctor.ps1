# doctor.ps1 — Windows counterpart of doctor.sh.
# Re-reads a profile and verifies declared items are present.
# Exit codes: 0 = clean, 1 = warnings only, 2 = at least one missing.

[CmdletBinding()]
param(
  [Parameter(Position=0, Mandatory=$true)][string]$Profile
)

$ErrorActionPreference = 'Continue'

if (-not (Test-Path $Profile)) {
  Write-Error "Profile not found: $Profile"
  exit 2
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Parser    = Join-Path $ScriptDir '_parse-profile.py'

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command python3 -ErrorAction SilentlyContinue }
if (-not $python) {
  Write-Error 'Python 3 not found on PATH.'
  exit 2
}

$records = & $python.Path $Parser $Profile
if ($LASTEXITCODE -ne 0) {
  Write-Error 'Failed to parse profile.'
  exit 2
}

# Group records
$grouped = @{}
foreach ($line in $records) {
  if (-not $line) { continue }
  $parts = $line -split "`t"
  $section = $parts[0]
  if (-not $grouped.ContainsKey($section)) { $grouped[$section] = @() }
  $grouped[$section] += ,($parts[1..($parts.Length-1)])
}

$name = ($grouped['meta'] | Where-Object { $_[0] -eq 'name' } | ForEach-Object { $_[1] } | Select-Object -First 1)
Write-Host "=== Doctor: $($name -or '<unnamed profile>') ==="

$missing = 0
$warn = 0

function Test-WingetInstalled($id) {
  $null = winget list --id $id --exact 2>$null
  return ($LASTEXITCODE -eq 0)
}

# winget formulae
if ($grouped.ContainsKey('winget')) {
  Write-Host '--- winget CLI tools ---'
  foreach ($entry in $grouped['winget']) {
    $id = $entry[0]
    if (Test-WingetInstalled $id) { Write-Host "  ✓ $id" }
    else { Write-Host "  ✗ $id MISSING"; $missing++ }
  }
}

# winget apps
if ($grouped.ContainsKey('winget_apps')) {
  Write-Host '--- winget GUI apps ---'
  foreach ($entry in $grouped['winget_apps']) {
    $id = $entry[0]
    if (Test-WingetInstalled $id) { Write-Host "  ✓ $id" }
    else { Write-Host "  ✗ $id MISSING"; $missing++ }
  }
}

# npm global
if ($grouped.ContainsKey('npm_global')) {
  Write-Host '--- npm global ---'
  if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Host '  ⚠️  npm not on PATH'
    $warn++
  } else {
    foreach ($entry in $grouped['npm_global']) {
      $pkg = $entry[0]
      $null = npm ls -g --depth=0 $pkg 2>$null
      if ($LASTEXITCODE -eq 0) { Write-Host "  ✓ $pkg" }
      else { Write-Host "  ✗ $pkg MISSING"; $missing++ }
    }
  }
}

# pip
if ($grouped.ContainsKey('pip_global')) {
  Write-Host '--- pip global ---'
  if (-not (Get-Command pip -ErrorAction SilentlyContinue)) {
    Write-Host '  ⚠️  pip not on PATH'
    $warn++
  } else {
    foreach ($entry in $grouped['pip_global']) {
      $pkg = $entry[0]
      $null = pip show $pkg 2>$null
      if ($LASTEXITCODE -eq 0) { Write-Host "  ✓ $pkg" }
      else { Write-Host "  ✗ $pkg MISSING"; $missing++ }
    }
  }
}

# post_install
if ($grouped.ContainsKey('post_install')) {
  $count = $grouped['post_install'].Count
  Write-Host "--- post_install ---"
  Write-Host "  ↻ $count command(s) — not verifiable, trust the apply-profile run"
  $warn++
}

# accounts / security
if ($grouped.ContainsKey('accounts')) {
  $count = $grouped['accounts'].Count
  Write-Host '=== Account checklist ==='
  Write-Host "  ↻ $count item(s) — verify manually in references/CHECKLIST-ACCOUNTS.md"
  $warn++
}
if ($grouped.ContainsKey('security')) {
  $count = $grouped['security'].Count
  Write-Host '=== Security checklist ==='
  Write-Host "  ↻ $count item(s) — verify manually in references/CHECKLIST-SECURITY.md"
  $warn++
}

Write-Host ''
if ($missing -gt 0) {
  Write-Host "Exit: 2 ($missing missing package(s)) — re-run apply-profile.ps1"
  exit 2
}
if ($warn -gt 0) {
  Write-Host "Exit: 1 ($warn manual-check warning(s))"
  exit 1
}
Write-Host 'Exit: 0 (all clear)'
exit 0
