<#
.SYNOPSIS
    Remove the db2-query MCP server from Cursor's mcp.json.
.EXAMPLE
    pwsh.exe -NoProfile -File Uninstall-Db2QueryMcpCursor.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

$mcpJsonPath = Join-Path $env:USERPROFILE '.cursor\mcp.json'
$serverKey = 'db2-query'

Write-LogMessage "Removing '$($serverKey)' from Cursor mcp.json..." -Level INFO

if (-not (Test-Path -LiteralPath $mcpJsonPath)) {
    Write-LogMessage "mcp.json not found at $($mcpJsonPath). Nothing to remove." -Level WARN
    exit 0
}

$config = Get-Content -LiteralPath $mcpJsonPath -Raw | ConvertFrom-Json
if ($config.mcpServers.PSObject.Properties.Name -contains $serverKey) {
    $newServers = [ordered]@{}
    foreach ($prop in $config.mcpServers.PSObject.Properties) {
        if ($prop.Name -ne $serverKey) {
            $newServers[$prop.Name] = $prop.Value
        }
    }
    $config = @{ mcpServers = $newServers }
    $config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $mcpJsonPath -Encoding utf8
    Write-LogMessage "Removed '$($serverKey)'. Restart Cursor." -Level INFO
} else {
    Write-LogMessage "'$($serverKey)' not found in mcp.json. Nothing to remove." -Level WARN
}
