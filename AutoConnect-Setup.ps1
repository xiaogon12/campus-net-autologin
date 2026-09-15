<#
  CampusNet autologin - install / remove the logon autostart entry.

  Installed mode (default): the watchdog keeps running in the background and
  logs the campus network in again whenever the link drops - including after
  waking up from sleep or hibernate. The main script re-checks every 30
  seconds, so a reconnect happens within about half a minute.

  One-shot mode: pass -NoWatch to log in once per logon and then exit.

  Usage:
    powershell -NoProfile -ExecutionPolicy Bypass -File AutoConnect-Setup.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File AutoConnect-Setup.ps1 -NoWatch
    powershell -NoProfile -ExecutionPolicy Bypass -File AutoConnect-Setup.ps1 -Remove
#>
[CmdletBinding()]
param(
    [switch]$Remove,
    [switch]$NoWatch,
    [string]$Target = ''
)

$ErrorActionPreference = 'Continue'

function Find-MainScript {
    param([string]$Folder)
    $exact = Join-Path -Path $Folder -ChildPath 'CampusNet-AutoConnect.ps1'
    if (Test-Path -LiteralPath $exact) { return $exact }
    $cand = Get-ChildItem -LiteralPath $Folder -Filter 'CampusNet-AutoConnect*.ps1' -File -ErrorAction SilentlyContinue |
            Sort-Object -Property Name | Select-Object -First 1
    if ($cand) { return $cand.FullName }
    return $null
}

$rootFolder = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($rootFolder)) { $rootFolder = (Get-Location).Path }
if ([string]::IsNullOrWhiteSpace($Target))   { $Target = $rootFolder }

$startupDir = [Environment]::GetFolderPath('Startup')
$launcher   = Join-Path -Path $startupDir -ChildPath 'CampusNet-AutoConnect.vbs'

if ($Remove) {
    if (Test-Path -LiteralPath $launcher) {
        Remove-Item -LiteralPath $launcher -Force
        Write-Host ''
        Write-Host 'Autostart removed - no automatic login any more.'
        Write-Host 'The watchdog may stay in memory until the next logoff; it is harmless.'
        Write-Host ''
    } else {
        Write-Host ''
        Write-Host 'Nothing to remove - autostart was not installed.'
        Write-Host ''
    }
    exit 0
}

Write-Host ''
Write-Host '=== CampusNet autologin : install ==='
Write-Host ''

$mainScript = Find-MainScript -Folder $Target
if (-not $mainScript) {
    Write-Host ('Main script not found in: ' + $Target) -ForegroundColor Red
    Write-Host 'CampusNet-AutoConnect.ps1 must sit in the same folder as this file.'
    exit 1
}

$watchdog = Join-Path -Path $Target -ChildPath 'Start-AutoConnect.ps1'
if (-not (Test-Path -LiteralPath $watchdog)) {
    Write-Host ('Watchdog script not found: ' + $watchdog) -ForegroundColor Red
    Write-Host 'Start-AutoConnect.ps1 must sit in the same folder as the main script.'
    exit 1
}

# make sure the password has been filled in
$text = [System.IO.File]::ReadAllText($mainScript, [System.Text.Encoding]::UTF8)
$passwordMissing = $false
foreach ($line in ($text -split "`n")) {
    if ($line -match '^[ \t]*[$]script:Password[ \t]*=') {
        $value = $line.Substring($line.IndexOf('=') + 1).Trim()
        if (($value -eq "''") -or ($value -eq '') -or ($value -eq "'YOUR_PASSWORD'")) { $passwordMissing = $true }
    }
}
if ($passwordMissing) {
    Write-Host 'The password is still empty in the script.' -ForegroundColor Red
    Write-Host ('Open it with Notepad and fill in the Password line: ' + $mainScript)
    exit 1
}

# build the hidden launcher (written as Unicode so non-ASCII paths also work)
$argLine = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $watchdog + '" -Main "' + $mainScript + '"'
if ($NoWatch) { $argLine += ' -NoWatch' }
$vbsCmd = ('powershell.exe ' + $argLine).Replace('"', '""')

$vbsLines = @()
$vbsLines += "' CampusNet autologin launcher - generated automatically, do not edit"
$vbsLines += 'On Error Resume Next'
$vbsLines += 'Set sh = CreateObject("WScript.Shell")'
$vbsLines += 'sh.Run "' + $vbsCmd + '", 0, False'

try {
    $unicode = New-Object System.Text.UnicodeEncoding($false, $true)
    [System.IO.File]::WriteAllText($launcher, ($vbsLines -join "`r`n"), $unicode)
} catch {
    Write-Host ('Could not write the launcher: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $launcher)) {
    Write-Host 'Install failed.' -ForegroundColor Red
    exit 1
}

Write-Host 'Installed.' -ForegroundColor Green
Write-Host ''
Write-Host ('Main script : ' + $mainScript)
Write-Host ('Watchdog    : ' + $watchdog)
Write-Host ('Launcher    : ' + $launcher)
if ($NoWatch) {
    Write-Host 'Mode        : once per logon (the script retries 5 times itself)'
} else {
    Write-Host 'Mode        : watch - stays in the background, reconnects within ~30s'
    Write-Host '              after a drop or after waking up from sleep'
}
Write-Host ('Log file    : ' + (Join-Path -Path $Target -ChildPath 'logs\CampusNet-AutoConnect.log'))
Write-Host ''
Write-Host 'Note: if you move this folder, run this installer again.'
Write-Host ''
