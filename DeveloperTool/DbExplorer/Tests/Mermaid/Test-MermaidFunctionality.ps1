# Test Mermaid Designer Functionality
# Purpose: Verify what actually works vs what I claimed works

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   MERMAID DESIGNER FUNCTIONALITY VERIFICATION TEST" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

$results = @()

# Test 1: Check if buttons exist in HTML
Write-Host "TEST 1: Verify buttons exist in MermaidDesigner.html" -ForegroundColor Yellow
$htmlContent = Get-Content "Resources\MermaidDesigner.html" -Raw

$buttons = @(
    @{Name="Load from DB"; Pattern='generateFromDB'},
    @{Name="Show Diff"; Pattern='showDiff'},
    @{Name="Generate DDL"; Pattern='generateDDL'},
    @{Name="Mermaid → SQL"; Pattern='generateSqlFromMermaid'},
    @{Name="Translate SQL"; Pattern='translateSqlDialog'}
)

foreach ($button in $buttons) {
    if ($htmlContent -match $button.Pattern) {
        Write-Host "  ✅ Button exists: $($button.Name)" -ForegroundColor Green
        $results += [PSCustomObject]@{
            Test = "Button Exists: $($button.Name)"
            Status = "PASS"
        }
    } else {
        Write-Host "  ❌ Button missing: $($button.Name)" -ForegroundColor Red
        $results += [PSCustomObject]@{
            Test = "Button Exists: $($button.Name)"
            Status = "FAIL"
        }
    }
}

# Test 2: Check if C# handlers exist
Write-Host "`nTEST 2: Verify C# message handlers exist" -ForegroundColor Yellow
$csContent = Get-Content "Dialogs\MermaidDesignerWindow.xaml.cs" -Raw

$handlers = @(
    @{Name="generateFromDB"; Method='HandleGenerateFromDB'},
    @{Name="analyzeDiff"; Method='HandleAnalyzeDiff'},
    @{Name="generateDDL"; Method='HandleGenerateDDL'},
    @{Name="generateSqlFromMermaid"; Method='HandleGenerateSqlFromMermaid'}
)

foreach ($handler in $handlers) {
    if ($csContent -match $handler.Method) {
        Write-Host "  ✅ Handler exists: $($handler.Method)" -ForegroundColor Green
        $results += [PSCustomObject]@{
            Test = "Handler Exists: $($handler.Method)"
            Status = "PASS"
        }
    } else {
        Write-Host "  ❌ Handler missing: $($handler.Method)" -ForegroundColor Red
        $results += [PSCustomObject]@{
            Test = "Handler Exists: $($handler.Method)"
            Status = "FAIL"
        }
    }
}

# Test 3: Check if AlterStatementReviewDialog is called
Write-Host "`nTEST 3: Verify AlterStatementReviewDialog integration" -ForegroundColor Yellow
if ($csContent -match 'new AlterStatementReviewDialog') {
    Write-Host "  ✅ AlterStatementReviewDialog is instantiated in code" -ForegroundColor Green
    $results += [PSCustomObject]@{
        Test = "AlterStatementReviewDialog Integration"
        Status = "PASS - Code Exists"
    }
} else {
    Write-Host "  ❌ AlterStatementReviewDialog NOT found in code" -ForegroundColor Red
    $results += [PSCustomObject]@{
        Test = "AlterStatementReviewDialog Integration"
        Status = "FAIL - Not Found"
    }
}

# Test 4: Check if SqlMermaidIntegrationService exists
Write-Host "`nTEST 4: Verify SqlMermaidIntegrationService" -ForegroundColor Yellow
if (Test-Path "Services\SqlMermaidIntegrationService.cs") {
    Write-Host "  ✅ SqlMermaidIntegrationService.cs exists" -ForegroundColor Green
    $serviceContent = Get-Content "Services\SqlMermaidIntegrationService.cs" -Raw
    
    $methods = @(
        'GenerateDdlFromDb2TablesAsync',
        'ConvertDdlToMermaidAsync',
        'ConvertMermaidToSqlAsync',
        'GenerateMigrationFromMermaidDiffAsync'
    )
    
    foreach ($method in $methods) {
        if ($serviceContent -match $method) {
            Write-Host "    ✅ Method: $method" -ForegroundColor Green
            $results += [PSCustomObject]@{
                Test = "Service Method: $method"
                Status = "PASS"
            }
        } else {
            Write-Host "    ❌ Method missing: $method" -ForegroundColor Red
            $results += [PSCustomObject]@{
                Test = "Service Method: $method"
                Status = "FAIL"
            }
        }
    }
} else {
    Write-Host "  ❌ SqlMermaidIntegrationService.cs NOT FOUND" -ForegroundColor Red
    $results += [PSCustomObject]@{
        Test = "SqlMermaidIntegrationService File"
        Status = "FAIL - File Not Found"
    }
}

# Test 5: CLI test-form support
Write-Host "`nTEST 5: Verify CLI test-form support for Mermaid Designer" -ForegroundColor Yellow
$guiTestingContent = Get-Content "Services\GuiTestingService.cs" -Raw
if ($guiTestingContent -match 'mermaid-designer') {
    Write-Host "  ✅ CLI test-form 'mermaid-designer' exists" -ForegroundColor Green
    $results += [PSCustomObject]@{
        Test = "CLI test-form support"
        Status = "PASS"
    }
} else {
    Write-Host "  ❌ CLI test-form 'mermaid-designer' NOT found" -ForegroundColor Red
    $results += [PSCustomObject]@{
        Test = "CLI test-form support"
        Status = "FAIL"
    }
}

# Test 6: Try to actually run CLI test
Write-Host "`nTEST 6: Run actual CLI test for Mermaid Designer" -ForegroundColor Yellow
try {
    Write-Host "  ⏳ Running: DbExplorer.exe --profile FKKTOTST --test-form mermaid-designer --object INL --outfile test_result.json" -ForegroundColor Gray
    
    $testProcess = Start-Process -FilePath "bin\Debug\net10.0-windows\DbExplorer.exe" `
        -ArgumentList "--profile FKKTOTST --test-form mermaid-designer --object INL --outfile test_result.json" `
        -PassThru -NoNewWindow -Wait
    
    Start-Sleep -Seconds 2
    
    if (Test-Path "test_result.json") {
        $testResult = Get-Content "test_result.json" | ConvertFrom-Json
        
        if ($testResult.error) {
            Write-Host "  ⚠️  CLI test ran but returned error: $($testResult.error)" -ForegroundColor Yellow
            $results += [PSCustomObject]@{
                Test = "CLI Execution Test"
                Status = "PARTIAL - Error: $($testResult.error)"
            }
        } elseif ($testResult.formName -eq "MermaidDesignerWindow") {
            Write-Host "  ✅ CLI test successful! Mermaid Designer opened and returned data" -ForegroundColor Green
            Write-Host "    Schema: $($testResult.targetSchema)" -ForegroundColor Gray
            Write-Host "    IsLoaded: $($testResult.isDesignerLoaded)" -ForegroundColor Gray
            $results += [PSCustomObject]@{
                Test = "CLI Execution Test"
                Status = "PASS"
            }
        } else {
            Write-Host "  ⚠️  Unexpected result format" -ForegroundColor Yellow
            $results += [PSCustomObject]@{
                Test = "CLI Execution Test"
                Status = "PARTIAL - Unexpected Format"
            }
        }
        
        Remove-Item "test_result.json" -ErrorAction SilentlyContinue
    } else {
        Write-Host "  ❌ CLI test failed - no output file created" -ForegroundColor Red
        $results += [PSCustomObject]@{
            Test = "CLI Execution Test"
            Status = "FAIL - No Output"
        }
    }
} catch {
    Write-Host "  ❌ CLI test failed with exception: $($_.Exception.Message)" -ForegroundColor Red
    $results += [PSCustomObject]@{
        Test = "CLI Execution Test"
        Status = "FAIL - Exception"
    }
}

# Summary
Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   TEST RESULTS SUMMARY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

$passCount = ($results | Where-Object { $_.Status -like "PASS*" }).Count
$failCount = ($results | Where-Object { $_.Status -like "FAIL*" }).Count
$partialCount = ($results | Where-Object { $_.Status -like "PARTIAL*" }).Count

Write-Host "Total Tests: $($results.Count)" -ForegroundColor White
Write-Host "  ✅ PASS: $passCount" -ForegroundColor Green
Write-Host "  ⚠️  PARTIAL: $partialCount" -ForegroundColor Yellow
Write-Host "  ❌ FAIL: $failCount" -ForegroundColor Red

Write-Host "`nDetailed Results:" -ForegroundColor Cyan
$results | Format-Table -AutoSize

# What Actually Works vs What Was Claimed
Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   VERIFICATION: What Actually Works?" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

Write-Host "CLAIMED:" -ForegroundColor Yellow
Write-Host "  ✅ Load from DB → Generates Mermaid diagram" -ForegroundColor Gray
Write-Host "  ✅ Show Diff → Displays schema changes" -ForegroundColor Gray
Write-Host "  ✅ Generate DDL → Opens AlterStatementReviewDialog" -ForegroundColor Gray

Write-Host "`nACTUAL STATUS:" -ForegroundColor Yellow
$loadFromDBWorks = $results | Where-Object { $_.Test -like "*HandleGenerateFromDB*" -and $_.Status -eq "PASS" }
$showDiffWorks = $results | Where-Object { $_.Test -like "*HandleAnalyzeDiff*" -and $_.Status -eq "PASS" }
$generateDDLWorks = $results | Where-Object { $_.Test -like "*AlterStatementReviewDialog*" -and $_.Status -like "PASS*" }

if ($loadFromDBWorks) {
    Write-Host "  ✅ Load from DB: Handler code exists (NOT TESTED FUNCTIONALLY)" -ForegroundColor Green
} else {
    Write-Host "  ❌ Load from DB: Handler code MISSING" -ForegroundColor Red
}

if ($showDiffWorks) {
    Write-Host "  ✅ Show Diff: Handler code exists (NOT TESTED FUNCTIONALLY)" -ForegroundColor Green
} else {
    Write-Host "  ❌ Show Diff: Handler code MISSING" -ForegroundColor Red
}

if ($generateDDLWorks) {
    Write-Host "  ✅ Generate DDL: AlterStatementReviewDialog code exists (NOT TESTED FUNCTIONALLY)" -ForegroundColor Green
} else {
    Write-Host "  ❌ Generate DDL: AlterStatementReviewDialog code MISSING" -ForegroundColor Red
}

Write-Host "`n⚠️  IMPORTANT:" -ForegroundColor Yellow
Write-Host "  These tests verify CODE EXISTS, not that it WORKS END-TO-END." -ForegroundColor White
Write-Host "  Manual testing required to verify actual functionality." -ForegroundColor White

Write-Host "`n═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan
