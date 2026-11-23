# Pulls the latest Card Tracker code, rebuilds it, and restarts the server.

. (Join-Path $PSScriptRoot 'common.ps1')

$config = Read-Config
if (-not $config) { throw 'Card Tracker is not installed yet. Run install.cmd first.' }

Write-Step 'Stopping Card Tracker'
Stop-CardTracker -Port $config.Port

Set-Location $AppDir
if (Test-Path (Join-Path $AppDir '.git')) {
    Write-Step 'Downloading the latest version'
    Invoke-Native 'git pull' { git pull --ff-only }
} else {
    Write-Host 'This folder is not a git clone; skipping download and rebuilding the current files.'
}

Write-Step 'Installing dependencies'
Invoke-Native 'npm ci' { npm ci --no-audit --no-fund }
Write-Step 'Building the app'
Invoke-Native 'npm run build' { npm run build }

Write-Step 'Starting Card Tracker'
if (Start-CardTracker -Port $config.Port) {
    Write-Host 'Updated and running.' -ForegroundColor Green
} else {
    Write-Host "The server didn't respond. Check $ConfigDir\server-error.log" -ForegroundColor Red
    exit 1
}
