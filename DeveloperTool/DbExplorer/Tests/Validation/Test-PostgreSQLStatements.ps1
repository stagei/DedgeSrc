# Test all statements in postgresql_18_sql_statements.json by alias.
# Logs alias + actual SQL + tag so Cursor AI can find and verify/correct each statement.
# With -Execute: runs each statement via CLI; exit 0 (including 0 rows) = PASS, SQL error = FAIL.
# Usage: .\Tests\Validation\Test-PostgreSQLStatements.ps1 [-Profile PostgreSQL_Local] [-Provider PostgreSQL] [-Execute]
# Cursor AI: search log for "CURSOR_VERIFY_POSTGRESQL_STATEMENT" to find each statement for verification.

param(
    [string]$Profile,
    [ValidateSet('', 'DB2', 'PostgreSQL')]
    [string]$Provider = 'PostgreSQL',
    [switch]$Execute
)

$ErrorActionPreference = "Continue"
$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$testsRoot = Join-Path $projectRoot "Tests"
$configPath = Join-Path $projectRoot "ConfigFiles"
$jsonFile = Join-Path $configPath "postgresql_18_sql_statements.json"
$outputDir = Join-Path $projectRoot "CLI_Test_Output"
$exePath = Join-Path $projectRoot "bin\Debug\net10.0-windows\DbExplorer.exe"

if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir -Force | Out-Null }

# Load TestLogger and TestConfig so we write to suite log when run from Run-TestSuite
. (Join-Path $testsRoot "TestLogger.ps1") -LogDir $outputDir -LogPrefix "pg_statements"
Start-TestLog -Title "PostgreSQL statements verification (alias + SQL logged for Cursor AI)" -LogDir $outputDir -LogPrefix "pg_statements" | Out-Null
. (Join-Path $testsRoot "TestConfig.ps1") -Profile $Profile -Provider $Provider
$Profile = Get-WdeTestProfile
$Provider = Get-WdeTestProvider

if ($Provider -ne 'PostgreSQL') {
    Write-TestLog "This test is for PostgreSQL statements only. Provider=$Provider. Exiting." -Level WARN
    exit 0
}

if (-not (Test-Path $jsonFile)) {
    Write-TestLog "SQL statements file not found: $jsonFile" -Level FAIL
    exit 1
}

# Substitute ? placeholders in order: 1st='public', 2nd='dummy', 3rd='p' (prokind). Safe for empty DB; 0 rows = OK.
# PowerShell -replace has no "replace once" third arg; replace one ? at a time by position.
function Get-ExecutableSql {
    param([string]$Sql, [array]$ParamNames)
    $s = $Sql
    $values = @('public', 'dummy', 'p')
    $i = 0
    while (($pos = $s.IndexOf('?')) -ge 0) {
        $val = if ($i -lt $values.Length) { $values[$i] } else { 'dummy' }
        $s = $s.Substring(0, $pos) + "'$val'" + $s.Substring($pos + 1)
        $i++
    }
    return $s
}

$json = Get-Content $jsonFile -Raw -Encoding utf8 | ConvertFrom-Json
$statements = @($json.statements.PSObject.Properties)
$count = $statements.Count

# Dedicated verification log: one file with all [CURSOR_VERIFY_POSTGRESQL_STATEMENT] blocks for agent to grep
$verifyTimestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$verifyLogPath = Join-Path $outputDir "postgresql_statements_verify_$verifyTimestamp.log"
$header = @"
# PostgreSQL 18 SQL Statements Verification Log
# Cursor AI: search this file for "CURSOR_VERIFY_POSTGRESQL_STATEMENT" to find each statement.
# Use alias to locate the statement in ConfigFiles/postgresql_18_sql_statements.json and verify or correct the SQL.
# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# File: $jsonFile
# Total statements: $count

"@
$header | Out-File -FilePath $verifyLogPath -Encoding utf8

Write-TestLog "Verification log (for Cursor AI): $verifyLogPath" -Level INFO
Write-TestLog "Total statements to log: $count" -Level INFO
if ($Execute) { Write-TestLog "Execute mode: running each statement via CLI (0 rows = OK, SQL error = FAIL)." -Level INFO }

$script:executeFailed = $false
$n = 0
foreach ($stmt in $statements) {
    $n++
    $alias = $stmt.Name
    $obj = $stmt.Value
    $sql = if ($obj.sql) { $obj.sql.ToString().Trim() } else { '' }
    $desc = if ($obj.description) { $obj.description.ToString().Trim() } else { '' }
    $params = if ($obj.parameters -and $obj.parameters.Count -gt 0) { ($obj.parameters | ForEach-Object { $_.ToString() }) -join ',' } else { '' }

    # Block for dedicated verification log (tagged for Cursor AI)
    $block = @"
[CURSOR_VERIFY_POSTGRESQL_STATEMENT] alias=$alias
description=$desc
parameters=$params
sql=$sql
---
"@
    Add-Content -Path $verifyLogPath -Value $block -Encoding utf8 -NoNewline:$false

    # Also write one line to main test log with tag so suite log is searchable
    Write-TestLog "[CURSOR_VERIFY_POSTGRESQL_STATEMENT] alias=$alias | sql_len=$($sql.Length)" -Level DEBUG -NoConsole
    if ($n % 10 -eq 0 -or $n -eq $count) {
        Write-TestLog "Logged $n / $count statements (alias + sql in $verifyLogPath)" -Level INFO
    }

    # -Execute: run statement via CLI; exit 0 (including 0 rows) = PASS, SQL error = FAIL
    if ($Execute) {
        $paramList = if ($obj.parameters -and $obj.parameters.Count -gt 0) { @($obj.parameters | ForEach-Object { $_.ToString() }) } else { @() }
        $execSql = Get-ExecutableSql -Sql $sql -ParamNames $paramList
        # Placeholder statements (e.g. ExecuteUserQuery with {user_sql}) are not runnable; use SELECT 1 for test
        if ($execSql -match '\{user_sql\}') { $execSql = 'SELECT 1' }
        $tempOut = Join-Path $outputDir "stmt_$n`_$alias.json"
        $runProfile = if ($Profile) { $Profile } else { 'PostgreSQL_Local' }
        if (-not (Test-Path $exePath)) {
            Write-TestLog "Exe not found: $exePath (skip execute)" -Level FAIL
            $script:executeFailed = $true
            continue
        }
        $psi = New-Object System.Diagnostics.ProcessStartInfo -Property @{
            FileName = $exePath
            Arguments = "--profile $runProfile -Outfile `"$tempOut`" -Sql `"$($execSql -replace '"', '\"')`""
            UseShellExecute = $false
            RedirectStandardOutput = $true
            RedirectStandardError = $true
            CreateNoWindow = $true
        }
        $proc = [System.Diagnostics.Process]::Start($psi)
        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()
        $exitCode = $proc.ExitCode
        $cliResult = $stdout, $stderr | Where-Object { $_ }
        if ($exitCode -eq 0) {
            $rows = if ($stdout -match 'Query returned (\d+) rows') { $Matches[1] } else { '?' }
            Write-TestLog "[CURSOR_VERIFY_POSTGRESQL_STATEMENT] alias=$alias executed OK (rows=$rows)" -Level PASS
        } else {
            Write-TestLog "[CURSOR_VERIFY_POSTGRESQL_STATEMENT] alias=$alias SQL error (exit=$exitCode)" -Level FAIL
            $errLines = ($cliResult | Out-String) -split "`n" | Where-Object { $_ -match 'ERROR|Exception|Failed' }
            if ($errLines) { Write-TestLog ($errLines | Select-Object -First 3 | Out-String) -Level ERROR }
            $script:executeFailed = $true
        }
        if (Test-Path $tempOut) { Remove-Item $tempOut -Force -ErrorAction SilentlyContinue }
    }
}

Write-TestLog "All $count statements written to verification log." -Level PASS
Write-TestLog "Cursor AI: grep 'CURSOR_VERIFY_POSTGRESQL_STATEMENT' in $verifyLogPath to verify or correct each statement in ConfigFiles/postgresql_18_sql_statements.json" -Level INFO
if ($Execute -and $script:executeFailed) {
    Write-TestLog "One or more statements failed (SQL errors)." -Level FAIL
    exit 1
}
exit 0
