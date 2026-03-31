#Requires -Version 5.1

<#
.SYNOPSIS
    Test script for OllamaHandler model library and installation functions.

.DESCRIPTION
    Tests the model library, browsing, and installation capabilities including:
    - Fetching model library from ollama.com
    - Getting recommended models
    - Model installation (optional)

.PARAMETER InstallTestModel
    If specified, actually downloads and installs a small test model.

.EXAMPLE
    .\Test-ModelLibrary.ps1
    # Run model library tests without installing

.EXAMPLE
    .\Test-ModelLibrary.ps1 -InstallTestModel
    # Run tests and install a small test model

.AUTHOR
    Geir Helge Starholm, www.dEdge.no
#>

[CmdletBinding()]
param(
    [switch]$InstallTestModel
)

# Import module
$modulePath = Join-Path $PSScriptRoot "..\OllamaHandler.psm1"
Import-Module $modulePath -Force

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║           MODEL LIBRARY FUNCTIONALITY TEST                     ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

#region Recommended Models

Write-Host "───────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "Test: Get-OllamaRecommendedModels" -ForegroundColor Yellow
Write-Host "───────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

$allModels = Get-OllamaRecommendedModels -ModelGroup "All"
Write-Host ""
Write-Host "All Recommended Models ($($allModels.Count) total):" -ForegroundColor Green

$allModels | Format-Table -Property Name, Title, SizeGB, @{Label='Tags';Expression={$_.Tags -join ', '}} -AutoSize

Write-Host ""
Write-Host "Non-GPU Models:" -ForegroundColor Green
$nonGpuModels = Get-OllamaRecommendedModels -ModelGroup "Non-GPU"
$nonGpuModels | ForEach-Object {
    Write-Host "  - $($_.Name) (~$($_.SizeGB) GB) - $($_.Description.Substring(0, [Math]::Min(60, $_.Description.Length)))..." -ForegroundColor White
}

Write-Host ""
Write-Host "  ✓ Get-OllamaRecommendedModels works" -ForegroundColor Green

#endregion

#region Online Model Library

Write-Host ""
Write-Host "───────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "Test: Get-OllamaModelLibrary (fetches from ollama.com)" -ForegroundColor Yellow
Write-Host "───────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Fetching model library from ollama.com..." -ForegroundColor Yellow

try {
    $onlineModels = Get-OllamaModelLibrary
    
    if ($onlineModels.Count -gt 0) {
        Write-Host "  ✓ Fetched $($onlineModels.Count) models from ollama.com" -ForegroundColor Green
        Write-Host ""
        Write-Host "Sample models (first 10):" -ForegroundColor Green
        $onlineModels | Select-Object -First 10 | ForEach-Object {
            Write-Host "  - $($_.Name)" -ForegroundColor White
        }
    }
    else {
        Write-Host "  ⚠ No models returned (may be network issue)" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "  ⚠ Failed to fetch model library: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "    (This may be due to network issues)" -ForegroundColor DarkYellow
}

#endregion

#region Installed Models Check

Write-Host ""
Write-Host "───────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "Test: Check Installed Models" -ForegroundColor Yellow
Write-Host "───────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

if (Test-OllamaService) {
    $installedModels = Get-OllamaModels -IncludeDetails
    
    if ($installedModels.Count -gt 0) {
        Write-Host "Installed Models:" -ForegroundColor Green
        $installedModels | Format-Table -Property Name, SizeGB, Family, ParameterSize -AutoSize
        Write-Host "  ✓ Get-OllamaModels works" -ForegroundColor Green
    }
    else {
        Write-Host "  No models currently installed." -ForegroundColor Yellow
        Write-Host "  Use Select-OllamaModelsToInstall or Install-OllamaModelBatch to install models." -ForegroundColor DarkYellow
    }
}
else {
    Write-Host "  Ollama service not running. Start with: ollama serve" -ForegroundColor Yellow
}

#endregion

#region Optional Model Installation Test

if ($InstallTestModel) {
    Write-Host ""
    Write-Host "───────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "Test: Install Small Test Model" -ForegroundColor Yellow
    Write-Host "───────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    
    if (-not (Test-OllamaService)) {
        Write-Host "  Ollama service not running. Attempting to start..." -ForegroundColor Yellow
        $started = Start-OllamaService
        if (-not $started) {
            Write-Host "  ✗ Cannot start Ollama service" -ForegroundColor Red
            exit 1
        }
    }
    
    # Install a small model for testing
    $testModel = "phi3:mini"  # Small ~2.3GB model
    Write-Host "Installing test model: $testModel" -ForegroundColor Yellow
    Write-Host "  (This may take several minutes depending on your connection)" -ForegroundColor DarkYellow
    Write-Host ""
    
    $result = Install-OllamaModelBatch -ModelNames @($testModel)
    
    if ($result | Where-Object { $_.Success }) {
        Write-Host ""
        Write-Host "  ✓ Model installation test passed" -ForegroundColor Green
    }
    else {
        Write-Host ""
        Write-Host "  ✗ Model installation failed" -ForegroundColor Red
    }
}
else {
    Write-Host ""
    Write-Host "  Tip: Run with -InstallTestModel to test actual model installation" -ForegroundColor DarkYellow
}

#endregion

# Summary
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Model library tests completed!" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor White
Write-Host "    - Use Select-OllamaModelsToInstall for interactive model browsing" -ForegroundColor DarkGray
Write-Host "    - Use Install-OllamaModelBatch to install specific models" -ForegroundColor DarkGray
Write-Host "    - Use Export-OllamaModel to prepare models for airgapped transfer" -ForegroundColor DarkGray
Write-Host ""

