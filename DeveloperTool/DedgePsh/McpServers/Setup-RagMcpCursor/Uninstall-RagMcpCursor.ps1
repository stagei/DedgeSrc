<#
.SYNOPSIS
    Remove RAG MCP servers from Cursor's mcp.json and clean up the proxy.
.DESCRIPTION
    Restores mcp.json from the pre-rag backup if available.
    Removes the rag-proxy folder (venv + proxy script).
    Also removes legacy RAG keys (db2-docs, visual-cobol-docs, Dedge-code).
.PARAMETER KeepProxy
    Do not delete the rag-proxy folder.
.EXAMPLE
    pwsh.exe -NoProfile -File Uninstall-RagMcpCursor.ps1
#>
[CmdletBinding()]
param(
    [switch]$KeepProxy
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

$mcpJson   = Join-Path $env:USERPROFILE '.cursor\mcp.json'
$mcpBackup = Join-Path $env:USERPROFILE '.cursor\mcp.json.pre-rag-backup'
$proxyDir  = Join-Path $env:USERPROFILE '.cursor\rag-proxy'

$legacyNames = @('db2-docs', 'visual-cobol-docs', 'Dedge-code')

if (Test-Path -LiteralPath $mcpBackup) {
    Write-LogMessage "Restoring mcp.json from pre-rag backup..." -Level INFO
    Copy-Item -LiteralPath $mcpBackup -Destination $mcpJson -Force
    Remove-Item -LiteralPath $mcpBackup -Force
    Write-LogMessage "Restored mcp.json from backup." -Level INFO
} elseif (Test-Path -LiteralPath $mcpJson) {
    Write-LogMessage "No backup found. Removing RAG entries from mcp.json manually..." -Level INFO
    $config = Get-Content -LiteralPath $mcpJson -Raw | ConvertFrom-Json
    $ragKeys = @($config.mcpServers.PSObject.Properties | Where-Object {
        $_.Value.args -and ($_.Value.args -match 'server_mcp_proxy')
    } | ForEach-Object { $_.Name })
    $allRemove = @($ragKeys) + $legacyNames | Select-Object -Unique

    $newServers = [ordered]@{}
    foreach ($prop in $config.mcpServers.PSObject.Properties) {
        if ($prop.Name -notin $allRemove) {
            $newServers[$prop.Name] = $prop.Value
        }
    }
    $config = @{ mcpServers = $newServers }
    $config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $mcpJson -Encoding utf8
    Write-LogMessage "Removed RAG entries: $($allRemove -join ', ')" -Level INFO
} else {
    Write-LogMessage "mcp.json not found. Nothing to remove." -Level WARN
}

if (-not $KeepProxy -and (Test-Path -LiteralPath $proxyDir)) {
    try {
        Remove-Item -LiteralPath $proxyDir -Recurse -Force
        Write-LogMessage "Removed rag-proxy folder." -Level INFO
    }
    catch {
        Write-LogMessage "Could not fully remove rag-proxy folder (files may be locked): $($_.Exception.Message)" -Level WARN
        Write-LogMessage "Close Cursor/Python processes and retry, or delete manually: $($proxyDir)" -Level WARN
    }
}

Write-LogMessage "Uninstall complete. Restart Cursor." -Level INFO
