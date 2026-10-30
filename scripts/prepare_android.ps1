param(
    [string]$FlutterRoot = (Join-Path $PSScriptRoot '../.tools/flutter'),
    [switch]$UpdateLockfile
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sdkRoot = (Resolve-Path $FlutterRoot).Path
$flutter = Join-Path $sdkRoot 'bin/flutter'
if ($IsWindows) { $flutter += '.bat' }
$env:PUB_CACHE = Join-Path $projectRoot '.tools/pub-cache'
if ($IsWindows) {
    # Scoped to this process and child git commands; do not change global config.
    $configIndex = if ($env:GIT_CONFIG_COUNT) { [int]$env:GIT_CONFIG_COUNT } else { 0 }
    [Environment]::SetEnvironmentVariable("GIT_CONFIG_KEY_$configIndex", 'core.longpaths', 'Process')
    [Environment]::SetEnvironmentVariable("GIT_CONFIG_VALUE_$configIndex", 'true', 'Process')
    $env:GIT_CONFIG_COUNT = [string]($configIndex + 1)
}

function Invoke-CheckedPatch([string]$directory, [string]$relativePatch) {
    # A hosted package under this checkout must not inherit the app's Git root:
    # git apply would otherwise silently skip all paths outside that prefix.
    $ownGit = Join-Path $directory '.git'
    if (-not (Test-Path -LiteralPath $ownGit)) {
        git -C $directory init --quiet
        if ($LASTEXITCODE -ne 0) { throw "Cannot prepare patch directory: $directory" }
    }
    $patch = Join-Path $projectRoot "lib/scripts/$relativePatch"
    git -C $directory apply --reverse --check $patch 2>$null
    if ($LASTEXITCODE -eq 0) { return }
    git -C $directory apply --check $patch
    if ($LASTEXITCODE -ne 0) { throw "Patch does not match: $relativePatch" }
    git -C $directory apply $patch
    if ($LASTEXITCODE -ne 0) { throw "Patch failed: $relativePatch" }
    Write-Host "Applied $relativePatch"
}

# The upstream uses patched Flutter APIs. Only a dedicated SDK may be patched.
$expectedSdk = Join-Path $projectRoot '.tools/flutter'
if ([IO.Path]::GetFullPath($sdkRoot) -ne [IO.Path]::GetFullPath($expectedSdk)) {
    throw 'Use the isolated .tools/flutter checkout; shared SDKs are never modified.'
}
$revision = (git -C $sdkRoot rev-parse HEAD).Trim()
if ($revision -ne '737ba8f885dc774b53b442759999a312c9461e4e') {
    throw 'Flutter 3.47.8 is required. See README.md.'
}
Push-Location $projectRoot
try {
    $pubArguments = @('pub', 'get')
    if (-not $UpdateLockfile) { $pubArguments += '--enforce-lockfile' }
    & $flutter @pubArguments
    if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed' }
    $patches = @(
        'modal_barrier.patch', 'text_selection.patch', 'mouse_cursor.patch',
        'image_anim.patch', 'layout_builder.patch', 'navigation_drawer.patch',
        'popup_menu.patch', 'fab.patch', 'null_safety_for_selectable_region.patch',
        'selectable_region.patch', 'editable_text.patch', 'text_field.patch',
        'scroll_position.patch', 'scrollable.patch', 'scrollable_gesture.patch',
        'draggable_scrollable_sheet.patch', 'scaffold.patch', 'text.patch',
        'text_painter.patch', 'sliver.patch', 'refresh_indicator.patch',
        'double_tap_gesture.patch', 'bottom_sheet_android.patch', 'scroll_view.patch',
        'navigator.patch'
    )
    foreach ($patch in $patches) { Invoke-CheckedPatch $sdkRoot $patch }
    $configPath = Join-Path $projectRoot '.dart_tool/package_config.json'
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $package = $config.packages | Where-Object name -eq 'material_ui'
    $configUri = [Uri]::new($configPath)
    $packageDir = [Uri]::new($configUri, $package.rootUri).LocalPath
    foreach ($patch in @('modal_barrier_material.patch', 'navigation_drawer.patch',
        'popup_menu.patch', 'fab.patch', 'text_field.patch', 'scaffold.patch',
        'refresh_indicator.patch', 'tabs.patch', 'bottom_sheet_android.patch')) {
        Invoke-CheckedPatch $packageDir "material/$patch"
    }
    & (Join-Path $PSScriptRoot 'fetch_native_libs.ps1')
} finally { Pop-Location }
