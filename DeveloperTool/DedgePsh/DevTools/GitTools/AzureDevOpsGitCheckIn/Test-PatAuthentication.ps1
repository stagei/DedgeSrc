# Test Azure DevOps PAT Authentication
# Author: Geir Helge Starholm, www.dEdge.no

param(
    [string]$Pat = 'CX7ZFkl4nFDyn8fFWR7DPYa1C04jEZHipMNXGfg0zYb5Oy0Mtxz9JQQJ99CAACAAAAAMSOigAAASAZDO2Uxv',
    [string]$Organization = 'Dedge',
    [string]$Project = 'Dedge',
    [string]$Email = 'srv_Dedge_repo@Dedge.onmicrosoft.com'
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Azure DevOps PAT Authentication Test" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Organization: $Organization"
Write-Host "  Project: $Project"
Write-Host "  Email: $Email"
Write-Host "  PAT: $($Pat.Substring(0,10))..." -ForegroundColor Gray
Write-Host ""

# Test 1: Empty username with PAT (standard Azure DevOps format)
Write-Host "=== Test 1: API call with empty username (:PAT) ===" -ForegroundColor Cyan
$base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$Pat"))
$headers = @{ Authorization = "Basic $base64Auth" }

try {
    $uri = "https://dev.azure.com/$Organization/$Project/_apis/git/repositories?api-version=6.0"
    $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -UseBasicParsing
    Write-Host "SUCCESS: Found $($response.count) repositories" -ForegroundColor Green
    $response.value | ForEach-Object { Write-Host "  - $($_.name)" -ForegroundColor Gray }
} catch {
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        $statusCode = [int]$_.Exception.Response.StatusCode.value__
        Write-Host "HTTP Status: $statusCode" -ForegroundColor Red
    }
}

# Test 2: Service account email as username
Write-Host "`n=== Test 2: API call with service email as username ===" -ForegroundColor Cyan
$base64Auth2 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${Email}:$Pat"))
$headers2 = @{ Authorization = "Basic $base64Auth2" }

try {
    $uri2 = "https://dev.azure.com/$Organization/$Project/_apis/git/repositories?api-version=6.0"
    $response2 = Invoke-RestMethod -Uri $uri2 -Headers $headers2 -Method Get -UseBasicParsing
    Write-Host "SUCCESS: Authentication works with email as username" -ForegroundColor Green
} catch {
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        $statusCode = [int]$_.Exception.Response.StatusCode.value__
        Write-Host "HTTP Status: $statusCode" -ForegroundColor Red
    }
}

# Test 3: Test against visualstudio.com domain
Write-Host "`n=== Test 3: visualstudio.com domain (legacy URL) ===" -ForegroundColor Cyan
try {
    $uri3 = "https://$Organization.visualstudio.com/DefaultCollection/$Project/_apis/git/repositories?api-version=6.0"
    $response3 = Invoke-RestMethod -Uri $uri3 -Headers $headers -Method Get -UseBasicParsing
    Write-Host "SUCCESS: visualstudio.com domain works ($($response3.count) repos)" -ForegroundColor Green
} catch {
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        $statusCode = [int]$_.Exception.Response.StatusCode.value__
        Write-Host "HTTP Status: $statusCode" -ForegroundColor Red
    }
}

# Test 4: Git credential URL format test (URL-encoded email)
Write-Host "`n=== Test 4: URL-encoded email format (for git credentials) ===" -ForegroundColor Cyan
$encodedEmail = $Email.Replace('@', '%40')
Write-Host "URL-encoded email: $encodedEmail" -ForegroundColor Gray
Write-Host "Git credential format: https://$($encodedEmail):***@$Organization.visualstudio.com" -ForegroundColor Gray
Write-Host "This format will be used for git clone/push operations" -ForegroundColor Yellow

Write-Host "`n========================================"
Write-Host "  Test Complete" -ForegroundColor Cyan
Write-Host "========================================`n"
