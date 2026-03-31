#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Builds and publishes SystemAnalyzer to the staging share.
.DESCRIPTION
    Uses the standard Build-And-Publish pattern:
    - Auto-increments version number in all .csproj files
    - Stops running SystemAnalyzer.Web processes so publish can succeed
    - Publishes SystemAnalyzer.Web using WebApp-FileSystem publish profile
    - Signs published executable
    - Verifies published version and signature
.PARAMETER VersionPart
    Which version part to increment: Major, Minor, or Patch (default: Patch)
.PARAMETER SkipVersionBump
    Do not increment version; only build.
.PARAMETER SkipBuild
    Do not rebuild.
.PARAMETER SkipStart
    Do not start SystemAnalyzer; only publish. Do not open browser.
.EXAMPLE
    .\Build-And-Publish.ps1
.EXAMPLE
    .\Build-And-Publish.ps1 -VersionPart Minor
#>

[CmdletBinding()]
param(
    [ValidateSet("Major", "Minor", "Patch")]
    [string]$VersionPart = "Patch",

    [string]$ApiBaseUrl = "http://localhost:8790",

    [Parameter(Mandatory = $false)]
    [switch]$SkipVersionBump,

    [Parameter(Mandatory = $false)]
    [switch]$SkipBuild,

    [Parameter(Mandatory = $false)]
    [bool]$SkipStart = $true,

    [ValidateSet("WebApp-FileSystem")]
    [string]$PublishProfile = "WebApp-FileSystem"
)

Import-Module GlobalFunctions -Force

$ErrorActionPreference = "Stop"
$startTime = Get-Date
$projectRoot = $PSScriptRoot
$publishBase = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\SystemAnalyzer"

Stop-Process -Name "SystemAnalyzer.Web" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# ═══════════════════════════════════════════════════════════════════════════════
# VERSION MANAGEMENT FUNCTIONS
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
    } else {
        $content = $content -replace '<Version>\d+\.\d+\.\d+</Version>', "<Version>$NewVersion</Version>"
    }
    Set-Content -Path $CsprojPath -Value $content -NoNewline
}

function Get-IncrementedVersion {
    param([string]$CurrentVersion, [string]$Part = "Patch")
    $versionParts = $CurrentVersion.Split('.')
    $major = [int]$versionParts[0]
    $minor = [int]$versionParts[1]
    $patch = [int]$versionParts[2]
    switch ($Part) {
        "Major" { $major++; $minor = 0; $patch = 0 }
        "Minor" { $minor++; $patch = 0 }
        "Patch" { $patch++ }
    }
    return "$major.$minor.$patch"
}

# ═══════════════════════════════════════════════════════════════════════════════
# PROJECT DEFINITIONS
# ═══════════════════════════════════════════════════════════════════════════════

$versionedProjects = @(
    @{ Name = "SystemAnalyzer.Web";   Path = Join-Path $projectRoot "src\SystemAnalyzer.Web\SystemAnalyzer.Web.csproj";     IsPrimary = $true }
    @{ Name = "SystemAnalyzer.Core";  Path = Join-Path $projectRoot "src\SystemAnalyzer.Core\SystemAnalyzer.Core.csproj";   IsPrimary = $false }
    @{ Name = "SystemAnalyzer.Batch"; Path = Join-Path $projectRoot "src\SystemAnalyzer.Batch\SystemAnalyzer.Batch.csproj"; IsPrimary = $false }
)

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  SystemAnalyzer – Build & Publish" -ForegroundColor Cyan
Write-Host "  Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# VERSION INCREMENT
# ═══════════════════════════════════════════════════════════════════════════════

$newVersion = $null

Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
Write-Host "  Version Management (Incrementing $VersionPart)" -ForegroundColor Yellow
Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
Write-Host ""

$primaryProject = $versionedProjects | Where-Object { $_.IsPrimary } | Select-Object -First 1
$currentVersion = Get-ProjectVersion -CsprojPath $primaryProject.Path

if ($null -eq $currentVersion) {
    Write-LogMessage "No version found in SystemAnalyzer.Web csproj; using 1.0.0" -Level WARN
    $currentVersion = "1.0.0"
}

if (-not $SkipVersionBump) {
    $newVersion = Get-IncrementedVersion -CurrentVersion $currentVersion -Part $VersionPart
    Write-Host "  SystemAnalyzer.Web: $($currentVersion) -> $($newVersion) (PRIMARY)" -ForegroundColor Green
} else {
    $newVersion = $currentVersion
    Write-Host "  Version (no bump): $newVersion" -ForegroundColor Gray
}

foreach ($proj in $versionedProjects) {
    $label = if ($proj.IsPrimary) { "" } else { "  $($proj.Name): -> $newVersion" }
    if ($label) { Write-Host $label -ForegroundColor Gray }
    Set-ProjectVersion -CsprojPath $proj.Path -NewVersion $newVersion
}
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# BUILD AND PUBLISH
# ═══════════════════════════════════════════════════════════════════════════════

$results = @()

if (-not $SkipBuild) {
    $projectStart = Get-Date

    Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
    Write-Host "  Publishing SystemAnalyzer.Web (profile: $PublishProfile)" -ForegroundColor Yellow
    Write-Host "  Target: $publishBase" -ForegroundColor Gray
    Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
    Write-Host ""

    $csprojPath = Join-Path $projectRoot "src\SystemAnalyzer.Web\SystemAnalyzer.Web.csproj"
    if (-not (Test-Path $csprojPath)) {
        Write-LogMessage "Project not found: $($csprojPath)" -Level ERROR
        exit 1
    }

    try {
        $publishArgs = @(
            "publish", $csprojPath,
            "/p:PublishProfile=$PublishProfile",
            "-v", "minimal"
        )
        & dotnet @publishArgs
        if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit code $($LASTEXITCODE)" }

        $duration = [math]::Round(((Get-Date) - $projectStart).TotalSeconds, 1)
        Write-Host ""
        Write-Host "  SystemAnalyzer.Web published successfully! ($($duration)s)" -ForegroundColor Green
        Write-Host ""
        $results += @{ Name = "SystemAnalyzer.Web"; Success = $true; Duration = $duration; Error = $null }
    }
    catch {
        $duration = [math]::Round(((Get-Date) - $projectStart).TotalSeconds, 1)
        Write-Host "  SystemAnalyzer.Web failed: $($_.Exception.Message)" -ForegroundColor Red
        $results += @{ Name = "SystemAnalyzer.Web"; Success = $false; Duration = $duration; Error = $_.Exception.Message }
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # PUBLISH SystemAnalyzer.Batch
    # ═══════════════════════════════════════════════════════════════════════════

    $batchStart = Get-Date
    $batchPublishBase = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\SystemAnalyzer-Batch"

    Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
    Write-Host "  Publishing SystemAnalyzer.Batch" -ForegroundColor Yellow
    Write-Host "  Target: $($batchPublishBase)" -ForegroundColor Gray
    Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
    Write-Host ""

    $batchCsproj = Join-Path $projectRoot "src\SystemAnalyzer.Batch\SystemAnalyzer.Batch.csproj"
    if (Test-Path $batchCsproj) {
        try {
            $batchPublishArgs = @(
                "publish", $batchCsproj,
                "-c", "Release",
                "-o", $batchPublishBase,
                "-v", "minimal"
            )
            & dotnet @batchPublishArgs
            if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit code $($LASTEXITCODE)" }

            $batchDuration = [math]::Round(((Get-Date) - $batchStart).TotalSeconds, 1)
            Write-Host ""
            Write-Host "  SystemAnalyzer.Batch published successfully! ($($batchDuration)s)" -ForegroundColor Green
            Write-Host ""
            $results += @{ Name = "SystemAnalyzer.Batch"; Success = $true; Duration = $batchDuration; Error = $null }
        } catch {
            $batchDuration = [math]::Round(((Get-Date) - $batchStart).TotalSeconds, 1)
            Write-Host "  SystemAnalyzer.Batch failed: $($_.Exception.Message)" -ForegroundColor Red
            $results += @{ Name = "SystemAnalyzer.Batch"; Success = $false; Duration = $batchDuration; Error = $_.Exception.Message }
        }
    } else {
        Write-Host "  Batch project not found: $($batchCsproj)" -ForegroundColor Yellow
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # SIGN PUBLISHED EXECUTABLES
    # ═══════════════════════════════════════════════════════════════════════════

    Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Magenta
    Write-Host "  Signing Published Files" -ForegroundColor Magenta
    Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Magenta
    Write-Host ""

    $filesToSign = @(
        "$publishBase\SystemAnalyzer.Web.exe",
        "$batchPublishBase\SystemAnalyzer.Batch.exe"
    )
    $DedgeSignPath = "dedge-server.DEDGE.fk.no\DedgeCommon\Software\DedgePshApps\DedgeSign\DedgeSign.ps1"

    foreach ($fileToSign in $filesToSign) {
        if (Test-Path $fileToSign) {
            $sig = Get-AuthenticodeSignature -FilePath $fileToSign -ErrorAction SilentlyContinue
            if ($sig.Status -eq 'Valid') {
                Write-Host "  Already signed: $(Split-Path -Leaf $fileToSign)" -ForegroundColor Green
                continue
            }
            Write-Host "  Signing: $(Split-Path -Leaf $fileToSign)..." -ForegroundColor Yellow
            try {
                & pwsh.exe -ExecutionPolicy Bypass -File $DedgeSignPath -Path $fileToSign -Action Add -NoConfirm 2>&1 | Out-Null
                $sigAfter = Get-AuthenticodeSignature -FilePath $fileToSign -ErrorAction SilentlyContinue
                if ($sigAfter.Status -eq 'Valid') {
                    Write-Host "  Signed successfully: $(Split-Path -Leaf $fileToSign)" -ForegroundColor Green
                } else {
                    Write-Host "  Signing may have failed: $(Split-Path -Leaf $fileToSign) (Status: $($sigAfter.Status))" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "  Could not sign: $(Split-Path -Leaf $fileToSign) - $($_.Exception.Message)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  File not found: $fileToSign" -ForegroundColor Yellow
        }
    }
    Write-Host ""

    # ═══════════════════════════════════════════════════════════════════════════
    # VERIFY PUBLISHED VERSIONS
    # ═══════════════════════════════════════════════════════════════════════════

    Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
    Write-Host "  Verifying Published Versions" -ForegroundColor Cyan
    Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
    Write-Host ""

    $exePath = "$publishBase\SystemAnalyzer.Web.exe"
    if (Test-Path $exePath) {
        $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exePath)
        $sig = Get-AuthenticodeSignature $exePath -ErrorAction SilentlyContinue
        $sigStatus = if ($sig.Status -eq 'Valid') { "Signed" } else { "$($sig.Status)" }
        Write-Host "  SystemAnalyzer.Web: v$($vi.FileVersion) $sigStatus" -ForegroundColor $(if ($sig.Status -eq 'Valid') { 'Green' } else { 'Yellow' })
    } else {
        Write-Host "  SystemAnalyzer.Web: NOT FOUND at $exePath" -ForegroundColor Red
    }
    Write-Host ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════

$totalDuration = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
$successCount = ($results | Where-Object { $_.Success }).Count
$failCount = ($results | Where-Object { -not $_.Success }).Count

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Build Summary" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

if ($newVersion) {
    Write-Host "  Version: $newVersion" -ForegroundColor Cyan
    Write-Host ""
}

foreach ($result in $results) {
    $icon = if ($result.Success) { "+" } else { "X" }
    $color = if ($result.Success) { "Green" } else { "Red" }
    $status = if ($result.Success) { "SUCCESS" } else { "FAILED" }
    Write-Host "  [$icon] $($result.Name): $status ($($result.Duration)s)" -ForegroundColor $color
}

Write-Host ""
Write-Host "  Total: $successCount succeeded, $failCount failed | Duration: $($totalDuration)s" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Yellow" })
Write-Host "  Finished: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

if ($failCount -gt 0) { exit 1 }
