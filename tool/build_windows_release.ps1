<#!
.SYNOPSIS
Builds the Windows Release and refreshes the desktop shortcut.
#>

[CmdletBinding()]
param()

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$flutter = (Get-Command flutter -ErrorAction SilentlyContinue).Source
$python = (Get-Command python -ErrorAction SilentlyContinue).Source

if (-not $flutter -or -not (Test-Path -LiteralPath $flutter -PathType Leaf)) {
  throw 'Flutter was not found on PATH.'
}
if (-not $python -or -not (Test-Path -LiteralPath $python -PathType Leaf)) {
  throw 'Python was not found on PATH.'
}

& $python (Join-Path $PSScriptRoot 'prepare_windows_icon.py')
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

& $flutter build windows --release
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

& (Join-Path $PSScriptRoot 'update_windows_desktop_shortcut.ps1')
