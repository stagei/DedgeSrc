# DbExplorer - Comprehensive Testing Script
# Database: BASISTST (FKMTST)
# Test Schemas: INL, DBM
# User: FKGEISTA (DBA access)

$ErrorActionPreference = "Continue"
$testResults = @()
$exe = "bin\Debug\net10.0-windows\DbExplorer.exe"

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "   COMPREHENSIVE DB2 TESTING SCRIPT" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# Phase 1: Test Core CLI Commands (Basic Queries)
Write-Host "Phase 1: Testing Core CLI Commands..." -ForegroundColor Yellow
Write-Host ""

$coreCommands = @(
    @{cmd = "list-schemas"; desc = "List all schemas"}
    @{cmd = "list-tables"; schema = "INL"; desc = "List tables in INL schema"}
    @{cmd = "list-tables"; schema = "DBM"; desc = "List tables in DBM schema"}
    @{cmd = "list-views"; schema = "INL"; desc = "List views in INL"}
    @{cmd = "list-procedures"; schema = "INL"; desc = "List procedures in INL"}
    @{cmd = "list-triggers"; schema = "INL"; desc = "List triggers in INL"}
    @{cmd = "db-size"; desc = "Database size"}
    @{cmd = "active-sessions"; desc = "Active sessions"}
)

$OutputDir = "CLI_Test_Output"
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$testNum = 1
foreach ($test in $coreCommands) {
    Write-Host "Test $testNum/$($coreCommands.Count): $($test.desc)..." -ForegroundColor Cyan
    
    $outFile = "$OutputDir\test_output_$testNum.json"
    $args = @("--profile", "BASISTST", "--command", $test.cmd, "--outfile", $outFile)
    
    if ($test.schema) {
        $args += @("--schema", $test.schema)
    }
    
    $result = & $exe $args 2>&1
    
    if ($LASTEXITCODE -eq 0 -and (Test-Path $outFile)) {
        $size = (Get-Item $outFile).Length
        Write-Host "  ✅ PASSED ($size bytes)" -ForegroundColor Green
        $testResults += [PSCustomObject]@{
            Test = "$($test.desc)"
            Command = $test.cmd
            Status = "PASSED"
            OutputSize = $size
        }
    } else {
        Write-Host "  ❌ FAILED" -ForegroundColor Red
        $testResults += [PSCustomObject]@{
            Test = "$($test.desc)"
            Command = $test.cmd
            Status = "FAILED"
            OutputSize = 0
        }
    }
    
    $testNum++
}

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""

# Phase 2: Test Table-Specific Commands
Write-Host "Phase 2: Testing Table-Specific Commands..." -ForegroundColor Yellow
Write-Host ""

# First, get a sample table from INL schema
Write-Host "Getting sample table from INL schema..." -ForegroundColor Cyan
$tableListResult = & $exe --profile BASISTST --command list-tables --schema INL --outfile "$OutputDir\temp_tables.json" 2>&1

if ($LASTEXITCODE -eq 0 -and (Test-Path "$OutputDir\temp_tables.json")) {
    $tablesData = Get-Content "$OutputDir\temp_tables.json" -Raw | ConvertFrom-Json
    if ($tablesData.tables -and $tablesData.tables.Count -gt 0) {
        $sampleTable = $tablesData.tables[0].tableName
        Write-Host "  Using sample table: INL.$sampleTable" -ForegroundColor Green
        Write-Host ""
        
        $tableCommands = @(
            @{cmd = "table-properties"; obj = "INL.$sampleTable"; desc = "Table properties"}
            @{cmd = "table-stats"; obj = "INL.$sampleTable"; desc = "Table statistics"}
            @{cmd = "table-size"; obj = "INL.$sampleTable"; desc = "Table size"}
            @{cmd = "table-columns"; obj = "INL.$sampleTable"; desc = "Table columns"}
            @{cmd = "table-indexes"; obj = "INL.$sampleTable"; desc = "Table indexes"}
            @{cmd = "table-fks"; obj = "INL.$sampleTable"; desc = "Foreign keys"}
        )
        
        foreach ($test in $tableCommands) {
            Write-Host "Test: $($test.desc) for $($test.obj)..." -ForegroundColor Cyan
            
            $outFile = "$OutputDir\test_table_$(($test.cmd -replace '-','_')).json"
            $result = & $exe --profile BASISTST --command $test.cmd --object $test.obj --outfile $outFile 2>&1
            
            if ($LASTEXITCODE -eq 0 -and (Test-Path $outFile)) {
                $size = (Get-Item $outFile).Length
                Write-Host "  ✅ PASSED ($size bytes)" -ForegroundColor Green
                $testResults += [PSCustomObject]@{
                    Test = "$($test.desc) - $($test.obj)"
                    Command = $test.cmd
                    Status = "PASSED"
                    OutputSize = $size
                }
            } else {
                Write-Host "  ❌ FAILED" -ForegroundColor Red
                $testResults += [PSCustomObject]@{
                    Test = "$($test.desc) - $($test.obj)"
                    Command = $test.cmd
                    Status = "FAILED"
                    OutputSize = 0
                }
            }
        }
    } else {
        Write-Host "  ⚠️  No tables found in INL schema - skipping table tests" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""

# Summary
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "   TEST SUMMARY" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

$passed = ($testResults | Where-Object { $_.Status -eq "PASSED" }).Count
$failed = ($testResults | Where-Object { $_.Status -eq "FAILED" }).Count
$total = $testResults.Count

Write-Host "Total Tests: $total" -ForegroundColor White
Write-Host "Passed: $passed" -ForegroundColor Green
Write-Host "Failed: $failed" -ForegroundColor Red
Write-Host "Success Rate: $([math]::Round(($passed / $total) * 100, 2))%" -ForegroundColor Cyan
Write-Host ""

$OutputDir = "CLI_Test_Output"
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Save results
$testResults | Export-Csv "$OutputDir\test_results.csv" -NoTypeInformation
$testResults | ConvertTo-Json -Depth 10 | Out-File "$OutputDir\test_results.json" -Encoding UTF8

Write-Host "📊 Detailed results saved to:" -ForegroundColor Cyan
Write-Host "   • $OutputDir\test_results.csv" -ForegroundColor White
Write-Host "   • $OutputDir\test_results.json" -ForegroundColor White
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan

