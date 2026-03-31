<#
.SYNOPSIS
    Test the PostgreSQL MCP server by launching it and sending JSON-RPC requests via stdin/stdout.

.DESCRIPTION
    Starts the Node.js MCP server as a child process, sends initialize + tools/list +
    a test query, and validates the responses.

.PARAMETER DatabaseName
    Database to test with. Default: DedgeAuth

.PARAMETER Environment
    Environment to test. Default: TST

.PARAMETER PostgresUser
    PostgreSQL user. Default: postgres

.PARAMETER PostgresPassword
    PostgreSQL password. Default: postgres

.PARAMETER PostgresPort
    PostgreSQL port. Default: 8432

.EXAMPLE
    pwsh.exe -NoProfile -File Test-PostgreSqlMcpCursor.ps1

.EXAMPLE
    pwsh.exe -NoProfile -File Test-PostgreSqlMcpCursor.ps1 -DatabaseName GenericLogHandler -Environment TST
#>
[CmdletBinding()]
[System.Diagnostics.CodeAnalysis.SuppressMessage('Security', 'PSAvoidUsingPlainTextForPassword', Justification = 'psql PGPASSWORD requires plain string.')]
param(
    [string]$DatabaseName     = 'DedgeAuth',
    [string]$Environment      = 'TST',
    [string]$PostgresUser     = 'postgres',
    [string]$PostgresPassword = 'postgres',
    [int]$PostgresPort        = 8432
)

Import-Module GlobalFunctions -Force
$ErrorActionPreference = 'Stop'

$serverScript = Join-Path $PSScriptRoot 'postgresql-mcp-server.mjs'
$nodeModules  = Join-Path $PSScriptRoot 'node_modules'

Write-LogMessage "Testing PostgreSQL MCP Server" -Level INFO

if (-not (Test-Path $nodeModules)) {
    Write-LogMessage "node_modules missing — running npm install..." -Level INFO
    Push-Location $PSScriptRoot
    npm install --production 2>&1 | Out-Null
    Pop-Location
}

Write-LogMessage "1. Starting MCP server process..." -Level INFO

$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.FileName = 'node'
$psi.Arguments = "`"$serverScript`""
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$psi.Environment['PG_USER']     = $PostgresUser
$psi.Environment['PG_PASSWORD'] = $PostgresPassword
$psi.Environment['PG_PORT']     = [string]$PostgresPort

$proc = [System.Diagnostics.Process]::Start($psi)
Start-Sleep -Milliseconds 1500

if ($proc.HasExited) {
    $stderr = $proc.StandardError.ReadToEnd()
    Write-LogMessage "MCP server failed to start: $($stderr)" -Level ERROR
    exit 1
}
Write-LogMessage "MCP server started (PID: $($proc.Id))" -Level INFO

function Send-McpRequest {
    param([object]$Body)
    $json = $Body | ConvertTo-Json -Depth 6 -Compress
    $proc.StandardInput.WriteLine($json)
    $proc.StandardInput.Flush()
    Start-Sleep -Milliseconds 500
    $line = $proc.StandardOutput.ReadLine()
    if ($line) {
        return $line | ConvertFrom-Json
    }
    return $null
}

$script:testPassed = $null
try {
    Write-LogMessage "2. Sending initialize request..." -Level INFO
    $initResult = Send-McpRequest -Body @{
        jsonrpc = '2.0'
        id      = 1
        method  = 'initialize'
        params  = @{
            protocolVersion = '2024-11-05'
            capabilities    = @{}
            clientInfo      = @{ name = 'test-script'; version = '1.0' }
        }
    }
    if ($initResult.result) {
        Write-LogMessage "Server: $($initResult.result.serverInfo.name) v$($initResult.result.serverInfo.version)" -Level INFO
    }
    else {
        Write-LogMessage "Initialize response: $($initResult | ConvertTo-Json -Depth 4 -Compress)" -Level WARN
    }

    Write-LogMessage "3. Listing tools..." -Level INFO
    $listResult = Send-McpRequest -Body @{
        jsonrpc = '2.0'
        id      = 2
        method  = 'tools/list'
        params  = @{}
    }
    if ($listResult.result.tools) {
        foreach ($tool in $listResult.result.tools) {
            Write-LogMessage "   Tool: $($tool.name) — $($tool.description.Substring(0, [Math]::Min(80, $tool.description.Length)))..." -Level INFO
        }
    }

    Write-LogMessage "4. Listing databases..." -Level INFO
    $dbListResult = Send-McpRequest -Body @{
        jsonrpc = '2.0'
        id      = 3
        method  = 'tools/call'
        params  = @{
            name      = 'list_postgresql_databases'
            arguments = @{}
        }
    }
    if ($dbListResult.result.content) {
        $dbData = ($dbListResult.result.content | Where-Object { $_.type -eq 'text' } | Select-Object -First 1).text | ConvertFrom-Json
        Write-LogMessage "   Available databases: $($dbData.Count)" -Level INFO
        foreach ($db in $dbData) {
            Write-LogMessage "   - $($db.database) ($($db.environment)) on $($db.server):$($db.port)" -Level INFO
        }
        if ($dbData.Count -eq 0) {
            Write-LogMessage "   No databases configured — no PostgreSQL entries in DatabasesV2.json" -Level ERROR
            $script:testPassed = $false
        }
    }

    Write-LogMessage "5. Executing test query on $($DatabaseName) ($($Environment))..." -Level INFO
    $queryResult = Send-McpRequest -Body @{
        jsonrpc = '2.0'
        id      = 4
        method  = 'tools/call'
        params  = @{
            name      = 'query_postgresql'
            arguments = @{
                databaseName = $DatabaseName
                environment  = $Environment
                query        = 'SELECT current_database() AS db, current_user AS usr, version() AS ver'
            }
        }
    }
    if ($queryResult.result.content) {
        $content = ($queryResult.result.content | Where-Object { $_.type -eq 'text' } | Select-Object -First 1).text | ConvertFrom-Json
        if ($content.error) {
            Write-LogMessage "   Query error: $($content.error)" -Level ERROR
            $script:testPassed = $false
        }
        else {
            Write-LogMessage "   Database: $($content.database)" -Level INFO
            Write-LogMessage "   Server: $($content.server)" -Level INFO
            Write-LogMessage "   Rows: $($content.rowCount)" -Level INFO
            if ($content.rows.Count -gt 0) {
                Write-LogMessage "   Result: db=$($content.rows[0].db), user=$($content.rows[0].usr)" -Level INFO
                $ver = $content.rows[0].ver
                if ($ver.Length -gt 60) { $ver = $ver.Substring(0, 60) + '...' }
                Write-LogMessage "   Version: $($ver)" -Level INFO
            }
        }
    }
    elseif ($queryResult.error) {
        Write-LogMessage "   Query failed: $($queryResult.error.message)" -Level ERROR
        $script:testPassed = $false
    }

    Write-LogMessage "6. Testing read-only enforcement..." -Level INFO
    $writeResult = Send-McpRequest -Body @{
        jsonrpc = '2.0'
        id      = 5
        method  = 'tools/call'
        params  = @{
            name      = 'query_postgresql'
            arguments = @{
                databaseName = $DatabaseName
                environment  = $Environment
                query        = 'DELETE FROM pg_tables'
            }
        }
    }
    if ($writeResult.result.content) {
        $writeContent = ($writeResult.result.content | Where-Object { $_.type -eq 'text' } | Select-Object -First 1).text | ConvertFrom-Json
        if ($writeContent.error -match 'read-only') {
            Write-LogMessage "   Read-only enforcement: PASSED (write query blocked)" -Level INFO
        }
        else {
            Write-LogMessage "   Read-only enforcement: FAILED — $($writeContent | ConvertTo-Json -Compress)" -Level ERROR
        }
    }

    if ($script:testPassed -ne $false) { $script:testPassed = $true }
    Write-LogMessage "Test complete." -Level INFO
}
finally {
    if (-not $proc.HasExited) {
        $proc.Kill()
        $null = $proc.WaitForExit(5000)
    }
    $proc.Dispose()
}

$result = [PSCustomObject]@{
    Script  = $MyInvocation.MyCommand.Name
    Status  = if ($script:testPassed) { "OK" } else { "FAIL" }
    Message = if ($script:testPassed) { "All PostgreSQL MCP tests passed" } else { "PostgreSQL MCP tests failed" }
}
Write-LogMessage "RESULT: $($result.Status) - $($result.Message)" -Level INFO
Write-Output $result
