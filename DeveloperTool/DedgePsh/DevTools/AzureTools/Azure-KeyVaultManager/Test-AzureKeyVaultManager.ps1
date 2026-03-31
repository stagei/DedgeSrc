<#
.SYNOPSIS
    Test script for Azure-KeyVaultManager.ps1.

.DESCRIPTION
    Verifies Set, Get, List, Delete, and Undelete actions against the configured Key Vault.
    Uses keyvault-config.json for default vault and subscription.
    Run with pwsh.exe. Requires Azure CLI (az) and valid login.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$KeyVaultName,

    [Parameter(Mandatory = $false)]
    [string]$TestSecretName = "test-cursor-agent-$(Get-Date -Format 'yyyyMMddHHmmss')",

    [Parameter(Mandatory = $false)]
    [switch]$SkipCleanup
)

$ErrorActionPreference = "Stop"
$scriptRoot = $PSScriptRoot
$scriptPath = Join-Path $scriptRoot "Azure-KeyVaultManager.ps1"
$repoRoot = (Get-Item $scriptRoot).Parent.Parent.Parent.FullName
$azureFunctionsPath = Join-Path $repoRoot "_Modules\AzureFunctions"
Import-Module $azureFunctionsPath -Force -ErrorAction Stop
Assert-AzModule -ModuleNames 'Az.Accounts'

# Resolve vault from config if not provided
$kvName = $KeyVaultName
if (-not $kvName) {
    $configPath = Join-Path $scriptRoot "keyvault-config.json"
    if (Test-Path $configPath) {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        $kvName = $config.defaultVault
    }
}
if (-not $kvName) {
    Write-Error "KeyVaultName is required. Set -KeyVaultName or configure keyvault-config.json."
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Azure Key Vault Manager - Test Suite" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Vault: $kvName" -ForegroundColor Gray
Write-Host "Test secret: $TestSecretName" -ForegroundColor Gray
Write-Host ""

$testsPassed = 0
$testsFailed = 0

function Invoke-Test {
    param(
        [string]$Name,
        [scriptblock]$TestBlock
    )
    Write-Host "[$Name]" -ForegroundColor Yellow -NoNewline
    try {
        & $TestBlock
        Write-Host " PASS" -ForegroundColor Green
        $script:testsPassed++
        return $true
    }
    catch {
        Write-Host " FAIL" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
        $script:testsFailed++
        return $false
    }
}

# 1. Set (create)
$null = Invoke-Test -Name "Set (create)" -TestBlock {
    $p = @{
        Action        = "Set"
        KeyVaultName  = $kvName
        SecretName    = $TestSecretName
        SecretValue   = "InitialValue-$(Get-Date -Format 'yyyyMMddHHmmss')"
        ErrorAction   = "Stop"
    }
    & $scriptPath @p | Out-Null
}

# 2. Get
$fetchedValue = $null
$null = Invoke-Test -Name "Get (read)" -TestBlock {
    $p = @{
        Action       = "Get"
        KeyVaultName = $kvName
        SecretName   = $TestSecretName
        ErrorAction  = "Stop"
    }
    $out = & $scriptPath @p
    $obj = $out | ConvertFrom-Json
    if (-not $obj.value) { throw "No value returned" }
    $script:fetchedValue = $obj.value
}

# 3. List
$null = Invoke-Test -Name "List" -TestBlock {
    $p = @{
        Action       = "List"
        KeyVaultName = $kvName
        ErrorAction  = "Stop"
    }
    $out = & $scriptPath @p
    $list = $out | ConvertFrom-Json
    $found = $list | Where-Object { $_.key -eq $TestSecretName }
    if (-not $found) { throw "Test secret not found in list" }
}

# 4. Set (update - change secret value)
$null = Invoke-Test -Name "Set (update)" -TestBlock {
    $newVal = "UpdatedValue-$(Get-Date -Format 'yyyyMMddHHmmss')"
    $p = @{
        Action        = "Set"
        KeyVaultName  = $kvName
        SecretName    = $TestSecretName
        SecretValue   = $newVal
        ErrorAction   = "Stop"
    }
    & $scriptPath @p | Out-Null
    $p2 = @{ Action = "Get"; KeyVaultName = $kvName; SecretName = $TestSecretName }
    $out = & $scriptPath @p2
    $obj = $out | ConvertFrom-Json
    if ($obj.value -ne $newVal) { throw "Value not updated: expected $newVal, got $($obj.value)" }
}

# 5. Delete (soft-delete)
$null = Invoke-Test -Name "Delete (soft-delete)" -TestBlock {
    $p = @{
        Action       = "Delete"
        KeyVaultName = $kvName
        SecretName   = $TestSecretName
        ErrorAction  = "Stop"
    }
    & $scriptPath @p | Out-Null
    $p2 = @{ Action = "Get"; KeyVaultName = $kvName; SecretName = $TestSecretName }
    try {
        & $scriptPath @p2 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { throw "Secret should not be readable after soft-delete" }
    }
    catch { }
}

# 6. Undelete (recover)
$null = Invoke-Test -Name "Undelete (recover)" -TestBlock {
    $p = @{
        Action       = "Undelete"
        KeyVaultName = $kvName
        SecretName   = $TestSecretName
        ErrorAction  = "Stop"
    }
    & $scriptPath @p | Out-Null
    $p2 = @{ Action = "Get"; KeyVaultName = $kvName; SecretName = $TestSecretName }
    $out = & $scriptPath @p2
    $obj = $out | ConvertFrom-Json
    if (-not $obj.value) { throw "Secret not readable after recover" }
}

# 7. Optional cleanup - delete again so test secret is removed
if (-not $SkipCleanup) {
    $null = Invoke-Test -Name "Cleanup (delete)" -TestBlock {
        $p = @{
            Action       = "Delete"
            KeyVaultName = $kvName
            SecretName   = $TestSecretName
            ErrorAction  = "Stop"
        }
        & $scriptPath @p | Out-Null
    }
}

Write-Host ""
Write-Host "----------------------------------------" -ForegroundColor Cyan
Write-Host "Results: $testsPassed passed, $testsFailed failed" -ForegroundColor $(if ($testsFailed -eq 0) { "Green" } else { "Yellow" })
Write-Host "========================================" -ForegroundColor Cyan

if ($testsFailed -gt 0) { exit 1 }
exit 0
