<#
.SYNOPSIS
    Discovers all IIS virtual applications and tests their API endpoints.

.DESCRIPTION
    Dynamic IIS application discovery and API endpoint testing:

    1. Enumerates IIS virtual applications under Default Web Site
    2. For each ASP.NET Core app, fetches the OpenAPI spec to discover endpoints
    3. Tests all safe (GET) endpoints and selected health/status endpoints
    4. Reports per-app and overall pass/warn/fail summary

    Endpoints returning 401/403 are reported as WARN (auth-protected, working correctly).
    Endpoints returning 5xx are reported as FAIL.

    Optionally accepts a JWT token to test authenticated endpoints.

.PARAMETER BaseUrl
    Base URL of the IIS server. Default: http://localhost

.PARAMETER ParentSite
    IIS parent site name. Default: Default Web Site

.PARAMETER Token
    Optional JWT bearer token for authenticated endpoint testing.

.PARAMETER IncludeUnsafe
    Also test POST/PUT/DELETE endpoints with empty bodies (dry-run style).
    Default: false (only GET endpoints are tested).

.PARAMETER AppFilter
    Optional app name filter (wildcard). E.g. "DedgeAuth" or "Generic*"

.PARAMETER TimeoutSeconds
    HTTP request timeout per endpoint. Default: 10

.EXAMPLE
    .\Test-AllApps.ps1
    Discover and test all apps with GET endpoints only.

.EXAMPLE
    .\Test-AllApps.ps1 -Token "eyJhbG..."
    Test with authentication (unlocks protected endpoints).

.EXAMPLE
    .\Test-AllApps.ps1 -AppFilter "DedgeAuth"
    Test only DedgeAuth endpoints.
#>

param(
    [string]$BaseUrl = "http://localhost",

    [string]$ParentSite = "Default Web Site",

    [string]$Token = "",

    [switch]$IncludeUnsafe,

    [string]$AppFilter = "*",

    [int]$TimeoutSeconds = 10
)

$ErrorActionPreference = "Continue"

Import-Module GlobalFunctions -Force

try {
    Import-Module IIS-Handler -Force -ErrorAction Stop
    Set-OverrideAppDataFolder -Path $(Join-Path $env:OptPath "data" "IIS-DeployApp")
    $hasIISHandler = $true
} catch {
    $hasIISHandler = $false
}

Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_STARTED

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

# Endpoints with path parameters that need substitution -- skip by default
$skipPatterns = @(
    '\{id\}', '\{userId\}', '\{appId\}', '\{domain\}', '\{path\}',
    '\{serverName\}', '\{fileName\}', '\{jobName\}', '\{action\}'
)

# Known safe GET endpoints to always test (even without OpenAPI discovery)
$fallbackEndpoints = @(
    @{ Path = "/health";       Method = "GET"; Description = "Health check" },
    @{ Path = "/scalar/v1";    Method = "GET"; Description = "Scalar API docs" },
    @{ Path = "/api/IsAlive";  Method = "GET"; Description = "IsAlive check" }
)

# ═══════════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

function Get-SolutionHint {
    <#
    .SYNOPSIS
        Returns actionable remediation hints based on HTTP status code and error context.
    #>
    param(
        [string]$AppName,
        [int]$StatusCode,
        [string]$ErrorMessage = ""
    )

    $hints = @()
    $logPath = "\\$($env:COMPUTERNAME)\opt\DedgeWinApps\$($AppName)\logs"

    switch ($StatusCode) {
        0 {
            if ($ErrorMessage -match "refused|No connection") {
                $hints += "Parent site 'Default Web Site' may not be running."
                $hints += "  Fix: .\IIS-DeployApp.ps1 -SiteName DefaultWebSite"
                $hints += "  Alt: appcmd start site ""Default Web Site"""
            }
            else {
                $hints += "App pool may be stopped or the app is not deployed."
                $hints += "  Fix: appcmd start apppool ""$($AppName)"""
                $hints += "  Alt: .\IIS-DeployApp.ps1 -SiteName $($AppName)"
            }
        }
        500 {
            $hints += "Internal server error -- check application startup logs."
            $hints += "  Logs: $logPath\stdout*"
            $hints += "  Diag: Test-IISSite -SiteName $($AppName)"
            $hints += "  Fix:  .\IIS-DeployApp.ps1 -SiteName $($AppName)"
        }
        { $_ -in @(502, 503) } {
            $hints += "App pool stopped or crashed (may be rapid-fail protected)."
            $hints += "  Fix: appcmd start apppool ""$($AppName)"""
            $hints += "  Alt: appcmd recycle apppool ""$($AppName)"""
            $hints += "  Logs: $logPath\stdout*"
        }
        404 {
            $hints += "Endpoint not found -- app may be deployed but route is missing."
            $hints += "  Check: Is the app's OpenAPI spec accessible?"
        }
        default {
            if ($StatusCode -ge 500) {
                $hints += "Server error (HTTP $($StatusCode))."
                $hints += "  Logs: $logPath\stdout*"
                $hints += "  Diag: Test-IISSite -SiteName $($AppName)"
            }
        }
    }

    return $hints
}

function Get-SharedAppPools {
    <#
    .SYNOPSIS
        Detects app pools that host more than one app (causes HTTP 500.35 for ASP.NET Core).
    .OUTPUTS
        Array of [PSCustomObject]@{ Pool = string; Apps = string[] } for pools with multiple apps.
    #>
    $shared = @()
    $appcmd = "$env:SystemRoot\System32\inetsrv\appcmd.exe"
    if (-not (Test-Path $appcmd)) { return $shared }
    try {
        $output = & $appcmd list app 2>&1
        if ($LASTEXITCODE -ne 0) { return $shared }
        # Parse: APP "Default Web Site/AppName" (applicationPool:PoolName)
        $poolToApps = @{}
        foreach ($line in $output) {
            if ($line -match '"[^"]+/([^"/]+)"\s+\(applicationPool:([^)]+)\)') {
                $appName = $matches[1]
                $poolName = $matches[2]
                if (-not $poolToApps[$poolName]) { $poolToApps[$poolName] = [System.Collections.ArrayList]@() }
                $null = $poolToApps[$poolName].Add($appName)
            }
        }
        foreach ($pool in $poolToApps.Keys) {
            $apps = @($poolToApps[$pool])
            if ($apps.Count -gt 1) {
                $shared += [PSCustomObject]@{ Pool = $pool; Apps = $apps }
            }
        }
    } catch { }
    return $shared
}

function Get-IISVirtualApps {
    <#
    .SYNOPSIS
        Discovers IIS virtual applications. Tries appcmd (needs admin), falls back to HTTP probing.
    #>
    param([string]$ParentSiteName)

    $apps = @()

    # Try appcmd.exe (requires admin)
    $appcmd = "$env:SystemRoot\System32\inetsrv\appcmd.exe"
    if (Test-Path $appcmd) {
        try {
            $output = & $appcmd list app 2>&1
            if ($LASTEXITCODE -eq 0) {
                foreach ($line in $output) {
                    # Format: APP "Default Web Site/DedgeAuth" (applicationPool:DedgeAuth)
                    # Regex: match virtual app path and pool name
                    #   "Default Web Site/(\S+)"  -> capture app name after site/
                    #   applicationPool:(\S+)     -> capture pool name
                    #   The (?!/) negative lookahead excludes the root app "Default Web Site/"
                    if ($line -match '"[^"]+/([^"/]+)"\s+\(applicationPool:([^)]+)\)') {
                        $appName = $matches[1]
                        $poolName = $matches[2]
                        $apps += [PSCustomObject]@{
                            Name     = $appName
                            Pool     = $poolName
                            BasePath = "/$appName"
                        }
                    }
                }
                if ($apps.Count -gt 0) {
                    Write-LogMessage "Discovered $($apps.Count) virtual app(s) via appcmd" -Level INFO
                    return $apps
                }
            }
        } catch { }
    }

    # Fallback: try deploy profile templates
    $templatesPath = Join-Path $PSScriptRoot "templates"
    if (Test-Path $templatesPath) {
        $templateFiles = Get-ChildItem -Path $templatesPath -Filter "*.deploy.json" -File
        foreach ($f in $templateFiles) {
            $json = Get-Content $f.FullName -Raw | ConvertFrom-Json
            if ($json.IsRootSiteProfile -eq $true) { continue }
            $apps += [PSCustomObject]@{
                Name     = $json.SiteName
                Pool     = $json.AppPoolName
                BasePath = $json.VirtualPath
            }
        }
        if ($apps.Count -gt 0) {
            Write-LogMessage "Discovered $($apps.Count) app(s) via deploy templates (appcmd unavailable -- run as admin for full discovery)" -Level WARN
        }
    }

    # Last fallback: probe known app names
    if ($apps.Count -eq 0) {
        Write-LogMessage "No IIS discovery available. Probing known app paths..." -Level WARN
        $knownApps = @("DedgeAuth", "DocView", "GenericLogHandler", "ServerMonitorDashboard", "AutoDoc", "AutoDocJson")
        foreach ($name in $knownApps) {
            $apps += [PSCustomObject]@{
                Name     = $name
                Pool     = $name
                BasePath = "/$name"
            }
        }
    }

    return $apps
}

function Get-OpenApiEndpoints {
    <#
    .SYNOPSIS
        Fetches the OpenAPI spec for an app and extracts all endpoint paths and methods.
    #>
    param(
        [string]$AppBaseUrl
    )

    $endpoints = @()
    $specUrls = @(
        "$AppBaseUrl/openapi/v1.json",
        "$AppBaseUrl/swagger/v1/swagger.json"
    )

    foreach ($specUrl in $specUrls) {
        try {
            $spec = Invoke-RestMethod -Uri $specUrl -TimeoutSec $TimeoutSeconds -ErrorAction Stop
            if ($spec.paths) {
                $pathProps = if ($spec.paths -is [PSCustomObject]) {
                    $spec.paths.PSObject.Properties
                } else {
                    @()
                }

                foreach ($pathProp in $pathProps) {
                    $path = $pathProp.Name
                    $methods = $pathProp.Value.PSObject.Properties | Where-Object {
                        $_.Name -in @('get', 'post', 'put', 'delete', 'patch', 'head', 'options')
                    }
                    foreach ($m in $methods) {
                        $summary = ""
                        if ($m.Value.summary) { $summary = $m.Value.summary }
                        $tag = ""
                        if ($m.Value.tags -and $m.Value.tags.Count -gt 0) { $tag = $m.Value.tags[0] }
                        $endpoints += [PSCustomObject]@{
                            Path        = $path
                            Method      = $m.Name.ToUpper()
                            Summary     = $summary
                            Tag         = $tag
                            HasParams   = $path -match '\{[^}]+\}'
                        }
                    }
                }
                Write-LogMessage "  OpenAPI: $($endpoints.Count) endpoint(s) from $specUrl" -Level INFO
                return $endpoints
            }
        } catch {
            # Try next spec URL
        }
    }

    return $endpoints
}

function Test-Endpoint {
    <#
    .SYNOPSIS
        Tests a single HTTP endpoint using HttpClient with a hard cancellation timeout.
        This handles SSE/streaming endpoints that Invoke-WebRequest would hang on.
    #>
    param(
        [string]$Url,
        [string]$Method = "GET",
        [string]$BearerToken = "",
        [int]$Timeout = 10
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $cts = [System.Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds($Timeout))
    try {
        $handler = [System.Net.Http.HttpClientHandler]::new()
        $client = [System.Net.Http.HttpClient]::new($handler)
        $client.Timeout = [TimeSpan]::FromSeconds($Timeout)

        if ($BearerToken) {
            $client.DefaultRequestHeaders.Authorization =
                [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $BearerToken)
        }

        $request = [System.Net.Http.HttpRequestMessage]::new(
            [System.Net.Http.HttpMethod]::new($Method), $Url
        )

        if ($Method -ne "GET") {
            $request.Content = [System.Net.Http.StringContent]::new(
                "{}", [System.Text.Encoding]::UTF8, "application/json"
            )
        }

        # ResponseHeadersRead returns as soon as headers arrive (doesn't wait for body)
        $responseTask = $client.SendAsync(
            $request,
            [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead,
            $cts.Token
        )
        $response = $responseTask.GetAwaiter().GetResult()
        $stopwatch.Stop()

        $statusCode = [int]$response.StatusCode
        $status = if ($statusCode -ge 200 -and $statusCode -lt 300) { "PASS" }
                  elseif ($statusCode -in @(401, 403)) { "AUTH" }
                  elseif ($statusCode -eq 400) { "PARAM" }
                  elseif ($statusCode -eq 404) { "NOTFOUND" }
                  elseif ($statusCode -eq 405) { "METHODNA" }
                  else { "FAIL" }

        return [PSCustomObject]@{
            StatusCode = $statusCode
            Status     = $status
            Duration   = $stopwatch.ElapsedMilliseconds
            Error      = ""
        }
    } catch {
        $stopwatch.Stop()
        $errMsg = $_.Exception.InnerException?.Message ?? $_.Exception.Message
        $isTimeout = $errMsg -match 'cancel|timeout|TaskCanceled'

        return [PSCustomObject]@{
            StatusCode = 0
            Status     = if ($isTimeout) { "TIMEOUT" } else { "FAIL" }
            Duration   = $stopwatch.ElapsedMilliseconds
            Error      = $errMsg
        }
    } finally {
        $cts.Dispose()
        if ($client) { $client.Dispose() }
    }
}

function Write-TestResult {
    param(
        [string]$Method,
        [string]$Path,
        [PSCustomObject]$Result,
        [string]$Summary = ""
    )

    $icon = switch ($Result.Status) {
        "PASS"     { "PASS" }
        "AUTH"     { "AUTH" }
        "PARAM"    { "PARAM" }
        "TIMEOUT"  { "TIME" }
        "NOTFOUND" { "SKIP" }
        "METHODNA" { "SKIP" }
        default    { "FAIL" }
    }

    $level = switch ($Result.Status) {
        "PASS"     { "INFO" }
        "AUTH"     { "WARN" }
        "PARAM"    { "WARN" }
        "TIMEOUT"  { "WARN" }
        "NOTFOUND" { "INFO" }
        "METHODNA" { "INFO" }
        default    { "ERROR" }
    }

    $duration = "$($Result.Duration)ms"
    $desc = if ($Summary) { " -- $Summary" } else { "" }
    $statusText = switch ($Result.Status) {
        "TIMEOUT" { "TIMEOUT ($($TimeoutSeconds)s)" }
        default   { if ($Result.StatusCode -gt 0) { "HTTP $($Result.StatusCode)" } else { "ERROR" } }
    }

    Write-LogMessage "  [$icon] $Method $Path -- $statusText ($duration)$desc" -Level $level
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  IIS Application API Endpoint Tester" -ForegroundColor Cyan
Write-Host "  Base URL:  $BaseUrl" -ForegroundColor Cyan
Write-Host "  Computer:  $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host "  Date:      $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "  Auth:      $(if ($Token) { 'JWT token provided' } else { 'No token (auth endpoints will show 401)' })" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ─── Discover apps ────────────────────────────────────────────────────────────

$allApps = Get-IISVirtualApps -ParentSiteName $ParentSite
$filteredApps = $allApps | Where-Object { $_.Name -like $AppFilter } | Sort-Object Name

if ($filteredApps.Count -eq 0) {
    Write-LogMessage "No apps found matching filter '$AppFilter'" -Level ERROR
    exit 1
}

Write-LogMessage "Testing $($filteredApps.Count) app(s): $($filteredApps.Name -join ', ')" -Level INFO
Write-Host ""

# ─── App pool sharing check (HTTP 500.35) ───────────────────────────────────────
# ASP.NET Core InProcess does not support multiple apps in the same app pool.
$sharedPools = Get-SharedAppPools
if ($sharedPools.Count -gt 0) {
    Write-Host "  App pool sharing (HTTP 500.35)" -ForegroundColor Red
    Write-Host "  ASP.NET Core does not support multiple apps in the same app pool." -ForegroundColor Red
    Write-Host "  The following pool(s) have more than one app; requests will return HTTP 500.35:" -ForegroundColor Yellow
    Write-Host ""
    foreach ($sp in $sharedPools) {
        Write-Host "    Pool: $($sp.Pool)" -ForegroundColor Red
        Write-Host "    Apps: $($sp.Apps -join ', ')" -ForegroundColor Yellow
        Write-Host "    Fix:  Give each app its own pool. Redeploy with:" -ForegroundColor Gray
        foreach ($a in $sp.Apps) {
            Write-Host "      .\IIS-DeployApp.ps1 -SiteName $a" -ForegroundColor Gray
        }
        Write-Host ""
    }
    Write-Host "  See: Troubleshoot ASP.NET Core on Azure App Service and IIS (HTTP 500.35)" -ForegroundColor DarkGray
    Write-Host ""
}

# ─── Pre-flight: Check Default Web Site is reachable ─────────────────────────

$siteCheck = Test-Endpoint -Url "$BaseUrl/" -Timeout 5
if ($siteCheck.StatusCode -eq 0) {
    Write-Host ""
    Write-Host "  *** DEFAULT WEB SITE IS NOT REACHABLE ***" -ForegroundColor Red
    Write-Host "  All apps depend on 'Default Web Site' listening on port 80." -ForegroundColor Red
    Write-Host "  No app tests will succeed until this is resolved." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Possible causes:" -ForegroundColor Yellow
    Write-Host "    - Default Web Site is stopped or in 'Unknown' state" -ForegroundColor Gray
    Write-Host "    - Root '/' application is missing (site shows 'Unknown' in IIS Manager)" -ForegroundColor Gray
    Write-Host "    - IIS (W3SVC) service is not running" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Fixes (run on the server):" -ForegroundColor Yellow
    Write-Host "    1. .\IIS-DeployApp.ps1 -SiteName DefaultWebSite" -ForegroundColor Cyan
    Write-Host "    2. appcmd start site ""Default Web Site""" -ForegroundColor Cyan
    Write-Host "    3. iisreset && .\IIS-ReDeployAll.ps1" -ForegroundColor Cyan
    Write-Host ""
    Write-LogMessage "Default Web Site is unreachable at $($BaseUrl)/ -- all app tests will likely fail" -Level ERROR
    Write-Host ""
}

# ─── Test each app ────────────────────────────────────────────────────────────

$overallResults = @()
$appSummaries = @()

foreach ($app in $filteredApps) {
    $appBaseUrl = "$BaseUrl$($app.BasePath)"

    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkCyan
    Write-Host "  $($app.Name)  ($appBaseUrl)" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkCyan

    $appPass = 0; $appWarn = 0; $appFail = 0; $appSkip = 0

    # Step 1: Quick connectivity check
    $connResult = Test-Endpoint -Url "$appBaseUrl/" -Timeout $TimeoutSeconds
    if ($connResult.StatusCode -eq 0) {
        Write-LogMessage "  [FAIL] Cannot reach $appBaseUrl/ -- skipping" -Level ERROR
        $hints = Get-SolutionHint -AppName $app.Name -StatusCode 0 -ErrorMessage $connResult.Error
        foreach ($hint in $hints) {
            Write-Host "         $hint" -ForegroundColor DarkYellow
        }
        Write-Host ""
        $appFail++
        $overallResults += [PSCustomObject]@{
            App = $app.Name; Method = "GET"; Path = "/"; StatusCode = 0; Status = "FAIL"; Duration = $connResult.Duration
        }
        $appSummaries += [PSCustomObject]@{
            App = $app.Name; Pass = 0; Warn = 0; Fail = 1; Skip = 0; Total = 1; OpenApi = $false
        }
        continue
    }

    # Step 2: Discover endpoints via OpenAPI
    $endpoints = Get-OpenApiEndpoints -AppBaseUrl $appBaseUrl
    $hasOpenApi = $endpoints.Count -gt 0

    if (-not $hasOpenApi) {
        Write-LogMessage "  No OpenAPI spec found. Using fallback endpoints." -Level WARN
        $endpoints = $fallbackEndpoints | ForEach-Object {
            [PSCustomObject]@{
                Path      = $_.Path
                Method    = $_.Method
                Summary   = $_.Description
                Tag       = ""
                HasParams = $false
            }
        }
    }

    # Step 3: Filter endpoints
    $testEndpoints = @()
    foreach ($ep in $endpoints) {
        # Skip parameterized paths
        if ($ep.HasParams) {
            $appSkip++
            continue
        }

        # Only GET unless IncludeUnsafe
        if (-not $IncludeUnsafe -and $ep.Method -ne "GET") {
            $appSkip++
            continue
        }

        # Skip duplicate paths (OpenAPI can list same path under multiple methods)
        $testEndpoints += $ep
    }

    # Step 4: Deduplicate and sort
    $testEndpoints = $testEndpoints | Sort-Object Tag, Path, Method -Unique

    if ($testEndpoints.Count -eq 0 -and $hasOpenApi) {
        # All endpoints were parameterized or non-GET -- add fallbacks
        foreach ($fb in $fallbackEndpoints) {
            $testEndpoints += [PSCustomObject]@{
                Path = $fb.Path; Method = $fb.Method; Summary = $fb.Description; Tag = ""; HasParams = $false
            }
        }
    }

    Write-LogMessage "  Testing $($testEndpoints.Count) endpoint(s) ($appSkip skipped: parameterized/unsafe)" -Level INFO
    Write-Host ""

    # Step 5: Test endpoints grouped by tag
    $currentTag = ""
    foreach ($ep in $testEndpoints) {
        if ($ep.Tag -and $ep.Tag -ne $currentTag) {
            $currentTag = $ep.Tag
            Write-Host "    ── $currentTag ──" -ForegroundColor DarkGray
        }

        $url = "$appBaseUrl$($ep.Path)"
        $result = Test-Endpoint -Url $url -Method $ep.Method -BearerToken $Token -Timeout $TimeoutSeconds

        Write-TestResult -Method $ep.Method -Path $ep.Path -Result $result -Summary $ep.Summary

        $overallResults += [PSCustomObject]@{
            App        = $app.Name
            Method     = $ep.Method
            Path       = $ep.Path
            StatusCode = $result.StatusCode
            Status     = $result.Status
            Duration   = $result.Duration
        }

        switch ($result.Status) {
            "PASS"     { $appPass++ }
            "AUTH"     { $appWarn++ }
            "PARAM"    { $appWarn++ }
            "TIMEOUT"  { $appWarn++ }
            "NOTFOUND" { $appSkip++ }
            "METHODNA" { $appSkip++ }
            default    { $appFail++ }
        }
    }

    Write-Host ""
    $color = if ($appFail -gt 0) { "Red" } elseif ($appWarn -gt 0) { "Yellow" } else { "Green" }
    Write-Host "  Result: $appPass passed, $appWarn auth-protected, $appFail failed, $appSkip skipped" -ForegroundColor $color
    Write-Host ""

    $appSummaries += [PSCustomObject]@{
        App     = $app.Name
        Pass    = $appPass
        Warn    = $appWarn
        Fail    = $appFail
        Skip    = $appSkip
        Total   = $appPass + $appWarn + $appFail
        OpenApi = $hasOpenApi
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# OVERALL SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════

$totalPass = ($appSummaries | Measure-Object -Property Pass -Sum).Sum
$totalWarn = ($appSummaries | Measure-Object -Property Warn -Sum).Sum
$totalFail = ($appSummaries | Measure-Object -Property Fail -Sum).Sum
$totalSkip = ($appSummaries | Measure-Object -Property Skip -Sum).Sum
$totalTested = $totalPass + $totalWarn + $totalFail

Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Overall Summary" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

foreach ($s in $appSummaries) {
    $icon = if ($s.Fail -gt 0) { "X" } elseif ($s.Warn -gt 0) { "~" } else { "+" }
    $color = if ($s.Fail -gt 0) { "Red" } elseif ($s.Warn -gt 0) { "Yellow" } else { "Green" }
    $apiTag = if ($s.OpenApi) { "OpenAPI" } else { "fallback" }
    Write-Host "  [$icon] $($s.App): $($s.Pass) pass, $($s.Warn) auth, $($s.Fail) fail ($apiTag)" -ForegroundColor $color
}

Write-Host ""
Write-Host "  Endpoints tested: $totalTested | Passed: $totalPass | Auth-protected: $totalWarn | Failed: $totalFail | Skipped: $totalSkip" -ForegroundColor White
Write-Host "  Finished: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ─── Failed endpoints detail ──────────────────────────────────────────────────

$failedEndpoints = $overallResults | Where-Object { $_.Status -eq "FAIL" }
if ($failedEndpoints.Count -gt 0) {
    Write-Host "  Failed endpoints:" -ForegroundColor Red
    Write-Host ""

    # Group failures by app for cleaner output with per-app solutions
    $failedByApp = $failedEndpoints | Group-Object App
    foreach ($group in $failedByApp) {
        $appName = $group.Name
        Write-Host "    $($appName):" -ForegroundColor Red
        foreach ($f in $group.Group) {
            $statusText = if ($f.StatusCode -gt 0) { "HTTP $($f.StatusCode)" } else { "Connection refused" }
            Write-Host "      $($f.Method) $($f.Path) -- $statusText" -ForegroundColor Red
        }

        # Get solution hints based on the most severe status code for this app
        $worstCode = ($group.Group | Sort-Object StatusCode | Select-Object -First 1).StatusCode
        $hints = Get-SolutionHint -AppName $appName -StatusCode $worstCode
        if ($hints.Count -gt 0) {
            Write-Host "      Proposed solution:" -ForegroundColor Yellow
            foreach ($hint in $hints) {
                Write-Host "        $hint" -ForegroundColor DarkYellow
            }
        }
        Write-Host ""
    }
}

if ($hasIISHandler) {
    Reset-OverrideAppDataFolder
}

if ($totalFail -gt 0) {
    Write-LogMessage "Endpoint testing completed with $totalFail failure(s)" -Level ERROR
    Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_FAILED
    exit 1
} else {
    Write-LogMessage "All $totalTested endpoint(s) responded successfully" -Level INFO
    Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_COMPLETED
    exit 0
}
