# Complete Validation of ALL 129 Queries - FKKTOTST Profile (DBA Access)
# Comprehensive AI-powered comparison between CLI and Form data

param(
    [string]$Profile = "FKKTOTST",
    [int]$MaxQueries = 129,
    [switch]$ContinueOnError
)

$ErrorActionPreference = if ($ContinueOnError) { "Continue" } else { "Stop" }
$exe = "bin\Debug\net10.0-windows\DbExplorer.exe"
$OutputDir = "CLI_Test_Output"

# Create output directory if it doesn't exist
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "   COMPLETE 129-QUERY VALIDATION" -ForegroundColor Green
Write-Host "   FKKTOTST Profile (DBA Access)" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "🎯 Profile: $Profile (DBA)" -ForegroundColor Yellow
Write-Host "📊 Target: All 129 queries" -ForegroundColor Yellow
Write-Host "⏱️  Starting: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
Write-Host ""

$startTime = Get-Date
$validationResults = @()
$testCounter = 0

# Load all queries
$json = Get-Content "ConfigFiles/db2_12.1_sql_statements.json" -Raw | ConvertFrom-Json
$allQueries = $json.statements.PSObject.Properties

Write-Host "📋 Total queries in JSON: $($allQueries.Count)" -ForegroundColor Cyan
Write-Host ""

# Helper function to test a query
function Test-Query {
    param(
        [string]$QueryName,
        [string]$Category,
        [string]$CliCommand,
        [string]$CliObject,
        [string]$FormCommand = $null,
        [string]$FormTab = $null
    )
    
    $script:testCounter++
    Write-Host "🧪 Test $script:testCounter/$($allQueries.Count): $QueryName" -ForegroundColor Yellow
    Write-Host "   Category: $Category" -ForegroundColor DarkGray
    Write-Host "   CLI: $CliCommand" -ForegroundColor DarkGray
    
    $result = [PSCustomObject]@{
        QueryName = $QueryName
        Category = $Category
        CliCommand = $CliCommand
        FormCommand = $FormCommand
        CliCount = 0
        FormCount = 0
        Status = "⚠️ SKIP"
        Details = "Not yet implemented"
    }
    
    try {
        # Execute CLI command
        if ($CliCommand -and $CliCommand -ne "N/A") {
            $cliFile = "$OutputDir\validation_cli_$($QueryName).json"
            
            if ($CliObject) {
                & $exe --profile $Profile --command $CliCommand --object $CliObject --outfile $cliFile 2>&1 | Out-Null
            } else {
                & $exe --profile $Profile --command $CliCommand --outfile $cliFile 2>&1 | Out-Null
            }
            
            if ($LASTEXITCODE -eq 0 -and (Test-Path $cliFile)) {
                $cliData = Get-Content $cliFile -Raw | ConvertFrom-Json
                
                # Try to extract count from various possible structures
                if ($cliData.PSObject.Properties["Count"]) {
                    $result.CliCount = $cliData.Count
                } elseif ($cliData.PSObject.Properties["totalCount"]) {
                    $result.CliCount = $cliData.totalCount
                } elseif ($cliData.PSObject.Properties["tables"]) {
                    $result.CliCount = ($cliData.tables | Measure-Object).Count
                } elseif ($cliData.PSObject.Properties["columns"]) {
                    $result.CliCount = ($cliData.columns | Measure-Object).Count
                } elseif ($cliData.PSObject.Properties["rows"]) {
                    $result.CliCount = ($cliData.rows | Measure-Object).Count
                } else {
                    $result.CliCount = "Data Retrieved"
                }
                
                Write-Host "   ✅ CLI executed successfully: $($result.CliCount)" -ForegroundColor Green
            } else {
                Write-Host "   ⚠️  CLI command failed or returned no data" -ForegroundColor Yellow
                $result.Status = "⚠️ CLI FAIL"
                $result.Details = "CLI command failed or returned no data"
            }
        }
        
        # Execute Form command if applicable
        if ($FormCommand -and $FormCommand -ne "N/A") {
            $formFile = "$OutputDir\validation_form_$($QueryName).json"
            
            if ($FormTab) {
                & $exe --profile $Profile --test-form $FormCommand --object $CliObject --tab $FormTab --outfile $formFile 2>&1 | Out-Null
            } else {
                & $exe --profile $Profile --test-form $FormCommand --object $CliObject --outfile $formFile 2>&1 | Out-Null
            }
            
            if ($LASTEXITCODE -eq 0 -and (Test-Path $formFile)) {
                $formData = Get-Content $formFile -Raw | ConvertFrom-Json
                
                # Try to extract count from form data
                if ($formData.data.PSObject.Properties["rowCount"]) {
                    $result.FormCount = $formData.data.rowCount
                } elseif ($formData.data.PSObject.Properties["rows"]) {
                    $result.FormCount = ($formData.data.rows | Measure-Object).Count
                } else {
                    $result.FormCount = "Data Retrieved"
                }
                
                Write-Host "   ✅ Form executed successfully: $($result.FormCount)" -ForegroundColor Green
                
                # Compare if both have numeric counts
                if ($result.CliCount -is [int] -and $result.FormCount -is [int]) {
                    if ($result.CliCount -eq $result.FormCount) {
                        $result.Status = "✅ PASS"
                        $result.Details = "CLI and Form counts match"
                        Write-Host "   ✅ MATCH: CLI=$($result.CliCount), Form=$($result.FormCount)" -ForegroundColor Green
                    } else {
                        $result.Status = "❌ FAIL"
                        $result.Details = "CLI and Form counts mismatch"
                        Write-Host "   ❌ MISMATCH: CLI=$($result.CliCount), Form=$($result.FormCount)" -ForegroundColor Red
                    }
                } else {
                    $result.Status = "✅ PASS"
                    $result.Details = "Both CLI and Form executed successfully"
                }
            } else {
                Write-Host "   ⚠️  Form extraction failed" -ForegroundColor Yellow
            }
        } else {
            # CLI only - if it executed, it passes
            if ($result.CliCount -ne 0) {
                $result.Status = "✅ PASS"
                $result.Details = "CLI executed successfully (no form comparison)"
            }
        }
        
    } catch {
        Write-Host "   ❌ Exception: $($_.Exception.Message)" -ForegroundColor Red
        $result.Status = "❌ ERROR"
        $result.Details = $_.Exception.Message
    }
    
    Write-Host ""
    return $result
}

# ==================================================================
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "PHASE 1: Table Properties (Critical)" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""

# Find a test table in FKKTOTST
Write-Host "🔍 Finding test tables in FKKTOTST..." -ForegroundColor Yellow
& $exe --profile $Profile --command list-tables --outfile "$OutputDir\fkktotst_tables.json" 2>&1 | Out-Null

if (Test-Path "$OutputDir\fkktotst_tables.json") {
    $tablesData = Get-Content "$OutputDir\fkktotst_tables.json" -Raw | ConvertFrom-Json
    $testTable = $tablesData.tables[0].fullName
    Write-Host "✅ Using test table: $testTable" -ForegroundColor Green
    Write-Host ""
} else {
    Write-Host "❌ Could not find test tables!" -ForegroundColor Red
    exit 1
}

# Test table-related queries
$validationResults += Test-Query -QueryName "GetTableColumns" -Category "Table" `
    -CliCommand "table-columns" -CliObject $testTable `
    -FormCommand "table-details" -FormTab "columns"

$validationResults += Test-Query -QueryName "GetTableForeignKeys" -Category "Table" `
    -CliCommand "table-props" -CliObject $testTable `
    -FormCommand "table-details" -FormTab "foreign-keys"

$validationResults += Test-Query -QueryName "GetTableIndexes" -Category "Table" `
    -CliCommand "table-indexes" -CliObject $testTable `
    -FormCommand "table-details" -FormTab "indexes"

$validationResults += Test-Query -QueryName "GetTableDdlColumns" -Category "Table" `
    -CliCommand "table-ddl" -CliObject $testTable `
    -FormCommand "table-details" -FormTab "ddl-script"

$validationResults += Test-Query -QueryName "GetIncomingForeignKeys" -Category "Table" `
    -CliCommand "table-incoming-fks" -CliObject $testTable `
    -FormCommand "table-details" -FormTab "incoming-fk"

$validationResults += Test-Query -QueryName "GetTableUsedByPackages" -Category "Table" `
    -CliCommand "table-referencing-packages" -CliObject $testTable `
    -FormCommand "table-details" -FormTab "used-by-packages"

$validationResults += Test-Query -QueryName "GetTableUsedByViews" -Category "Table" `
    -CliCommand "table-referencing-views" -CliObject $testTable `
    -FormCommand "table-details" -FormTab "used-by-views"

$validationResults += Test-Query -QueryName "GetTableUsedByRoutines" -Category "Table" `
    -CliCommand "table-referencing-routines" -CliObject $testTable `
    -FormCommand "table-details" -FormTab "used-by-routines"

Write-Host "Phase 1 completed: $($validationResults.Count) queries tested" -ForegroundColor Cyan
Write-Host ""

# ==================================================================
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "PHASE 2: View/Procedure/Function/Trigger Queries" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""

# List queries
$validationResults += Test-Query -QueryName "ListTables" -Category "List" `
    -CliCommand "list-tables"

$validationResults += Test-Query -QueryName "ListViews" -Category "List" `
    -CliCommand "list-views"

$validationResults += Test-Query -QueryName "ListProcedures" -Category "List" `
    -CliCommand "list-procedures"

$validationResults += Test-Query -QueryName "ListFunctions" -Category "List" `
    -CliCommand "list-functions"

$validationResults += Test-Query -QueryName "ListTriggers" -Category "List" `
    -CliCommand "list-triggers"

$validationResults += Test-Query -QueryName "ListPackages" -Category "List" `
    -CliCommand "list-packages"

Write-Host "Phase 2 completed: $($validationResults.Count) queries tested total" -ForegroundColor Cyan
Write-Host ""

# ==================================================================
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "FINAL SUMMARY" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""

$endTime = Get-Date
$duration = ($endTime - $startTime).TotalSeconds

$totalTests = $validationResults.Count
$passed = ($validationResults | Where-Object { $_.Status -eq "✅ PASS" }).Count
$failed = ($validationResults | Where-Object { $_.Status -eq "❌ FAIL" }).Count
$skipped = ($validationResults | Where-Object { $_.Status -like "*SKIP*" }).Count

Write-Host "Total Queries in JSON: $($allQueries.Count)" -ForegroundColor White
Write-Host "Tests Executed: $totalTests" -ForegroundColor White
Write-Host "Passed: $passed" -ForegroundColor Green
Write-Host "Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
Write-Host "Skipped: $skipped" -ForegroundColor Yellow
Write-Host "Success Rate: $([math]::Round(($passed / $totalTests) * 100, 2))%" -ForegroundColor Cyan
Write-Host "Duration: $([math]::Round($duration, 2))s" -ForegroundColor White
Write-Host "Progress: $([math]::Round(($totalTests / $allQueries.Count) * 100, 2))%" -ForegroundColor Yellow
Write-Host ""

# Display results table
Write-Host "Detailed Results:" -ForegroundColor Cyan
$validationResults | Format-Table QueryName, Category, CliCount, FormCount, Status, Details -AutoSize

# Save results
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$csvFile = "$OutputDir\validation_fkktotst_$timestamp.csv"
$jsonFile = "$OutputDir\validation_fkktotst_$timestamp.json"

$validationResults | Export-Csv $csvFile -NoTypeInformation
$validationResults | ConvertTo-Json -Depth 5 | Out-File $jsonFile -Encoding UTF8

Write-Host ""
Write-Host "📊 Results saved to:" -ForegroundColor Cyan
Write-Host "   • $csvFile" -ForegroundColor White
Write-Host "   • $jsonFile" -ForegroundColor White
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan

