# DbExplorer - Comprehensive Dialog Testing Script
# Tests all property dialogs with various database objects

param(
    [string]$Profile = "FKKTOTST"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  🧪 COMPREHENSIVE DIALOG TESTING" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Profile: $Profile" -ForegroundColor White
Write-Host ""

$exe = "bin\Debug\net10.0-windows\DbExplorer.exe"
$testResults = @()

# Define test cases for each dialog type
$tests = @(
    # TableDetailsDialog - multiple tables
    @{Name="INL.KONTO - All Tabs"; Args="--profile $Profile --open INL.KONTO"; Expected="9 columns, 5 FKs, 1 index"},
    @{Name="INL.KUNDETYPE - Basic"; Args="--profile $Profile --open INL.KUNDETYPE"; Expected="Columns visible"},
    @{Name="INL.LAND - Basic"; Args="--profile $Profile --open INL.LAND"; Expected="Columns visible"},
    
    # Additional tables
    @{Name="DBM.APPLIKASJONER"; Args="--profile $Profile --open DBM.APPLIKASJONER"; Expected="Columns visible"},
    @{Name="DBM.PERSON"; Args="--profile $Profile --open DBM.PERSON"; Expected="Columns visible"}
)

$successCount = 0
$failCount = 0

foreach ($test in $tests) {
    Write-Host "Testing: $($test.Name)..." -ForegroundColor Cyan
    
    try {
        # Kill any existing instances
        $proc = Get-Process -Name "DbExplorer" -ErrorAction SilentlyContinue
        if ($proc) {
            taskkill /F /IM DbExplorer.exe 2>$null | Out-Null
            Start-Sleep -Milliseconds 500
        }
        
        # Start app
        $argList = $test.Args -split ' '
        Start-Process $exe -ArgumentList $argList
        
        # Wait for app to launch and load
        Start-Sleep -Seconds 6
        
        # Check if process is running
        $proc = Get-Process -Name "DbExplorer" -ErrorAction SilentlyContinue
        
        if ($proc) {
            # Check logs for errors
            $logFile = Get-ChildItem "bin\Debug\net10.0-windows\logs\*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            $recentErrors = Get-Content $logFile.FullName | Select-Object -Last 100 | Select-String -Pattern "ERROR.*Failed to load|ERROR.*Column.*does not belong"
            
            if ($recentErrors) {
                Write-Host "  ❌ FAIL: Errors found in log" -ForegroundColor Red
                $recentErrors | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
                $failCount++
                $testResults += [PSCustomObject]@{
                    Test = $test.Name
                    Status = "FAIL"
                    Issue = "Errors in log"
                }
            } else {
                # Check for successful data loading
                $successLogs = Get-Content $logFile.FullName | Select-Object -Last 50 | Select-String -Pattern "Loaded \d+ columns|Table details loaded successfully"
                
                if ($successLogs) {
                    Write-Host "  ✅ PASS: Dialog opened and data loaded" -ForegroundColor Green
                    $successCount++
                    $testResults += [PSCustomObject]@{
                        Test = $test.Name
                        Status = "PASS"
                        Issue = "-"
                    }
                } else {
                    Write-Host "  ⚠️  WARN: Process running but no data load confirmation" -ForegroundColor Yellow
                    $testResults += [PSCustomObject]@{
                        Test = $test.Name
                        Status = "WARN"
                        Issue = "No data load confirmation"
                    }
                }
            }
        } else {
            Write-Host "  ❌ FAIL: Process crashed or didn't start" -ForegroundColor Red
            $failCount++
            $testResults += [PSCustomObject]@{
                Test = $test.Name
                Status = "FAIL"
                Issue = "Process crashed"
            }
        }
        
        # Cleanup
        taskkill /F /IM DbExplorer.exe 2>$null | Out-Null
        Start-Sleep -Milliseconds 500
    }
    catch {
        Write-Host "  ❌ FAIL: Exception - $($_.Exception.Message)" -ForegroundColor Red
        $failCount++
        $testResults += [PSCustomObject]@{
            Test = $test.Name
            Status = "FAIL"
            Issue = $_.Exception.Message
        }
    }
    
    Write-Host ""
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  📊 TEST SUMMARY" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Total Tests: $($tests.Count)" -ForegroundColor White
Write-Host "Passed:      $successCount" -ForegroundColor Green
Write-Host "Failed:      $failCount" -ForegroundColor Red
Write-Host "Pass Rate:   $([math]::Round(($successCount/$tests.Count)*100, 2))%" -ForegroundColor Yellow
Write-Host ""

if ($testResults.Count -gt 0) {
    Write-Host "Detailed Results:" -ForegroundColor Cyan
    $testResults | Format-Table -AutoSize
}

if ($failCount -eq 0 -and $successCount -eq $tests.Count) {
    Write-Host "🎉 ALL TESTS PASSED!" -ForegroundColor Green
} else {
    Write-Host "⚠️  $failCount test(s) failed - review above for details" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "✅ All dialogs tested. Final validation complete!" -ForegroundColor Green

