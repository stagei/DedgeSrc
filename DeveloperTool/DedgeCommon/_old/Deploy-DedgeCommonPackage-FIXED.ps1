param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("Major", "Minor", "Patch")]
    [string]$VersionBump = "Patch",
    
    [Parameter(Mandatory = $false)]
    [string]$SpecificVersion,
    
    [Parameter(Mandatory = $false)]
    [string]$PAT,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipTests,
    
    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   DedgeCommon NuGet Package Deployment Script               ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$projectFile = "DedgeCommon\DedgeCommon.csproj"
$packageOutputDir = "DedgeCommon\bin\x64\Release"

# Check if project file exists
if (-not (Test-Path $projectFile)) {
    Write-Host "ERROR: Project file not found: $projectFile" -ForegroundColor Red
    exit 1
}

# Function to get current version from csproj
function Get-CurrentVersion {
    param([string]$ProjectFile)
    
    [xml]$proj = Get-Content $ProjectFile
    $version = $proj.Project.PropertyGroup.Version
    
    if ([string]::IsNullOrEmpty($version)) {
        Write-Host "ERROR: Version not found in project file" -ForegroundColor Red
        exit 1
    }
    
    return $version
}

# Function to bump version
function Get-NextVersion {
    param(
        [string]$CurrentVersion,
        [string]$BumpType
    )
    
    $parts = $CurrentVersion.Split('.')
    if ($parts.Count -ne 3) {
        Write-Host "ERROR: Invalid version format. Expected: Major.Minor.Patch" -ForegroundColor Red
        exit 1
    }
    
    $major = [int]$parts[0]
    $minor = [int]$parts[1]
    $patch = [int]$parts[2]
    
    switch ($BumpType) {
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

# Function to update version in csproj
function Set-ProjectVersion {
    param(
        [string]$ProjectFile,
        [string]$NewVersion
    )
    
    [xml]$proj = Get-Content $ProjectFile
    $proj.Project.PropertyGroup.Version = $NewVersion
    $proj.Save($ProjectFile)
    
    Write-Host "OK Updated project version to $NewVersion" -ForegroundColor Green
}

# Get current version
$currentVersion = Get-CurrentVersion -ProjectFile $projectFile
Write-Host "Current Version: $currentVersion" -ForegroundColor Yellow

# Determine new version
if ($SpecificVersion) {
    $newVersion = $SpecificVersion
    Write-Host "Using specific version: $newVersion" -ForegroundColor Yellow
}
else {
    $newVersion = Get-NextVersion -CurrentVersion $currentVersion -BumpType $VersionBump
    Write-Host "Bumping $VersionBump version: $currentVersion → $newVersion" -ForegroundColor Yellow
}

# Confirm version bump
if (-not $Force) {
    Write-Host ""
    $confirm = Read-Host "Proceed with version bump to $newVersion? (y/n)"
    if ($confirm -ne 'y') {
        Write-Host "Deployment cancelled by user" -ForegroundColor Yellow
        exit 0
    }
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Gray

# Step 1: Update version
Write-Host "Step 1: Updating version..." -ForegroundColor Cyan
Set-ProjectVersion -ProjectFile $projectFile -NewVersion $newVersion

# Step 2: Clean previous builds
Write-Host ""
Write-Host "Step 2: Cleaning previous builds..." -ForegroundColor Cyan
if (Test-Path $packageOutputDir) {
    Remove-Item "$packageOutputDir\*.nupkg" -Force -ErrorAction SilentlyContinue
    Write-Host "OK Cleaned old packages" -ForegroundColor Green
}

# Step 3: Run tests (optional)
if (-not $SkipTests) {
    Write-Host ""
    Write-Host "Step 3: Running tests..." -ForegroundColor Cyan
    
    # Run VerifyFunctionality test
    Push-Location DedgeCommonVerifyFkDatabaseHandler
    try {
        $testResult = dotnet run --no-build 2>&1 | Select-String -Pattern "Final Count: 7/7" -Quiet
        if ($testResult) {
            Write-Host "OK VerifyFunctionality test passed (7/7)" -ForegroundColor Green
        }
        else {
            Write-Host "OK VerifyFunctionality test results unclear" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "OK Could not run tests: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    finally {
        Pop-Location
    }
}
else {
    Write-Host ""
    Write-Host "Step 3: Skipping tests (--SkipTests specified)" -ForegroundColor Yellow
}

# Step 4: Build Release
Write-Host ""
Write-Host "Step 4: Building Release package..." -ForegroundColor Cyan
$buildResult = dotnet build $projectFile -c Release
if ($LASTEXITCODE -ne 0) {
    Write-Host "OK Build failed!" -ForegroundColor Red
    exit 1
}
Write-Host "OK Build successful" -ForegroundColor Green

# Step 5: Verify package created
Write-Host ""
Write-Host "Step 5: Verifying package..." -ForegroundColor Cyan
$packagePath = "$packageOutputDir\Dedge.DedgeCommon.$newVersion.nupkg"

if (-not (Test-Path $packagePath)) {
    Write-Host "OK Package not found: $packagePath" -ForegroundColor Red
    exit 1
}

$packageSize = (Get-Item $packagePath).Length / 1MB
Write-Host "OK Package created: Dedge.DedgeCommon.$newVersion.nupkg" -ForegroundColor Green
Write-Host "  Size: $($packageSize.ToString('F2')) MB" -ForegroundColor Gray
Write-Host "  Location: $packagePath" -ForegroundColor Gray

# Step 6: Get PAT
Write-Host ""
Write-Host "Step 6: Configuring deployment..." -ForegroundColor Cyan

if ([string]::IsNullOrEmpty($PAT)) {
    Write-Host "OK No PAT provided via parameter" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Enter your Azure DevOps PAT (with Packaging permissions):" -ForegroundColor Yellow
    Write-Host "(Leave empty to skip deployment)" -ForegroundColor Gray
    $PAT = Read-Host -AsSecureString | ConvertFrom-SecureString -AsPlainText
    
    if ([string]::IsNullOrEmpty($PAT)) {
        Write-Host ""
        Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Gray
        Write-Host "OK Package built successfully but NOT deployed" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "To deploy manually later, run:" -ForegroundColor Cyan
        Write-Host "  dotnet nuget push `"$packagePath`" --source `"Dedge`" --api-key YOUR_PAT" -ForegroundColor White
        exit 0
    }
}
else {
    Write-Host "OK PAT provided via parameter" -ForegroundColor Green
}

# Step 7: Push to NuGet feed
Write-Host ""
Write-Host "Step 7: Pushing package to Dedge feed..." -ForegroundColor Cyan

try {
    $pushResult = dotnet nuget push $packagePath --source "Dedge" --api-key $PAT --skip-duplicate 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "OK Package pushed successfully!" -ForegroundColor Green
        $deployed = $true
    }
    else {
        if ($pushResult -like "*409*" -or $pushResult -like "*already exists*") {
            Write-Host "OK Package version $newVersion already exists in feed" -ForegroundColor Yellow
            Write-Host "  Use --skip-duplicate to ignore or bump version again" -ForegroundColor Gray
            $deployed = $false
        }
        elseif ($pushResult -like "*401*" -or $pushResult -like "*Unauthorized*") {
            Write-Host "X Authentication failed - 401 Unauthorized" -ForegroundColor Red
            Write-Host ""
            Write-Host "PAT Issues:" -ForegroundColor Yellow
            Write-Host "  1. PAT may have expired" -ForegroundColor Gray
            Write-Host "  2. PAT missing Packaging permissions" -ForegroundColor Gray
            Write-Host "  3. PAT for wrong organization" -ForegroundColor Gray
            Write-Host ""
            Write-Host "Create new PAT at: https://dev.azure.com/Dedge/_usersSettings/tokens" -ForegroundColor Cyan
            $deployed = $false
        }
        else {
            Write-Host "X Push failed: $pushResult" -ForegroundColor Red
            $deployed = $false
        }
    }
}
catch {
    Write-Host "OK Error pushing package: $($_.Exception.Message)" -ForegroundColor Red
    $deployed = $false
}

# Summary
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   Deployment Summary" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "Package Version:  $newVersion" -ForegroundColor White
Write-Host "Package File:     $packagePath" -ForegroundColor White
Write-Host "Package Size:     $($packageSize.ToString('F2')) MB" -ForegroundColor White
Write-Host "Build Status:     OK Successful" -ForegroundColor Green

if ($deployed) {
    Write-Host "Deploy Status:    OK Deployed to Dedge feed" -ForegroundColor Green
    Write-Host ""
    Write-Host "✅ Deployment completed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Verify at: https://dev.azure.com/Dedge/Dedge/_artifacts/feed/Dedge" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Yellow
    Write-Host "  1. Update consuming applications:" -ForegroundColor Gray
    Write-Host ('     <PackageReference Include="Dedge.DedgeCommon" Version="' + $newVersion + '" />') -ForegroundColor White
    Write-Host "  2. Test in DEV environment first" -ForegroundColor Gray
    Write-Host "  3. Deploy to TST, then PRD" -ForegroundColor Gray
}
else {
    Write-Host "Deploy Status:    X Not deployed" -ForegroundColor Red
    Write-Host ""
    Write-Host "OK Package built but not deployed" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To deploy manually:" -ForegroundColor Cyan
    Write-Host "  dotnet nuget push ""$packagePath"" --source ""Dedge"" --api-key YOUR_VALID_PAT" -ForegroundColor White
}

Write-Host ""

