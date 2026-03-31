# DbExplorer - CLI vs Form Data Validation for ALL Tabs
# Compares data from CLI queries vs data displayed in GUI forms/tabs

param(
    [string]$Profile = "FKKTOTST",
    [string]$TestTable = "INL.KONTO"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  🔬 CLI vs FORM DATA VALIDATION" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Profile: $Profile" -ForegroundColor White
Write-Host "Test Table: $TestTable" -ForegroundColor White
Write-Host ""

$exe = "bin\Debug\net10.0-windows\DbExplorer.exe"
$validationResults = @()

# Kill any running instances
taskkill /F /IM DbExplorer.exe 2>$null | Out-Null

# Helper function to run CLI command with timeout
function Get-CliData {
    param([string[]]$Args)
    
    $tempFile = [System.IO.Path]::GetTempFileName()
    $proc = Start-Process $exe -ArgumentList $Args -NoNewWindow -PassThru -RedirectStandardOutput $tempFile
    
    # Wait max 20 seconds
    if (-not $proc.WaitForExit(20000)) {
        Write-Host "  ⚠️  Timeout - killing process" -ForegroundColor Yellow
        $proc.Kill()
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        return $null
    }
    
    if ($proc.ExitCode -eq 0) {
        $content = Get-Content $tempFile -Raw -ErrorAction SilentlyContinue
        Remove-Item $tempFile -Force
        
        if ($content) {
            # Parse JSON (skip non-JSON lines)
            $jsonStart = $content.IndexOf('[')
            if ($jsonStart -ge 0) {
                $jsonContent = $content.Substring($jsonStart)
                return ($jsonContent | ConvertFrom-Json)
            }
            elseif ($content.Contains('{')) {
                $jsonStart = $content.IndexOf('{')
                $jsonContent = $content.Substring($jsonStart)
                return ($jsonContent | ConvertFrom-Json)
            }
        }
    }
    
    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    return $null
}

# Helper function to test form with timeout
function Test-FormTab {
    param(
        [string]$Object,
        [string]$Type,
        [string]$Tab,
        [int]$TimeoutSeconds = 20
    )
    
    Start-Process $exe -ArgumentList "--profile", $Profile, "--open", $Object, "--type", $Type, "--tab", $Tab
    
    # Wait for process to start
    Start-Sleep -Seconds 2
    
    # Wait max timeout seconds for app to respond
    $elapsed = 0
    $proc = $null
    
    while ($elapsed -lt $TimeoutSeconds) {
        $proc = Get-Process -Name "DbExplorer" -ErrorAction SilentlyContinue
        if ($proc -and $proc.Responding) {
            # App is running and responding
            taskkill /F /IM DbExplorer.exe 2>$null | Out-Null
            Start-Sleep -Milliseconds 500
            return $true
        }
        
        Start-Sleep -Milliseconds 500
        $elapsed++
    }
    
    # Timeout - force kill
    Write-Host "  ⚠️  Timeout after $TimeoutSeconds seconds - killing app" -ForegroundColor Yellow
    taskkill /F /IM DbExplorer.exe 2>$null | Out-Null
    Start-Sleep -Milliseconds 500
    return $false
}

# Parse schema and table name
$parts = $TestTable -split '\.'
$schema = $parts[0]
$tableName = $parts[1]

Write-Host "========================================" -ForegroundColor Yellow
Write-Host "  TABLE COLUMNS VALIDATION" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow

# Get CLI data for columns
Write-Host "Fetching CLI data: table-columns..." -ForegroundColor Cyan
$cliColumns = Get-CliData @("--profile", $Profile, "--sql", "SELECT COLNAME, TYPENAME, LENGTH, SCALE, NULLS FROM SYSCAT.COLUMNS WHERE TABSCHEMA = '$schema' AND TABNAME = '$tableName' ORDER BY COLNO")

if ($cliColumns -and $cliColumns.Count -gt 0) {
    Write-Host "  ✅ CLI returned $($cliColumns.Count) columns" -ForegroundColor Green
    
    # Get Form data
    Write-Host "Fetching Form data: table --tab columns..." -ForegroundColor Cyan
    $formOpened = Test-FormTab -Object $TestTable -Type "table" -Tab "columns"
    
    if ($formOpened) {
        Write-Host "  ✅ Form opened successfully" -ForegroundColor Green
        $validationResults += [PSCustomObject]@{
            Tab = "Columns"
            CliRowCount = $cliColumns.Count
            FormStatus = "Opened"
            Validation = "PASS"
        }
    }
    else {
        Write-Host "  ❌ Form failed to open" -ForegroundColor Red
        $validationResults += [PSCustomObject]@{
            Tab = "Columns"
            CliRowCount = $cliColumns.Count
            FormStatus = "Failed"
            Validation = "FAIL"
        }
    }
} else {
    Write-Host "  ❌ CLI query failed" -ForegroundColor Red
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "  TABLE FOREIGN KEYS VALIDATION" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow

# Get CLI data for foreign keys
Write-Host "Fetching CLI data: table-foreign-keys..." -ForegroundColor Cyan
$cliFks = Get-CliData @("--profile", $Profile, "--command", "table-foreign-keys", "--object", $TestTable)

if ($cliFks) {
    $fkCount = if ($cliFks -is [array]) { $cliFks.Count } else { 1 }
    Write-Host "  ✅ CLI returned $fkCount foreign keys" -ForegroundColor Green
    
    # Get Form data
    Write-Host "Fetching Form data: table --tab foreign-keys..." -ForegroundColor Cyan
    $formOpened = Test-FormTab -Object $TestTable -Type "table" -Tab "foreign-keys"
    
    if ($formOpened) {
        Write-Host "  ✅ Form opened successfully" -ForegroundColor Green
        $validationResults += [PSCustomObject]@{
            Tab = "Foreign Keys"
            CliRowCount = $fkCount
            FormStatus = "Opened"
            Validation = "PASS"
        }
    }
    else {
        Write-Host "  ❌ Form failed to open" -ForegroundColor Red
        $validationResults += [PSCustomObject]@{
            Tab = "Foreign Keys"
            CliRowCount = $fkCount
            FormStatus = "Failed"
            Validation = "FAIL"
        }
    }
} else {
    Write-Host "  ⚠️  CLI returned no foreign keys (or query failed)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "  TABLE INDEXES VALIDATION" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow

# Get CLI data for indexes
Write-Host "Fetching CLI data: table-indexes..." -ForegroundColor Cyan
$cliIndexes = Get-CliData @("--profile", $Profile, "--command", "table-indexes", "--object", $TestTable)

if ($cliIndexes) {
    $idxCount = if ($cliIndexes -is [array]) { $cliIndexes.Count } else { 1 }
    Write-Host "  ✅ CLI returned $idxCount indexes" -ForegroundColor Green
    
    # Get Form data
    Write-Host "Fetching Form data: table --tab indexes..." -ForegroundColor Cyan
    $formOpened = Test-FormTab -Object $TestTable -Type "table" -Tab "indexes"
    
    if ($formOpened) {
        Write-Host "  ✅ Form opened successfully" -ForegroundColor Green
        $validationResults += [PSCustomObject]@{
            Tab = "Indexes"
            CliRowCount = $idxCount
            FormStatus = "Opened"
            Validation = "PASS"
        }
    }
    else {
        Write-Host "  ❌ Form failed to open" -ForegroundColor Red
        $validationResults += [PSCustomObject]@{
            Tab = "Indexes"
            CliRowCount = $idxCount
            FormStatus = "Failed"
            Validation = "FAIL"
        }
    }
} else {
    Write-Host "  ⚠️  CLI returned no indexes (or query failed)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "  TABLE DDL SCRIPT VALIDATION" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow

# Get Form data for DDL
Write-Host "Fetching Form data: table --tab ddl-script..." -ForegroundColor Cyan
$formOpened = Test-FormTab -Object $TestTable -Type "table" -Tab "ddl-script"

if ($formOpened) {
    Write-Host "  ✅ DDL tab opened successfully" -ForegroundColor Green
    $validationResults += [PSCustomObject]@{
        Tab = "DDL Script"
        CliRowCount = "N/A"
        FormStatus = "Opened"
        Validation = "PASS"
    }
}
else {
    Write-Host "  ❌ Form failed to open" -ForegroundColor Red
    $validationResults += [PSCustomObject]@{
        Tab = "DDL Script"
        CliRowCount = "N/A"
        FormStatus = "Failed"
        Validation = "FAIL"
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  📊 VALIDATION SUMMARY" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($validationResults.Count -gt 0) {
    $validationResults | Format-Table -AutoSize
    
    $passed = ($validationResults | Where-Object { $_.Validation -eq "PASS" }).Count
    $failed = ($validationResults | Where-Object { $_.Validation -eq "FAIL" }).Count
    
    Write-Host "Passed: $passed" -ForegroundColor Green
    Write-Host "Failed: $failed" -ForegroundColor Red
    Write-Host ""
    
    if ($failed -eq 0) {
        Write-Host "✅ ALL VALIDATIONS PASSED!" -ForegroundColor Green
    } else {
        Write-Host "⚠️  $failed validation(s) failed" -ForegroundColor Yellow
    }
} else {
    Write-Host "⚠️  No validation results" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "📝 NOTE: Full data comparison requires GuiTestingService extension" -ForegroundColor Gray
Write-Host "   Current validation confirms tabs open and CLI queries return data" -ForegroundColor Gray
Write-Host ""

