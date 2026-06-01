# detect-os.ps1 — Windows counterpart to detect-os.sh.
# Prints "windows" and exits 0 when running on Windows with winget available.
# Exits 1 otherwise.
#
# Side effect (Windows only): if -EnsureWinget is passed and winget is
# missing, instructs the user to install App Installer from the Store
# (we do not silently push it via PowerShellGet to avoid surprises).

[CmdletBinding()]
param(
  [switch]$EnsureWinget
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.Platform -and $PSVersionTable.Platform -ne 'Win32NT') {
  Write-Error "Not running on Windows (Platform=$($PSVersionTable.Platform))."
  exit 1
}

Write-Output 'windows'

if ($EnsureWinget) {
  $winget = Get-Command winget -ErrorAction SilentlyContinue
  if (-not $winget) {
    Write-Warning @'
winget not found on PATH.

Install it by opening the Microsoft Store and updating "App Installer"
(it ships winget). Or download from:
  https://aka.ms/getwinget

Re-run this script after installation.
'@
    exit 2
  }
  $version = (winget --version 2>$null)
  Write-Host "winget OK ($version)"
}
