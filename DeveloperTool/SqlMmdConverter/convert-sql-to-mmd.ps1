#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Converts SQL DDL files to Mermaid ERD diagrams.

.DESCRIPTION
    Automatically detects SqlMmdConverter.exe or Python runtime and converts SQL files to Mermaid format.
    Output file is automatically named as input file with .mmd or .md extension.

.PARAMETER InputFile
    Path to the SQL file to convert (required)

.PARAMETER ExportMarkdown
    If specified, exports as Markdown with embedded Mermaid diagram (.md file)

.EXAMPLE
    .\convert-sql-to-mmd.ps1 test.sql
    Converts test.sql to test.sql.mmd

.EXAMPLE
    .\convert-sql-to-mmd.ps1 test.sql -ExportMarkdown
    Converts test.sql to test.sql.md with Mermaid diagram

.EXAMPLE
    .\convert-sql-to-mmd.ps1 D:\opt\src\SqlMmdConverter\test.sql -ExportMarkdown
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$InputFile,

    [Parameter(Mandatory = $false)]
    [switch]$ExportMarkdown
)

$ErrorActionPreference = 'Stop'

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  SQL to Mermaid ERD Converter" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

# Validate input file
if (-not (Test-Path $InputFile)) {
    Write-Host "✗ Input file not found: $InputFile" -ForegroundColor Red
    exit 1
}

$InputFile = Resolve-Path $InputFile
$OutputExtension = if ($ExportMarkdown) { ".md" } else { ".mmd" }
$OutputFile = "$InputFile$OutputExtension"

Write-Host "  Input:  $InputFile" -ForegroundColor Cyan
Write-Host "  Output: $OutputFile" -ForegroundColor Cyan
Write-Host "  Format: $(if ($ExportMarkdown) { 'Markdown with Mermaid' } else { 'Mermaid ERD' })" -ForegroundColor Cyan

# Function to find SqlMmdConverter.exe
function Find-SqlMmdConverter {
    # Search patterns
    $searchPaths = @(
        "samples\SqlMmdConverter.Samples\bin\Release\net10.0\SqlMmdConverter.Samples.exe",
        "samples\SqlMmdConverter.Samples\bin\Debug\net10.0\SqlMmdConverter.Samples.exe"
    )
    
    foreach ($path in $searchPaths) {
        if (Test-Path $path) {
            return (Resolve-Path $path)
        }
    }
    
    # Fallback: search in subdirectories
    $found = Get-ChildItem -Path . -Recurse -Filter "SqlMmdConverter.Samples.exe" -ErrorAction SilentlyContinue | 
        Select-Object -First 1
    
    if ($found) {
        return $found.FullName
    }
    
    return $null
}

# Function to find Python runtime
function Find-PythonRuntime {
    # Check for bundled Python
    $bundledPython = "src\SqlMmdConverter\runtimes\win-x64\python\python.exe"
    if (Test-Path $bundledPython) {
        $script = "src\SqlMmdConverter\runtimes\win-x64\scripts\sql_to_mmd.py"
        if (Test-Path $script) {
            return @{
                Python = (Resolve-Path $bundledPython)
                Script = (Resolve-Path $script)
            }
        }
    }
    
    # Check build output
    if (Test-Path "src\SqlMmdConverter\bin\Release\net10.0\runtimes\win-x64\python\python.exe") {
        $python = Resolve-Path "src\SqlMmdConverter\bin\Release\net10.0\runtimes\win-x64\python\python.exe"
        $script = Resolve-Path "src\SqlMmdConverter\bin\Release\net10.0\runtimes\win-x64\scripts\sql_to_mmd.py"
        return @{
            Python = $python
            Script = $script
        }
    }
    
    # Search in subdirectories
    $found = Get-ChildItem -Path . -Recurse -Filter "python.exe" -ErrorAction SilentlyContinue | 
        Where-Object { $_.FullName -like "*runtimes*win-x64*" } | 
        Select-Object -First 1
    
    if ($found) {
        $runtimeDir = Split-Path (Split-Path $found.FullName)
        $script = Join-Path $runtimeDir "scripts\sql_to_mmd.py"
        if (Test-Path $script) {
            return @{
                Python = $found.FullName
                Script = $script
            }
        }
    }
    
    return $null
}

# Try to find SqlMmdConverter.exe first (preferred method)
Write-Host "`nSearching for converter..." -ForegroundColor Yellow

$converterExe = Find-SqlMmdConverter

if ($converterExe) {
    Write-Host "✓ Found SqlMmdConverter.exe" -ForegroundColor Green
    Write-Host "  Path: $converterExe" -ForegroundColor Gray
    
    # Build arguments
    $converterArgs = @($InputFile)
    if ($ExportMarkdown) {
        $converterArgs += "--markdown"
    }
    
    Write-Host "`nConverting..." -ForegroundColor Cyan
    
    try {
        & $converterExe @converterArgs
        
        if ($LASTEXITCODE -eq 0 -and (Test-Path $OutputFile)) {
            $fileInfo = Get-Item $OutputFile
            Write-Host "`n✓ Success!" -ForegroundColor Green
            Write-Host "  Created: $OutputFile" -ForegroundColor Cyan
            Write-Host "  Size: $([math]::Round($fileInfo.Length/1KB, 2)) KB" -ForegroundColor Gray
        } else {
            Write-Host "✗ Conversion failed (exit code: $LASTEXITCODE)" -ForegroundColor Red
            exit 1
        }
    } catch {
        Write-Host "✗ Error: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
else {
    # Fallback to Python
    Write-Host "✓ SqlMmdConverter.exe not found, using Python fallback..." -ForegroundColor Yellow
    
    $pythonRuntime = Find-PythonRuntime
    
    if (-not $pythonRuntime) {
        Write-Host "✗ Neither SqlMmdConverter.exe nor Python runtime found" -ForegroundColor Red
        Write-Host "  Please build the project first: dotnet build" -ForegroundColor Yellow
        exit 1
    }
    
    Write-Host "✓ Found Python runtime" -ForegroundColor Green
    Write-Host "  Python: $($pythonRuntime.Python)" -ForegroundColor Gray
    Write-Host "  Script: $($pythonRuntime.Script)" -ForegroundColor Gray
    
    if ($ExportMarkdown) {
        Write-Host "`n⚠ Warning: Python fallback doesn't support --markdown flag" -ForegroundColor Yellow
        Write-Host "  Building markdown file manually..." -ForegroundColor Yellow
    }
    
    Write-Host "`nConverting..." -ForegroundColor Cyan
    
    try {
        $output = & $($pythonRuntime.Python) $($pythonRuntime.Script) $InputFile 2>&1 | Out-String
        
        if ($LASTEXITCODE -eq 0 -and $output -like "*erDiagram*") {
            if ($ExportMarkdown) {
                # Wrap in markdown manually
                $fileNameWithoutExtension = [System.IO.Path]::GetFileNameWithoutExtension($InputFile)
                $markdownContent = @"
# $fileNameWithoutExtension

``````mermaid
$output``````
"@
                $markdownContent | Out-File -FilePath $OutputFile -Encoding UTF8
            } else {
                $output | Out-File -FilePath $OutputFile -Encoding UTF8
            }
            
            $fileInfo = Get-Item $OutputFile
            Write-Host "`n✓ Success!" -ForegroundColor Green
            Write-Host "  Created: $OutputFile" -ForegroundColor Cyan
            Write-Host "  Size: $([math]::Round($fileInfo.Length/1KB, 2)) KB" -ForegroundColor Gray
        } else {
            Write-Host "✗ Conversion failed" -ForegroundColor Red
            Write-Host "Error output:" -ForegroundColor Yellow
            Write-Host $output -ForegroundColor Red
            exit 1
        }
    } catch {
        Write-Host "✗ Exception: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Done! Open $OutputFile to view the diagram" -ForegroundColor Cyan  
Write-Host "═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan
