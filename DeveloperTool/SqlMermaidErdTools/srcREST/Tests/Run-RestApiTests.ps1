#Requires -Version 7.0

<#
.SYNOPSIS
    Comprehensive test suite for SqlMermaid REST API
.DESCRIPTION
    Tests all REST API endpoints with various scenarios, validates responses,
    and compares against baseline results to detect regressions.
    
    First run: Creates baseline files
    Subsequent runs: Compares against baseline and reports differences
.PARAMETER ResetBaseline
    Create/reset baseline files from current test outputs
.PARAMETER ApiBaseUrl
    Base URL for the API (default: http://localhost:5001/api/v1)
.PARAMETER SkipTokenCheck
    Skip API key validation (useful for development/testing)
.EXAMPLE
    .\Run-RestApiTests.ps1
    Run all API tests with default settings
.EXAMPLE
    .\Run-RestApiTests.ps1 -ResetBaseline
    Reset baseline files
.EXAMPLE
    .\Run-RestApiTests.ps1 -SkipTokenCheck
    Run tests without API key validation
#>

param(
    [Parameter(Mandatory=$false)]
    [switch]$ResetBaseline = $false,
    
    [Parameter(Mandatory=$false)]
    [string]$ApiBaseUrl = "http://localhost:5001/api/v1",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipTokenCheck = $false
)

$ErrorActionPreference = "Stop"

# Color output helpers
function Write-Header($message) {
    Write-Host "`n═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host $message -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan
}

function Write-Success($message) {
    Write-Host "✅ $message" -ForegroundColor Green
}

function Write-Failure($message) {
    Write-Host "❌ $message" -ForegroundColor Red
}

function Write-Info($message) {
    Write-Host "ℹ️  $message" -ForegroundColor Yellow
}

# Setup paths
$testRoot = $PSScriptRoot
$srcRestRoot = Split-Path -Parent $testRoot
$projectRoot = Split-Path -Parent $srcRestRoot
$baselineRoot = Join-Path $testRoot "Baseline"
$auditRoot = Join-Path $testRoot "Audit"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$currentAuditFolder = Join-Path $auditRoot $timestamp

# Detect if running on KRAKEN
$computerName = $env:COMPUTERNAME
$isKraken = $computerName -eq "KRAKEN"

# Auto-skip token check on KRAKEN
if ($isKraken -and -not $SkipTokenCheck) {
    Write-Info "Running on KRAKEN - automatically skipping token validation"
    $SkipTokenCheck = $true
}

# Create directories
Write-Header "Setting Up REST API Test Environment"
Write-Info "Computer: $computerName"
Write-Info "API Base URL: $ApiBaseUrl"
Write-Info "Token Check: $(if ($SkipTokenCheck) { 'DISABLED' } else { 'ENABLED' })"
Write-Info "Audit folder: $currentAuditFolder"

@($baselineRoot, $auditRoot, $currentAuditFolder) | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -ItemType Directory -Path $_ -Force | Out-Null
        Write-Info "Created directory: $_"
    }
}

# Initialize report
$reportPath = Join-Path $currentAuditFolder "REST_API_TEST_REPORT.md"
$report = New-Object System.Text.StringBuilder

[void]$report.AppendLine("# SqlMermaid REST API Test Report")
[void]$report.AppendLine("")
[void]$report.AppendLine("**Test Date:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$report.AppendLine("**Computer:** $computerName")
[void]$report.AppendLine("**API Base URL:** ``$ApiBaseUrl``")
[void]$report.AppendLine("**Token Validation:** $(if ($SkipTokenCheck) { 'DISABLED (KRAKEN mode)' } else { 'ENABLED' })")
[void]$report.AppendLine("**Audit Folder:** ``$currentAuditFolder``")
[void]$report.AppendLine("**Mode:** $(if ($ResetBaseline) { 'BASELINE CREATION' } else { 'REGRESSION TEST' })")
[void]$report.AppendLine("")
[void]$report.AppendLine("---")
[void]$report.AppendLine("")

# Test tracking
$totalTests = 0
$passedTests = 0
$failedTests = 0
$baselineCreated = $false

# Test data
$testSqlSimple = "CREATE TABLE users (id INT PRIMARY KEY, name VARCHAR(100));"
$testSqlComplex = @"
CREATE TABLE customers (
    customer_id INT PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE orders (
    order_id INT PRIMARY KEY,
    customer_id INT NOT NULL,
    total DECIMAL(10,2),
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);
"@

$testMermaidSimple = @"
erDiagram
    users {
        int id PK
        varchar name
    }
"@

$testMermaidBefore = @"
erDiagram
    products {
        int id PK
        varchar name
        decimal price
    }
"@

$testMermaidAfter = @"
erDiagram
    products {
        int id PK
        varchar name
        decimal price
        text description
        int stock
    }
"@

# Helper function to make API requests
function Invoke-ApiRequest {
    param(
        [string]$Method,
        [string]$Endpoint,
        [hashtable]$Body = $null,
        [string]$ApiKey = $null
    )
    
    $uri = "$ApiBaseUrl/$Endpoint"
    $headers = @{
        "Content-Type" = "application/json"
    }
    
    if ($ApiKey) {
        $headers["X-API-Key"] = $ApiKey
    }
    
    try {
        $params = @{
            Uri = $uri
            Method = $Method
            Headers = $headers
            UseBasicParsing = $true
        }
        
        if ($Body) {
            $params.Body = ($Body | ConvertTo-Json -Depth 10)
        }
        
        $response = Invoke-WebRequest @params
        
        return @{
            Success = $true
            StatusCode = $response.StatusCode
            Content = $response.Content | ConvertFrom-Json
        }
    } catch {
        return @{
            Success = $false
            StatusCode = $_.Exception.Response.StatusCode.value__
            Error = $_.Exception.Message
            Content = $null
        }
    }
}

# Helper function to compare responses with baseline
function Compare-WithBaseline {
    param(
        [string]$TestName,
        [object]$Response,
        [string]$BaselineFileName
    )
    
    $totalTests++
    $baselineFile = Join-Path $baselineRoot "$BaselineFileName.json"
    $currentFile = Join-Path $currentAuditFolder "$BaselineFileName.json"
    
    # Save current response
    $Response | ConvertTo-Json -Depth 10 | Out-File $currentFile -Encoding UTF8
    
    if ($ResetBaseline) {
        # Create baseline
        Copy-Item $currentFile $baselineFile -Force
        Write-Info "Created baseline: $BaselineFileName.json"
        [void]$report.AppendLine("- **$TestName**: ✅ Baseline created")
        $script:passedTests++
        $script:baselineCreated = $true
        return $true
    } else {
        # Compare with baseline
        if (-not (Test-Path $baselineFile)) {
            Write-Failure "$TestName - Baseline not found"
            [void]$report.AppendLine("- **$TestName**: ❌ FAIL - Baseline not found (run with -ResetBaseline)")
            $script:failedTests++
            return $false
        }
        
        $baselineContent = Get-Content $baselineFile -Raw | ConvertFrom-Json
        $currentContent = $Response
        
        # Compare JSON objects (basic comparison)
        $baselineJson = $baselineContent | ConvertTo-Json -Depth 10 -Compress
        $currentJson = $currentContent | ConvertTo-Json -Depth 10 -Compress
        
        if ($baselineJson -eq $currentJson) {
            Write-Success "$TestName - Matches baseline"
            [void]$report.AppendLine("- **$TestName**: ✅ PASS - Exact match")
            $script:passedTests++
            return $true
        } else {
            Write-Failure "$TestName - Differs from baseline"
            [void]$report.AppendLine("- **$TestName**: ❌ FAIL - Response differs from baseline")
            $script:failedTests++
            
            # Save diff
            $diffFile = Join-Path $currentAuditFolder "DIFF_$BaselineFileName.txt"
            "=== BASELINE ===" | Out-File $diffFile
            $baselineJson | Out-File $diffFile -Append
            "" | Out-File $diffFile -Append
            "=== CURRENT ===" | Out-File $diffFile -Append
            $currentJson | Out-File $diffFile -Append
            
            return $false
        }
    }
}

# STEP 0: Check if API is running
Write-Header "Checking API Availability"

# Check health directly (not via API base URL)
try {
    $healthResponse = Invoke-WebRequest -Uri "http://localhost:5001/health" -UseBasicParsing
    $healthCheck = @{
        Success = $true
        Content = $healthResponse.Content | ConvertFrom-Json
    }
} catch {
    $healthCheck = @{ Success = $false }
}
if (-not $healthCheck.Success) {
    Write-Failure "API is not running at $ApiBaseUrl"
    Write-Info "Please start the API first: cd srcREST && dotnet run"
    [void]$report.AppendLine("## ❌ API Not Available")
    [void]$report.AppendLine("")
    [void]$report.AppendLine("The API is not running. Start it with: ``cd srcREST && dotnet run``")
    $report.ToString() | Out-File $reportPath -Encoding UTF8
    exit 1
}

Write-Success "API is running"
Write-Info "Service: $($healthCheck.Content.service)"
Write-Info "Version: $($healthCheck.Content.version)"

[void]$report.AppendLine("## API Health Check")
[void]$report.AppendLine("")
[void]$report.AppendLine("**Status:** ✅ API is running")
[void]$report.AppendLine("**Service:** $($healthCheck.Content.service)")
[void]$report.AppendLine("**Version:** $($healthCheck.Content.version)")
[void]$report.AppendLine("")
[void]$report.AppendLine("---")
[void]$report.AppendLine("")

# STEP 1: Test Authentication (if not skipped)
Write-Header "Testing Authentication"

[void]$report.AppendLine("## Test 1: Authentication")
[void]$report.AppendLine("")

if ($SkipTokenCheck) {
    Write-Info "Token validation disabled - skipping authentication tests"
    [void]$report.AppendLine("**Status:** ⚠️ SKIPPED (KRAKEN mode)")
    [void]$report.AppendLine("")
    $testApiKey = $null
} else {
    # Test 1.1: Create API Key (Pro tier)
    $totalTests++
    Write-Info "Creating test API key (Pro tier)..."
    $createKeyRequest = @{
        email = "autotest@sqlmermaid.tools"
        licenseKey = "SQLMMD-PRO-AUTOTEST-$(Get-Random)"
    }
    
    $createKeyResponse = Invoke-ApiRequest -Method "POST" -Endpoint "auth/create-api-key" -Body $createKeyRequest
    
    if ($createKeyResponse.Success -and $createKeyResponse.Content.apiKey) {
        Write-Success "API key created successfully"
        $testApiKey = $createKeyResponse.Content.apiKey
        Write-Info "Tier: $($createKeyResponse.Content.tier)"
        [void]$report.AppendLine("- **Create API Key**: ✅ PASS")
        [void]$report.AppendLine("  - Email: $($createKeyRequest.email)")
        [void]$report.AppendLine("  - Tier: $($createKeyResponse.Content.tier)")
        $passedTests++
    } else {
        Write-Failure "Failed to create API key"
        [void]$report.AppendLine("- **Create API Key**: ❌ FAIL - $($createKeyResponse.Error)")
        $failedTests++
        $testApiKey = $null
    }
    
    # Test 1.2: Get Key Info
    if ($testApiKey) {
        $totalTests++
        Write-Info "Getting API key info..."
        $keyInfoResponse = Invoke-ApiRequest -Method "GET" -Endpoint "auth/key-info" -ApiKey $testApiKey
        
        if ($keyInfoResponse.Success) {
            Write-Success "Key info retrieved"
            [void]$report.AppendLine("- **Get Key Info**: ✅ PASS")
            [void]$report.AppendLine("  - Table Limit: $($keyInfoResponse.Content.tableLimit)")
            [void]$report.AppendLine("  - Daily Limit: $($keyInfoResponse.Content.dailyLimit)")
            $passedTests++
        } else {
            Write-Failure "Failed to get key info"
            [void]$report.AppendLine("- **Get Key Info**: ❌ FAIL")
            $failedTests++
        }
    }
}

[void]$report.AppendLine("")
[void]$report.AppendLine("---")
[void]$report.AppendLine("")

# STEP 2: Test SQL to Mermaid Conversion
Write-Header "Testing SQL to Mermaid Conversion"

[void]$report.AppendLine("## Test 2: SQL to Mermaid Conversion")
[void]$report.AppendLine("")

# Test 2.1: Simple SQL
$totalTests++
Write-Info "Testing simple SQL conversion..."
$sqlToMmdRequest = @{
    sql = $testSqlSimple
    includeAst = $false
}

$sqlToMmdResponse = Invoke-ApiRequest -Method "POST" -Endpoint "conversion/sql-to-mermaid" -Body $sqlToMmdRequest -ApiKey $testApiKey

if ($sqlToMmdResponse.Success -and $sqlToMmdResponse.Content.success) {
    Write-Success "Simple SQL conversion succeeded"
    Compare-WithBaseline -TestName "SQL to Mermaid (Simple)" -Response $sqlToMmdResponse.Content -BaselineFileName "sql_to_mmd_simple"
} else {
    Write-Failure "Simple SQL conversion failed"
    [void]$report.AppendLine("- **Simple SQL**: ❌ FAIL - $($sqlToMmdResponse.Error)")
    $failedTests++
}

# Test 2.2: Complex SQL with relationships
$totalTests++
Write-Info "Testing complex SQL conversion..."
$sqlToMmdComplexRequest = @{
    sql = $testSqlComplex
    includeAst = $false
}

$sqlToMmdComplexResponse = Invoke-ApiRequest -Method "POST" -Endpoint "conversion/sql-to-mermaid" -Body $sqlToMmdComplexRequest -ApiKey $testApiKey

if ($sqlToMmdComplexResponse.Success -and $sqlToMmdComplexResponse.Content.success) {
    Write-Success "Complex SQL conversion succeeded"
    Compare-WithBaseline -TestName "SQL to Mermaid (Complex)" -Response $sqlToMmdComplexResponse.Content -BaselineFileName "sql_to_mmd_complex"
} else {
    Write-Failure "Complex SQL conversion failed"
    [void]$report.AppendLine("- **Complex SQL**: ❌ FAIL - $($sqlToMmdComplexResponse.Error)")
    $failedTests++
}

[void]$report.AppendLine("")
[void]$report.AppendLine("---")
[void]$report.AppendLine("")

# STEP 3: Test Mermaid to SQL Conversion
Write-Header "Testing Mermaid to SQL Conversion"

[void]$report.AppendLine("## Test 3: Mermaid to SQL Conversion")
[void]$report.AppendLine("")

$dialects = @("AnsiSql", "SqlServer", "PostgreSql", "MySql")

foreach ($dialect in $dialects) {
    $totalTests++
    Write-Info "Testing $dialect conversion..."
    
    $mmdToSqlRequest = @{
        mermaid = $testMermaidSimple
        dialect = $dialect
        includeAst = $false
    }
    
    $mmdToSqlResponse = Invoke-ApiRequest -Method "POST" -Endpoint "conversion/mermaid-to-sql" -Body $mmdToSqlRequest -ApiKey $testApiKey
    
    if ($mmdToSqlResponse.Success -and $mmdToSqlResponse.Content.success) {
        Write-Success "$dialect conversion succeeded"
        Compare-WithBaseline -TestName "Mermaid to SQL ($dialect)" -Response $mmdToSqlResponse.Content -BaselineFileName "mmd_to_sql_$dialect"
    } else {
        Write-Failure "$dialect conversion failed"
        [void]$report.AppendLine("- **$dialect**: ❌ FAIL - $($mmdToSqlResponse.Error)")
        $failedTests++
    }
}

[void]$report.AppendLine("")
[void]$report.AppendLine("---")
[void]$report.AppendLine("")

# STEP 4: Test Migration Generation
Write-Header "Testing Migration Generation"

[void]$report.AppendLine("## Test 4: Migration Generation")
[void]$report.AppendLine("")

foreach ($dialect in $dialects) {
    $totalTests++
    Write-Info "Testing migration generation for $dialect..."
    
    $migrationRequest = @{
        beforeMermaid = $testMermaidBefore
        afterMermaid = $testMermaidAfter
        dialect = $dialect
    }
    
    $migrationResponse = Invoke-ApiRequest -Method "POST" -Endpoint "conversion/generate-migration" -Body $migrationRequest -ApiKey $testApiKey
    
    if ($migrationResponse.Success -and $migrationResponse.Content.success) {
        Write-Success "Migration for $dialect succeeded"
        Compare-WithBaseline -TestName "Migration ($dialect)" -Response $migrationResponse.Content -BaselineFileName "migration_$dialect"
    } else {
        Write-Failure "Migration for $dialect failed"
        [void]$report.AppendLine("- **Migration ($dialect)**: ❌ FAIL - $($migrationResponse.Error)")
        $failedTests++
    }
}

[void]$report.AppendLine("")
[void]$report.AppendLine("---")
[void]$report.AppendLine("")

# STEP 5: Test Error Handling
Write-Header "Testing Error Handling"

[void]$report.AppendLine("## Test 5: Error Handling")
[void]$report.AppendLine("")

# Test 5.1: Invalid SQL
$totalTests++
Write-Info "Testing invalid SQL handling..."
$invalidSqlRequest = @{
    sql = "INVALID SQL SYNTAX HERE"
}

$invalidSqlResponse = Invoke-ApiRequest -Method "POST" -Endpoint "conversion/sql-to-mermaid" -Body $invalidSqlRequest -ApiKey $testApiKey

if (-not $invalidSqlResponse.Success -or -not $invalidSqlResponse.Content.success) {
    Write-Success "Invalid SQL correctly rejected"
    [void]$report.AppendLine("- **Invalid SQL Handling**: ✅ PASS - Error correctly returned")
    $passedTests++
} else {
    Write-Failure "Invalid SQL was accepted (should have failed)"
    [void]$report.AppendLine("- **Invalid SQL Handling**: ❌ FAIL - Should have rejected invalid SQL")
    $failedTests++
}

# Test 5.2: Missing required fields
if (-not $SkipTokenCheck) {
    $totalTests++
    Write-Info "Testing missing API key..."
    $noKeyResponse = Invoke-ApiRequest -Method "POST" -Endpoint "conversion/sql-to-mermaid" -Body $sqlToMmdRequest
    
    if ($noKeyResponse.StatusCode -eq 401) {
        Write-Success "Missing API key correctly rejected (401)"
        [void]$report.AppendLine("- **Missing API Key**: ✅ PASS - 401 Unauthorized")
        $passedTests++
    } else {
        Write-Failure "Missing API key not properly validated"
        [void]$report.AppendLine("- **Missing API Key**: ❌ FAIL - Should return 401")
        $failedTests++
    }
}

[void]$report.AppendLine("")
[void]$report.AppendLine("---")
[void]$report.AppendLine("")

# Summary
Write-Header "REST API Test Summary"

$passRate = if ($totalTests -gt 0) { [math]::Round(($passedTests / $totalTests) * 100, 2) } else { 0 }

Write-Host "Total Tests:  $totalTests" -ForegroundColor Cyan
Write-Host "Passed:       $passedTests" -ForegroundColor Green
Write-Host "Failed:       $failedTests" -ForegroundColor $(if ($failedTests -eq 0) { "Green" } else { "Red" })
Write-Host "Pass Rate:    $passRate%" -ForegroundColor $(if ($passRate -eq 100) { "Green" } else { "Yellow" })

[void]$report.AppendLine("## Summary")
[void]$report.AppendLine("")
[void]$report.AppendLine("| Metric | Value |")
[void]$report.AppendLine("|--------|-------|")
[void]$report.AppendLine("| **Total Tests** | $totalTests |")
[void]$report.AppendLine("| **Passed** | $passedTests ✅ |")
[void]$report.AppendLine("| **Failed** | $failedTests $(if ($failedTests -eq 0) { '✅' } else { '❌' }) |")
[void]$report.AppendLine("| **Pass Rate** | $passRate% |")
[void]$report.AppendLine("")

if ($baselineCreated) {
    [void]$report.AppendLine("### ⚠️ Baseline Files Created")
    [void]$report.AppendLine("")
    [void]$report.AppendLine("Baseline files have been created in:")
    [void]$report.AppendLine("``````")
    [void]$report.AppendLine($baselineRoot)
    [void]$report.AppendLine("``````")
    [void]$report.AppendLine("")
    [void]$report.AppendLine("**Run the tests again to perform actual regression testing.**")
    [void]$report.AppendLine("")
}

if ($failedTests -eq 0 -and -not $baselineCreated) {
    [void]$report.AppendLine("### ✅ All Tests Passed!")
    [void]$report.AppendLine("")
    [void]$report.AppendLine("All API endpoints are working correctly and match baseline responses.")
    [void]$report.AppendLine("")
} elseif ($failedTests -gt 0) {
    [void]$report.AppendLine("### ⚠️ Test Failures Detected!")
    [void]$report.AppendLine("")
    [void]$report.AppendLine("Review the test results above and check diff files in the audit folder.")
    [void]$report.AppendLine("")
}

[void]$report.AppendLine("---")
[void]$report.AppendLine("")
[void]$report.AppendLine("### Test Artifacts")
[void]$report.AppendLine("")
[void]$report.AppendLine("All test responses and diffs saved to:")
[void]$report.AppendLine("``````")
[void]$report.AppendLine($currentAuditFolder)
[void]$report.AppendLine("``````")
[void]$report.AppendLine("")

# Save report
$report.ToString() | Out-File $reportPath -Encoding UTF8

Write-Success "Report saved: $reportPath"
Write-Host ""

# Open report
Write-Info "Opening report..."
Start-Process "cursor" -ArgumentList "`"$reportPath`""

Write-Host ""
Write-Success "REST API tests complete!"
Write-Info "Audit folder: $currentAuditFolder"

# Exit with appropriate code
exit $(if ($failedTests -eq 0 -and -not $baselineCreated) { 0 } else { 1 })

