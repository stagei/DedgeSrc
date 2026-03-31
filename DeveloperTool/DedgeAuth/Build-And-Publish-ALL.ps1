#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Builds and publishes DedgeAuth and all consumer apps that depend on DedgeAuth.Client.

.DESCRIPTION
    1. Scans $env:OptPath\src for .csproj files that reference DedgeAuth.Client.csproj
    2. Resolves each match to its Build-And-Publish.ps1 script (walks up the directory tree)
    3. Runs DedgeAuth's Build-And-Publish.ps1 first (the auth server must be published before consumer apps)
    4. Runs all discovered consumer app Build-And-Publish.ps1 scripts sequentially

.PARAMETER SkipDedgeAuth
    Skip building DedgeAuth itself. Useful when only consumer apps need republishing.

.PARAMETER DryRun
    Show what would be built without actually running anything.

.EXAMPLE
    .\Build-And-Publish-ALL.ps1
    # Builds DedgeAuth first, then all consumer apps

.EXAMPLE
    .\Build-And-Publish-ALL.ps1 -DryRun
    # Shows discovered projects without building

.EXAMPLE
    .\Build-And-Publish-ALL.ps1 -SkipDedgeAuth
    # Only builds consumer apps (assumes DedgeAuth is already published)
#>

param(
    [switch]$SkipDedgeAuth,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# ─────────────────────────────────────────────────────────────────────────────
#  Configuration
# ─────────────────────────────────────────────────────────────────────────────

$srcRoot = Join-Path $env:OptPath 'src'
if (-not (Test-Path $srcRoot)) {
    Write-Error "Source root not found: $($srcRoot). Ensure `$env:OptPath` is set."
    exit 1
}

# DedgeAuth project root (where Build-And-Publish.ps1 and src\DedgeAuth.Client live)
$DedgeAuthRoot = Join-Path $srcRoot 'DedgeAuth'
$DedgeAuthBuildScript = Join-Path $DedgeAuthRoot 'Build-And-Publish.ps1'
$DedgeAuthClientCsproj = Join-Path $DedgeAuthRoot 'src' 'DedgeAuth.Client' 'DedgeAuth.Client.csproj'

if (-not (Test-Path $DedgeAuthClientCsproj)) {
    Write-Error "DedgeAuth.Client.csproj not found at: $($DedgeAuthClientCsproj)"
    exit 1
}

if (-not (Test-Path $DedgeAuthBuildScript)) {
    Write-Error "DedgeAuth Build-And-Publish.ps1 not found at: $($DedgeAuthBuildScript)"
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
#  Helper: Walk up directory tree to find Build-And-Publish.ps1
# ─────────────────────────────────────────────────────────────────────────────

function Find-BuildScript {
    param([string]$StartPath)

    $dir = if (Test-Path $StartPath -PathType Leaf) {
        Split-Path $StartPath -Parent
    } else {
        $StartPath
    }

    # Walk up from the .csproj directory until we find Build-And-Publish.ps1
    # Stop at $srcRoot to avoid escaping the source tree
    while ($dir -and $dir.Length -ge $srcRoot.Length) {
        $candidate = Join-Path $dir 'Build-And-Publish.ps1'
        if (Test-Path $candidate) {
            return $candidate
        }
        $dir = Split-Path $dir -Parent
    }

    return $null
}

# ─────────────────────────────────────────────────────────────────────────────
#  Discovery: Find all .csproj files that reference DedgeAuth.Client
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ''
Write-Host '═══════════════════════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host '  DedgeAuth - Build & Publish ALL' -ForegroundColor Cyan
Write-Host "  Source root: $($srcRoot)" -ForegroundColor Cyan
Write-Host "  Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host '═══════════════════════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

Write-Host '  Scanning for projects that reference DedgeAuth.Client...' -ForegroundColor Yellow

# Search all .csproj files for references to DedgeAuth.Client
$consumerProjects = @()
$csprojFiles = Get-ChildItem -Path $srcRoot -Filter '*.csproj' -Recurse -ErrorAction SilentlyContinue

foreach ($csproj in $csprojFiles) {
    # Skip DedgeAuth's own projects
    if ($csproj.FullName -like "$($DedgeAuthRoot)*") { continue }

    $content = Get-Content $csproj.FullName -Raw -ErrorAction SilentlyContinue
    if ($content -match 'DedgeAuth\.Client') {
        $buildScript = Find-BuildScript -StartPath $csproj.FullName
        if ($buildScript) {
            $consumerProjects += [PSCustomObject]@{
                CsprojPath  = $csproj.FullName
                BuildScript = $buildScript
                ProjectDir  = Split-Path $buildScript -Parent
                ProjectName = (Split-Path (Split-Path $buildScript -Parent) -Leaf)
            }
        } else {
            Write-Host "    WARNING: No Build-And-Publish.ps1 found for: $($csproj.FullName)" -ForegroundColor Red
        }
    }
}

# Deduplicate by Build-And-Publish.ps1 path (multiple .csproj in same solution)
$uniqueProjects = $consumerProjects | Sort-Object BuildScript -Unique

# ─────────────────────────────────────────────────────────────────────────────
#  Summary
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ''
Write-Host '  Build order:' -ForegroundColor White
Write-Host ''

$buildOrder = @()

if (-not $SkipDedgeAuth) {
    Write-Host "    1. DedgeAuth (auth server)" -ForegroundColor Green
    Write-Host "       $($DedgeAuthBuildScript)" -ForegroundColor DarkGray
    $buildOrder += [PSCustomObject]@{
        ProjectName = 'DedgeAuth'
        BuildScript = $DedgeAuthBuildScript
        ProjectDir  = $DedgeAuthRoot
        IsDedgeAuth    = $true
    }
}

$index = $buildOrder.Count + 1
foreach ($proj in $uniqueProjects) {
    Write-Host "    $($index). $($proj.ProjectName) (consumer app)" -ForegroundColor Green
    Write-Host "       $($proj.BuildScript)" -ForegroundColor DarkGray
    $buildOrder += [PSCustomObject]@{
        ProjectName = $proj.ProjectName
        BuildScript = $proj.BuildScript
        ProjectDir  = $proj.ProjectDir
        IsDedgeAuth    = $false
    }
    $index++
}

Write-Host ''
Write-Host "  Total: $($buildOrder.Count) project(s) to build" -ForegroundColor White
Write-Host ''

if ($buildOrder.Count -eq 0) {
    Write-Host '  Nothing to build.' -ForegroundColor Yellow
    exit 0
}

if ($DryRun) {
    Write-Host '  DRY RUN - no builds executed.' -ForegroundColor Yellow
    exit 0
}

# ─────────────────────────────────────────────────────────────────────────────
#  Execute builds sequentially
# ─────────────────────────────────────────────────────────────────────────────

$results = @()
$overallStart = Get-Date

foreach ($build in $buildOrder) {
    Write-Host ''
    Write-Host '───────────────────────────────────────────────────────────────────────────────' -ForegroundColor DarkCyan
    Write-Host "  Building: $($build.ProjectName)" -ForegroundColor Cyan
    Write-Host "  Script:   $($build.BuildScript)" -ForegroundColor DarkGray
    Write-Host '───────────────────────────────────────────────────────────────────────────────' -ForegroundColor DarkCyan
    Write-Host ''

    $buildStart = Get-Date

    try {
        & pwsh.exe -File $build.BuildScript
        $exitCode = $LASTEXITCODE

        $duration = (Get-Date) - $buildStart
        $status = if ($exitCode -eq 0) { 'SUCCESS' } else { 'FAILED' }

        $results += [PSCustomObject]@{
            Project  = $build.ProjectName
            Status   = $status
            ExitCode = $exitCode
            Duration = '{0:N1}s' -f $duration.TotalSeconds
        }

        if ($exitCode -eq 0) {
            Write-Host "  $($build.ProjectName): SUCCESS ($($duration.TotalSeconds.ToString('N1'))s)" -ForegroundColor Green
        } else {
            Write-Host "  $($build.ProjectName): FAILED (exit code $($exitCode), $($duration.TotalSeconds.ToString('N1'))s)" -ForegroundColor Red
        }
    }
    catch {
        $duration = (Get-Date) - $buildStart
        $results += [PSCustomObject]@{
            Project  = $build.ProjectName
            Status   = 'ERROR'
            ExitCode = -1
            Duration = '{0:N1}s' -f $duration.TotalSeconds
        }
        Write-Host "  $($build.ProjectName): ERROR - $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  Final summary
# ─────────────────────────────────────────────────────────────────────────────

$overallDuration = (Get-Date) - $overallStart
$succeeded = ($results | Where-Object { $_.Status -eq 'SUCCESS' }).Count
$failed = ($results | Where-Object { $_.Status -ne 'SUCCESS' }).Count

Write-Host ''
Write-Host '═══════════════════════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host '  Build Summary' -ForegroundColor Cyan
Write-Host '═══════════════════════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

foreach ($r in $results) {
    $icon = if ($r.Status -eq 'SUCCESS') { '+' } else { 'X' }
    $color = if ($r.Status -eq 'SUCCESS') { 'Green' } else { 'Red' }
    Write-Host "  [$($icon)] $($r.Project): $($r.Status) ($($r.Duration))" -ForegroundColor $color
}

Write-Host ''
Write-Host "  Total: $($succeeded) succeeded, $($failed) failed | Duration: $($overallDuration.TotalSeconds.ToString('N1'))s" -ForegroundColor White
Write-Host "  Finished: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
Write-Host '═══════════════════════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

# Exit with failure if any build failed
if ($failed -gt 0) {
    exit 1
}
