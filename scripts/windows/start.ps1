# Starts the Card Tracker server. Run by the "Card Tracker" scheduled task at log-on;
# you normally don't run this yourself.

. (Join-Path $PSScriptRoot 'common.ps1')

$config = Read-Config
if (-not $config) { throw "No configuration found at $ConfigFile. Run install.cmd first." }

foreach ($name in $SecretNames) {
    $value = $config.Secrets.$name
    if ($value) { Set-Item -Path "env:$name" -Value (Unprotect-Text $value) }
}
$env:DATA_DIR = $config.DataDir
if ($config.BackupDir) { $env:BACKUP_DIR = $config.BackupDir }
$env:EBAY_MARKETPLACE_ID = $config.EbayMarketplace

New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
$nextBin = Join-Path $AppDir 'node_modules\next\dist\bin\next'
$node = (Get-Command node).Source

Set-Location $AppDir
# Output goes to server.log / server-error.log in %LOCALAPPDATA%\CardTracker (replaced on each start).
$p = Start-Process -FilePath $node -WorkingDirectory $AppDir -NoNewWindow -Wait -PassThru `
    -ArgumentList @("`"$nextBin`"", 'start', '-H', '0.0.0.0', '-p', "$($config.Port)") `
    -RedirectStandardOutput (Join-Path $ConfigDir 'server.log') `
    -RedirectStandardError (Join-Path $ConfigDir 'server-error.log')
exit $p.ExitCode
