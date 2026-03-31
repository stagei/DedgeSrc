# Comprehensive Validation of All Queries
# Provider-independent: tests queries from db2_12.1 or postgresql_18_sql_statements.json
# Use -Profile / -Provider or env WDE_TEST_PROFILE, WDE_TEST_PROVIDER

param(
    [string]$Profile,
    [ValidateSet('', 'DB2', 'PostgreSQL')]
    [string]$Provider,
    [int]$MaxHours = 20
)

# Load shared config (profile/provider from env if not passed)
$testsRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $testsRoot "TestConfig.ps1") -Profile $Profile -Provider $Provider
$Profile = Get-WdeTestProfile
$Provider = Get-WdeTestProvider

$startTime = Get-Date
$exe = "bin\Debug\net10.0-windows\DbExplorer.exe"
$jsonFile = if ($Provider -eq 'PostgreSQL') {
    "ConfigFiles\postgresql_18_sql_statements.json"
} else {
    "ConfigFiles\db2_12.1_sql_statements.json"
}
$OutputDir = "CLI_Test_Output"

# Create output directory if it doesn't exist
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Load all queries from JSON (provider-specific file)
if (-not (Test-Path $jsonFile)) {
    Write-Host "ERROR: SQL statements file not found: $jsonFile" -ForegroundColor Red
    exit 1
}
$json = Get-Content $jsonFile -Raw | ConvertFrom-Json
$queries = $json.statements.PSObject.Properties

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "   COMPREHENSIVE QUERY VALIDATION" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Total queries in JSON: $($queries.Count)" -ForegroundColor Yellow
Write-Host "Profile: $Profile" -ForegroundColor Cyan
Write-Host "Provider: $(if ($Provider) { $Provider } else { 'DB2 (default)' })" -ForegroundColor Cyan
Write-Host "SQL file: $jsonFile" -ForegroundColor Gray
Write-Host "Max time: $MaxHours hours" -ForegroundColor White
Write-Host ""

# Results tracking
$results = @{
    Tested = @()
    Passed = @()
    Failed = @()
    NoCliCommand = @()
    Skipped = @()
}

# Find test objects
Write-Host "🔍 Finding test objects..." -ForegroundColor Cyan
& $exe --profile $Profile --command list-tables --limit 10 --outfile "$OutputDir\_test_tables.json" 2>&1 | Out-Null
& $exe --profile $Profile --command list-views --limit 5 --outfile "$OutputDir\_test_views.json" 2>&1 | Out-Null
& $exe --profile $Profile --command list-procedures --limit 5 --outfile "$OutputDir\_test_procedures.json" 2>&1 | Out-Null
& $exe --profile $Profile --command list-functions --limit 5 --outfile "$OutputDir\_test_functions.json" 2>&1 | Out-Null
& $exe --profile $Profile --command list-triggers --limit 5 --outfile "$OutputDir\_test_triggers.json" 2>&1 | Out-Null
if ($Provider -ne 'PostgreSQL') {
    & $exe --profile $Profile --command list-packages --limit 5 --outfile "$OutputDir\_test_packages.json" 2>&1 | Out-Null
}

$testTable = if (Test-Path "$OutputDir\_test_tables.json") {
    $data = Get-Content "$OutputDir\_test_tables.json" -Raw | ConvertFrom-Json
    "$($data.tables[0].schema).$($data.tables[0].tableName)"
} else { $null }

$testView = if (Test-Path "$OutputDir\_test_views.json") {
    $data = Get-Content "$OutputDir\_test_views.json" -Raw | ConvertFrom-Json
    "$($data.views[0].schema).$($data.views[0].viewName)"
} else { $null }

$testProc = if (Test-Path "$OutputDir\_test_procedures.json") {
    $data = Get-Content "$OutputDir\_test_procedures.json" -Raw | ConvertFrom-Json
    "$($data.procedures[0].schema).$($data.procedures[0].procedureName)"
} else { $null }

$testFunc = if (Test-Path "$OutputDir\_test_functions.json") {
    $data = Get-Content "$OutputDir\_test_functions.json" -Raw | ConvertFrom-Json
    "$($data.functions[0].schema).$($data.functions[0].functionName)"
} else { $null }

$testTrig = if (Test-Path "$OutputDir\_test_triggers.json") {
    $data = Get-Content "$OutputDir\_test_triggers.json" -Raw | ConvertFrom-Json
    if ($data.triggers.Count -gt 0) {
        "$($data.triggers[0].schema).$($data.triggers[0].triggerName)"
    } else { $null }
} else { $null }

$testPkg = if (Test-Path "$OutputDir\_test_packages.json") {
    $data = Get-Content "$OutputDir\_test_packages.json" -Raw | ConvertFrom-Json
    if ($data.packages.Count -gt 0) {
        "$($data.packages[0].schema).$($data.packages[0].packageName)"
    } else { $null }
} else { $null }

$testSchema = if ($testTable) { $testTable.Split('.')[0] } else { $null }

Write-Host "✅ Test objects identified:" -ForegroundColor Green
Write-Host "   Table: $testTable" -ForegroundColor White
Write-Host "   View: $testView" -ForegroundColor White
Write-Host "   Procedure: $testProc" -ForegroundColor White
Write-Host "   Function: $testFunc" -ForegroundColor White
Write-Host "   Trigger: $testTrig" -ForegroundColor White
Write-Host "   Package: $testPkg" -ForegroundColor White
Write-Host "   Schema: $testSchema" -ForegroundColor White
Write-Host ""

# Query to CLI command mapping (partial - known mappings)
$queryToCliMap = @{
    "ListTables" = @{ cmd = "list-tables"; obj = $null; schema = $null }
    "ListViews" = @{ cmd = "list-views"; obj = $null; schema = $null }
    "ListProcedures" = @{ cmd = "list-procedures"; obj = $null; schema = $null }
    "ListFunctions" = @{ cmd = "list-functions"; obj = $null; schema = $null }
    "ListTriggers" = @{ cmd = "list-triggers"; obj = $null; schema = $null }
    "ListPackages" = @{ cmd = "list-packages"; obj = $null; schema = $null }
    "ListTablespaces" = @{ cmd = "list-tablespaces"; obj = $null; schema = $null }
    "ListSchemas" = @{ cmd = "list-schemas"; obj = $null; schema = $null }
    "GetTableColumns" = @{ cmd = "table-columns"; obj = $testTable; schema = $null }
    "GetTableForeignKeys" = @{ cmd = "table-foreign-keys"; obj = $testTable; schema = $null }
    "GetTableIndexes" = @{ cmd = "table-indexes"; obj = $testTable; schema = $null }
    "GetTableDdlColumns" = @{ cmd = "table-ddl"; obj = $testTable; schema = $null }
    "GetIncomingForeignKeys" = @{ cmd = "table-incoming-fks"; obj = $testTable; schema = $null }
    "GetTableUsedByPackages" = @{ cmd = "table-referencing-packages"; obj = $testTable; schema = $null }
    "GetTableUsedByViews" = @{ cmd = "table-referencing-views"; obj = $testTable; schema = $null }
    "GetTableUsedByRoutines" = @{ cmd = "table-referencing-routines"; obj = $testTable; schema = $null }
    "GetTableSize" = @{ cmd = "table-size"; obj = $testTable; schema = $null }
    "GetTableProps" = @{ cmd = "table-props"; obj = $testTable; schema = $null }
    "GetTableStats" = @{ cmd = "table-stats"; obj = $testTable; schema = $null }
    "GetViewInfo" = @{ cmd = "view-info"; obj = $testView; schema = $null }
    "GetProcedureInfo" = @{ cmd = "procedure-info"; obj = $testProc; schema = $null }
    "GetFunctionInfo" = @{ cmd = "function-info"; obj = $testFunc; schema = $null }
    "GetTriggerInfo" = @{ cmd = "trigger-info"; obj = $testTrig; schema = $null }
    "GetPackageDetails" = @{ cmd = "package-details"; obj = $testPkg; schema = $null }
    "GetSchemaSize" = @{ cmd = "schema-size"; obj = $null; schema = $testSchema }
    "GetSchemaMetadata" = @{ cmd = "schema-metadata"; obj = $null; schema = $testSchema }
    "GetDatabaseSize" = @{ cmd = "database-size"; obj = $null; schema = $null }
    "GetDatabaseMetadata" = @{ cmd = "database-metadata"; obj = $null; schema = $null }
    "GetDependencies" = @{ cmd = "dependencies"; obj = $testTable; schema = $null }
}

$queryNum = 0
$totalQueries = $queries.Count

foreach ($query in $queries) {
    $queryNum++
    $queryName = $query.Name
    
    # Check time budget
    $elapsed = ((Get-Date) - $startTime).TotalHours
    if ($elapsed -gt $MaxHours) {
        Write-Host ""
        Write-Host "⏱️  Time budget exceeded ($MaxHours hours)" -ForegroundColor Yellow
        break
    }
    
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    Write-Host "[$queryNum/$totalQueries] Testing: $queryName" -ForegroundColor Yellow
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    
    # Check if query has CLI mapping
    if ($queryToCliMap.ContainsKey($queryName)) {
        $mapping = $queryToCliMap[$queryName]
        $cliCmd = $mapping.cmd
        $cliObj = $mapping.obj
        $cliSchema = $mapping.schema
        if (-not (Test-WdeCommandSupportedForProvider -CommandName $cliCmd)) {
            Write-Host "   ⏭️  Skipped (DB2-only: $cliCmd)" -ForegroundColor DarkGray
            $results.Skipped += $queryName
            continue
        }
        if ($cliObj -eq $null -and $cliSchema -eq $null) {
            # Simple command
            Write-Host "   Executing: $cliCmd" -ForegroundColor Cyan
            & $exe --profile $Profile --command $cliCmd --outfile "$OutputDir\_query_test_$queryName.json" 2>&1 | Out-Null
        } elseif ($cliObj) {
            # Object-based command
            Write-Host "   Executing: $cliCmd --object $cliObj" -ForegroundColor Cyan
            & $exe --profile $Profile --command $cliCmd --object $cliObj --outfile "$OutputDir\_query_test_$queryName.json" 2>&1 | Out-Null
        } elseif ($cliSchema) {
            # Schema-based command
            Write-Host "   Executing: $cliCmd --schema $cliSchema" -ForegroundColor Cyan
            & $exe --profile $Profile --command $cliCmd --schema $cliSchema --outfile "$OutputDir\_query_test_$queryName.json" 2>&1 | Out-Null
        }
        
        if ($LASTEXITCODE -eq 0 -and (Test-Path "_query_test_$queryName.json")) {
            Write-Host "   ✅ PASS" -ForegroundColor Green
            $results.Passed += $queryName
            $results.Tested += $queryName
        } else {
            Write-Host "   ❌ FAIL" -ForegroundColor Red
            $results.Failed += $queryName
            $results.Tested += $queryName
        }
    } else {
        Write-Host "   ⚠️  No CLI mapping - skipping" -ForegroundColor Yellow
        $results.NoCliCommand += $queryName
    }
}

# Summary
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "   VALIDATION SUMMARY" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

$totalTested = $results.Tested.Count
$passRate = if ($totalTested -gt 0) { [math]::Round(($results.Passed.Count / $totalTested) * 100, 2) } else { 0 }

Write-Host "Total Queries: $totalQueries" -ForegroundColor White
Write-Host "Tested: $totalTested" -ForegroundColor Cyan
Write-Host "Passed: $($results.Passed.Count)" -ForegroundColor Green
Write-Host "Failed: $($results.Failed.Count)" -ForegroundColor Red
Write-Host "No CLI Command: $($results.NoCliCommand.Count)" -ForegroundColor Yellow
if ($results.Skipped.Count -gt 0) {
    Write-Host "Skipped (provider-specific): $($results.Skipped.Count)" -ForegroundColor DarkGray
}
Write-Host "Success Rate: $passRate%" -ForegroundColor Cyan
Write-Host ""
Write-Host "Elapsed Time: $([math]::Round(((Get-Date) - $startTime).TotalHours, 2)) hours" -ForegroundColor White
Write-Host ""

# Save detailed results
$results | ConvertTo-Json -Depth 5 | Out-File "$OutputDir\_comprehensive_validation_results.json" -Encoding UTF8

Write-Host "📊 Results saved to: $OutputDir\_comprehensive_validation_results.json" -ForegroundColor Cyan
Write-Host ""

if ($results.Failed.Count -gt 0) {
    Write-Host "❌ Failed Queries:" -ForegroundColor Red
    $results.Failed | ForEach-Object { Write-Host "   - $_" -ForegroundColor DarkGray }
    Write-Host ""
}

Write-Host "=============================================" -ForegroundColor Cyan

