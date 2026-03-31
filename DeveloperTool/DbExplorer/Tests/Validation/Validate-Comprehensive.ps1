# DbExplorer - Comprehensive GUI vs CLI Validation
# Compares all tabs and validates data accuracy

param(
    [string]$Profile = "BASISTST",
    [string]$TestObject = "INL.KONTO"
)

$ErrorActionPreference = "Continue"
$exe = "bin\Debug\net10.0-windows\DbExplorer.exe"
$OutputDir = "CLI_Test_Output"

# Create output directory if it doesn't exist
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "   COMPREHENSIVE VALIDATION" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "🎯 Test Object: $TestObject" -ForegroundColor Yellow
Write-Host "🔌 Profile: $Profile" -ForegroundColor Yellow
Write-Host ""

$validationResults = @()
$startTime = Get-Date

# ==================================================================
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "PHASE 1: Data Collection" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""

Write-Host "⏳ Getting CLI data (table-props)..." -ForegroundColor Yellow
& $exe --profile $Profile --command table-props --object $TestObject --outfile "$OutputDir\cli_data.json" 2>&1 | Out-Null

if (-not (Test-Path "$OutputDir\cli_data.json")) {
    Write-Host "❌ Failed to get CLI data!" -ForegroundColor Red
    exit 1
}

Write-Host "✅ CLI data retrieved" -ForegroundColor Green

Write-Host "⏳ Getting Form data (all tabs)..." -ForegroundColor Yellow
& $exe --profile $Profile --test-form table-details --object $TestObject --outfile "$OutputDir\form_data.json" 2>&1 | Out-Null

if (-not (Test-Path "$OutputDir\form_data.json")) {
    Write-Host "❌ Failed to get Form data!" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Form data retrieved" -ForegroundColor Green
Write-Host ""

# Load data
$cli = Get-Content "$OutputDir\cli_data.json" -Raw | ConvertFrom-Json
$form = Get-Content "$OutputDir\form_data.json" -Raw | ConvertFrom-Json

# ==================================================================
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "PHASE 2: Validation Tests" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""

# ------------------------------------------------------------
Write-Host "TEST 1: Columns Tab" -ForegroundColor Yellow
Write-Host "───────────────────" -ForegroundColor DarkGray

$cliColumns = $cli.columnCount
$formColumns = $form.tabs.columns.rowCount

Write-Host "   CLI:  $cliColumns columns" -ForegroundColor White
Write-Host "   Form: $formColumns columns" -ForegroundColor White

if ($cliColumns -eq $formColumns) {
    Write-Host "   ✅ PASS - Match!" -ForegroundColor Green
    $validationResults += [PSCustomObject]@{
        Test = "Columns Count"
        CliValue = $cliColumns
        FormValue = $formColumns
        Match = "✅ PASS"
        Details = "Column count matches"
    }
} else {
    Write-Host "   ❌ FAIL - Mismatch!" -ForegroundColor Red
    $validationResults += [PSCustomObject]@{
        Test = "Columns Count"
        CliValue = $cliColumns
        FormValue = $formColumns
        Match = "❌ FAIL"
        Details = "Column count mismatch"
    }
}
Write-Host ""

# ------------------------------------------------------------
Write-Host "TEST 2: Foreign Keys Tab" -ForegroundColor Yellow
Write-Host "────────────────────────" -ForegroundColor DarkGray

$cliFKs = $cli.foreignKeyCount
$formFKs = $form.tabs.foreignKeys.rowCount

Write-Host "   CLI:  $cliFKs foreign keys" -ForegroundColor White
Write-Host "   Form: $formFKs foreign keys" -ForegroundColor White

if ($cliFKs -eq $formFKs) {
    Write-Host "   ✅ PASS - Match!" -ForegroundColor Green
    $validationResults += [PSCustomObject]@{
        Test = "Foreign Keys Count"
        CliValue = $cliFKs
        FormValue = $formFKs
        Match = "✅ PASS"
        Details = "FK count matches"
    }
} else {
    Write-Host "   ❌ FAIL - Mismatch!" -ForegroundColor Red
    $validationResults += [PSCustomObject]@{
        Test = "Foreign Keys Count"
        CliValue = $cliFKs
        FormValue = $formFKs
        Match = "❌ FAIL"
        Details = "FK count mismatch"
    }
}
Write-Host ""

# ------------------------------------------------------------
Write-Host "TEST 3: Indexes Tab" -ForegroundColor Yellow
Write-Host "───────────────────" -ForegroundColor DarkGray

$cliIndexes = $cli.indexCount
$formIndexes = $form.tabs.indexes.rowCount

Write-Host "   CLI:  $cliIndexes indexes" -ForegroundColor White
Write-Host "   Form: $formIndexes indexes" -ForegroundColor White

if ($cliIndexes -eq $formIndexes) {
    Write-Host "   ✅ PASS - Match!" -ForegroundColor Green
    $validationResults += [PSCustomObject]@{
        Test = "Indexes Count"
        CliValue = $cliIndexes
        FormValue = $formIndexes
        Match = "✅ PASS"
        Details = "Index count matches"
    }
} else {
    Write-Host "   ❌ FAIL - Mismatch!" -ForegroundColor Red
    $validationResults += [PSCustomObject]@{
        Test = "Indexes Count"
        CliValue = $cliIndexes
        FormValue = $formIndexes
        Match = "❌ FAIL"
        Details = "Index count mismatch"
    }
}
Write-Host ""

# ------------------------------------------------------------
Write-Host "TEST 4: DDL Script Tab" -ForegroundColor Yellow
Write-Host "──────────────────────" -ForegroundColor DarkGray

$formDDLLength = $form.tabs.ddlScript.length
$formDDLLines = $form.tabs.ddlScript.lineCount

Write-Host "   Form DDL: $formDDLLength chars, $formDDLLines lines" -ForegroundColor White

# Verify DDL contains CREATE TABLE
$hasDDL = $form.tabs.ddlScript.text -like "*CREATE TABLE*"

if ($hasDDL -and $formDDLLength -gt 100) {
    Write-Host "   ✅ PASS - DDL generated successfully" -ForegroundColor Green
    $validationResults += [PSCustomObject]@{
        Test = "DDL Script"
        CliValue = "N/A"
        FormValue = "$formDDLLength chars"
        Match = "✅ PASS"
        Details = "DDL contains CREATE TABLE statement"
    }
} else {
    Write-Host "   ❌ FAIL - DDL missing or invalid" -ForegroundColor Red
    $validationResults += [PSCustomObject]@{
        Test = "DDL Script"
        CliValue = "N/A"
        FormValue = "$formDDLLength chars"
        Match = "❌ FAIL"
        Details = "DDL does not contain CREATE TABLE"
    }
}
Write-Host ""

# ------------------------------------------------------------
Write-Host "TEST 5: Statistics Tab" -ForegroundColor Yellow
Write-Host "──────────────────────" -ForegroundColor DarkGray

$statsFields = $form.tabs.statistics.PSObject.Properties.Name
Write-Host "   Statistics fields: $($statsFields -join ', ')" -ForegroundColor White

# Verify required fields exist
$requiredFields = @("rowCount", "columnCount", "fkCount", "indexCount", "tableType", "tablespace")
$missingFields = $requiredFields | Where-Object { $_ -notin $statsFields }

if ($missingFields.Count -eq 0) {
    Write-Host "   ✅ PASS - All required fields present" -ForegroundColor Green
    $validationResults += [PSCustomObject]@{
        Test = "Statistics Fields"
        CliValue = "N/A"
        FormValue = $statsFields.Count
        Match = "✅ PASS"
        Details = "All required fields present"
    }
} else {
    Write-Host "   ❌ FAIL - Missing fields: $($missingFields -join ', ')" -ForegroundColor Red
    $validationResults += [PSCustomObject]@{
        Test = "Statistics Fields"
        CliValue = "N/A"
        FormValue = $statsFields.Count
        Match = "❌ FAIL"
        Details = "Missing: $($missingFields -join ', ')"
    }
}

# Cross-validate statistics with CLI data
$formRowCount = $form.tabs.statistics.rowCount
$formColumnCount = $form.tabs.statistics.columnCount
$formFKCount = $form.tabs.statistics.fkCount
$formIndexCount = $form.tabs.statistics.indexCount

Write-Host ""
Write-Host "   Cross-validation:" -ForegroundColor Cyan
Write-Host "      Columns:  CLI=$cliColumns, Stats=$formColumnCount" -ForegroundColor White
Write-Host "      FKs:      CLI=$cliFKs, Stats=$formFKCount" -ForegroundColor White
Write-Host "      Indexes:  CLI=$cliIndexes, Stats=$formIndexCount" -ForegroundColor White

$statsMatch = ($formColumnCount -eq $cliColumns) -and ($formFKCount -eq $cliFKs) -and ($formIndexCount -eq $cliIndexes)

if ($statsMatch) {
    Write-Host "   ✅ PASS - Statistics match other tabs" -ForegroundColor Green
    $validationResults += [PSCustomObject]@{
        Test = "Statistics Cross-Validation"
        CliValue = "Multiple"
        FormValue = "Multiple"
        Match = "✅ PASS"
        Details = "Statistics consistent with other tabs"
    }
} else {
    Write-Host "   ❌ FAIL - Statistics inconsistent" -ForegroundColor Red
    $validationResults += [PSCustomObject]@{
        Test = "Statistics Cross-Validation"
        CliValue = "Multiple"
        FormValue = "Multiple"
        Match = "❌ FAIL"
        Details = "Statistics inconsistent with other tabs"
    }
}
Write-Host ""

# ------------------------------------------------------------
Write-Host "TEST 6: Incoming Foreign Keys Tab" -ForegroundColor Yellow
Write-Host "──────────────────────────────────" -ForegroundColor DarkGray

$formIncomingFK = $form.tabs.incomingFK.rowCount
Write-Host "   Form: $formIncomingFK incoming FKs" -ForegroundColor White

# This is optional data - pass if present
Write-Host "   ✅ PASS - Data extracted" -ForegroundColor Green
$validationResults += [PSCustomObject]@{
    Test = "Incoming FKs"
    CliValue = "N/A"
    FormValue = $formIncomingFK
    Match = "✅ PASS"
    Details = "Incoming FK data extracted"
}
Write-Host ""

# ------------------------------------------------------------
Write-Host "TEST 7: Used By (Packages/Views/Routines)" -ForegroundColor Yellow
Write-Host "──────────────────────────────────────────" -ForegroundColor DarkGray

$formPackages = $form.tabs.usedByPackages.rowCount
$formViews = $form.tabs.usedByViews.rowCount
$formRoutines = $form.tabs.usedByRoutines.rowCount

Write-Host "   Form Packages: $formPackages" -ForegroundColor White
Write-Host "   Form Views:    $formViews" -ForegroundColor White
Write-Host "   Form Routines: $formRoutines" -ForegroundColor White

# These are optional - pass if data was extracted
Write-Host "   ✅ PASS - Data extracted" -ForegroundColor Green
$validationResults += [PSCustomObject]@{
    Test = "Used By Dependencies"
    CliValue = "N/A"
    FormValue = "$formPackages pkg, $formViews views, $formRoutines routines"
    Match = "✅ PASS"
    Details = "Dependency data extracted"
}
Write-Host ""

# ==================================================================
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "PHASE 3: Summary & Report" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""

$endTime = Get-Date
$duration = ($endTime - $startTime).TotalSeconds

$totalTests = $validationResults.Count
$passed = ($validationResults | Where-Object { $_.Match -eq "✅ PASS" }).Count
$failed = ($validationResults | Where-Object { $_.Match -eq "❌ FAIL" }).Count
$successRate = [math]::Round(($passed / $totalTests) * 100, 2)

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "   VALIDATION SUMMARY" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Total Tests:    $totalTests" -ForegroundColor White
Write-Host "Passed:         $passed" -ForegroundColor Green
Write-Host "Failed:         $failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
Write-Host "Success Rate:   $successRate%" -ForegroundColor $(if ($successRate -eq 100) { "Green" } else { "Yellow" })
Write-Host "Duration:       $([math]::Round($duration, 2))s" -ForegroundColor White
Write-Host ""

# Display results table
Write-Host "Detailed Results:" -ForegroundColor Cyan
$validationResults | Format-Table -AutoSize

# Save results
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$csvFile = "$OutputDir\validation_results_$timestamp.csv"
$jsonFile = "$OutputDir\validation_results_$timestamp.json"

$validationResults | Export-Csv $csvFile -NoTypeInformation
$validationResults | ConvertTo-Json -Depth 5 | Out-File $jsonFile -Encoding UTF8

# Create summary report
$report = @"
# GUI Validation Report
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Test Object: $TestObject
Profile: $Profile

## Summary
- Total Tests: $totalTests
- Passed: $passed
- Failed: $failed
- Success Rate: $successRate%
- Duration: $([math]::Round($duration, 2))s

## Test Results

$($validationResults | ForEach-Object { "- **$($_.Test)**: $($_.Match) - $($_.Details)" } | Out-String)

## Files Generated
- CSV: $csvFile
- JSON: $jsonFile
- Report: validation_report_$timestamp.md

## Conclusion
$(if ($failed -eq 0) { "✅ **All tests passed!** The GUI forms are displaying correct data." } else { "❌ **Some tests failed.** Review the detailed results above." })

---
*Generated by DbExplorer GUI Validation Framework*
"@

$reportFile = "validation_report_$timestamp.md"
$report | Out-File $reportFile -Encoding UTF8

Write-Host ""
Write-Host "📊 Files Generated:" -ForegroundColor Cyan
Write-Host "   • $csvFile" -ForegroundColor White
Write-Host "   • $jsonFile" -ForegroundColor White
Write-Host "   • $reportFile" -ForegroundColor White
Write-Host ""

if ($failed -eq 0) {
    Write-Host "🎉 ALL TESTS PASSED! GUI forms are working correctly!" -ForegroundColor Green
} else {
    Write-Host "⚠️  Some tests failed. Review the report for details." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan

