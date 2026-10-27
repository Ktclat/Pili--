param(
    [switch]$RequireReleaseSigning,
    [ValidateSet('', 'android-arm', 'android-arm64', 'android-x64')]
    [string]$TargetPlatform = ''
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$flutter = Join-Path $projectRoot '.tools/flutter/bin/flutter'
if ($IsWindows) { $flutter += '.bat' }
$env:PUB_CACHE = Join-Path $projectRoot '.tools/pub-cache'

if (-not (Test-Path -LiteralPath $flutter)) {
    throw 'Prepare the isolated Flutter SDK first. See README.md.'
}
$pubspec = Get-Content -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)\+(\d+)\s*$') {
    throw 'pubspec.yaml must declare a semantic version and Android build number.'
}
$versionName = $matches[1]
$versionCode = $matches[2]

if ($RequireReleaseSigning) {
    $keyFile = Join-Path $projectRoot 'android/key.properties'
    if (-not (Test-Path -LiteralPath $keyFile)) {
        throw 'Formal distribution requires your own android/key.properties and signing key.'
    }
    $keyProperties = Get-Content -LiteralPath $keyFile -Raw
    foreach ($property in @('storeFile', 'storePassword', 'keyAlias', 'keyPassword')) {
        if ($keyProperties -notmatch "(?m)^\s*$property\s*=\s*\S+") {
            throw "Release signing configuration is missing $property."
        }
    }
}

Push-Location $projectRoot
try {
    $commitHash = (git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot determine the source commit.' }
    $changes = git status --porcelain --untracked-files=normal
    if ($LASTEXITCODE -ne 0) { throw 'Cannot determine the working tree state.' }
    if ($changes) {
        if ($RequireReleaseSigning) {
            throw 'Commit the reviewed source before building a formally signed distribution.'
        }
        $commitHash += '-dirty'
    }
    $buildTime = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $arguments = @(
        'build', 'apk', '--release', '--split-per-abi', '--no-pub',
        "--dart-define=pili.name=$versionName",
        "--dart-define=pili.code=$versionCode",
        "--dart-define=pili.hash=$commitHash",
        "--dart-define=pili.time=$buildTime"
    )
    if ($TargetPlatform) { $arguments += "--target-platform=$TargetPlatform" }
    Write-Host "Building Pili-- $versionName+$versionCode ($commitHash)"
    & $flutter @arguments
    if ($LASTEXITCODE -ne 0) { throw 'Android APK build failed.' }
} finally { Pop-Location }
