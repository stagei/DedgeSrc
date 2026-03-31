#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Builds and publishes ServerMonitor, ServerMonitorTrayIcon, and ServerMonitorDashboard applications
.DESCRIPTION
    Uses standard publish profiles (WebApp-FileSystem / WinApp-FileSystem) to build and deploy all applications:
    - ServerMonitorAgent → C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitor
    - ServerMonitorTrayIcon → C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitorTrayIcon
    - ServerMonitorDashboard → C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitorDashboard
    - ServerMonitorDashboard.Tray → C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitorDashboard.Tray (MSI installer)
    
    Also:
    - Auto-increments version numbers in all .csproj files
    - Creates/updates the Agent reinstall trigger file with the new version
    - Dashboard is deployed exclusively via IIS-DeployApp (no trigger file)
.PARAMETER VersionPart
    Which version part to increment: Major, Minor, or Patch (default: Patch)
.EXAMPLE
    .\Build-And-Publish.ps1
.EXAMPLE
    .\Build-And-Publish.ps1 -VersionPart Minor
#>

[CmdletBinding()]
param(
    [ValidateSet("Major", "Minor", "Patch")]
    [string]$VersionPart = "Patch"
)
Import-Module -Name GlobalFunctions -Force
Import-Module -Name SoftwareUtils -Force

$ErrorActionPreference = "Stop"
$startTime = Get-Date
Stop-Process -Name "ServerMonitorDashboard" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "ServerMonitorDashboard.Tray" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "ServerMonitor" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "ServerMonitorTrayIcon" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════
$ConfigBasePath = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor"
$ReinstallTriggerFile = Join-Path $ConfigBasePath "ReinstallServerMonitor.txt"

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  ServerMonitor Build & Publish Script" -ForegroundColor Cyan
Write-Host "  Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Get script directory (project root)
$projectRoot = $PSScriptRoot

# ═══════════════════════════════════════════════════════════════════════════════
# DELETE EXISTING TRIGGER FILES (to ensure FileSystemWatcher detects new files)
# ═══════════════════════════════════════════════════════════════════════════════
if (Test-Path $ReinstallTriggerFile) {
    Write-Host "  🗑️  Removing existing Agent trigger file..." -ForegroundColor DarkGray
    Remove-Item -Path $ReinstallTriggerFile -Force -ErrorAction SilentlyContinue
    Write-Host "     Deleted: $ReinstallTriggerFile" -ForegroundColor DarkGray
}
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# CLEAN AND PREPARE TARGET FOLDERS
# ═══════════════════════════════════════════════════════════════════════════════
$targetFolders = @(
    "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitor",
    "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitorTrayIcon",
    "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitorDashboard",
    "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitorDashboard.Tray"
)

Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  Preparing Target Folders" -ForegroundColor DarkGray
Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

foreach ($folder in $targetFolders) {
    if (Test-Path $folder) {
        Write-Host "  🗑️  Removing: $folder" -ForegroundColor DarkGray
        Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "  📁 Creating: $folder" -ForegroundColor DarkGray
    New-Item -ItemType Directory -Path $folder -Force -ErrorAction SilentlyContinue | Out-Null
}
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# VERSION MANAGEMENT FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

function Get-ProjectVersion {
    param([string]$CsprojPath)
    
    if (-not (Test-Path $CsprojPath)) {
        return $null
    }
    
    $content = Get-Content $CsprojPath -Raw
    # Try VersionPrefix first (preferred), then fall back to Version
    if ($content -match '<VersionPrefix>(\d+\.\d+\.\d+)</VersionPrefix>') {
        return $matches[1]
    }
    if ($content -match '<Version>(\d+\.\d+\.\d+)</Version>') {
        return $matches[1]
    }
    return $null
}

function Set-ProjectVersion {
    param(
        [string]$CsprojPath,
        [string]$NewVersion
    )
    
    $content = Get-Content $CsprojPath -Raw
    # Update VersionPrefix if it exists, otherwise update Version
    if ($content -match '<VersionPrefix>\d+\.\d+\.\d+</VersionPrefix>') {
        $updatedContent = $content -replace '<VersionPrefix>\d+\.\d+\.\d+</VersionPrefix>', "<VersionPrefix>$NewVersion</VersionPrefix>"
    } else {
        $updatedContent = $content -replace '<Version>\d+\.\d+\.\d+</Version>', "<Version>$NewVersion</Version>"
    }
    Set-Content -Path $CsprojPath -Value $updatedContent -NoNewline
}

function Get-IncrementedVersion {
    param(
        [string]$CurrentVersion,
        [string]$Part = "Patch"
    )
    
    $versionParts = $CurrentVersion.Split('.')
    $major = [int]$versionParts[0]
    $minor = [int]$versionParts[1]
    $patch = [int]$versionParts[2]
    
    switch ($Part) {
        "Major" {
            $major++
            $minor = 0
            $patch = 0
        }
        "Minor" {
            $minor++
            $patch = 0
        }
        "Patch" {
            $patch++
        }
    }
    
    return "$major.$minor.$patch"
}

function Write-ReinstallTriggerFile {
    param(
        [string]$Version,
        [string]$TriggerFilePath
    )
    
    # Ensure directory exists
    $triggerDir = Split-Path $TriggerFilePath -Parent
    if (-not (Test-Path $triggerDir)) {
        New-Item -ItemType Directory -Path $triggerDir -Force | Out-Null
    }
    
    $content = @"
# ServerMonitor Reinstall Trigger File
# Created by Build-And-Publish.ps1
# 
# This file triggers automatic reinstall in ServerMonitorTrayIcon
# The tray app will compare this version with the installed version
# and only reinstall if they differ.

Version=$Version
BuildDate=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
BuildMachine=$env:COMPUTERNAME
BuildUser=$env:USERNAME
"@
    
    Set-Content -Path $TriggerFilePath -Value $content -Force
    Write-Host "  📄 Trigger file updated: $TriggerFilePath" -ForegroundColor Green
    Write-Host "     Version=$Version" -ForegroundColor Gray
}

# ═══════════════════════════════════════════════════════════════════════════════
# PROJECT DEFINITIONS
# ═══════════════════════════════════════════════════════════════════════════════

$projects = @(
    @{
        Name = "ServerMonitorAgent"
        ProjectPath = Join-Path $projectRoot "ServerMonitorAgent\src\ServerMonitor\ServerMonitor.csproj"
        PublishProfile = "WinApp-FileSystem"
        TargetPath = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitor"
        IsPrimary = $true  # This is the main application whose version triggers reinstall
    },
    @{
        Name = "ServerMonitorTrayIcon"
        ProjectPath = Join-Path $projectRoot "ServerMonitorTrayIcon\src\ServerMonitorTrayIcon\ServerMonitorTrayIcon.csproj"
        PublishProfile = "WinApp-FileSystem"
        TargetPath = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitorTrayIcon"
        IsPrimary = $false
    },
    @{
        Name = "ServerMonitorDashboard"
        ProjectPath = Join-Path $projectRoot "ServerMonitorDashboard\src\ServerMonitorDashboard\ServerMonitorDashboard.csproj"
        PublishProfile = "WebApp-FileSystem"
        TargetPath = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitorDashboard"
        IsPrimary = $false
    },
    @{
        Name = "ServerMonitorDashboard.Tray"
        ProjectPath = Join-Path $projectRoot "ServerMonitorDashboard\src\ServerMonitorDashboard.Tray\ServerMonitorDashboard.Tray.csproj"
        PublishProfile = $null
        TargetPath = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitorDashboard.Tray"
        IsPrimary = $false
        MsiProject = $true
    }
)

# ═══════════════════════════════════════════════════════════════════════════════
# VERSION INCREMENT
# All projects use the same version, based on ServerMonitorAgent (primary project)
# Only the Agent version is incremented, all others are set to match
# ═══════════════════════════════════════════════════════════════════════════════

$newVersion = $null

Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
Write-Host "  Version Management (Incrementing $VersionPart)" -ForegroundColor Yellow
Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
Write-Host ""

# Step 1: Get the primary project (ServerMonitorAgent) and increment its version
$primaryProject = $projects | Where-Object { $_.IsPrimary } | Select-Object -First 1
$currentAgentVersion = Get-ProjectVersion -CsprojPath $primaryProject.ProjectPath

if ($null -eq $currentAgentVersion) {
    Write-Host "  ❌ ERROR: No version found in ServerMonitorAgent csproj" -ForegroundColor Red
    exit 1
}

$newVersion = Get-IncrementedVersion -CurrentVersion $currentAgentVersion -Part $VersionPart
Write-Host "  ServerMonitorAgent: $currentAgentVersion → $newVersion (PRIMARY)" -ForegroundColor Green

# Step 2: Set all projects to the same version as ServerMonitorAgent
foreach ($project in $projects) {
    $currentVersion = Get-ProjectVersion -CsprojPath $project.ProjectPath
    
    if ($null -eq $currentVersion) {
        Write-Host "  ⚠️  $($project.Name): No version found in csproj" -ForegroundColor Yellow
        continue
    }
    
    Set-ProjectVersion -CsprojPath $project.ProjectPath -NewVersion $newVersion
    
    if (-not $project.IsPrimary) {
        if ($currentVersion -ne $newVersion) {
            Write-Host "  $($project.Name): $currentVersion → $newVersion" -ForegroundColor White
        } else {
            Write-Host "  $($project.Name): $newVersion (unchanged)" -ForegroundColor DarkGray
        }
    }
}

Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# BUILD AND PUBLISH
# ═══════════════════════════════════════════════════════════════════════════════

$results = @()

foreach ($project in $projects) {
    $projectStart = Get-Date
    
    Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
    Write-Host "  Building: $($project.Name)" -ForegroundColor Yellow
    Write-Host "  Project:  $($project.ProjectPath)" -ForegroundColor Gray
    if ($project.MsiProject) {
        Write-Host "  Output:   MSI Installer → $($project.TargetPath)" -ForegroundColor Gray
    } else {
        Write-Host "  Profile:  $($project.PublishProfile)" -ForegroundColor Gray
        Write-Host "  Target:   $($project.TargetPath)" -ForegroundColor Gray
    }
    Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
    Write-Host ""
    
    # Verify project file exists
    if (-not (Test-Path $project.ProjectPath)) {
        Write-Host "  ❌ ERROR: Project file not found: $($project.ProjectPath)" -ForegroundColor Red
        $results += @{ Name = $project.Name; Success = $false; Duration = 0; Error = "Project file not found" }
        continue
    }
    
    try {
        if ($project.MsiProject) {
            # ─── MSI PROJECT: publish locally, build WiX installer, copy MSI to target ───
            $trayProjectDir = Split-Path $project.ProjectPath -Parent
            $localPublishDir = Join-Path $trayProjectDir "bin\Release\net10.0-windows\win-x64\publish"
            $installerDir = Join-Path (Split-Path $trayProjectDir -Parent) "ServerMonitorDashboard.Tray.Installer"
            $installerProj = Join-Path $installerDir "ServerMonitorDashboard.Tray.Installer.wixproj"

            # Step 1: Publish the tray app locally (WiX installer consumes from this folder)
            Write-Host "  Step 1/3: Publishing tray app locally..." -ForegroundColor Cyan
            $publishArgs = @(
                "publish", $project.ProjectPath,
                "-c", "Release",
                "-r", "win-x64",
                "--self-contained", "false",
                "-o", $localPublishDir,
                "-v", "minimal"
            )
            Write-Host "  Executing: dotnet $($publishArgs -join ' ')" -ForegroundColor DarkGray
            Write-Host ""
            & dotnet @publishArgs
            if ($LASTEXITCODE -ne 0) { throw "dotnet publish (local) failed with exit code $($LASTEXITCODE)" }

            # Step 2: Update Package.wxs version and build the WiX installer
            Write-Host ""
            Write-Host "  Step 2/3: Building WiX installer (MSI) v$($newVersion)..." -ForegroundColor Cyan
            $packageWxs = Join-Path $installerDir "Package.wxs"
            $wxsContent = Get-Content $packageWxs -Raw
            $wxsContent = $wxsContent -replace 'Version="[\d\.]+"', "Version=`"$($newVersion)`""
            Set-Content -Path $packageWxs -Value $wxsContent -NoNewline

            $buildArgs = @(
                "build", $installerProj,
                "-c", "Release",
                "-v", "minimal"
            )
            Write-Host "  Executing: dotnet $($buildArgs -join ' ')" -ForegroundColor DarkGray
            Write-Host ""
            & dotnet @buildArgs
            if ($LASTEXITCODE -ne 0) { throw "WiX installer build failed with exit code $($LASTEXITCODE)" }

            # Step 3: Copy the MSI to the target folder
            Write-Host ""
            Write-Host "  Step 3/3: Copying MSI to $($project.TargetPath)..." -ForegroundColor Cyan
            $msiSource = Join-Path $installerDir "bin\x64\Release\ServerMonitorDashboard.Tray.Setup.msi"
            if (-not (Test-Path $msiSource)) {
                $msiSource = Get-ChildItem -Path (Join-Path $installerDir "bin") -Filter "*.msi" -Recurse | Select-Object -First 1 -ExpandProperty FullName
            }
            if (-not $msiSource -or -not (Test-Path $msiSource)) {
                throw "MSI file not found after build"
            }
            Copy-Item -Path $msiSource -Destination $project.TargetPath -Force
            $msiName = Split-Path $msiSource -Leaf
            Write-Host "  ✅ $msiName → $($project.TargetPath)\$msiName" -ForegroundColor Green

            $duration = [math]::Round(((Get-Date) - $projectStart).TotalSeconds, 1)
            Write-Host ""
            Write-Host "  ✅ $($project.Name) MSI published successfully! ($(${duration})s)" -ForegroundColor Green
            Write-Host ""
            $results += @{ Name = $project.Name; Success = $true; Duration = $duration; Error = $null }
        }
        else {
            # ─── STANDARD PROJECT: publish with profile directly to target ───
            $publishArgs = @(
                "publish"
                $project.ProjectPath
                "/p:PublishProfile=$($project.PublishProfile)"
                "-v", "minimal"
            )
            
            Write-Host "  Executing: dotnet $($publishArgs -join ' ')" -ForegroundColor DarkGray
            Write-Host ""
            
            & dotnet @publishArgs
            
            if ($LASTEXITCODE -ne 0) {
                throw "dotnet publish failed with exit code $LASTEXITCODE"
            }
            
            $duration = [math]::Round(((Get-Date) - $projectStart).TotalSeconds, 1)
            Write-Host ""
            Write-Host "  ✅ $($project.Name) published successfully! ($(${duration})s)" -ForegroundColor Green
            Write-Host ""
            
            $results += @{ Name = $project.Name; Success = $true; Duration = $duration; Error = $null }
        }
    }
    catch {
        $duration = [math]::Round(((Get-Date) - $projectStart).TotalSeconds, 1)
        Write-Host ""
        Write-Host "  ❌ $($project.Name) failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        
        $results += @{ Name = $project.Name; Success = $false; Duration = $duration; Error = $_.Exception.Message }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# SIGN PUBLISHED EXECUTABLES
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Magenta
Write-Host "  Signing Published Files (EXE + MSI)" -ForegroundColor Magenta
Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Magenta
Write-Host ""

$filesToSign = @(
    "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitor\ServerMonitor.exe",
    "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitorTrayIcon\ServerMonitorTrayIcon.exe",
    "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitorDashboard\ServerMonitorDashboard.exe"
)

# Find the MSI file in the Dashboard.Tray target folder
$msiTarget = Get-ChildItem -Path "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitorDashboard.Tray" -Filter "*.msi" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($msiTarget) {
    $filesToSign += $msiTarget.FullName
}

$DedgeSignPath = "dedge-server.DEDGE.fk.no\DedgeCommon\Software\DedgePshApps\DedgeSign\DedgeSign.ps1"

foreach ($fileToSign in $filesToSign) {
    if (Test-Path $fileToSign) {
        $sig = Get-AuthenticodeSignature -FilePath $fileToSign -ErrorAction SilentlyContinue
        if ($sig.Status -eq 'Valid') {
            Write-Host "  ✅ Already signed: $(Split-Path -Leaf $fileToSign)" -ForegroundColor Green
            continue
        }
        
        Write-Host "  🔐 Signing: $(Split-Path -Leaf $fileToSign)..." -ForegroundColor Yellow
        try {
            & pwsh.exe -ExecutionPolicy Bypass -File $DedgeSignPath -Path $fileToSign -Action Add -NoConfirm 2>&1 | Out-Null
            
            $sigAfter = Get-AuthenticodeSignature -FilePath $fileToSign -ErrorAction SilentlyContinue
            if ($sigAfter.Status -eq 'Valid') {
                Write-Host "  ✅ Signed successfully: $(Split-Path -Leaf $fileToSign)" -ForegroundColor Green
            }
            else {
                Write-Host "  ⚠️  Signing may have failed for: $(Split-Path -Leaf $fileToSign) (Status: $($sigAfter.Status))" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "  ⚠️  Could not sign: $(Split-Path -Leaf $fileToSign) - $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "  ⚠️  File not found: $fileToSign" -ForegroundColor Yellow
    }
}

Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# VERIFY PUBLISHED VERSIONS
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
Write-Host "  Verifying Published Versions" -ForegroundColor Cyan
Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
Write-Host ""

$verifyApps = @(
    @{ Name = "ServerMonitor"; Path = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitor\ServerMonitor.exe"; IsMsi = $false },
    @{ Name = "ServerMonitorTrayIcon"; Path = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitorTrayIcon\ServerMonitorTrayIcon.exe"; IsMsi = $false },
    @{ Name = "ServerMonitorDashboard"; Path = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitorDashboard\ServerMonitorDashboard.exe"; IsMsi = $false },
    @{ Name = "ServerMonitorDashboard.Tray"; Path = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitorDashboard.Tray"; IsMsi = $true }
)

foreach ($app in $verifyApps) {
    if ($app.IsMsi) {
        $msiFile = Get-ChildItem -Path $app.Path -Filter "*.msi" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($msiFile) {
            $sizeMB = [math]::Round($msiFile.Length / 1MB, 1)
            Write-Host "  $($app.Name): $($msiFile.Name) ($(${sizeMB}) MB)" -ForegroundColor Green
        } else {
            Write-Host "  $($app.Name): ❌ MSI NOT FOUND in $($app.Path)" -ForegroundColor Red
        }
    }
    elseif (Test-Path $app.Path) {
        $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($app.Path)
        $sig = Get-AuthenticodeSignature $app.Path -ErrorAction SilentlyContinue
        $sigStatus = if ($sig.Status -eq 'Valid') { "✅ Signed" } else { "⚠️ $($sig.Status)" }
        Write-Host "  $($app.Name): v$($vi.FileVersion) $sigStatus" -ForegroundColor $(if ($sig.Status -eq 'Valid') { 'Green' } else { 'Yellow' })
    } else {
        Write-Host "  $($app.Name): ❌ NOT FOUND at $($app.Path)" -ForegroundColor Red
    }
}
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# CREATE REINSTALL TRIGGER FILE (After all builds complete)
# ═══════════════════════════════════════════════════════════════════════════════

$allSucceeded = ($results | Where-Object { -not $_.Success }).Count -eq 0

if ($allSucceeded -and $newVersion) {
    Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
    Write-Host "  Creating Reinstall Trigger File (New File for FileSystemWatcher)" -ForegroundColor Yellow
    Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
    Write-Host ""
    
    try {
        # Create Agent trigger file
        Write-ReinstallTriggerFile -Version $newVersion -TriggerFilePath $ReinstallTriggerFile
        Write-Host ""
    }
    catch {
        Write-Host "  ⚠️  Could not create trigger file: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host ""
    }
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
    Write-Host "  📦 Version: $newVersion" -ForegroundColor Cyan
    Write-Host ""
}

foreach ($result in $results) {
    $icon = if ($result.Success) { "✅" } else { "❌" }
    $color = if ($result.Success) { "Green" } else { "Red" }
    $status = if ($result.Success) { "SUCCESS" } else { "FAILED" }
    Write-Host "  $icon $($result.Name): $status ($($result.Duration)s)" -ForegroundColor $color
    if ($result.Error) {
        Write-Host "     Error: $($result.Error)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Gray
Write-Host "  Total: $successCount succeeded, $failCount failed | Duration: $(${totalDuration})s" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Yellow" })
Write-Host "  Finished: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

if ($allSucceeded -and $newVersion) {
    Write-Host ""
    Write-Host "  📄 Agent trigger: $ReinstallTriggerFile" -ForegroundColor Cyan
    Write-Host "     Agent and tray will auto-update to v$newVersion" -ForegroundColor Gray
    Write-Host "  ℹ️  Dashboard: deploy via IIS-DeployApp.ps1 -SiteName ServerMonitorDashboard" -ForegroundColor DarkGray
}

Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Exit with error if any failed
if ($failCount -gt 0) {
    exit 1
}

# Deployment is handled by IIS-DeployApp.ps1 -SiteName ServerMonitorDashboard
# See: C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\IIS-DeployApp.ps1
