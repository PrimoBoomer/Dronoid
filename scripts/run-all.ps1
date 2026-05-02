# Launch the Rust server and the Godot client side-by-side.
# Usage (from repo root):
#   pwsh ./scripts/run-all.ps1 [-Godot <path-to-godot.exe>]
# Stop with Ctrl+C — both child jobs are terminated.

[CmdletBinding()]
param(
    [string]$Godot = $env:GODOT,
    [string]$Bind = $env:DRONOID_BIND
)

$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

if (-not $Godot) {
    $candidates = @(
        "godot",
        "godot.exe",
        "Godot_v4.6.2-stable_win64.exe",
        "Godot_v4.6.2-stable_win64_console.exe"
    )
    foreach ($c in $candidates) {
        $found = Get-Command $c -ErrorAction SilentlyContinue
        if ($found) { $Godot = $found.Source; break }
    }
}

if (-not $Godot) {
    Write-Error "Godot binary not found. Pass -Godot <path> or set GODOT env var."
}

$env:DRONOID_BIND = if ($Bind) { $Bind } else { "127.0.0.1:8080" }

Write-Host "[run-all] DRONOID_BIND=$($env:DRONOID_BIND)"
Write-Host "[run-all] Godot       =$Godot"

function Start-Server {
    return Start-Process -FilePath "cargo" `
        -ArgumentList @("run", "--manifest-path", (Join-Path $RepoRoot "server/Cargo.toml"), "--release", "--bin", "dronoid-server") `
        -PassThru -NoNewWindow
}

$server = Start-Server
Start-Sleep -Seconds 2

if ($server.HasExited) {
    $dbPath = Join-Path $RepoRoot "galaxy.sqlite"
    if (Test-Path $dbPath) {
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        Write-Host "[run-all] server exited early; backing up galaxy.sqlite* (likely incompatible schema)"
        foreach ($suffix in @("", "-shm", "-wal")) {
            $src = "$dbPath$suffix"
            if (Test-Path $src) { Move-Item -Force $src "$src.bak-$stamp" }
        }
        Write-Host "[run-all] retrying server"
        $server = Start-Server
        Start-Sleep -Seconds 2
    }
}

if ($server.HasExited) {
    Write-Error "[run-all] server failed to start (see output above)"
}

$client = Start-Process -FilePath $Godot `
    -ArgumentList @("--path", (Join-Path $RepoRoot "client")) `
    -PassThru -NoNewWindow

try {
    Wait-Process -Id $client.Id
}
finally {
    foreach ($p in @($server, $client)) {
        if ($p -and -not $p.HasExited) {
            try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
}
