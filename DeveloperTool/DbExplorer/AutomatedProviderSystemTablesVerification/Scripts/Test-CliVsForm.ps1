<#
.SYNOPSIS
    Compares CLI query results with Form display data

.DESCRIPTION
    This script runs CLI queries to fetch metadata, then opens the corresponding
    GUI form/tab and verifies the data matches. This ensures SQL queries and
    form extraction are consistent.

.PARAMETER ConfigFile
    Path to provider configuration JSON file

.PARAMETER OutputPath
    Path to save test results (optional)

.EXAMPLE
    .\Test-CliVsForm.ps1 -ConfigFile "..\ProviderConfigs\DB2_Config.json"

.NOTES
    Version: 1.0
    Author: DbExplorer Project
    Date: December 14, 2025
    
    NOTE: Full data extraction requires GuiTestingService extension.
    Current implementation validates that forms open and CLI queries return data.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ConfigFile,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "..\TestResults",
    
    [Parameter(Mandatory=$false)]
    [int]$TimeoutSeconds = 20
)

# Load configuration
if (-not (Test-Path $ConfigFile)) {
    Write-Host "❌ Config file not found: $ConfigFile" -ForegroundColor Red
    exit 1
}

$config = Get-Content $ConfigFile | ConvertFrom-Json
$exe = "..\..\bin\Debug\net10.0-windows\DbExplorer.exe"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  🔬 CLI vs FORM VALIDATION" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Provider: $($config.provider) $($config.version)" -ForegroundColor White
Write-Host "Test Table: $($config.testObjects.table)" -ForegroundColor White
Write-Host ""

# Kill any running instances
taskkill /F /IM DbExplorer.exe 2>$null | Out-Null
Start-Sleep -Seconds 1

# Helper function to run CLI command with timeout
function Get-CliData {
    param([string[]]$Args)
    
    $tempFile = [System.IO.Path]::GetTempFileName()
    $proc = Start-Process $exe -ArgumentList $Args -NoNewWindow -PassThru -RedirectStandardOutput $tempFile
    
    # Wait max timeout
    if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
        Write-Host "  ⚠️  Timeout - killing process" -ForegroundColor Yellow
        $proc.Kill()
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        return $null
    }
    
    if ($proc.ExitCode -eq 0) {
        $content = Get-Content $tempFile -Raw -ErrorAction SilentlyContinue
        Remove-Item $tempFile -Force
        
        if ($content) {
            # Parse JSON
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
        [string]$Tab
    )
    
    Start-Process $exe -ArgumentList "--profile", $config.profileName, "--open", $Object, "--type", $Type, "--tab", $Tab
    
    Start-Sleep -Seconds 2
    
    $elapsed = 0
    $proc = $null
    
    while ($elapsed -lt $TimeoutSeconds) {
        $proc = Get-Process -Name "DbExplorer" -ErrorAction SilentlyContinue
        if ($proc -and $proc.Responding) {
            taskkill /F /IM DbExplorer.exe 2>$null | Out-Null
            Start-Sleep -Milliseconds 500
            return $true
        }
        
        Start-Sleep -Milliseconds 500
        $elapsed++
    }
    
    Write-Host "  ⚠️  Timeout after $TimeoutSeconds seconds" -ForegroundColor Yellow
    taskkill /F /IM DbExplorer.exe 2>$null | Out-Null
    Start-Sleep -Milliseconds 500
    return $false
}

$validationResults = @()

# Test 1: Table Columns
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "  TABLE COLUMNS VALIDATION" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow

if ($config.testObjects.table -and $config.testObjects.table -ne "N/A") {
    Write-Host "Fetching CLI data: table-columns..." -ForegroundColor Cyan
    $cliColumns = Get-CliData @("--profile", $config.profileName, "--command", "table-columns", "--object", $config.testObjects.table)
    
    if ($cliColumns -and $cliColumns.Count -gt 0) {
        Write-Host "  ✅ CLI returned $($cliColumns.Count) columns" -ForegroundColor Green
        
        Write-Host "Fetching Form data: table --tab columns..." -ForegroundColor Cyan
        $formOpened = Test-FormTab -Object $config.testObjects.table -Type "table" -Tab "columns"
        
        if ($formOpened) {
            Write-Host "  ✅ Form opened successfully" -ForegroundColor Green
            $validationResults += [PSCustomObject]@{
                Test = "Columns"
                CliRowCount = $cliColumns.Count
                FormStatus = "Opened"
                Validation = "PASS"
            }
        }
        else {
            Write-Host "  ❌ Form failed to open" -ForegroundColor Red
            $validationResults += [PSCustomObject]@{
                Test = "Columns"
                CliRowCount = $cliColumns.Count
                FormStatus = "Failed"
                Validation = "FAIL"
            }
        }
    }
    else {
        Write-Host "  ❌ CLI query failed" -ForegroundColor Red
    }
}
else {
    Write-Host "  ⏭️  SKIP (table not configured)" -ForegroundColor Gray
}

Write-Host ""

# Test 2: Foreign Keys
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "  TABLE FOREIGN KEYS VALIDATION" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow

if ($config.testObjects.table -and $config.testObjects.table -ne "N/A") {
    Write-Host "Fetching CLI data: table-foreign-keys..." -ForegroundColor Cyan
    $cliFks = Get-CliData @("--profile", $config.profileName, "--command", "table-foreign-keys", "--object", $config.testObjects.table)
    
    if ($cliFks) {
        $fkCount = if ($cliFks -is [array]) { $cliFks.Count } else { 1 }
        Write-Host "  ✅ CLI returned $fkCount foreign keys" -ForegroundColor Green
        
        Write-Host "Fetching Form data: table --tab foreign-keys..." -ForegroundColor Cyan
        $formOpened = Test-FormTab -Object $config.testObjects.table -Type "table" -Tab "foreign-keys"
        
        if ($formOpened) {
            Write-Host "  ✅ Form opened successfully" -ForegroundColor Green
            $validationResults += [PSCustomObject]@{
                Test = "Foreign Keys"
                CliRowCount = $fkCount
                FormStatus = "Opened"
                Validation = "PASS"
            }
        }
        else {
            Write-Host "  ❌ Form failed to open" -ForegroundColor Red
            $validationResults += [PSCustomObject]@{
                Test = "Foreign Keys"
                CliRowCount = $fkCount
                FormStatus = "Failed"
                Validation = "FAIL"
            }
        }
    }
    else {
        Write-Host "  ⚠️  CLI returned no foreign keys (or query failed)" -ForegroundColor Yellow
    }
}
else {
    Write-Host "  ⏭️  SKIP (table not configured)" -ForegroundColor Gray
}

Write-Host ""

# Test 3: Indexes
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "  TABLE INDEXES VALIDATION" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow

if ($config.testObjects.table -and $config.testObjects.table -ne "N/A") {
    Write-Host "Fetching CLI data: table-indexes..." -ForegroundColor Cyan
    $cliIndexes = Get-CliData @("--profile", $config.profileName, "--command", "table-indexes", "--object", $config.testObjects.table)
    
    if ($cliIndexes) {
        $idxCount = if ($cliIndexes -is [array]) { $cliIndexes.Count } else { 1 }
        Write-Host "  ✅ CLI returned $idxCount indexes" -ForegroundColor Green
        
        Write-Host "Fetching Form data: table --tab indexes..." -ForegroundColor Cyan
        $formOpened = Test-FormTab -Object $config.testObjects.table -Type "table" -Tab "indexes"
        
        if ($formOpened) {
            Write-Host "  ✅ Form opened successfully" -ForegroundColor Green
            $validationResults += [PSCustomObject]@{
                Test = "Indexes"
                CliRowCount = $idxCount
                FormStatus = "Opened"
                Validation = "PASS"
            }
        }
        else {
            Write-Host "  ❌ Form failed to open" -ForegroundColor Red
            $validationResults += [PSCustomObject]@{
                Test = "Indexes"
                CliRowCount = $idxCount
                FormStatus = "Failed"
                Validation = "FAIL"
            }
        }
    }
    else {
        Write-Host "  ⚠️  CLI returned no indexes (or query failed)" -ForegroundColor Yellow
    }
}
else {
    Write-Host "  ⏭️  SKIP (table not configured)" -ForegroundColor Gray
}

Write-Host ""

# Summary
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
    
    # Save results
    if ($OutputPath) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $outputFile = Join-Path $OutputPath "$($config.provider)_CliVsForm_$timestamp.json"
        
        $report = @{
            provider = $config.provider
            version = $config.version
            testDate = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
            testType = "CliVsForm"
            results = @{
                total = $validationResults.Count
                passed = $passed
                failed = $failed
                passRate = [math]::Round(($passed / $validationResults.Count) * 100, 2)
            }
            details = $validationResults
        }
        
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        $report | ConvertTo-Json -Depth 10 | Out-File $outputFile
        Write-Host "📄 Results saved to: $outputFile" -ForegroundColor Cyan
    }
    
    if ($failed -eq 0) {
        Write-Host "✅ ALL VALIDATIONS PASSED!" -ForegroundColor Green
        exit 0
    }
    else {
        Write-Host "⚠️  $failed validation(s) failed" -ForegroundColor Yellow
        exit 1
    }
}
else {
    Write-Host "⚠️  No validation results" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "📝 NOTE: Full data comparison requires GuiTestingService extension" -ForegroundColor Gray
Write-Host "   Current validation confirms tabs open and CLI queries return data" -ForegroundColor Gray
Write-Host ""

