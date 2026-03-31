#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Builds and publishes DbExplorer with auto-incrementing version and MSI installer
.DESCRIPTION
    - Auto-increments version numbers in DbExplorer.csproj, DbExplorerTray.csproj, and Package.wxs
    - Publishes DbExplorer (self-contained win-x64)
    - Builds WiX MSI installer
    - Signs EXE and MSI (FK users only)
    - Copies MSI to network share: C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\DbExplorer
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

$projectRoot = $PSScriptRoot
$deployShare = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\DbExplorer"
$DedgeSignPath = "dedge-server.DEDGE.fk.no\DedgeCommon\Software\DedgePshApps\DedgeSign\DedgeSign.ps1"

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  DbExplorer Build & Publish Script" -ForegroundColor Cyan
Write-Host "  Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# KILL RUNNING INSTANCES
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  Stopping Running Instances" -ForegroundColor DarkGray
Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

Stop-Process -Name "DbExplorer" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "DbExplorerTray" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Write-Host "  Done" -ForegroundColor DarkGray
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

    $content = $content -replace '<VersionPrefix>\d+\.\d+\.\d+</VersionPrefix>', "<VersionPrefix>$NewVersion</VersionPrefix>"
    $content = $content -replace '<Version>\d+\.\d+\.\d+</Version>', "<Version>$NewVersion</Version>"

    $fourPart = "$NewVersion.0"
    $content = $content -replace '<AssemblyVersion>[\d\.]+</AssemblyVersion>', "<AssemblyVersion>$fourPart</AssemblyVersion>"
    $content = $content -replace '<FileVersion>[\d\.]+</FileVersion>', "<FileVersion>$fourPart</FileVersion>"

    Set-Content -Path $CsprojPath -Value $content -NoNewline
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

function Set-WxsVersion {
    param(
        [string]$WxsPath,
        [string]$NewVersion
    )

    $content = Get-Content $WxsPath -Raw
    # Regex: match Version="x.y.z" inside the <Package> element
    # Version="<digits>.<digits>.<digits>"
    $content = $content -replace 'Version="\d+\.\d+\.\d+"', "Version=`"$NewVersion`""
    Set-Content -Path $WxsPath -Value $content -NoNewline
}

# ═══════════════════════════════════════════════════════════════════════════════
# PROJECT DEFINITIONS
# ═══════════════════════════════════════════════════════════════════════════════

$mainCsproj   = Join-Path $projectRoot "DbExplorer.csproj"
$trayCsproj   = Join-Path $projectRoot "DbExplorerTray\DbExplorerTray.csproj"
$installerDir = Join-Path $projectRoot "DbExplorer.Installer"
$installerProj = Join-Path $installerDir "DbExplorer.Installer.wixproj"
$packageWxs   = Join-Path $installerDir "Package.wxs"
$publishDir   = Join-Path $projectRoot "bin\Release\net10.0-windows\win-x64\publish"

# ═══════════════════════════════════════════════════════════════════════════════
# VERSION INCREMENT
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
Write-Host "  Version Management (Incrementing $VersionPart)" -ForegroundColor Yellow
Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
Write-Host ""

$currentVersion = Get-ProjectVersion -CsprojPath $mainCsproj
if ($null -eq $currentVersion) {
    Write-Host "  ❌ ERROR: No version found in $($mainCsproj)" -ForegroundColor Red
    exit 1
}

$newVersion = Get-IncrementedVersion -CurrentVersion $currentVersion -Part $VersionPart
Write-Host "  DbExplorer:     $currentVersion → $newVersion (PRIMARY)" -ForegroundColor Green

Set-ProjectVersion -CsprojPath $mainCsproj -NewVersion $newVersion

# Update tray project to same version
$trayCurrentVersion = Get-ProjectVersion -CsprojPath $trayCsproj
if ($null -ne $trayCurrentVersion) {
    Set-ProjectVersion -CsprojPath $trayCsproj -NewVersion $newVersion
    Write-Host "  DbExplorerTray: $trayCurrentVersion → $newVersion" -ForegroundColor White
}
else {
    Write-Host "  DbExplorerTray: ⚠️  No version found in csproj" -ForegroundColor Yellow
}

# Update Package.wxs version
Set-WxsVersion -WxsPath $packageWxs -NewVersion $newVersion
Write-Host "  Package.wxs:    → $newVersion" -ForegroundColor White
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1: PUBLISH DBEXPLORER (self-contained)
# ═══════════════════════════════════════════════════════════════════════════════

$results = @()
$stepStart = Get-Date

Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
Write-Host "  Step 1/3: Publishing DbExplorer (self-contained win-x64)" -ForegroundColor Yellow
Write-Host "  Project:  $mainCsproj" -ForegroundColor Gray
Write-Host "  Output:   $publishDir" -ForegroundColor Gray
Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
Write-Host ""

try {
    $publishArgs = @(
        "publish", $mainCsproj,
        "-c", "Release",
        "-r", "win-x64",
        "--self-contained", "true",
        "-p:PublishReadyToRun=true",
        "-o", $publishDir,
        "-v", "minimal"
    )
    Write-Host "  Executing: dotnet $($publishArgs -join ' ')" -ForegroundColor DarkGray
    Write-Host ""
    & dotnet @publishArgs
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit code $($LASTEXITCODE)" }

    $duration = [math]::Round(((Get-Date) - $stepStart).TotalSeconds, 1)
    Write-Host ""
    Write-Host "  ✅ DbExplorer published successfully! ($(${duration})s)" -ForegroundColor Green
    Write-Host ""
    $results += @{ Name = "DbExplorer (publish)"; Success = $true; Duration = $duration; Error = $null }
}
catch {
    $duration = [math]::Round(((Get-Date) - $stepStart).TotalSeconds, 1)
    Write-Host ""
    Write-Host "  ❌ DbExplorer publish failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    $results += @{ Name = "DbExplorer (publish)"; Success = $false; Duration = $duration; Error = $_.Exception.Message }
    Write-Host "  Aborting — cannot build installer without published files." -ForegroundColor Red
    exit 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2: BUILD WIX INSTALLER (MSI)
# ═══════════════════════════════════════════════════════════════════════════════

$stepStart = Get-Date

Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
Write-Host "  Step 2/3: Building WiX installer (MSI) v$newVersion" -ForegroundColor Yellow
Write-Host "  Project:  $installerProj" -ForegroundColor Gray
Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
Write-Host ""

try {
    $buildArgs = @(
        "build", $installerProj,
        "-c", "Release",
        "-v", "minimal"
    )
    Write-Host "  Executing: dotnet $($buildArgs -join ' ')" -ForegroundColor DarkGray
    Write-Host ""
    & dotnet @buildArgs
    if ($LASTEXITCODE -ne 0) { throw "WiX installer build failed with exit code $($LASTEXITCODE)" }

    $duration = [math]::Round(((Get-Date) - $stepStart).TotalSeconds, 1)
    Write-Host ""
    Write-Host "  ✅ WiX installer built successfully! ($(${duration})s)" -ForegroundColor Green
    Write-Host ""
    $results += @{ Name = "WiX Installer (build)"; Success = $true; Duration = $duration; Error = $null }
}
catch {
    $duration = [math]::Round(((Get-Date) - $stepStart).TotalSeconds, 1)
    Write-Host ""
    Write-Host "  ❌ WiX installer build failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    $results += @{ Name = "WiX Installer (build)"; Success = $false; Duration = $duration; Error = $_.Exception.Message }
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 3: SIGN AND DEPLOY MSI TO NETWORK SHARE
# ═══════════════════════════════════════════════════════════════════════════════

$stepStart = Get-Date

Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
Write-Host "  Step 3/3: Sign and deploy to $deployShare" -ForegroundColor Yellow
Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
Write-Host ""

$msiSource = Join-Path $installerDir "bin\x64\Release\DbExplorer.Setup.msi"
if (-not (Test-Path $msiSource)) {
    $msiSource = Get-ChildItem -Path (Join-Path $installerDir "bin") -Filter "*.msi" -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
}

if (-not $msiSource -or -not (Test-Path $msiSource)) {
    Write-Host "  ❌ MSI file not found after build — skipping deploy" -ForegroundColor Red
    $results += @{ Name = "Deploy MSI"; Success = $false; Duration = 0; Error = "MSI file not found" }
}
else {
    # Sign the MSI
    $isFkUser = $env:USERNAME -match '^FK'
    if ($isFkUser -and (Test-Path $DedgeSignPath)) {
        Write-Host "  🔐 Signing MSI: $(Split-Path -Leaf $msiSource)..." -ForegroundColor Yellow
        try {
            & pwsh.exe -ExecutionPolicy Bypass -File $DedgeSignPath -Path $msiSource -Action Add -NoConfirm 2>&1 | Out-Null
            $sigAfter = Get-AuthenticodeSignature -FilePath $msiSource -ErrorAction SilentlyContinue
            if ($sigAfter.Status -eq 'Valid') {
                Write-Host "  ✅ MSI signed successfully" -ForegroundColor Green
            }
            else {
                Write-Host "  ⚠️  MSI signing status: $($sigAfter.Status)" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "  ⚠️  Could not sign MSI: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "  ℹ️  Skipping code signing (non-FK user or sign script not available)" -ForegroundColor DarkGray
    }

    # Copy MSI to network share
    try {
        if (-not (Test-Path $deployShare)) {
            New-Item -ItemType Directory -Path $deployShare -Force | Out-Null
        }

        Copy-Item -Path $msiSource -Destination $deployShare -Force
        $msiName = Split-Path $msiSource -Leaf
        $sizeMB = [math]::Round((Get-Item $msiSource).Length / 1MB, 1)

        Write-Host "  ✅ $msiName ($(${sizeMB}) MB) → $deployShare" -ForegroundColor Green

        $duration = [math]::Round(((Get-Date) - $stepStart).TotalSeconds, 1)
        $results += @{ Name = "Deploy MSI"; Success = $true; Duration = $duration; Error = $null }
    }
    catch {
        $duration = [math]::Round(((Get-Date) - $stepStart).TotalSeconds, 1)
        Write-Host "  ❌ Failed to copy MSI to share: $($_.Exception.Message)" -ForegroundColor Red
        $results += @{ Name = "Deploy MSI"; Success = $false; Duration = $duration; Error = $_.Exception.Message }
    }
}

Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# VERIFY PUBLISHED VERSION
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
Write-Host "  Verifying Published Artifacts" -ForegroundColor Cyan
Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
Write-Host ""

$publishedExe = Join-Path $publishDir "DbExplorer.exe"
if (Test-Path $publishedExe) {
    $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($publishedExe)
    Write-Host "  DbExplorer.exe: v$($vi.FileVersion)" -ForegroundColor Green
}
else {
    Write-Host "  DbExplorer.exe: ❌ NOT FOUND in publish folder" -ForegroundColor Red
}

$deployedMsi = Join-Path $deployShare "DbExplorer.Setup.msi"
if (Test-Path $deployedMsi) {
    $sizeMB = [math]::Round((Get-Item $deployedMsi).Length / 1MB, 1)
    $sig = Get-AuthenticodeSignature $deployedMsi -ErrorAction SilentlyContinue
    $sigStatus = if ($sig.Status -eq 'Valid') { "✅ Signed" } else { "⚠️ $($sig.Status)" }
    Write-Host "  DbExplorer.Setup.msi: $(${sizeMB}) MB $sigStatus" -ForegroundColor $(if ($sig.Status -eq 'Valid') { 'Green' } else { 'Yellow' })
}
else {
    Write-Host "  DbExplorer.Setup.msi: ❌ NOT FOUND on share" -ForegroundColor Red
}

Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════

$totalDuration = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
$successCount = ($results | Where-Object { $_.Success }).Count
$failCount = ($results | Where-Object { -not $_.Success }).Count

Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Build Summary" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  📦 Version: $newVersion" -ForegroundColor Cyan
Write-Host ""

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
Write-Host "  Deploy:   $deployShare" -ForegroundColor Gray
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

if ($failCount -gt 0) {
    exit 1
}
