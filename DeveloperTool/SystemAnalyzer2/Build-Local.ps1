#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Builds and runs SystemAnalyzer2.Web locally with version bump.
.DESCRIPTION
    - Kills any running dotnet/SystemAnalyzer2 processes
    - Auto-increments version in all csproj files
    - Builds the solution
    - Starts the web server
    - Verifies the version endpoint
.PARAMETER VersionPart
    Which version part to increment: Major, Minor, or Patch (default: Patch)
.PARAMETER SkipVersionBump
    Do not increment version; only build and run.
.PARAMETER SkipRun
    Only build, do not start the web server.
.PARAMETER Port
    Port for the web server (default: 5042)
.EXAMPLE
    .\Build-Local.ps1
.EXAMPLE
    .\Build-Local.ps1 -VersionPart Minor
#>

[CmdletBinding()]
param(
    [ValidateSet("Major", "Minor", "Patch")]
    [string]$VersionPart = "Patch",

    [switch]$SkipVersionBump,

    [switch]$SkipRun,

    [int]$Port = 5042
)

$ErrorActionPreference = "Stop"
$startTime = Get-Date
$projectRoot = $PSScriptRoot
$webCsproj = Join-Path $projectRoot "src\SystemAnalyzer2.Web\SystemAnalyzer2.Web.csproj"

# ═══════════════════════════════════════════════════════════════════════════════
# VERSION MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════════

function Get-ProjectVersion {
    param([string]$CsprojPath)
    if (-not (Test-Path $CsprojPath)) { return $null }
    $content = Get-Content $CsprojPath -Raw
    if ($content -match '<VersionPrefix>(\d+\.\d+\.\d+)</VersionPrefix>') { return $matches[1] }
    if ($content -match '<Version>(\d+\.\d+\.\d+)</Version>') { return $matches[1] }
    return $null
}

function Set-ProjectVersion {
    param([string]$CsprojPath, [string]$NewVersion)
    $content = Get-Content $CsprojPath -Raw
    if ($content -match '<VersionPrefix>\d+\.\d+\.\d+</VersionPrefix>') {
        $content = $content -replace '<VersionPrefix>\d+\.\d+\.\d+</VersionPrefix>', "<VersionPrefix>$NewVersion</VersionPrefix>"
    } elseif ($content -match '<Version>\d+\.\d+\.\d+</Version>') {
        $content = $content -replace '<Version>\d+\.\d+\.\d+</Version>', "<Version>$NewVersion</Version>"
    }
    Set-Content -Path $CsprojPath -Value $content -NoNewline
}

function Get-IncrementedVersion {
    param([string]$CurrentVersion, [string]$Part = "Patch")
    $parts = $CurrentVersion.Split('.')
    $major = [int]$parts[0]; $minor = [int]$parts[1]; $patch = [int]$parts[2]
    switch ($Part) {
        "Major" { $major++; $minor = 0; $patch = 0 }
        "Minor" { $minor++; $patch = 0 }
        "Patch" { $patch++ }
    }
    return "$major.$minor.$patch"
}

# ═══════════════════════════════════════════════════════════════════════════════
# PROJECT LIST
# ═══════════════════════════════════════════════════════════════════════════════

$versionedProjects = @(
    @{ Name = "SystemAnalyzer2.Web";   Path = Join-Path $projectRoot "src\SystemAnalyzer2.Web\SystemAnalyzer2.Web.csproj";     IsPrimary = $true }
    @{ Name = "SystemAnalyzer2.Core";  Path = Join-Path $projectRoot "src\SystemAnalyzer2.Core\SystemAnalyzer2.Core.csproj";   IsPrimary = $false }
    @{ Name = "SystemAnalyzer2.Batch"; Path = Join-Path $projectRoot "src\SystemAnalyzer2.Batch\SystemAnalyzer2.Batch.csproj"; IsPrimary = $false }
)

Write-Host ""
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host "  SystemAnalyzer2 - Local Build & Run" -ForegroundColor Cyan
Write-Host "  Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# KILL EXISTING PROCESSES
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "--- Killing existing dotnet processes ---" -ForegroundColor Yellow
$killed = 0
Get-Process -Name dotnet -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "  Killing PID $($_.Id): $($_.ProcessName)" -ForegroundColor Gray
    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    $killed++
}
if ($killed -eq 0) { Write-Host "  No dotnet processes found" -ForegroundColor Gray }
else { Write-Host "  Killed $killed process(es)" -ForegroundColor Green; Start-Sleep -Seconds 2 }
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# VERSION INCREMENT
# ═══════════════════════════════════════════════════════════════════════════════

$primary = $versionedProjects | Where-Object { $_.IsPrimary } | Select-Object -First 1
$currentVersion = Get-ProjectVersion -CsprojPath $primary.Path

if ($null -eq $currentVersion) {
    Write-Host "  No version found; defaulting to 1.0.0" -ForegroundColor Yellow
    $currentVersion = "1.0.0"
}

if (-not $SkipVersionBump) {
    $newVersion = Get-IncrementedVersion -CurrentVersion $currentVersion -Part $VersionPart
    Write-Host "--- Version: $currentVersion -> $newVersion ($VersionPart) ---" -ForegroundColor Yellow
    foreach ($proj in $versionedProjects) {
        Set-ProjectVersion -CsprojPath $proj.Path -NewVersion $newVersion
        Write-Host "  $($proj.Name): $newVersion" -ForegroundColor Green
    }
} else {
    $newVersion = $currentVersion
    Write-Host "--- Version: $newVersion (no bump) ---" -ForegroundColor Gray
}
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# BUILD
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "--- Building SystemAnalyzer2.Web ---" -ForegroundColor Yellow
$buildStart = Get-Date

try {
    & dotnet build $webCsproj -c Debug -v minimal
    if ($LASTEXITCODE -ne 0) { throw "dotnet build failed (exit code $LASTEXITCODE)" }
    $buildDuration = [math]::Round(((Get-Date) - $buildStart).TotalSeconds, 1)
    Write-Host "  Build succeeded ($(${buildDuration})s)" -ForegroundColor Green
} catch {
    Write-Host "  BUILD FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
Write-Host ""

if ($SkipRun) {
    Write-Host "  SkipRun set — not starting server" -ForegroundColor Gray
    exit 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# START WEB SERVER
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "--- Starting web server on port $Port ---" -ForegroundColor Yellow
$webProjectDir = Join-Path $projectRoot "src\SystemAnalyzer2.Web"

$proc = Start-Process -FilePath "dotnet" -ArgumentList "run", "--no-build", "--project", $webCsproj -WorkingDirectory $webProjectDir -PassThru -WindowStyle Hidden
Write-Host "  PID: $($proc.Id)" -ForegroundColor Gray

$baseUrl = "http://localhost:$Port"
$ready = $false
for ($i = 0; $i -lt 15; $i++) {
    Start-Sleep -Seconds 1
    try {
        $r = Invoke-WebRequest -Uri "$baseUrl/health" -Method GET -TimeoutSec 2 -ErrorAction Stop
        if ($r.StatusCode -eq 200) { $ready = $true; break }
    } catch { }
}

if (-not $ready) {
    Write-Host "  Server did not start within 15 seconds!" -ForegroundColor Red
    exit 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# VERIFY VERSION
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "--- Verifying running version ---" -ForegroundColor Yellow
try {
    $vResp = Invoke-RestMethod -Uri "$baseUrl/api/version" -Method GET -TimeoutSec 5
    $runningBase = ($vResp.version -split '\+')[0]
    Write-Host "  Running: v$($vResp.version)" -ForegroundColor $(if ($runningBase -eq $newVersion) { "Green" } else { "Red" })
    Write-Host "  Assembly: $($vResp.assembly)" -ForegroundColor Gray
    Write-Host "  Started: $($vResp.started)" -ForegroundColor Gray
    if ($runningBase -ne $newVersion) {
        Write-Host "  WARNING: Expected v$newVersion but got v$($vResp.version)!" -ForegroundColor Red
    }
} catch {
    Write-Host "  Could not verify version: $($_.Exception.Message)" -ForegroundColor Red
}

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════

$totalDuration = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
Write-Host ""
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host "  SystemAnalyzer2 v$newVersion running at $baseUrl" -ForegroundColor Cyan
Write-Host "  Graph:   $baseUrl/graph.html" -ForegroundColor Cyan
Write-Host "  API:     $baseUrl/scalar/v1" -ForegroundColor Cyan
Write-Host "  Version: $baseUrl/api/version" -ForegroundColor Cyan
Write-Host "  Total:   $(${totalDuration})s" -ForegroundColor Gray
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host ""
