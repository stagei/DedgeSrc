#Requires -Version 5.1

<#
.SYNOPSIS
    Test script for OllamaHandler export/import functionality.

.DESCRIPTION
    Tests the model export and import capabilities for airgapped server transfer.
    Note: These tests require at least one model to be installed.

.PARAMETER ModelName
    The name of the model to test export with. Defaults to first installed model.

.EXAMPLE
    .\Test-ExportImport.ps1
    # Run export/import tests with first available model

.EXAMPLE
    .\Test-ExportImport.ps1 -ModelName "llama3.1:8b"
    # Run tests with specific model

.AUTHOR
    Geir Helge Starholm, www.dEdge.no
#>

[CmdletBinding()]
param(
    [string]$ModelName = ""
)

# Import module
$modulePath = Join-Path $PSScriptRoot "..\OllamaHandler.psm1"
Import-Module $modulePath -Force

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║           EXPORT/IMPORT FUNCTIONALITY TEST                     ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check prerequisites
Write-Host "Checking prerequisites..." -ForegroundColor Yellow

# Check Ollama service
if (-not (Test-OllamaService)) {
    Write-Host "  ✗ Ollama service is not running" -ForegroundColor Red
    Write-Host "    Start with: ollama serve" -ForegroundColor Yellow
    exit 1
}
Write-Host "  ✓ Ollama service is running" -ForegroundColor Green

# Check installed models
$installedModels = Get-OllamaModels -IncludeDetails
if ($installedModels.Count -eq 0) {
    Write-Host "  ✗ No models installed" -ForegroundColor Red
    Write-Host "    Install a model first: ollama pull llama3.1:8b" -ForegroundColor Yellow
    exit 1
}
Write-Host "  ✓ Found $($installedModels.Count) installed model(s)" -ForegroundColor Green

# Select model for testing
if (-not $ModelName) {
    # Pick the smallest installed model
    $testModel = $installedModels | Sort-Object Size | Select-Object -First 1
    $ModelName = $testModel.Name
    Write-Host "  Using smallest model for test: $ModelName ($($testModel.SizeGB) GB)" -ForegroundColor Yellow
}
else {
    if ($ModelName -notin ($installedModels | ForEach-Object { $_.Name })) {
        Write-Host "  ✗ Model '$ModelName' is not installed" -ForegroundColor Red
        Write-Host "    Available models:" -ForegroundColor Yellow
        $installedModels | ForEach-Object { Write-Host "      - $($_.Name)" -ForegroundColor White }
        exit 1
    }
    Write-Host "  Using specified model: $ModelName" -ForegroundColor Yellow
}

#region Export Test

Write-Host ""
Write-Host "───────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "Test: Export-OllamaModel" -ForegroundColor Yellow
Write-Host "───────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

$safeModelName = $ModelName -replace '[:\/]', '-'
$exportPath = Join-Path $env:TEMP "OllamaTest_$safeModelName.zip"

Write-Host "Exporting model: $ModelName" -ForegroundColor Yellow
Write-Host "Export path: $exportPath" -ForegroundColor Yellow
Write-Host ""
Write-Host "  (This may take a while for large models...)" -ForegroundColor DarkYellow
Write-Host ""

$exportResult = Export-OllamaModel -ModelName $ModelName -OutputPath $exportPath

if ($exportResult -and (Test-Path $exportResult)) {
    $exportSize = (Get-Item $exportResult).Length / 1MB
    Write-Host "  ✓ Export successful!" -ForegroundColor Green
    Write-Host "    File: $exportResult" -ForegroundColor White
    Write-Host "    Size: $([math]::Round($exportSize, 2)) MB" -ForegroundColor White
}
else {
    Write-Host "  ✗ Export failed" -ForegroundColor Red
    Write-Host "    Check that the model is fully downloaded." -ForegroundColor Yellow
    exit 1
}

#endregion

#region Verify Export Contents

Write-Host ""
Write-Host "───────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "Test: Verify Export Contents" -ForegroundColor Yellow
Write-Host "───────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Extract and verify
$verifyPath = Join-Path $env:TEMP "OllamaTest_Verify_$safeModelName"
if (Test-Path $verifyPath) {
    Remove-Item $verifyPath -Recurse -Force
}

Write-Host "Extracting for verification..." -ForegroundColor Yellow
Expand-Archive -Path $exportResult -DestinationPath $verifyPath -Force

$hasManifests = Test-Path (Join-Path $verifyPath "manifests")
$hasBlobs = Test-Path (Join-Path $verifyPath "blobs")

if ($hasManifests -and $hasBlobs) {
    $manifestCount = (Get-ChildItem (Join-Path $verifyPath "manifests") -Recurse -File).Count
    $blobCount = (Get-ChildItem (Join-Path $verifyPath "blobs") -File).Count
    
    Write-Host "  ✓ Export structure is valid" -ForegroundColor Green
    Write-Host "    Manifests: $manifestCount file(s)" -ForegroundColor White
    Write-Host "    Blobs: $blobCount file(s)" -ForegroundColor White
}
else {
    Write-Host "  ✗ Export structure is invalid" -ForegroundColor Red
    Write-Host "    Missing: $(if (-not $hasManifests) { 'manifests' }) $(if (-not $hasBlobs) { 'blobs' })" -ForegroundColor Red
}

# Cleanup verification
Remove-Item $verifyPath -Recurse -Force -ErrorAction SilentlyContinue

#endregion

#region Import Test (Simulated)

Write-Host ""
Write-Host "───────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "Test: Import-OllamaModel (Verification Only)" -ForegroundColor Yellow
Write-Host "───────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

Write-Host "Note: Not actually importing to avoid duplicating existing model." -ForegroundColor Yellow
Write-Host "      The import function would copy files to the Ollama models directory." -ForegroundColor Yellow
Write-Host ""

# Verify the import function works with validation
Write-Host "Verifying Import-OllamaModel function..." -ForegroundColor Yellow

$importCmd = Get-Command Import-OllamaModel -ErrorAction SilentlyContinue
if ($importCmd) {
    Write-Host "  ✓ Import-OllamaModel function is available" -ForegroundColor Green
    Write-Host "    Parameters: $($importCmd.Parameters.Keys -join ', ')" -ForegroundColor White
}
else {
    Write-Host "  ✗ Import-OllamaModel function not found" -ForegroundColor Red
}

#endregion

#region Cleanup

Write-Host ""
Write-Host "───────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "Cleanup" -ForegroundColor Yellow
Write-Host "───────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

if (Test-Path $exportResult) {
    Remove-Item $exportResult -Force
    Write-Host "  ✓ Cleaned up test export file" -ForegroundColor Green
}

#endregion

# Summary
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Export/Import tests completed!" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Usage for airgapped transfer:" -ForegroundColor White
Write-Host "    1. Export: Export-OllamaModel -ModelName 'llama3.1:8b'" -ForegroundColor DarkGray
Write-Host "    2. Transfer the .zip file to the airgapped server" -ForegroundColor DarkGray
Write-Host "    3. Import: Import-OllamaModel -ModelPath 'C:\path\to\model.zip'" -ForegroundColor DarkGray
Write-Host ""

