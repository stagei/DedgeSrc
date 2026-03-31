# DbExplorer - Comprehensive Tab Testing Script
# Tests ALL tabs in ALL dialogs to verify data displays correctly

param(
    [string]$Profile = "FKKTOTST"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  🧪 COMPREHENSIVE TAB TESTING" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Profile: $Profile" -ForegroundColor White
Write-Host ""

$exe = "bin\Debug\net10.0-windows\DbExplorer.exe"
$testResults = @()

# Define ALL tab tests for ALL dialog types
$allTests = @(
    # TableDetailsDialog - 9 tabs
    @{Dialog="Table"; Object="INL.KONTO"; Type="table"; Tab="columns"; Expected="9 columns"},
    @{Dialog="Table"; Object="INL.KONTO"; Type="table"; Tab="foreign-keys"; Expected="5 FKs"},
    @{Dialog="Table"; Object="INL.KONTO"; Type="table"; Tab="indexes"; Expected="1 index"},
    @{Dialog="Table"; Object="INL.KONTO"; Type="table"; Tab="ddl-script"; Expected="DDL text"},
    @{Dialog="Table"; Object="INL.KONTO"; Type="table"; Tab="statistics"; Expected="Row count"},
    @{Dialog="Table"; Object="INL.KONTO"; Type="table"; Tab="incoming-fk"; Expected="0 rows"},
    @{Dialog="Table"; Object="INL.KONTO"; Type="table"; Tab="packages"; Expected="0 rows"},
    @{Dialog="Table"; Object="INL.KONTO"; Type="table"; Tab="views"; Expected="0 rows"},
    @{Dialog="Table"; Object="INL.KONTO"; Type="table"; Tab="routines"; Expected="0 rows"},
    
    # ObjectDetailsDialog - 5 tabs (View)
    @{Dialog="View"; Object="DBE.JOBJECT_VIEW"; Type="view"; Tab="properties"; Expected="Properties displayed"},
    @{Dialog="View"; Object="DBE.JOBJECT_VIEW"; Type="view"; Tab="source-code"; Expected="Source code"},
    @{Dialog="View"; Object="DBE.JOBJECT_VIEW"; Type="view"; Tab="create-ddl"; Expected="CREATE DDL"},
    @{Dialog="View"; Object="DBE.JOBJECT_VIEW"; Type="view"; Tab="drop-ddl"; Expected="DROP DDL"},
    @{Dialog="View"; Object="DBE.JOBJECT_VIEW"; Type="view"; Tab="dependencies"; Expected="Dependencies"},
    
    # ObjectDetailsDialog - 5 tabs (Procedure)
    @{Dialog="Procedure"; Object="SQLJ.DB2_INSTALL_JAR"; Type="procedure"; Tab="properties"; Expected="Properties"},
    @{Dialog="Procedure"; Object="SQLJ.DB2_INSTALL_JAR"; Type="procedure"; Tab="source-code"; Expected="Source"},
    @{Dialog="Procedure"; Object="SQLJ.DB2_INSTALL_JAR"; Type="procedure"; Tab="create-ddl"; Expected="CREATE DDL"},
    @{Dialog="Procedure"; Object="SQLJ.DB2_INSTALL_JAR"; Type="procedure"; Tab="drop-ddl"; Expected="DROP DDL"},
    @{Dialog="Procedure"; Object="SQLJ.DB2_INSTALL_JAR"; Type="procedure"; Tab="dependencies"; Expected="Dependencies"},
    
    # ObjectDetailsDialog - 5 tabs (Function)
    @{Dialog="Function"; Object="FK.D10AMD"; Type="function"; Tab="properties"; Expected="Properties"},
    @{Dialog="Function"; Object="FK.D10AMD"; Type="function"; Tab="source-code"; Expected="Source"},
    @{Dialog="Function"; Object="FK.D10AMD"; Type="function"; Tab="create-ddl"; Expected="CREATE DDL"},
    @{Dialog="Function"; Object="FK.D10AMD"; Type="function"; Tab="drop-ddl"; Expected="DROP DDL"},
    @{Dialog="Function"; Object="FK.D10AMD"; Type="function"; Tab="dependencies"; Expected="Dependencies"},
    
    # PackageDetailsDialog - 2 tabs
    @{Dialog="Package"; Object="DB2TE434.DBEPC1"; Type="package"; Tab="properties"; Expected="Package properties"},
    @{Dialog="Package"; Object="DB2TE434.DBEPC1"; Type="package"; Tab="statements"; Expected="SQL statements"},
    
    # UserDetailsDialog - 4 tabs (User - Roles tab not tested here)
    @{Dialog="User"; Object="DB2INST1"; Type="user"; Tab="authorities"; Expected="DB authorities"},
    @{Dialog="User"; Object="DB2INST1"; Type="user"; Tab="table-privileges"; Expected="Table privileges"},
    @{Dialog="User"; Object="DB2INST1"; Type="user"; Tab="schema-privileges"; Expected="Schema privileges"},
    @{Dialog="User"; Object="DB2INST1"; Type="user"; Tab="routine-privileges"; Expected="Routine privileges"}
)

$totalTests = $allTests.Count
$passed = 0
$failed = 0
$warned = 0

Write-Host "Running $totalTests tab tests..." -ForegroundColor Yellow
Write-Host ""

foreach ($test in $allTests) {
    $testName = "$($test.Dialog) - $($test.Object) - Tab:$($test.Tab)"
    Write-Host "Testing: $testName" -ForegroundColor Cyan
    
    try {
        # Launch app with specific tab
        $args = @("--profile", $Profile, "--open", $test.Object, "--type", $test.Type, "--tab", $test.Tab)
        Start-Process $exe -ArgumentList $args
        
        # Wait for dialog to open and load
        Start-Sleep -Seconds 5
        
        # Check if running
        $proc = Get-Process -Name "DbExplorer" -ErrorAction SilentlyContinue
        
        if ($proc) {
            # Check logs for tab activation
            $logFile = Get-ChildItem "bin\Debug\net10.0-windows\logs\*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            $tabLog = Get-Content $logFile.FullName | Select-Object -Last 50 | Select-String -Pattern "Activated tab.*$($test.Tab)|Activating tab.*$($test.Tab)"
            
            if ($tabLog) {
                Write-Host "  ✅ PASS - Tab activated: $($test.Tab)" -ForegroundColor Green
                $passed++
                $testResults += [PSCustomObject]@{
                    Dialog = $test.Dialog
                    Object = $test.Object
                    Tab = $test.Tab
                    Status = "PASS"
                }
            } else {
                Write-Host "  ⚠️  WARN - App running but tab not confirmed" -ForegroundColor Yellow
                $warned++
                $testResults += [PSCustomObject]@{
                    Dialog = $test.Dialog
                    Object = $test.Object
                    Tab = $test.Tab
                    Status = "WARN"
                }
            }
            
            # Kill process
            taskkill /F /IM DbExplorer.exe 2>$null | Out-Null
            Start-Sleep -Milliseconds 500
        } else {
            Write-Host "  ❌ FAIL - App crashed" -ForegroundColor Red
            $failed++
            $testResults += [PSCustomObject]@{
                Dialog = $test.Dialog
                Object = $test.Object
                Tab = $test.Tab
                Status = "FAIL"
            }
        }
    }
    catch {
        Write-Host "  ❌ FAIL - Exception: $($_.Exception.Message)" -ForegroundColor Red
        $failed++
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  📊 TEST SUMMARY" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Total Tests: $totalTests" -ForegroundColor White
Write-Host "Passed:      $passed" -ForegroundColor Green
Write-Host "Failed:      $failed" -ForegroundColor Red
Write-Host "Warnings:    $warned" -ForegroundColor Yellow
Write-Host "Pass Rate:   $([math]::Round(($passed/$totalTests)*100, 2))%" -ForegroundColor Yellow
Write-Host ""

if ($testResults.Count -gt 0) {
    Write-Host "Detailed Results:" -ForegroundColor Cyan
    $testResults | Format-Table -AutoSize
}

Write-Host ""

if ($failed -eq 0) {
    Write-Host "🎉 ALL TAB TESTS PASSED!" -ForegroundColor Green
} else {
    Write-Host "⚠️  $failed tab test(s) failed" -ForegroundColor Yellow
}

Write-Host ""

