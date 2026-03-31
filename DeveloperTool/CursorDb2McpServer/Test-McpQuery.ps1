<#
.SYNOPSIS
    Test the CursorDb2McpServer Streamable HTTP MCP endpoint.
.DESCRIPTION
    Sends JSON-RPC requests to the MCP server via its IIS virtual app endpoint.
    The server uses Streamable HTTP transport with stateful sessions (Mcp-Session-Id).
.PARAMETER ServerHost
    Hostname of the server. Default: dedge-server
.EXAMPLE
    pwsh.exe -File Test-McpQuery.ps1
.EXAMPLE
    pwsh.exe -File Test-McpQuery.ps1 -ServerHost localhost
#>
[CmdletBinding()]
param(
    [string]$ServerHost = "dedge-server"
)

$ErrorActionPreference = 'Stop'

$mcpUrl = "http://$($ServerHost)/CursorDb2McpServer/"
$script:sessionId = $null

Write-Host "Testing CursorDb2McpServer at $mcpUrl"
Write-Host ""

function Invoke-McpRequest {
    param([string]$Url, [hashtable]$Body)
    $json = $Body | ConvertTo-Json -Depth 5
    $headers = @{ "Accept" = "application/json, text/event-stream" }
    if ($script:sessionId) {
        $headers["Mcp-Session-Id"] = $script:sessionId
    }
    $response = Invoke-WebRequest -Uri $Url -Method Post -Body $json -ContentType "application/json" -Headers $headers -TimeoutSec 60

    if ($response.Headers["Mcp-Session-Id"]) {
        $script:sessionId = $response.Headers["Mcp-Session-Id"] | Select-Object -First 1
    }

    $lines = $response.Content -split "`n"
    $dataLine = $lines | Where-Object { $_ -match '^data: ' } | Select-Object -First 1
    if ($dataLine) {
        return ($dataLine -replace '^data: ', '') | ConvertFrom-Json
    }
    return $response.Content | ConvertFrom-Json
}

# Step 1: Initialize
Write-Host "1. Sending initialize request..."
$initResult = Invoke-McpRequest -Url $mcpUrl -Body @{
    jsonrpc = "2.0"; id = 1; method = "initialize"
    params = @{
        protocolVersion = "2024-11-05"
        capabilities = @{}
        clientInfo = @{ name = "test-script"; version = "1.0" }
    }
}
Write-Host "   Server: $($initResult.result.serverInfo.name) v$($initResult.result.serverInfo.version)"
Write-Host "   Protocol: $($initResult.result.protocolVersion)"
Write-Host "   Session: $($script:sessionId)"

# Step 2: List tools
Write-Host "2. Listing tools..."
$listResult = Invoke-McpRequest -Url $mcpUrl -Body @{
    jsonrpc = "2.0"; id = 2; method = "tools/list"; params = @{}
}
foreach ($tool in $listResult.result.tools) {
    Write-Host "   Tool: $($tool.name) - $($tool.description)"
}

# Step 3: Execute a query
Write-Host "3. Executing test query..."
$queryResult = Invoke-McpRequest -Url $mcpUrl -Body @{
    jsonrpc = "2.0"; id = 3; method = "tools/call"
    params = @{
        name = "query_db2"
        arguments = @{
            databaseName = "FKMTST"
            query = "SELECT CURRENT SERVER AS DB, CURRENT USER AS USR FROM SYSIBM.SYSDUMMY1"
        }
    }
}

if ($queryResult.result.content) {
    $content = $queryResult.result.content | Where-Object { $_.type -eq "text" } | Select-Object -First 1
    if ($content) {
        $parsed = $content.text | ConvertFrom-Json
        Write-Host "   Database: $($parsed.database)"
        Write-Host "   User: $($parsed.currentUser)"
        Write-Host "   Rows: $($parsed.rows.Count)"
    }
}
elseif ($queryResult.error) {
    Write-Host "   ERROR: $($queryResult.error.message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "Test complete."
