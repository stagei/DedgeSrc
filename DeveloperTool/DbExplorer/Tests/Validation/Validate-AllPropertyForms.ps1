# DbExplorer - Comprehensive Property Form Validation
# Tests ALL tabs in ALL property dialogs to verify data displays correctly

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  🔍 COMPREHENSIVE FORM VALIDATION" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$exe = "bin\Debug\net10.0-windows\DbExplorer.exe"
$profile = "FKKTOTST"
$testResults = @()

# Define all test cases: Form, Object, Tab
$testCases = @(
    # TableDetailsDialog tabs
    @{Form="table-details"; Object="INL.KONTO"; Tab="columns"; ExpectedRows=9},
    @{Form="table-details"; Object="INL.KONTO"; Tab="foreign-keys"; ExpectedRows=5},
    @{Form="table-details"; Object="INL.KONTO"; Tab="indexes"; ExpectedRows=1},
    @{Form="table-details"; Object="INL.KONTO"; Tab="incoming-fk"; ExpectedRows=0},
    @{Form="table-details"; Object="INL.KONTO"; Tab="packages"; ExpectedRows=0},
    @{Form="table-details"; Object="INL.KONTO"; Tab="views"; ExpectedRows=0},
    @{Form="table-details"; Object="INL.KONTO"; Tab="routines"; ExpectedRows=0},
    
    # Additional table tests
    @{Form="table-details"; Object="INL.KUNDETYPE"; Tab="columns"; ExpectedRows=-1},
    @{Form="table-details"; Object="INL.LAND"; Tab="columns"; ExpectedRows=-1},
    
    # ObjectDetailsDialog (Views)
    @{Form="object-details"; Object="INL.SOME_VIEW"; Tab="properties"; ExpectedRows=-1},
    
    # PackageDetailsDialog
    @{Form="package-details"; Object="NULLID.SYSSH200"; Tab="statements"; ExpectedRows=-1},
    
    # UserDetailsDialog
    @{Form="user-details"; Object="DB2INST1"; Tab="table-privileges"; ExpectedRows=-1}
)

$totalTests = $testCases.Count
$passed = 0
$failed = 0

Write-Host "Running $totalTests validation tests..." -ForegroundColor Yellow
Write-Host ""

foreach ($test in $testCases) {
    $testName = "$($test.Form) - $($test.Object) - $($test.Tab)"
    Write-Host "Testing: $testName..." -ForegroundColor Cyan
    
    $outFile = "test_$($test.Form)_$($test.Tab)_$($test.Object -replace '\.','_').json"
    
    try {
        # Execute test-form
        $result = & $exe --profile $profile --test-form $test.Form --object $test.Object --tab $test.Tab --outfile $outFile 2>&1
        
        if ($LASTEXITCODE -eq 0 -and (Test-Path $outFile)) {
            $data = Get-Content $outFile -Raw | ConvertFrom-Json
            
            # Check if data was extracted
            if ($data.data) {
                $rowCount = if ($data.data.rowCount) { $data.data.rowCount } 
                           elseif ($data.data.rows) { $data.data.rows.Count } 
                           else { 0 }
                
                if ($rowCount -gt 0) {
                    Write-Host "  ✅ PASS: $rowCount rows extracted" -ForegroundColor Green
                    $passed++
                    $testResults += [PSCustomObject]@{
                        Test = $testName
                        Status = "PASS"
                        Rows = $rowCount
                        Expected = $test.ExpectedRows
                        Match = if ($test.ExpectedRows -eq -1) { "N/A" } else { $rowCount -eq $test.ExpectedRows }
                    }
                } elseif ($test.ExpectedRows -eq 0) {
                    Write-Host "  ✅ PASS: 0 rows (expected)" -ForegroundColor Green
                    $passed++
                    $testResults += [PSCustomObject]@{
                        Test = $testName
                        Status = "PASS"
                        Rows = 0
                        Expected = 0
                        Match = $true
                    }
                } else {
                    Write-Host "  ❌ FAIL: No data extracted" -ForegroundColor Red
                    $failed++
                    $testResults += [PSCustomObject]@{
                        Test = $testName
                        Status = "FAIL"
                        Rows = 0
                        Expected = $test.ExpectedRows
                        Match = $false
                    }
                }
            } else {
                Write-Host "  ❌ FAIL: No data property in response" -ForegroundColor Red
                $failed++
            }
            
            # Cleanup
            Remove-Item $outFile -Force -ErrorAction SilentlyContinue
        } else {
            Write-Host "  ❌ FAIL: test-form execution failed" -ForegroundColor Red
            $failed++
            $testResults += [PSCustomObject]@{
                Test = $testName
                Status = "FAIL"
                Rows = "ERROR"
                Expected = $test.ExpectedRows
                Match = $false
            }
        }
    }
    catch {
        Write-Host "  ❌ FAIL: Exception - $($_.Exception.Message)" -ForegroundColor Red
        $failed++
    }
    
    Write-Host ""
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  📊 VALIDATION SUMMARY" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Total Tests: $totalTests" -ForegroundColor White
Write-Host "Passed:      $passed" -ForegroundColor Green
Write-Host "Failed:      $failed" -ForegroundColor Red
Write-Host "Pass Rate:   $([math]::Round(($passed/$totalTests)*100, 2))%" -ForegroundColor Yellow
Write-Host ""

if ($testResults.Count -gt 0) {
    Write-Host "Detailed Results:" -ForegroundColor Cyan
    $testResults | Format-Table -AutoSize
}

if ($failed -eq 0) {
    Write-Host "🎉 ALL TESTS PASSED!" -ForegroundColor Green
} else {
    Write-Host "⚠️  $failed test(s) failed - review above for details" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Next: Manual verification in GUI to confirm grids are visible and populated" -ForegroundColor Yellow

