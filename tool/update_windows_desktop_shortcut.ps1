<#!
.SYNOPSIS
Updates the Sona desktop shortcut to the current Windows Release build.

.DESCRIPTION
Run this after a successful `flutter build windows --release`. The shortcut
always launches the executable from the current build output, so it never
continues to point at an old unpacked or temporary release folder.
#>

[CmdletBinding()]
param()

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$releaseDirectory = Join-Path $projectRoot 'build\windows\x64\runner\Release'
$executablePath = Join-Path $releaseDirectory 'sonar_vault.exe'
$iconPath = Join-Path $projectRoot 'windows\runner\resources\sona_cutout.ico'

if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
  throw "Windows Release executable was not found: $executablePath`nRun flutter build windows --release first."
}
if (-not (Test-Path -LiteralPath $iconPath -PathType Leaf)) {
  throw "Transparent Windows icon was not found: $iconPath"
}

$desktopPath = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktopPath 'Sona.lnk'
$existingShortcut = Get-ChildItem -LiteralPath $desktopPath -Filter '*.lnk' |
  Where-Object { $_.Name -like '*SonarVault*' } |
  Select-Object -First 1
if (-not (Test-Path -LiteralPath $shortcutPath) -and $null -ne $existingShortcut) {
  Move-Item -LiteralPath $existingShortcut.FullName -Destination $shortcutPath
}
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $executablePath
$shortcut.WorkingDirectory = $releaseDirectory
$shortcut.IconLocation = "$iconPath,0"
$shortcut.Description = 'Sona music player - current Windows Release'
$shortcut.Save()

$iconRefresh = Join-Path $env:SystemRoot 'System32\ie4uinit.exe'
if (Test-Path -LiteralPath $iconRefresh -PathType Leaf) {
  & $iconRefresh -show
}

Write-Output "Desktop shortcut updated: $shortcutPath"
Write-Output "Target: $executablePath"
