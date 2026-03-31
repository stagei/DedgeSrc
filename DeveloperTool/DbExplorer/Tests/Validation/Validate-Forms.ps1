# DbExplorer - GUI vs CLI Validation Framework
# Compares data from CLI (direct SQL) vs GUI (form extraction)
# Purpose: Verify forms display correct data and use correct SQL queries

$ErrorActionPreference = "Continue"
$exe = "bin\Debug\net10.0-windows\DbExplorer.exe"
$profile = "BASISTST"
$testObject = "INL.KONTO"
$OutputDir = "CLI_Test_Output"

# Create output directory if it doesn't exist
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "   GUI vs CLI VALIDATION FRAMEWORK" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "🎯 Test Object: $testObject" -ForegroundColor Yellow
Write-Host "🔌 Profile: $profile" -ForegroundColor Yellow
Write-Host ""

# Initialize results
$validationResults = @()

# Function to compare CLI vs Form data
function Compare-CliVsForm {
    param(
        [string]$TabName,
        [PSCustomObject]$CliData,
        [PSCustomObject]$FormData
    )
    
    Write-Host "Comparing $TabName..." -ForegroundColor Cyan
    
    $result = [PSCustomObject]@{
        Tab = $TabName
        CliRows = 0
        FormRows = 0
        Match = $false
        Details = ""
    }
    
    # Extract row counts
    if ($CliData.PSObject.Properties["tables"]) {
        $result.CliRows = $CliData.tables.Count
    } elseif ($CliData.PSObject.Properties["columns"]) {
        $result.CliRows = $CliData.columns.Count
    } elseif ($CliData.PSObject.Properties["foreignKeys"]) {
        $result.CliRows = $CliData.foreignKeys.Count
    }
    
    if ($FormData.PSObject.Properties["rowCount"]) {
        $result.FormRows = $FormData.rowCount
    } elseif ($FormData.PSObject.Properties["rows"]) {
        $result.FormRows = $FormData.rows.Count
    }
    
    # Compare
    if ($result.CliRows -eq $result.FormRows) {
        $result.Match = $true
        $result.Details = "✅ MATCH: Both have $($result.CliRows) rows"
        Write-Host "   ✅ PASS: $($result.Details)" -ForegroundColor Green
    } else {
        $result.Match = $false
        $result.Details = "❌ MISMATCH: CLI=$($result.CliRows), Form=$($result.FormRows)"
        Write-Host "   ❌ FAIL: $($result.Details)" -ForegroundColor Red
    }
    
    return $result
}

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""
Write-Host "TEST 1: Columns Tab" -ForegroundColor Yellow
Write-Host "─────────────────────" -ForegroundColor DarkGray
Write-Host ""

# CLI: Get table columns
Write-Host "Getting CLI data (table-columns)..." -ForegroundColor Cyan
& $exe --profile $profile --command table-columns --object $testObject --outfile "$OutputDir\cli_columns.json" 2>&1 | Out-Null

# Form: Extract columns tab
Write-Host "Getting Form data (columns tab)..." -ForegroundColor Cyan
& $exe --profile $profile --test-form table-details --object $testObject --tab columns --outfile "$OutputDir\form_columns.json" 2>&1 | Out-Null

if ((Test-Path "$OutputDir\cli_columns.json") -and (Test-Path "$OutputDir\form_columns.json")) {
    $cliData = Get-Content "$OutputDir\cli_columns.json" -Raw | ConvertFrom-Json
    $formData = Get-Content "$OutputDir\form_columns.json" -Raw | ConvertFrom-Json
    
    Write-Host ""
    Write-Host "CLI Data:" -ForegroundColor DarkGray
    Write-Host "   Total columns: $($cliData.totalColumns)" -ForegroundColor White
    
    Write-Host "Form Data:" -ForegroundColor DarkGray
    Write-Host "   Total columns: $($formData.data.rowCount)" -ForegroundColor White
    Write-Host ""
    
    $result = Compare-CliVsForm -TabName "Columns" -CliData $cliData -FormData $formData.data
    $validationResults += $result
} else {
    Write-Host "❌ Failed to get data" -ForegroundColor Red
}

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""
Write-Host "TEST 2: Foreign Keys Tab" -ForegroundColor Yellow
Write-Host "─────────────────────" -ForegroundColor DarkGray
Write-Host ""

# CLI: Get foreign keys
Write-Host "Getting CLI data (table-fks)..." -ForegroundColor Cyan
& $exe --profile $profile --command table-fks --object $testObject --outfile "$OutputDir\cli_fks.json" 2>&1 | Out-Null

# Form: Extract FK tab
Write-Host "Getting Form data (foreign-keys tab)..." -ForegroundColor Cyan
& $exe --profile $profile --test-form table-details --object $testObject --tab foreign-keys --outfile "$OutputDir\form_fks.json" 2>&1 | Out-Null

if ((Test-Path "$OutputDir\cli_fks.json") -and (Test-Path "$OutputDir\form_fks.json")) {
    $cliData = Get-Content "$OutputDir\cli_fks.json" -Raw | ConvertFrom-Json
    $formData = Get-Content "$OutputDir\form_fks.json" -Raw | ConvertFrom-Json
    
    Write-Host ""
    Write-Host "CLI Data:" -ForegroundColor DarkGray
    Write-Host "   Total FKs: $($cliData.totalForeignKeys)" -ForegroundColor White
    
    Write-Host "Form Data:" -ForegroundColor DarkGray
    Write-Host "   Total FKs: $($formData.data.rowCount)" -ForegroundColor White
    Write-Host ""
    
    $result = Compare-CliVsForm -TabName "ForeignKeys" -CliData $cliData -FormData $formData.data
    $validationResults += $result
} else {
    Write-Host "❌ Failed to get data" -ForegroundColor Red
}

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""
Write-Host "TEST 3: Indexes Tab" -ForegroundColor Yellow
Write-Host "─────────────────────" -ForegroundColor DarkGray
Write-Host ""

# CLI: Get indexes
Write-Host "Getting CLI data (table-indexes)..." -ForegroundColor Cyan
& $exe --profile $profile --command table-indexes --object $testObject --outfile "$OutputDir\cli_indexes.json" 2>&1 | Out-Null

# Form: Extract indexes tab
Write-Host "Getting Form data (indexes tab)..." -ForegroundColor Cyan
& $exe --profile $profile --test-form table-details --object $testObject --tab indexes --outfile "$OutputDir\form_indexes.json" 2>&1 | Out-Null

if ((Test-Path "$OutputDir\cli_indexes.json") -and (Test-Path "$OutputDir\form_indexes.json")) {
    $cliData = Get-Content "$OutputDir\cli_indexes.json" -Raw | ConvertFrom-Json
    $formData = Get-Content "$OutputDir\form_indexes.json" -Raw | ConvertFrom-Json
    
    Write-Host ""
    Write-Host "CLI Data:" -ForegroundColor DarkGray
    Write-Host "   Total indexes: $($cliData.totalIndexes)" -ForegroundColor White
    
    Write-Host "Form Data:" -ForegroundColor DarkGray
    Write-Host "   Total indexes: $($formData.data.rowCount)" -ForegroundColor White
    Write-Host ""
    
    $result = Compare-CliVsForm -TabName "Indexes" -CliData $cliData -FormData $formData.data
    $validationResults += $result
} else {
    Write-Host "❌ Failed to get data" -ForegroundColor Red
}

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""
Write-Host "TEST 4: DDL Script Tab" -ForegroundColor Yellow
Write-Host "─────────────────────" -ForegroundColor DarkGray
Write-Host ""

# CLI: Get DDL (using dedicated command if exists, or table-properties)
Write-Host "Getting CLI data (ddl command)..." -ForegroundColor Cyan
& $exe --profile $profile --command ddl --object $testObject --outfile "$OutputDir\cli_ddl.json" 2>&1 | Out-Null

# Form: Extract DDL tab
Write-Host "Getting Form data (ddl-script tab)..." -ForegroundColor Cyan
& $exe --profile $profile --test-form table-details --object $testObject --tab ddl-script --outfile "$OutputDir\form_ddl.json" 2>&1 | Out-Null

if ((Test-Path "$OutputDir\cli_ddl.json") -and (Test-Path "$OutputDir\form_ddl.json")) {
    $cliData = Get-Content "$OutputDir\cli_ddl.json" -Raw | ConvertFrom-Json
    $formData = Get-Content "$OutputDir\form_ddl.json" -Raw | ConvertFrom-Json
    
    Write-Host ""
    Write-Host "CLI Data:" -ForegroundColor DarkGray
    Write-Host "   DDL length: $($cliData.ddl.Length) chars" -ForegroundColor White
    
    Write-Host "Form Data:" -ForegroundColor DarkGray
    Write-Host "   DDL length: $($formData.data.length) chars" -ForegroundColor White
    Write-Host ""
    
    if ($cliData.ddl.Length -gt 0 -and $formData.data.length -gt 0) {
        Write-Host "   ✅ PASS: Both have DDL content" -ForegroundColor Green
        $validationResults += [PSCustomObject]@{
            Tab = "DDL Script"
            CliRows = $cliData.ddl.Length
            FormRows = $formData.data.length
            Match = $true
            Details = "Both have DDL content"
        }
    } else {
        Write-Host "   ❌ FAIL: Missing DDL content" -ForegroundColor Red
        $validationResults += [PSCustomObject]@{
            Tab = "DDL Script"
            CliRows = $cliData.ddl.Length
            FormRows = $formData.data.length
            Match = $false
            Details = "Missing content"
        }
    }
} else {
    Write-Host "❌ Failed to get DDL data" -ForegroundColor Red
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "   VALIDATION SUMMARY" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

$passed = ($validationResults | Where-Object { $_.Match -eq $true }).Count
$failed = ($validationResults | Where-Object { $_.Match -eq $false }).Count
$total = $validationResults.Count

Write-Host "Total Tests: $total" -ForegroundColor White
Write-Host "Passed: $passed" -ForegroundColor Green
Write-Host "Failed: $failed" -ForegroundColor Red
Write-Host "Success Rate: $([math]::Round(($passed / $total) * 100, 2))%" -ForegroundColor Cyan
Write-Host ""

Write-Host "Detailed Results:" -ForegroundColor Cyan
$validationResults | Format-Table -AutoSize

# Save results
$validationResults | Export-Csv "$OutputDir\validation_results.csv" -NoTypeInformation
$validationResults | ConvertTo-Json -Depth 5 | Out-File "$OutputDir\validation_results.json" -Encoding UTF8

Write-Host ""
Write-Host "📊 Results saved to:" -ForegroundColor Cyan
Write-Host "   • $OutputDir\validation_results.csv" -ForegroundColor White
Write-Host "   • $OutputDir\validation_results.json" -ForegroundColor White
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan

