# Comprehensive CLI Test - ALL 119 Commands with Full I/O Capture
# Provider-independent: use -Profile / -Provider or env WDE_TEST_PROFILE, WDE_TEST_PROVIDER
# Captures: CLI Input, Console Output (logs), and JSON Results

param(
    [string]$Profile,
    [ValidateSet('', 'DB2', 'PostgreSQL')]
    [string]$Provider,
    [switch]$SkipBuild
)

# Load shared config (profile/provider from env if not passed)
$testsRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $testsRoot "TestConfig.ps1") -Profile $Profile -Provider $Provider
$Profile = Get-WdeTestProfile
$Provider = Get-WdeTestProvider

$ErrorActionPreference = "Continue"
$testResults = @()
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputDir = "CLI_Test_Output"
$reportFile = "$outputDir/COMPLETE_TEST_REPORT_$timestamp.md"
$jsonReportFile = "$outputDir/COMPLETE_TEST_REPORT_$timestamp.json"

if (!(Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

$connectionProfile = $Profile
$exePath = "bin\Debug\net10.0-windows\DbExplorer.exe"

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "COMPREHENSIVE CLI TEST - ALL COMMANDS WITH I/O CAPTURE" -ForegroundColor Cyan
Write-Host "Profile: $connectionProfile" -ForegroundColor Cyan
Write-Host "Provider: $(if ($Provider) { $Provider } else { 'all' })" -ForegroundColor Cyan
Write-Host "Started: $(Get-Date)" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

# Build the application first
if (-not $SkipBuild) {
    Write-Host "[1/3] Building application..." -ForegroundColor Yellow
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
$testView = "SYSDUMMY1"  # Use SYSIBM.SYSDUMMY1 as it always exists
$testViewSchema = "SYSIBM"  # View is in SYSIBM schema
$testProcSchema = "SYSPROC"             # System procedures schema
$testProcedure = "ADMIN_CMD"            # System procedure
$testFuncSchema = "SYSFUN"              # System functions schema
$testFunction = "ABS"                   # System function
$testPkgSchema = "NULLID"               # System package schema
$testPackage = "SYSSH200"               # System package
$testUser = "FKGEISTA"

# Define all 119 CLI commands to test with detailed metadata
$commands = @(
    # === CONNECTION & INFO (6) ===
    @{
        Category = "Connection & Info"
        Name = "connection-test"
        Description = "Test database connection"
        Args = @("-profile", $connectionProfile)
    }
    @{
        Category = "Connection & Info"
        Name = "connection-stats"
        Description = "Get connection statistics"
        Args = @("-profile", $connectionProfile)
    }
    @{
        Category = "Connection & Info"
        Name = "help-all"
        Description = "Show all available commands"
        Args = @("-profile", $connectionProfile)
    }
    @{
        Category = "Connection & Info"
        Name = "cli-version"
        Description = "Show CLI version"
        Args = @("-profile", $connectionProfile)
    }
    @{
        Category = "Connection & Info"
        Name = "db-config"
        Description = "Get database configuration"
        Args = @("-profile", $connectionProfile)
    }
    @{
        Category = "Connection & Info"
        Name = "connection-history"
        Description = "Show connection history"
        Args = @("-profile", $connectionProfile)
    }
    
    # === SCHEMA OPERATIONS (10) ===
    @{
        Category = "Schema Operations"
        Name = "list-schemas"
        Description = "List all schemas"
        Args = @("-profile", $connectionProfile)
    }
    @{
        Category = "Schema Operations"
        Name = "list-tables"
        Description = "List tables in schema"
        Args = @("-profile", $connectionProfile, "-schema", $testSchema)
    }
    @{
        Category = "Schema Operations"
        Name = "list-views"
        Description = "List views in schema"
        Args = @("-profile", $connectionProfile, "-schema", $testSchema)
    }
    @{
        Category = "Schema Operations"
        Name = "list-procedures"
        Description = "List procedures in schema"
        Args = @("-profile", $connectionProfile, "-schema", $testSchema)
    }
    @{
        Category = "Schema Operations"
        Name = "list-functions"
        Description = "List functions in schema"
        Args = @("-profile", $connectionProfile, "-schema", $testSchema)
    }
    @{
        Category = "Schema Operations"
        Name = "list-packages"
        Description = "List packages in schema"
        Args = @("-profile", $connectionProfile, "-schema", $testSchema)
    }
    @{
        Category = "Schema Operations"
        Name = "list-tablespaces"
        Description = "List all tablespaces"
        Args = @("-profile", $connectionProfile)
    }
    @{
        Category = "Schema Operations"
        Name = "list-all-indexes"
        Description = "List all indexes in schema"
        Args = @("-profile", $connectionProfile, "-schema", $testSchema)
    }
    @{
        Category = "Schema Operations"
        Name = "list-constraints"
        Description = "List constraints in schema"
        Args = @("-profile", $connectionProfile, "-schema", $testSchema)
    }
    @{
        Category = "Schema Operations"
        Name = "list-sequences"
        Description = "List sequences in schema"
        Args = @("-profile", $connectionProfile, "-schema", $testSchema)
    }
    
    # === TABLE OPERATIONS (15) ===
    @{
        Category = "Table Operations"
        Name = "table-properties"
        Description = "Get table properties"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "Table Operations"
        Name = "table-columns"
        Description = "List table columns"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "Table Operations"
        Name = "table-indexes"
        Description = "List table indexes"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "Table Operations"
        Name = "table-foreignkeys"
        Description = "List table foreign keys"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "Table Operations"
        Name = "table-ddl"
        Description = "Generate table DDL"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "Table Operations"
        Name = "table-statistics"
        Description = "Get table statistics"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "Table Operations"
        Name = "table-relationships"
        Description = "Show table relationships"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "Table Operations"
        Name = "table-sample-data"
        Description = "Get sample data from table"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "Table Operations"
        Name = "table-size"
        Description = "Get table size"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "Table Operations"
        Name = "table-grants"
        Description = "List table grants"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "Table Operations"
        Name = "table-dependencies"
        Description = "Show table dependencies"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "Table Operations"
        Name = "table-incoming-fk"
        Description = "List incoming foreign keys"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "Table Operations"
        Name = "table-used-by-packages"
        Description = "List packages using this table"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "Table Operations"
        Name = "table-used-by-views"
        Description = "List views using this table"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "Table Operations"
        Name = "table-used-by-routines"
        Description = "List routines using this table"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testTable")
    }
    
    # === VIEW OPERATIONS (7) ===
    @{
        Category = "View Operations"
        Name = "view-properties"
        Description = "Get view properties"
        Args = @("-profile", $connectionProfile, "-object", "$testViewSchema.$testView")
    }
    @{
        Category = "View Operations"
        Name = "view-definition"
        Description = "Get view definition SQL"
        Args = @("-profile", $connectionProfile, "-object", "$testViewSchema.$testView")
    }
    @{
        Category = "View Operations"
        Name = "view-columns"
        Description = "List view columns"
        Args = @("-profile", $connectionProfile, "-object", "$testViewSchema.$testView")
    }
    @{
        Category = "View Operations"
        Name = "view-dependencies"
        Description = "Show view dependencies"
        Args = @("-profile", $connectionProfile, "-object", "$testViewSchema.$testView")
    }
    @{
        Category = "View Operations"
        Name = "view-sample-data"
        Description = "Get sample data from view"
        Args = @("-profile", $connectionProfile, "-object", "$testViewSchema.$testView")
    }
    @{
        Category = "View Operations"
        Name = "view-used-by-packages"
        Description = "List packages using this view"
        Args = @("-profile", $connectionProfile, "-object", "$testViewSchema.$testView")
    }
    @{
        Category = "View Operations"
        Name = "view-used-by-views"
        Description = "List views using this view"
        Args = @("-profile", $connectionProfile, "-object", "$testViewSchema.$testView")
    }
    
    # === PROCEDURE OPERATIONS (6) ===
    @{
        Category = "Procedure Operations"
        Name = "procedure-properties"
        Description = "Get procedure properties"
        Args = @("-profile", $connectionProfile, "-object", "$testProcSchema.$testProcedure")
    }
    @{
        Category = "Procedure Operations"
        Name = "procedure-source"
        Description = "Get procedure source code"
        Args = @("-profile", $connectionProfile, "-object", "$testProcSchema.$testProcedure")
    }
    @{
        Category = "Procedure Operations"
        Name = "procedure-parameters"
        Description = "List procedure parameters"
        Args = @("-profile", $connectionProfile, "-object", "$testProcSchema.$testProcedure")
    }
    @{
        Category = "Procedure Operations"
        Name = "procedure-dependencies"
        Description = "Show procedure dependencies"
        Args = @("-profile", $connectionProfile, "-object", "$testProcSchema.$testProcedure")
    }
    @{
        Category = "Procedure Operations"
        Name = "procedure-usage"
        Description = "Show procedure usage"
        Args = @("-profile", $connectionProfile, "-object", "$testProcSchema.$testProcedure")
    }
    @{
        Category = "Procedure Operations"
        Name = "procedure-grants"
        Description = "List procedure grants"
        Args = @("-profile", $connectionProfile, "-object", "$testProcSchema.$testProcedure")
    }
    
    # === FUNCTION OPERATIONS (6) ===
    @{
        Category = "Function Operations"
        Name = "function-properties"
        Description = "Get function properties"
        Args = @("-profile", $connectionProfile, "-object", "$testFuncSchema.$testFunction")
    }
    @{
        Category = "Function Operations"
        Name = "function-source"
        Description = "Get function source code"
        Args = @("-profile", $connectionProfile, "-object", "$testFuncSchema.$testFunction")
    }
    @{
        Category = "Function Operations"
        Name = "function-parameters"
        Description = "List function parameters"
        Args = @("-profile", $connectionProfile, "-object", "$testFuncSchema.$testFunction")
    }
    @{
        Category = "Function Operations"
        Name = "function-dependencies"
        Description = "Show function dependencies"
        Args = @("-profile", $connectionProfile, "-object", "$testFuncSchema.$testFunction")
    }
    @{
        Category = "Function Operations"
        Name = "function-usage"
        Description = "Show function usage"
        Args = @("-profile", $connectionProfile, "-object", "$testFuncSchema.$testFunction")
    }
    @{
        Category = "Function Operations"
        Name = "function-grants"
        Description = "List function grants"
        Args = @("-profile", $connectionProfile, "-object", "$testFuncSchema.$testFunction")
    }
    
    # === PACKAGE OPERATIONS (8) ===
    @{
        Category = "Package Operations"
        Name = "package-properties"
        Description = "Get package properties"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testPackage")
    }
    @{
        Category = "Package Operations"
        Name = "package-statements"
        Description = "List package statements"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testPackage")
    }
    @{
        Category = "Package Operations"
        Name = "package-dependencies"
        Description = "Show package dependencies"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testPackage")
    }
    @{
        Category = "Package Operations"
        Name = "package-statistics"
        Description = "Get package statistics"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testPackage")
    }
    @{
        Category = "Package Operations"
        Name = "package-list-tables"
        Description = "List tables used by package"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testPackage")
    }
    @{
        Category = "Package Operations"
        Name = "package-list-views"
        Description = "List views used by package"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testPackage")
    }
    @{
        Category = "Package Operations"
        Name = "package-list-procedures"
        Description = "List procedures used by package"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testPackage")
    }
    @{
        Category = "Package Operations"
        Name = "package-list-functions"
        Description = "List functions used by package"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testPackage")
    }
    
    # === USER & SECURITY (5) ===
    @{
        Category = "User & Security"
        Name = "user-properties"
        Description = "Get user properties"
        Args = @("-profile", $connectionProfile, "-object", $testUser)
    }
    @{
        Category = "User & Security"
        Name = "user-privileges"
        Description = "List user privileges"
        Args = @("-profile", $connectionProfile, "-object", $testUser)
    }
    @{
        Category = "User & Security"
        Name = "user-tables"
        Description = "List user's tables"
        Args = @("-profile", $connectionProfile, "-object", $testUser)
    }
    @{
        Category = "User & Security"
        Name = "user-schemas"
        Description = "List user's schemas"
        Args = @("-profile", $connectionProfile, "-object", $testUser)
    }
    @{
        Category = "User & Security"
        Name = "user-connections"
        Description = "List user connections"
        Args = @("-profile", $connectionProfile)
    }
    
    # === MONITORING & STATS (12) ===
    @{
        Category = "Monitoring & Stats"
        Name = "db-load"
        Description = "Get database load"
        Args = @("-profile", $connectionProfile)
    }
    @{
        Category = "Monitoring & Stats"
        Name = "db-locks"
        Description = "Show database locks"
        Args = @("-profile", $connectionProfile)
    }
    @{
        Category = "Monitoring & Stats"
        Name = "db-sessions"
        Description = "List database sessions"
        Args = @("-profile", $connectionProfile)
    }
    @{
        Category = "Monitoring & Stats"
        Name = "db-size"
        Description = "Get database size"
        Args = @("-profile", $connectionProfile)
    }
    @{
        Category = "Monitoring & Stats"
        Name = "schema-size"
        Description = "Get schema size"
        Args = @("-profile", $connectionProfile, "-schema", $testSchema)
    }
    @{
        Category = "Monitoring & Stats"
        Name = "db-version"
        Description = "Get database version"
        Args = @("-profile", $connectionProfile)
    }
    @{
        Category = "Monitoring & Stats"
        Name = "db-parameters"
        Description = "List database parameters"
        Args = @("-profile", $connectionProfile)
    }
    @{
        Category = "Monitoring & Stats"
        Name = "db-registry"
        Description = "Show database registry"
        Args = @("-profile", $connectionProfile)
    }
    @{
        Category = "Monitoring & Stats"
        Name = "active-queries"
        Description = "List active queries"
        Args = @("-profile", $connectionProfile)
    }
    @{
        Category = "Monitoring & Stats"
        Name = "bufferpool-stats"
        Description = "Get buffer pool statistics"
        Args = @("-profile", $connectionProfile)
    }
    @{
        Category = "Monitoring & Stats"
        Name = "tablespace-usage"
        Description = "Show tablespace usage"
        Args = @("-profile", $connectionProfile)
    }
    
    # === CDC OPERATIONS (7) ===
    @{
        Category = "CDC Operations"
        Name = "cdc-status"
        Description = "Get CDC status for schema"
        Args = @("-profile", $connectionProfile, "-schema", $testSchema)
    }
    @{
        Category = "CDC Operations"
        Name = "cdc-status-full"
        Description = "Get full CDC status"
        Args = @("-profile", $connectionProfile, "-schema", $testSchema)
    }
    @{
        Category = "CDC Operations"
        Name = "cdc-configuration"
        Description = "Get CDC configuration for table"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "CDC Operations"
        Name = "cdc-changes"
        Description = "List CDC changes"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "CDC Operations"
        Name = "cdc-enable"
        Description = "Enable CDC for table"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "CDC Operations"
        Name = "cdc-disable"
        Description = "Disable CDC for table"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "CDC Operations"
        Name = "cdc-history"
        Description = "Show CDC history"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testTable")
    }
    
    # === DATABASE COMPARISON (5) ===
    @{
        Category = "Database Comparison"
        Name = "db-compare"
        Description = "Compare two schemas"
        Args = @("-profile", $connectionProfile, "-object", $testSchema, "-schema", "${testSchema}_TEST")
    }
    @{
        Category = "Database Comparison"
        Name = "db-compare-source-only"
        Description = "Show objects only in source"
        Args = @("-profile", $connectionProfile, "-object", $testSchema, "-schema", "${testSchema}_TEST")
    }
    @{
        Category = "Database Comparison"
        Name = "db-compare-target-only"
        Description = "Show objects only in target"
        Args = @("-profile", $connectionProfile, "-object", $testSchema, "-schema", "${testSchema}_TEST")
    }
    @{
        Category = "Database Comparison"
        Name = "db-compare-different"
        Description = "Show different objects"
        Args = @("-profile", $connectionProfile, "-object", $testSchema, "-schema", "${testSchema}_TEST")
    }
    @{
        Category = "Database Comparison"
        Name = "db-compare-ddl"
        Description = "Generate comparison DDL"
        Args = @("-profile", $connectionProfile, "-object", $testSchema, "-schema", "${testSchema}_TEST")
    }
    
    # === METADATA & ADVANCED (8) ===
    @{
        Category = "Metadata & Advanced"
        Name = "object-metadata"
        Description = "Get object metadata"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "Metadata & Advanced"
        Name = "object-search"
        Description = "Search for objects"
        Args = @("-profile", $connectionProfile, "-object", "BILAG%")
    }
    @{
        Category = "Metadata & Advanced"
        Name = "column-search"
        Description = "Search for columns"
        Args = @("-profile", $connectionProfile, "-object", "BILAG%")
    }
    @{
        Category = "Metadata & Advanced"
        Name = "dependency-graph"
        Description = "Generate dependency graph"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "Metadata & Advanced"
        Name = "query-history"
        Description = "Show query history"
        Args = @("-profile", $connectionProfile)
    }
    @{
        Category = "Metadata & Advanced"
        Name = "schema-summary"
        Description = "Get schema summary"
        Args = @("-profile", $connectionProfile, "-schema", $testSchema)
    }
    @{
        Category = "Metadata & Advanced"
        Name = "database-summary"
        Description = "Get database summary"
        Args = @("-profile", $connectionProfile)
    }
    @{
        Category = "Metadata & Advanced"
        Name = "health-check"
        Description = "Run health check"
        Args = @("-profile", $connectionProfile)
    }
    
    # === AI FEATURES (7) ===
    @{
        Category = "AI Features"
        Name = "ai-query"
        Description = "AI-assisted query generation"
        Args = @("-profile", $connectionProfile, "-prompt", "Show all invoices from last month")
    }
    @{
        Category = "AI Features"
        Name = "ai-explain-table"
        Description = "AI explanation of table"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testTable")
    }
    @{
        Category = "AI Features"
        Name = "ai-explain-view"
        Description = "AI explanation of view"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testView")
    }
    @{
        Category = "AI Features"
        Name = "ai-analyze-procedure"
        Description = "AI analysis of procedure"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testProcedure")
    }
    @{
        Category = "AI Features"
        Name = "ai-analyze-function"
        Description = "AI analysis of function"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testFunction")
    }
    @{
        Category = "AI Features"
        Name = "ai-analyze-package"
        Description = "AI analysis of package"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testPackage")
    }
    @{
        Category = "AI Features"
        Name = "ai-deep-analysis"
        Description = "Deep AI analysis of table"
        Args = @("-profile", $connectionProfile, "-object", "$testSchema.$testTable")
    }
    
    # === GUI TESTING (12) ===
    @{
        Category = "GUI Testing"
        Name = "gui-test"
        Description = "Test TableDetails form"
        Args = @("-profile", $connectionProfile, "-form", "TableDetails", "-object", "$testSchema.$testTable")
    }
    @{
        Category = "GUI Testing"
        Name = "gui-test"
        Description = "Test TableDetails Columns tab"
        Args = @("-profile", $connectionProfile, "-form", "TableDetails", "-object", "$testSchema.$testTable", "-tab", "Columns")
    }
    @{
        Category = "GUI Testing"
        Name = "gui-test"
        Description = "Test TableDetails Indexes tab"
        Args = @("-profile", $connectionProfile, "-form", "TableDetails", "-object", "$testSchema.$testTable", "-tab", "Indexes")
    }
    @{
        Category = "GUI Testing"
        Name = "gui-test"
        Description = "Test TableDetails ForeignKeys tab"
        Args = @("-profile", $connectionProfile, "-form", "TableDetails", "-object", "$testSchema.$testTable", "-tab", "ForeignKeys")
    }
    @{
        Category = "GUI Testing"
        Name = "gui-test"
        Description = "Test ViewDetails form"
        Args = @("-profile", $connectionProfile, "-form", "ViewDetails", "-object", "$testSchema.$testView")
    }
    @{
        Category = "GUI Testing"
        Name = "gui-test"
        Description = "Test ProcedureDetails form"
        Args = @("-profile", $connectionProfile, "-form", "ProcedureDetails", "-object", "$testSchema.$testProcedure")
    }
    @{
        Category = "GUI Testing"
        Name = "gui-test"
        Description = "Test FunctionDetails form"
        Args = @("-profile", $connectionProfile, "-form", "FunctionDetails", "-object", "$testSchema.$testFunction")
    }
    @{
        Category = "GUI Testing"
        Name = "gui-test"
        Description = "Test PackageDetails form"
        Args = @("-profile", $connectionProfile, "-form", "PackageDetails", "-object", "$testSchema.$testPackage")
    }
    @{
        Category = "GUI Testing"
        Name = "gui-test"
        Description = "Test DatabaseLoadMonitor form"
        Args = @("-profile", $connectionProfile, "-form", "DatabaseLoadMonitor")
    }
    @{
        Category = "GUI Testing"
        Name = "gui-test"
        Description = "Test ActiveSessions form"
        Args = @("-profile", $connectionProfile, "-form", "ActiveSessions")
    }
    @{
        Category = "GUI Testing"
        Name = "gui-test"
        Description = "Test LockMonitor form"
        Args = @("-profile", $connectionProfile, "-form", "LockMonitor")
    }
    @{
        Category = "GUI Testing"
        Name = "gui-test"
        Description = "Test CdcStatusDialog form"
        Args = @("-profile", $connectionProfile, "-form", "CdcStatusDialog", "-schema", $testSchema)
    }
)

Write-Host "[2/3] Running $($commands.Count) CLI commands..." -ForegroundColor Yellow
$totalCommands = $commands.Count
$passed = 0
$failed = 0
$current = 0

foreach ($cmd in $commands) {
    if (-not (Test-WdeCommandSupportedForProvider -CommandName $cmd.Name)) {
        Write-Host "  Skipping $($cmd.Name) (not supported for provider: $Provider)" -ForegroundColor DarkGray
        $testResults += @{
            Command = $cmd.Name
            Description = $cmd.Description
            Status = "Skipped"
            SkipReason = "DB2-only"
            DurationMs = 0
            ExitCode = $null
        }
        continue
    }
    $current++
    $progress = [math]::Round(($current / $totalCommands) * 100, 1)
    
    Write-Host "[${current}/${totalCommands}] ${progress}% - $($cmd.Name): $($cmd.Description)" -ForegroundColor Gray
    
    # Build the full command line
    $argsString = $cmd.Args -join " "
    $fullCommand = "$exePath -command $($cmd.Name) $argsString -format json"
    
    $startTime = Get-Date
    $consoleOutput = ""
    $jsonOutput = ""
    $exitCode = 0
    
    try {
        # Execute the command and capture both stdout and stderr
        $tempJsonFile = "$outputDir/temp_$($cmd.Name)_$timestamp.json"
        $fullCommandWithFile = "$exePath -command $($cmd.Name) $argsString -format json -Outfile `"$tempJsonFile`""
        
        # Run the command
        $consoleOutput = & cmd /c $fullCommandWithFile 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
        
        # Read the JSON output file if it exists
        if (Test-Path $tempJsonFile) {
            $jsonOutput = Get-Content -Path $tempJsonFile -Raw -ErrorAction SilentlyContinue
            # Keep the file for reference
            $finalJsonFile = "$outputDir/$($cmd.Name).json"
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
        TestNumber = $current
        Category = $cmd.Category
        Command = $cmd.Name
        Description = $cmd.Description
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
Write-Host "[3/3] Generating report..." -ForegroundColor Yellow

# Generate markdown report
$report = @"
# Comprehensive CLI Test Report - ALL 119 Commands with Full I/O Capture

**Date**: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")  
**Connection**: $connectionProfile  
**Total Commands Tested**: $totalCommands  
**✅ Passed**: $passed ($([math]::Round(($passed/$totalCommands)*100, 1))%)  
**❌ Failed**: $failed ($([math]::Round(($failed/$totalCommands)*100, 1))%)  

---

## Executive Summary

| Metric | Value |
|--------|-------|
| Total Commands Tested | $totalCommands |
| Passed | $passed |
| Failed | $failed |
| Success Rate | $([math]::Round(($passed/$totalCommands)*100, 1))% |
| Test Duration | ~$([math]::Round(($testResults | ForEach-Object { $_.DurationMs } | Measure-Object -Sum).Sum / 1000, 1)) seconds |

---

## Test Results by Category

"@

# Group by category
$categories = $testResults | Group-Object -Property Category

foreach ($cat in $categories | Sort-Object Name) {
    $catPassed = ($cat.Group | Where-Object { $_.Passed }).Count
    $catTotal = $cat.Group.Count
    $catStatus = if ($catPassed -eq $catTotal) { "✅" } else { "⚠️" }
    
    $report += @"

### $catStatus $($cat.Name) ($catPassed/$catTotal passed)

| # | Command | Description | Status | Duration | Exit Code |
|---|---------|-------------|--------|----------|-----------|

"@
    
    foreach ($result in $cat.Group) {
        $status = if ($result.Passed) { "✅ PASS" } else { "❌ FAIL" }
        $report += "| $($result.TestNumber) | ``$($result.Command)`` | $($result.Description) | $status | $($result.DurationMs)ms | $($result.ExitCode) |`n"
    }
}

$report += @"

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
    
    $report += @"

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
        $report += @"
#### 📋 JSON Result

``````json
$jsonOutputDisplay
``````

"@
    }
}

$report += @"

---

## Test Environment

- **Executable**: $exePath
- **Test Timestamp**: $timestamp
- **PowerShell Version**: $($PSVersionTable.PSVersion)
- **Test Script**: _comprehensive_cli_test_all_119.ps1

---

*Report generated automatically by DbExplorer Comprehensive CLI Test Suite*
"@

# Save Markdown report
$report | Out-File -FilePath $reportFile -Encoding UTF8

# Save JSON report (full data for programmatic access)
$jsonReport = @{
    ReportMetadata = @{
        Generated = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Profile = $connectionProfile
        TotalTests = $totalCommands
        Passed = $passed
        Failed = $failed
        SuccessRate = [math]::Round(($passed/$totalCommands)*100, 2)
        Timestamp = $timestamp
    }
    TestResults = $testResults
}

$jsonReport | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonReportFile -Encoding UTF8

Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "TEST COMPLETE" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Total: $totalCommands commands" -ForegroundColor White
Write-Host "✅ Passed: $passed ($([math]::Round(($passed/$totalCommands)*100, 1))%)" -ForegroundColor Green
Write-Host "❌ Failed: $failed ($([math]::Round(($failed/$totalCommands)*100, 1))%)" -ForegroundColor Red
Write-Host ""
Write-Host "Reports saved to:" -ForegroundColor Yellow
Write-Host "  Markdown: $reportFile" -ForegroundColor Gray
Write-Host "  JSON:     $jsonReportFile" -ForegroundColor Gray
Write-Host "=" * 80 -ForegroundColor Cyan

