#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Builds and publishes AutoDocJson.Web and AutoDocJson (batch runner) to the staging share.
.DESCRIPTION
    Uses the ServerMonitor Build-And-Publish pattern:
    - Auto-increments version numbers in ALL .csproj files (Web is primary, all others sync)
    - Publishes AutoDocJson.Web using WebApp-FileSystem publish profile
    - Publishes AutoDocJson (console) using WinApp-FileSystem publish profile
    - Signs published executables
    - Verifies published versions and signatures
.PARAMETER VersionPart
    Which version part to increment: Major, Minor, or Patch (default: Patch)
.PARAMETER SkipVersionBump
    Do not increment version; only build.
.PARAMETER SkipBuild
    Do not rebuild.
.EXAMPLE
    .\Build-And-Publish.ps1
.EXAMPLE
    .\Build-And-Publish.ps1 -VersionPart Minor
#>

[CmdletBinding()]
param(
    [ValidateSet("Major", "Minor", "Patch")]
    [string]$VersionPart = "Patch",

    [Parameter(Mandatory = $false)]
    [switch]$SkipVersionBump,

    [Parameter(Mandatory = $false)]
    [switch]$SkipBuild
)

Import-Module GlobalFunctions -Force

$ErrorActionPreference = "Stop"
$startTime = Get-Date
$projectRoot = $PSScriptRoot
$publishShareBase = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps"

Stop-Process -Name "AutoDocJson.Web" -Force -ErrorAction SilentlyContinue
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
    @{ Name = "AutoDocJson.Web";     Path = Join-Path $projectRoot "AutoDocJson.Web\AutoDocJson.Web.csproj";       IsPrimary = $true },
    @{ Name = "AutoDocJson";         Path = Join-Path $projectRoot "AutoDocJson\AutoDocJson.csproj";               IsPrimary = $false },
    @{ Name = "AutoDocJson.Core";    Path = Join-Path $projectRoot "AutoDocJson.Core\AutoDocJson.Core.csproj";     IsPrimary = $false },
    @{ Name = "AutoDocJson.Models";  Path = Join-Path $projectRoot "AutoDocJson.Models\AutoDocJson.Models.csproj"; IsPrimary = $false },
    @{ Name = "AutoDocJson.Parsers"; Path = Join-Path $projectRoot "AutoDocJson.Parsers\AutoDocJson.Parsers.csproj"; IsPrimary = $false }
)

$publishProjects = @(
    @{
        Name           = "AutoDocJson.Web"
        ProjectPath    = Join-Path $projectRoot "AutoDocJson.Web\AutoDocJson.Web.csproj"
        PublishProfile = "WebApp-FileSystem"
        PublishFolder  = "AutoDocJson"
        ExeName        = "AutoDocJson.Web.exe"
    },
    @{
        Name           = "AutoDocJson"
        ProjectPath    = Join-Path $projectRoot "AutoDocJson\AutoDocJson.csproj"
        PublishProfile = "WinApp-FileSystem"
        PublishFolder  = "AutoDocJsonBatchRunner"
        ExeName        = "AutoDocJson.exe"
    }
)

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  AutoDocJson – Build & Publish" -ForegroundColor Cyan
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
    Write-LogMessage "No version found in AutoDocJson.Web csproj; using 1.0.0" -Level WARN
    $currentVersion = "1.0.0"
}

if (-not $SkipVersionBump) {
    $newVersion = Get-IncrementedVersion -CurrentVersion $currentVersion -Part $VersionPart
    Write-Host "  AutoDocJson.Web: $currentVersion -> $newVersion (PRIMARY)" -ForegroundColor Green
} else {
    $newVersion = $currentVersion
    Write-Host "  Version (no bump): $newVersion" -ForegroundColor Gray
}

foreach ($proj in $versionedProjects) {
    if (-not (Test-Path $proj.Path)) {
        Write-Host "  $($proj.Name): csproj not found" -ForegroundColor Yellow
        continue
    }
    $cur = Get-ProjectVersion -CsprojPath $proj.Path
    Set-ProjectVersion -CsprojPath $proj.Path -NewVersion $newVersion
    if (-not $proj.IsPrimary) {
        if ($cur -ne $newVersion) {
            Write-Host "  $($proj.Name): $cur -> $newVersion" -ForegroundColor White
        } else {
            Write-Host "  $($proj.Name): $newVersion (unchanged)" -ForegroundColor DarkGray
        }
    }
}
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# BUILD AND PUBLISH
# ═══════════════════════════════════════════════════════════════════════════════

$results = @()

if (-not $SkipBuild) {
    foreach ($proj in $publishProjects) {
        $projectStart = Get-Date

        Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
        Write-Host "  Publishing $($proj.Name) (profile: $($proj.PublishProfile))" -ForegroundColor Yellow
        Write-Host "  Target: $publishShareBase\$($proj.PublishFolder)" -ForegroundColor Gray
        Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
        Write-Host ""

        if (-not (Test-Path $proj.ProjectPath)) {
            Write-Host "  ERROR: Project not found: $($proj.ProjectPath)" -ForegroundColor Red
            $results += @{ Name = $proj.Name; Success = $false; Duration = 0; Error = "Project not found" }
            continue
        }

        try {
            & dotnet publish "$($proj.ProjectPath)" /p:PublishProfile=$($proj.PublishProfile) -v minimal
            if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit code $($LASTEXITCODE)" }

            $duration = [math]::Round(((Get-Date) - $projectStart).TotalSeconds, 1)
            Write-Host ""
            Write-Host "  $($proj.Name) published successfully! ($(${duration})s)" -ForegroundColor Green
            Write-Host ""
            $results += @{ Name = $proj.Name; Success = $true; Duration = $duration; Error = $null }
        }
        catch {
            $duration = [math]::Round(((Get-Date) - $projectStart).TotalSeconds, 1)
            Write-Host "  $($proj.Name) failed: $($_.Exception.Message)" -ForegroundColor Red
            $results += @{ Name = $proj.Name; Success = $false; Duration = $duration; Error = $_.Exception.Message }
        }
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # SIGN PUBLISHED EXECUTABLES
    # ═══════════════════════════════════════════════════════════════════════════

    Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Magenta
    Write-Host "  Signing Published Files" -ForegroundColor Magenta
    Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Magenta
    Write-Host ""

    $filesToSign = @()
    foreach ($proj in $publishProjects) {
        $filesToSign += "$publishShareBase\$($proj.PublishFolder)\$($proj.ExeName)"
    }
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

    foreach ($proj in $publishProjects) {
        $exePath = "$publishShareBase\$($proj.PublishFolder)\$($proj.ExeName)"
        if (Test-Path $exePath) {
            $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exePath)
            $sig = Get-AuthenticodeSignature $exePath -ErrorAction SilentlyContinue
            $sigStatus = if ($sig.Status -eq 'Valid') { "Signed" } else { "$($sig.Status)" }
            Write-Host "  $($proj.Name): v$($vi.FileVersion) $sigStatus" -ForegroundColor $(if ($sig.Status -eq 'Valid') { 'Green' } else { 'Yellow' })
        } else {
            Write-Host "  $($proj.Name): NOT FOUND at $exePath" -ForegroundColor Red
        }
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
    if ($result.Error) {
        Write-Host "     Error: $($result.Error)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "  Total: $successCount succeeded, $failCount failed | Duration: $(${totalDuration})s" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Yellow" })
Write-Host "  Finished: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

if ($failCount -gt 0) { exit 1 }
