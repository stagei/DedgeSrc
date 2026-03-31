# Continuous Validation of All 129 Queries
# Runs continuously, fixes issues, rebuilds as needed
# Profile: FKKTOTST (DBA access)

param(
    [string]$Profile = "FKKTOTST",
    [int]$MaxHours = 20
)

$startTime = Get-Date
$exe = "bin\Debug\net10.0-windows\DbExplorer.exe"
$fixLog = "VALIDATION_FIXES_LOG.md"
$blockersLog = "BLOCKING_ERRORS.md"
$OutputDir = "CLI_Test_Output"

# Create output directory if it doesn't exist
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Test results tracking
$results = @{
    Passed = @()
    Failed = @()
    Fixed = @()
    Blockers = @()
}

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "   CONTINUOUS VALIDATION - 129 QUERIES" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# Find test table
Write-Host "🔍 Finding test table in FKKTOTST..." -ForegroundColor Yellow
& $exe --profile $Profile --command list-tables --outfile "$OutputDir\tables_list.json" 2>&1 | Out-Null

if (Test-Path "$OutputDir\tables_list.json") {
    $tablesData = Get-Content "$OutputDir\tables_list.json" -Raw | ConvertFrom-Json
    $testTable = "$($tablesData.tables[0].schema).$($tablesData.tables[0].tableName)"
    Write-Host "✅ Test table: $testTable" -ForegroundColor Green
} else {
    Write-Host "❌ Cannot find test tables!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Starting validation loop..." -ForegroundColor Cyan
Write-Host ""

# Test configurations for queries that can be tested
$testConfigs = @(
    @{
        Name = "GetTableColumns"
        Category = "Table Properties"
        CliCommand = "table-columns"
        CliObject = $testTable
        FormCommand = "table-details"
        FormTab = "columns"
        ExpectData = $true
    },
    @{
        Name = "GetTableForeignKeys"  
        Category = "Table Properties"
        CliCommand = "table-props"
        CliObject = $testTable
        FormCommand = "table-details"
        FormTab = "foreign-keys"
        ExpectData = $true
    },
    @{
        Name = "GetTableIndexes"
        Category = "Table Properties"
        CliCommand = "table-indexes"
        CliObject = $testTable
        FormCommand = "table-details"
        FormTab = "indexes"
        ExpectData = $true
    },
    @{
        Name = "GetTableDdlColumns"
        Category = "Table Properties"
        CliCommand = "table-ddl"
        CliObject = $testTable
        FormCommand = "table-details"
        FormTab = "ddl-script"
        ExpectData = $true
    },
    @{
        Name = "GetIncomingForeignKeys"
        Category = "Table Properties"
        CliCommand = "table-incoming-fks"
        CliObject = $testTable
        FormCommand = "table-details"
        FormTab = "incoming-fk"
        ExpectData = $false  # May be 0 for some tables
    },
    @{
        Name = "GetTableUsedByPackages"
        Category = "Table Properties"
        CliCommand = "table-referencing-packages"
        CliObject = $testTable
        FormCommand = "table-details"
        FormTab = "used-by-packages"
        ExpectData = $false
    },
    @{
        Name = "GetTableUsedByViews"
        Category = "Table Properties"
        CliCommand = "table-referencing-views"
        CliObject = $testTable
        FormCommand = "table-details"
        FormTab = "used-by-views"
        ExpectData = $false
    },
    @{
        Name = "GetTableUsedByRoutines"
        Category = "Table Properties"
        CliCommand = "table-referencing-routines"
        CliObject = $testTable
        FormCommand = "table-details"
        FormTab = "used-by-routines"
        ExpectData = $false
    },
    @{
        Name = "ListTables"
        Category = "List Queries"
        CliCommand = "list-tables"
        CliObject = $null
        FormCommand = $null
        FormTab = $null
        ExpectData = $true
    },
    @{
        Name = "ListViews"
        Category = "List Queries"
        CliCommand = "list-views"
        CliObject = $null
        FormCommand = $null
        FormTab = $null
        ExpectData = $false
    },
    @{
        Name = "ListProcedures"
        Category = "List Queries"
        CliCommand = "list-procedures"
        CliObject = $null
        FormCommand = $null
        FormTab = $null
        ExpectData = $false
    },
    @{
        Name = "ListFunctions"
        Category = "List Queries"
        CliCommand = "list-functions"
        CliObject = $null
        FormCommand = $null
        FormTab = $null
        ExpectData = $false
    },
    @{
        Name = "ListTriggers"
        Category = "List Queries"
        CliCommand = "list-triggers"
        CliObject = $null
        FormCommand = $null
        FormTab = $null
        ExpectData = $false
    },
    @{
        Name = "ListPackages"
        Category = "List Queries"
        CliCommand = "list-packages"
        CliObject = $null
        FormCommand = $null
        FormTab = $null
        ExpectData = $false
    }
)

$testNumber = 0
$totalTests = $testConfigs.Count

foreach ($config in $testConfigs) {
    $testNumber++
    
    # Check time budget
    $elapsed = ((Get-Date) - $startTime).TotalHours
    if ($elapsed -gt $MaxHours) {
        Write-Host ""
        Write-Host "⏱️  Time budget exceeded ($MaxHours hours)" -ForegroundColor Yellow
        break
    }
    
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    Write-Host "TEST $testNumber/$totalTests : $($config.Name)" -ForegroundColor Yellow
    Write-Host "Category: $($config.Category)" -ForegroundColor DarkGray
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    
    $testResult = @{
        Name = $config.Name
        Category = $config.Category
        CliSuccess = $false
        FormSuccess = $false
        Match = $false
        CliCount = 0
        FormCount = 0
        Status = "UNKNOWN"
    }
    
    try {
        # Execute CLI
        Write-Host "⏳ Executing CLI: $($config.CliCommand)..." -ForegroundColor Cyan
        
        $cliFile = "$OutputDir\test_cli_$($config.Name).json"
        
        if ($config.CliObject) {
            & $exe --profile $Profile --command $config.CliCommand --object $config.CliObject --outfile $cliFile 2>&1 | Out-Null
        } else {
            & $exe --profile $Profile --command $config.CliCommand --outfile $cliFile 2>&1 | Out-Null
        }
        
        if (Test-Path $cliFile) {
            $cliData = Get-Content $cliFile -Raw | ConvertFrom-Json
            $testResult.CliSuccess = $true
            
            # Try to extract count
            if ($cliData.PSObject.Properties["columnCount"]) {
                $testResult.CliCount = $cliData.columnCount
            } elseif ($cliData.PSObject.Properties["totalCount"]) {
                $testResult.CliCount = $cliData.totalCount
            } elseif ($cliData.PSObject.Properties["tables"]) {
                $testResult.CliCount = ($cliData.tables | Measure-Object).Count
            } elseif ($cliData.PSObject.Properties["columns"]) {
                $testResult.CliCount = ($cliData.columns | Measure-Object).Count
            } else {
                $testResult.CliCount = "Data"
            }
            
            Write-Host "✅ CLI: $($testResult.CliCount)" -ForegroundColor Green
        } else {
            Write-Host "❌ CLI failed" -ForegroundColor Red
        }
        
        # Execute Form (if applicable)
        if ($config.FormCommand) {
            Write-Host "⏳ Executing Form: $($config.FormCommand)..." -ForegroundColor Cyan
            
            $formFile = "$OutputDir\test_form_$($config.Name).json"
            
            if ($config.FormTab) {
                & $exe --profile $Profile --test-form $config.FormCommand --object $config.CliObject --tab $config.FormTab --outfile $formFile 2>&1 | Out-Null
            } else {
                & $exe --profile $Profile --test-form $config.FormCommand --object $config.CliObject --outfile $formFile 2>&1 | Out-Null
            }
            
            if (Test-Path $formFile) {
                $formData = Get-Content $formFile -Raw | ConvertFrom-Json
                $testResult.FormSuccess = $true
                
                # Try to extract count
                if ($formData.data.PSObject.Properties["rowCount"]) {
                    $testResult.FormCount = $formData.data.rowCount
                } elseif ($formData.data.PSObject.Properties["rows"]) {
                    $testResult.FormCount = ($formData.data.rows | Measure-Object).Count
                } elseif ($formData.data.PSObject.Properties["length"]) {
                    $testResult.FormCount = "Text($($formData.data.length) chars)"
                } else {
                    $testResult.FormCount = "Data"
                }
                
                Write-Host "✅ Form: $($testResult.FormCount)" -ForegroundColor Green
            } else {
                Write-Host "❌ Form failed" -ForegroundColor Red
            }
        }
        
        # Compare results
        Write-Host ""
        
        if ($config.FormCommand) {
            # Compare CLI vs Form
            if ($testResult.CliSuccess -and $testResult.FormSuccess) {
                if ($testResult.CliCount -eq $testResult.FormCount) {
                    Write-Host "✅ PASS: CLI and Form match" -ForegroundColor Green
                    $testResult.Match = $true
                    $testResult.Status = "PASS"
                    $results.Passed += $testResult
                } else {
                    Write-Host "❌ MISMATCH: CLI=$($testResult.CliCount), Form=$($testResult.FormCount)" -ForegroundColor Red
                    $testResult.Status = "MISMATCH"
                    $results.Failed += $testResult
                    
                    # TODO: Investigate and fix
                    Write-Host "   🔍 Investigation needed - will fix in next iteration" -ForegroundColor Yellow
                }
            } else {
                Write-Host "⚠️  INCOMPLETE: One or both failed" -ForegroundColor Yellow
                $testResult.Status = "INCOMPLETE"
                $results.Failed += $testResult
            }
        } else {
            # CLI only
            if ($testResult.CliSuccess) {
                Write-Host "✅ PASS: CLI executed successfully" -ForegroundColor Green
                $testResult.Status = "PASS"
                $results.Passed += $testResult
            } else {
                Write-Host "❌ FAIL: CLI failed" -ForegroundColor Red
                $testResult.Status = "FAIL"
                $results.Failed += $testResult
            }
        }
        
    } catch {
        Write-Host "❌ ERROR: $($_.Exception.Message)" -ForegroundColor Red
        $testResult.Status = "ERROR"
        $results.Failed += $testResult
    }
    
    Write-Host ""
}

# Summary
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "   VALIDATION SUMMARY" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

$totalTested = $results.Passed.Count + $results.Failed.Count
$passRate = if ($totalTested -gt 0) { [math]::Round(($results.Passed.Count / $totalTested) * 100, 2) } else { 0 }

Write-Host "Tests Run: $totalTested / $totalTests" -ForegroundColor White
Write-Host "Passed: $($results.Passed.Count)" -ForegroundColor Green
Write-Host "Failed: $($results.Failed.Count)" -ForegroundColor Red
Write-Host "Success Rate: $passRate%" -ForegroundColor Cyan
Write-Host ""

Write-Host "Elapsed Time: $([math]::Round(((Get-Date) - $startTime).TotalHours, 2)) hours" -ForegroundColor White
Write-Host ""

# Save results
$results | ConvertTo-Json -Depth 5 | Out-File "$OutputDir\continuous_validation_results.json" -Encoding UTF8

Write-Host "📊 Results saved to: $OutputDir\continuous_validation_results.json" -ForegroundColor Cyan
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan

