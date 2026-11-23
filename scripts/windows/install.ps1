# Installs Card Tracker on this PC: asks for your keys and a password, builds the
# app, starts it in the background at log-on, and opens the firewall port for your
# home network and Tailscale. Safe to run again to change settings.

param([int]$Port = 3000)

. (Join-Path $PSScriptRoot 'common.ps1')

Write-Host 'Card Tracker setup' -ForegroundColor Green
Write-Host "App folder: $AppDir"

# --- Node.js -----------------------------------------------------------------
Write-Step 'Checking Node.js'
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host 'Node.js is not installed. Installing the LTS version with winget...'
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'winget is not available. Install Node.js LTS from https://nodejs.org, then run this again.'
    }
    Invoke-Native 'Installing Node.js' { winget install -e --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements }
    Write-Host ''
    Write-Host 'Node.js installed. Close this window and run install.cmd again so Windows picks it up.' -ForegroundColor Yellow
    exit 0
}
$nodeVersion = [version]((& node -v).TrimStart('v'))
if ($nodeVersion -lt [version]'20.0.0') {
    throw "Node.js $nodeVersion is too old. Install Node.js 20 or newer from https://nodejs.org."
}
Write-Host "Node.js $nodeVersion"

# --- Settings ----------------------------------------------------------------
Write-Step 'Settings'
New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
$old = Read-Config
$secrets = @{}
foreach ($name in $SecretNames) { $secrets[$name] = if ($old) { $old.Secrets.$name } else { '' } }

Write-Host 'Typing is hidden for keys and the password. Press Enter to keep an existing value.'
$prompts = [ordered]@{
    APP_PASSWORD       = 'Password for signing in to the app'
    ANTHROPIC_API_KEY  = 'Anthropic API key (console.anthropic.com)'
    EBAY_CLIENT_ID     = 'eBay App ID / Client ID (Production)'
    EBAY_CLIENT_SECRET = 'eBay Cert ID / Client Secret (Production)'
}
foreach ($name in $prompts.Keys) {
    $label = $prompts[$name]
    if ($secrets[$name]) { $label += ' [saved]' }
    $entered = SecureString-ToProtected (Read-Host -Prompt $label -AsSecureString)
    if ($entered) { $secrets[$name] = $entered }
}
if (-not $secrets['APP_PASSWORD']) {
    throw 'A password is required, because the app is reachable from other devices on your network.'
}

$defaultBackup = ''
if ($old -and $old.BackupDir) { $defaultBackup = $old.BackupDir } elseif ($env:OneDrive) { $defaultBackup = Join-Path $env:OneDrive 'CardTracker' }
$backup = Read-Host -Prompt "OneDrive backup folder [$defaultBackup]"
if (-not $backup) { $backup = $defaultBackup }
if (-not $backup) { Write-Host 'No backup folder set; backups are off.' -ForegroundColor Yellow }

$config = [ordered]@{
    Port            = $Port
    DataDir         = if ($old -and $old.DataDir) { $old.DataDir } else { Join-Path $ConfigDir 'data' }
    BackupDir       = $backup
    EbayMarketplace = if ($old -and $old.EbayMarketplace) { $old.EbayMarketplace } else { 'EBAY_US' }
    Secrets         = $secrets
}
$config | ConvertTo-Json -Depth 4 | Set-Content -Path $ConfigFile -Encoding UTF8
Write-Host "Saved settings to $ConfigFile"
Write-Host "Collection database: $($config.DataDir)"

# --- Build -------------------------------------------------------------------
Write-Step 'Stopping any running copy'
if ($old) { Stop-CardTracker -Port $old.Port }
Stop-CardTracker -Port $Port

Write-Step 'Installing dependencies (a few minutes the first time)'
Set-Location $AppDir
Invoke-Native 'npm ci' { npm ci --no-audit --no-fund }

Write-Step 'Building the app'
Invoke-Native 'npm run build' { npm run build }

# --- Background task ---------------------------------------------------------
Write-Step 'Setting it to start automatically when you log in'
$user = "$env:USERDOMAIN\$env:USERNAME"
$startScript = Join-Path $PSScriptRoot 'start.ps1'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$startScript`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
    -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal `
    -Settings $settings -Description 'Runs the Card Tracker web app.' -Force | Out-Null

# --- Firewall ----------------------------------------------------------------
Write-Step 'Allowing your phone through Windows Firewall'
$rule = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue
$rulePort = if ($rule) { ($rule | Get-NetFirewallPortFilter).LocalPort } else { $null }
if ("$rulePort" -eq "$Port") {
    Write-Host 'Firewall rule already in place.'
} else {
    Write-Host 'Windows will ask for permission to add a firewall rule (home network + Tailscale only).'
    $cmd = "Remove-NetFirewallRule -DisplayName '$RuleName' -ErrorAction SilentlyContinue; " +
           "New-NetFirewallRule -DisplayName '$RuleName' -Direction Inbound -Action Allow -Protocol TCP " +
           "-LocalPort $Port -RemoteAddress LocalSubnet,100.64.0.0/10 -Profile Any | Out-Null"
    try {
        if (-not (Invoke-Elevated $cmd)) { throw 'rule command failed' }
        Write-Host 'Firewall rule added.'
    } catch {
        Write-Host 'Could not add the firewall rule. Your phone may not be able to connect until it is added.' -ForegroundColor Yellow
    }
}

# --- Start -------------------------------------------------------------------
Write-Step 'Starting Card Tracker'
if (-not (Start-CardTracker -Port $Port)) {
    Write-Host "The server didn't respond. Check $ConfigDir\server-error.log" -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host 'Card Tracker is running.' -ForegroundColor Green
Write-Host "On this PC:            http://localhost:$Port"
$ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.254.*' }
foreach ($ip in $ips) {
    $where = if ($ip.IPAddress -like '100.*') { 'Phone via Tailscale:' } else { 'Phone on home Wi-Fi: ' }
    Write-Host "$where  http://$($ip.IPAddress):$Port"
}
if (Get-Command tailscale -ErrorAction SilentlyContinue) {
    Write-Host "Tailscale name:        http://$($env:COMPUTERNAME.ToLower()):$Port"
} else {
    Write-Host ''
    Write-Host 'To use it away from home, install Tailscale on this PC and your phone: https://tailscale.com/download'
}
