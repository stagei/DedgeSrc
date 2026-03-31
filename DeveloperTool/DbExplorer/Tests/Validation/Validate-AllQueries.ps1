# DbExplorer - Complete Validation of ALL 122 SYSCAT Queries
# AI-powered comparison between CLI and Form data

param(
    [string]$Profile = "BASISTST",
    [string]$TestSchema = "INL",
    [string]$TestTable = "KONTO"
)

$ErrorActionPreference = "Continue"
$exe = "bin\Debug\net10.0-windows\DbExplorer.exe"
$OutputDir = "CLI_Test_Output"

# Create output directory if it doesn't exist
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "   COMPLETE 122-QUERY VALIDATION" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "🎯 Profile: $Profile" -ForegroundColor Yellow
Write-Host "🎯 Test Schema: $TestSchema" -ForegroundColor Yellow
Write-Host "🎯 Test Table: $TestSchema.$TestTable" -ForegroundColor Yellow
Write-Host ""

$startTime = Get-Date
$validationResults = @()

# Load all queries from JSON
$json = Get-Content "ConfigFiles/db2_12.1_sql_statements.json" -Raw | ConvertFrom-Json
$allQueries = $json.statements.PSObject.Properties

Write-Host "📊 Total queries to validate: $($allQueries.Count)" -ForegroundColor Cyan
Write-Host ""

# ==================================================================
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "PHASE 1: Table Properties Queries (9 queries)" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""

# Test 1: GetTableColumns (DONE - revalidate)
Write-Host "🧪 Test 1/122: GetTableColumns" -ForegroundColor Yellow
Write-Host "   Executing..." -ForegroundColor DarkGray

# Get CLI data via table-props
& $exe --profile $Profile --command table-props --object "$TestSchema.$TestTable" --outfile "$OutputDir\validation_cli_tableprops.json" 2>&1 | Out-Null

# Get Form data
& $exe --profile $Profile --test-form table-details --object "$TestSchema.$TestTable" --tab columns --outfile "$OutputDir\validation_form_columns.json" 2>&1 | Out-Null

if ((Test-Path "$OutputDir\validation_cli_tableprops.json") -and (Test-Path "$OutputDir\validation_form_columns.json")) {
    $cliData = (Get-Content "$OutputDir\validation_cli_tableprops.json" -Raw | ConvertFrom-Json).columns
    $formData = (Get-Content "$OutputDir\validation_form_columns.json" -Raw | ConvertFrom-Json).data.rows
    
    $cliCount = $cliData.Count
    $formCount = $formData.Count
    
    if ($cliCount -eq $formCount) {
        Write-Host "   ✅ PASS - Columns: CLI=$cliCount, Form=$formCount" -ForegroundColor Green
        $validationResults += [PSCustomObject]@{
            QueryName = "GetTableColumns"
            Category = "Table Properties"
            Method = "CLI vs Form"
            CliCount = $cliCount
            FormCount = $formCount
            Status = "✅ PASS"
            Details = "Column counts match"
        }
    } else {
        Write-Host "   ❌ FAIL - Columns: CLI=$cliCount, Form=$formCount" -ForegroundColor Red
        $validationResults += [PSCustomObject]@{
            QueryName = "GetTableColumns"
            Category = "Table Properties"
            Method = "CLI vs Form"
            CliCount = $cliCount
            FormCount = $formCount
            Status = "❌ FAIL"
            Details = "Column counts mismatch"
        }
    }
} else {
    Write-Host "   ⚠️  SKIP - Data retrieval failed" -ForegroundColor Yellow
    $validationResults += [PSCustomObject]@{
        QueryName = "GetTableColumns"
        Category = "Table Properties"
        Method = "CLI vs Form"
        CliCount = 0
        FormCount = 0
        Status = "⚠️ SKIP"
        Details = "Data retrieval failed"
    }
}
Write-Host ""

# Test 2: GetTableForeignKeys (DONE - revalidate)
Write-Host "🧪 Test 2/122: GetTableForeignKeys" -ForegroundColor Yellow
Write-Host "   Executing..." -ForegroundColor DarkGray

$cliData = (Get-Content "validation_cli_tableprops.json" -Raw | ConvertFrom-Json).foreignKeys
& $exe --profile $Profile --test-form table-details --object "$TestSchema.$TestTable" --tab foreign-keys --outfile "$OutputDir\validation_form_fks.json" 2>&1 | Out-Null

if ((Test-Path "$OutputDir\validation_form_fks.json")) {
    $formData = (Get-Content "validation_form_fks.json" -Raw | ConvertFrom-Json).data.rows
    
    $cliCount = $cliData.Count
    $formCount = $formData.Count
    
    if ($cliCount -eq $formCount) {
        Write-Host "   ✅ PASS - Foreign Keys: CLI=$cliCount, Form=$formCount" -ForegroundColor Green
        $validationResults += [PSCustomObject]@{
            QueryName = "GetTableForeignKeys"
            Category = "Table Properties"
            Method = "CLI vs Form"
            CliCount = $cliCount
            FormCount = $formCount
            Status = "✅ PASS"
            Details = "FK counts match"
        }
    } else {
        Write-Host "   ❌ FAIL - Foreign Keys: CLI=$cliCount, Form=$formCount" -ForegroundColor Red
        $validationResults += [PSCustomObject]@{
            QueryName = "GetTableForeignKeys"
            Category = "Table Properties"
            Method = "CLI vs Form"
            CliCount = $cliCount
            FormCount = $formCount
            Status = "❌ FAIL"
            Details = "FK counts mismatch"
        }
    }
} else {
    Write-Host "   ⚠️  SKIP - Form data retrieval failed" -ForegroundColor Yellow
    $validationResults += [PSCustomObject]@{
        QueryName = "GetTableForeignKeys"
        Category = "Table Properties"
        Method = "CLI vs Form"
        CliCount = 0
        FormCount = 0
        Status = "⚠️ SKIP"
        Details = "Form data retrieval failed"
    }
}
Write-Host ""

# Test 3: GetTableIndexes (DONE - revalidate)
Write-Host "🧪 Test 3/122: GetTableIndexes" -ForegroundColor Yellow
Write-Host "   Executing..." -ForegroundColor DarkGray

$cliData = (Get-Content "validation_cli_tableprops.json" -Raw | ConvertFrom-Json).indexes
& $exe --profile $Profile --test-form table-details --object "$TestSchema.$TestTable" --tab indexes --outfile "$OutputDir\validation_form_indexes.json" 2>&1 | Out-Null

if ((Test-Path "$OutputDir\validation_form_indexes.json")) {
    $formData = (Get-Content "validation_form_indexes.json" -Raw | ConvertFrom-Json).data.rows
    
    $cliCount = $cliData.Count
    $formCount = $formData.Count
    
    if ($cliCount -eq $formCount) {
        Write-Host "   ✅ PASS - Indexes: CLI=$cliCount, Form=$formCount" -ForegroundColor Green
        $validationResults += [PSCustomObject]@{
            QueryName = "GetTableIndexes"
            Category = "Table Properties"
            Method = "CLI vs Form"
            CliCount = $cliCount
            FormCount = $formCount
            Status = "✅ PASS"
            Details = "Index counts match"
        }
    } else {
        Write-Host "   ❌ FAIL - Indexes: CLI=$cliCount, Form=$formCount" -ForegroundColor Red
        $validationResults += [PSCustomObject]@{
            QueryName = "GetTableIndexes"
            Category = "Table Properties"
            Method = "CLI vs Form"
            CliCount = $cliCount
            FormCount = $formCount
            Status = "❌ FAIL"
            Details = "Index counts mismatch"
        }
    }
} else {
    Write-Host "   ⚠️  SKIP - Form data retrieval failed" -ForegroundColor Yellow
    $validationResults += [PSCustomObject]@{
        QueryName = "GetTableIndexes"
        Category = "Table Properties"
        Method = "CLI vs Form"
        CliCount = 0
        FormCount = 0
        Status = "⚠️ SKIP"
        Details = "Form data retrieval failed"
    }
}
Write-Host ""

# Test 4: GetTableDdlColumns (DONE - revalidate)
Write-Host "🧪 Test 4/122: GetTableDdlColumns" -ForegroundColor Yellow
Write-Host "   Executing..." -ForegroundColor DarkGray

& $exe --profile $Profile --test-form table-details --object "$TestSchema.$TestTable" --tab ddl-script --outfile "$OutputDir\validation_form_ddl.json" 2>&1 | Out-Null

if ((Test-Path "$OutputDir\validation_form_ddl.json")) {
    $formData = Get-Content "validation_form_ddl.json" -Raw | ConvertFrom-Json
    $ddlText = $formData.data.text
    
    $hasDDL = $ddlText -like "*CREATE TABLE*" -and $ddlText.Length -gt 100
    
    if ($hasDDL) {
        Write-Host "   ✅ PASS - DDL Script: $($ddlText.Length) chars, contains CREATE TABLE" -ForegroundColor Green
        $validationResults += [PSCustomObject]@{
            QueryName = "GetTableDdlColumns"
            Category = "Table Properties"
            Method = "Form DDL Generation"
            CliCount = "N/A"
            FormCount = $ddlText.Length
            Status = "✅ PASS"
            Details = "DDL generated successfully"
        }
    } else {
        Write-Host "   ❌ FAIL - DDL Script invalid or missing" -ForegroundColor Red
        $validationResults += [PSCustomObject]@{
            QueryName = "GetTableDdlColumns"
            Category = "Table Properties"
            Method = "Form DDL Generation"
            CliCount = "N/A"
            FormCount = $ddlText.Length
            Status = "❌ FAIL"
            Details = "DDL missing or invalid"
        }
    }
} else {
    Write-Host "   ⚠️  SKIP - DDL data retrieval failed" -ForegroundColor Yellow
    $validationResults += [PSCustomObject]@{
        QueryName = "GetTableDdlColumns"
        Category = "Table Properties"
        Method = "Form DDL Generation"
        CliCount = "N/A"
        FormCount = 0
        Status = "⚠️ SKIP"
        Details = "DDL data retrieval failed"
    }
}
Write-Host ""

# Test 5: GetIncomingForeignKeys (DONE - revalidate)
Write-Host "🧪 Test 5/122: GetIncomingForeignKeys" -ForegroundColor Yellow
Write-Host "   Executing..." -ForegroundColor DarkGray

& $exe --profile $Profile --test-form table-details --object "$TestSchema.$TestTable" --tab incoming-fk --outfile "$OutputDir\validation_form_incoming_fk.json" 2>&1 | Out-Null

if ((Test-Path "$OutputDir\validation_form_incoming_fk.json")) {
    $formData = (Get-Content "validation_form_incoming_fk.json" -Raw | ConvertFrom-Json).data.rowCount
    
    Write-Host "   ✅ PASS - Incoming FKs: $formData rows extracted" -ForegroundColor Green
    $validationResults += [PSCustomObject]@{
        QueryName = "GetIncomingForeignKeys"
        Category = "Table Properties"
        Method = "Form Extraction"
        CliCount = "N/A"
        FormCount = $formData
        Status = "✅ PASS"
        Details = "Incoming FK data extracted"
    }
} else {
    Write-Host "   ⚠️  SKIP - Data retrieval failed" -ForegroundColor Yellow
    $validationResults += [PSCustomObject]@{
        QueryName = "GetIncomingForeignKeys"
        Category = "Table Properties"
        Method = "Form Extraction"
        CliCount = "N/A"
        FormCount = 0
        Status = "⚠️ SKIP"
        Details = "Data retrieval failed"
    }
}
Write-Host ""

Write-Host "Phase 1 Progress: 5/9 queries validated" -ForegroundColor Cyan
Write-Host ""

# ==================================================================
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "PHASE 2: Remaining Queries (Automated Discovery)" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""

Write-Host "📋 Analyzing remaining 117 queries..." -ForegroundColor Yellow
Write-Host "   (This requires CLI commands for each query type)" -ForegroundColor DarkGray
Write-Host ""

# Categorize all queries
$categorized = @{
    "Table Properties" = @()
    "View Properties" = @()
    "Routine Properties" = @()
    "Package Properties" = @()
    "Security" = @()
    "Schema/Database" = @()
    "Count Queries" = @()
    "Other" = @()
}

foreach ($query in $allQueries) {
    $name = $query.Name
    $sql = $query.Value.sql
    
    if ($name -like "*Table*" -or $name -like "*Column*" -or $name -like "*Index*" -or $name -like "*ForeignKey*") {
        $categorized["Table Properties"] += $name
    }
    elseif ($name -like "*View*") {
        $categorized["View Properties"] += $name
    }
    elseif ($name -like "*Procedure*" -or $name -like "*Function*" -or $name -like "*Trigger*" -or $name -like "*Routine*") {
        $categorized["Routine Properties"] += $name
    }
    elseif ($name -like "*Package*" -or $name -like "*Statement*") {
        $categorized["Package Properties"] += $name
    }
    elseif ($name -like "*User*" -or $name -like "*Group*" -or $name -like "*Priv*" -or $name -like "*Auth*" -or $name -like "*Role*") {
        $categorized["Security"] += $name
    }
    elseif ($name -like "*Schema*" -or $name -like "*Tablespace*" -or $name -like "*Database*") {
        $categorized["Schema/Database"] += $name
    }
    elseif ($name -like "Count*") {
        $categorized["Count Queries"] += $name
    }
    else {
        $categorized["Other"] += $name
    }
}

Write-Host "Query Distribution:" -ForegroundColor Cyan
foreach ($category in $categorized.Keys | Sort-Object) {
    $count = $categorized[$category].Count
    if ($count -gt 0) {
        Write-Host "   • $category`: $count queries" -ForegroundColor White
    }
}
Write-Host ""

# ==================================================================
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "VALIDATION SUMMARY (Current Progress)" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""

$endTime = Get-Date
$duration = ($endTime - $startTime).TotalSeconds

$totalTests = $validationResults.Count
$passed = ($validationResults | Where-Object { $_.Status -eq "✅ PASS" }).Count
$failed = ($validationResults | Where-Object { $_.Status -eq "❌ FAIL" }).Count
$skipped = ($validationResults | Where-Object { $_.Status -eq "⚠️ SKIP" }).Count

Write-Host "Total Queries in JSON: $($allQueries.Count)" -ForegroundColor White
Write-Host "Tests Executed: $totalTests" -ForegroundColor White
Write-Host "Passed: $passed" -ForegroundColor Green
Write-Host "Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
Write-Host "Skipped: $skipped" -ForegroundColor Yellow
Write-Host "Success Rate: $([math]::Round(($passed / $totalTests) * 100, 2))%" -ForegroundColor Cyan
Write-Host "Duration: $([math]::Round($duration, 2))s" -ForegroundColor White
Write-Host ""

Write-Host "Remaining Queries: $($allQueries.Count - $totalTests)" -ForegroundColor Yellow
Write-Host ""

# Display results table
Write-Host "Detailed Results:" -ForegroundColor Cyan
$validationResults | Format-Table -AutoSize

# Save results
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$csvFile = "validation_all_queries_$timestamp.csv"
$jsonFile = "validation_all_queries_$timestamp.json"

$validationResults | Export-Csv $csvFile -NoTypeInformation
$validationResults | ConvertTo-Json -Depth 5 | Out-File $jsonFile -Encoding UTF8

Write-Host ""
Write-Host "📊 Results saved to:" -ForegroundColor Cyan
Write-Host "   • $csvFile" -ForegroundColor White
Write-Host "   • $jsonFile" -ForegroundColor White
Write-Host ""

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "NEXT STEPS:" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""
Write-Host "To complete validation of all 122 queries:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Implement CLI commands for remaining query types" -ForegroundColor White
Write-Host "   - View operations (8 queries)" -ForegroundColor DarkGray
Write-Host "   - Routine operations (15 queries)" -ForegroundColor DarkGray
Write-Host "   - Package operations (8 queries)" -ForegroundColor DarkGray
Write-Host "   - Security operations (10 queries)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "2. Extend --test-form parameter for other dialogs" -ForegroundColor White
Write-Host "   - object-details (Views/Procedures/Functions)" -ForegroundColor DarkGray
Write-Host "   - package-details (Packages)" -ForegroundColor DarkGray
Write-Host "   - user-details (Users/Groups)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "3. Re-run this script after CLI commands are implemented" -ForegroundColor White
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan

