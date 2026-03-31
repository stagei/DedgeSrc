# Setup Tenant Isolation Test Data
# Creates test tenants, users for isolation testing

param(
    [string]$BaseUrl = "http://localhost:8100",
    [string]$OutputPath = "docs"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Setting Up Tenant Isolation Test Data" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

. "$PSScriptRoot\SecurityTestHelpers.ps1"

# Test data structure
$testData = @{
    TenantA = @{
        Domain = "tenant-a.test"
        DisplayName = "Tenant A"
        PrimaryColor = "#FF0000"
        Users = @()
    }
    TenantB = @{
        Domain = "tenant-b.test"
        DisplayName = "Tenant B"
        PrimaryColor = "#0000FF"
        Users = @()
    }
}

# Create Tenant A
Write-Host "Creating Tenant A..." -ForegroundColor Yellow
try {
    $tenantABody = @{
        domain = $testData.TenantA.Domain
        displayName = $testData.TenantA.DisplayName
        primaryColor = $testData.TenantA.PrimaryColor
        cssOverrides = ":root { --primary-color: $($testData.TenantA.PrimaryColor); }"
    } | ConvertTo-Json
    
    # Note: This requires admin authentication - for now we'll create via database
    Write-Host "  Note: Tenant creation requires admin API access" -ForegroundColor Gray
    Write-Host "  Tenant A: $($testData.TenantA.Domain) - $($testData.TenantA.DisplayName)" -ForegroundColor Gray
    
    # Create test users for Tenant A
    $userA1 = @{
        Email = "user-a1@$($testData.TenantA.Domain)"
        DisplayName = "User A1"
        Password = "TestPass123!"
    }
    $testData.TenantA.Users += $userA1
    
    $userA2 = @{
        Email = "user-a2@$($testData.TenantA.Domain)"
        DisplayName = "User A2"
        Password = "TestPass123!"
    }
    $testData.TenantA.Users += $userA2
}
catch {
    Write-Warning "Failed to create Tenant A: $($_.Exception.Message)"
}

# Create Tenant B
Write-Host "Creating Tenant B..." -ForegroundColor Yellow
try {
    Write-Host "  Tenant B: $($testData.TenantB.Domain) - $($testData.TenantB.DisplayName)" -ForegroundColor Gray
    
    # Create test users for Tenant B
    $userB1 = @{
        Email = "user-b1@$($testData.TenantB.Domain)"
        DisplayName = "User B1"
        Password = "TestPass123!"
    }
    $testData.TenantB.Users += $userB1
    
    $userB2 = @{
        Email = "user-b2@$($testData.TenantB.Domain)"
        DisplayName = "User B2"
        Password = "TestPass123!"
    }
    $testData.TenantB.Users += $userB2
}
catch {
    Write-Warning "Failed to create Tenant B: $($_.Exception.Message)"
}

# Save test data to JSON file
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$testDataFile = Join-Path $OutputPath "tenant-isolation-test-data.json"
$testData | ConvertTo-Json -Depth 10 | Out-File -FilePath $testDataFile -Encoding UTF8

Write-Host ""
Write-Host "Test data saved to: $testDataFile" -ForegroundColor Green
Write-Host ""
Write-Host "Test Users:" -ForegroundColor Cyan
Write-Host "  Tenant A:" -ForegroundColor Yellow
foreach ($user in $testData.TenantA.Users) {
    Write-Host "    - $($user.Email) / $($user.Password)" -ForegroundColor Gray
}
Write-Host "  Tenant B:" -ForegroundColor Yellow
foreach ($user in $testData.TenantB.Users) {
    Write-Host "    - $($user.Email) / $($user.Password)" -ForegroundColor Gray
}
Write-Host ""
Write-Host "Note: You may need to create these tenants and users manually via API or database" -ForegroundColor Yellow
Write-Host "      if you don't have admin access to the API." -ForegroundColor Yellow
Write-Host ""
