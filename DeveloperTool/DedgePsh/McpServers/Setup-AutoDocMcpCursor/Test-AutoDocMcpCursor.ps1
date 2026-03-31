<#
.SYNOPSIS
    End-to-end test for the AutoDocJson MCP server.

.DESCRIPTION
    Sends JSON-RPC 2.0 requests to the AutoDocJson MCP endpoint to verify:
    1. MCP initialization handshake
    2. Tool listing (list_documents, get_document, search_documents)
    3. Tool invocation for each tool

.PARAMETER ServerHost
    Hostname of the server running AutoDocJson. Default: dedge-server

.EXAMPLE
    pwsh.exe -NoProfile -File Test-AutoDocMcpCursor.ps1
#>
[CmdletBinding()]
param(
    [string]$ServerHost = "dedge-server"
)

$ErrorActionPreference = 'Stop'

Import-Module GlobalFunctions -Force

$baseUrl = "http://$($ServerHost)/AutoDocJson/mcp"
$sessionId = $null
$requestId = 0

function Send-McpRequest {
    param(
        [string]$Method,
        [hashtable]$Params = @{}
    )

    $script:requestId++
    $body = @{
        jsonrpc = "2.0"
        id      = $script:requestId
        method  = $Method
        params  = $Params
    } | ConvertTo-Json -Depth 10

    $headers = @{
        "Content-Type" = "application/json"
        "Accept"       = "application/json, text/event-stream"
    }
    if ($script:sessionId) {
        $headers["Mcp-Session-Id"] = $script:sessionId
    }

    $response = Invoke-WebRequest -Uri $baseUrl -Method POST -Body $body -Headers $headers -UseBasicParsing

    $contentType = $response.Headers['Content-Type']
    if ($contentType -is [array]) { $contentType = $contentType[0] }
    if ($contentType -match 'text/html') {
        if ($response.Content -match 'DedgeAuth.*Login|login\.html') {
            throw "MCP endpoint returned DedgeAuth login page — authentication required. Ensure the MCP endpoint is excluded from DedgeAuth middleware."
        }
        throw "MCP endpoint returned HTML instead of JSON (Content-Type: $($contentType))"
    }

    if ($response.Headers["Mcp-Session-Id"]) {
        $script:sessionId = $response.Headers["Mcp-Session-Id"]
        if ($script:sessionId -is [array]) { $script:sessionId = $script:sessionId[0] }
    }

    $content = $response.Content
    if ($content -match "^data:\s*(.+)$") {
        $content = $matches[1]
    }
    $lines = $content -split "`n" | Where-Object { $_ -match "^data:\s*" }
    if ($lines) {
        $lastDataLine = ($lines | Select-Object -Last 1) -replace "^data:\s*", ""
        return $lastDataLine | ConvertFrom-Json
    }

    return $content | ConvertFrom-Json
}

Write-LogMessage "Testing AutoDocJson MCP at $($baseUrl)" -Level INFO

# Step 1: Initialize
Write-LogMessage "Step 1: MCP Initialize" -Level INFO
$initResult = Send-McpRequest -Method "initialize" -Params @{
    protocolVersion = "2025-03-26"
    capabilities    = @{}
    clientInfo      = @{ name = "test-client"; version = "1.0" }
}
Write-LogMessage "  Server: $($initResult.result.serverInfo.name) v$($initResult.result.serverInfo.version)" -Level INFO
Write-LogMessage "  Session: $($script:sessionId)" -Level INFO

# Step 2: List tools
Write-LogMessage "Step 2: List tools" -Level INFO
$toolsResult = Send-McpRequest -Method "tools/list"
$tools = $toolsResult.result.tools
Write-LogMessage "  Found $($tools.Count) tool(s):" -Level INFO
foreach ($tool in $tools) {
    Write-LogMessage "    - $($tool.name): $($tool.description)" -Level INFO
}

# Step 3: Call search_documents (fast — no full file scan)
Write-LogMessage "Step 3: Call search_documents" -Level INFO
$searchResult = Send-McpRequest -Method "tools/call" -Params @{
    name      = "search_documents"
    arguments = @{ query = "batch"; types = "BAT" }
}
$searchContent = $searchResult.result.content[0].text | ConvertFrom-Json
Write-LogMessage "  Results: $($searchContent.resultCount) match(es) for 'batch' in BAT" -Level INFO

# Step 4: Call get_document (use first search result)
if ($searchContent.results -and $searchContent.results.Count -gt 0) {
    $testFile = $searchContent.results[0].JsonFile
    Write-LogMessage "Step 4: Call get_document ($($testFile))" -Level INFO
    $getResult = Send-McpRequest -Method "tools/call" -Params @{
        name      = "get_document"
        arguments = @{ fileName = $testFile }
    }
    $getContent = $getResult.result.content[0].text | ConvertFrom-Json
    if ($getContent.document) {
        Write-LogMessage "  Got document with $($getContent.availableDiagrams.Count) diagram(s), renderer=$($getContent.recommendedRenderer)" -Level INFO
    } else {
        Write-LogMessage "  Document retrieved (keys: $($getContent.PSObject.Properties.Name -join ', '))" -Level INFO
    }
} else {
    Write-LogMessage "Step 4: Skipped (no search results for get_document)" -Level WARN
}

# Step 5: Call list_documents (filtered by BAT to keep response small)
Write-LogMessage "Step 5: Call list_documents (BAT only)" -Level INFO
$listResult = Send-McpRequest -Method "tools/call" -Params @{
    name      = "list_documents"
    arguments = @{ fileType = "BAT" }
}
$listContent = $listResult.result.content[0].text | ConvertFrom-Json
Write-LogMessage "  Result: $($listContent.count) BAT document(s)" -Level INFO

$result = [PSCustomObject]@{
    Script  = $MyInvocation.MyCommand.Name
    Status  = "OK"
    Message = "All AutoDoc MCP tests passed"
}
Write-LogMessage "RESULT: $($result.Status) - $($result.Message)" -Level INFO
Write-Output $result
