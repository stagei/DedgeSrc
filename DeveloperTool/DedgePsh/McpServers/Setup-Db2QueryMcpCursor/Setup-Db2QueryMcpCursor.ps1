<#
.SYNOPSIS
    Register the remote CursorDb2McpServer MCP endpoint in Cursor's mcp.json.

.DESCRIPTION
    Adds or updates the 'db2-query' entry in ~/.cursor/mcp.json to point at the
    Streamable HTTP endpoint on the app server.

    Restart Cursor after running this script.

.PARAMETER ServerHost
    Hostname of the server running CursorDb2McpServer. Default: dedge-server

.EXAMPLE
    pwsh.exe -NoProfile -File Setup-Db2QueryMcpCursor.ps1
#>
[CmdletBinding()]
param(
    [string]$ServerHost = 'dedge-server'
)

Import-Module GlobalFunctions -Force
$ErrorActionPreference = 'Stop'

$mcpJsonPath = Join-Path $env:USERPROFILE '.cursor\mcp.json'
$mcpEndpoint = "http://$($ServerHost)/CursorDb2McpServer/"

Write-LogMessage "Registering db2-query MCP server" -Level INFO
Write-LogMessage "Endpoint: $($mcpEndpoint)" -Level INFO

$cursorDir = Split-Path -Parent $mcpJsonPath
if (-not (Test-Path -LiteralPath $cursorDir)) {
    New-Item -ItemType Directory -Path $cursorDir -Force | Out-Null
}

$db2ServerEntry = @{ url = $mcpEndpoint }
$mcpConfig = @{ mcpServers = @{} }

if (Test-Path -LiteralPath $mcpJsonPath) {
    $existing = Get-Content -LiteralPath $mcpJsonPath -Raw | ConvertFrom-Json
    if ($existing.mcpServers) {
        $existing.mcpServers.PSObject.Properties | ForEach-Object {
            $mcpConfig.mcpServers[$_.Name] = $_.Value
        }
    }
}

$mcpConfig.mcpServers['db2-query'] = $db2ServerEntry
$mcpConfig | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $mcpJsonPath -Encoding utf8

Write-LogMessage "Done. Restart Cursor to pick up the db2-query MCP server." -Level INFO
Write-LogMessage "Config: $($mcpJsonPath)" -Level INFO
Write-LogMessage "Endpoint: $($mcpEndpoint)" -Level INFO

$result = [PSCustomObject]@{
    Script  = $MyInvocation.MyCommand.Name
    Status  = "OK"
    Message = "Registered db2-query in mcp.json"
}
Write-LogMessage "RESULT: $($result.Status) - $($result.Message)" -Level INFO
Write-Output $result
