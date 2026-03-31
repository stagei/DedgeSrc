<#
.SYNOPSIS
    Verifies DB2 connectivity from local machine via CLI and JDBC after shadow pipeline.

.DESCRIPTION
    For each config.*.json in the script folder (or a single -ConfigName):
    1. Builds a work object via Get-DefaultWorkObjects to get the control SQL
    2. Auto-detects the Alias access point from DatabasesV2.json
    3. Tests CLI connection via db2cmd (Kerberos passthrough)
    4. Tests JDBC connection via Db2JdbcTest.py (db2nt/ntdb2)
    5. Reports results and sends SMS

.PARAMETER ConfigName
    Test a single config file (e.g. "inltst" for config.inltst.json).
    If omitted, tests all config.*.json files found.

.PARAMETER AliasName
    Override the DB2 alias to test. If not provided, auto-detected from
    DatabasesV2.json by looking up SourceDatabase and finding the Alias AccessPoint.

.PARAMETER SendSms
    Send SMS notification with result.

.PARAMETER SkipJdbc
    Skip the JDBC connection test.

.EXAMPLE
    .\Verify-LocalDb2Connection.ps1 -SendSms
    .\Verify-LocalDb2Connection.ps1 -ConfigName inltst -SendSms
    .\Verify-LocalDb2Connection.ps1 -AliasName FKKTOTST
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigName,

    [Parameter(Mandatory = $false)]
    [string]$AliasName,

    [Parameter(Mandatory = $false)]
    [switch]$SendSms,

    [Parameter(Mandatory = $false)]
    [switch]$SkipJdbc,

    [Parameter(Mandatory = $false)]
    [string[]]$SmsNumbers = @("+4797188358")
)

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

function Test-SingleDatabase {
    param(
        [string]$SourceDatabase,
        [string]$Application,
        [string]$OverrideAlias,
        [switch]$TestJdbc,
        [switch]$Notify,
        [string[]]$NotifyNumbers
    )

    $results = @()
    $overallSuccess = $false
    $rowCount = "unknown"

    # Phase 0: Build work object and get control SQL from Db2-Handler
    Write-LogMessage "Phase 0: Building work object for $($SourceDatabase) to get control SQL" -Level INFO

    $workObj = Get-DefaultWorkObjects -DatabaseType PrimaryDb -DatabaseName $SourceDatabase -QuickMode -SkipDb2StateInfo
    if ($workObj -is [array]) { $workObj = $workObj[-1] }

    $workObj = Get-ControlSqlStatement -WorkObject $workObj -SelectCount -ForceGetControlSqlStatement
    if ($workObj -is [array]) { $workObj = $workObj[-1] }

    $controlTable = $workObj.TableToCheck
    $controlSql = $workObj.ControlSqlStatement
    if ([string]::IsNullOrEmpty($controlTable)) {
        Write-LogMessage "No control table found for application $($Application) / database $($SourceDatabase)" -Level ERROR
        return @{ Success = $false; Summary = "No control table for $($SourceDatabase)" }
    }
    Write-LogMessage "Control table: $($controlTable) (from Db2-Handler for app $($workObj.Application))" -Level INFO

    # Phase 0b: Resolve alias
    $testAlias = $OverrideAlias
    if ([string]::IsNullOrEmpty($testAlias)) {
        $aliasAp = $workObj.AliasAccessPoints | Where-Object { $_.CatalogName -eq $workObj.RemoteDatabaseName } | Select-Object -First 1
        if ($null -eq $aliasAp) {
            $aliasAp = $workObj.AliasAccessPoints | Select-Object -First 1
        }
        if ($null -ne $aliasAp) {
            $testAlias = $aliasAp.CatalogName
            Write-LogMessage "Auto-detected alias: $($testAlias) (port $($aliasAp.Port))" -Level INFO
        }
        else {
            $testAlias = $workObj.RemoteDatabaseName
            if ([string]::IsNullOrEmpty($testAlias)) { $testAlias = $SourceDatabase }
            Write-LogMessage "No alias access point found, using: $($testAlias)" -Level WARN
        }
    }

    # Phase 1: Check local catalog
    Write-LogMessage "Phase 1: Checking local DB2 catalog for $($testAlias)" -Level INFO

    $workFolder = Join-Path $env:TEMP "Db2-ShadowDatabase-Verify"
    New-Item -Path $workFolder -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

    $catalogCmds = @("db2 list db directory", "db2 terminate")
    $catalogOutput = Invoke-Db2ContentAsScript -Content $catalogCmds -ExecutionType BAT `
        -FileName (Join-Path $workFolder "VerifyCatalog_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors

    if ($catalogOutput -match $testAlias) {
        Write-LogMessage "Alias $($testAlias) found in local DB2 catalog" -Level INFO
        $results += "Catalog: OK"
    }
    else {
        Write-LogMessage "Alias $($testAlias) NOT found in local DB2 catalog" -Level WARN
        $results += "Catalog: MISSING"
    }

    # Phase 2: CLI connection test (Kerberos passthrough)
    Write-LogMessage "Phase 2: CLI connection to $($testAlias) (Kerberos passthrough)" -Level INFO

    $connectCmds = @("db2 connect to $($testAlias)")
    $connectCmds += "db2 `"SELECT COUNT(*) AS ROW_COUNT FROM $($controlTable)`""
    $connectCmds += "db2 connect reset"
    $connectCmds += "db2 terminate"

    $connectOutput = Invoke-Db2ContentAsScript -Content $connectCmds -ExecutionType BAT `
        -FileName (Join-Path $workFolder "VerifyCli_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors

    if ($connectOutput -match "(\d+)\s+post(?:\(er\))?\s+er\s+valgt") {
        $countMatch = [regex]::Match($connectOutput, "(\d+)\s+post(?:\(er\))?\s+er\s+valgt")
        $rowCount = $countMatch.Groups[1].Value
        Write-LogMessage "CLI OK (Kerberos): $($controlTable) = $($rowCount) rows" -Level INFO
        $results += "CLI: OK ($($rowCount) rows)"
        $overallSuccess = $true
    }
    elseif ($connectOutput -match "ROW_COUNT\s*\r?\n\s*-+\s*\r?\n\s*(\d+)") {
        $countMatch = [regex]::Match($connectOutput, "ROW_COUNT\s*\r?\n\s*-+\s*\r?\n\s*(\d+)")
        $rowCount = $countMatch.Groups[1].Value
        Write-LogMessage "CLI OK (Kerberos): $($controlTable) = $($rowCount) rows" -Level INFO
        $results += "CLI: OK ($($rowCount) rows)"
        $overallSuccess = $true
    }
    elseif ($connectOutput -match "SQL0551N|SQL0204N") {
        $err = if ($connectOutput -match "SQL0551N") { "SQL0551N (no SELECT auth)" } else { "SQL0204N (table not found)" }
        Write-LogMessage "CLI: $($err)" -Level WARN
        $results += "CLI: $($err)"
    }
    else {
        Write-LogMessage "CLI FAIL: connection or query error" -Level WARN
        $results += "CLI: FAIL"
    }

    # Phase 3: JDBC connection test (db2nt/ntdb2 credentials)
    if ($TestJdbc) {
        Write-LogMessage "Phase 3: JDBC connection test for $($testAlias)" -Level INFO

        $aliasAp = $workObj.AliasAccessPoints | Where-Object { $_.CatalogName -eq $testAlias } | Select-Object -First 1
        if ($null -eq $aliasAp) { $aliasAp = $workObj.AliasAccessPoints | Select-Object -First 1 }

        $jdbcHost = $workObj.ServerName
        $jdbcPort = if ($null -ne $aliasAp) { $aliasAp.Port } else { "50000" }
        $jdbcDb = $SourceDatabase

        $jdbcTestScript = Join-Path $PSScriptRoot "..\Db2-JdbcTest\Db2JdbcTest.py"
        if (-not (Test-Path $jdbcTestScript)) {
            Write-LogMessage "JDBC: Db2JdbcTest.py not found at $($jdbcTestScript), skipping" -Level WARN
            $results += "JDBC: SKIPPED (script not found)"
        }
        else {
            try {
                $jdbcResult = py -3 $jdbcTestScript $jdbcHost $jdbcPort $jdbcDb "db2nt" "ntdb2" $controlTable 2>&1
                $jdbcOutput = $jdbcResult -join "`n"

                if ($jdbcOutput -match "WORKING:.+") {
                    # Regex: capture row count from "SELECT COUNT(*) FROM <table> = <N>"
                    $jdbcRowMatch = [regex]::Match($jdbcOutput, "COUNT\(\*\)\s+FROM\s+\S+\s*=\s*(\d+)")
                    $jdbcRows = if ($jdbcRowMatch.Success) { $jdbcRowMatch.Groups[1].Value } else { "?" }
                    Write-LogMessage "JDBC OK: $($controlTable) = $($jdbcRows) rows" -Level INFO
                    $results += "JDBC: OK ($($jdbcRows) rows)"
                }
                elseif ($jdbcOutput -match "ALL security mechanisms FAILED") {
                    Write-LogMessage "JDBC FAIL: all security mechanisms failed" -Level WARN
                    $results += "JDBC: FAIL (all mechanisms)"
                }
                else {
                    Write-LogMessage "JDBC: unexpected output" -Level WARN
                    $results += "JDBC: UNKNOWN"
                }
            }
            catch {
                Write-LogMessage "JDBC test error: $($_.Exception.Message)" -Level WARN
                $results += "JDBC: ERROR"
            }
        }
    }

    $summary = "Verify $($testAlias) ($($SourceDatabase)): " + ($results -join " | ")
    Write-LogMessage $summary -Level INFO

    if ($Notify) {
        $smsMsg = if ($overallSuccess) {
            "$($testAlias) OK: CLI $($rowCount) rows in $($controlTable)"
            if ($results -match "JDBC: OK") { $smsMsg += " + JDBC OK" }
        }
        else {
            "FAIL $($testAlias): $($results -join '; ')"
        }
        if ($smsMsg.Length -gt 1024) { $smsMsg = $smsMsg.Substring(0, 1024) }
        foreach ($smsNumber in $NotifyNumbers) {
            Send-Sms -Receiver $smsNumber -Message $smsMsg
        }
    }

    return @{ Success = $overallSuccess; Summary = $summary; Alias = $testAlias; RowCount = $rowCount; Results = $results }
}

# Main
try {
    Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED

    . (Join-Path $PSScriptRoot "_helpers\_Shared.ps1")

    $configFiles = @()
    if (-not [string]::IsNullOrEmpty($ConfigName)) {
        $cfgFile = Join-Path $PSScriptRoot "config.$($ConfigName).json"
        if (-not (Test-Path $cfgFile)) { throw "Config file not found: $($cfgFile)" }
        $configFiles += Get-Item $cfgFile
    }
    else {
        $configFiles = Get-ChildItem -Path $PSScriptRoot -Filter "config.*.json" -File -ErrorAction SilentlyContinue
        if ($configFiles.Count -eq 0) {
            $fallback = Join-Path $PSScriptRoot "config.json"
            if (Test-Path $fallback) { $configFiles += Get-Item $fallback }
            else { throw "No config.*.json files found in $($PSScriptRoot)" }
        }
    }

    $allResults = @()

    foreach ($cfgFile in $configFiles) {
        $cfg = Get-Content $cfgFile.FullName -Raw | ConvertFrom-Json
        Write-LogMessage "===== Testing $($cfg.SourceDatabase) (from $($cfgFile.Name)) =====" -Level INFO

        $testResult = Test-SingleDatabase `
            -SourceDatabase $cfg.SourceDatabase `
            -Application $cfg.Application `
            -OverrideAlias $AliasName `
            -TestJdbc:(-not $SkipJdbc) `
            -Notify:$SendSms `
            -NotifyNumbers $SmsNumbers

        $allResults += $testResult
    }

    # Final summary
    Write-LogMessage "========================================" -Level INFO
    Write-LogMessage "LOCAL VERIFICATION SUMMARY" -Level INFO
    $allPass = $true
    foreach ($r in $allResults) {
        $status = if ($r.Success) { "PASS" } else { "FAIL"; $allPass = $false }
        Write-LogMessage "  $($r.Alias): $($status) ($($r.Results -join ', '))" -Level $(if ($r.Success) { "INFO" } else { "WARN" })
    }
    Write-LogMessage "========================================" -Level INFO

    if ($SendSms -and $allResults.Count -gt 1) {
        $passCount = @($allResults | Where-Object { $_.Success }).Count
        $totalCount = $allResults.Count
        $smsMsg = "Local verify: $($passCount)/$($totalCount) databases OK."
        foreach ($smsNumber in $SmsNumbers) {
            Send-Sms -Receiver $smsNumber -Message $smsMsg
        }
    }

    if (-not $allPass) {
        Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
        exit 1
    }

    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
    if ($SendSms) {
        foreach ($smsNumber in $SmsNumbers) {
            Send-Sms -Receiver $smsNumber -Message "Local verify ERROR: $($_.Exception.Message)"
        }
    }
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    exit 1
}
