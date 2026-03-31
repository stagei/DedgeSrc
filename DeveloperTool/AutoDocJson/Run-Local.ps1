#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Builds and runs AutoDocJson locally without DedgeAuth.
.DESCRIPTION
    Runs AutoDocJson.Web on Kestrel using the Development environment.
    DedgeAuth is automatically disabled via appsettings.Development.json
    (DedgeAuth.Enabled = false), so no authentication server is required.

    All [Authorize] and [RequireAppPermission] attributes are auto-allowed
    by DedgeAuth.Client standalone mode.

    Output folder defaults to C:\opt\Webs\AutoDocJson (configurable in
    appsettings.Development.json -> AutoDocJson:OutputFolder).

    Press Ctrl+C to stop the application.
.PARAMETER Port
    HTTP port to listen on. Default: 5280.
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
    [int]$Port = 5280,

    [switch]$NoBrowser,

    [switch]$NoBuild,

    [Alias('h','help')]
    [switch]$ShowHelp
)

if ($ShowHelp -or $args -contains '/?' -or $args -contains '--help' -or $args -contains '--h') {
    Write-Host ""
    Write-Host "Run-Local.ps1 — Run AutoDocJson locally without DedgeAuth" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage:  .\Run-Local.ps1 [-Port <int>] [-NoBrowser] [-NoBuild] [-Help]" -ForegroundColor White
    Write-Host ""
    Write-Host "Parameters:" -ForegroundColor Yellow
    Write-Host "  -Port <int>    HTTP port to listen on (default: 5280)"
    Write-Host "  -NoBrowser     Do not open the browser automatically"
    Write-Host "  -NoBuild       Skip the build step (use previous build output)"
    Write-Host "  -Help, -h      Show this help message"
    Write-Host "  /?, --help     Show this help message"
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  .\Run-Local.ps1                       # Default (port 5280, opens browser)"
    Write-Host "  .\Run-Local.ps1 -Port 8080            # Custom port"
    Write-Host "  .\Run-Local.ps1 -NoBrowser            # No auto-open"
    Write-Host "  .\Run-Local.ps1 -NoBuild -NoBrowser   # Skip build, no browser"
    Write-Host ""
    Write-Host "Environment:" -ForegroundColor Yellow
    Write-Host "  Uses appsettings.Development.json (DedgeAuth.Enabled = false)."
    Write-Host "  Output folder: C:\opt\Webs\AutoDocJson"
    Write-Host "  Press Ctrl+C to stop the running application."
    Write-Host ""
    exit 0
}

$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
$webProject  = Join-Path $projectRoot "AutoDocJson.Web\AutoDocJson.Web.csproj"

if (-not (Test-Path $webProject)) {
    Write-Host "Project not found: $($webProject)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  AutoDocJson — Run Local (no DedgeAuth)" -ForegroundColor Cyan
Write-Host "  URL: http://localhost:$($Port)" -ForegroundColor Cyan
Write-Host "  Environment: Development (DedgeAuth disabled)" -ForegroundColor Gray
Write-Host "  Press Ctrl+C to stop" -ForegroundColor Gray
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

Stop-Process -Name "AutoDocJson.Web" -Force -ErrorAction SilentlyContinue

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
