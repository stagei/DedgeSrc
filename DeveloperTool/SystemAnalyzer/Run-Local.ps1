#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Builds and runs SystemAnalyzer.Web locally without DedgeAuth.
.DESCRIPTION
    Runs SystemAnalyzer.Web on Kestrel using the Development environment.
    DedgeAuth is automatically disabled via appsettings.Development.json
    (DedgeAuth.Enabled = false), so no authentication server is required.

    All [Authorize] and [RequireAppPermission] attributes are auto-allowed
    by DedgeAuth.Client standalone mode.

    DataRoot points to the source tree (C:\opt\src\SystemAnalyzer) in Development.
    Analysis results are served from {DataRoot}\AnalysisResults\ (i.e. the repo folder).
    Press Ctrl+C to stop the application.
.PARAMETER Port
    HTTP port to listen on. Default: 5042.
.PARAMETER NoBrowser
    Do not open the browser automatically.
.PARAMETER NoBuild
    Skip the build step (use previous build output).
.EXAMPLE
    .\Run-Local.ps1
.EXAMPLE
    .\Run-Local.ps1 -Port 8080
.EXAMPLE
    .\Run-Local.ps1 -NoBrowser
#>

[CmdletBinding()]
param(
    [int]$Port = 5042,

    [switch]$NoBrowser,

    [switch]$NoBuild
)

$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
$webProject  = Join-Path $projectRoot "src\SystemAnalyzer.Web\SystemAnalyzer.Web.csproj"

if (-not (Test-Path $webProject)) {
    Write-Host "Project not found: $($webProject)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  SystemAnalyzer — Run Local (no DedgeAuth)" -ForegroundColor Cyan
Write-Host "  URL: http://localhost:$($Port)" -ForegroundColor Cyan
Write-Host "  Environment: Development (DedgeAuth disabled)" -ForegroundColor Gray
Write-Host "  Press Ctrl+C to stop" -ForegroundColor Gray
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

Stop-Process -Name "SystemAnalyzer.Web" -Force -ErrorAction SilentlyContinue

$appUrl = "http://localhost:$($Port)"

if (-not $NoBrowser) {
    Start-Job -Name "OpenBrowser" -ScriptBlock {
        param($url)
        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Seconds 1
            try {
                $null = Invoke-WebRequest -Uri "$($url)/health" -UseBasicParsing -TimeoutSec 2
                Start-Process $url
                return
            } catch { }
        }
        Write-Warning "Timed out waiting for $($url) — open it manually"
    } -ArgumentList $appUrl | Out-Null
}

$runArgs = @("run", "--project", $webProject, "--environment", "Development", "--urls", $appUrl)
if ($NoBuild) { $runArgs += "--no-build" }

& dotnet @runArgs
