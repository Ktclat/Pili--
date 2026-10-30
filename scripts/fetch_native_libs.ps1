$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$targetDir = Join-Path $root 'build/media_kit_libs_android_video/20260906'
New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
# Same release and checksums as pinned media-kit commit 73771ec38176be2d984a3049c28177bce23b54a0.
$artifacts = @{
    'default-arm64-v8a.jar' = '98df6410375cc7a4be7e6eff56f9ccd88fa52678973cc23bcf7e934ab8c8682d'
    'default-armeabi-v7a.jar' = '75ba2199848cd6224817320ddfabb7d7ea48fb4cfb1721b0090043d5a8a38602'
    'default-x86_64.jar' = '1caa6198de22808bd7f10fcff2923f5eb174cc42ef24569aeafb98c6597457a4'
}
foreach ($name in $artifacts.Keys) {
    $target = Join-Path $targetDir $name
    if ((Test-Path -LiteralPath $target) -and
        (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -eq $artifacts[$name]) { continue }
    $temporary = "$target.download"
    $url = "https://github.com/My-Responsitories/libmpv-android-video-build/releases/download/20260906/$name"
    try {
        Invoke-WebRequest -Uri $url -OutFile $temporary -UserAgent 'PiliMinus-Android-Build/0.1' -TimeoutSec 120
        if ((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash -ne $artifacts[$name]) {
            throw "Native library checksum mismatch: $name"
        }
        Move-Item -LiteralPath $temporary -Destination $target -Force
        Write-Host "Verified $name"
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
    }
}
