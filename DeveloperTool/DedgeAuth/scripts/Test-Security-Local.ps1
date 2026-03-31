# Master Security Test Runner
# Executes all security test scripts and generates reports

param(
    [string]$BaseUrl = "http://localhost:8100",
    [string]$OutputPath = "docs"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  DedgeAuth Security Testing" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "Base URL: $BaseUrl" -ForegroundColor Gray
Write-Host ""

# Initialize global test results
$Global:SecurityTestResults = @()

# Dot-source helpers
$helpersPath = Join-Path $PSScriptRoot "SecurityTestHelpers.ps1"
if (Test-Path $helpersPath) {
    . $helpersPath
} else {
    Write-Error "SecurityTestHelpers.ps1 not found at: $helpersPath"
    exit 1
}

# Ensure output directory exists
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

# List of test scripts to run
$testScripts = @(
    "Test-PasswordSecurity.ps1",
    "Test-AccountLockout.ps1",
    "Test-JwtTokenSecurity.ps1",
    "Test-CorsConfiguration.ps1",
    "Test-RateLimiting.ps1",
    "Test-DebugEndpoints.ps1",
    "Test-AuthorizationPolicies.ps1",
    "Test-ApiAuthorization.ps1",
    "Test-RefreshTokenSecurity.ps1",
    "Test-SecretsExposure.ps1",
    "Test-ConfigurationValidation.ps1",
    "Test-TokenRevocation.ps1"
)

Write-Host "Running security tests..." -ForegroundColor Yellow
Write-Host ""

# Run each test script
foreach ($script in $testScripts) {
    $scriptPath = Join-Path $PSScriptRoot $script
    if (Test-Path $scriptPath) {
        Write-Host "Running $script..." -ForegroundColor Gray
        try {
            . $scriptPath -BaseUrl $BaseUrl
        }
        catch {
            Write-TestResult -TestName "Script Execution" -Category "Infrastructure" -Passed $false `
                -Message "Failed to execute $script : $($_.Exception.Message)"
        }
    }
    else {
        Write-Host "Warning: $script not found, skipping..." -ForegroundColor Yellow
    }
}

# Generate reports
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Generating Reports" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

$jsonPath = Export-TestResults -OutputPath $OutputPath -Prefix "SECURITY_TEST_RESULTS_LOCAL"
$htmlPath = Generate-HtmlReport -OutputPath $OutputPath -Prefix "SECURITY_TEST_RESULTS_LOCAL" -Title "DedgeAuth Security Test Results"

# Summary
$totalTests = $Global:SecurityTestResults.Count
$passedTests = ($Global:SecurityTestResults | Where-Object { $_.Passed }).Count
$failedTests = $totalTests - $passedTests

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Test Summary" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "Total Tests:  $totalTests" -ForegroundColor White
Write-Host "Passed:       $passedTests" -ForegroundColor Green
Write-Host "Failed:       $failedTests" -ForegroundColor $(if ($failedTests -gt 0) { "Red" } else { "Green" })
Write-Host ""
Write-Host "Reports:" -ForegroundColor Cyan
Write-Host "  JSON: $jsonPath" -ForegroundColor Gray
Write-Host "  HTML: $htmlPath" -ForegroundColor Gray
Write-Host ""

if ($failedTests -gt 0) {
    Write-Host "Some tests failed. Review the reports for details." -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "All tests passed!" -ForegroundColor Green
    exit 0
}
