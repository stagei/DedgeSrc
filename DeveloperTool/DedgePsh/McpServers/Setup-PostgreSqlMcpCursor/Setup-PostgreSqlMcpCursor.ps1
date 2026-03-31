<#
.SYNOPSIS
    Register the local PostgreSQL MCP server in Cursor's mcp.json.

.DESCRIPTION
    Adds or updates the 'postgresql-query' entry in ~/.cursor/mcp.json to point
    at the Node.js stdio-based MCP server. Also runs npm install if node_modules
    is missing.

    Restart Cursor after running this script.

.PARAMETER PostgresUser
    PostgreSQL user. Default: postgres

.PARAMETER PostgresPassword
    PostgreSQL password. Default: postgres

.PARAMETER PostgresPort
    PostgreSQL port. Default: 8432

.PARAMETER ServerDir
    Path to the MCP server directory. Default: auto-detected from script location.

.EXAMPLE
    pwsh.exe -NoProfile -File Setup-PostgreSqlMcpCursor.ps1

.EXAMPLE
    pwsh.exe -NoProfile -File Setup-PostgreSqlMcpCursor.ps1 -PostgresPort 5432
#>
[CmdletBinding()]
[System.Diagnostics.CodeAnalysis.SuppressMessage('Security', 'PSAvoidUsingPlainTextForPassword', Justification = 'MCP server config requires plain connection params.')]
param(
    [string]$PostgresUser     = 'postgres',
    [string]$PostgresPassword = 'postgres',
    [int]$PostgresPort        = 8432,
    [string]$ServerDir        = $null
)

Import-Module GlobalFunctions -Force
$ErrorActionPreference = 'Stop'

if (-not $ServerDir) {
    $ServerDir = $PSScriptRoot
}

$serverScript = Join-Path $ServerDir 'postgresql-mcp-server.mjs'
$nodeModules  = Join-Path $ServerDir 'node_modules'

Write-LogMessage "Registering postgresql-query MCP server" -Level INFO
Write-LogMessage "Server dir: $($ServerDir)" -Level INFO

if (-not (Test-Path $serverScript -PathType Leaf)) {
    Write-LogMessage "MCP server script not found: $($serverScript)" -Level ERROR
    exit 1
}

$nodeExe = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeExe) {
    Write-LogMessage "Node.js not found. Install Node.js and try again." -Level ERROR
    exit 1
}
Write-LogMessage "Node.js: $($nodeExe.Source) ($(node --version))" -Level INFO

if (-not (Test-Path $nodeModules)) {
    Write-LogMessage "Installing npm dependencies..." -Level INFO
    Push-Location $ServerDir
    try {
        npm install --production 2>&1 | ForEach-Object { Write-LogMessage "npm: $_" -Level DEBUG }
        if ($LASTEXITCODE -ne 0) {
            Write-LogMessage "npm install failed." -Level ERROR
            exit 1
        }
        Write-LogMessage "npm install completed." -Level INFO
    }
    finally {
        Pop-Location
    }
}
else {
    Write-LogMessage "node_modules already present." -Level INFO
}

$mcpJsonPath = Join-Path $env:USERPROFILE '.cursor\mcp.json'
$cursorDir = Split-Path -Parent $mcpJsonPath
if (-not (Test-Path -LiteralPath $cursorDir)) {
    New-Item -ItemType Directory -Path $cursorDir -Force | Out-Null
}

$pgServerEntry = @{
    command = 'node'
    args    = @($serverScript)
    env     = @{
        PG_USER     = $PostgresUser
        PG_PASSWORD = $PostgresPassword
        PG_PORT     = [string]$PostgresPort
    }
}

$mcpConfig = @{ mcpServers = @{} }

if (Test-Path -LiteralPath $mcpJsonPath) {
    $existing = Get-Content -LiteralPath $mcpJsonPath -Raw | ConvertFrom-Json
    if ($existing.mcpServers) {
        $existing.mcpServers.PSObject.Properties | ForEach-Object {
            $mcpConfig.mcpServers[$_.Name] = $_.Value
        }
    }
}

$mcpConfig.mcpServers['postgresql-query'] = $pgServerEntry
$mcpConfig | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $mcpJsonPath -Encoding utf8

Write-LogMessage "Done. Restart Cursor to pick up the postgresql-query MCP server." -Level INFO
Write-LogMessage "Config: $($mcpJsonPath)" -Level INFO
Write-LogMessage "Server: $($serverScript)" -Level INFO
Write-LogMessage "PostgreSQL port: $($PostgresPort)" -Level INFO

$result = [PSCustomObject]@{
    Script  = $MyInvocation.MyCommand.Name
    Status  = "OK"
    Message = "Registered postgresql-query in mcp.json"
}
Write-LogMessage "RESULT: $($result.Status) - $($result.Message)" -Level INFO
Write-Output $result
