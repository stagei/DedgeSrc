#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Collects a full DedgeAuth authentication and navigation diagnostic snapshot.
.DESCRIPTION
    Gathers server logs, deployed file versions, API endpoint health, database
    state, IIS deployment status, and end-to-end auth flow tests.  Outputs a
    single markdown report that gives an AI agent (or a human) the complete
    picture needed to diagnose login / app-link / redirect issues.

    Designed to be called automatically by a Cursor rule whenever an auth or
    navigation error is reported.
.PARAMETER BaseUrl
    The base URL of the DedgeAuth server.  Default: http://localhost
.PARAMETER ServerName
    UNC-accessible server name for remote log/file checks.
    Default: dedge-server
.PARAMETER DbServer
    PostgreSQL server for DedgeAuth database.  Default: t-no1fkxtst-db
.PARAMETER DbPort
    PostgreSQL port.  Default: 8432
.PARAMETER TestEmail
    Email for the test login.  Default: test.service@Dedge.no
.PARAMETER TestPassword
    Password for the test login.  Default: TestPass123!
.PARAMETER OutputPath
    Where to write the markdown report.  Default: $env:TEMP\DedgeAuth-Diagnostics.md
.EXAMPLE
    .\Get-DedgeAuthDiagnostics.ps1
    .\Get-DedgeAuthDiagnostics.ps1 -BaseUrl http://dedge-server -ServerName dedge-server
#>
param(
    [string]$BaseUrl     = 'http://localhost',
    [string]$ServerName  = 'dedge-server',
    [string]$DbServer    = 't-no1fkxtst-db',
    [int]   $DbPort      = 8432,
    [string]$TestEmail   = 'test.service@Dedge.no',
    [string]$TestPassword = 'TestPass123!',
    [string]$OutputPath  = (Join-Path $env:TEMP 'DedgeAuth-Diagnostics.md')
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

$DedgeAuthBase = "$BaseUrl/DedgeAuth"
$today      = Get-Date -Format 'yyyyMMdd'
$timestamp  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$report     = [System.Text.StringBuilder]::new()

function Out-Section([string]$title) {
    [void]$report.AppendLine("`n## $title`n")
}
function Out-Line([string]$text) {
    [void]$report.AppendLine($text)
}
function Out-Table([string[]]$headers, [object[]]$rows) {
    $sep = ($headers | ForEach-Object { '---' }) -join ' | '
    Out-Line ("| " + ($headers -join ' | ') + " |")
    Out-Line ("| $sep |")
    foreach ($r in $rows) { Out-Line ("| " + ($r -join ' | ') + " |") }
}
function Safe-Invoke {
    param([string]$Uri, [string]$Method = 'GET', [hashtable]$Headers = @{},
          [string]$Body, [string]$ContentType, [int]$MaxRedir = 5)
    $splat = @{ Uri = $Uri; Method = $Method; UseBasicParsing = $true;
                MaximumRedirection = $MaxRedir; ErrorAction = 'Stop' }
    if ($Headers.Count) { $splat.Headers = $Headers }
    if ($Body)          { $splat.Body = $Body }
    if ($ContentType)   { $splat.ContentType = $ContentType }
    try   { Invoke-WebRequest @splat }
    catch { $_ }
}

Out-Line "# DedgeAuth Diagnostics Report"
Out-Line "**Generated:** $timestamp"
Out-Line "**Base URL:** $BaseUrl"
Out-Line "**Server:** $ServerName"

# ──────────────────────────────────────────────
Out-Section '1. Server Log Tail (last 60 lines)'
# ──────────────────────────────────────────────
$logSources = @(
    @{ Label = 'DedgeAuth.Api (local)';  Path = "C:\opt\data\DedgeAuth.Api\DedgeAuth-$($today).log" },
    @{ Label = "DedgeAuth.Api ($ServerName)"; Path = "\\$ServerName\opt\data\DedgeAuth.Api\DedgeAuth-$($today).log" }
)
foreach ($src in $logSources) {
    Out-Line "### $($src.Label)"
    Out-Line "Path: ``$($src.Path)``"
    if (Test-Path $src.Path) {
        $localCopy = Join-Path $env:TEMP "diag_$(Split-Path $src.Path -Leaf)"
        try {
            Copy-Item $src.Path $localCopy -Force -ErrorAction Stop
            $tail = Get-Content $localCopy -Tail 60 -ErrorAction Stop
            $errors = $tail | Where-Object { $_ -match '\|ERROR\||\|WARN\|' }
            Out-Line "``````"
            $tail | ForEach-Object { Out-Line $_ }
            Out-Line "``````"
            if ($errors) {
                Out-Line "`n**Errors/Warnings found:** $($errors.Count)"
            } else {
                Out-Line "`n**No errors or warnings in tail.**"
            }
        } catch {
            Out-Line "``Copy failed: $($_.Exception.Message)``"
        }
    } else {
        Out-Line "*File not found.*"
    }
}

# ──────────────────────────────────────────────
Out-Section '2. Deployed File Versions'
# ──────────────────────────────────────────────
$fileSets = @(
    @{ Label = 'Staging share';  Base = "\\$ServerName\DedgeCommon\Software\DedgeWinApps\DedgeAuth" },
    @{ Label = "IIS install ($ServerName)"; Base = "\\$ServerName\opt\DedgeWinApps\DedgeAuth" },
    @{ Label = 'Local IIS';     Base = "C:\opt\DedgeWinApps\DedgeAuth" }
)
$checkFiles = @('DedgeAuth.Api.dll', 'DedgeAuth.Services.dll', 'DedgeAuth.Client.dll',
                'DedgeAuth.Core.dll', 'DedgeAuth.Data.dll', 'wwwroot\login.html',
                'wwwroot\admin.html', 'appsettings.json', 'web.config')

foreach ($fs in $fileSets) {
    Out-Line "### $($fs.Label)"
    Out-Line "Base: ``$($fs.Base)``"
    $rows = @()
    foreach ($f in $checkFiles) {
        $fp = Join-Path $fs.Base $f
        if (Test-Path $fp) {
            $fi = Get-Item $fp
            $ver = ''
            if ($f -like '*.dll') {
                try { $ver = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($fp).FileVersion } catch {}
            }
            $rows += ,@($f, $fi.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'), $fi.Length, $ver)
        } else {
            $rows += ,@($f, 'NOT FOUND', '', '')
        }
    }
    Out-Table @('File','LastWriteTime','Size','Version') $rows
}

# ──────────────────────────────────────────────
Out-Section '3. API Endpoint Health'
# ──────────────────────────────────────────────
$endpoints = @(
    @{ Label = 'Health';         Url = "$DedgeAuthBase/health";            Method = 'GET';  Auth = $false },
    @{ Label = 'Scalar docs';    Url = "$DedgeAuthBase/scalar/v1";         Method = 'GET';  Auth = $false },
    @{ Label = 'Windows probe';  Url = "$DedgeAuthBase/api/auth/windows-probe"; Method = 'GET'; Auth = $false },
    @{ Label = 'Login (POST)';   Url = "$DedgeAuthBase/api/auth/login";    Method = 'POST'; Auth = $false;
       Body = (@{Email=$TestEmail;Password=$TestPassword} | ConvertTo-Json); CT = 'application/json' },
    @{ Label = 'Me (no auth)';   Url = "$DedgeAuthBase/api/auth/me";       Method = 'GET';  Auth = $false },
    @{ Label = 'Apps list';      Url = "$DedgeAuthBase/api/apps";          Method = 'GET';  Auth = $true  },
    @{ Label = 'Apps tree';      Url = "$DedgeAuthBase/api/apps/tree";     Method = 'GET';  Auth = $true  },
    @{ Label = 'Redirect (no cookie)'; Url = "$DedgeAuthBase/api/auth/redirect?returnUrl=http://test/"; Method = 'GET'; Auth = $false; MaxRedir = 0 },
    @{ Label = 'Validate';       Url = "$DedgeAuthBase/api/auth/validate"; Method = 'GET';  Auth = $true  }
)

$jwt = $null
$rows = @()
foreach ($ep in $endpoints) {
    $headers = @{}
    if ($ep.Auth -and $jwt) { $headers['Authorization'] = "Bearer $jwt" }
    $splat = @{ Uri = $ep.Url; Method = $ep.Method; Headers = $headers; MaxRedir = 5 }
    if ($ep.MaxRedir -ne $null -and $ep.MaxRedir -eq 0) { $splat.MaxRedir = 0 }
    if ($ep.Body) { $splat.Body = $ep.Body; $splat.ContentType = $ep.CT }

    $status = ''; $detail = ''
    try {
        $resp = Invoke-WebRequest -Uri $splat.Uri -Method $splat.Method -Headers $headers `
                    -Body $ep.Body -ContentType $ep.CT -MaximumRedirection ($ep.MaxRedir ?? 5) `
                    -UseBasicParsing -ErrorAction Stop
        $status = "$($resp.StatusCode)"
        if ($ep.Label -eq 'Login (POST)' -and $resp.StatusCode -eq 200) {
            $loginData = $resp.Content | ConvertFrom-Json
            if ($loginData.accessToken) {
                $jwt = $loginData.accessToken
                $detail = "JWT obtained (len=$($jwt.Length))"
            } else {
                $detail = "No accessToken in response"
            }
        } elseif ($ep.Label -eq 'Me (no auth)') {
            $detail = 'Expected 401'
        } elseif ($ep.Label -match 'Apps') {
            try { $d = $resp.Content | ConvertFrom-Json; $detail = "items=$($d.Count ?? $d.tree.Count ?? '?')" } catch { $detail = "len=$($resp.Content.Length)" }
        } else {
            $detail = "len=$($resp.Content.Length)"
        }
    } catch {
        $ex = $_.Exception
        if ($ex.Response) {
            $status = "$([int]$ex.Response.StatusCode)"
            $loc = $ex.Response.Headers.Location
            if ($loc) { $detail = "Location: $loc" } else { $detail = $ex.Message.Substring(0, [Math]::Min(80, $ex.Message.Length)) }
        } else {
            $status = 'FAIL'
            $detail = $ex.Message.Substring(0, [Math]::Min(80, $ex.Message.Length))
        }
    }
    $rows += ,@($ep.Label, $ep.Method, $status, $detail)
}
Out-Table @('Endpoint','Method','Status','Detail') $rows

# ──────────────────────────────────────────────
Out-Section '4. Auth Flow End-to-End'
# ──────────────────────────────────────────────
if ($jwt) {
    Out-Line "### 4a. create-code"
    try {
        $codeResp = Invoke-WebRequest -Uri "$DedgeAuthBase/api/auth/create-code" -Method POST `
                      -Headers @{Authorization="Bearer $jwt"} -UseBasicParsing -ErrorAction Stop
        $codeData = $codeResp.Content | ConvertFrom-Json
        $code = $codeData.code
        Out-Line "- Status: **$($codeResp.StatusCode)**"
        Out-Line "- Code: ``$($code.Substring(0, [Math]::Min(24, $code.Length)))...``"
    } catch {
        Out-Line "- **FAILED:** $($_.Exception.Message)"
        $code = $null
    }

    Out-Line "`n### 4b. /api/auth/me"
    try {
        $meResp = Invoke-WebRequest -Uri "$DedgeAuthBase/api/auth/me" -Method GET `
                    -Headers @{Authorization="Bearer $jwt"} -UseBasicParsing -ErrorAction Stop
        $me = $meResp.Content | ConvertFrom-Json
        Out-Line "- Status: **$($meResp.StatusCode)**"
        Out-Line "- User: ``$($me.email)`` | Access: ``$($me.globalAccessLevel)``"
        Out-Line "- Permissions: ``$(($me.appPermissions.PSObject.Properties.Name -join ', '))``"
    } catch {
        Out-Line "- **FAILED:** $($_.Exception.Message)"
    }

    Out-Line "`n### 4c. Consumer app code exchange"
    $testApps = @(
        @{ Name = 'DocView';      Url = "$BaseUrl/DocView/" },
        @{ Name = 'GenericLogHandler'; Url = "$BaseUrl/GenericLogHandler/" },
        @{ Name = 'ServerMonitorDashboard'; Url = "$BaseUrl/ServerMonitorDashboard/" },
        @{ Name = 'AutoDocJson';  Url = "$BaseUrl/AutoDocJson/" },
        @{ Name = 'AgriNxt.GrainDryingDeduction'; Url = "$BaseUrl/AgriNxt.GrainDryingDeduction/" }
    )
    $rows = @()
    foreach ($app in $testApps) {
        try {
            $freshCode = Invoke-WebRequest -Uri "$DedgeAuthBase/api/auth/create-code" -Method POST `
                           -Headers @{Authorization="Bearer $jwt"} -UseBasicParsing -ErrorAction Stop
            $fc = ($freshCode.Content | ConvertFrom-Json).code

            $appResp = Invoke-WebRequest -Uri "$($app.Url)?code=$fc" -MaximumRedirection 0 `
                         -UseBasicParsing -ErrorAction Stop
            $rows += ,@($app.Name, "$($appResp.StatusCode)", '')
        } catch {
            $ex = $_.Exception
            if ($ex.Response) {
                $loc = try { $ex.Response.Headers.Location } catch { '' }
                $rows += ,@($app.Name, "$([int]$ex.Response.StatusCode)", "Location: $loc")
            } else {
                $rows += ,@($app.Name, 'FAIL', $ex.Message.Substring(0, [Math]::Min(60, $ex.Message.Length)))
            }
        }
    }
    Out-Table @('App','Status','Detail') $rows
} else {
    Out-Line "*Login failed — cannot test auth flow.*"
}

# ──────────────────────────────────────────────
Out-Section '5. Refresh Token Cookie Test'
# ──────────────────────────────────────────────
Out-Line "### Login with session to get Set-Cookie headers"
try {
    $session = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
    $loginResp = Invoke-WebRequest -Uri "$DedgeAuthBase/api/auth/login" -Method POST `
                   -Body (@{Email=$TestEmail;Password=$TestPassword} | ConvertTo-Json) `
                   -ContentType 'application/json' -SessionVariable 'sess' -UseBasicParsing -ErrorAction Stop
    $setCookies = $loginResp.Headers['Set-Cookie']
    if ($setCookies) {
        Out-Line "``````"
        foreach ($c in $setCookies) { Out-Line $c }
        Out-Line "``````"
        $hasCookiePath = $setCookies | Where-Object { $_ -match 'path=/DedgeAuth' -or $_ -match 'Path=/DedgeAuth' }
        $hasSameSite   = $setCookies | Where-Object { $_ -match 'SameSite=Lax' -or $_ -match 'samesite=lax' }
        Out-Line "- Cookie Path set to /DedgeAuth: **$(if ($hasCookiePath) {'YES'} else {'NO — PROBLEM'})**"
        Out-Line "- SameSite=Lax: **$(if ($hasSameSite) {'YES'} else {'NO — PROBLEM'})**"
    } else {
        Out-Line "*No Set-Cookie headers returned — **PROBLEM***"
    }
} catch {
    Out-Line "- **FAILED:** $($_.Exception.Message)"
}

# ──────────────────────────────────────────────
Out-Section '6. Database State (apps + tenants)'
# ──────────────────────────────────────────────
Out-Line "*Requires the db2-query / PostgreSQL MCP or psql. Skipped in script — data below from API.*"
if ($jwt) {
    try {
        $appsResp = Invoke-WebRequest -Uri "$DedgeAuthBase/api/apps" -Headers @{Authorization="Bearer $jwt"} -UseBasicParsing -ErrorAction Stop
        $apps = $appsResp.Content | ConvertFrom-Json
        $rows = @()
        foreach ($a in $apps) {
            $rows += ,@($a.appId, $a.displayName, $a.baseUrl, $a.isActive)
        }
        Out-Table @('AppId','DisplayName','BaseUrl','Active') $rows
    } catch {
        Out-Line "*Could not fetch apps: $($_.Exception.Message)*"
    }
}

# ──────────────────────────────────────────────
Out-Section '7. IIS App Pool & Process State'
# ──────────────────────────────────────────────
$pools = @('DedgeAuth','DocView','GenericLogHandler','ServerMonitorDashboard','AutoDocJson','AgriNxt.GrainDryingDeduction')
try {
    Import-Module WebAdministration -SkipEditionCheck -ErrorAction Stop
    $rows = @()
    foreach ($p in $pools) {
        try {
            $pool = Get-Item "IIS:\AppPools\$p" -ErrorAction Stop
            $rows += ,@($p, $pool.state, $pool.managedRuntimeVersion, $pool.processModel.userName)
        } catch {
            $rows += ,@($p, 'NOT FOUND', '', '')
        }
    }
    Out-Table @('Pool','State','Runtime','Identity') $rows
} catch {
    Out-Line "*WebAdministration module not available (not running on IIS server).*"
    Out-Line "Check remotely: processes listening on DedgeAuth port 8100"
    try {
        $listeners = netstat -ano | Select-String ':8100'
        if ($listeners) {
            Out-Line "``````"
            $listeners | ForEach-Object { Out-Line $_.Line }
            Out-Line "``````"
        } else {
            Out-Line "*No listener on port 8100 locally.*"
        }
    } catch {}
}

# ──────────────────────────────────────────────
Out-Section '8. login.html Key Functions Presence'
# ──────────────────────────────────────────────
$loginFiles = @(
    "$BaseUrl/DedgeAuth/login.html"
)
foreach ($url in $loginFiles) {
    $label = if ($url -match 'localhost') { 'local' } else { 'server' }
    Out-Line "### login.html ($label)"
    try {
        $html = (Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop).Content
        $checks = [ordered]@{
            'openApp()'           = $html -match 'function openApp'
            'storeAccessToken()'  = $html -match 'function storeAccessToken'
            'clearAccessToken()'  = $html -match 'function clearAccessToken'
            'tryLocalTokenRedirect()' = $html -match 'function tryLocalTokenRedirect'
            'tryAutoKerberos()'   = $html -match 'tryAutoKerberos'
            'create-code call'    = $html -match 'api/auth/create-code'
            'redirect fallback'   = $html -match 'api/auth/redirect'
            'DedgeAuth_jwt cookie'   = $html -match 'DedgeAuth_jwt'
            'same-tab nav (no _blank)' = -not ($html -match 'target="_blank".*openApp' -or $html -match "target='_blank'.*openApp")
            'href=javascript:void(0)' = $html -match 'javascript:void\(0\)'
        }
        $rows = @()
        foreach ($k in $checks.Keys) {
            $v = if ($checks[$k]) { 'YES' } else { 'NO — PROBLEM' }
            $rows += ,@($k, $v)
        }
        Out-Table @('Check','Present') $rows
    } catch {
        Out-Line "*Could not fetch: $($_.Exception.Message)*"
    }
}

# ──────────────────────────────────────────────
Out-Section '9. Staging vs IIS Install File Comparison'
# ──────────────────────────────────────────────
$stagingBase = "\\$ServerName\DedgeCommon\Software\DedgeWinApps\DedgeAuth"
$iisBase     = "\\$ServerName\opt\DedgeWinApps\DedgeAuth"
if ((Test-Path $stagingBase) -and (Test-Path $iisBase)) {
    $criticalFiles = @('DedgeAuth.Api.dll','DedgeAuth.Services.dll','DedgeAuth.Core.dll',
                       'DedgeAuth.Data.dll','DedgeAuth.Client.dll','wwwroot\login.html')
    $rows = @()
    foreach ($f in $criticalFiles) {
        $sf = Join-Path $stagingBase $f
        $if = Join-Path $iisBase $f
        $sTime = if (Test-Path $sf) { (Get-Item $sf).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') } else { 'MISSING' }
        $iTime = if (Test-Path $if) { (Get-Item $if).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') } else { 'MISSING' }
        $match = if ($sTime -eq $iTime) { 'MATCH' } elseif ($sTime -eq 'MISSING' -or $iTime -eq 'MISSING') { 'MISSING' } else { 'STALE — needs IIS-DeployApp' }
        $rows += ,@($f, $sTime, $iTime, $match)
    }
    Out-Table @('File','Staging','IIS Install','Status') $rows
} else {
    Out-Line "*Cannot access staging ($stagingBase) or IIS ($iisBase) paths.*"
}

# ──────────────────────────────────────────────
Out-Section '10. Summary & Recommendations'
# ──────────────────────────────────────────────
Out-Line "Review sections above for any **PROBLEM** or **FAIL** markers."
Out-Line ""
Out-Line "Common fixes:"
Out-Line "- **Stale IIS files**: Run ``IIS-DeployApp.ps1 -SiteName DedgeAuth``"
Out-Line "- **Missing openApp()**: Republish login.html via ``Build-And-Publish.ps1``"
Out-Line "- **Cookie path wrong**: Check ``SetRefreshTokenCookie`` in ``AuthController.cs``"
Out-Line "- **create-code 401**: JWT expired; check ``AccessTokenExpirationMinutes`` in ``appsettings.json``"
Out-Line "- **Consumer app 401 on code exchange**: Code already used or expired (5 min lifetime)"
Out-Line "- **Redirect loop**: Check ``DedgeAuthRedirectMiddleware`` skips ``/api/`` and static files"

# Write report
$reportText = $report.ToString()
$reportText | Out-File $OutputPath -Encoding utf8 -Force
Write-Host "`n=========================================="
Write-Host "  DedgeAuth Diagnostics Report"
Write-Host "  Output: $OutputPath"
Write-Host "  Sections: 10"
Write-Host "==========================================`n"
Write-Host $reportText

return $OutputPath
