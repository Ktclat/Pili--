param([string]$platform = 'android')
if ($platform -ne 'android') {
    throw 'This fork currently validates Android only. See README.md.'
}
& (Join-Path $PSScriptRoot '../../scripts/prepare_android.ps1')
