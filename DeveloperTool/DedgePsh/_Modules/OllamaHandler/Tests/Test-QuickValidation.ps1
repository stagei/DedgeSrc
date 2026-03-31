#Requires -Version 5.1

<#
.SYNOPSIS
    Quick validation test for OllamaHandler module.

.DESCRIPTION
    Performs a rapid smoke test to verify the module is working.
    Runs in under 30 seconds (excluding AI response time).

.EXAMPLE
    .\Test-QuickValidation.ps1

.AUTHOR
    Geir Helge Starholm, www.dEdge.no
#>

[CmdletBinding()]
param()

$passed = 0
$failed = 0

Write-Host ""
Write-Host "OllamaHandler Quick Validation" -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan
Write-Host ""

# Test 1: Import module
Write-Host "1. Import module... " -NoNewline
try {
    $modulePath = Join-Path $PSScriptRoot "..\OllamaHandler.psm1"
    Import-Module $modulePath -Force -ErrorAction Stop
    Write-Host "OK" -ForegroundColor Green
    $passed++
}
catch {
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $failed++
    exit 1
}

# Test 2: Get roles
Write-Host "2. Get-OllamaRoles... " -NoNewline
try {
    $roles = Get-OllamaRoles
    if ($roles.Count -ge 5) {
        Write-Host "OK ($($roles.Count) roles)" -ForegroundColor Green
        $passed++
    }
    else {
        Write-Host "FAIL: Expected 5+ roles, got $($roles.Count)" -ForegroundColor Red
        $failed++
    }
}
catch {
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $failed++
}

# Test 3: Get audience levels
Write-Host "3. Get-OllamaAudienceLevels... " -NoNewline
try {
    $levels = Get-OllamaAudienceLevels
    if ($levels.Count -eq 5) {
        Write-Host "OK ($($levels.Count) levels)" -ForegroundColor Green
        $passed++
    }
    else {
        Write-Host "FAIL: Expected 5 levels, got $($levels.Count)" -ForegroundColor Red
        $failed++
    }
}
catch {
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $failed++
}

# Test 4: Get recommended models
Write-Host "4. Get-OllamaRecommendedModels... " -NoNewline
try {
    $models = Get-OllamaRecommendedModels
    if ($models.Count -gt 0) {
        Write-Host "OK ($($models.Count) models)" -ForegroundColor Green
        $passed++
    }
    else {
        Write-Host "FAIL: No models returned" -ForegroundColor Red
        $failed++
    }
}
catch {
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $failed++
}

# Test 5: Get configuration
Write-Host "5. Get-OllamaConfiguration... " -NoNewline
try {
    $config = Get-OllamaConfiguration
    if ($config.Port -gt 0) {
        Write-Host "OK (Port: $($config.Port))" -ForegroundColor Green
        $passed++
    }
    else {
        Write-Host "FAIL: Invalid config" -ForegroundColor Red
        $failed++
    }
}
catch {
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $failed++
}

# Test 6: Test service (doesn't require service to be running)
Write-Host "6. Test-OllamaService... " -NoNewline
try {
    $running = Test-OllamaService
    Write-Host "OK (Running: $running)" -ForegroundColor Green
    $passed++
}
catch {
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $failed++
}

# Test 7: Get Ollama path
Write-Host "7. Get-OllamaPath... " -NoNewline
try {
    $path = Get-OllamaPath
    if ($path) {
        Write-Host "OK ($path)" -ForegroundColor Green
    }
    else {
        Write-Host "OK (not installed)" -ForegroundColor Yellow
    }
    $passed++
}
catch {
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $failed++
}

# Test 8: AI test (if service running)
$serviceRunning = Test-OllamaService
if ($serviceRunning) {
    $models = Get-OllamaModels -ErrorAction SilentlyContinue
    if ($models.Count -gt 0) {
        Write-Host "8. Invoke-Ollama (AI test)... " -NoNewline
        try {
            $response = Invoke-Ollama -Prompt "Reply with only the word 'test'" -Raw -MaxTokens 10
            if ($response) {
                Write-Host "OK" -ForegroundColor Green
                $passed++
            }
            else {
                Write-Host "FAIL: Empty response" -ForegroundColor Red
                $failed++
            }
        }
        catch {
            Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
            $failed++
        }
    }
    else {
        Write-Host "8. Invoke-Ollama... SKIP (no models installed)" -ForegroundColor Yellow
    }
}
else {
    Write-Host "8. Invoke-Ollama... SKIP (service not running)" -ForegroundColor Yellow
}

# Summary
Write-Host ""
Write-Host "─────────────────────────────" -ForegroundColor DarkGray
$total = $passed + $failed
Write-Host "Results: $passed/$total passed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Yellow" })

if ($failed -eq 0) {
    Write-Host ""
    Write-Host "✓ Quick validation PASSED" -ForegroundColor Green
    exit 0
}
else {
    Write-Host ""
    Write-Host "✗ Quick validation FAILED ($failed failures)" -ForegroundColor Red
    exit 1
}

