# One-shot build & publish for the Windows Tauri frontend.
#
#   .\release.ps1              # build and publish to GitHub Release
#   .\release.ps1 -Tag "v1.0.0" # specify release tag
#   .\release.ps1 -NoPublish  # build only, skip upload
#
# Requires:
#   - GitHub CLI (gh) installed and authenticated
#   - Rust / Cargo (build.ps1 checks this)
#   - Node.js (build.ps1 checks this)
#   - Python 3 (build.ps1 checks this)
param(
    [string]$Tag = "",
    [switch]$NoPublish
)

$ErrorActionPreference = "Stop"

function Get-JsonVersion($path) {
    $json = Get-Content $path -Raw | ConvertFrom-Json
    return $json.version
}

function Get-TomlVersion($path) {
    $content = Get-Content $path -Raw
    $match = [regex]::Match($content, '^\s*version\s*=\s*"([^"]+)"', [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if ($match.Success) { return $match.Groups[1].Value }
    return $null
}

$tauriVersion = Get-JsonVersion "$PSScriptRoot\src-tauri\tauri.conf.json"
$cargoVersion = Get-TomlVersion "$PSScriptRoot\src-tauri\Cargo.toml"

if ($tauriVersion -ne $cargoVersion) {
    throw "Version mismatch: tauri.conf.json ($tauriVersion) vs Cargo.toml ($cargoVersion)"
}

Write-Host "==> Building Windows widget v$tauriVersion…"
& "$PSScriptRoot\build.ps1"

$bundleDir = "$PSScriptRoot\src-tauri\target\release\bundle"
$msi = Get-ChildItem "$bundleDir\msi\*.msi" -ErrorAction SilentlyContinue | Select-Object -First 1
$nsis = Get-ChildItem "$bundleDir\nsis\*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $msi -and -not $nsis) {
    throw "No installer found in $bundleDir"
}

Write-Host "Build complete."
if ($msi) { Write-Host "  MSI: $($msi.FullName)" }
if ($nsis) { Write-Host "  NSIS: $($nsis.FullName)" }

if ($NoPublish) {
    Write-Host "-NoPublish set — skipping upload."
    exit
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI (gh) is required for publishing. Install from https://cli.github.com/"
}

$releaseTag = if ($Tag) { $Tag } else { "windows-widget-v$tauriVersion" }

$releaseExists = $null
$releaseExists = gh release view "$releaseTag" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Creating release $releaseTag…"
    gh release create "$releaseTag" --title "Windows Widget $tauriVersion" --notes "Windows AI Agent Usage Widget $tauriVersion" --repo "lazyfoxy33-dev/ai-agent-usage-widget"
}

foreach ($artifact in @($msi, $nsis)) {
    if ($artifact) {
        Write-Host "Uploading $($artifact.Name)…"
        gh release upload "$releaseTag" "$($artifact.FullName)" --clobber --repo "lazyfoxy33-dev/ai-agent-usage-widget"
    }
}

Write-Host "✓ Windows release published: $releaseTag"
