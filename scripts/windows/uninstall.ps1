# Stops Card Tracker and removes the startup task and firewall rule.
# Your collection, photos, settings and OneDrive backup are left in place.

. (Join-Path $PSScriptRoot 'common.ps1')

$config = Read-Config
$port = if ($config) { $config.Port } else { 3000 }

Write-Step 'Stopping Card Tracker'
Stop-CardTracker -Port $port
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host 'Removed the startup task.'
}

if (Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue) {
    Write-Step 'Removing the firewall rule (Windows will ask for permission)'
    try { Invoke-Elevated "Remove-NetFirewallRule -DisplayName '$RuleName'" | Out-Null } catch { }
}

Write-Host ''
Write-Host 'Card Tracker has been uninstalled.' -ForegroundColor Green
Write-Host "Your data is still in $ConfigDir"
if ($config -and $config.BackupDir) { Write-Host "and backed up in $($config.BackupDir)" }
