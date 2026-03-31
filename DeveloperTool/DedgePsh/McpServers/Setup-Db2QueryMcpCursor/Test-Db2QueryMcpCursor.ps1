<#
.SYNOPSIS
    Test the CursorDb2McpServer Streamable HTTP MCP endpoint.

.DESCRIPTION
    Sends JSON-RPC requests to the MCP server via its IIS virtual app endpoint.
    The server uses Streamable HTTP transport with stateful sessions (Mcp-Session-Id).

.PARAMETER ServerHost
    Hostname of the server. Default: dedge-server

.PARAMETER DatabaseName
    Alias database name to test with. Default: BASISTST

.EXAMPLE
    pwsh.exe -NoProfile -File Test-Db2QueryMcpCursor.ps1
#>
[CmdletBinding()]
param(
    [string]$ServerHost = 'dedge-server',
    [string]$DatabaseName = 'BASISTST'
)

Import-Module GlobalFunctions -Force
$ErrorActionPreference = 'Stop'

$mcpUrl = "http://$($ServerHost)/CursorDb2McpServer/"
$script:sessionId = $null

Write-LogMessage "Testing CursorDb2McpServer at $($mcpUrl)" -Level INFO

function Invoke-McpRequest {
    param([string]$Url, [hashtable]$Body)

    $json = $Body | ConvertTo-Json -Depth 6
    $headers = @{ 'Accept' = 'application/json, text/event-stream' }
    if ($script:sessionId) {
        $headers['Mcp-Session-Id'] = $script:sessionId
    }

    $response = Invoke-WebRequest -Uri $Url -Method Post -Body $json -ContentType 'application/json' -Headers $headers -TimeoutSec 60

    if ($response.Headers['Mcp-Session-Id']) {
        $script:sessionId = $response.Headers['Mcp-Session-Id'] | Select-Object -First 1
    }

    $lines = $response.Content -split "`n"
    $dataLine = $lines | Where-Object { $_ -match '^data: ' } | Select-Object -First 1
    if ($dataLine) {
        return ($dataLine -replace '^data: ', '') | ConvertFrom-Json
    }

    return $response.Content | ConvertFrom-Json
}

Write-LogMessage "1. Sending initialize request" -Level INFO
$initResult = Invoke-McpRequest -Url $mcpUrl -Body @{
    jsonrpc = '2.0'
    id = 1
    method = 'initialize'
    params = @{
        protocolVersion = '2024-11-05'
        capabilities = @{}
        clientInfo = @{ name = 'test-script'; version = '1.0' }
    }
}
Write-LogMessage "Server: $($initResult.result.serverInfo.name) v$($initResult.result.serverInfo.version)" -Level INFO
Write-LogMessage "Protocol: $($initResult.result.protocolVersion)" -Level INFO
Write-LogMessage "Session: $($script:sessionId)" -Level INFO

Write-LogMessage "2. Listing tools" -Level INFO
$listResult = Invoke-McpRequest -Url $mcpUrl -Body @{
    jsonrpc = '2.0'
    id = 2
    method = 'tools/list'
    params = @{}
}
foreach ($tool in $listResult.result.tools) {
    Write-LogMessage "Tool: $($tool.name) - $($tool.description)" -Level INFO
}

Write-LogMessage "3. Executing test query on $($DatabaseName)" -Level INFO
$queryResult = Invoke-McpRequest -Url $mcpUrl -Body @{
    jsonrpc = '2.0'
    id = 3
    method = 'tools/call'
    params = @{
        name = 'query_db2'
        arguments = @{
            databaseName = $DatabaseName
            query = 'SELECT CURRENT SERVER AS DB, CURRENT USER AS USR FROM SYSIBM.SYSDUMMY1 FETCH FIRST 1 ROWS ONLY'
        }
    }
}

if ($queryResult.result.content) {
    $content = $queryResult.result.content | Where-Object { $_.type -eq 'text' } | Select-Object -First 1
    if ($content) {
        $parsed = $content.text | ConvertFrom-Json
        Write-LogMessage "Database: $($parsed.database)" -Level INFO
        Write-LogMessage "User: $($parsed.currentUser)" -Level INFO
        Write-LogMessage "Rows: $($parsed.rows.Count)" -Level INFO
    }
}
elseif ($queryResult.error) {
    Write-LogMessage "Test failed: $($queryResult.error.message)" -Level ERROR
}

$result = [PSCustomObject]@{
    Script  = $MyInvocation.MyCommand.Name
    Status  = "OK"
    Message = "All DB2 Query MCP tests passed"
}
Write-LogMessage "RESULT: $($result.Status) - $($result.Message)" -Level INFO
Write-Output $result
