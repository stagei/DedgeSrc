#!/usr/bin/env pwsh
$pythonExe = "src\SqlMmdConverter\runtimes\win-x64\python\python.exe"
$script = "src\SqlMmdConverter\runtimes\win-x64\scripts\sql_to_mmd.py"
$inputSql = "test.sql"
$outputMmd = "test.mmd"

Write-Host "Converting test.sql to Mermaid ERD..." -ForegroundColor Cyan

try {
    $output = & $pythonExe $script $inputSql 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        $output | Out-File -FilePath $outputMmd -Encoding UTF8
        Write-Host "✓ Success! Created: $outputMmd" -ForegroundColor Green
        
        $lines = ($output | Measure-Object -Line).Lines
        Write-Host "  Lines: $lines" -ForegroundColor Gray
    } else {
        Write-Host "✗ Error:" -ForegroundColor Red
        Write-Host $output -ForegroundColor Yellow
    }
} catch {
    Write-Host "✗ Exception: $($_.Exception.Message)" -ForegroundColor Red
}

