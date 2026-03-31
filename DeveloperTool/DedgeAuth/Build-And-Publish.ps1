#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Builds and publishes DedgeAuth.Api and IIS-AutoDeploy.Tray MSI installer.
.DESCRIPTION
    Uses the ServerMonitor Build-And-Publish pattern:
    - Auto-increments version numbers in ALL .csproj files (Api is primary, all others sync)
    - Stops running DedgeAuth processes so publish can succeed
    - Publishes DedgeAuth.Api using WebApp-FileSystem publish profile
    - Builds IIS-AutoDeploy.Tray MSI installer with the same version
    - Signs all published executables and MSI
    - Verifies published versions and signatures
    - Deploys DedgePsh server scripts
.PARAMETER VersionPart
    Which version part to increment: Major, Minor, or Patch (default: Patch)
.PARAMETER SkipVersionBump
    Do not increment version; only sync existing Api version and build.
.PARAMETER SkipBuild
    Do not rebuild. Only stop processes.
.PARAMETER SkipStart
    Do not start DedgeAuth.Api; only publish.
.PARAMETER PublishProfile
    Publish profile to use. Default: WebApp-FileSystem.
.EXAMPLE
    .\Build-And-Publish.ps1
.EXAMPLE
    .\Build-And-Publish.ps1 -VersionPart Minor
#>

[CmdletBinding()]
param(
    [ValidateSet("Major", "Minor", "Patch")]
    [string]$VersionPart = "Patch",

    [string]$ApiBaseUrl = "http://localhost:8100",

    [Parameter(Mandatory = $false)]
    [switch]$SkipVersionBump,

    [Parameter(Mandatory = $false)]
    [switch]$SkipBuild,

    [Parameter(Mandatory = $false)]
    [switch]$SkipStart,

    [ValidateSet("Local", "Prod", "WebApp-FileSystem")]
    [string]$PublishProfile = "WebApp-FileSystem"
)

try {
    Import-Module -Name GlobalFunctions -Force -ErrorAction Stop
} catch {
    Write-Host "[WARN] GlobalFunctions not available; using fallback logging." -ForegroundColor Yellow
    function Write-LogMessage { param([string]$Message, [string]$Level = "INFO") Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message" }
}

$ErrorActionPreference = "Stop"
$startTime = Get-Date
$projectRoot = $PSScriptRoot

# Publish output base paths
$publishBaseLocal = "C:\opt\DedgeWinApps\DedgeAuth"
$publishBaseProd = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\DedgeAuth"
$publishBase = if ($PublishProfile -eq "Prod" -or $PublishProfile -eq "WebApp-FileSystem") { $publishBaseProd } else { $publishBaseLocal }
$trayStagingPath = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\IIS-AutoDeploy-Tray"

Stop-Process -Name "DedgeAuth.Api" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "IIS-AutoDeploy.Tray" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  DedgeAuth – Build & Publish" -ForegroundColor Cyan
Write-Host "  Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# CLEAN AND PREPARE TARGET FOLDERS
# ═══════════════════════════════════════════════════════════════════════════════
$targetFolders = @($publishBase, $trayStagingPath)

Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  Preparing Target Folders" -ForegroundColor DarkGray
Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

foreach ($folder in $targetFolders) {
    if (Test-Path $folder) {
        Write-Host "  Removing: $folder" -ForegroundColor DarkGray
        Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "  Creating: $folder" -ForegroundColor DarkGray
    New-Item -ItemType Directory -Path $folder -Force -ErrorAction SilentlyContinue | Out-Null
}
Write-Host ""

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
# All projects use the same version, based on DedgeAuth.Api (primary project)
# ═══════════════════════════════════════════════════════════════════════════════

$versionedProjects = @(
    @{ Name = "DedgeAuth.Api";          Path = Join-Path $projectRoot "src\DedgeAuth.Api\DedgeAuth.Api.csproj";                   IsPrimary = $true },
    @{ Name = "DedgeAuth.Client";       Path = Join-Path $projectRoot "src\DedgeAuth.Client\DedgeAuth.Client.csproj";             IsPrimary = $false },
    @{ Name = "DedgeAuth.Core";         Path = Join-Path $projectRoot "src\DedgeAuth.Core\DedgeAuth.Core.csproj";                 IsPrimary = $false },
    @{ Name = "DedgeAuth.Data";         Path = Join-Path $projectRoot "src\DedgeAuth.Data\DedgeAuth.Data.csproj";                 IsPrimary = $false },
    @{ Name = "DedgeAuth.Services";     Path = Join-Path $projectRoot "src\DedgeAuth.Services\DedgeAuth.Services.csproj";         IsPrimary = $false },
    @{ Name = "IIS-AutoDeploy.Tray"; Path = Join-Path $projectRoot "src\IIS-AutoDeploy.Tray\IIS-AutoDeploy.Tray.csproj"; IsPrimary = $false }
)

$publishProjects = @(
    @{
        Name           = "DedgeAuth.Api"
        ProjectPath    = Join-Path $projectRoot "src\DedgeAuth.Api\DedgeAuth.Api.csproj"
        PublishProfile = $PublishProfile
        TargetPath     = $publishBase
        IsPrimary      = $true
    },
    @{
        Name           = "IIS-AutoDeploy.Tray"
        ProjectPath    = Join-Path $projectRoot "src\IIS-AutoDeploy.Tray\IIS-AutoDeploy.Tray.csproj"
        PublishProfile = $null
        TargetPath     = $trayStagingPath
        IsPrimary      = $false
        MsiProject     = $true
    }
)

# ═══════════════════════════════════════════════════════════════════════════════
# VERSION INCREMENT
# All projects use the same version, based on DedgeAuth.Api (primary project)
# ═══════════════════════════════════════════════════════════════════════════════

$newVersion = $null

Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
Write-Host "  Version Management (Incrementing $VersionPart)" -ForegroundColor Yellow
Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
Write-Host ""

$primaryProject = $versionedProjects | Where-Object { $_.IsPrimary } | Select-Object -First 1
$currentVersion = Get-ProjectVersion -CsprojPath $primaryProject.Path

if ($null -eq $currentVersion) {
    Write-LogMessage "No version found in DedgeAuth.Api csproj; using 1.0.0" -Level WARN
    $currentVersion = "1.0.0"
}

if (-not $SkipVersionBump) {
    $newVersion = Get-IncrementedVersion -CurrentVersion $currentVersion -Part $VersionPart
    Write-Host "  DedgeAuth.Api: $currentVersion -> $newVersion (PRIMARY)" -ForegroundColor Green
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
    foreach ($project in $publishProjects) {
        $projectStart = Get-Date

        Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
        Write-Host "  Building: $($project.Name)" -ForegroundColor Yellow
        Write-Host "  Project:  $($project.ProjectPath)" -ForegroundColor Gray
        if ($project.MsiProject) {
            Write-Host "  Output:   MSI Installer -> $($project.TargetPath)" -ForegroundColor Gray
        } else {
            Write-Host "  Profile:  $($project.PublishProfile)" -ForegroundColor Gray
            Write-Host "  Target:   $($project.TargetPath)" -ForegroundColor Gray
        }
        Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
        Write-Host ""

        if (-not (Test-Path $project.ProjectPath)) {
            Write-Host "  ERROR: Project file not found: $($project.ProjectPath)" -ForegroundColor Red
            $results += @{ Name = $project.Name; Success = $false; Duration = 0; Error = "Project file not found" }
            continue
        }

        try {
            if ($project.MsiProject) {
                $trayProjectDir = Split-Path $project.ProjectPath -Parent
                $localPublishDir = Join-Path $trayProjectDir "bin\Release\net10.0-windows\win-x64\publish"
                $installerDir = Join-Path (Split-Path $trayProjectDir -Parent) "IIS-AutoDeploy.Tray.Installer"
                $installerProj = Join-Path $installerDir "IIS-AutoDeploy.Tray.Installer.wixproj"

                Write-Host "  Step 1/3: Publishing tray app locally..." -ForegroundColor Cyan
                $publishArgs = @(
                    "publish", $project.ProjectPath,
                    "-c", "Release",
                    "-r", "win-x64",
                    "--self-contained", "false",
                    "-o", $localPublishDir,
                    "-v", "minimal"
                )
                & dotnet @publishArgs
                if ($LASTEXITCODE -ne 0) { throw "dotnet publish (local) failed with exit code $($LASTEXITCODE)" }

                Write-Host ""
                Write-Host "  Step 2/3: Building WiX installer (MSI) v$($newVersion)..." -ForegroundColor Cyan
                $buildArgs = @(
                    "build", $installerProj,
                    "-c", "Release",
                    "-p:Platform=x64",
                    "-p:ProductVersion=$newVersion",
                    "-v", "minimal"
                )
                & dotnet @buildArgs
                if ($LASTEXITCODE -ne 0) { throw "WiX installer build failed with exit code $($LASTEXITCODE)" }

                Write-Host ""
                Write-Host "  Step 3/3: Copying MSI to $($project.TargetPath)..." -ForegroundColor Cyan
                $msiSource = Join-Path $installerDir "bin\x64\Release\IIS-AutoDeploy.Tray.Setup.msi"
                if (-not (Test-Path $msiSource)) {
                    $msiSource = Get-ChildItem -Path (Join-Path $installerDir "bin") -Filter "*.msi" -Recurse | Select-Object -First 1 -ExpandProperty FullName
                }
                if (-not $msiSource -or -not (Test-Path $msiSource)) {
                    throw "MSI file not found after build"
                }
                Copy-Item -Path $msiSource -Destination $project.TargetPath -Force
                $msiName = Split-Path $msiSource -Leaf
                Write-Host "  $msiName -> $($project.TargetPath)\$msiName" -ForegroundColor Green

                # Copy _install.ps1 so Install-OurWinApp can run the MSI silently
                $installScript = Join-Path (Split-Path $project.ProjectPath) "_install.ps1"
                if (Test-Path $installScript -PathType Leaf) {
                    Copy-Item -Path $installScript -Destination $project.TargetPath -Force
                    Write-Host "  _install.ps1 -> $($project.TargetPath)\_install.ps1" -ForegroundColor Green
                }

                $duration = [math]::Round(((Get-Date) - $projectStart).TotalSeconds, 1)
                Write-Host ""
                Write-Host "  $($project.Name) MSI published successfully! ($(${duration})s)" -ForegroundColor Green
                Write-Host ""
                $results += @{ Name = $project.Name; Success = $true; Duration = $duration; Error = $null }
            }
            else {
                $publishArgs = @(
                    "publish",
                    $project.ProjectPath,
                    "--configuration", "Release",
                    "-p:PublishProfile=$($project.PublishProfile)",
                    "-v", "minimal"
                )
                & dotnet @publishArgs
                if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit code $($LASTEXITCODE)" }

                $duration = [math]::Round(((Get-Date) - $projectStart).TotalSeconds, 1)
                Write-Host ""
                Write-Host "  $($project.Name) published successfully! ($(${duration})s)" -ForegroundColor Green
                Write-Host ""
                $results += @{ Name = $project.Name; Success = $true; Duration = $duration; Error = $null }
            }
        }
        catch {
            $duration = [math]::Round(((Get-Date) - $projectStart).TotalSeconds, 1)
            Write-Host ""
            Write-Host "  $($project.Name) failed: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ""
            $results += @{ Name = $project.Name; Success = $false; Duration = $duration; Error = $_.Exception.Message }
        }
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # SIGN PUBLISHED EXECUTABLES
    # ═══════════════════════════════════════════════════════════════════════════

    Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Magenta
    Write-Host "  Signing Published Files (EXE + MSI)" -ForegroundColor Magenta
    Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Magenta
    Write-Host ""

    $filesToSign = @(
        "$publishBase\DedgeAuth.Api.exe"
    )

    $msiTarget = Get-ChildItem -Path $trayStagingPath -Filter "*.msi" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($msiTarget) {
        $filesToSign += $msiTarget.FullName
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
                    Write-Host "  Signing may have failed for: $(Split-Path -Leaf $fileToSign) (Status: $($sigAfter.Status))" -ForegroundColor Yellow
                }
            }
            catch {
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

    $verifyApps = @(
        @{ Name = "DedgeAuth.Api"; Path = "$publishBase\DedgeAuth.Api.exe"; IsMsi = $false },
        @{ Name = "IIS-AutoDeploy.Tray"; Path = $trayStagingPath; IsMsi = $true }
    )

    foreach ($app in $verifyApps) {
        if ($app.IsMsi) {
            $msiFile = Get-ChildItem -Path $app.Path -Filter "*.msi" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($msiFile) {
                $sizeMB = [math]::Round($msiFile.Length / 1MB, 1)
                Write-Host "  $($app.Name): $($msiFile.Name) ($(${sizeMB}) MB)" -ForegroundColor Green
            } else {
                Write-Host "  $($app.Name): MSI NOT FOUND in $($app.Path)" -ForegroundColor Red
            }
        }
        elseif (Test-Path $app.Path) {
            $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($app.Path)
            $sig = Get-AuthenticodeSignature $app.Path -ErrorAction SilentlyContinue
            $sigStatus = if ($sig.Status -eq 'Valid') { "Signed" } else { "$($sig.Status)" }
            Write-Host "  $($app.Name): v$($vi.FileVersion) $sigStatus" -ForegroundColor $(if ($sig.Status -eq 'Valid') { 'Green' } else { 'Yellow' })
        } else {
            Write-Host "  $($app.Name): NOT FOUND at $($app.Path)" -ForegroundColor Red
        }
    }
    Write-Host ""

    # ═══════════════════════════════════════════════════════════════════════════
    # DEPLOY DedgePsh SCRIPTS
    # ═══════════════════════════════════════════════════════════════════════════

    $deployScripts = @(
        @{ Name = "Database setup";     Path = "C:\opt\src\DedgePsh\DevTools\WebSites\DedgeAuth\DedgeAuth-DatabaseSetup\_deploy.ps1" },
        @{ Name = "App registration";   Path = "C:\opt\src\DedgePsh\DevTools\WebSites\DedgeAuth\DedgeAuth-AddAppSupport\_deploy.ps1" },
        @{ Name = "IIS-DeployApp";      Path = "C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\_deploy.ps1" }
    )
    $firstDeploy = $true
    foreach ($ds in $deployScripts) {
        if (Test-Path $ds.Path) {
            Write-Host "  Deploying $($ds.Name) script..." -ForegroundColor Gray
            try {
                & $ds.Path -DeployModules $firstDeploy
                $firstDeploy = $false
                Write-Host "  $($ds.Name) script deployed." -ForegroundColor Green
            } catch {
                Write-LogMessage "$($ds.Name) script deploy failed: $($_.Exception.Message)" -Level WARN
            }
        } else {
            Write-LogMessage "$($ds.Name) deploy script not found: $($ds.Path)" -Level WARN
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
Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Gray
Write-Host "  Total: $successCount succeeded, $failCount failed | Duration: $(${totalDuration})s" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Yellow" })
Write-Host "  Finished: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

if ($failCount -gt 0) {
    exit 1
}
