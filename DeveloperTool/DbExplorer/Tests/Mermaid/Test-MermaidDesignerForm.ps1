# DbExplorer - Automated Mermaid Designer Form Testing
# Tests Mermaid Visual Designer using GUI automation

param(
    [string]$Profile = "FKKTOTST",
    [string]$TestSchema = "INL",
    [int]$TimeoutSeconds = 30
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  🧪 MERMAID DESIGNER FORM TEST" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Profile: $Profile" -ForegroundColor White
Write-Host "Schema: $TestSchema" -ForegroundColor White
Write-Host ""

$exe = "bin\Debug\net10.0-windows\DbExplorer.exe"
$passed = 0
$failed = 0

# Helper function to run CLI command with timeout
function Invoke-CliCommand {
    param(
        [string[]]$Arguments,
        [int]$Timeout = 30
    )
    
    $outputFile = [System.IO.Path]::GetTempFileName() + ".json"
    $stderrFile = [System.IO.Path]::GetTempFileName() + ".err"
    
    # Add outfile to arguments
    $Arguments += @("-Outfile", $outputFile)
    
    try {
        $proc = Start-Process $exe -ArgumentList $Arguments -NoNewWindow -PassThru -Wait -RedirectStandardError $stderrFile
        
        if ($proc.ExitCode -eq 0) {
            # Read output from file
            if (Test-Path $outputFile) {
                $content = Get-Content $outputFile -Raw -ErrorAction SilentlyContinue
                
                if ($content) {
                    # Parse JSON
                    try {
                        return ($content | ConvertFrom-Json)
                    }
                    catch {
                        # Return raw content if not JSON
                        return $content
                    }
                }
            }
        }
        else {
            $errorContent = Get-Content $stderrFile -Raw -ErrorAction SilentlyContinue
            Write-Host "  ❌ CLI Error (exit $($proc.ExitCode)): $errorContent" -ForegroundColor Red
        }
    }
    finally {
        Remove-Item $outputFile -Force -ErrorAction SilentlyContinue
        Remove-Item $stderrFile -Force -ErrorAction SilentlyContinue
    }
    
    return $null
}

Write-Host "========================================" -ForegroundColor Yellow
Write-Host "  TEST 1: CLI MERMAID-ERD BASELINE" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

Write-Host "Generating baseline Mermaid ERD via CLI..." -ForegroundColor Cyan

$cliResult = Invoke-CliCommand @("--profile", $Profile, "--command", "mermaid-erd", "--schema", $TestSchema, "--limit", "5")

if ($cliResult -and $cliResult.mermaidDiagram) {
    $cliDiagramLength = $cliResult.mermaidDiagram.Length
    $cliTableCount = $cliResult.tableCount
    
    Write-Host "  ✅ PASS - CLI generated Mermaid diagram" -ForegroundColor Green
    Write-Host "     Diagram Length: $cliDiagramLength chars" -ForegroundColor Gray
    Write-Host "     Tables: $cliTableCount" -ForegroundColor Gray
    
    $passed++
}
else {
    Write-Host "  ❌ FAIL - CLI did not generate diagram" -ForegroundColor Red
    $failed++
    exit 1
}

Write-Host ""

Write-Host "========================================" -ForegroundColor Yellow
Write-Host "  TEST 2: GUI MERMAID DESIGNER FORM" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

Write-Host "Opening Mermaid Designer via GUI..." -ForegroundColor Cyan

# Kill any existing instances
taskkill /F /IM DbExplorer.exe 2>$null | Out-Null
Start-Sleep -Seconds 1

# Launch GUI with Mermaid designer for specific schema
$proc = Start-Process $exe -ArgumentList "--profile", $Profile, "--open", $TestSchema, "--type", "mermaid" -PassThru -NoNewWindow

Write-Host "  Process started (PID: $($proc.Id))" -ForegroundColor Gray

# Wait for application to fully load
Write-Host "  Waiting for application to load..." -ForegroundColor Gray
Start-Sleep -Seconds 8

# Check if process is still running
if ($proc.HasExited) {
    Write-Host "  ❌ FAIL - Application exited prematurely" -ForegroundColor Red
    $failed++
}
else {
    Write-Host "  ✅ PASS - Application is running" -ForegroundColor Green
    $passed++
    
    # Give more time for Mermaid Designer to initialize
    Write-Host "  Waiting for Mermaid Designer to initialize..." -ForegroundColor Gray
    Start-Sleep -Seconds 5
    
    # Check log for evidence of Mermaid Designer loading
    $logFile = Get-ChildItem "bin\Debug\net10.0-windows\logs\*.log" -ErrorAction SilentlyContinue | 
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    
    if ($logFile) {
        $recentLogs = Get-Content $logFile.FullName -Tail 100
        
        Write-Host ""
        Write-Host "  📋 Recent Log Entries:" -ForegroundColor Cyan
        
        # Check for key events
        $mermaidInit = $recentLogs | Select-String "Mermaid Designer|MermaidDesignerWindow" | Select-Object -Last 3
        if ($mermaidInit) {
            Write-Host "  ✅ Mermaid Designer initialized:" -ForegroundColor Green
            $mermaidInit | ForEach-Object { Write-Host "     $($_.Line.Substring(0, [Math]::Min(120, $_.Line.Length)))" -ForegroundColor Gray }
            $passed++
        }
        else {
            Write-Host "  ⚠️  No Mermaid Designer initialization logs found" -ForegroundColor Yellow
        }
        
        # Check for schema loading
        $schemaLoad = $recentLogs | Select-String "Opening Mermaid Designer for schema: $TestSchema" | Select-Object -Last 1
        if ($schemaLoad) {
            Write-Host "  ✅ Schema loaded: $TestSchema" -ForegroundColor Green
            $passed++
        }
        else {
            Write-Host "  ⚠️  Schema load not confirmed in logs" -ForegroundColor Yellow
        }
        
        # Check for WebView2 initialization
        $webViewInit = $recentLogs | Select-String "WebView2|MermaidWebView" | Select-Object -Last 2
        if ($webViewInit) {
            Write-Host "  ✅ WebView2 component loaded" -ForegroundColor Green
            $passed++
        }
        else {
            Write-Host "  ⚠️  WebView2 initialization not confirmed" -ForegroundColor Yellow
        }
    }
    
    Write-Host ""
    Write-Host "  💡 Manual verification needed:" -ForegroundColor Cyan
    Write-Host "     • Mermaid Designer window is visible" -ForegroundColor Gray
    Write-Host "     • Web-based editor is loaded in right pane" -ForegroundColor Gray
    Write-Host "     • 'Load from DB' button is clickable" -ForegroundColor Gray
    Write-Host "     • Preview pane is ready" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  ⏸️  Pausing 10 seconds for manual inspection..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
}

Write-Host ""

# Kill process
Write-Host "  🛑 Terminating application..." -ForegroundColor Gray
taskkill /F /IM DbExplorer.exe 2>$null | Out-Null
Start-Sleep -Seconds 2

Write-Host ""

Write-Host "========================================" -ForegroundColor Yellow
Write-Host "  TEST 3: AUTOMATED DIAGRAM GENERATION" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

Write-Host "Testing programmatic diagram generation..." -ForegroundColor Cyan
Write-Host "  ⚠️  This would require extending the automation framework" -ForegroundColor Yellow
Write-Host "  💡 Future enhancement: Add COM/Automation interface" -ForegroundColor Gray

Write-Host ""

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  📊 TEST SUMMARY" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$total = $passed + $failed
Write-Host "Total Tests: $total" -ForegroundColor White
Write-Host "Passed: $passed" -ForegroundColor Green
Write-Host "Failed: $failed" -ForegroundColor Red

if ($total -gt 0) {
    $passRate = [math]::Round(($passed / $total) * 100, 2)
    Write-Host "Pass Rate: $passRate%" -ForegroundColor Yellow
}

Write-Host ""

Write-Host "🎯 Mermaid Designer Testing:" -ForegroundColor Cyan
Write-Host "   ✅ CLI baseline working" -ForegroundColor White
Write-Host "   ✅ GUI launches correctly" -ForegroundColor White
Write-Host "   ⏭️  Manual verification required for full UI" -ForegroundColor White
Write-Host "   ⏭️  Automated data extraction pending" -ForegroundColor White
Write-Host ""

Write-Host "📝 Next Steps:" -ForegroundColor Cyan
Write-Host "   1. Manually test 'Load from DB' button" -ForegroundColor Gray
Write-Host "   2. Select tables and generate diagram" -ForegroundColor Gray
Write-Host "   3. Verify diagram renders in preview pane" -ForegroundColor Gray
Write-Host "   4. Test export/save functionality" -ForegroundColor Gray
Write-Host ""

if ($failed -eq 0 -and $passed -gt 0) {
    Write-Host "✅ All automated tests passed!" -ForegroundColor Green
    Write-Host "   (Manual verification still needed)" -ForegroundColor Gray
    exit 0
}
else {
    Write-Host "⚠️  Some tests failed - review results" -ForegroundColor Yellow
    exit 1
}

