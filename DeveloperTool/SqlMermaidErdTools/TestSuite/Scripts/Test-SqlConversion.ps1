#!/usr/bin/env pwsh
# Try build output first (most common case)
$pythonExe = "src\SqlMermaidErdTools\bin\Release\net10.0\runtimes\win-x64\python\python.exe"
$script = "src\SqlMermaidErdTools\bin\Release\net10.0\runtimes\win-x64\scripts\sql_to_mmd.py"

# Fallback to source runtimes if build output doesn't exist
if (-not (Test-Path $pythonExe)) {
    $pythonExe = "src\SqlMermaidErdTools\runtimes\win-x64\python\python.exe"
    $script = "src\SqlMermaidErdTools\runtimes\win-x64\scripts\sql_to_mmd.py"
}

$inputSql = "test.sql"
$outputMmd = "test.mmd"

if (-not (Test-Path $pythonExe)) {
    Write-Host "✗ Python runtime not found. Please build the project first: dotnet build" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $script)) {
    Write-Host "✗ Python script not found: $script" -ForegroundColor Red
    exit 1
}

Write-Host "Converting test.sql to Mermaid ERD..." -ForegroundColor Cyan
Write-Host "  Python: $pythonExe" -ForegroundColor Gray
Write-Host "  Script: $script" -ForegroundColor Gray

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


