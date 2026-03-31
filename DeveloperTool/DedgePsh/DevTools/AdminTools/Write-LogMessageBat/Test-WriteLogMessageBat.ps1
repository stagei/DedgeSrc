param(
    [Parameter(Mandatory = $false)]
    [string]$TestLogFile = "$env:TEMP\Write-LogMessageBat-Test.log",

    [Parameter(Mandatory = $false)]
    [switch]$CleanupAfter
)

<#
.SYNOPSIS
    Test script for Write-LogMessageBat functionality.

.DESCRIPTION
    This script runs comprehensive tests on the Write-LogMessageBat.ps1 and Write-LogMessageBat.bat scripts
    to ensure they work correctly with various parameters and scenarios.

.PARAMETER TestLogFile
    Path to the test log file. Default is in TEMP directory.

.PARAMETER CleanupAfter
    Remove test log file after testing.

.EXAMPLE
    .\Test-WriteLogMessageBat.ps1

.EXAMPLE
    .\Test-WriteLogMessageBat.ps1 -TestLogFile "C:\temp\test.log" -CleanupAfter
#>

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Details = ""
    )

    $status = if ($Passed) { "PASSED" } else { "FAILED" }
    $color = if ($Passed) { "Green" } else { "Red" }

    Write-Host "[$status] $TestName" -ForegroundColor $color
    if ($Details) {
        Write-Host "  Details: $Details" -ForegroundColor Gray
    }

    return $Passed
}

function Test-PowerShellScript {
    param([string]$TestLogFile)

    Write-Host "`n=== Testing PowerShell Script ===" -ForegroundColor Cyan

    $scriptPath = Join-Path $PSScriptRoot "Write-LogMessageBat.ps1"
    $testsPassed = 0
    $totalTests = 0

    # Test 1: Basic message logging
    $totalTests++
    try {
        $result = & $scriptPath -Message "Test message 1" -Level "INFO"
        $passed = $LASTEXITCODE -eq 0
        $testsPassed += Write-TestResult "Basic message logging" $passed
    }
    catch {
        $testsPassed += Write-TestResult "Basic message logging" $false $_.Exception.Message
    }

    # Test 2: Different log levels
    $totalTests++
    try {
        $levels = @("INFO", "WARNING", "ERROR", "DEBUG", "SUCCESS")
        $allPassed = $true
        foreach ($level in $levels) {
            & $scriptPath -Message "Test $level message" -Level $level | Out-Null
            if ($LASTEXITCODE -ne 0) {
                $allPassed = $false
                break
            }
        }
        $testsPassed += Write-TestResult "Different log levels" $allPassed
    }
    catch {
        $testsPassed += Write-TestResult "Different log levels" $false $_.Exception.Message
    }

    # Test 3: File logging
    $totalTests++
    try {
        & $scriptPath -Message "Test file logging" -Level "INFO" -LogFile $TestLogFile | Out-Null
        $passed = ($LASTEXITCODE -eq 0) -and (Test-Path $TestLogFile)
        $testsPassed += Write-TestResult "File logging" $passed
    }
    catch {
        $testsPassed += Write-TestResult "File logging" $false $_.Exception.Message
    }

    # Test 4: No timestamp option
    $totalTests++
    try {
        & $scriptPath -Message "Test no timestamp" -Level "INFO" -NoTimestamp | Out-Null
        $passed = $LASTEXITCODE -eq 0
        $testsPassed += Write-TestResult "No timestamp option" $passed
    }
    catch {
        $testsPassed += Write-TestResult "No timestamp option" $false $_.Exception.Message
    }

    # Test 5: No console option
    $totalTests++
    try {
        & $scriptPath -Message "Test no console" -Level "INFO" -LogFile $TestLogFile -NoConsole | Out-Null
        $passed = $LASTEXITCODE -eq 0
        $testsPassed += Write-TestResult "No console option" $passed
    }
    catch {
        $testsPassed += Write-TestResult "No console option" $false $_.Exception.Message
    }

    # Test 6: Custom color
    $totalTests++
    try {
        & $scriptPath -Message "Test custom color" -Level "INFO" -Color "Magenta" | Out-Null
        $passed = $LASTEXITCODE -eq 0
        $testsPassed += Write-TestResult "Custom color" $passed
    }
    catch {
        $testsPassed += Write-TestResult "Custom color" $false $_.Exception.Message
    }

    return @{ Passed = $testsPassed; Total = $totalTests }
}

function Test-BatchScript {
    param([string]$TestLogFile)

    Write-Host "`n=== Testing Batch Script ===" -ForegroundColor Cyan

    $batchPath = Join-Path $PSScriptRoot "Write-LogMessageBat.bat"
    $testsPassed = 0
    $totalTests = 0

    # Test 1: Basic batch call
    $totalTests++
    try {
        $output = cmd /c "`"$batchPath`" `"Test batch message`" INFO 2>&1"
        $passed = $LASTEXITCODE -eq 0
        $testsPassed += Write-TestResult "Basic batch call" $passed
    }
    catch {
        $testsPassed += Write-TestResult "Basic batch call" $false $_.Exception.Message
    }

    # Test 2: Batch with log file
    $totalTests++
    try {
        $output = cmd /c "`"$batchPath`" `"Test batch file logging`" INFO `"$TestLogFile`" 2>&1"
        $passed = ($LASTEXITCODE -eq 0) -and (Test-Path $TestLogFile)
        $testsPassed += Write-TestResult "Batch with log file" $passed
    }
    catch {
        $testsPassed += Write-TestResult "Batch with log file" $false $_.Exception.Message
    }

    # Test 3: Batch with different levels
    $totalTests++
    try {
        $levels = @("INFO", "WARNING", "ERROR", "DEBUG", "SUCCESS")
        $allPassed = $true
        foreach ($level in $levels) {
            $output = cmd /c "`"$batchPath`" `"Test $level from batch`" $level 2>&1"
            if ($LASTEXITCODE -ne 0) {
                $allPassed = $false
                break
            }
        }
        $testsPassed += Write-TestResult "Batch with different levels" $allPassed
    }
    catch {
        $testsPassed += Write-TestResult "Batch with different levels" $false $_.Exception.Message
    }

    # Test 4: Batch with options
    $totalTests++
    try {
        $output = cmd /c "`"$batchPath`" `"Test with options`" INFO `"$TestLogFile`" NOTIMESTAMP 2>&1"
        $passed = $LASTEXITCODE -eq 0
        $testsPassed += Write-TestResult "Batch with options" $passed
    }
    catch {
        $testsPassed += Write-TestResult "Batch with options" $false $_.Exception.Message
    }

    return @{ Passed = $testsPassed; Total = $totalTests }
}

function Test-LogFileContent {
    param([string]$TestLogFile)

    Write-Host "`n=== Testing Log File Content ===" -ForegroundColor Cyan

    $testsPassed = 0
    $totalTests = 0

    # Test 1: Log file exists and has content
    $totalTests++
    try {
        $passed = (Test-Path $TestLogFile) -and ((Get-Content $TestLogFile).Count -gt 0)
        $testsPassed += Write-TestResult "Log file exists and has content" $passed
    }
    catch {
        $testsPassed += Write-TestResult "Log file exists and has content" $false $_.Exception.Message
    }

    # Test 2: Log file contains expected format
    $totalTests++
    try {
        $content = Get-Content $TestLogFile -Raw
        $hasTimestamp = $content -match '\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]'
        $hasLevel = $content -match '\[INFO\]|\[WARNING\]|\[ERROR\]|\[DEBUG\]|\[SUCCESS\]'
        $passed = $hasTimestamp -and $hasLevel
        $testsPassed += Write-TestResult "Log file contains expected format" $passed
    }
    catch {
        $testsPassed += Write-TestResult "Log file contains expected format" $false $_.Exception.Message
    }

    return @{ Passed = $testsPassed; Total = $totalTests }
}

# Main test execution
Write-Host "Starting Write-LogMessageBat Tests..." -ForegroundColor Yellow
Write-Host "Test log file: $TestLogFile" -ForegroundColor Gray

# Clean up any existing test log file
if (Test-Path $TestLogFile) {
    Remove-Item $TestLogFile -Force
}

# Run tests
$psResults = Test-PowerShellScript -TestLogFile $TestLogFile
$batchResults = Test-BatchScript -TestLogFile $TestLogFile
$logResults = Test-LogFileContent -TestLogFile $TestLogFile

# Calculate totals
$totalPassed = $psResults.Passed + $batchResults.Passed + $logResults.Passed
$totalTests = $psResults.Total + $batchResults.Total + $logResults.Total

# Display summary
Write-Host "`n=== Test Summary ===" -ForegroundColor Yellow
Write-Host "Total Tests: $totalTests" -ForegroundColor White
Write-Host "Passed: $totalPassed" -ForegroundColor Green
Write-Host "Failed: $($totalTests - $totalPassed)" -ForegroundColor Red
Write-Host "Success Rate: $([math]::Round(($totalPassed / $totalTests) * 100, 2))%" -ForegroundColor Cyan

# Show log file content if it exists
if (Test-Path $TestLogFile) {
    Write-Host "`n=== Sample Log File Content ===" -ForegroundColor Yellow
    Get-Content $TestLogFile | Select-Object -Last 5 | ForEach-Object {
        Write-Host $_ -ForegroundColor Gray
    }
}

# Cleanup if requested
if ($CleanupAfter -and (Test-Path $TestLogFile)) {
    Remove-Item $TestLogFile -Force
    Write-Host "`nTest log file cleaned up." -ForegroundColor Gray
}

# Exit with appropriate code
if ($totalPassed -eq $totalTests) {
    Write-Host "`nAll tests passed!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`nSome tests failed!" -ForegroundColor Red
    exit 1
}

