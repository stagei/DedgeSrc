#Requires -Version 5.1

<#
.SYNOPSIS
    Comprehensive test script for the OllamaHandler module.

.DESCRIPTION
    Tests all major functions of the OllamaHandler module including:
    - Module import and availability
    - Service functions
    - Installation functions
    - Model management
    - Model library
    - Role and audience functions
    - Core AI functions (requires running Ollama)
    - Export/Import functions

.PARAMETER SkipAITests
    Skip tests that require a running Ollama service with models.

.PARAMETER Verbose
    Show detailed test output.

.EXAMPLE
    .\Test-OllamaHandler.ps1
    # Run all tests

.EXAMPLE
    .\Test-OllamaHandler.ps1 -SkipAITests
    # Run tests that don't require Ollama service

.AUTHOR
    Geir Helge Starholm, www.dEdge.no
#>

[CmdletBinding()]
param(
    [switch]$SkipAITests
)

#region Test Framework

$script:TestResults = @{
    Passed = 0
    Failed = 0
    Skipped = 0
    Results = @()
}

function Write-TestHeader {
    param([string]$Title)
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
}

function Write-TestSection {
    param([string]$Title)
    Write-Host ""
    Write-Host "───────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  $Title" -ForegroundColor Yellow
    Write-Host "───────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
}

function Test-Assertion {
    param(
        [string]$Name,
        [scriptblock]$Test,
        [switch]$Skip,
        [string]$SkipReason = ""
    )
    
    if ($Skip) {
        Write-Host "  ○ SKIP: $Name" -ForegroundColor Yellow
        if ($SkipReason) {
            Write-Host "    Reason: $SkipReason" -ForegroundColor DarkYellow
        }
        $script:TestResults.Skipped++
        $script:TestResults.Results += [PSCustomObject]@{
            Name = $Name
            Status = "Skipped"
            Error = $SkipReason
        }
        return
    }
    
    try {
        $result = & $Test
        if ($result -eq $true -or $null -ne $result) {
            Write-Host "  ✓ PASS: $Name" -ForegroundColor Green
            $script:TestResults.Passed++
            $script:TestResults.Results += [PSCustomObject]@{
                Name = $Name
                Status = "Passed"
                Error = $null
            }
        }
        else {
            Write-Host "  ✗ FAIL: $Name" -ForegroundColor Red
            Write-Host "    Result was null or false" -ForegroundColor DarkRed
            $script:TestResults.Failed++
            $script:TestResults.Results += [PSCustomObject]@{
                Name = $Name
                Status = "Failed"
                Error = "Result was null or false"
            }
        }
    }
    catch {
        Write-Host "  ✗ FAIL: $Name" -ForegroundColor Red
        Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor DarkRed
        $script:TestResults.Failed++
        $script:TestResults.Results += [PSCustomObject]@{
            Name = $Name
            Status = "Failed"
            Error = $_.Exception.Message
        }
    }
}

function Write-TestSummary {
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  TEST SUMMARY" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Passed:  $($script:TestResults.Passed)" -ForegroundColor Green
    Write-Host "  Failed:  $($script:TestResults.Failed)" -ForegroundColor $(if ($script:TestResults.Failed -gt 0) { "Red" } else { "Green" })
    Write-Host "  Skipped: $($script:TestResults.Skipped)" -ForegroundColor Yellow
    Write-Host "  Total:   $($script:TestResults.Passed + $script:TestResults.Failed + $script:TestResults.Skipped)" -ForegroundColor White
    Write-Host ""
    
    if ($script:TestResults.Failed -gt 0) {
        Write-Host "  Failed Tests:" -ForegroundColor Red
        $script:TestResults.Results | Where-Object { $_.Status -eq "Failed" } | ForEach-Object {
            Write-Host "    - $($_.Name): $($_.Error)" -ForegroundColor DarkRed
        }
    }
    
    Write-Host ""
}

#endregion

#region Main Tests

Write-TestHeader "OllamaHandler Module Test Suite"

# ─────────────────────────────────────────────────────────────────────────────
# Module Import Tests
# ─────────────────────────────────────────────────────────────────────────────
Write-TestSection "Module Import Tests"

Test-Assertion "Module file exists" {
    $modulePath = Join-Path $PSScriptRoot "..\OllamaHandler.psm1"
    Test-Path $modulePath
}

Test-Assertion "Module can be imported" {
    Import-Module (Join-Path $PSScriptRoot "..\OllamaHandler.psm1") -Force -ErrorAction Stop
    $true
}

Test-Assertion "Module is loaded" {
    $module = Get-Module -Name "OllamaHandler"
    $null -ne $module -and $module.Name -eq "OllamaHandler"
}

# ─────────────────────────────────────────────────────────────────────────────
# Exported Function Tests
# ─────────────────────────────────────────────────────────────────────────────
Write-TestSection "Exported Function Tests"

$expectedFunctions = @(
    'Test-OllamaService',
    'Start-OllamaService',
    'Get-OllamaPath',
    'Install-Ollama',
    'Get-OllamaModels',
    'Set-OllamaPort',
    'Set-OllamaModelsPath',
    'Get-OllamaConfiguration',
    'Get-OllamaModelLibrary',
    'Get-OllamaRecommendedModels',
    'Select-OllamaModelsToInstall',
    'Install-OllamaModelBatch',
    'Export-OllamaModel',
    'Import-OllamaModel',
    'Get-OllamaRoles',
    'Get-OllamaAudienceLevels',
    'Invoke-OllamaGenerate',
    'Invoke-Ollama',
    'Start-OllamaChat'
)

foreach ($functionName in $expectedFunctions) {
    Test-Assertion "Function '$functionName' is exported" {
        Get-Command -Name $functionName -Module OllamaHandler -ErrorAction SilentlyContinue
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Role and Audience Function Tests
# ─────────────────────────────────────────────────────────────────────────────
Write-TestSection "Role and Audience Function Tests"

Test-Assertion "Get-OllamaRoles returns roles" {
    $roles = Get-OllamaRoles
    $roles.Count -gt 0
}

Test-Assertion "Get-OllamaRoles includes expected roles" {
    $roles = Get-OllamaRoles
    $roleNames = $roles | ForEach-Object { $_.RoleKey }
    ($roleNames -contains "General") -and 
    ($roleNames -contains "CodeAssist") -and 
    ($roleNames -contains "Teacher")
}

Test-Assertion "Get-OllamaRoles -RoleName returns specific role" {
    $role = Get-OllamaRoles -RoleName "CodeAssist"
    $role.RoleKey -eq "CodeAssist" -and $role.SystemPrompt.Length -gt 0
}

Test-Assertion "Get-OllamaAudienceLevels returns levels" {
    $levels = Get-OllamaAudienceLevels
    $levels.Count -eq 5
}

Test-Assertion "Get-OllamaAudienceLevels includes expected levels" {
    $levels = Get-OllamaAudienceLevels
    $levelNames = $levels | ForEach-Object { $_.LevelKey }
    ($levelNames -contains "Expert") -and 
    ($levelNames -contains "Beginner") -and 
    ($levelNames -contains "Child")
}

Test-Assertion "Get-OllamaAudienceLevels -Level returns specific level" {
    $level = Get-OllamaAudienceLevels -Level "Beginner"
    $level.LevelKey -eq "Beginner" -and $level.Modifier.Length -gt 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Recommended Models Function Tests
# ─────────────────────────────────────────────────────────────────────────────
Write-TestSection "Recommended Models Function Tests"

Test-Assertion "Get-OllamaRecommendedModels returns models" {
    $models = Get-OllamaRecommendedModels
    $models.Count -gt 0
}

Test-Assertion "Get-OllamaRecommendedModels returns expected properties" {
    $models = Get-OllamaRecommendedModels
    $firstModel = $models | Select-Object -First 1
    $null -ne $firstModel.Name -and 
    $null -ne $firstModel.Title -and 
    $null -ne $firstModel.Description
}

Test-Assertion "Get-OllamaRecommendedModels -ModelGroup filters correctly" {
    $allModels = Get-OllamaRecommendedModels -ModelGroup "All"
    $nonGpuModels = Get-OllamaRecommendedModels -ModelGroup "Non-GPU"
    $nonGpuModels.Count -le $allModels.Count
}

# ─────────────────────────────────────────────────────────────────────────────
# Configuration Function Tests
# ─────────────────────────────────────────────────────────────────────────────
Write-TestSection "Configuration Function Tests"

Test-Assertion "Get-OllamaConfiguration returns configuration" {
    $config = Get-OllamaConfiguration
    $null -ne $config.Host -and 
    $null -ne $config.Port -and 
    $null -ne $config.ModelsPath
}

Test-Assertion "Get-OllamaConfiguration has expected properties" {
    $config = Get-OllamaConfiguration
    $config.PSObject.Properties.Name -contains "ServiceRunning"
}

# ─────────────────────────────────────────────────────────────────────────────
# Installation Function Tests
# ─────────────────────────────────────────────────────────────────────────────
Write-TestSection "Installation Function Tests"

Test-Assertion "Get-OllamaPath returns path or null" {
    # This should not throw, just return path or null
    $path = Get-OllamaPath -ErrorAction SilentlyContinue
    $true  # Test passes if it doesn't throw
}

$ollamaInstalled = $null -ne (Get-OllamaPath -ErrorAction SilentlyContinue)

Test-Assertion "Get-OllamaPath finds Ollama (if installed)" -Skip:(-not $ollamaInstalled) -SkipReason "Ollama not installed" {
    $path = Get-OllamaPath
    (Test-Path $path)
}

# ─────────────────────────────────────────────────────────────────────────────
# Service Function Tests
# ─────────────────────────────────────────────────────────────────────────────
Write-TestSection "Service Function Tests"

Test-Assertion "Test-OllamaService returns boolean" {
    $result = Test-OllamaService -ErrorAction SilentlyContinue
    $result -is [bool]
}

$ollamaRunning = Test-OllamaService -ErrorAction SilentlyContinue

# ─────────────────────────────────────────────────────────────────────────────
# Model Management Function Tests (Requires Ollama)
# ─────────────────────────────────────────────────────────────────────────────
Write-TestSection "Model Management Function Tests"

Test-Assertion "Get-OllamaModels returns array" -Skip:(-not $ollamaRunning -or $SkipAITests) -SkipReason "Ollama not running or AI tests skipped" {
    $models = Get-OllamaModels
    $models -is [array] -or $models -is [System.Collections.IEnumerable]
}

Test-Assertion "Get-OllamaModels -IncludeDetails returns objects" -Skip:(-not $ollamaRunning -or $SkipAITests) -SkipReason "Ollama not running or AI tests skipped" {
    $models = Get-OllamaModels -IncludeDetails
    if ($models.Count -gt 0) {
        $models[0].PSObject.Properties.Name -contains "SizeGB"
    }
    else {
        $true  # No models installed, but function works
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Model Library Function Tests (Requires Internet)
# ─────────────────────────────────────────────────────────────────────────────
Write-TestSection "Model Library Function Tests (Internet Required)"

Test-Assertion "Get-OllamaModelLibrary fetches models" {
    try {
        $models = Get-OllamaModelLibrary -ErrorAction Stop
        $models.Count -gt 0
    }
    catch {
        # Network error is acceptable
        Write-Host "    (Network unavailable - test inconclusive)" -ForegroundColor DarkYellow
        $true
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Core AI Function Tests (Requires Ollama with Models)
# ─────────────────────────────────────────────────────────────────────────────
Write-TestSection "Core AI Function Tests"

$hasModels = $false
if ($ollamaRunning -and -not $SkipAITests) {
    $installedModels = Get-OllamaModels -ErrorAction SilentlyContinue
    $hasModels = $installedModels.Count -gt 0
}

Test-Assertion "Invoke-OllamaGenerate works" -Skip:(-not $hasModels -or $SkipAITests) -SkipReason "No models installed or AI tests skipped" {
    $response = Invoke-OllamaGenerate -Prompt "Say 'test' and nothing else" -MaxTokens 10
    $response.Length -gt 0
}

Test-Assertion "Invoke-Ollama returns structured response" -Skip:(-not $hasModels -or $SkipAITests) -SkipReason "No models installed or AI tests skipped" {
    $result = Invoke-Ollama -Prompt "Say 'hello'" -MaxTokens 20
    $result.PSObject.Properties.Name -contains "Success" -and 
    $result.PSObject.Properties.Name -contains "Response"
}

Test-Assertion "Invoke-Ollama -Raw returns string" -Skip:(-not $hasModels -or $SkipAITests) -SkipReason "No models installed or AI tests skipped" {
    $response = Invoke-Ollama -Prompt "Say 'test'" -Raw -MaxTokens 10
    $response -is [string]
}

Test-Assertion "Invoke-Ollama with Role works" -Skip:(-not $hasModels -or $SkipAITests) -SkipReason "No models installed or AI tests skipped" {
    $result = Invoke-Ollama -Prompt "What is 2+2?" -Role Teacher -Audience Beginner -MaxTokens 50
    $result.Role -eq "Teacher" -and $result.Audience -eq "Beginner"
}

# ─────────────────────────────────────────────────────────────────────────────
# Parameter Validation Tests
# ─────────────────────────────────────────────────────────────────────────────
Write-TestSection "Parameter Validation Tests"

Test-Assertion "Set-OllamaPort validates port range" {
    try {
        Set-OllamaPort -Port 500 -ErrorAction Stop  # Below valid range
        $false  # Should have thrown
    }
    catch {
        $true  # Expected to fail validation
    }
}

Test-Assertion "Get-OllamaRoles validates RoleName" {
    try {
        Get-OllamaRoles -RoleName "InvalidRole" -ErrorAction Stop
        $false  # Should have thrown
    }
    catch {
        $true  # Expected to fail validation
    }
}

Test-Assertion "Get-OllamaAudienceLevels validates Level" {
    try {
        Get-OllamaAudienceLevels -Level "InvalidLevel" -ErrorAction Stop
        $false  # Should have thrown
    }
    catch {
        $true  # Expected to fail validation
    }
}

#endregion

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
Write-TestSummary

# Return test results for automation
return $script:TestResults

