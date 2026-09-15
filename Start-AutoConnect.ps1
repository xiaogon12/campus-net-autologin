<#
  CampusNet autologin - watchdog, started hidden by the Startup launcher.

  What it does:
    1. makes sure only one watchdog is running (a named mutex guards it)
    2. runs the main script in watch mode, so a dropped link is logged in again
       automatically - this also covers waking up from sleep / hibernate,
       because the main script re-checks the link every 30 seconds
    3. if the main script ever exits, it is started again after a short pause

  You normally do not run this file yourself: install it with
  1-Install-AutoStart.cmd instead.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Main,
    [switch]$NoWatch,
    [int]$RestartSeconds = 30
)

$ErrorActionPreference = 'Continue'

$mutex = $null
$haveLock = $false
try {
    $mutex = New-Object System.Threading.Mutex($false, 'Local\CampusNet-AutoConnect-Watch')
    try {
        $haveLock = $mutex.WaitOne(0, $false)
    } catch [System.Threading.AbandonedMutexException] {
        $haveLock = $true
    }
} catch {
    $haveLock = $true
}

if (-not $haveLock) {
    # another watchdog is already running - nothing to do
    exit 0
}

try {
    if (-not (Test-Path -LiteralPath $Main)) { exit 1 }

    if ($NoWatch) {
        & $Main
        exit $LASTEXITCODE
    }

    while ($true) {
        try {
            & $Main -Watch
        } catch {
            # ignore, the pause below restarts it
        }
        Start-Sleep -Seconds $RestartSeconds
    }
} finally {
    if ($mutex -and $haveLock) {
        try { $mutex.ReleaseMutex() } catch { }
        try { $mutex.Dispose() } catch { }
    }
}
