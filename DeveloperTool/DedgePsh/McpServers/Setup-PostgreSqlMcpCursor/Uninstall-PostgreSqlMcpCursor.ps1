<#
.SYNOPSIS
    Remove the postgresql-query MCP server from Cursor's mcp.json and optionally clean up node_modules.
.PARAMETER CleanNodeModules
    Also remove node_modules from the server directory.
.EXAMPLE
    pwsh.exe -NoProfile -File Uninstall-PostgreSqlMcpCursor.ps1
.EXAMPLE
    pwsh.exe -NoProfile -File Uninstall-PostgreSqlMcpCursor.ps1 -CleanNodeModules
#>
[CmdletBinding()]
param(
    [switch]$CleanNodeModules
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

$mcpJsonPath = Join-Path $env:USERPROFILE '.cursor\mcp.json'
$serverKey = 'postgresql-query'

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

if ($CleanNodeModules) {
    $nodeModules = Join-Path $PSScriptRoot 'node_modules'
    if (Test-Path -LiteralPath $nodeModules) {
        Remove-Item -LiteralPath $nodeModules -Recurse -Force
        Write-LogMessage "Removed node_modules from $($PSScriptRoot)" -Level INFO
    }
}
