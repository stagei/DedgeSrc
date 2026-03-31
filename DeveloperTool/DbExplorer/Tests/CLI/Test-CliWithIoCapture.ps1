# CLI Test with Full Input/Output Capture
# Captures the exact CLI command and its complete output for each test
# Date: December 15, 2025

param(
    [string]$Profile = "FKKTOTST",
    [switch]$SkipBuild,
    [int]$MaxTests = 0  # 0 = run all tests
)

$ErrorActionPreference = "Continue"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputDir = "CLI_Test_Output"
$reportFile = "$outputDir/CLI_IO_TEST_REPORT_$timestamp.md"
$jsonReportFile = "$outputDir/CLI_IO_TEST_REPORT_$timestamp.json"

if (!(Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

$exePath = "bin\Debug\net10.0-windows\DbExplorer.exe"

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "CLI TEST WITH INPUT/OUTPUT CAPTURE" -ForegroundColor Cyan
Write-Host "Connection Profile: $Profile" -ForegroundColor Cyan
Write-Host "Started: $(Get-Date)" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

# Build if not skipped
if (-not $SkipBuild) {
    Write-Host "[BUILD] Building application..." -ForegroundColor Yellow
    $buildResult = dotnet build --verbosity quiet 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ BUILD FAILED" -ForegroundColor Red
        Write-Host $buildResult
        exit 1
    }
    Write-Host "✅ Build successful" -ForegroundColor Green
    Write-Host ""
}

# Test parameters
$testSchema = "INL"
$testTable = "BILAGNR"
$testViewSchema = "SYSIBM"
$testView = "SYSDUMMY1"
$testProcSchema = "SYSPROC"
$testProcedure = "ADMIN_CMD"
$testFuncSchema = "SYSFUN"
$testFunction = "ABS"
$testPkgSchema = "NULLID"
$testPackage = "SYSSH200"
$testUser = "FKGEISTA"

# Define all CLI commands with their test cases
$testCases = @(
    # === CONNECTION & INFO ===
    @{
        Category = "Connection & Info"
        Name = "connection-test"
        Description = "Test database connection"
        Args = @("-profile", $Profile)
    }
    @{
        Category = "Connection & Info"
        Name = "connection-stats"
        Description = "Get connection statistics"
        Args = @("-profile", $Profile)
    }
    @{
        Category = "Connection & Info"
        Name = "help-all"
        Description = "Show all available commands"
        Args = @("-profile", $Profile)
    }
    @{
        Category = "Connection & Info"
        Name = "cli-version"
        Description = "Show CLI version"
        Args = @("-profile", $Profile)
    }
    @{
        Category = "Connection & Info"
        Name = "db-config"
        Description = "Get database configuration"
        Args = @("-profile", $Profile)
    }
    @{
        Category = "Connection & Info"
        Name = "connection-history"
        Description = "Show connection history"
        Args = @("-profile", $Profile)
    }

    # === SCHEMA OPERATIONS ===
    @{
        Category = "Schema Operations"
        Name = "list-schemas"
        Description = "List all schemas"
        Args = @("-profile", $Profile)
    }
    @{
        Category = "Schema Operations"
        Name = "list-tables"
        Description = "List tables in schema"
        Args = @("-profile", $Profile, "-schema", $testSchema)
    }
    @{
        Category = "Schema Operations"
        Name = "list-views"
        Description = "List views in schema"
        Args = @("-profile", $Profile, "-schema", $testSchema)
    }
    @{
        Category = "Schema Operations"
        Name = "list-procedures"
        Description = "List procedures in schema"
        Args = @("-profile", $Profile, "-schema", $testSchema)
    }
    @{
        Category = "Schema Operations"
        Name = "list-functions"
        Description = "List functions in schema"
        Args = @("-profile", $Profile, "-schema", $testSchema)
    }
    @{
        Category = "Schema Operations"
        Name = "list-packages"
        Description = "List packages in schema"
        Args = @("-profile", $Profile, "-schema", $testSchema)
    }
    @{
        Category = "Schema Operations"
        Name = "list-tablespaces"
        Description = "List all tablespaces"
        Args = @("-profile", $Profile)
    }
    @{
        Category = "Schema Operations"
        Name = "list-all-indexes"
        Description = "List all indexes in schema"
        Args = @("-profile", $Profile, "-schema", $testSchema)
    }
    @{
        Category = "Schema Operations"
        Name = "list-constraints"
        Description = "List constraints in schema"
        Args = @("-profile", $Profile, "-schema", $testSchema)
    }
    @{
        Category = "Schema Operations"
        Name = "list-sequences"
        Description = "List sequences in schema"
        Args = @("-profile", $Profile, "-schema", $testSchema)
    }

    # === TABLE OPERATIONS ===
    @{
        Category = "Table Operations"
        Name = "table-properties"
        Description = "Get table properties"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "Table Operations"
        Name = "table-columns"
        Description = "List table columns"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "Table Operations"
        Name = "table-indexes"
        Description = "List table indexes"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "Table Operations"
        Name = "table-foreignkeys"
        Description = "List table foreign keys"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "Table Operations"
        Name = "table-ddl"
        Description = "Generate table DDL"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "Table Operations"
        Name = "table-statistics"
        Description = "Get table statistics"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "Table Operations"
        Name = "table-relationships"
        Description = "Show table relationships"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "Table Operations"
        Name = "table-sample-data"
        Description = "Get sample data from table"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "Table Operations"
        Name = "table-size"
        Description = "Get table size"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "Table Operations"
        Name = "table-grants"
        Description = "List table grants"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "Table Operations"
        Name = "table-dependencies"
        Description = "Show table dependencies"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "Table Operations"
        Name = "table-incoming-fk"
        Description = "List incoming foreign keys"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "Table Operations"
        Name = "table-used-by-packages"
        Description = "List packages using this table"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "Table Operations"
        Name = "table-used-by-views"
        Description = "List views using this table"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "Table Operations"
        Name = "table-used-by-routines"
        Description = "List routines using this table"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testTable")
    }

    # === VIEW OPERATIONS ===
    @{
        Category = "View Operations"
        Name = "view-properties"
        Description = "Get view properties"
        Args = @("-profile", $Profile, "-object", "$testViewSchema.$testView")
    }
    @{
        Category = "View Operations"
        Name = "view-definition"
        Description = "Get view definition SQL"
        Args = @("-profile", $Profile, "-object", "$testViewSchema.$testView")
    }
    @{
        Category = "View Operations"
        Name = "view-columns"
        Description = "List view columns"
        Args = @("-profile", $Profile, "-object", "$testViewSchema.$testView")
    }
    @{
        Category = "View Operations"
        Name = "view-dependencies"
        Description = "Show view dependencies"
        Args = @("-profile", $Profile, "-object", "$testViewSchema.$testView")
    }
    @{
        Category = "View Operations"
        Name = "view-sample-data"
        Description = "Get sample data from view"
        Args = @("-profile", $Profile, "-object", "$testViewSchema.$testView")
    }
    @{
        Category = "View Operations"
        Name = "view-used-by-packages"
        Description = "List packages using this view"
        Args = @("-profile", $Profile, "-object", "$testViewSchema.$testView")
    }
    @{
        Category = "View Operations"
        Name = "view-used-by-views"
        Description = "List views using this view"
        Args = @("-profile", $Profile, "-object", "$testViewSchema.$testView")
    }

    # === PROCEDURE OPERATIONS ===
    @{
        Category = "Procedure Operations"
        Name = "procedure-properties"
        Description = "Get procedure properties"
        Args = @("-profile", $Profile, "-object", "$testProcSchema.$testProcedure")
    }
    @{
        Category = "Procedure Operations"
        Name = "procedure-source"
        Description = "Get procedure source code"
        Args = @("-profile", $Profile, "-object", "$testProcSchema.$testProcedure")
    }
    @{
        Category = "Procedure Operations"
        Name = "procedure-parameters"
        Description = "List procedure parameters"
        Args = @("-profile", $Profile, "-object", "$testProcSchema.$testProcedure")
    }
    @{
        Category = "Procedure Operations"
        Name = "procedure-dependencies"
        Description = "Show procedure dependencies"
        Args = @("-profile", $Profile, "-object", "$testProcSchema.$testProcedure")
    }
    @{
        Category = "Procedure Operations"
        Name = "procedure-usage"
        Description = "Show procedure usage"
        Args = @("-profile", $Profile, "-object", "$testProcSchema.$testProcedure")
    }
    @{
        Category = "Procedure Operations"
        Name = "procedure-grants"
        Description = "List procedure grants"
        Args = @("-profile", $Profile, "-object", "$testProcSchema.$testProcedure")
    }

    # === FUNCTION OPERATIONS ===
    @{
        Category = "Function Operations"
        Name = "function-properties"
        Description = "Get function properties"
        Args = @("-profile", $Profile, "-object", "$testFuncSchema.$testFunction")
    }
    @{
        Category = "Function Operations"
        Name = "function-source"
        Description = "Get function source code"
        Args = @("-profile", $Profile, "-object", "$testFuncSchema.$testFunction")
    }
    @{
        Category = "Function Operations"
        Name = "function-parameters"
        Description = "List function parameters"
        Args = @("-profile", $Profile, "-object", "$testFuncSchema.$testFunction")
    }
    @{
        Category = "Function Operations"
        Name = "function-dependencies"
        Description = "Show function dependencies"
        Args = @("-profile", $Profile, "-object", "$testFuncSchema.$testFunction")
    }
    @{
        Category = "Function Operations"
        Name = "function-usage"
        Description = "Show function usage"
        Args = @("-profile", $Profile, "-object", "$testFuncSchema.$testFunction")
    }
    @{
        Category = "Function Operations"
        Name = "function-grants"
        Description = "List function grants"
        Args = @("-profile", $Profile, "-object", "$testFuncSchema.$testFunction")
    }

    # === PACKAGE OPERATIONS ===
    @{
        Category = "Package Operations"
        Name = "package-properties"
        Description = "Get package properties"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testPackage")
    }
    @{
        Category = "Package Operations"
        Name = "package-statements"
        Description = "List package statements"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testPackage")
    }
    @{
        Category = "Package Operations"
        Name = "package-dependencies"
        Description = "Show package dependencies"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testPackage")
    }
    @{
        Category = "Package Operations"
        Name = "package-statistics"
        Description = "Get package statistics"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testPackage")
    }
    @{
        Category = "Package Operations"
        Name = "package-list-tables"
        Description = "List tables used by package"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testPackage")
    }
    @{
        Category = "Package Operations"
        Name = "package-list-views"
        Description = "List views used by package"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testPackage")
    }
    @{
        Category = "Package Operations"
        Name = "package-list-procedures"
        Description = "List procedures used by package"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testPackage")
    }
    @{
        Category = "Package Operations"
        Name = "package-list-functions"
        Description = "List functions used by package"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testPackage")
    }

    # === USER & SECURITY ===
    @{
        Category = "User & Security"
        Name = "user-properties"
        Description = "Get user properties"
        Args = @("-profile", $Profile, "-object", $testUser)
    }
    @{
        Category = "User & Security"
        Name = "user-privileges"
        Description = "List user privileges"
        Args = @("-profile", $Profile, "-object", $testUser)
    }
    @{
        Category = "User & Security"
        Name = "user-tables"
        Description = "List user's tables"
        Args = @("-profile", $Profile, "-object", $testUser)
    }
    @{
        Category = "User & Security"
        Name = "user-schemas"
        Description = "List user's schemas"
        Args = @("-profile", $Profile, "-object", $testUser)
    }
    @{
        Category = "User & Security"
        Name = "user-connections"
        Description = "List user connections"
        Args = @("-profile", $Profile)
    }

    # === MONITORING & STATS ===
    @{
        Category = "Monitoring & Stats"
        Name = "db-load"
        Description = "Get database load"
        Args = @("-profile", $Profile)
    }
    @{
        Category = "Monitoring & Stats"
        Name = "db-locks"
        Description = "Show database locks"
        Args = @("-profile", $Profile)
    }
    @{
        Category = "Monitoring & Stats"
        Name = "db-sessions"
        Description = "List database sessions"
        Args = @("-profile", $Profile)
    }
    @{
        Category = "Monitoring & Stats"
        Name = "db-size"
        Description = "Get database size"
        Args = @("-profile", $Profile)
    }
    @{
        Category = "Monitoring & Stats"
        Name = "schema-size"
        Description = "Get schema size"
        Args = @("-profile", $Profile, "-schema", $testSchema)
    }
    @{
        Category = "Monitoring & Stats"
        Name = "db-version"
        Description = "Get database version"
        Args = @("-profile", $Profile)
    }
    @{
        Category = "Monitoring & Stats"
        Name = "db-parameters"
        Description = "List database parameters"
        Args = @("-profile", $Profile)
    }
    @{
        Category = "Monitoring & Stats"
        Name = "db-registry"
        Description = "Show database registry"
        Args = @("-profile", $Profile)
    }
    @{
        Category = "Monitoring & Stats"
        Name = "active-queries"
        Description = "List active queries"
        Args = @("-profile", $Profile)
    }
    @{
        Category = "Monitoring & Stats"
        Name = "bufferpool-stats"
        Description = "Get buffer pool statistics"
        Args = @("-profile", $Profile)
    }
    @{
        Category = "Monitoring & Stats"
        Name = "tablespace-usage"
        Description = "Show tablespace usage"
        Args = @("-profile", $Profile)
    }

    # === CDC OPERATIONS ===
    @{
        Category = "CDC Operations"
        Name = "cdc-status"
        Description = "Get CDC status for schema"
        Args = @("-profile", $Profile, "-schema", $testSchema)
    }
    @{
        Category = "CDC Operations"
        Name = "cdc-status-full"
        Description = "Get full CDC status"
        Args = @("-profile", $Profile, "-schema", $testSchema)
    }
    @{
        Category = "CDC Operations"
        Name = "cdc-configuration"
        Description = "Get CDC configuration for table"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "CDC Operations"
        Name = "cdc-changes"
        Description = "List CDC changes"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "CDC Operations"
        Name = "cdc-enable"
        Description = "Enable CDC for table"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "CDC Operations"
        Name = "cdc-disable"
        Description = "Disable CDC for table"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "CDC Operations"
        Name = "cdc-history"
        Description = "Show CDC history"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testTable")
    }

    # === DATABASE COMPARISON ===
    @{
        Category = "Database Comparison"
        Name = "db-compare"
        Description = "Compare two schemas"
        Args = @("-profile", $Profile, "-object", $testSchema, "-schema", "${testSchema}_TEST")
    }
    @{
        Category = "Database Comparison"
        Name = "db-compare-source-only"
        Description = "Show objects only in source"
        Args = @("-profile", $Profile, "-object", $testSchema, "-schema", "${testSchema}_TEST")
    }
    @{
        Category = "Database Comparison"
        Name = "db-compare-target-only"
        Description = "Show objects only in target"
        Args = @("-profile", $Profile, "-object", $testSchema, "-schema", "${testSchema}_TEST")
    }
    @{
        Category = "Database Comparison"
        Name = "db-compare-different"
        Description = "Show different objects"
        Args = @("-profile", $Profile, "-object", $testSchema, "-schema", "${testSchema}_TEST")
    }
    @{
        Category = "Database Comparison"
        Name = "db-compare-ddl"
        Description = "Generate comparison DDL"
        Args = @("-profile", $Profile, "-object", $testSchema, "-schema", "${testSchema}_TEST")
    }

    # === METADATA & ADVANCED ===
    @{
        Category = "Metadata & Advanced"
        Name = "object-metadata"
        Description = "Get object metadata"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "Metadata & Advanced"
        Name = "object-search"
        Description = "Search for objects"
        Args = @("-profile", $Profile, "-object", "BILAG%")
    }
    @{
        Category = "Metadata & Advanced"
        Name = "column-search"
        Description = "Search for columns"
        Args = @("-profile", $Profile, "-object", "BILAG%")
    }
    @{
        Category = "Metadata & Advanced"
        Name = "dependency-graph"
        Description = "Generate dependency graph"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "Metadata & Advanced"
        Name = "query-history"
        Description = "Show query history"
        Args = @("-profile", $Profile)
    }
    @{
        Category = "Metadata & Advanced"
        Name = "schema-summary"
        Description = "Get schema summary"
        Args = @("-profile", $Profile, "-schema", $testSchema)
    }
    @{
        Category = "Metadata & Advanced"
        Name = "database-summary"
        Description = "Get database summary"
        Args = @("-profile", $Profile)
    }
    @{
        Category = "Metadata & Advanced"
        Name = "health-check"
        Description = "Run health check"
        Args = @("-profile", $Profile)
    }

    # === AI FEATURES ===
    @{
        Category = "AI Features"
        Name = "ai-query"
        Description = "AI-assisted query generation"
        Args = @("-profile", $Profile, "-prompt", "Show all invoices from last month")
    }
    @{
        Category = "AI Features"
        Name = "ai-explain-table"
        Description = "AI explanation of table"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "AI Features"
        Name = "ai-explain-view"
        Description = "AI explanation of view"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testView")
    }
    @{
        Category = "AI Features"
        Name = "ai-analyze-procedure"
        Description = "AI analysis of procedure"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testProcedure")
    }
    @{
        Category = "AI Features"
        Name = "ai-analyze-function"
        Description = "AI analysis of function"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testFunction")
    }
    @{
        Category = "AI Features"
        Name = "ai-analyze-package"
        Description = "AI analysis of package"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testPackage")
    }
    @{
        Category = "AI Features"
        Name = "ai-deep-analysis"
        Description = "Deep AI analysis of table"
        Args = @("-profile", $Profile, "-object", "$testSchema.$testTable")
    }
)

# Limit tests if specified
if ($MaxTests -gt 0 -and $MaxTests -lt $testCases.Count) {
    $testCases = $testCases | Select-Object -First $MaxTests
}

$totalTests = $testCases.Count
$passed = 0
$failed = 0
$testResults = @()

Write-Host "[TESTING] Running $totalTests CLI commands..." -ForegroundColor Yellow
Write-Host ""

foreach ($i in 0..($testCases.Count - 1)) {
    $test = $testCases[$i]
    $testNum = $i + 1
    $progress = [math]::Round(($testNum / $totalTests) * 100, 1)
    
    Write-Host "[$testNum/$totalTests] ${progress}% - $($test.Name): $($test.Description)" -ForegroundColor Gray
    
    # Build the full command line
    $argsString = $test.Args -join " "
    $fullCommand = "$exePath -command $($test.Name) $argsString -format json"
    
    $startTime = Get-Date
    $consoleOutput = ""
    $jsonOutput = ""
    $exitCode = 0
    
    try {
        # Execute the command and capture both stdout and stderr
        $tempJsonFile = "$outputDir/temp_$($test.Name)_$timestamp.json"
        $fullCommandWithFile = "$exePath -command $($test.Name) $argsString -format json -Outfile `"$tempJsonFile`""
        
        # Run the command
        $consoleOutput = & cmd /c $fullCommandWithFile 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
        
        # Read the JSON output file if it exists
        if (Test-Path $tempJsonFile) {
            $jsonOutput = Get-Content -Path $tempJsonFile -Raw -ErrorAction SilentlyContinue
            # Keep the file for reference
            $finalJsonFile = "$outputDir/$($test.Name).json"
            Copy-Item -Path $tempJsonFile -Destination $finalJsonFile -Force
            Remove-Item -Path $tempJsonFile -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        $consoleOutput = $_.Exception.Message
        $exitCode = -1
    }
    
    $duration = [math]::Round(((Get-Date) - $startTime).TotalMilliseconds, 0)
    
    # Check for errors
    $hasError = $consoleOutput -match "^ERROR:|CRITICAL:|SQL0206N|SQLCODE=-|Invalid.*parameter|not found.*Error|Query failed"
    $testPassed = ($exitCode -eq 0 -and -not $hasError)
    
    if ($testPassed) {
        Write-Host "  ✅ PASSED (${duration}ms)" -ForegroundColor Green
        $passed++
    }
    else {
        Write-Host "  ❌ FAILED (exit: $exitCode)" -ForegroundColor Red
        $failed++
    }
    
    # Store result with full I/O
    $testResults += @{
        TestNumber = $testNum
        Category = $test.Category
        Command = $test.Name
        Description = $test.Description
        CliInput = $fullCommand
        CliArgs = $argsString
        ExitCode = $exitCode
        DurationMs = $duration
        Passed = $testPassed
        ConsoleOutput = $consoleOutput.Trim()
        JsonOutput = $jsonOutput
        Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
}

Write-Host ""
Write-Host "[REPORT] Generating test reports..." -ForegroundColor Yellow

# Generate Markdown Report with Full I/O
$mdReport = @"
# CLI Test Report with Input/Output Capture

**Generated**: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")  
**Connection Profile**: $Profile  
**Total Tests**: $totalTests  
**✅ Passed**: $passed ($([math]::Round(($passed/$totalTests)*100, 1))%)  
**❌ Failed**: $failed ($([math]::Round(($failed/$totalTests)*100, 1))%)  

---

## Executive Summary

| Metric | Value |
|--------|-------|
| Total Commands Tested | $totalTests |
| Passed | $passed |
| Failed | $failed |
| Success Rate | $([math]::Round(($passed/$totalTests)*100, 1))% |
| Test Duration | ~$([math]::Round(($testResults.DurationMs | Measure-Object -Sum).Sum / 1000, 1)) seconds |

---

## Results by Category

"@

# Group by category
$categories = $testResults | Group-Object -Property Category

foreach ($cat in $categories | Sort-Object Name) {
    $catPassed = ($cat.Group | Where-Object { $_.Passed }).Count
    $catTotal = $cat.Group.Count
    $catStatus = if ($catPassed -eq $catTotal) { "✅" } else { "⚠️" }
    
    $mdReport += @"

### $catStatus $($cat.Name) ($catPassed/$catTotal passed)

| # | Command | Description | Status | Duration | Exit Code |
|---|---------|-------------|--------|----------|-----------|
"@
    
    foreach ($result in $cat.Group) {
        $status = if ($result.Passed) { "✅ PASS" } else { "❌ FAIL" }
        $mdReport += "| $($result.TestNumber) | ``$($result.Command)`` | $($result.Description) | $status | $($result.DurationMs)ms | $($result.ExitCode) |`n"
    }
}

$mdReport += @"

---

## Detailed Test Results with Input/Output

Each test case below shows:
- **CLI Input**: The exact command line executed
- **Console Output**: What was printed to the console (logs, errors)
- **JSON Output**: The structured data returned by the command

"@

foreach ($result in $testResults) {
    $status = if ($result.Passed) { "✅ PASSED" } else { "❌ FAILED" }
    $statusEmoji = if ($result.Passed) { "✅" } else { "❌" }
    
    # Truncate very long outputs for readability
    $consoleOutputDisplay = $result.ConsoleOutput
    if ($consoleOutputDisplay.Length -gt 2000) {
        $consoleOutputDisplay = $consoleOutputDisplay.Substring(0, 2000) + "`n... (truncated, see full output in JSON report)"
    }
    
    $jsonOutputDisplay = $result.JsonOutput
    if ($jsonOutputDisplay -and $jsonOutputDisplay.Length -gt 3000) {
        $jsonOutputDisplay = $jsonOutputDisplay.Substring(0, 3000) + "`n... (truncated)"
    }
    
    $mdReport += @"

---

### $statusEmoji Test #$($result.TestNumber): $($result.Command)

**Category**: $($result.Category)  
**Description**: $($result.Description)  
**Status**: $status  
**Duration**: $($result.DurationMs) ms  
**Exit Code**: $($result.ExitCode)  
**Timestamp**: $($result.Timestamp)  

#### 📥 CLI Input (Command Executed)

``````bash
$($result.CliInput)
``````

#### 📤 Console Output

``````
$consoleOutputDisplay
``````

"@

    if ($result.JsonOutput) {
        $mdReport += @"
#### 📋 JSON Result

``````json
$jsonOutputDisplay
``````

"@
    }
}

$mdReport += @"

---

## Test Environment

- **Executable**: $exePath
- **Test Timestamp**: $timestamp
- **PowerShell Version**: $($PSVersionTable.PSVersion)
- **Test Script**: _cli_test_with_io_capture.ps1

---

*Report generated automatically by DbExplorer CLI Test Suite*
"@

# Save Markdown report
$mdReport | Out-File -FilePath $reportFile -Encoding UTF8

# Save JSON report (full data for programmatic access)
$jsonReport = @{
    ReportMetadata = @{
        Generated = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Profile = $Profile
        TotalTests = $totalTests
        Passed = $passed
        Failed = $failed
        SuccessRate = [math]::Round(($passed/$totalTests)*100, 2)
        Timestamp = $timestamp
    }
    TestResults = $testResults
}

$jsonReport | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonReportFile -Encoding UTF8

Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "TEST COMPLETE" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Total: $totalTests commands" -ForegroundColor White
Write-Host "✅ Passed: $passed ($([math]::Round(($passed/$totalTests)*100, 1))%)" -ForegroundColor Green
Write-Host "❌ Failed: $failed ($([math]::Round(($failed/$totalTests)*100, 1))%)" -ForegroundColor Red
Write-Host ""
Write-Host "Reports saved to:" -ForegroundColor Yellow
Write-Host "  Markdown: $reportFile" -ForegroundColor Gray
Write-Host "  JSON:     $jsonReportFile" -ForegroundColor Gray
Write-Host "=" * 80 -ForegroundColor Cyan

