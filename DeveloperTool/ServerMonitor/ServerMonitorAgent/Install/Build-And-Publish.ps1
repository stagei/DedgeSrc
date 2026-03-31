#Requires -Version 7.0

<#
.SYNOPSIS
    Builds and publishes Server Health Monitor Check Tool

.DESCRIPTION
    This script builds the solution in Release mode and publishes a self-contained executable.

.PARAMETER Configuration
    Build configuration: Debug or Release. Default: Release

.PARAMETER Runtime
    Target runtime identifier. Default: win-x64

.PARAMETER SelfContained
    Create self-contained deployment. Default: false

.EXAMPLE
    .\Build-And-Publish.ps1
    Builds and publishes with default settings

.EXAMPLE
    .\Build-And-Publish.ps1 -Configuration Debug -SelfContained
    Builds debug version as self-contained
#>

[CmdletBinding()]
param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",
    
    [string]$Runtime = "win-x64",
    
    [switch]$SelfContained
)

$ErrorActionPreference = "Stop"

Write-Host "=== Server Health Monitor Check Tool - Build and Publish ===" -ForegroundColor Cyan

# Find solution file
$solutionPath = Join-Path $PSScriptRoot "..\ServerMonitor.sln"

if (-not (Test-Path $solutionPath)) {
    Write-Error "Solution file not found at: $($solutionPath)"
    exit 1
}

Write-Host "Solution: $($solutionPath)" -ForegroundColor Gray

# Clean previous builds
Write-Host "`nCleaning previous builds..." -ForegroundColor Yellow
dotnet clean $solutionPath --configuration $Configuration

if ($LASTEXITCODE -ne 0) {
    Write-Error "Clean failed with exit code: $($LASTEXITCODE)"
    exit 1
}

# Restore NuGet packages
Write-Host "`nRestoring NuGet packages..." -ForegroundColor Yellow
dotnet restore $solutionPath

if ($LASTEXITCODE -ne 0) {
    Write-Error "Restore failed with exit code: $($LASTEXITCODE)"
    exit 1
}

# Build solution
Write-Host "`nBuilding solution ($($Configuration))..." -ForegroundColor Green
dotnet build $solutionPath --configuration $Configuration --no-restore

if ($LASTEXITCODE -ne 0) {
    Write-Error "Build failed with exit code: $($LASTEXITCODE)"
    exit 1
}

# Publish
$projectPath = Join-Path $PSScriptRoot "..\src\ServerMonitor\ServerMonitor.csproj"
$publishPath = Join-Path $PSScriptRoot "..\src\ServerMonitor\bin\$($Configuration)\net10.0-windows\$($Runtime)\publish"

Write-Host "`nPublishing application..." -ForegroundColor Green
Write-Host "Output: $($publishPath)" -ForegroundColor Gray

$publishArgs = @(
    "publish"
    $projectPath
    "--configuration", $Configuration
    "--runtime", $Runtime
    "--no-build"
    "--output", $publishPath
)

if ($SelfContained) {
    $publishArgs += "--self-contained", "true"
    Write-Host "Mode: Self-Contained" -ForegroundColor Gray
} else {
    $publishArgs += "--self-contained", "false"
    Write-Host "Mode: Framework-Dependent" -ForegroundColor Gray
}

& dotnet $publishArgs

if ($LASTEXITCODE -ne 0) {
    Write-Error "Publish failed with exit code: $($LASTEXITCODE)"
    exit 1
}

Write-Host "`n=== Build Complete ===" -ForegroundColor Cyan
Write-Host "Published to: $($publishPath)" -ForegroundColor White

# List published files
Write-Host "`nPublished files:" -ForegroundColor Gray
Get-ChildItem -Path $publishPath | ForEach-Object {
    Write-Host "  $($_.Name)" -ForegroundColor DarkGray
}

$exePath = Join-Path $publishPath "ServerMonitor.exe"
if (Test-Path $exePath) {
    $fileInfo = Get-Item $exePath
    Write-Host "`nExecutable size: $([math]::Round($fileInfo.Length / 1MB, 2)) MB" -ForegroundColor White
}

Write-Host "`nTo install as service, run:" -ForegroundColor Gray
Write-Host "  .\Install\Install-Service.ps1" -ForegroundColor Gray

