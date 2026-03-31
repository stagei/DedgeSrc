#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Builds and publishes SqlMermaidErdTools NuGet package to GitHub Packages.

.DESCRIPTION
    This script builds the NuGet package and publishes it to GitHub Packages.
    It handles version checking, building, and publishing to your private GitHub NuGet registry.

.PARAMETER GitHubUsername
    Your GitHub username or organization name.

.PARAMETER GitHubToken
    GitHub Personal Access Token (PAT) with write:packages scope.
    Can also be set via GITHUB_TOKEN environment variable.

.PARAMETER BuildOnly
    Only build the package without publishing.

.PARAMETER SkipTests
    Skip running tests before building package.

.PARAMETER OutputPath
    Output directory for the .nupkg files. Default: ./nupkg

.EXAMPLE
    .\Publish-ToGitHubPackages.ps1 -GitHubUsername "myuser" -GitHubToken "ghp_xxxx"
    Builds and publishes the package to GitHub Packages.

.EXAMPLE
    .\Publish-ToGitHubPackages.ps1 -BuildOnly
    Builds the package without publishing.

.EXAMPLE
    .\Publish-ToGitHubPackages.ps1 -GitHubUsername "myuser"
    Uses GITHUB_TOKEN environment variable for authentication.

.NOTES
    To create a GitHub PAT:
    1. Go to GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
    2. Click "Generate new token (classic)"
    3. Select scopes: write:packages, read:packages, delete:packages (optional)
    4. Copy the token (shown only once!)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$GitHubUsername,

    [Parameter(Mandatory = $false)]
    [string]$GitHubToken,

    [Parameter(Mandatory = $false)]
    [switch]$BuildOnly,

    [Parameter(Mandatory = $false)]
    [switch]$SkipTests,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "./nupkg"
)

$ErrorActionPreference = 'Stop'

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
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host "  SqlMermaidErdTools → GitHub Packages Publisher" -ForegroundColor Magenta
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Magenta

# Validate GitHub credentials
if (-not $BuildOnly) {
    # Try environment variable if token not provided
    if (-not $GitHubToken) {
        $GitHubToken = $env:GITHUB_TOKEN
        if (-not $GitHubToken) {
            $GitHubToken = $env:GH_TOKEN
        }
    }
    
    if (-not $GitHubUsername) {
        Write-Fail "GitHub username is required for publishing!"
        Write-Host ""
        Write-Host "Usage:" -ForegroundColor Yellow
        Write-Host "  .\Publish-ToGitHubPackages.ps1 -GitHubUsername 'your-username' -GitHubToken 'ghp_xxxx'" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Or set environment variables:" -ForegroundColor Yellow
        Write-Host '  $env:GITHUB_TOKEN = "ghp_xxxx"' -ForegroundColor Gray
        Write-Host ""
        exit 1
    }
    
    if (-not $GitHubToken) {
        Write-Fail "GitHub token is required for publishing!"
        Write-Host ""
        Write-Host "Options:" -ForegroundColor Yellow
        Write-Host "  1. Pass -GitHubToken parameter" -ForegroundColor Gray
        Write-Host '  2. Set $env:GITHUB_TOKEN environment variable' -ForegroundColor Gray
        Write-Host "  3. Use -BuildOnly to skip publishing" -ForegroundColor Gray
        Write-Host ""
        Write-Host "To create a GitHub PAT:" -ForegroundColor Yellow
        Write-Host "  1. Go to GitHub → Settings → Developer settings → Personal access tokens" -ForegroundColor Gray
        Write-Host "  2. Generate new token (classic) with write:packages scope" -ForegroundColor Gray
        Write-Host ""
        exit 1
    }
}

# Get package version from project file
$projectFile = "src/SqlMermaidErdTools/SqlMermaidErdTools.csproj"
if (-not (Test-Path $projectFile)) {
    # Try from Scripts directory
    $projectFile = "../src/SqlMermaidErdTools/SqlMermaidErdTools.csproj"
    if (-not (Test-Path $projectFile)) {
        Write-Fail "Project file not found. Run this script from the repository root."
        exit 1
    }
}

$xml = [xml](Get-Content $projectFile)
$version = $xml.Project.PropertyGroup.Version
$packageId = $xml.Project.PropertyGroup.PackageId

Write-Step "Package Information"
Write-Info "Package ID: $packageId"
Write-Info "Version: $version"
Write-Info "Output: $OutputPath"
if (-not $BuildOnly) {
    Write-Info "Target: https://nuget.pkg.github.com/$GitHubUsername/"
}

# Run tests
if (-not $SkipTests) {
    Write-Step "Running tests..."
    
    $solutionFile = "SqlMermaidErdTools.sln"
    if (-not (Test-Path $solutionFile)) {
        $solutionFile = "../SqlMermaidErdTools.sln"
    }
    
    if (Test-Path $solutionFile) {
        dotnet test $solutionFile --configuration Release --verbosity minimal --nologo 2>&1 | Out-Null
        
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Some tests failed, but continuing with build..."
        } else {
            Write-Info "All tests passed"
        }
    } else {
        Write-Warn "Solution file not found, skipping tests"
    }
} else {
    Write-Warn "Skipping tests"
}

# Clean output directory
Write-Step "Preparing output directory..."
if (Test-Path $OutputPath) {
    Remove-Item $OutputPath -Recurse -Force
}
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
Write-Info "Output directory: $((Resolve-Path $OutputPath).Path)"

# Build the package
Write-Step "Building NuGet package..."

$packArgs = @(
    "pack"
    $projectFile
    "--configuration", "Release"
    "--output", $OutputPath
    "--nologo"
    "/p:IncludeSymbols=true"
    "/p:SymbolPackageFormat=snupkg"
)

$output = & dotnet @packArgs 2>&1
$buildSuccess = $LASTEXITCODE -eq 0

if (-not $buildSuccess) {
    Write-Fail "Package build failed!"
    Write-Host $output -ForegroundColor Red
    exit 1
}

$packageFile = Get-ChildItem -Path $OutputPath -Filter "*.nupkg" | Where-Object { $_.Name -notlike "*.snupkg" } | Select-Object -First 1
$symbolFile = Get-ChildItem -Path $OutputPath -Filter "*.snupkg" -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $packageFile) {
    Write-Fail "Package file not created!"
    exit 1
}

Write-Info "Package: $($packageFile.Name)"
if ($symbolFile) {
    Write-Info "Symbols: $($symbolFile.Name)"
}

# Show package size
$packageSize = $packageFile.Length / 1MB
Write-Info "Size: $([math]::Round($packageSize, 2)) MB"

# Verify package contents
Write-Step "Verifying package contents..."
try {
    $tempDir = Join-Path $env:TEMP "nuget-verify-$(New-Guid)"
    Expand-Archive -Path $packageFile.FullName -DestinationPath $tempDir -Force
    
    $contents = @{
        "lib/"      = Test-Path (Join-Path $tempDir "lib")
        "runtimes/" = Test-Path (Join-Path $tempDir "runtimes")
        "scripts/"  = Test-Path (Join-Path $tempDir "scripts")
        "README.md" = Test-Path (Join-Path $tempDir "README.md")
        "icon.png"  = Test-Path (Join-Path $tempDir "icon.png")
    }
    
    foreach ($item in $contents.GetEnumerator()) {
        $status = if ($item.Value) { "✓" } else { "✗" }
        $color = if ($item.Value) { "Green" } else { "Yellow" }
        Write-Host "    $status $($item.Key)" -ForegroundColor $color
    }
    
    Remove-Item $tempDir -Recurse -Force
} catch {
    Write-Warn "Could not verify package contents: $($_.Exception.Message)"
}

# Publishing
if ($BuildOnly) {
    Write-Step "Build complete (publish skipped)"
    Write-Info "Package ready: $($packageFile.FullName)"
    Write-Host ""
    Write-Host "To publish manually:" -ForegroundColor Yellow
    Write-Host "  dotnet nuget push `"$($packageFile.FullName)`" --source `"https://nuget.pkg.github.com/YOUR_USERNAME/index.json`" --api-key YOUR_PAT_TOKEN" -ForegroundColor Gray
    Write-Host ""
} else {
    Write-Step "Publishing to GitHub Packages..."
    
    $sourceUrl = "https://nuget.pkg.github.com/$GitHubUsername/index.json"
    
    Write-Info "Source: $sourceUrl"
    Write-Info "Publishing..."
    
    $pushArgs = @(
        "nuget", "push"
        $packageFile.FullName
        "--source", $sourceUrl
        "--api-key", $GitHubToken
        "--skip-duplicate"
    )
    
    $output = & dotnet @pushArgs 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Step "Package published successfully!"
        Write-Host ""
        Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "║  ✓ PUBLISHED TO GITHUB PACKAGES                               ║" -ForegroundColor Green
        Write-Host "╠═══════════════════════════════════════════════════════════════╣" -ForegroundColor Green
        Write-Host "║                                                               ║" -ForegroundColor Green
        Write-Host "║  Package: $packageId" -ForegroundColor Green
        Write-Host "║  Version: $version" -ForegroundColor Green
        Write-Host "║                                                               ║" -ForegroundColor Green
        Write-Host "║  View at:                                                     ║" -ForegroundColor Green
        Write-Host "║  https://github.com/$GitHubUsername?tab=packages" -ForegroundColor Cyan
        Write-Host "║                                                               ║" -ForegroundColor Green
        Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
        Write-Host ""
        Write-Host "To install this package:" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  1. Add the GitHub Packages source (one-time):" -ForegroundColor Gray
        Write-Host "     dotnet nuget add source `"https://nuget.pkg.github.com/$GitHubUsername/index.json`" --name github-$GitHubUsername --username YOUR_USERNAME --password YOUR_PAT" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  2. Install the package:" -ForegroundColor Gray
        Write-Host "     dotnet add package $packageId --version $version" -ForegroundColor DarkGray
        Write-Host ""
    } else {
        Write-Fail "Publishing failed!"
        Write-Host $output -ForegroundColor Red
        Write-Host ""
        Write-Host "Common issues:" -ForegroundColor Yellow
        Write-Host "  - Token doesn't have write:packages scope" -ForegroundColor Gray
        Write-Host "  - Username doesn't match token owner" -ForegroundColor Gray
        Write-Host "  - Repository doesn't exist yet (create it first)" -ForegroundColor Gray
        Write-Host ""
        exit 1
    }
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host "  Done!" -ForegroundColor Magenta
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Magenta

