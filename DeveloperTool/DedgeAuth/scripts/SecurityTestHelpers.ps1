# Security Test Helpers
# Shared functions for all security and tenant isolation tests

# Global test results array
if (-not (Get-Variable -Name "Global:SecurityTestResults" -ErrorAction SilentlyContinue)) {
    $Global:SecurityTestResults = @()
}

<#
.SYNOPSIS
    Records a test result to the global results array
#>
function Write-TestResult {
    param(
        [string]$TestName,
        [string]$Category,
        [bool]$Passed,
        [string]$Message = "",
        [object]$Details = $null
    )
    
    $result = @{
        TestName = $TestName
        Category = $Category
        Passed = $Passed
        Message = $Message
        Details = $Details
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
    
    $Global:SecurityTestResults += $result
    
    $status = if ($Passed) { "PASS" } else { "FAIL" }
    $color = if ($Passed) { "Green" } else { "Red" }
    
    Write-Host "[$status] $Category - $TestName" -ForegroundColor $color
    if ($Message) {
        Write-Host "  $Message" -ForegroundColor Gray
    }
}

<#
.SYNOPSIS
    Authenticates as a user and returns the access token
#>
function Login-AsUser {
    param(
        [string]$Email,
        [string]$Password,
        [string]$BaseUrl = "http://localhost:8100"
    )
    
    try {
        $body = @{
            email = $Email
            password = $Password
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Uri "$BaseUrl/api/auth/login" `
            -Method Post `
            -Body $body `
            -ContentType "application/json" `
            -ErrorAction Stop
        
        if ($response.success -and $response.accessToken) {
            return $response.accessToken
        }
        
        return $null
    }
    catch {
        Write-Warning "Login failed for $Email : $($_.Exception.Message)"
        return $null
    }
}

<#
.SYNOPSIS
    Makes an API request with error handling
#>
function Invoke-ApiRequest {
    param(
        [string]$Url,
        [string]$Method = "GET",
        [object]$Body = $null,
        [string]$Token = $null,
        [hashtable]$Headers = @{},
        [switch]$SkipCertificateCheck
    )
    
    $requestParams = @{
        Uri = $Url
        Method = $Method
        ErrorAction = "Stop"
    }
    
    if ($Body) {
        $requestParams.Body = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 10 }
        $requestParams.ContentType = "application/json"
    }
    
    if ($Token) {
        $requestParams.Headers = @{
            Authorization = "Bearer $Token"
        }
    }
    
    foreach ($key in $Headers.Keys) {
        if (-not $requestParams.Headers) {
            $requestParams.Headers = @{}
        }
        $requestParams.Headers[$key] = $Headers[$key]
    }
    
    try {
        $response = Invoke-RestMethod @requestParams
        return @{
            Success = $true
            StatusCode = 200
            Content = $response
            Headers = @{}
        }
    }
    catch {
        $statusCode = 0
        $content = $null
        
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $content = $reader.ReadToEnd() | ConvertFrom-Json -ErrorAction SilentlyContinue
            }
            catch {
                $content = $_.Exception.Message
            }
        }
        
        return @{
            Success = $false
            StatusCode = $statusCode
            Content = $content
            Error = $_.Exception.Message
            Headers = @{}
        }
    }
}

<#
.SYNOPSIS
    Gets a PostgreSQL database connection
#>
function Get-DatabaseConnection {
    param(
        [string]$ConnectionString,
        [string]$DbHost = "localhost",
        [int]$Port = 8432,
        [string]$Database = "DedgeAuth",
        [string]$Username = "postgres",
        [string]$Password = "postgres"
    )
    
    if ($ConnectionString) {
        # Parse connection string
        $parts = $ConnectionString -split ';'
        $connParams = @{}
        foreach ($part in $parts) {
            if ($part -match '^(\w+)=(.*)$') {
                $key = $matches[1]
                $value = $matches[2]
                switch ($key.ToLower()) {
                    'host' { $connParams['Host'] = $value }
                    'port' { $connParams['Port'] = [int]$value }
                    'database' { $connParams['Database'] = $value }
                    'username' { $connParams['Username'] = $value }
                    'password' { $connParams['Password'] = $value }
                }
            }
        }
        $resultHost = if ($connParams.ContainsKey('Host')) { $connParams['Host'] } else { $DbHost }
        $resultPort = if ($connParams.ContainsKey('Port')) { $connParams['Port'] } else { $Port }
        $resultDatabase = if ($connParams.ContainsKey('Database')) { $connParams['Database'] } else { $Database }
        $resultUsername = if ($connParams.ContainsKey('Username')) { $connParams['Username'] } else { $Username }
        $resultPassword = if ($connParams.ContainsKey('Password')) { $connParams['Password'] } else { $Password }
    }
    
    if ($ConnectionString) {
        return @{
            Host = $resultHost
            Port = $resultPort
            Database = $resultDatabase
            Username = $resultUsername
            Password = $resultPassword
        }
    } else {
        return @{
            Host = $DbHost
            Port = $Port
            Database = $Database
            Username = $Username
            Password = $Password
        }
    }
}

<#
.SYNOPSIS
    Executes a SQL query against PostgreSQL
#>
function Query-Database {
    param(
        [hashtable]$Connection,
        [string]$Query,
        [object[]]$Parameters = @()
    )
    
    $env:PGPASSWORD = $Connection.Password
    
    try {
        $psqlPath = $null
        $possiblePaths = @(
            "C:\Program Files\PostgreSQL\*\bin\psql.exe",
            "C:\pgsql\bin\psql.exe",
            "C:\PostgreSQL\bin\psql.exe"
        )
        
        foreach ($path in $possiblePaths) {
            $found = Get-Item $path -ErrorAction SilentlyContinue | 
                Sort-Object { [int]($_.Directory.Parent.Name) } -Descending | 
                Select-Object -First 1
            if ($found) {
                $psqlPath = $found.FullName
                break
            }
        }
        
        if (-not $psqlPath) {
            $psqlInPath = Get-Command psql -ErrorAction SilentlyContinue
            if ($psqlInPath) {
                $psqlPath = $psqlInPath.Source
            }
        }
        
        if (-not $psqlPath) {
            throw "PostgreSQL client (psql) not found"
        }
        
        # Build psql command - use Connection hashtable values directly
        $queryFile = [System.IO.Path]::GetTempFileName()
        $Query | Out-File -FilePath $queryFile -Encoding UTF8
        
        $dbHost = $Connection.Host
        $dbPort = $Connection.Port
        $dbUser = $Connection.Username
        $dbName = $Connection.Database
        
        $psqlArgs = @(
            "-h", $dbHost
            "-p", $dbPort.ToString()
            "-U", $dbUser
            "-d", $dbName
            "-t"
            "-A"
            "-F", "|"
            "-f", $queryFile
        )
        
        $output = & $psqlPath @psqlArgs 2>&1
        
        Remove-Item $queryFile -ErrorAction SilentlyContinue
        
        if ($LASTEXITCODE -ne 0) {
            throw "Query failed: $output"
        }
        
        # Parse output
        $lines = $output | Where-Object { $_ -and $_.Trim() }
        $results = @()
        
        foreach ($line in $lines) {
            if ($line -match '^\|') {
                $fields = $line -split '\|'
                $results += $fields
            }
        }
        
        return $results
    }
    catch {
        Write-Error "Database query failed: $($_.Exception.Message)"
        return $null
    }
    finally {
        Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue
    }
}

<#
.SYNOPSIS
    Decodes a JWT token (without verification)
#>
function Decode-JwtToken {
    param(
        [string]$Token
    )
    
    if (-not $Token) {
        return $null
    }
    
    try {
        $parts = $Token -split '\.'
        if ($parts.Length -ne 3) {
            return $null
        }
        
        # Decode payload (base64url)
        $payload = $parts[1]
        $payload = $payload.Replace('-', '+').Replace('_', '/')
        
        # Add padding if needed
        switch ($payload.Length % 4) {
            2 { $payload += "==" }
            3 { $payload += "=" }
        }
        
        $bytes = [System.Convert]::FromBase64String($payload)
        $json = [System.Text.Encoding]::UTF8.GetString($bytes)
        $claims = $json | ConvertFrom-Json
        
        return $claims
    }
    catch {
        Write-Warning "Failed to decode JWT: $($_.Exception.Message)"
        return $null
    }
}

<#
.SYNOPSIS
    Exports test results to JSON file
#>
function Export-TestResults {
    param(
        [string]$OutputPath,
        [string]$Prefix = "SECURITY_TEST_RESULTS"
    )
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $filename = "${Prefix}_${timestamp}.json"
    $fullPath = Join-Path $OutputPath $filename
    
    $Global:SecurityTestResults | ConvertTo-Json -Depth 10 | Out-File -FilePath $fullPath -Encoding UTF8
    
    Write-Host "Test results exported to: $fullPath" -ForegroundColor Cyan
    return $fullPath
}

<#
.SYNOPSIS
    Generates an HTML report from test results
#>
function Generate-HtmlReport {
    param(
        [string]$OutputPath,
        [string]$Prefix = "SECURITY_TEST_RESULTS",
        [string]$Title = "Security Test Results"
    )
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $filename = "${Prefix}_${timestamp}.html"
    $fullPath = Join-Path $OutputPath $filename
    
    $totalTests = $Global:SecurityTestResults.Count
    $passedTests = ($Global:SecurityTestResults | Where-Object { $_.Passed }).Count
    $failedTests = $totalTests - $passedTests
    $passRate = if ($totalTests -gt 0) { [math]::Round(($passedTests / $totalTests) * 100, 2) } else { 0 }
    
    # Group by category
    $byCategory = $Global:SecurityTestResults | Group-Object -Property Category
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>$Title</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .header { background: #2c3e50; color: white; padding: 20px; border-radius: 5px; }
        .summary { background: white; padding: 20px; margin: 20px 0; border-radius: 5px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .category { background: white; padding: 15px; margin: 10px 0; border-radius: 5px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .test { padding: 10px; margin: 5px 0; border-left: 4px solid #ddd; }
        .test.pass { border-left-color: #27ae60; background: #d5f4e6; }
        .test.fail { border-left-color: #e74c3c; background: #fadbd8; }
        .stat { display: inline-block; margin: 10px 20px; }
        .stat-value { font-size: 2em; font-weight: bold; }
        .stat-label { color: #7f8c8d; }
        h2 { color: #2c3e50; }
        .timestamp { color: #95a5a6; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="header">
        <h1>$Title</h1>
        <div class="timestamp">Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</div>
    </div>
    
    <div class="summary">
        <h2>Summary</h2>
        <div class="stat">
            <div class="stat-value" style="color: #2c3e50;">$totalTests</div>
            <div class="stat-label">Total Tests</div>
        </div>
        <div class="stat">
            <div class="stat-value" style="color: #27ae60;">$passedTests</div>
            <div class="stat-label">Passed</div>
        </div>
        <div class="stat">
            <div class="stat-value" style="color: #e74c3c;">$failedTests</div>
            <div class="stat-label">Failed</div>
        </div>
        <div class="stat">
            <div class="stat-value" style="color: #3498db;">$passRate%</div>
            <div class="stat-label">Pass Rate</div>
        </div>
    </div>
"@
    
    foreach ($category in $byCategory) {
        $categoryPassed = ($category.Group | Where-Object { $_.Passed }).Count
        $categoryTotal = $category.Group.Count
        
        $html += @"
    <div class="category">
        <h2>$($category.Name) ($categoryPassed/$categoryTotal passed)</h2>
"@
        
        foreach ($test in $category.Group) {
            $class = if ($test.Passed) { "pass" } else { "fail" }
            $icon = if ($test.Passed) { "✓" } else { "✗" }
            
            $html += @"
        <div class="test $class">
            <strong>$icon $($test.TestName)</strong>
            <div class="timestamp">$($test.Timestamp)</div>
            $(if ($test.Message) { "<div>$($test.Message)</div>" })
        </div>
"@
        }
        
        $html += "    </div>`n"
    }
    
    $html += @"
</body>
</html>
"@
    
    $html | Out-File -FilePath $fullPath -Encoding UTF8
    
    Write-Host "HTML report generated: $fullPath" -ForegroundColor Cyan
    return $fullPath
}
