#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Builds and publishes SqlMmdConverter NuGet package.

.DESCRIPTION
    This script builds the NuGet package and optionally publishes it to NuGet.org.
    It handles version checking, building, testing, and publishing.

.PARAMETER ApiKey
    NuGet API key for publishing. Get from https://www.nuget.org/account/apikeys

.PARAMETER BuildOnly
    Only build the package without publishing.

.PARAMETER SkipTests
    Skip running tests before building package.

.PARAMETER DeprecatePrevious
    Automatically provide deprecation instructions for the previous version. Default: $true

.PARAMETER OutputPath
    Output directory for the .nupkg files. Default: ./nupkg

.EXAMPLE
    .\publish-nuget.ps1 -BuildOnly
    Builds the package without publishing.

.EXAMPLE
    .\publish-nuget.ps1 -ApiKey "oy2abc123..."
    Builds and publishes the package to NuGet.org.

.EXAMPLE
    .\publish-nuget.ps1 -BuildOnly -SkipTests
    Builds without running tests (not recommended).

.EXAMPLE
    .\publish-nuget.ps1 -DeprecatePrevious $false
    Publishes without showing deprecation instructions for the previous version.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ApiKey,

    [Parameter(Mandatory = $false)]
    [switch]$BuildOnly,

    [Parameter(Mandatory = $false)]
    [switch]$SkipTests,

    [Parameter(Mandatory = $false)]
    [bool]$DeprecatePrevious = $true,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "./nupkg"
)

$ErrorActionPreference = 'Stop'

# Read API key from environment variable if not provided
if (-not $ApiKey -and -not $BuildOnly) {
    $ApiKey = [System.Environment]::GetEnvironmentVariable("NUGET_API_KEY_SQL2MMD", [System.EnvironmentVariableTarget]::User)
    if (-not $ApiKey) {
        Write-Host "ERROR: NuGet API key not provided!" -ForegroundColor Red
        Write-Host ""
        Write-Host "Set the API key via:" -ForegroundColor Yellow
        Write-Host "  1. Environment variable: `$env:NUGET_API_KEY_SQL2MMD = 'your-key'" -ForegroundColor Gray
        Write-Host "  2. Parameter: -ApiKey 'your-key'" -ForegroundColor Gray
        Write-Host "  3. Build only: -BuildOnly (skip publishing)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "To set permanently (recommended):" -ForegroundColor Yellow
        Write-Host '  [System.Environment]::SetEnvironmentVariable("NUGET_API_KEY_SQL2MMD", "your-key", [System.EnvironmentVariableTarget]::User)' -ForegroundColor Gray
        exit 1
    }
}

# Helper function to get previous version
function Get-PreviousVersion {
    param([string]$CurrentVersion)
    
    # Parse semantic version (e.g., "0.1.1" -> 0.1.0)
    if ($CurrentVersion -match '^(\d+)\.(\d+)\.(\d+)$') {
        $major = [int]$matches[1]
        $minor = [int]$matches[2]
        $patch = [int]$matches[3]
        
        # Decrement patch version
        if ($patch -gt 0) {
            return "$major.$minor.$($patch - 1)"
        }
        # Decrement minor version
        elseif ($minor -gt 0) {
            return "$major.$($minor - 1).0"
        }
        # Decrement major version
        elseif ($major -gt 0) {
            return "$($major - 1).0.0"
        }
    }
    
    return $null
}

# Helper function to deprecate a NuGet package version
function Deprecate-NuGetVersion {
    param(
        [string]$PackageId,
        [string]$Version,
        [string]$AlternatePackage,
        [string]$Message,
        [string]$ApiKey
    )
    
    try {
        # NuGet API endpoint for deprecation
        $url = "https://www.nuget.org/api/v2/package/$PackageId/$Version"
        
        # Deprecation payload
        $body = @{
            isLegacy = $true
            isOther = $false
            alternatePackageId = $PackageId
            alternatePackageVersion = $Version.Split(' ')[1]  # Extract version from "PackageId Version"
            message = $Message
        } | ConvertTo-Json
        
        # Make API request
        $headers = @{
            "X-NuGet-ApiKey" = $ApiKey
            "Content-Type" = "application/json"
        }
        
        # Note: NuGet deprecation requires web UI or NuGet.org account
        # API-based deprecation is limited, so we'll provide instructions instead
        Write-Warn "Automated deprecation via API is not fully supported by NuGet.org"
        Write-Info "To deprecate v$Version manually:"
        Write-Info "  1. Go to https://www.nuget.org/packages/$PackageId/$Version"
        Write-Info "  2. Sign in to your account"
        Write-Info "  3. Click 'Deprecate' button"
        Write-Info "  4. Select 'Legacy' reason"
        Write-Info "  5. Set alternate: $AlternatePackage"
        Write-Info "  6. Message: $Message"
        
        return $false  # Not actually deprecated via API
    }
    catch {
        Write-Warn "Deprecation check failed: $($_.Exception.Message)"
        return $false
    }
}

# Colors for output
function Write-Step {
    param([string]$Message)
    Write-Host "`n✓ $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor Cyan
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  ⚠ $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "  ✗ $Message" -ForegroundColor Red
}

# Script start
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host "  SqlMmdConverter NuGet Package Builder & Publisher" -ForegroundColor Magenta
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Magenta

# Get package version from project file
$projectFile = "src/SqlMmdConverter/SqlMmdConverter.csproj"
if (-not (Test-Path $projectFile)) {
    Write-Fail "Project file not found: $projectFile"
    exit 1
}

$xml = [xml](Get-Content $projectFile)
$version = $xml.Project.PropertyGroup.Version
$packageId = $xml.Project.PropertyGroup.PackageId

Write-Info "Package ID: $packageId"
Write-Info "Version: $version"
Write-Info "Output: $OutputPath"

# Check if version already exists on NuGet.org
Write-Step "Checking if version already exists on NuGet.org..."
try {
    $nugetSearch = Invoke-RestMethod -Uri "https://api.nuget.org/v3/registration5-semver1/$($packageId.ToLower())/index.json" -ErrorAction SilentlyContinue
    $existingVersions = $nugetSearch.items.items.catalogEntry.version
    
    if ($existingVersions -contains $version) {
        Write-Fail "Version $version already exists on NuGet.org!"
        Write-Warn "Please update the version in $projectFile"
        exit 1
    }
    Write-Info "Version $version is available"
} catch {
    Write-Info "Package not yet published (this is OK for first release)"
}

# Run tests
if (-not $SkipTests) {
    Write-Step "Running tests..."
    dotnet test SqlMmdConverter.sln --configuration Release --verbosity minimal --nologo
    
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Tests failed! Fix tests before publishing."
        exit 1
    }
    Write-Info "All tests passed"
} else {
    Write-Warn "Skipping tests (not recommended for publishing)"
}

# Clean output directory
Write-Step "Cleaning output directory..."
if (Test-Path $OutputPath) {
    Remove-Item $OutputPath -Recurse -Force
}
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
Write-Info "Output directory ready: $OutputPath"

# Build the package
Write-Step "Building NuGet package..."
dotnet pack src/SqlMmdConverter/SqlMmdConverter.csproj `
    --configuration Release `
    --output $OutputPath `
    --nologo `
    /p:IncludeSymbols=true `
    /p:SymbolPackageFormat=snupkg

if ($LASTEXITCODE -ne 0) {
    Write-Fail "Package build failed!"
    exit 1
}

$packageFile = Join-Path $OutputPath "$packageId.$version.nupkg"
$symbolFile = Join-Path $OutputPath "$packageId.$version.snupkg"

if (-not (Test-Path $packageFile)) {
    Write-Fail "Package file not created: $packageFile"
    exit 1
}

Write-Info "Package created: $packageFile"
if (Test-Path $symbolFile) {
    Write-Info "Symbol package created: $symbolFile"
}

# Show package size
$packageSize = (Get-Item $packageFile).Length / 1MB
Write-Info "Package size: $([math]::Round($packageSize, 2)) MB"

if ($packageSize -gt 100) {
    Write-Warn "Package is very large (>100 MB). Consider optimizing."
}

# Verify package contents
Write-Step "Verifying package contents..."
try {
    $tempDir = Join-Path $env:TEMP "nuget-verify-$(New-Guid)"
    Expand-Archive -Path $packageFile -DestinationPath $tempDir -Force
    
    $hasRuntimes = Test-Path (Join-Path $tempDir "runtimes")
    $hasScripts = Test-Path (Join-Path $tempDir "scripts")
    $hasLib = Test-Path (Join-Path $tempDir "lib")
    
    Write-Info "Contains lib/: $hasLib"
    Write-Info "Contains runtimes/: $hasRuntimes"
    Write-Info "Contains scripts/: $hasScripts"
    
    Remove-Item $tempDir -Recurse -Force
} catch {
    Write-Warn "Could not verify package contents: $($_.Exception.Message)"
}

# Publishing
if ($BuildOnly) {
    Write-Step "Build complete (publish skipped)"
    Write-Info "Package ready for publishing: $packageFile"
    Write-Info "`nTo publish manually:"
    Write-Info "  dotnet nuget push `"$packageFile`" --api-key YOUR_API_KEY --source https://api.nuget.org/v3/index.json"
} else {
    if (-not $ApiKey) {
        Write-Fail "API key required for publishing. Use -ApiKey parameter or -BuildOnly to skip."
        Write-Info "`nGet your API key from: https://www.nuget.org/account/apikeys"
        exit 1
    }

    Write-Step "Publishing to NuGet.org..."
    # Write-Warn "This will publish version $version publicly!"
    # Write-Host "`nPress Ctrl+C to cancel, or Enter to continue..." -ForegroundColor Yellow
    # Read-Host
    
    dotnet nuget push $packageFile `
        --api-key $ApiKey `
        --source https://api.nuget.org/v3/index.json `
        --skip-duplicate

    if ($LASTEXITCODE -eq 0) {
        Write-Step "Package published successfully!"
        Write-Info "Package: https://www.nuget.org/packages/$packageId/$version"
        Write-Info "`nIt may take 5-15 minutes to appear in search and package manager."
        Write-Info "`nUsers can install with:"
        Write-Info "  dotnet add package $packageId --version $version"
        
        # Deprecate previous version if requested
        if ($DeprecatePrevious) {
            Write-Step "Deprecating previous version..."
            $previousVersion = Get-PreviousVersion -CurrentVersion $version
            
            if ($previousVersion) {
                Write-Info "Current version: $version"
                Write-Info "Previous version: $previousVersion"
                Write-Info "Deprecating $previousVersion..."
                
                $deprecateResult = Deprecate-NuGetVersion `
                    -PackageId $packageId `
                    -Version $previousVersion `
                    -AlternatePackage "$packageId $version" `
                    -Message "Please upgrade to v$version - includes bug fixes and improvements" `
                    -ApiKey $ApiKey
                
                if ($deprecateResult) {
                    Write-Info "✓ Successfully deprecated v$previousVersion"
                } else {
                    Write-Warn "Could not deprecate v$previousVersion (may not exist or already deprecated)"
                }
            } else {
                Write-Info "No previous version to deprecate (this is the first release)"
            }
        }
    } else {
        Write-Fail "Publishing failed!"
        exit 1
    }
}

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host "  Done!" -ForegroundColor Magenta
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Magenta

