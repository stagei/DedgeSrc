param(
    [Parameter(Mandatory = $false)]
    [string]$ProjectFile = "DedgeCommon\DedgeCommon.csproj",
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("Major", "Minor", "Patch")]
    [string]$VersionBump = "Patch",
    
    [Parameter(Mandatory = $false)]
    [string]$SpecificVersion,
    
    [Parameter(Mandatory = $false)]
    [string]$PAT,
    
    [Parameter(Mandatory = $false)]
    [string]$ConfigFileName,
    
    [Parameter(Mandatory = $false)]
    [string]$NuGetSource = "Dedge",
    
    [Parameter(Mandatory = $false)]
    [switch]$Force,
    
    [Parameter(Mandatory = $false)]
    [switch]$NoOpenBrowser
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "=== Generic NuGet Package Deployment ===" -ForegroundColor Cyan
Write-Host ""

# Resolve project file path
if (-not [System.IO.Path]::IsPathRooted($ProjectFile)) {
    $ProjectFile = Join-Path (Get-Location) $ProjectFile
}

# Check project file
if (-not (Test-Path $ProjectFile)) {
    Write-Host "ERROR: Project file not found: $ProjectFile" -ForegroundColor Red
    exit 1
}

$projectDir = Split-Path $ProjectFile -Parent
$projectName = [System.IO.Path]::GetFileNameWithoutExtension($ProjectFile)

Write-Host "Project: $projectName" -ForegroundColor White
Write-Host "File: $ProjectFile" -ForegroundColor Gray
Write-Host ""

# Get current version
[xml]$proj = Get-Content $ProjectFile
$currentVersion = $proj.Project.PropertyGroup.Version

if ([string]::IsNullOrEmpty($currentVersion)) {
    Write-Host "ERROR: Version not found in project file" -ForegroundColor Red
    Write-Host "Ensure <Version>X.Y.Z</Version> exists in <PropertyGroup>" -ForegroundColor Yellow
    exit 1
}

Write-Host "Current Version: $currentVersion" -ForegroundColor Yellow

# Determine new version
if ($SpecificVersion) {
    # Allow partial versions (e.g., "2.0" becomes "2.0.0")
    $parts = $SpecificVersion.Split('.')
    
    if ($parts.Count -eq 1) {
        # Just major version provided (e.g., "2")
        $newVersion = "$($parts[0]).0.0"
        Write-Host "Target Version:  $newVersion (specified as $SpecificVersion, auto-completed)" -ForegroundColor Yellow
    }
    elseif ($parts.Count -eq 2) {
        # Major.Minor provided (e.g., "2.0")
        $newVersion = "$($parts[0]).$($parts[1]).0"
        Write-Host "Target Version:  $newVersion (specified as $SpecificVersion, auto-completed)" -ForegroundColor Yellow
    }
    elseif ($parts.Count -eq 3) {
        # Full version provided
        $newVersion = $SpecificVersion
        Write-Host "Target Version:  $newVersion (specified)" -ForegroundColor Yellow
    }
    else {
        Write-Host "ERROR: Invalid version format: $SpecificVersion" -ForegroundColor Red
        Write-Host "Expected: Major, Major.Minor, or Major.Minor.Patch" -ForegroundColor Yellow
        exit 1
    }
}
else {
    $parts = $currentVersion.Split('.')
    if ($parts.Count -ne 3) {
        Write-Host "ERROR: Invalid version format. Expected: Major.Minor.Patch" -ForegroundColor Red
        exit 1
    }
    
    $major = [int]$parts[0]
    $minor = [int]$parts[1]
    $patch = [int]$parts[2]
    
    switch ($VersionBump) {
        "Major" { $major++; $minor = 0; $patch = 0 }
        "Minor" { $minor++; $patch = 0 }
        "Patch" { $patch++ }
    }
    
    $newVersion = "$major.$minor.$patch"
    Write-Host "Target Version:  $newVersion ($VersionBump bump)" -ForegroundColor Yellow
}

# Confirm
if (-not $Force) {
    Write-Host ""
    $confirm = Read-Host "Proceed with version bump to $newVersion? (y/n)"
    if ($confirm -ne 'y') {
        Write-Host "Cancelled by user" -ForegroundColor Yellow
        exit 0
    }
}

Write-Host ""
Write-Host "=" * 63 -ForegroundColor Gray

# Step 1: Update version
Write-Host "`nStep 1: Updating version..." -ForegroundColor Cyan
$proj.Project.PropertyGroup.Version = $newVersion
$proj.Save($ProjectFile)
Write-Host "  [OK] Version updated to $newVersion" -ForegroundColor Green

# Step 2: Clean old packages
Write-Host "`nStep 2: Cleaning old packages..." -ForegroundColor Cyan

# Find output directory (check for bin\Release or bin\x64\Release)
$possibleDirs = @(
    (Join-Path $projectDir "bin\Release"),
    (Join-Path $projectDir "bin\x64\Release"),
    (Join-Path $projectDir "bin\Debug"),
    (Join-Path $projectDir "bin\x64\Debug")
)

$packageOutputDir = $null
foreach ($dir in $possibleDirs) {
    if (Test-Path $dir) {
        $packageOutputDir = $dir
        break
    }
}

if ($packageOutputDir) {
    Remove-Item "$packageOutputDir\*.nupkg" -Force -ErrorAction SilentlyContinue
    Write-Host "  [OK] Cleaned old packages from: $packageOutputDir" -ForegroundColor Green
}
else {
    Write-Host "  [INFO] No previous packages found" -ForegroundColor Gray
}

# Step 3: Build Release
Write-Host "`nStep 3: Building Release..." -ForegroundColor Cyan
Write-Host "  Building: $ProjectFile" -ForegroundColor Gray

$buildOutput = dotnet build $ProjectFile -c Release 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "  [ERROR] Build failed" -ForegroundColor Red
    Write-Host $buildOutput
    exit 1
}
Write-Host "  [OK] Build successful" -ForegroundColor Green

# Step 4: Find and verify package
Write-Host "`nStep 4: Locating package..." -ForegroundColor Cyan

# Get PackageId from project file (or use project name)
$packageId = $proj.Project.PropertyGroup.PackageId
if ([string]::IsNullOrEmpty($packageId)) {
    $packageId = $projectName
}

# Search for package in possible locations
$packagePath = $null
$searchDirs = @(
    (Join-Path $projectDir "bin\Release"),
    (Join-Path $projectDir "bin\x64\Release")
)

foreach ($dir in $searchDirs) {
    if (Test-Path $dir) {
        $foundPackage = Get-ChildItem -Path $dir -Filter "$packageId.$newVersion.nupkg" -ErrorAction SilentlyContinue
        if ($foundPackage) {
            $packagePath = $foundPackage.FullName
            break
        }
    }
}

if (-not $packagePath -or -not (Test-Path $packagePath)) {
    Write-Host "  [ERROR] Package not found: $packageId.$newVersion.nupkg" -ForegroundColor Red
    Write-Host "  Searched in: $($searchDirs -join ', ')" -ForegroundColor Gray
    exit 1
}

$packageSize = (Get-Item $packagePath).Length / 1MB
Write-Host "  [OK] Package found" -ForegroundColor Green
Write-Host "  Name: $packageId.$newVersion.nupkg" -ForegroundColor Gray
Write-Host "  Size: $($packageSize.ToString('F2')) MB" -ForegroundColor Gray
Write-Host "  Location: $packagePath" -ForegroundColor Gray

# Step 5: Get PAT
Write-Host "`nStep 5: Getting PAT..." -ForegroundColor Cyan

if ([string]::IsNullOrEmpty($PAT)) {
    # Check for environment variable override first
    $centralConfigPath = $null
    
    if ($env:AZURE_ACCESS_TOKENS) {
        $centralConfigPath = $env:AZURE_ACCESS_TOKENS
        Write-Host "  Using config from AZURE_ACCESS_TOKENS env var" -ForegroundColor Gray
    }
    else {
        # Default to centralized config directly under OneDrive
        $centralConfigPath = Join-Path $env:OneDriveCommercial "AzureAccessTokens.json"
    }
    
    if (Test-Path $centralConfigPath) {
        Write-Host "  Loading from: AzureAccessTokens.json" -ForegroundColor Gray
        try {
            $tokens = Get-Content $centralConfigPath -Raw | ConvertFrom-Json
            
            # Find matching token by ProjectName or Id
            $token = $tokens | Where-Object { 
                $_.ProjectName -eq $NuGetSource -or 
                $_.Id -like "*$NuGetSource*" -or
                $_.Id -like "*NugetAccessToken*"
            } | Select-Object -First 1
            
            if ($token -and -not [string]::IsNullOrEmpty($token.Token)) {
                $PAT = $token.Token
                Write-Host "  [OK] Token loaded: $($token.Id)" -ForegroundColor Green
                
                if ($token.Email) {
                    Write-Host "  Email: $($token.Email)" -ForegroundColor Gray
                }
                if ($token.ProjectName) {
                    Write-Host "  Project: $($token.ProjectName)" -ForegroundColor Gray
                }
                
                # Check expiration
                if ($token.ExpirationDate) {
                    try {
                        $expDate = [DateTime]::Parse($token.ExpirationDate)
                        $daysUntilExpiration = ($expDate - (Get-Date)).Days
                        
                        if ($daysUntilExpiration -lt 0) {
                            Write-Host "  [WARNING] PAT expired on $($expDate.ToString('yyyy-MM-dd'))" -ForegroundColor Red
                            Write-Host "            Update at: https://dev.azure.com/Dedge/_usersSettings/tokens" -ForegroundColor Yellow
                        }
                        elseif ($daysUntilExpiration -lt 7) {
                            Write-Host "  [WARNING] PAT expires in $daysUntilExpiration days ($($expDate.ToString('yyyy-MM-dd')))" -ForegroundColor Yellow
                        }
                        elseif ($daysUntilExpiration -lt 30) {
                            Write-Host "  [INFO] PAT expires in $daysUntilExpiration days ($($expDate.ToString('yyyy-MM-dd')))" -ForegroundColor Cyan
                        }
                        else {
                            Write-Host "  Expires: $($expDate.ToString('yyyy-MM-dd')) ($daysUntilExpiration days)" -ForegroundColor Gray
                        }
                    }
                    catch {
                        Write-Host "  ExpirationDate: $($token.ExpirationDate)" -ForegroundColor Gray
                    }
                }
            }
            else {
                Write-Host "  [WARNING] No matching token found for $NuGetSource" -ForegroundColor Yellow
            }
            
            # Check expiration date if available
            if ($expirationDate) {
                try {
                    $expDate = [DateTime]::Parse($expirationDate)
                    $daysUntilExpiration = ($expDate - (Get-Date)).Days
                    
                    if ($daysUntilExpiration -lt 0) {
                        Write-Host "  [WARNING] PAT expired on $($expDate.ToString('yyyy-MM-dd'))" -ForegroundColor Red
                        Write-Host "            Update PAT at: https://dev.azure.com/Dedge/_usersSettings/tokens" -ForegroundColor Yellow
                    }
                    elseif ($daysUntilExpiration -lt 7) {
                        Write-Host "  [WARNING] PAT expires in $daysUntilExpiration days ($($expDate.ToString('yyyy-MM-dd')))" -ForegroundColor Yellow
                    }
                    elseif ($daysUntilExpiration -lt 30) {
                        Write-Host "  [INFO] PAT expires in $daysUntilExpiration days ($($expDate.ToString('yyyy-MM-dd')))" -ForegroundColor Cyan
                    }
                    else {
                        Write-Host "  Expires: $($expDate.ToString('yyyy-MM-dd')) ($daysUntilExpiration days)" -ForegroundColor Gray
                    }
                }
                catch {
                    Write-Host "  ExpirationDate: $expirationDate (could not parse)" -ForegroundColor Gray
                }
            }
        }
        catch {
            Write-Host "  [WARNING] Could not load centralized config: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    
    # Fallback to legacy package-specific config
    if ([string]::IsNullOrEmpty($PAT)) {
        if ([string]::IsNullOrEmpty($ConfigFileName)) {
            $ConfigFileName = "$($packageId)Config.json"
        }
        
        $legacyConfigPath = Join-Path $env:OneDriveCommercial "Documents\$ConfigFileName"
        
        if (Test-Path $legacyConfigPath) {
            Write-Host "  Loading from legacy config: $ConfigFileName" -ForegroundColor Gray
            try {
                $config = Get-Content $legacyConfigPath -Raw | ConvertFrom-Json
                $PAT = $config.PAT
                
                if (-not [string]::IsNullOrEmpty($PAT)) {
                    Write-Host "  [OK] PAT loaded from legacy config" -ForegroundColor Green
                    if ($config.NuGetSource) {
                        $NuGetSource = $config.NuGetSource
                    }
                }
            }
            catch {
                Write-Host "  [WARNING] Could not load legacy config: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "  No config file found" -ForegroundColor Gray
            Write-Host "  Recommended: Create centralized config at:" -ForegroundColor Gray
            Write-Host "    $centralConfigPath" -ForegroundColor Cyan
        }
    }
    
    # If still no PAT, prompt
    if ([string]::IsNullOrEmpty($PAT)) {
        Write-Host ""
        Write-Host "  Enter PAT (or press Enter to skip deployment):" -ForegroundColor Yellow
        $PAT = Read-Host
        
        if ([string]::IsNullOrEmpty($PAT)) {
            Write-Host ""
            Write-Host "[INFO] Package built but NOT deployed" -ForegroundColor Yellow
            Write-Host "Package: $packagePath" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "To deploy later:" -ForegroundColor Cyan
            Write-Host "  .\Deploy-NuGetPackage.ps1 -ProjectFile ""$ProjectFile"" -PAT YOUR_PAT" -ForegroundColor White
            Write-Host ""
            Write-Host "Or create config file: $configPath" -ForegroundColor Cyan
            Write-Host "  {" -ForegroundColor Gray
            Write-Host "    ""PAT"": ""YOUR_PAT""," -ForegroundColor Gray
            Write-Host "    ""Email"": ""your.email@company.com""," -ForegroundColor Gray
            Write-Host "    ""NuGetSource"": ""$NuGetSource""" -ForegroundColor Gray
            Write-Host "  }" -ForegroundColor Gray
            exit 0
        }
    }
}
else {
    Write-Host "  [OK] PAT provided via parameter" -ForegroundColor Green
}

# Step 6: Push to feed
Write-Host "`nStep 6: Pushing to NuGet feed ($NuGetSource)..." -ForegroundColor Cyan

try {
    # When source has configured credentials, use arbitrary API key (Azure DevOps requirement)
    # Otherwise use the PAT as API key
    $apiKey = if ([string]::IsNullOrEmpty($PAT)) { "AzureDevOps" } else { $PAT }
    $pushOutput = dotnet nuget push $packagePath --source $NuGetSource --api-key $apiKey --skip-duplicate 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Package pushed successfully!" -ForegroundColor Green
        $deployed = $true
    }
    else {
        $deployed = $false
        
        if ($pushOutput -like "*401*" -or $pushOutput -like "*Unauthorized*") {
            Write-Host "  [ERROR] Authentication failed (401)" -ForegroundColor Red
            Write-Host ""
            Write-Host "  Possible causes:" -ForegroundColor Yellow
            Write-Host "    1. PAT has expired" -ForegroundColor Gray
            Write-Host "    2. PAT missing 'Packaging (Read, write, & manage)' permission" -ForegroundColor Gray
            Write-Host "    3. PAT for wrong organization/source" -ForegroundColor Gray
            Write-Host ""
            Write-Host "  Update config file: $configPath" -ForegroundColor Cyan
        }
        elseif ($pushOutput -like "*409*" -or $pushOutput -like "*already exists*") {
            Write-Host "  [INFO] Package $newVersion already exists in $NuGetSource" -ForegroundColor Yellow
            Write-Host "  Bump version again or check feed" -ForegroundColor Gray
        }
        else {
            Write-Host "  [ERROR] Push failed" -ForegroundColor Red
            Write-Host "  Output: $pushOutput" -ForegroundColor Gray
        }
    }
}
catch {
    Write-Host "  [ERROR] Exception: $($_.Exception.Message)" -ForegroundColor Red
    $deployed = $false
}

# Summary
Write-Host ""
Write-Host "=" * 63 -ForegroundColor Cyan
Write-Host "   Deployment Summary" -ForegroundColor Cyan
Write-Host "=" * 63 -ForegroundColor Cyan
Write-Host ""
Write-Host "Project:    $packageId" -ForegroundColor White
Write-Host "Version:    $currentVersion -> $newVersion" -ForegroundColor White
Write-Host "Package:    $([System.IO.Path]::GetFileName($packagePath))" -ForegroundColor White
Write-Host "Size:       $($packageSize.ToString('F2')) MB" -ForegroundColor White
Write-Host "Source:     $NuGetSource" -ForegroundColor White
Write-Host "Build:      [OK]" -ForegroundColor Green

if ($deployed) {
    Write-Host "Deploy:     [OK] Deployed" -ForegroundColor Green
    Write-Host ""
    Write-Host "[SUCCESS] Package $newVersion deployed to $NuGetSource!" -ForegroundColor Green
    Write-Host ""
    
    # Open browser to package page
    if (-not $NoOpenBrowser) {
        $packageUrl = $null
        
        # Construct URL based on NuGet source
        if ($NuGetSource -eq "Dedge") {
            $packageUrl = "https://dev.azure.com/Dedge/Dedge/_artifacts/feed/Dedge/NuGet/$packageId/overview/$newVersion"
        }
        elseif ($config -and $config.NuGetSourceUrl) {
            # Try to construct URL from config
            if ($config.NuGetSourceUrl -like "*dev.azure.com*") {
                # Extract organization and feed from URL
                if ($config.NuGetSourceUrl -match "dev.azure.com/([^/]+)/([^/]+)/_packaging/([^/]+)") {
                    $org = $Matches[1]
                    $project = $Matches[2]
                    $feed = $Matches[3]
                    $packageUrl = "https://dev.azure.com/$org/$project/_artifacts/feed/$feed/NuGet/$packageId/overview/$newVersion"
                }
            }
        }
        
        if ($packageUrl) {
            Write-Host "Opening package page in browser..." -ForegroundColor Cyan
            Write-Host "  $packageUrl" -ForegroundColor Gray
            Start-Process $packageUrl
        }
        else {
            Write-Host "Package URL: (Could not determine, check feed manually)" -ForegroundColor Gray
        }
        Write-Host ""
    }
    
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Update consuming apps: <PackageReference Include=""$packageId"" Version=""$newVersion"" />" -ForegroundColor Gray
    Write-Host "  2. Test in DEV environment" -ForegroundColor Gray
    Write-Host "  3. Deploy to higher environments" -ForegroundColor Gray
}
else {
    Write-Host "Deploy:     [SKIPPED]" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "[INFO] Package built but not deployed" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To deploy:" -ForegroundColor Cyan
    Write-Host "  .\Deploy-NuGetPackage.ps1 -ProjectFile ""$ProjectFile"" -PAT YOUR_PAT" -ForegroundColor White
}

Write-Host ""
