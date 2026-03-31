<#
.SYNOPSIS
    Generates a comprehensive test report for a database provider

.DESCRIPTION
    Aggregates all test results (Object Types, Tab Selection, CLI vs Form)
    and generates a comprehensive HTML/Markdown report.

.PARAMETER Provider
    Provider name (e.g., "DB2", "PostgreSQL")

.PARAMETER InputPath
    Path to test results JSON files

.PARAMETER OutputPath
    Path to save the report

.PARAMETER Format
    Output format: "Markdown" or "HTML" (default: Markdown)

.EXAMPLE
    .\Generate-ProviderReport.ps1 -Provider "DB2" -InputPath "..\TestResults"

.EXAMPLE
    .\Generate-ProviderReport.ps1 -Provider "PostgreSQL" -InputPath "..\TestResults" -Format "HTML"

.NOTES
    Version: 1.0
    Author: DbExplorer Project
    Date: December 14, 2025
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Provider,
    
    [Parameter(Mandatory=$false)]
    [string]$InputPath = "..\TestResults",
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "..\TestResults",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("Markdown", "HTML")]
    [string]$Format = "Markdown"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  📊 GENERATING PROVIDER REPORT" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Provider: $Provider" -ForegroundColor White
Write-Host "Input: $InputPath" -ForegroundColor White
Write-Host "Format: $Format" -ForegroundColor White
Write-Host ""

# Find all test result files for this provider
$testFiles = Get-ChildItem -Path $InputPath -Filter "$Provider_*.json" | Sort-Object LastWriteTime -Descending

if ($testFiles.Count -eq 0) {
    Write-Host "❌ No test results found for $Provider in $InputPath" -ForegroundColor Red
    exit 1
}

Write-Host "Found $($testFiles.Count) test result file(s)" -ForegroundColor Green
Write-Host ""

# Load and aggregate results
$objectTypesResults = $null
$tabSelectionResults = $null
$cliVsFormResults = $null

foreach ($file in $testFiles) {
    $data = Get-Content $file.FullName | ConvertFrom-Json
    
    switch ($data.testType) {
        "ObjectTypes" { 
            if (-not $objectTypesResults) { $objectTypesResults = $data }
        }
        "TabSelection" { 
            if (-not $tabSelectionResults) { $tabSelectionResults = $data }
        }
        "CliVsForm" { 
            if (-not $cliVsFormResults) { $cliVsFormResults = $data }
        }
    }
}

# Generate report content
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$reportContent = @"
# $Provider Provider Test Report

**Generated**: $timestamp  
**Provider**: $Provider  
**Version**: $($objectTypesResults.version)

---

## 📊 Executive Summary

"@

# Calculate overall stats
$totalTests = 0
$totalPassed = 0
$totalFailed = 0

if ($objectTypesResults) {
    $totalTests += $objectTypesResults.results.total
    $totalPassed += $objectTypesResults.results.passed
    $totalFailed += $objectTypesResults.results.failed
}

if ($tabSelectionResults) {
    $totalTests += $tabSelectionResults.results.total
    $totalPassed += $tabSelectionResults.results.passed
    $totalFailed += $tabSelectionResults.results.failed
}

if ($cliVsFormResults) {
    $totalTests += $cliVsFormResults.results.total
    $totalPassed += $cliVsFormResults.results.passed
    $totalFailed += $cliVsFormResults.results.failed
}

$overallPassRate = if ($totalTests -gt 0) { [math]::Round(($totalPassed / $totalTests) * 100, 2) } else { 0 }

$reportContent += @"

| Metric | Value |
|--------|-------|
| Total Tests | $totalTests |
| Passed | $totalPassed |
| Failed | $totalFailed |
| Pass Rate | $overallPassRate% |
| Status | $(if ($totalFailed -eq 0) { "✅ PASS" } else { "⚠️ NEEDS ATTENTION" }) |

---

## 🎯 Test Results by Category

"@

# Object Types section
if ($objectTypesResults) {
    $reportContent += @"

### Object Types Test

| Metric | Value |
|--------|-------|
| Total Object Types | $($objectTypesResults.results.total) |
| Passed | $($objectTypesResults.results.passed) |
| Failed | $($objectTypesResults.results.failed) |
| Skipped | $($objectTypesResults.results.skipped) |
| Pass Rate | $($objectTypesResults.results.passRate)% |
| Test Date | $($objectTypesResults.testDate) |

"@
}

# Tab Selection section
if ($tabSelectionResults) {
    $reportContent += @"

### Tab Selection Test

| Metric | Value |
|--------|-------|
| Total Tabs | $($tabSelectionResults.results.total) |
| Passed | $($tabSelectionResults.results.passed) |
| Failed | $($tabSelectionResults.results.failed) |
| Skipped | $($tabSelectionResults.results.skipped) |
| Pass Rate | $($tabSelectionResults.results.passRate)% |
| Test Date | $($tabSelectionResults.testDate) |

"@
}

# CLI vs Form section
if ($cliVsFormResults) {
    $reportContent += @"

### CLI vs Form Validation

| Metric | Value |
|--------|-------|
| Total Validations | $($cliVsFormResults.results.total) |
| Passed | $($cliVsFormResults.results.passed) |
| Failed | $($cliVsFormResults.results.failed) |
| Pass Rate | $($cliVsFormResults.results.passRate)% |
| Test Date | $($cliVsFormResults.testDate) |

"@
}

# Failures section
$reportContent += @"

---

## ❌ Failures & Issues

"@

$hasFailures = $false

if ($objectTypesResults -and $objectTypesResults.details) {
    $failures = $objectTypesResults.details | Where-Object { $_.Status -eq "FAIL" }
    if ($failures) {
        $hasFailures = $true
        $reportContent += @"

### Object Type Failures

| Type | Object | Reason |
|------|--------|--------|

"@
        foreach ($fail in $failures) {
            $reportContent += "| $($fail.Type) | $($fail.ObjectName) | $($fail.Reason) |`n"
        }
    }
}

if ($tabSelectionResults -and $tabSelectionResults.details) {
    $failures = $tabSelectionResults.details | Where-Object { $_.Status -eq "FAIL" }
    if ($failures) {
        $hasFailures = $true
        $reportContent += @"

### Tab Selection Failures

| Dialog | Tab | Object |
|--------|-----|--------|

"@
        foreach ($fail in $failures) {
            $reportContent += "| $($fail.Dialog) | $($fail.Tab) | $($fail.Object) |`n"
        }
    }
}

if ($cliVsFormResults -and $cliVsFormResults.details) {
    $failures = $cliVsFormResults.details | Where-Object { $_.Validation -eq "FAIL" }
    if ($failures) {
        $hasFailures = $true
        $reportContent += @"

### CLI vs Form Validation Failures

| Test | CLI Row Count | Form Status |
|------|---------------|-------------|

"@
        foreach ($fail in $failures) {
            $reportContent += "| $($fail.Test) | $($fail.CliRowCount) | $($fail.FormStatus) |`n"
        }
    }
}

if (-not $hasFailures) {
    $reportContent += "`n✅ **No failures detected!**`n"
}

# Recommendations section
$reportContent += @"

---

## 📝 Recommendations

"@

if ($totalFailed -eq 0) {
    $reportContent += @"

✅ **All tests passed!** This provider implementation is ready for production use.

Next steps:
- Perform manual spot-checks on critical features
- Run performance benchmarks
- Update provider documentation
- Create release notes

"@
}
else {
    $reportContent += @"

⚠️ **$totalFailed test(s) failed.** Please address the failures before production deployment.

Recommended actions:
1. Review failed tests in detail
2. Check provider-specific SQL syntax
3. Verify system catalog table structures
4. Consult provider documentation for version-specific changes
5. Re-run tests after fixes

"@
}

# Footer
$reportContent += @"

---

**Report generated by DbExplorer Automated Provider Testing Framework**  
**Framework Version**: 1.0  
**Report Date**: $timestamp

"@

# Save report
$reportFileName = if ($Format -eq "HTML") {
    "$Provider_TestReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
}
else {
    "$Provider_TestReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').md"
}

$reportPath = Join-Path $OutputPath $reportFileName

if ($Format -eq "HTML") {
    # Convert Markdown to basic HTML
    $htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>$Provider Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        h1 { color: #2c3e50; }
        h2 { color: #34495e; border-bottom: 2px solid #3498db; padding-bottom: 10px; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
        th { background-color: #3498db; color: white; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .pass { color: green; font-weight: bold; }
        .fail { color: red; font-weight: bold; }
    </style>
</head>
<body>
$($reportContent -replace '# ', '<h1>' -replace '\n## ', '</h1><h2>' -replace '\n### ', '</h2><h3>' -replace '\n---', '</h3><hr>')
</body>
</html>
"@
    $htmlContent | Out-File $reportPath -Encoding UTF8
}
else {
    $reportContent | Out-File $reportPath -Encoding UTF8
}

Write-Host "✅ Report generated: $reportPath" -ForegroundColor Green
Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Total Tests: $totalTests" -ForegroundColor White
Write-Host "  Passed: $totalPassed" -ForegroundColor Green
Write-Host "  Failed: $totalFailed" -ForegroundColor $(if ($totalFailed -eq 0) { "Green" } else { "Red" })
Write-Host "  Pass Rate: $overallPassRate%" -ForegroundColor Yellow
Write-Host ""

if ($totalFailed -eq 0) {
    Write-Host "🎉 ALL TESTS PASSED!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "⚠️  $totalFailed test(s) failed - review report for details" -ForegroundColor Yellow
    exit 1
}

