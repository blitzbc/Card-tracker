# Shared settings and helpers for the Card Tracker Windows scripts.
# Written for Windows PowerShell 5.1 (built into Windows 10/11).

$ErrorActionPreference = 'Stop'

$AppDir     = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ConfigDir  = Join-Path $env:LOCALAPPDATA 'CardTracker'
$ConfigFile = Join-Path $ConfigDir 'config.json'
$TaskName   = 'Card Tracker'
$RuleName   = 'Card Tracker'
$SecretNames = @('APP_PASSWORD', 'ANTHROPIC_API_KEY', 'EBAY_CLIENT_ID', 'EBAY_CLIENT_SECRET')

function Write-Step([string]$Message) {
    Write-Host ''
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Read-Config {
    if (-not (Test-Path $ConfigFile)) { return $null }
    return Get-Content $ConfigFile -Raw | ConvertFrom-Json
}

# Secrets are stored with Windows DPAPI: only this Windows user on this PC can decrypt them.
function Protect-Text([string]$Plain) {
    if (-not $Plain) { return '' }
    return ConvertTo-SecureString $Plain -AsPlainText -Force | ConvertFrom-SecureString
}

function Unprotect-Text([string]$Encrypted) {
    if (-not $Encrypted) { return '' }
    $secure = ConvertTo-SecureString $Encrypted
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function SecureString-ToProtected([Security.SecureString]$Secure) {
    if ($Secure.Length -eq 0) { return '' }
    return ConvertFrom-SecureString $Secure
}

# Stops the background server (the scheduled task and the node process on our port).
function Stop-CardTracker([int]$Port) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    }
    $conns = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    foreach ($c in $conns) {
        $proc = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue
        if ($proc -and $proc.ProcessName -eq 'node') {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        }
    }
    Start-Sleep -Seconds 1
}

function Start-CardTracker([int]$Port) {
    Start-ScheduledTask -TaskName $TaskName
    Write-Host 'Waiting for the server to start...'
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 1
        try {
            Invoke-WebRequest "http://localhost:$Port/login" -UseBasicParsing -TimeoutSec 2 | Out-Null
            return $true
        } catch { }
    }
    return $false
}

# Runs a PowerShell command as administrator (shows a Windows UAC prompt).
function Invoke-Elevated([string]$Command) {
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Command))
    $p = Start-Process powershell.exe -Verb RunAs -Wait -PassThru `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded)
    return ($p.ExitCode -eq 0)
}

function Invoke-Native([string]$What, [scriptblock]$Block) {
    & $Block
    if ($LASTEXITCODE -ne 0) { throw "$What failed (exit code $LASTEXITCODE)." }
}
