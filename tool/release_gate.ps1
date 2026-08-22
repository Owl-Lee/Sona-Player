[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$Tag = '',
    [ValidateSet('none', 'android', 'windows', 'all')]
    [string]$ArtifactSet = 'none',
    [string]$ArtifactDirectory = '',
    [string]$WindowsBuildDirectory = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Fail([string]$Message) {
    throw "Release gate failed: $Message"
}

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        Fail $Message
    }
}

function Read-RequiredFile([string]$Path) {
    Assert-True (Test-Path -LiteralPath $Path -PathType Leaf) "Missing required file: $Path"
    return Get-Content -LiteralPath $Path -Raw
}

function Resolve-ExistingDirectory([string]$Path, [string]$Label) {
    Assert-True (-not [string]::IsNullOrWhiteSpace($Path)) "$Label was not provided."
    Assert-True (Test-Path -LiteralPath $Path -PathType Container) "$Label does not exist: $Path"
    return (Resolve-Path -LiteralPath $Path).Path
}

function Test-ChecksumSidecar([string]$FilePath) {
    $sidecarPath = "$FilePath.sha256"
    Assert-True (Test-Path -LiteralPath $sidecarPath -PathType Leaf) "Missing checksum sidecar: $sidecarPath"

    $line = (Get-Content -LiteralPath $sidecarPath -Raw).Trim()
    $match = [regex]::Match($line, '^([0-9a-fA-F]{64})  ([^\\/]+)$')
    Assert-True $match.Success "Invalid SHA-256 sidecar format: $sidecarPath"
    Assert-True ($match.Groups[2].Value -ceq (Split-Path -Leaf $FilePath)) "Checksum sidecar must reference only the stable asset filename: $sidecarPath"

    $expected = $match.Groups[1].Value.ToLowerInvariant()
    $actual = (Get-FileHash -LiteralPath $FilePath -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-True ($actual -ceq $expected) "SHA-256 mismatch for $(Split-Path -Leaf $FilePath)."
}

$root = Resolve-ExistingDirectory $RepositoryRoot 'Repository root'
$pubspec = Read-RequiredFile (Join-Path $root 'pubspec.yaml')
$pubspecMatch = [regex]::Match(
    $pubspec,
    '(?m)^version:\s*["'']?(\d+\.\d+\.\d+)\+(\d+)["'']?\s*$'
)
Assert-True $pubspecMatch.Success 'pubspec.yaml must contain a stable x.y.z+build version.'
$version = $pubspecMatch.Groups[1].Value
$buildNumber = $pubspecMatch.Groups[2].Value
Assert-True ([int64]$buildNumber -gt 0) 'The Flutter build number must be positive.'

$installerPath = Join-Path $root 'installer/windows/Sona.iss'
$installer = Read-RequiredFile $installerPath
$installerVersionMatch = [regex]::Match(
    $installer,
    '(?m)^\s*#define\s+MyAppVersion\s+"(\d+\.\d+\.\d+)"\s*$'
)
Assert-True $installerVersionMatch.Success 'Sona.iss must define MyAppVersion as x.y.z.'
Assert-True ($installerVersionMatch.Groups[1].Value -ceq $version) "Version mismatch: pubspec.yaml is $version but Sona.iss is $($installerVersionMatch.Groups[1].Value)."

if ([string]::IsNullOrWhiteSpace($Tag) -and $env:GITHUB_REF_TYPE -eq 'tag') {
    $Tag = $env:GITHUB_REF_NAME
}
if (-not [string]::IsNullOrWhiteSpace($Tag)) {
    Assert-True ($Tag -ceq "v$version") "Release tag '$Tag' must exactly match pubspec version 'v$version'."
}

$releaseWorkflow = Read-RequiredFile (Join-Path $root '.github/workflows/release.yml')
$requiredWorkflowTokens = @(
    'Sona-Android.apk',
    'Sona-Windows-x64.zip',
    'SONA_ANDROID_KEYSTORE_BASE64',
    'SONA_ANDROID_STORE_PASSWORD',
    'SONA_ANDROID_KEY_PASSWORD',
    'SONA_ANDROID_KEY_ALIAS',
    'SONA_ACOUSTID_API_KEY',
    '1F6007D81EBF423D4EBD1AA1658C210D40241C879C97B7C164B233B5C1399BBD',
    'com.sonarvault.sonar_vault',
    'body_path: ${{ env.RELEASE_NOTES_PATH }}',
    'RELEASE_NOTES_PATH="docs/releases/$VERSION.md"',
    'fail_on_unmatched_files: true'
)
foreach ($token in $requiredWorkflowTokens) {
    Assert-True $releaseWorkflow.Contains($token) "Release workflow is missing required token '$token'."
}
$releaseNotesRelativePath = "docs/releases/$version.md"
$releaseNotesPath = Join-Path $root $releaseNotesRelativePath
$releaseNotes = Read-RequiredFile $releaseNotesPath
Assert-True $releaseNotes.Contains("# Sona $version Public Preview") "Release notes must start with the English $version title."
Assert-True $releaseNotes.Contains('## 简体中文') 'Release notes must include the complete Simplified Chinese section.'
Assert-True (-not [regex]::IsMatch($releaseNotes, '(?i)\b[0-9a-f]{64}\b')) 'Release notes must not contain package hashes before final artifacts are verified.'
Assert-True ([regex]::IsMatch($installer, '(?m)^OutputBaseFilename=Sona-Windows-x64-Setup\s*$')) 'Installer output name must remain Sona-Windows-x64-Setup.'
Assert-True ([regex]::IsMatch($installer, '(?m)^#define\s+MyAppExeName\s+"sonar_vault\.exe"\s*$')) 'Installer executable name must remain sonar_vault.exe.'
Assert-True ([regex]::IsMatch($installer, '(?m)^AppId=\{\{9A7B635B-B65D-46D6-A243-10B616C40C05\}\s*$')) 'Installer AppId changed; upgrades must keep the permanent Sona AppId.'

$workflowPaths = @(Get-ChildItem -LiteralPath (Join-Path $root '.github/workflows') -File -Include '*.yml', '*.yaml')
Assert-True ($workflowPaths.Count -gt 0) 'No GitHub Actions workflows were found.'
foreach ($workflowPath in $workflowPaths) {
    $workflowText = Read-RequiredFile $workflowPath.FullName
    $usesMatches = [regex]::Matches($workflowText, '(?m)^\s*-?\s*uses:\s*([^\s#]+)')
    foreach ($usesMatch in $usesMatches) {
        $reference = $usesMatch.Groups[1].Value
        if ($reference.StartsWith('./', [System.StringComparison]::Ordinal)) {
            continue
        }
        if ($reference.StartsWith('docker://', [System.StringComparison]::OrdinalIgnoreCase)) {
            Assert-True ([regex]::IsMatch($reference, '@sha256:[0-9a-fA-F]{64}$')) "Container action is not pinned to an immutable digest in $($workflowPath.Name): $reference"
            continue
        }
        Assert-True ([regex]::IsMatch($reference, '@[0-9a-fA-F]{40}$')) "Action is not pinned to an immutable commit SHA in $($workflowPath.Name): $reference"
    }
}

$candidateFiles = @(& git -C $root ls-files --cached --others --exclude-standard)
Assert-True ($LASTEXITCODE -eq 0) 'Unable to enumerate repository files with git.'
$credentialPattern = '(?i)(^|/)(key\.properties|\.env(?:\.[^/]+)?|id_(rsa|dsa|ecdsa|ed25519)|[^/]+\.(jks|keystore|p12|pfx|pem|private-key))$'
$trackedCredentials = @($candidateFiles | Where-Object {
    $normalized = $_ -replace '\\', '/'
    $normalized -match $credentialPattern -and $normalized -notmatch '(?i)\.env\.example$'
})
Assert-True ($trackedCredentials.Count -eq 0) "Credential-like files are present in the source set: $($trackedCredentials -join ', ')"

if (-not [string]::IsNullOrWhiteSpace($WindowsBuildDirectory)) {
    $windowsBuild = Resolve-ExistingDirectory $WindowsBuildDirectory 'Windows build directory'
    $windowsExe = Join-Path $windowsBuild 'sonar_vault.exe'
    Assert-True (Test-Path -LiteralPath $windowsExe -PathType Leaf) 'Windows build is missing sonar_vault.exe.'
    Assert-True (Test-Path -LiteralPath (Join-Path $windowsBuild 'flutter_windows.dll') -PathType Leaf) 'Windows build is missing flutter_windows.dll.'
    Assert-True (Test-Path -LiteralPath (Join-Path $windowsBuild 'data/flutter_assets') -PathType Container) 'Windows build is missing data/flutter_assets.'

    if ($env:OS -eq 'Windows_NT') {
        $productVersion = (Get-Item -LiteralPath $windowsExe).VersionInfo.ProductVersion
        Assert-True (-not [string]::IsNullOrWhiteSpace($productVersion)) 'Windows executable has no product version.'
        Assert-True ($productVersion -ceq "$version+$buildNumber") "Windows executable version '$productVersion' does not match '$version+$buildNumber'."
    }
}

if ($ArtifactSet -ne 'none') {
    $artifactRoot = Resolve-ExistingDirectory $ArtifactDirectory 'Artifact directory'
    $requiredAssets = switch ($ArtifactSet) {
        'android' { @('Sona-Android.apk') }
        'windows' { @('Sona-Windows-x64.zip', 'Sona-Windows-x64-Setup.exe') }
        'all' { @('Sona-Android.apk', 'Sona-Windows-x64.zip', 'Sona-Windows-x64-Setup.exe') }
    }

    $expectedFiles = @($requiredAssets | ForEach-Object { $_; "$_.sha256" })
    $actualFiles = @(Get-ChildItem -LiteralPath $artifactRoot -File | Select-Object -ExpandProperty Name)
    $missingFiles = @($expectedFiles | Where-Object { $_ -notin $actualFiles })
    $unexpectedFiles = @($actualFiles | Where-Object { $_ -notin $expectedFiles })
    Assert-True ($missingFiles.Count -eq 0) "Missing release assets: $($missingFiles -join ', ')"
    Assert-True ($unexpectedFiles.Count -eq 0) "Unexpected files in release assets: $($unexpectedFiles -join ', ')"

    foreach ($asset in $requiredAssets) {
        $assetPath = Join-Path $artifactRoot $asset
        Assert-True ((Get-Item -LiteralPath $assetPath).Length -gt 1MB) "Release asset is unexpectedly small: $asset"
        Test-ChecksumSidecar $assetPath
    }

    if ($ArtifactSet -in @('windows', 'all')) {
        if ($env:OS -eq 'Windows_NT') {
            $setupPath = Join-Path $artifactRoot 'Sona-Windows-x64-Setup.exe'
            $setupVersion = (Get-Item -LiteralPath $setupPath).VersionInfo.ProductVersion
            Assert-True (-not [string]::IsNullOrWhiteSpace($setupVersion)) 'Windows installer has no product version.'
            Assert-True ($setupVersion -ceq $version) "Windows installer version '$setupVersion' does not match '$version'."
        }

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zipPath = Join-Path $artifactRoot 'Sona-Windows-x64.zip'
        $archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            $entries = @($archive.Entries | Select-Object -ExpandProperty FullName)
            Assert-True ($entries -contains 'sonar_vault.exe') 'Windows ZIP must contain sonar_vault.exe at its root.'
            Assert-True ($entries -contains 'flutter_windows.dll') 'Windows ZIP must contain flutter_windows.dll at its root.'
            Assert-True (@($entries | Where-Object { $_ -like 'data/flutter_assets/*' }).Count -gt 0) 'Windows ZIP is missing Flutter assets.'
        }
        finally {
            $archive.Dispose()
        }
    }
}

Write-Host "Sona release gate passed: version $version, build $buildNumber, artifacts $ArtifactSet."
