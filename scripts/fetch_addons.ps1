# Fetch Godot addons declared below into client/addons/.
# Usage (from repo root):
#   pwsh ./scripts/fetch_addons.ps1
# Addons are never committed (see .gitignore). Re-run after pulling
# whenever the list changes.

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$AddonsDir = Join-Path $RepoRoot "client/addons"

# Each entry: @{ name = "<dir>"; repo = "owner/repo"; tag = "vX.Y.Z"; asset = "<file.zip>"; strip = <int> }
# strip = number of leading path components to drop when extracting.
$Addons = @()

function Fetch-Release($entry) {
    $name = $entry.name
    $url = "https://github.com/$($entry.repo)/releases/download/$($entry.tag)/$($entry.asset)"
    $tmpDir = Join-Path $env:TEMP ("dronoid_addon_" + [Guid]::NewGuid())
    New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
    $zip = Join-Path $tmpDir $entry.asset
    Write-Host "Fetching $name from $url"
    Invoke-WebRequest -Uri $url -OutFile $zip
    $extract = Join-Path $tmpDir "extract"
    Expand-Archive -Path $zip -DestinationPath $extract
    $target = Join-Path $AddonsDir $name
    if (Test-Path $target) { Remove-Item -Recurse -Force $target }
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    # naive copy: caller handles strip via picking the right asset layout
    Copy-Item -Recurse (Join-Path $extract "*") $target
    Remove-Item -Recurse -Force $tmpDir
    Write-Host "Installed $name -> $target"
}

if ($Addons.Count -eq 0) {
    Write-Host "No addons declared yet."
    exit 0
}

New-Item -ItemType Directory -Force -Path $AddonsDir | Out-Null
foreach ($entry in $Addons) { Fetch-Release $entry }
