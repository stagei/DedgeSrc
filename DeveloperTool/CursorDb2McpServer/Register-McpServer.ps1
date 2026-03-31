<#
.SYNOPSIS
    Register the remote CursorDb2McpServer MCP endpoint in Cursor's mcp.json.

.DESCRIPTION
    Adds or updates the 'db2-query' entry in ~/.cursor/mcp.json to point at the
    Streamable HTTP endpoint on the app server. No local build or publish is needed;
    the server runs as an IIS virtual app on dedge-server under Default Web Site.

    Restart Cursor after running this script.

.PARAMETER ServerHost
    Hostname of the server running CursorDb2McpServer. Default: dedge-server

.EXAMPLE
    pwsh.exe -File Register-McpServer.ps1
.EXAMPLE
    pwsh.exe -File Register-McpServer.ps1 -ServerHost "my-server"
#>
[CmdletBinding()]
param(
    [string]$ServerHost = "dedge-server"
)

$ErrorActionPreference = 'Stop'

$mcpJsonPath = Join-Path $env:USERPROFILE '.cursor\mcp.json'
$mcpEndpoint = "http://$($ServerHost)/CursorDb2McpServer/"

Write-Host "Registering db2-query MCP server..."
Write-Host "  Endpoint: $mcpEndpoint"

$cursorDir = Split-Path -Parent $mcpJsonPath
if (-not (Test-Path -LiteralPath $cursorDir)) {
    New-Item -ItemType Directory -Path $cursorDir -Force | Out-Null
}

$db2ServerEntry = @{
    url = $mcpEndpoint
}

$mcpConfig = @{ mcpServers = @{} }

if (Test-Path -LiteralPath $mcpJsonPath) {
    $existing = Get-Content -LiteralPath $mcpJsonPath -Raw | ConvertFrom-Json
    if ($existing.mcpServers) {
        $mcpConfig.mcpServers = @{}
        $existing.mcpServers.PSObject.Properties | ForEach-Object {
            $mcpConfig.mcpServers[$_.Name] = $_.Value
        }
    }
}

$mcpConfig.mcpServers['db2-query'] = $db2ServerEntry

$mcpConfig | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $mcpJsonPath -Encoding utf8

Write-Host ""
Write-Host "Done. Restart Cursor to pick up the db2-query MCP server."
Write-Host "  Config: $mcpJsonPath"
Write-Host "  Endpoint: $mcpEndpoint"
