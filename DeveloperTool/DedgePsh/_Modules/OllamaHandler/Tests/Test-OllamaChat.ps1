#Requires -Version 5.1

<#
.SYNOPSIS
    Quick test script for OllamaHandler chat and AI functionality.

.DESCRIPTION
    Tests the AI interaction capabilities including:
    - Simple prompts
    - Role-based prompts
    - Audience-level adjustments
    - Context file handling

.EXAMPLE
    .\Test-OllamaChat.ps1
    # Run interactive AI tests

.AUTHOR
    Geir Helge Starholm, www.dEdge.no
#>

[CmdletBinding()]
param()

# Import module
$modulePath = Join-Path $PSScriptRoot "..\OllamaHandler.psm1"
Import-Module $modulePath -Force

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║           OLLAMA CHAT FUNCTIONALITY TEST                       ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check service
Write-Host "Checking Ollama service..." -ForegroundColor Yellow
$serviceRunning = Test-OllamaService
if (-not $serviceRunning) {
    Write-Host "  Ollama service is not running." -ForegroundColor Red
    Write-Host "  Attempting to start..." -ForegroundColor Yellow
    $started = Start-OllamaService
    if (-not $started) {
        Write-Host "  Failed to start Ollama service. Please start it manually." -ForegroundColor Red
        Write-Host "  Run: ollama serve" -ForegroundColor Yellow
        exit 1
    }
}
Write-Host "  ✓ Ollama service is running" -ForegroundColor Green

# Check models
Write-Host ""
Write-Host "Checking installed models..." -ForegroundColor Yellow
$models = Get-OllamaModels -IncludeDetails
if ($models.Count -eq 0) {
    Write-Host "  No models installed!" -ForegroundColor Red
    Write-Host "  Please install a model first:" -ForegroundColor Yellow
    Write-Host "  ollama pull llama3.1:8b" -ForegroundColor White
    Write-Host ""
    Write-Host "  Or use the model browser:" -ForegroundColor Yellow
    Write-Host "  Select-OllamaModelsToInstall" -ForegroundColor White
    exit 1
}

Write-Host "  ✓ Found $($models.Count) model(s):" -ForegroundColor Green
$models | ForEach-Object {
    Write-Host "    - $($_.Name) ($($_.SizeGB) GB)" -ForegroundColor White
}

# Test 1: Simple prompt
Write-Host ""
Write-Host "───────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "Test 1: Simple Prompt" -ForegroundColor Yellow
Write-Host "───────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

$prompt = "In exactly one sentence, what is PowerShell?"
Write-Host "Prompt: $prompt" -ForegroundColor Cyan
Write-Host ""

$response = Invoke-Ollama -Prompt $prompt -Raw -MaxTokens 100
if ($response) {
    Write-Host "Response: " -ForegroundColor Green -NoNewline
    Write-Host $response -ForegroundColor White
    Write-Host "  ✓ Test passed" -ForegroundColor Green
}
else {
    Write-Host "  ✗ No response received" -ForegroundColor Red
}

# Test 2: Role-based prompt
Write-Host ""
Write-Host "───────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "Test 2: CodeAssist Role" -ForegroundColor Yellow
Write-Host "───────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

$prompt = "Write a one-line PowerShell command to list files in current directory"
Write-Host "Role: CodeAssist" -ForegroundColor Cyan
Write-Host "Prompt: $prompt" -ForegroundColor Cyan
Write-Host ""

$response = Invoke-Ollama -Prompt $prompt -Role CodeAssist -Raw -MaxTokens 150
if ($response) {
    Write-Host "Response: " -ForegroundColor Green -NoNewline
    Write-Host $response -ForegroundColor White
    Write-Host "  ✓ Test passed" -ForegroundColor Green
}
else {
    Write-Host "  ✗ No response received" -ForegroundColor Red
}

# Test 3: Audience adjustment
Write-Host ""
Write-Host "───────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "Test 3: Teacher Role with Beginner Audience" -ForegroundColor Yellow
Write-Host "───────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

$prompt = "What is a variable?"
Write-Host "Role: Teacher, Audience: Beginner" -ForegroundColor Cyan
Write-Host "Prompt: $prompt" -ForegroundColor Cyan
Write-Host ""

$result = Invoke-Ollama -Prompt $prompt -Role Teacher -Audience Beginner -MaxTokens 200
if ($result.Success) {
    Write-Host "Response: " -ForegroundColor Green -NoNewline
    Write-Host $result.Response -ForegroundColor White
    Write-Host ""
    Write-Host "  Role: $($result.Role), Audience: $($result.Audience)" -ForegroundColor DarkGray
    Write-Host "  ✓ Test passed" -ForegroundColor Green
}
else {
    Write-Host "  ✗ Error: $($result.Error)" -ForegroundColor Red
}

# Test 4: Structured response
Write-Host ""
Write-Host "───────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "Test 4: Structured Response Object" -ForegroundColor Yellow
Write-Host "───────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

$prompt = "Say hello"
Write-Host "Prompt: $prompt" -ForegroundColor Cyan
Write-Host ""

$result = Invoke-Ollama -Prompt $prompt -MaxTokens 20
Write-Host "Response Object Properties:" -ForegroundColor Green
Write-Host "  Success:   $($result.Success)" -ForegroundColor White
Write-Host "  Model:     $($result.Model)" -ForegroundColor White
Write-Host "  Role:      $($result.Role)" -ForegroundColor White
Write-Host "  Audience:  $($result.Audience)" -ForegroundColor White
Write-Host "  Timestamp: $($result.Timestamp)" -ForegroundColor White
Write-Host "  Response:  $($result.Response.Substring(0, [Math]::Min(50, $result.Response.Length)))..." -ForegroundColor White

if ($result.Success) {
    Write-Host "  ✓ Test passed" -ForegroundColor Green
}
else {
    Write-Host "  ✗ Test failed" -ForegroundColor Red
}

# Summary
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  All chat functionality tests completed!" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

