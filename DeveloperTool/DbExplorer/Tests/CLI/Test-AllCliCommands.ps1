# Comprehensive CLI Command Testing Script
# Tests ALL CLI commands with file output and generates detailed report
# Provider-independent: use -Profile / -Provider or env WDE_TEST_PROFILE, WDE_TEST_PROVIDER

param(
    [Parameter(Mandatory=$false)]
    [string]$ProfileName,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet('', 'DB2', 'PostgreSQL')]
    [string]$Provider,
    
    [Parameter(Mandatory=$false)]
    [string]$TestSchema = "INL",
    
    [Parameter(Mandatory=$false)]
    [string]$TestTable = "INL.BILAGNR"
)

# Load shared config (profile/provider from env if not passed)
$testsRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $testsRoot "TestConfig.ps1") -Profile $ProfileName -Provider $Provider
$ProfileName = Get-WdeTestProfile
$Provider = Get-WdeTestProvider

$ErrorActionPreference = "Continue"
$AppPath = "bin\Debug\net10.0-windows\DbExplorer.exe"
$OutputDir = "CLI_Test_Output"
$ReportFile = Join-Path $OutputDir "TEST_REPORT_$(Get-Date -Format 'yyyyMMdd_HHmmss').md"

# Create output directory
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

# Initialize report
$report = @"
# CLI Command Test Report
**Date**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
**Profile**: $ProfileName
**Provider**: $(if ($Provider) { $Provider } else { 'all' })
**Test Schema**: $TestSchema
**Test Table**: $TestTable

---

## Test Summary

"@

# Test statistics
$totalTests = 0
$passedTests = 0
$failedTests = 0
$testResults = @()

# Define all CLI commands to test (organized by category)
$cliCommands = @{
    "Table Details Commands" = @(
        @{name="table-props"; args="-Object `"$TestTable`""},
        @{name="table-columns"; args="-Object `"$TestTable`""},
        @{name="table-foreign-keys"; args="-Object `"$TestTable`""},
        @{name="table-indexes"; args="-Object `"$TestTable`""},
        @{name="table-statistics-full"; args="-Object `"$TestTable`""},
        @{name="table-ddl"; args="-Object `"$TestTable`""},
        @{name="table-incoming-fks"; args="-Object `"$TestTable`""},
        @{name="table-referencing-packages"; args="-Object `"$TestTable`""},
        @{name="table-referencing-views"; args="-Object `"$TestTable`""},
        @{name="table-referencing-routines"; args="-Object `"$TestTable`""}
    )
    
    "Database Load Monitor Commands" = @(
        @{name="database-load"; args=""},
        @{name="database-load-full"; args=""},
        @{name="table-activity"; args=""},
        @{name="top-active-tables"; args="-Limit 10"}
    )
    
    "Lock Monitor Commands" = @(
        @{name="lock-monitor"; args=""},
        @{name="lock-monitor-full"; args=""},
        @{name="lock-chains"; args=""}
    )
    
    "Statistics Manager Commands" = @(
        @{name="statistics-overview"; args=""},
        @{name="statistics-recommendations"; args=""},
        @{name="index-statistics"; args="-Schema `"$TestSchema`""}
    )
    
    "Active Sessions Commands" = @(
        @{name="active-sessions"; args=""},
        @{name="active-sessions-full"; args=""},
        @{name="session-details"; args="-Object `"1`""},
        @{name="long-running-sessions"; args=""}
    )
    
    "CDC Manager Commands" = @(
        @{name="cdc-info"; args="-Object `"$TestTable`""},
        @{name="cdc-status-full"; args=""},
        @{name="cdc-configuration"; args=""},
        @{name="cdc-changes"; args="-Object `"$TestTable`""}
    )
    
    "Unused Objects Commands" = @(
        @{name="unused-tables"; args="-Schema `"$TestSchema`""},
        @{name="unused-indexes"; args="-Schema `"$TestSchema`""},
        @{name="unused-views"; args="-Schema `"$TestSchema`""},
        @{name="unused-routines"; args="-Schema `"$TestSchema`""}
    )
    
    "Source Code Browser Commands" = @(
        @{name="list-all-source"; args="-Schema `"$TestSchema`""},
        @{name="source-code-full"; args="-Object `"$TestSchema.MY_PROC`""},
        @{name="source-search"; args="-Sql `"SELECT`""}
    )
    
    "Package Analyzer Commands" = @(
        @{name="list-packages"; args="-Schema `"$TestSchema`""},
        @{name="package-analysis"; args="-Object `"$TestSchema.MY_PACKAGE`""},
        @{name="package-details"; args="-Object `"$TestSchema.MY_PACKAGE`""}
    )
    
    "Comment Manager Commands" = @(
        @{name="list-comments"; args="-Schema `"$TestSchema`""},
        @{name="object-comment"; args="-Object `"$TestTable`""},
        @{name="missing-comments"; args="-Schema `"$TestSchema`""}
    )
    
    "Dependency Analyzer Commands" = @(
        @{name="dependencies"; args="-Object `"$TestTable`""},
        @{name="dependency-graph"; args="-Object `"$TestTable`""},
        @{name="dependency-impact"; args="-Object `"$TestTable`""},
        @{name="dependency-chain"; args="-Object `"$TestTable`""}
    )
    
    "Migration Assistant Commands" = @(
        @{name="migration-plan"; args="-Schema `"$TestSchema`""},
        @{name="migration-ddl"; args="-Schema `"$TestSchema`""},
        @{name="migration-data-script"; args="-Object `"$TestTable`""}
    )
    
    "Mermaid Visual Designer Commands" = @(
        @{name="mermaid-erd"; args="-Schema `"$TestSchema`" -Limit 3"},
        @{name="mermaid-from-sql"; args="-Sql `"CREATE TABLE TEST (ID INT)`""},
        @{name="sql-from-mermaid"; args="-Sql `"erDiagram`nTEST {`nINT ID PK`n}`""},
        @{name="sql-translate"; args="-Sql `"CREATE TABLE TEST (ID INT)`" -ObjectType PostgreSQL"}
    )
    
    "List Commands" = @(
        @{name="list-tables"; args="-Schema `"$TestSchema`""},
        @{name="list-views"; args="-Schema `"$TestSchema`""},
        @{name="list-procedures"; args="-Schema `"$TestSchema`""},
        @{name="list-triggers"; args="-Schema `"$TestSchema`""},
        @{name="list-functions"; args="-Schema `"$TestSchema`""},
        @{name="list-schemas"; args=""},
        @{name="list-tablespaces"; args=""},
        @{name="list-indexes-all"; args="-Schema `"$TestSchema`""},
        @{name="list-constraints"; args="-Schema `"$TestSchema`""},
        @{name="list-sequences"; args="-Schema `"$TestSchema`""}
    )
    
    "Object Details Commands" = @(
        @{name="trigger-info"; args="-Object `"$TestSchema.MY_TRIGGER`""},
        @{name="trigger-usage"; args="-Object `"$TestSchema.MY_TRIGGER`""},
        @{name="view-info"; args="-Object `"$TestSchema.MY_VIEW`""},
        @{name="procedure-info"; args="-Object `"$TestSchema.MY_PROC`""},
        @{name="function-info"; args="-Object `"$TestSchema.MY_FUNC`""}
    )
    
    "Export Commands" = @(
        @{name="export-table-data"; args="-Object `"$TestTable`" -Limit 100"},
        @{name="export-query-results"; args="-Sql `"SELECT * FROM $TestTable FETCH FIRST 10 ROWS ONLY`""},
        @{name="export-schema-ddl"; args="-Schema `"$TestSchema`""}
    )
    
    "Schema Compare Commands" = @(
        @{name="schema-compare"; args="-Schema `"$TestSchema`" -Sql `"$TestSchema`""},
        @{name="schema-diff-ddl"; args="-Schema `"$TestSchema`" -Sql `"$TestSchema`""}
    )
    
    "Size Commands" = @(
        @{name="table-size"; args="-Object `"$TestTable`""},
        @{name="schema-size"; args="-Schema `"$TestSchema`""},
        @{name="database-size"; args=""}
    )
    
    "User/Privileges Commands" = @(
        @{name="user-info-enhanced"; args="-Object `"DB2INST1`""},
        @{name="user-privileges-full"; args="-Object `"DB2INST1`""},
        @{name="table-grants"; args="-Object `"$TestTable`""}
    )
    
    "Metadata Commands" = @(
        @{name="query-history"; args=""},
        @{name="schema-metadata"; args="-Schema `"$TestSchema`""},
        @{name="database-metadata"; args=""},
        @{name="db-config"; args=""}
    )
    
    "Connection Commands" = @(
        @{name="connection-profiles"; args=""},
        @{name="connection-stats"; args=""},
        @{name="connection-test"; args=""}
    )
    
    "SQL Tools Commands" = @(
        @{name="sql-validate"; args="-Sql `"SELECT * FROM $TestTable`""},
        @{name="sql-format"; args="-Sql `"SELECT * FROM $TestTable WHERE ID=1`""}
    )
    
    "Meta Commands" = @(
        @{name="help-all"; args=""},
        @{name="cli-version"; args=""}
    )
}

function Test-CLICommand {
    param(
        [string]$CommandName,
        [string]$Arguments,
        [string]$Category
    )
    
    $script:totalTests++
    $outputFile = Join-Path $OutputDir "$CommandName.json"
    
    Write-Host "`nTesting: $CommandName" -ForegroundColor Cyan
    Write-Host "Category: $Category" -ForegroundColor Gray
    Write-Host "Arguments: $Arguments" -ForegroundColor Gray
    
    $fullArgs = "-Profile `"$ProfileName`" -Command `"$CommandName`" $Arguments -Outfile `"$outputFile`""
    $startTime = Get-Date
    
    try {
        $process = Start-Process -FilePath $AppPath -ArgumentList $fullArgs -Wait -PassThru -NoNewWindow -RedirectStandardError "$OutputDir\$CommandName.err"
        $duration = (Get-Date) - $startTime
        
        if ($process.ExitCode -eq 0 -and (Test-Path $outputFile)) {
            $fileSize = (Get-Item $outputFile).Length
            Write-Host "✓ PASSED ($([math]::Round($duration.TotalSeconds, 2))s, $fileSize bytes)" -ForegroundColor Green
            $script:passedTests++
            
            return @{
                Command = $CommandName
                Category = $Category
                Status = "PASSED"
                Duration = $duration.TotalSeconds
                FileSize = $fileSize
                OutputFile = $outputFile
                Arguments = $Arguments
                ErrorMessage = $null
            }
        }
        else {
            $errorMsg = if (Test-Path "$OutputDir\$CommandName.err") {
                Get-Content "$OutputDir\$CommandName.err" -Raw
            } else {
                "Exit code: $($process.ExitCode)"
            }
            
            Write-Host "✗ FAILED: $errorMsg" -ForegroundColor Red
            $script:failedTests++
            
            return @{
                Command = $CommandName
                Category = $Category
                Status = "FAILED"
                Duration = $duration.TotalSeconds
                FileSize = 0
                OutputFile = $null
                Arguments = $Arguments
                ErrorMessage = $errorMsg
            }
        }
    }
    catch {
        Write-Host "✗ EXCEPTION: $($_.Exception.Message)" -ForegroundColor Red
        $script:failedTests++
        
        return @{
            Command = $CommandName
            Category = $Category
            Status = "EXCEPTION"
            Duration = 0
            FileSize = 0
            OutputFile = $null
            Arguments = $Arguments
            ErrorMessage = $_.Exception.Message
        }
    }
}

# Run all tests
Write-Host "`n═══════════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host "  CLI COMMAND COMPREHENSIVE TEST SUITE" -ForegroundColor Magenta
Write-Host "═══════════════════════════════════════════════════════════`n" -ForegroundColor Magenta
Write-Host "Profile: $ProfileName" -ForegroundColor Yellow
Write-Host "Schema: $TestSchema" -ForegroundColor Yellow
Write-Host "Table: $TestTable" -ForegroundColor Yellow
Write-Host "Output: $OutputDir" -ForegroundColor Yellow
Write-Host ""

foreach ($category in $cliCommands.Keys) {
    Write-Host "`n╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host " $category" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    foreach ($cmd in $cliCommands[$category]) {
        if (-not (Test-WdeCommandSupportedForProvider -CommandName $cmd.name)) {
            Write-Host "  Skipping $($cmd.name) (not supported for provider: $Provider)" -ForegroundColor DarkGray
            continue
        }
        $result = Test-CLICommand -CommandName $cmd.name -Arguments $cmd.args -Category $category
        $testResults += $result
        Start-Sleep -Milliseconds 500  # Brief pause between tests
    }
}

# Generate detailed report
$report += @"
**Total Tests**: $totalTests
**Passed**: $passedTests ✓
**Failed**: $failedTests ✗
**Success Rate**: $([math]::Round(($passedTests / $totalTests) * 100, 2))%

---

## Test Results by Category

"@

foreach ($category in $cliCommands.Keys) {
    $categoryResults = $testResults | Where-Object { $_.Category -eq $category }
    $categoryPassed = ($categoryResults | Where-Object { $_.Status -eq "PASSED" }).Count
    $categoryTotal = $categoryResults.Count
    
    $report += @"

### $category
**Passed**: $categoryPassed / $categoryTotal

| Command | Status | Duration (s) | File Size (bytes) | Arguments |
|---------|--------|--------------|-------------------|-----------|
"@
    
    foreach ($result in $categoryResults) {
        $statusIcon = if ($result.Status -eq "PASSED") { "✓" } else { "✗" }
        $duration = [math]::Round($result.Duration, 2)
        $report += "`n| ``$($result.Command)`` | $statusIcon $($result.Status) | $duration | $($result.FileSize) | $($result.Arguments) |"
    }
}

# Add failed tests section
$failedResults = $testResults | Where-Object { $_.Status -ne "PASSED" }
if ($failedResults.Count -gt 0) {
    $report += @"


---

## Failed Tests Details

"@
    
    foreach ($result in $failedResults) {
        $report += @"

### ❌ $($result.Command)
**Category**: $($result.Category)
**Arguments**: ``$($result.Arguments)``
**Error**: 
``````
$($result.ErrorMessage)
``````

"@
    }
}

# Add summary
$report += @"


---

## Files Generated

All test outputs are saved in: ``$OutputDir/``

- ``*.json`` - Command output files
- ``*.err`` - Error logs (if any)
- ``TEST_REPORT_*.md`` - This report

---

## Next Steps

1. Review failed tests and fix any issues
2. Verify JSON output files contain expected data
3. Ensure all View menu items have corresponding CLI commands
4. Update documentation with CLI command usage examples

---

**Report Generated**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@

# Save report
$report | Out-File -FilePath $ReportFile -Encoding UTF8

# Display summary
Write-Host "`n`n═══════════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host "  TEST COMPLETE" -ForegroundColor Magenta
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host "`nTotal Tests: $totalTests" -ForegroundColor Yellow
Write-Host "Passed: $passedTests" -ForegroundColor Green
Write-Host "Failed: $failedTests" -ForegroundColor Red
Write-Host "Success Rate: $([math]::Round(($passedTests / $totalTests) * 100, 2))%" -ForegroundColor $(if ($passedTests -eq $totalTests) { "Green" } else { "Yellow" })
Write-Host "`nReport saved to: $ReportFile" -ForegroundColor Cyan
Write-Host "Output files in: $OutputDir" -ForegroundColor Cyan
Write-Host ""

# Open report in default editor
Start-Process $ReportFile

exit 0

