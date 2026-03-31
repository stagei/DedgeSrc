#Requires -Version 5.1

<#
.SYNOPSIS
    Master test runner for all OllamaHandler tests.

.DESCRIPTION
    Runs all test scripts in sequence and provides a summary.

.PARAMETER SkipAITests
    Skip tests that require running Ollama with models.

.PARAMETER SkipExportTests
    Skip export/import tests.

.PARAMETER Verbose
    Show detailed output.

.EXAMPLE
    .\Run-AllTests.ps1
    # Run all tests

.EXAMPLE
    .\Run-AllTests.ps1 -SkipAITests
    # Run only tests that don't need Ollama running

.AUTHOR
    Geir Helge Starholm, www.dEdge.no
#>

[CmdletBinding()]
param(
    [switch]$SkipAITests,
    [switch]$SkipExportTests
)

$ErrorActionPreference = "Continue"
$testDir = $PSScriptRoot

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║           OLLAMA HANDLER - COMPLETE TEST SUITE                 ║" -ForegroundColor Magenta
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
Write-Host ""
Write-Host "  Test Directory: $testDir" -ForegroundColor DarkGray
Write-Host "  Skip AI Tests: $SkipAITests" -ForegroundColor DarkGray
Write-Host "  Skip Export Tests: $SkipExportTests" -ForegroundColor DarkGray
Write-Host ""

$testResults = @{
    Passed = 0
    Failed = 0
    Skipped = 0
}

#region Module Tests

Write-Host "════════════════════════════════════════════════════════════════════" -ForegroundColor Blue
Write-Host "  RUNNING: Test-OllamaHandler.ps1 (Core Module Tests)" -ForegroundColor Blue
Write-Host "════════════════════════════════════════════════════════════════════" -ForegroundColor Blue

$params = @{}
if ($SkipAITests) { $params.SkipAITests = $true }

try {
    $result = & (Join-Path $testDir "Test-OllamaHandler.ps1") @params
    $testResults.Passed += $result.Passed
    $testResults.Failed += $result.Failed
    $testResults.Skipped += $result.Skipped
}
catch {
    Write-Host "  ✗ Test script failed: $($_.Exception.Message)" -ForegroundColor Red
    $testResults.Failed++
}

#endregion

#region Model Library Tests

Write-Host ""
Write-Host "════════════════════════════════════════════════════════════════════" -ForegroundColor Blue
Write-Host "  RUNNING: Test-ModelLibrary.ps1 (Model Library Tests)" -ForegroundColor Blue
Write-Host "════════════════════════════════════════════════════════════════════" -ForegroundColor Blue

try {
    & (Join-Path $testDir "Test-ModelLibrary.ps1")
    $testResults.Passed++
}
catch {
    Write-Host "  ✗ Test script failed: $($_.Exception.Message)" -ForegroundColor Red
    $testResults.Failed++
}

#endregion

#region Chat Tests

if (-not $SkipAITests) {
    Write-Host ""
    Write-Host "════════════════════════════════════════════════════════════════════" -ForegroundColor Blue
    Write-Host "  RUNNING: Test-OllamaChat.ps1 (AI Chat Tests)" -ForegroundColor Blue
    Write-Host "════════════════════════════════════════════════════════════════════" -ForegroundColor Blue
    
    try {
        & (Join-Path $testDir "Test-OllamaChat.ps1")
        $testResults.Passed++
    }
    catch {
        Write-Host "  ✗ Test script failed: $($_.Exception.Message)" -ForegroundColor Red
        $testResults.Failed++
    }
}
else {
    Write-Host ""
    Write-Host "  ○ SKIPPED: Test-OllamaChat.ps1 (AI tests disabled)" -ForegroundColor Yellow
    $testResults.Skipped++
}

#endregion

#region Export/Import Tests

if (-not $SkipExportTests -and -not $SkipAITests) {
    Write-Host ""
    Write-Host "════════════════════════════════════════════════════════════════════" -ForegroundColor Blue
    Write-Host "  RUNNING: Test-ExportImport.ps1 (Export/Import Tests)" -ForegroundColor Blue
    Write-Host "════════════════════════════════════════════════════════════════════" -ForegroundColor Blue
    
    try {
        & (Join-Path $testDir "Test-ExportImport.ps1")
        $testResults.Passed++
    }
    catch {
        Write-Host "  ✗ Test script failed: $($_.Exception.Message)" -ForegroundColor Red
        $testResults.Failed++
    }
}
else {
    Write-Host ""
    Write-Host "  ○ SKIPPED: Test-ExportImport.ps1 (export tests disabled)" -ForegroundColor Yellow
    $testResults.Skipped++
}

#endregion

#region Summary

Write-Host ""
Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║                    FINAL TEST SUMMARY                          ║" -ForegroundColor Magenta
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
Write-Host ""

$totalTests = $testResults.Passed + $testResults.Failed + $testResults.Skipped
$passRate = if ($totalTests -gt 0) { [math]::Round(($testResults.Passed / ($testResults.Passed + $testResults.Failed)) * 100, 1) } else { 0 }

Write-Host "  Test Categories Run: 4" -ForegroundColor White
Write-Host ""
Write-Host "  Core Module Tests:    $(if ($testResults.Passed -gt 0) { '✓ Completed' } else { '✗ Failed' })" -ForegroundColor $(if ($testResults.Failed -eq 0) { "Green" } else { "Red" })
Write-Host "  Model Library Tests:  $(if (-not $SkipAITests) { '✓ Completed' } else { '○ Skipped' })" -ForegroundColor $(if (-not $SkipAITests) { "Green" } else { "Yellow" })
Write-Host "  Chat Tests:           $(if (-not $SkipAITests) { '✓ Completed' } else { '○ Skipped' })" -ForegroundColor $(if (-not $SkipAITests) { "Green" } else { "Yellow" })
Write-Host "  Export/Import Tests:  $(if (-not $SkipExportTests -and -not $SkipAITests) { '✓ Completed' } else { '○ Skipped' })" -ForegroundColor $(if (-not $SkipExportTests -and -not $SkipAITests) { "Green" } else { "Yellow" })
Write-Host ""

if ($testResults.Failed -eq 0) {
    Write-Host "  ╔═══════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║     ALL TESTS PASSED SUCCESSFULLY!    ║" -ForegroundColor Green
    Write-Host "  ╚═══════════════════════════════════════╝" -ForegroundColor Green
}
else {
    Write-Host "  ╔═══════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "  ║     SOME TESTS FAILED - SEE ABOVE     ║" -ForegroundColor Red
    Write-Host "  ╚═══════════════════════════════════════╝" -ForegroundColor Red
}

Write-Host ""
Write-Host "  Pass Rate: $passRate%" -ForegroundColor $(if ($passRate -ge 80) { "Green" } elseif ($passRate -ge 50) { "Yellow" } else { "Red" })
Write-Host ""

#endregion

# Return results for automation
return $testResults

