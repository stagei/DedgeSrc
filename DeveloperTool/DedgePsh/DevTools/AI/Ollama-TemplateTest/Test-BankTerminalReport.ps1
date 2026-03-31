#Requires -Version 5.1

<#
.SYNOPSIS
    Tests the CreateBankTerminalOrderReport Ollama template.

.DESCRIPTION
    This script tests the template functionality by:
    1. Loading a sample bank terminal log file as context
    2. Applying the CreateBankTerminalOrderReport template
    3. Generating a markdown report

.PARAMETER LogFile
    Path to the log file to analyze. Defaults to the sample file in the script directory.

.PARAMETER OutputFile
    Path to save the generated report. Defaults to "BankTerminalReport.md" in current directory.

.PARAMETER Model
    The Ollama model to use. Defaults to first available model.

.EXAMPLE
    .\Test-BankTerminalReport.ps1
    # Uses sample log file and generates report

.EXAMPLE
    .\Test-BankTerminalReport.ps1 -LogFile "C:\logs\transaction.log" -OutputFile "report.md"
    # Uses specified log file and output

.AUTHOR
    Geir Helge Starholm, www.dEdge.no
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$LogFile = "",

    [Parameter()]
    [string]$OutputFile = "BankTerminalReport.md",

    [Parameter()]
    [string]$Model = ""
)

# Import required modules
Import-Module GlobalFunctions -Force -ErrorAction SilentlyContinue
Import-Module OllamaHandler -Force -ErrorAction Stop

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║    BANK TERMINAL REPORT TEMPLATE TEST                          ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Determine log file
if (-not $LogFile) {
    $LogFile = Join-Path $PSScriptRoot "AllResults.log"
}

if (-not (Test-Path $LogFile)) {
    Write-Host "Error: Log file not found: $LogFile" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please copy a log file to:" -ForegroundColor Yellow
    Write-Host "  $LogFile" -ForegroundColor White
    Write-Host ""
    Write-Host "Or specify a log file with -LogFile parameter" -ForegroundColor Yellow
    exit 1
}

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Log File:    $LogFile" -ForegroundColor White
Write-Host "  Output:      $OutputFile" -ForegroundColor White

# Check template exists
$template = Get-OllamaTemplates -TemplateName "CreateBankTerminalOrderReport"
if (-not $template) {
    Write-Host "  Template:    NOT FOUND!" -ForegroundColor Red
    Write-Host ""
    Write-Host "The template 'CreateBankTerminalOrderReport' was not found." -ForegroundColor Red
    Write-Host "Please ensure the template file exists at:" -ForegroundColor Yellow
    Write-Host "  $env:OptPath\data\OllamaTemplates\OllamaTemplates.json" -ForegroundColor White
    exit 1
}

Write-Host "  Template:    $($template.Name) [$($template.Source)]" -ForegroundColor Green
Write-Host ""

# Get file info
$fileInfo = Get-Item $LogFile
Write-Host "Log File Details:" -ForegroundColor Yellow
Write-Host "  Size:        $([math]::Round($fileInfo.Length / 1KB, 1)) KB" -ForegroundColor White
Write-Host "  Modified:    $($fileInfo.LastWriteTime)" -ForegroundColor White
Write-Host ""

# Check Ollama
Write-Host "Checking Ollama..." -ForegroundColor Yellow
if (-not (Test-OllamaService)) {
    Write-Host "Ollama is not running. Attempting to start..." -ForegroundColor Yellow
    if (-not (Start-OllamaService)) {
        Write-Host "Failed to start Ollama. Please start it manually." -ForegroundColor Red
        exit 1
    }
}

# Determine model
if (-not $Model) {
    $availableModels = Get-OllamaModels
    if ($availableModels.Count -eq 0) {
        Write-Host "No Ollama models available. Please install a model first." -ForegroundColor Red
        exit 1
    }
    $Model = $availableModels[0]
}

Write-Host "  Model:       $Model" -ForegroundColor Green
Write-Host ""

# Generate report
Write-Host "Generating report..." -ForegroundColor Yellow
Write-Host "─────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

$startTime = Get-Date

try {
    $response = Invoke-Ollama -Template "CreateBankTerminalOrderReport" -ContextFiles @($LogFile) -Model $Model -MaxTokens 8192 -Raw
    
    $endTime = Get-Date
    $duration = $endTime - $startTime

    if ($response) {
        # Save to file
        $response | Set-Content -Path $OutputFile -Encoding UTF8
        
        Write-Host ""
        Write-Host "─────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "╔═══════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "║      REPORT GENERATED SUCCESSFULLY!   ║" -ForegroundColor Green
        Write-Host "╚═══════════════════════════════════════╝" -ForegroundColor Green
        Write-Host ""
        Write-Host "Results:" -ForegroundColor Yellow
        Write-Host "  Output File: $(Resolve-Path $OutputFile)" -ForegroundColor White
        Write-Host "  Duration:    $([math]::Round($duration.TotalSeconds, 1)) seconds" -ForegroundColor White
        Write-Host "  Characters:  $($response.Length)" -ForegroundColor White
        Write-Host ""
        
        # Preview first few lines
        Write-Host "Report Preview:" -ForegroundColor Yellow
        Write-Host "─────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        $lines = $response -split "`n" | Select-Object -First 15
        foreach ($line in $lines) {
            Write-Host $line -ForegroundColor Gray
        }
        if (($response -split "`n").Count -gt 15) {
            Write-Host "..." -ForegroundColor DarkGray
            Write-Host "(truncated - see full report in output file)" -ForegroundColor DarkGray
        }
        Write-Host ""
    }
    else {
        Write-Host ""
        Write-Host "Failed to generate report. Check Ollama logs for details." -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host ""
    Write-Host "Error generating report:" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

