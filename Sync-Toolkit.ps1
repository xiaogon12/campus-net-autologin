<#
  CampusNet autologin - make the folder you actually use match this toolkit.

  It does four things:
    1. renames a "CampusNet-AutoConnect-fixed.ps1" style file back to
       CampusNet-AutoConnect.ps1  (older name is kept as a .bak-<date> copy)
    2. keeps your account / password / service / portal values
    3. copies the launcher and helper files into that folder
    4. removes the obsolete helper files from earlier versions

  Usage:
    powershell -NoProfile -ExecutionPolicy Bypass -File Sync-Toolkit.ps1 -Target "D:\CampusNet\campus-net-autologin"
#>
[CmdletBinding()]
param(
    [string]$Target = 'D:\CampusNet\campus-net-autologin'
)

$ErrorActionPreference = 'Continue'
$src = $PSScriptRoot
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$utf8Plain = New-Object System.Text.UTF8Encoding($false)
$utf8Bom   = New-Object System.Text.UTF8Encoding($true)

$keepNames = @('Username', 'Password', 'Service', 'PortalUrl')
$supportFiles = @(
    'AutoConnect-Setup.ps1'
    'Start-AutoConnect.ps1'
    'Sync-Toolkit.ps1'
    '0-Collect-Logs.cmd'
    '1-Install-AutoStart.cmd'
    '2-Test-Now.cmd'
    '3-Uninstall-AutoStart.cmd'
    '4-Sync-Toolkit.cmd'
)
$obsoletePatterns = @('0-*.cmd', '4-*.cmd', 'Update-Script.ps1')

Write-Host ''
Write-Host '=== CampusNet autologin : sync toolkit ==='
Write-Host ''

if (-not (Test-Path -LiteralPath $Target)) {
    Write-Host ('Target folder does not exist: ' + $Target) -ForegroundColor Red
    Write-Host 'Create it first, or pass the right path: -Target "D:\your\folder"'
    exit 1
}

$masterPath = Join-Path -Path $src -ChildPath 'CampusNet-AutoConnect.ps1'
if (-not (Test-Path -LiteralPath $masterPath)) {
    Write-Host ('Master script is missing: ' + $masterPath) -ForegroundColor Red
    exit 1
}

$canonical = Join-Path -Path $Target -ChildPath 'CampusNet-AutoConnect.ps1'

# --- 1. find existing main scripts in the target folder -------------------
$existing = @()
foreach ($f in @(Get-ChildItem -LiteralPath $Target -Filter 'CampusNet-AutoConnect*.ps1' -File -ErrorAction SilentlyContinue)) {
    $existing += $f
}
$existing = @($existing | Sort-Object -Property LastWriteTime -Descending)

# --- 2. take the account settings from the script that has been in use ----
$settings = @{}
if ($existing.Count -gt 0) {
    $oldText = [System.IO.File]::ReadAllText($existing[0].FullName, [System.Text.Encoding]::UTF8)
    foreach ($name in $keepNames) {
        $m = [regex]::Match($oldText, '(?m)^[ \t]*[$]script:' + $name + '[ \t]*=[ \t]*.*$')
        if ($m.Success) { $settings[$name] = $m.Value }
    }
    Write-Host ('Reading settings from: ' + $existing[0].Name)
} else {
    Write-Host 'No existing script in the target folder - installing the master copy as-is.'
}

# --- 3. write the canonical script --------------------------------------
$newText = [System.IO.File]::ReadAllText($masterPath, [System.Text.Encoding]::UTF8)
foreach ($name in $keepNames) {
    if (-not $settings.ContainsKey($name)) { continue }
    $keepLine = $settings[$name]
    $newText = [regex]::Replace($newText, '(?m)^[ \t]*[$]script:' + $name + '[ \t]*=[ \t]*.*$', { param($x) $keepLine })
    Write-Host ('  kept setting: ' + $name)
}
# pure-ASCII file stays byte-for-byte identical to what you had (no BOM added)
$isAscii = $true
foreach ($ch in $newText.ToCharArray()) { if ([int]$ch -gt 127) { $isAscii = $false; break } }
if ($isAscii) { [System.IO.File]::WriteAllText($canonical, $newText, $utf8Plain) }
else          { [System.IO.File]::WriteAllText($canonical, $newText, $utf8Bom) }
Write-Host ('Written: ' + $canonical)

# --- 4. rename the old names out of the way -----------------------------
foreach ($f in $existing) {
    if ($f.FullName -ieq $canonical) { continue }
    $backup = $f.FullName + '.bak-' + $stamp
    try {
        Move-Item -LiteralPath $f.FullName -Destination $backup -Force
        Write-Host ('  renamed: ' + $f.Name + '  ->  ' + (Split-Path -Leaf $backup))
    } catch {
        Write-Host ('  could not rename ' + $f.Name + ' : ' + $_.Exception.Message) -ForegroundColor Yellow
    }
}

# --- 5. copy the helper files -------------------------------------------
foreach ($name in $supportFiles) {
    $s = Join-Path -Path $src -ChildPath $name
    if (-not (Test-Path -LiteralPath $s)) { continue }
    Copy-Item -LiteralPath $s -Destination (Join-Path -Path $Target -ChildPath $name) -Force
}
# the manual (any .md file) travels along as well
foreach ($md in @(Get-ChildItem -LiteralPath $src -Filter '*.md' -File -ErrorAction SilentlyContinue)) {
    Copy-Item -LiteralPath $md.FullName -Destination (Join-Path -Path $Target -ChildPath $md.Name) -Force
}
Write-Host 'Helper files copied.'

# --- 6. drop helper files left over from earlier versions ---------------
foreach ($pattern in $obsoletePatterns) {
    foreach ($f in @(Get-ChildItem -LiteralPath $Target -Filter $pattern -File -ErrorAction SilentlyContinue)) {
        if ($supportFiles -contains $f.Name) { continue }
        try {
            Remove-Item -LiteralPath $f.FullName -Force
            Write-Host ('  removed obsolete file: ' + $f.Name)
        } catch {
            Write-Host ('  could not remove ' + $f.Name) -ForegroundColor Yellow
        }
    }
}

Write-Host ''
Write-Host 'Done. The folder now contains:' -ForegroundColor Green
Get-ChildItem -LiteralPath $Target -File | Sort-Object -Property Name |
    ForEach-Object { Write-Host ('    ' + $_.Name) }
Write-Host ''
Write-Host 'Next steps:'
Write-Host '    1) double-click  2-Test-Now.cmd'
Write-Host '    2) when it reports OK, double-click  1-Install-AutoStart.cmd'
Write-Host ''
