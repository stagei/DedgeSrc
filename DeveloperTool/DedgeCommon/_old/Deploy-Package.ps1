param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("Major", "Minor", "Patch")]
    [string]$VersionBump = "Patch",
    
    [Parameter(Mandatory = $false)]
    [string]$SpecificVersion,
    
    [Parameter(Mandatory = $false)]
    [string]$PAT,
    
    [Parameter(Mandatory = $false)]
    [switch]$Force
)

# DedgeCommon-specific wrapper for generic Deploy-NuGetPackage.ps1
Write-Host ""
Write-Host "=== DedgeCommon NuGet Package Deployment ===" -ForegroundColor Cyan
Write-Host ""

# Call generic script with DedgeCommon-specific parameters
$scriptParams = @{
    ProjectFile = "DedgeCommon\DedgeCommon.csproj"
    ConfigFileName = "DedgeCommonNuget.json"
    NuGetSource = "Dedge"
    VersionBump = $VersionBump
    Force = $Force
}

if ($SpecificVersion) {
    $scriptParams.SpecificVersion = $SpecificVersion
}

if ($PAT) {
    $scriptParams.PAT = $PAT
}

& "$PSScriptRoot\Deploy-NuGetPackage.ps1" @scriptParams

# Check project file
if (-not (Test-Path $projectFile)) {
    Write-Host "ERROR: Project file not found: $projectFile" -ForegroundColor Red
    exit 1
}

# Get current version
[xml]$proj = Get-Content $projectFile
$currentVersion = $proj.Project.PropertyGroup.Version
Write-Host "Current Version: $currentVersion" -ForegroundColor Yellow

# Determine new version
if ($SpecificVersion) {
    $newVersion = $SpecificVersion
}
else {
    $parts = $currentVersion.Split('.')
    $major = [int]$parts[0]
    $minor = [int]$parts[1]
    $patch = [int]$parts[2]
    
    switch ($VersionBump) {
        "Major" { $major++; $minor = 0; $patch = 0 }
        "Minor" { $minor++; $patch = 0 }
        "Patch" { $patch++ }
    }
    
    $newVersion = "$major.$minor.$patch"
}

Write-Host "New Version: $newVersion" -ForegroundColor Yellow

# Confirm
if (-not $Force) {
    $confirm = Read-Host "`nProceed with version $newVersion (y/n)"
    if ($confirm -ne 'y') {
        Write-Host "Cancelled" -ForegroundColor Yellow
        exit 0
    }
}

# Update version
Write-Host "`nStep 1: Updating version..." -ForegroundColor Cyan
$proj.Project.PropertyGroup.Version = $newVersion
$proj.Save($projectFile)
Write-Host "  [OK] Version updated to $newVersion" -ForegroundColor Green

# Clean old packages
Write-Host "`nStep 2: Cleaning old packages..." -ForegroundColor Cyan
Remove-Item "$packageOutputDir\*.nupkg" -Force -ErrorAction SilentlyContinue
Write-Host "  [OK] Old packages cleaned" -ForegroundColor Green

# Build Release
Write-Host "`nStep 3: Building Release..." -ForegroundColor Cyan
$buildOutput = dotnet build $projectFile -c Release 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "  [ERROR] Build failed" -ForegroundColor Red
    Write-Host $buildOutput
    exit 1
}
Write-Host "  [OK] Build successful" -ForegroundColor Green

# Verify package
Write-Host "`nStep 4: Verifying package..." -ForegroundColor Cyan
$packagePath = "$packageOutputDir\Dedge.DedgeCommon.$newVersion.nupkg"

if (-not (Test-Path $packagePath)) {
    Write-Host "  [ERROR] Package not found: $packagePath" -ForegroundColor Red
    exit 1
}

$packageSize = (Get-Item $packagePath).Length / 1MB
Write-Host "  [OK] Package created" -ForegroundColor Green
Write-Host "  Size: $($packageSize.ToString('F2')) MB" -ForegroundColor Gray
Write-Host "  Location: $packagePath" -ForegroundColor Gray

# Get PAT
Write-Host "`nStep 5: Getting PAT..." -ForegroundColor Cyan

if ([string]::IsNullOrEmpty($PAT)) {
    # Try to load from config file
    $configPath = Join-Path $env:OneDriveCommercial "Documents\DedgeCommonNuget.json"
    
    if (Test-Path $configPath) {
        Write-Host "  Loading from: $configPath" -ForegroundColor Gray
        try {
            $config = Get-Content $configPath -Raw | ConvertFrom-Json
            $PAT = $config.PAT
            Write-Host "  [OK] PAT loaded from config" -ForegroundColor Green
            Write-Host "  Email: $($config.Email)" -ForegroundColor Gray
        }
        catch {
            Write-Host "  [WARNING] Could not load config: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    
    # If still no PAT, prompt
    if ([string]::IsNullOrEmpty($PAT)) {
        Write-Host "  Enter PAT (or press Enter to skip):" -ForegroundColor Yellow
        $PAT = Read-Host
        
        if ([string]::IsNullOrEmpty($PAT)) {
            Write-Host "`n[INFO] Package built but NOT deployed" -ForegroundColor Yellow
            Write-Host "To deploy: .\Deploy-Package.ps1 -PAT YOUR_PAT" -ForegroundColor Cyan
            exit 0
        }
    }
}
else {
    Write-Host "  [OK] PAT provided via parameter" -ForegroundColor Green
}

# Push to feed
Write-Host "`nStep 6: Pushing to NuGet feed..." -ForegroundColor Cyan

try {
    $pushOutput = dotnet nuget push $packagePath --source "Dedge" --api-key $PAT --skip-duplicate 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Package pushed successfully!" -ForegroundColor Green
        $deployed = $true
    }
    else {
        if ($pushOutput -like "*401*" -or $pushOutput -like "*Unauthorized*") {
            Write-Host "  [ERROR] Authentication failed (401)" -ForegroundColor Red
            Write-Host "  PAT may be expired or missing Packaging permissions" -ForegroundColor Yellow
            Write-Host "  Create new PAT at: https://dev.azure.com/Dedge/_usersSettings/tokens" -ForegroundColor Cyan
            $deployed = $false
        }
        elseif ($pushOutput -like "*409*") {
            Write-Host "  [INFO] Package $newVersion already exists" -ForegroundColor Yellow
            $deployed = $false
        }
        else {
            Write-Host "  [ERROR] Push failed" -ForegroundColor Red
            Write-Host $pushOutput -ForegroundColor Gray
            $deployed = $false
        }
    }
}
catch {
    Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    $deployed = $false
}

# Summary
Write-Host ""
Write-Host "=== Deployment Summary ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Version:    $newVersion" -ForegroundColor White
Write-Host "Package:    $packagePath" -ForegroundColor White
Write-Host "Size:       $($packageSize.ToString('F2')) MB" -ForegroundColor White
Write-Host "Build:      [OK]" -ForegroundColor Green

if ($deployed) {
    Write-Host "Deploy:     [OK] Deployed to Dedge" -ForegroundColor Green
    Write-Host ""
    Write-Host "[SUCCESS] Package deployed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Verify: https://dev.azure.com/Dedge/Dedge/_artifacts" -ForegroundColor Cyan
}
else {
    Write-Host "Deploy:     [SKIPPED] Not deployed" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "[INFO] Package built but not deployed" -ForegroundColor Yellow
    Write-Host "To deploy: .\Deploy-Package.ps1 -PAT YOUR_PAT" -ForegroundColor Cyan
}

Write-Host ""
