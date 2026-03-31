# Test Generic Log Handler Web API endpoints.
# Uses -UseDefaultCredentials for Windows auth. /health does not require auth.
$ErrorActionPreference = 'Stop'
# Use HTTP to avoid SSL cert issues in local testing
$baseUrl = 'http://localhost:8110'

$results = @()

# 1. Health (no auth)
try {
    $r = Invoke-WebRequest -Uri "$baseUrl/health" -UseBasicParsing -TimeoutSec 10
    $results += [PSCustomObject]@{ Endpoint = 'GET /health'; Status = $r.StatusCode; Ok = ($r.StatusCode -eq 200) }
} catch {
    $results += [PSCustomObject]@{ Endpoint = 'GET /health'; Status = $_.Exception.Message; Ok = $false }
}

# 2. OpenAPI spec
try {
    $r = Invoke-WebRequest -Uri "$baseUrl/openapi/v1.json" -UseBasicParsing -TimeoutSec 10
    $results += [PSCustomObject]@{ Endpoint = 'GET /openapi/v1.json'; Status = $r.StatusCode; Ok = ($r.StatusCode -eq 200) }
} catch {
    $results += [PSCustomObject]@{ Endpoint = 'GET /openapi/v1.json'; Status = $_.Exception.Message; Ok = $false }
}

# 3. API endpoints (require Windows auth - use default credentials)
$apiTests = @(
    @{ Method = 'GET'; Path = '/api/logs/search'; Body = $null },
    @{ Method = 'GET'; Path = '/api/logs/statistics'; Body = $null },
    @{ Method = 'GET'; Path = '/api/logs/level-counts'; Body = $null },
    @{ Method = 'GET'; Path = '/api/logs/top-computers'; Body = $null },
    @{ Method = 'GET'; Path = '/api/logs/recent-errors'; Body = $null },
    @{ Method = 'GET'; Path = '/api/logs/00000000-0000-0000-0000-000000000001'; Body = $null },
    @{ Method = 'GET'; Path = '/api/dashboard/summary'; Body = $null },
    @{ Method = 'GET'; Path = '/api/dashboard/health'; Body = $null },
    @{ Method = 'GET'; Path = '/api/dashboard/trends'; Body = $null }
)
foreach ($t in $apiTests) {
    try {
        $params = @{ Uri = "$baseUrl$($t.Path)"; UseBasicParsing = $true; TimeoutSec = 15 }
        $r = Invoke-WebRequest @params
        $ok = ($r.StatusCode -eq 200) -or ($t.Path -match '00000000-0000-0000' -and $r.StatusCode -eq 404)
        $results += [PSCustomObject]@{ Endpoint = "$($t.Method) $($t.Path)"; Status = $r.StatusCode; Ok = $ok }
    } catch {
        $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { $null }
        $ok = ($t.Path -match '00000000-0000-0000' -and $code -eq 404)
        $results += [PSCustomObject]@{ Endpoint = "$($t.Method) $($t.Path)"; Status = if ($code) { $code } else { $_.Exception.Message }; Ok = $ok }
    }
}

# POST export endpoints (expect 200 with file or 400 on error)
$exportBody = '{"Page":1,"PageSize":10,"SortBy":"Timestamp","SortDescending":true}'
foreach ($path in '/api/logs/export/csv', '/api/logs/export/excel') {
    try {
        $r = Invoke-WebRequest -Uri "$baseUrl$path" -Method Post -Body $exportBody -ContentType 'application/json' -UseBasicParsing -TimeoutSec 15
        $results += [PSCustomObject]@{ Endpoint = "POST $path"; Status = $r.StatusCode; Ok = ($r.StatusCode -eq 200) }
    } catch {
        $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { $null }
        $results += [PSCustomObject]@{ Endpoint = "POST $path"; Status = if ($code) { $code } else { $_.Exception.Message }; Ok = $false }
    }
}

$results | Format-Table -AutoSize
$passed = ($results | Where-Object { $_.Ok }).Count
$total = $results.Count
Write-Host "Result: $passed / $total endpoints OK"
