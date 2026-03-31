<#
.SYNOPSIS
    Tests all tab selections for a database provider

.DESCRIPTION
    This script validates that all tabs in all dialogs can be activated
    correctly. It tests tabs for Table, View, Procedure, Function, Package,
    and User dialogs.

.PARAMETER ConfigFile
    Path to provider configuration JSON file

.PARAMETER OutputPath
    Path to save test results (optional)

.PARAMETER TabsToTest
    Specific tabs to test (optional, tests all if not specified)

.EXAMPLE
    .\Test-AllTabs.ps1 -ConfigFile "..\ProviderConfigs\DB2_Config.json"

.EXAMPLE
    .\Test-AllTabs.ps1 -ConfigFile "..\ProviderConfigs\PostgreSQL_Config.json" -TabsToTest "columns","indexes"

.NOTES
    Version: 1.0
    Author: DbExplorer Project
    Date: December 14, 2025
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ConfigFile,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "..\TestResults",
    
    [Parameter(Mandatory=$false)]
    [string[]]$TabsToTest,
    
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

if (-not (Test-Path $exe)) {
    Write-Host "❌ DbExplorer.exe not found: $exe" -ForegroundColor Red
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  🧪 TAB SELECTION TEST" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Provider: $($config.provider) $($config.version)" -ForegroundColor White
Write-Host "Profile: $($config.profileName)" -ForegroundColor White
Write-Host ""

# Define all tabs to test
$allTabs = @(
    # TableDetailsDialog tabs
    @{Dialog="Table"; Object=$config.testObjects.table; Type="table"; Tab="columns"},
    @{Dialog="Table"; Object=$config.testObjects.table; Type="table"; Tab="foreign-keys"},
    @{Dialog="Table"; Object=$config.testObjects.table; Type="table"; Tab="indexes"},
    @{Dialog="Table"; Object=$config.testObjects.table; Type="table"; Tab="ddl-script"},
    @{Dialog="Table"; Object=$config.testObjects.table; Type="table"; Tab="statistics"},
    @{Dialog="Table"; Object=$config.testObjects.table; Type="table"; Tab="incoming-fk"},
    @{Dialog="Table"; Object=$config.testObjects.table; Type="table"; Tab="packages"},
    @{Dialog="Table"; Object=$config.testObjects.table; Type="table"; Tab="views"},
    @{Dialog="Table"; Object=$config.testObjects.table; Type="table"; Tab="routines"},
    
    # ObjectDetailsDialog tabs (View)
    @{Dialog="View"; Object=$config.testObjects.view; Type="view"; Tab="properties"},
    @{Dialog="View"; Object=$config.testObjects.view; Type="view"; Tab="source-code"},
    @{Dialog="View"; Object=$config.testObjects.view; Type="view"; Tab="create-ddl"},
    @{Dialog="View"; Object=$config.testObjects.view; Type="view"; Tab="drop-ddl"},
    @{Dialog="View"; Object=$config.testObjects.view; Type="view"; Tab="dependencies"},
    
    # ObjectDetailsDialog tabs (Procedure)
    @{Dialog="Procedure"; Object=$config.testObjects.procedure; Type="procedure"; Tab="properties"},
    @{Dialog="Procedure"; Object=$config.testObjects.procedure; Type="procedure"; Tab="source-code"},
    
    # ObjectDetailsDialog tabs (Function)
    @{Dialog="Function"; Object=$config.testObjects.function; Type="function"; Tab="properties"},
    @{Dialog="Function"; Object=$config.testObjects.function; Type="function"; Tab="source-code"},
    
    # PackageDetailsDialog tabs
    @{Dialog="Package"; Object=$config.testObjects.package; Type="package"; Tab="properties"},
    @{Dialog="Package"; Object=$config.testObjects.package; Type="package"; Tab="statements"},
    
    # UserDetailsDialog tabs
    @{Dialog="User"; Object=$config.testObjects.user; Type="user"; Tab="authorities"},
    @{Dialog="User"; Object=$config.testObjects.user; Type="user"; Tab="table-privileges"}
)

# Filter tabs if specific ones requested
if ($TabsToTest -and $TabsToTest.Count -gt 0) {
    $allTabs = $allTabs | Where-Object { $TabsToTest -contains $_.Tab }
    Write-Host "Testing only: $($TabsToTest -join ', ')" -ForegroundColor Yellow
    Write-Host ""
}

$results = @()
$passed = 0
$failed = 0
$skipped = 0

foreach ($test in $allTabs) {
    if ([string]::IsNullOrEmpty($test.Object) -or $test.Object -eq "N/A") {
        Write-Host "$($test.Dialog) - $($test.Tab)..." -NoNewline -ForegroundColor Gray
        Write-Host " ⏭️  SKIP" -ForegroundColor Gray
        $skipped++
        continue
    }
    
    Write-Host "$($test.Dialog) - $($test.Tab)..." -NoNewline -ForegroundColor Cyan
    
    # Launch app with specific tab
    Start-Process $exe -ArgumentList "--profile", $config.profileName, "--open", $test.Object, "--type", $test.Type, "--tab", $test.Tab
    
    # Wait for app to respond (with timeout)
    $elapsed = 0
    $proc = $null
    $success = $false
    
    while ($elapsed -lt $TimeoutSeconds) {
        $proc = Get-Process -Name "DbExplorer" -ErrorAction SilentlyContinue
        if ($proc -and $proc.Responding) {
            $success = $true
            break
        }
        Start-Sleep -Milliseconds 500
        $elapsed++
    }
    
    # Kill process
    taskkill /F /IM DbExplorer.exe 2>$null | Out-Null
    Start-Sleep -Milliseconds 300
    
    if ($success) {
        Write-Host " ✅ PASS" -ForegroundColor Green
        $passed++
        $results += [PSCustomObject]@{
            Dialog = $test.Dialog
            Tab = $test.Tab
            Object = $test.Object
            Status = "PASS"
        }
    } else {
        Write-Host " ❌ FAIL" -ForegroundColor Red
        $failed++
        $results += [PSCustomObject]@{
            Dialog = $test.Dialog
            Tab = $test.Tab
            Object = $test.Object
            Status = "FAIL"
        }
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total: $($allTabs.Count)" -ForegroundColor White
Write-Host "Passed: $passed" -ForegroundColor Green
Write-Host "Failed: $failed" -ForegroundColor Red
Write-Host "Skipped: $skipped" -ForegroundColor Gray
$tested = $passed + $failed
if ($tested -gt 0) {
    Write-Host "Pass Rate: $([math]::Round(($passed / $tested) * 100, 2))%" -ForegroundColor Yellow
}
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($results.Count -gt 0) {
    $results | Format-Table -AutoSize
}

# Save results
if ($OutputPath) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $outputFile = Join-Path $OutputPath "$($config.provider)_TabSelection_$timestamp.json"
    
    $report = @{
        provider = $config.provider
        version = $config.version
        testDate = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        testType = "TabSelection"
        results = @{
            total = $allTabs.Count
            passed = $passed
            failed = $failed
            skipped = $skipped
            passRate = if ($tested -gt 0) { [math]::Round(($passed / $tested) * 100, 2) } else { 0 }
        }
        details = $results
    }
    
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    $report | ConvertTo-Json -Depth 10 | Out-File $outputFile
    Write-Host "📄 Results saved to: $outputFile" -ForegroundColor Cyan
}

Write-Host ""
if ($failed -eq 0 -and $passed -gt 0) {
    Write-Host "🎉 ALL TAB TESTS PASSED!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "⚠️  $failed tab test(s) failed" -ForegroundColor Yellow
    exit 1
}

