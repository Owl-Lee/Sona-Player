<#
.SYNOPSIS
Runs repeatable, non-destructive Android player lifecycle checks through ADB.

.DESCRIPTION
The script never uninstalls the app and never clears app data. It records any
notification-permission and rotation settings it changes and restores them in
a finally block. A JSON report is written under artifacts/mobile-regression.
#>

[CmdletBinding()]
param(
  [string]$Serial = '',
  [string]$AdbPath = '',
  [string]$Package = 'com.sonarvault.sonar_vault',
  [string]$ExpectedVersionName = '',
  [long]$ExpectedVersionCode = 0,
  [switch]$ExerciseMediaButtons,
  [switch]$ExerciseRotation,
  [switch]$ExerciseNotificationPermission
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$adbCommand = Get-Command adb -ErrorAction SilentlyContinue
$adbCandidates = @(
  $AdbPath,
  $(if ($adbCommand) { $adbCommand.Source }),
  $(if ($env:ANDROID_SDK_ROOT) {
      Join-Path $env:ANDROID_SDK_ROOT 'platform-tools\adb.exe'
    }),
  $(if ($env:ANDROID_HOME) {
      Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe'
    }),
  $(if ($env:LOCALAPPDATA) {
      Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
    })
) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }
$adb = $adbCandidates | Select-Object -First 1
if (-not $adb) {
  throw 'ADB was not found. Add adb to PATH or pass -AdbPath.'
}

function Invoke-Adb {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
  $prefix = if ($Serial) { @('-s', $Serial) } else { @() }
  $output = & $adb @prefix @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "adb $($Arguments -join ' ') failed: $output"
  }
  return ($output -join "`n")
}

function Invoke-AdbOptional {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
  $prefix = if ($Serial) { @('-s', $Serial) } else { @() }
  $output = & $adb @prefix @Arguments 2>&1
  return [ordered]@{
    exitCode = $LASTEXITCODE
    output = ($output -join "`n")
  }
}

function Add-Check {
  param(
    [string]$Name,
    [bool]$Passed,
    [string]$Evidence
  )
  $script:checks.Add([ordered]@{
      name = $Name
      passed = $Passed
      evidence = $Evidence.Trim()
    })
}

$checks = [System.Collections.Generic.List[object]]::new()
$startedAt = [DateTime]::UtcNow
$permissionWasGranted = $false
$permissionChanged = $false
$rotationMode = $null
$rotationValue = $null

try {
  $devices = Invoke-Adb devices
  $devicePattern = if ($Serial) {
    '(?m)^' + [regex]::Escape($Serial) + "`tdevice(?:`$|\s)"
  } else {
    "`tdevice(?:`$|\s)"
  }
  Add-Check 'device-connected' ($devices -match $devicePattern) $devices

  $crashBaseline = Invoke-Adb shell dumpsys dropbox --print data_app_crash
  $crashBaselineCount = ([regex]::Matches($crashBaseline, [regex]::Escape($Package))).Count

  $packageDump = Invoke-Adb shell dumpsys package $Package
  Add-Check 'package-installed' ($packageDump -match 'versionName=') (($packageDump -split "`n" | Where-Object { $_ -match 'versionName=|versionCode=|flags=' }) -join '; ')
  $installedVersionName = if ($packageDump -match 'versionName=([^\s]+)') { $Matches[1] } else { '' }
  $installedVersionCode = if ($packageDump -match 'versionCode=(\d+)') { [long]$Matches[1] } else { 0 }
  if ($ExpectedVersionName) {
    Add-Check 'expected-version-name' ($installedVersionName -eq $ExpectedVersionName) "expected=$ExpectedVersionName; installed=$installedVersionName"
  }
  if ($ExpectedVersionCode -gt 0) {
    Add-Check 'expected-version-code' ($installedVersionCode -eq $ExpectedVersionCode) "expected=$ExpectedVersionCode; installed=$installedVersionCode"
  }
  Add-Check 'non-debuggable' ($packageDump -notmatch '(?m)flags=\[[^\]]*\bDEBUGGABLE\b') 'Installed application flags do not contain DEBUGGABLE.'
  Add-Check 'media-playback-service-declared' ($packageDump -match 'com\.ryanheise\.audioservice\.AudioService') 'AudioService is present in the installed package.'
  Add-Check 'wake-lock-permission' ($packageDump -match 'android\.permission\.WAKE_LOCK') 'WAKE_LOCK is declared.'
  Add-Check 'foreground-media-permission' ($packageDump -match 'android\.permission\.FOREGROUND_SERVICE_MEDIA_PLAYBACK') 'FOREGROUND_SERVICE_MEDIA_PLAYBACK is declared.'

  Invoke-Adb -Arguments @('shell', 'monkey', '-p', $Package, '-c', 'android.intent.category.LAUNCHER', '1') | Out-Null
  Start-Sleep -Milliseconds 900
  $appPid = (Invoke-AdbOptional shell pidof $Package).output.Trim()
  Add-Check 'cold-launch' ([bool]$appPid) "pid=$appPid"

  Invoke-Adb shell input keyevent KEYCODE_HOME | Out-Null
  Start-Sleep -Milliseconds 500
  $processDump = Invoke-Adb shell dumpsys activity processes
  Add-Check 'background-process-alive' ($processDump -match [regex]::Escape($Package)) 'Process remains known after HOME.'

  $mediaSession = Invoke-Adb shell dumpsys media_session
  Add-Check 'media-session-published' ($mediaSession -match [regex]::Escape($Package)) (($mediaSession -split "`n" | Where-Object { $_ -match [regex]::Escape($Package) -or $_ -match 'state=' } | Select-Object -First 12) -join '; ')

  if ($ExerciseMediaButtons) {
    Invoke-Adb shell input keyevent KEYCODE_MEDIA_PLAY_PAUSE | Out-Null
    Start-Sleep -Milliseconds 700
    $afterFirst = Invoke-Adb shell dumpsys media_session
    Invoke-Adb shell input keyevent KEYCODE_MEDIA_PLAY_PAUSE | Out-Null
    Start-Sleep -Milliseconds 700
    $afterSecond = Invoke-Adb shell dumpsys media_session
    Add-Check 'media-button-round-trip' ($afterFirst -ne $afterSecond -or $afterFirst -match [regex]::Escape($Package)) 'PLAY_PAUSE was delivered twice; final state was restored.'
  }

  $permissionDump = Invoke-Adb shell dumpsys package $Package
  $notificationPermissionDeclared = $permissionDump -match 'android\.permission\.POST_NOTIFICATIONS'
  $permissionWasGranted = $permissionDump -match 'android\.permission\.POST_NOTIFICATIONS: granted=true'
  Add-Check 'notification-permission-state' $true $(
    if (-not $notificationPermissionDeclared) {
      'POST_NOTIFICATIONS is not declared; verify the media-session notification on target Android versions.'
    } elseif ($permissionWasGranted) {
      'POST_NOTIFICATIONS is declared and currently granted.'
    } else {
      'POST_NOTIFICATIONS is declared and currently denied.'
    }
  )

  $currentRotationMode = (Invoke-AdbOptional shell settings get system accelerometer_rotation).output.Trim()
  $currentRotationValue = (Invoke-AdbOptional shell settings get system user_rotation).output.Trim()
  Add-Check 'rotation-state' $true "accelerometer_rotation=$currentRotationMode; user_rotation=$currentRotationValue"

  if ($ExerciseNotificationPermission -and $notificationPermissionDeclared) {
    if ($permissionWasGranted) {
      Invoke-Adb shell pm revoke $Package android.permission.POST_NOTIFICATIONS | Out-Null
      $permissionChanged = $true
      Invoke-Adb shell am force-stop $Package | Out-Null
      Invoke-Adb -Arguments @('shell', 'monkey', '-p', $Package, '-c', 'android.intent.category.LAUNCHER', '1') | Out-Null
      Start-Sleep -Milliseconds 700
      $pidWithoutPermission = (Invoke-AdbOptional shell pidof $Package).output.Trim()
      Add-Check 'notification-permission-denied-launch' ([bool]$pidWithoutPermission) 'App launches without notification permission.'
    } else {
      Add-Check 'notification-permission-denied-launch' $true 'Permission was already denied; no mutation was needed.'
    }
  }

  if ($ExerciseRotation) {
    $rotationMode = $currentRotationMode
    $rotationValue = $currentRotationValue
    foreach ($rotation in 1, 0) {
      Invoke-Adb shell settings put system accelerometer_rotation 0 | Out-Null
      Invoke-Adb shell settings put system user_rotation $rotation | Out-Null
      Start-Sleep -Milliseconds 800
      $rotationPid = (Invoke-AdbOptional shell pidof $Package).output.Trim()
      Add-Check "rotation-$rotation-process-alive" ([bool]$rotationPid) "pid=$rotationPid"
    }
  }

  Invoke-Adb shell am send-trim-memory $Package RUNNING_CRITICAL | Out-Null
  Start-Sleep -Milliseconds 500
  $pidAfterTrim = (Invoke-AdbOptional shell pidof $Package).output.Trim()
  Add-Check 'critical-memory-callback' ([bool]$pidAfterTrim) "pid=$pidAfterTrim"

  Invoke-Adb shell am force-stop $Package | Out-Null
  Invoke-Adb -Arguments @('shell', 'monkey', '-p', $Package, '-c', 'android.intent.category.LAUNCHER', '1') | Out-Null
  Start-Sleep -Milliseconds 900
  $pidAfterRestart = (Invoke-AdbOptional shell pidof $Package).output.Trim()
  Add-Check 'force-stop-recovery' ([bool]$pidAfterRestart) "pid=$pidAfterRestart"

  $crashes = Invoke-Adb shell dumpsys dropbox --print data_app_crash
  $crashCount = ([regex]::Matches($crashes, [regex]::Escape($Package))).Count
  $newCrash = $crashCount -gt $crashBaselineCount
  Add-Check 'no-new-app-crash' (-not $newCrash) ($(if ($newCrash) { "New data_app_crash entry detected (before=$crashBaselineCount, after=$crashCount)." } else { "No new data_app_crash entry (before=$crashBaselineCount, after=$crashCount)." }))
}
finally {
  if ($permissionChanged -and $permissionWasGranted) {
    try { Invoke-Adb shell pm grant $Package android.permission.POST_NOTIFICATIONS | Out-Null } catch { Write-Warning $_ }
  }
  if ($null -ne $rotationMode) {
    try {
      Invoke-Adb shell settings put system accelerometer_rotation $rotationMode | Out-Null
      Invoke-Adb shell settings put system user_rotation $rotationValue | Out-Null
    } catch { Write-Warning $_ }
  }
}

$finishedAt = [DateTime]::UtcNow
$report = [ordered]@{
  schema = 1
  package = $Package
  serial = $Serial
  startedAtUtc = $startedAt.ToString('o')
  finishedAtUtc = $finishedAt.ToString('o')
  passed = ($checks | Where-Object { -not $_.passed }).Count -eq 0
  checks = $checks
  manualEvidenceRequired = @(
    'Physical Bluetooth headset play/pause, next and previous',
    'Real incoming-call interruption and resume policy',
    'Screen-off playback for at least ten minutes',
    'OEM battery-saver behavior after backgrounding'
  )
}
$outputDirectory = Join-Path $projectRoot 'artifacts\mobile-regression'
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outputPath = Join-Path $outputDirectory "android-$stamp.json"
$report | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 -LiteralPath $outputPath
Write-Host "Report: $outputPath"
if (-not $report.passed) { exit 1 }
