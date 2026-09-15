#requires -version 5.1

param(
    [switch]$Visible,
    [switch]$Watch
)

# ============================================================
# Config
# ============================================================

$script:Username = 'YOUR_STUDENT_ID'
$script:Password = 'YOUR_PASSWORD'
$script:Service = 'Free'
$script:PortalUrl = 'http://172.168.254.4/a79.htm'

# Dr.COM Params
$script:UsernamePrefix = ',0,'
$script:ITermType = '1'
$script:LoginMethod = '1'
$script:JsVersion = '3.0'
$script:Version = '1.3.5.201712141.P.W.A'
$script:MKKey = '123456'

$script:MaxRetry = 5
$script:RetrySeconds = 5
$script:LoginWaitSeconds = 3
$script:WatchIntervalSeconds = 30

# ============================================================
# Path
# ============================================================

$script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$script:LogDir = Join-Path $script:ScriptDir 'logs'

if (-not (Test-Path $script:LogDir)) {
    New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
}

$script:LogFile = Join-Path $script:LogDir 'CampusNet-AutoConnect.log'

# ============================================================
# Log
# ============================================================

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = 'INFO'
    )

    $time = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = '[{0}] [{1}] {2}' -f $time, $Level, $Message

    try {
        Add-Content -Path $script:LogFile -Value $line -Encoding UTF8
    }
    catch {}

    Write-Host $line
}

# ============================================================
# Test Internet
# ============================================================

function Test-Internet {
    try {
        $r = Invoke-WebRequest -Uri 'http://www.msftconnecttest.com/connecttest.txt' -Method Get -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
        if ($r.StatusCode -eq 200 -and ($r.Content -match 'Microsoft')) {
            return $true
        }
    }
    catch {}

    try {
        $r2 = Invoke-WebRequest -Uri 'http://connectivitycheck.gstatic.com/generate_204' -Method Get -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
        if ($r2.StatusCode -eq 204) {
            return $true
        }
    }
    catch {}

    return $false
}

# ============================================================
# Get IPv4
# ============================================================

function Get-LocalIPv4 {
    try {
        $config = Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object {
            $_.IPv4DefaultGateway -ne $null -and 
            $_.NetAdapter.Status -eq 'Up' -and
            $_.NetAdapter.Virtual -ne $true
        } | Select-Object -First 1

        if ($config -and $config.IPv4Address) {
            return [string]$config.IPv4Address.IPAddress
        }

        $items = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
            $_.IPAddress -notlike '127.*' -and
            $_.IPAddress -notlike '169.254.*' -and
            $_.IPAddress -notlike '172.17.*'
        }

        foreach ($item in $items) {
            if ($item.IPAddress) {
                return [string]$item.IPAddress
            }
        }
    }
    catch {}

    return ''
}

# ============================================================
# Query Parser
# ============================================================

function Get-QueryValue {
    param(
        [string]$Query,
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Query)) { return '' }

    $q = $Query
    if ($q.StartsWith('?')) { $q = $q.Substring(1) }
    $parts = $q.Split('&')

    foreach ($part in $parts) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        $equal = $part.IndexOf('=')
        if ($equal -lt 0) { continue }
        $key = $part.Substring(0, $equal)
        $value = $part.Substring($equal + 1)
        if ($key -ieq $Name) {
            try { return [uri]::UnescapeDataString($value) } catch { return $value }
        }
    }
    return ''
}

# ============================================================
# Portal Context
# ============================================================

function Get-PortalContext {
    Write-Log 'Checking portal status...' 'INFO'
    $portalResponse = $null

    try {
        $portalResponse = Invoke-WebRequest -Uri $script:PortalUrl -Method Get -TimeoutSec 10 -MaximumRedirection 5 -UseBasicParsing -ErrorAction Stop
    }
    catch {
        Write-Log ("Portal exception: {0}" -f $_.Exception.Message) 'DEBUG'
        if ($_.Exception.Response) {
            try { $portalResponse = $_.Exception.Response } catch {}
        }
    }

    $finalUrl = $script:PortalUrl
    if ($portalResponse -and $portalResponse.BaseResponse -and $portalResponse.BaseResponse.ResponseUri) {
        $finalUrl = [string]($portalResponse.BaseResponse.ResponseUri.AbsoluteUri)
    }

    Write-Log ("Portal URL: {0}" -f $finalUrl) 'DEBUG'

    $userIp = ''
    $acIp = ''
    $acName = ''

    try {
        $uri = New-Object System.Uri($finalUrl)
        $query = $uri.Query
        $userIp = Get-QueryValue -Query $query -Name 'wlanuserip'
        $acIp = Get-QueryValue -Query $query -Name 'wlanacip'
        $acName = Get-QueryValue -Query $query -Name 'wlanacname'
    }
    catch {
        Write-Log ("Parse URL failed: {0}" -f $_.Exception.Message) 'DEBUG'
    }

    if ([string]::IsNullOrWhiteSpace($userIp)) {
        $userIp = Get-LocalIPv4
        Write-Log ("Using Local Interface IP: {0}" -f $userIp) 'DEBUG'
    }

    if ([string]::IsNullOrWhiteSpace($acIp)) {
        $acIp = '172.168.254.100'
        Write-Log 'Using Fallback AC IP: 172.168.254.100' 'DEBUG'
    }

    $loginUrl = 'http://172.168.254.4:801/eportal/?c=ACSetting&a=Login'

    return [PSCustomObject]@{
        PortalUrl = $finalUrl
        LoginUrl  = $loginUrl
        UserIp    = $userIp
        AcIp      = $acIp
        AcName    = $acName
    }
}

# ============================================================
# URL Encode
# ============================================================

function Encode-Value {
    param([string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return '' }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $sb = New-Object System.Text.StringBuilder
    foreach ($b in $bytes) {
        $ch = [char]$b
        if (($ch -ge 'a' -and $ch -le 'z') -or ($ch -ge 'A' -and $ch -le 'Z') -or ($ch -ge '0' -and $ch -le '9') -or $ch -eq '-' -or $ch -eq '_' -or $ch -eq '.' -or $ch -eq '~') {
            [void]$sb.Append($ch)
        } else {
            [void]$sb.AppendFormat('%{0:X2}', $b)
        }
    }
    return $sb.ToString()
}

# ============================================================
# Login Body
# ============================================================

function New-LoginBody {
    param(
        [object]$Info,
        [string]$FullUsername
    )

    $hostname = '172.168.254.4'
    try { $hostname = ([uri]$Info.LoginUrl).Host } catch {}

    $data = [ordered]@{
        c             = 'ACSetting'
        a             = 'Login'
        DDDDD         = $FullUsername
        upass         = $script:Password
        protocol      = 'http:'
        hostname      = $hostname
        iTermType     = $script:ITermType
        wlanuserip    = $Info.UserIp
        wlanacip      = $Info.AcIp
        wlanacname    = $Info.AcName
        mac           = '00-00-00-00-00-00'
        ip            = $Info.UserIp
        enAdvert      = '0'
        queryACIP     = '0'
        loginMethod   = $script:LoginMethod
        jsVersion     = $script:JsVersion
        ver           = $script:Version
        R1            = '0'
        R2            = '0'
        R3            = '0'
        R6            = '0'
        para          = '00'
        '0MKKey'      = $script:MKKey
        buttonClicked = ''
        redirect_url  = ''
        err_flag      = ''
        username      = ''
        password      = ''
        user          = ''
        cmd           = ''
        Login         = ''
        v6ip          = ''
    }

    $pairs = New-Object System.Collections.ArrayList
    foreach ($key in $data.Keys) {
        $encodedKey = Encode-Value $key
        $encodedValue = Encode-Value ([string]$data[$key])
        [void]$pairs.Add(($encodedKey + '=' + $encodedValue))
    }

    return ($pairs -join '&')
}

# ============================================================
# Submit Login
# ============================================================

function Submit-Login {
    param(
        [object]$Info,
        [string]$FullUsername
    )

    $body = New-LoginBody -Info $Info -FullUsername $FullUsername

    Write-Log ("Submitting User: {0}" -f $FullUsername) 'DEBUG'
    Write-Log ("Client IP: {0}" -f $Info.UserIp) 'DEBUG'

    try {
        $headers = @{
            Referer = $Info.PortalUrl
            Origin  = 'http://172.168.254.4'
        }

        $response = Invoke-WebRequest -Uri $Info.LoginUrl -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded' -Headers $headers -TimeoutSec 15 -UseBasicParsing -ErrorAction Stop

        Write-Log ("HTTP Status: {0}" -f $response.StatusCode) 'DEBUG'
        return $true
    }
    catch {
        Write-Log ("Login POST Request Failed: {0}" -f $_.Exception.Message) 'WARN'
        return $false
    }
}

# ============================================================
# Connect Flow
# ============================================================

function Connect-CampusNet {
    if (Test-Internet) {
        Write-Log 'Internet is fully functional.' 'INFO'
        return $true
    }

    Write-Log 'Network offline. Initiating login...' 'INFO'
    $Info = Get-PortalContext

    if (-not $Info) {
        Write-Log 'Failed to get Portal context.' 'ERROR'
        return $false
    }

    $users = @()
    if (-not [string]::IsNullOrWhiteSpace($script:UsernamePrefix)) {
        $users += ($script:UsernamePrefix + $script:Username)
    }
    $users += $script:Username
    $users = $users | Select-Object -Unique

    foreach ($fullUser in $users) {
        Write-Log ("Trying format: {0}" -f $fullUser) 'INFO'

        for ($retry = 1; $retry -le $script:MaxRetry; $retry++) {
            Write-Log ("Attempting {0}/{1}..." -f $retry, $script:MaxRetry) 'INFO'

            $submitted = Submit-Login -Info $Info -FullUsername $fullUser

            if ($submitted) {
                Write-Log ("Request sent. Waiting {0}s..." -f $script:LoginWaitSeconds) 'INFO'
                Start-Sleep -Seconds $script:LoginWaitSeconds

                if (Test-Internet) {
                    Write-Host '============================================'
                    Write-Host '          LOGIN SUCCESSFUL!          '
                    Write-Host '============================================'
                    Write-Log 'Campus Network online.' 'INFO'
                    return $true
                }
            }

            if ($retry -lt $script:MaxRetry) {
                Start-Sleep -Seconds $script:RetrySeconds
            }
        }
    }

    Write-Host '============================================'
    Write-Host '            LOGIN FAILED             '
    Write-Host '============================================'
    Write-Log 'All login attempts failed.' 'ERROR'
    return $false
}

# ============================================================
# Main
# ============================================================

try {
    Write-Log '============================================' 'INFO'
    Write-Log 'CampusNet AutoConnect Started.' 'INFO'

    if ($Watch) {
        Write-Log 'Monitoring mode active.' 'INFO'
        while ($true) {
            try {
                if (-not (Test-Internet)) {
                    Write-Log 'Connection dropped! Re-authenticating...' 'WARN'
                    [void](Connect-CampusNet)
                }
            }
            catch {
                Write-Log ("Watch Exception: {0}" -f $_.Exception.Message) 'ERROR'
            }
            Start-Sleep -Seconds $script:WatchIntervalSeconds
        }
    }
    else {
        $result = Connect-CampusNet
        if ($result) { exit 0 } else { exit 1 }
    }
}
catch {
    Write-Log ("Unhandled Exception: {0}" -f $_.Exception.Message) 'ERROR'
    exit 1
}
