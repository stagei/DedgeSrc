<#
.SYNOPSIS
    Register the AutoDocJson MCP endpoint in Cursor's mcp.json.

.DESCRIPTION
    Adds or updates the 'autodoc-query' entry in ~/.cursor/mcp.json to point at the
    Streamable HTTP endpoint on the app server. The MCP endpoint runs inside the
    existing AutoDocJson IIS virtual application — no separate deploy needed.

    Restart Cursor after running this script.

.PARAMETER ServerHost
    Hostname of the server running AutoDocJson. Default: dedge-server

.EXAMPLE
    pwsh.exe -NoProfile -File Setup-AutoDocMcpCursor.ps1
.EXAMPLE
    pwsh.exe -NoProfile -File Setup-AutoDocMcpCursor.ps1 -ServerHost "my-server"
#>
[CmdletBinding()]
param(
    [string]$ServerHost = "dedge-server"
)

$ErrorActionPreference = 'Stop'

Import-Module GlobalFunctions -Force

$mcpJsonPath = Join-Path $env:USERPROFILE '.cursor\mcp.json'
$mcpEndpoint = "http://$($ServerHost)/AutoDocJson/mcp"

Write-LogMessage "Registering autodoc-query MCP server..." -Level INFO
Write-LogMessage "  Endpoint: $($mcpEndpoint)" -Level INFO

$cursorDir = Split-Path -Parent $mcpJsonPath
if (-not (Test-Path -LiteralPath $cursorDir)) {
    New-Item -ItemType Directory -Path $cursorDir -Force | Out-Null
}

$autoDocServerEntry = @{
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

$mcpConfig.mcpServers['autodoc-query'] = $autoDocServerEntry

$mcpConfig | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $mcpJsonPath -Encoding utf8

Write-LogMessage "Registration complete." -Level INFO
Write-LogMessage "  Config: $($mcpJsonPath)" -Level INFO
Write-LogMessage "  Endpoint: $($mcpEndpoint)" -Level INFO
Write-LogMessage "Restart Cursor to pick up the autodoc-query MCP server." -Level INFO

$result = [PSCustomObject]@{
    Script  = $MyInvocation.MyCommand.Name
    Status  = "OK"
    Message = "Registered autodoc-query in mcp.json"
}
Write-LogMessage "RESULT: $($result.Status) - $($result.Message)" -Level INFO
Write-Output $result
