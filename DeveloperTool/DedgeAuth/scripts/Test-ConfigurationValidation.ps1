# Test Configuration Validation
# Verifies configuration is valid

param(
    [string]$BaseUrl = "http://localhost:8100"
)

. "$PSScriptRoot\SecurityTestHelpers.ps1"

Write-Host "Testing Configuration Validation..." -ForegroundColor Yellow

try {
    # Test 1: Required config keys present
    $appSettingsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "src\DedgeAuth.Api\appsettings.json"
    
    if (Test-Path $appSettingsPath) {
        $config = Get-Content $appSettingsPath -Raw | ConvertFrom-Json
        
        $requiredKeys = @(
            "ConnectionStrings.AuthDb",
            "AuthConfiguration.JwtSecret",
            "AuthConfiguration.JwtIssuer",
            "AuthConfiguration.JwtAudience"
        )
        
        $missingKeys = @()
        foreach ($key in $requiredKeys) {
            $parts = $key -split '\.'
            $value = $config
            foreach ($part in $parts) {
                if ($value.PSObject.Properties.Name -contains $part) {
                    $value = $value.$part
                } else {
                    $missingKeys += $key
                    break
                }
            }
        }
        
        Write-TestResult -TestName "Required Config Keys" -Category "Configuration Validation" `
            -Passed ($missingKeys.Count -eq 0) `
            -Message "Required config keys $(if ($missingKeys.Count -eq 0) { 'present' } else { "missing: $($missingKeys -join ', ')" })"
        
        # Test 2: No placeholder values
        $hasPlaceholders = ($config.AuthConfiguration.JwtSecret -match "your-secret|placeholder|changeme") -or
                          ($config.ConnectionStrings.AuthDb -match "localhost.*postgres.*postgres")
        
        Write-TestResult -TestName "No Placeholder Values" -Category "Configuration Validation" `
            -Passed (-not $hasPlaceholders) `
            -Message "Configuration $(if (-not $hasPlaceholders) { 'has no placeholders' } else { 'contains placeholder values' })"
    }
}
catch {
    Write-TestResult -TestName "Configuration Validation" -Category "Configuration Validation" `
        -Passed $false `
        -Message "Failed to validate configuration: $($_.Exception.Message)"
}

Write-Host ""
