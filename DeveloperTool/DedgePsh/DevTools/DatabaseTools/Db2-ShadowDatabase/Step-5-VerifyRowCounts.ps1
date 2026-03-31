<#
.SYNOPSIS
    Compares row counts for all user tables between source and shadow database.

.DESCRIPTION
    Step 5 of the shadow database workflow. For each user table in both databases,
    runs a SELECT COUNT(*) that also returns CURRENT SERVER (the database name)
    to prove the count came from the correct database. Logs every table comparison
    and sends an SMS summary.

    Defaults are loaded from config.json. Parameters override config values.

.EXAMPLE
    .\Step-5-VerifyRowCounts.ps1
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$SourceInstance,

    [Parameter(Mandatory = $false)]
    [string]$SourceDatabase,

    [Parameter(Mandatory = $false)]
    [string]$TargetInstance,

    [Parameter(Mandatory = $false)]
    [string]$TargetDatabase
)

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force


. (Join-Path $PSScriptRoot "_helpers\_Shared.ps1")
$cfgPath = if ($env:Db2ShadowConfigPath -and (Test-Path $env:Db2ShadowConfigPath)) { $env:Db2ShadowConfigPath } else { Get-ShadowDatabaseConfigPath -ScriptRoot $PSScriptRoot }
if (-not (Test-Path $cfgPath)) { throw "Config not found. Ensure config.*.json exists for this computer." }
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
if ([string]::IsNullOrEmpty($SourceInstance))  { $SourceInstance = $cfg.SourceInstance }
if ([string]::IsNullOrEmpty($SourceDatabase))  { $SourceDatabase = $cfg.SourceDatabase }
if ([string]::IsNullOrEmpty($TargetInstance))   { $TargetInstance = $cfg.TargetInstance }
if ([string]::IsNullOrEmpty($TargetDatabase))   { $TargetDatabase = $cfg.TargetDatabase }
if ([string]::IsNullOrEmpty($SourceInstance))  { throw "SourceInstance not set. Configure in config.json or pass -SourceInstance." }
if ([string]::IsNullOrEmpty($SourceDatabase))  { throw "SourceDatabase not set. Configure in config.json or pass -SourceDatabase." }
if ([string]::IsNullOrEmpty($TargetInstance))   { throw "TargetInstance not set. Configure in config.json or pass -TargetInstance." }
if ([string]::IsNullOrEmpty($TargetDatabase))   { throw "TargetDatabase not set. Configure in config.json or pass -TargetDatabase." }

try {
    Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED
    Write-LogMessage "Step 5: Comparing row counts between $($SourceDatabase) ($($SourceInstance)) and $($TargetDatabase) ($($TargetInstance))" -Level INFO

    Test-Db2ServerAndAdmin

    $workFolder = Get-ApplicationDataPath
    Set-OverrideAppDataFolder -Path $workFolder
    Write-LogMessage "Work folder: $($workFolder)" -Level INFO

    #########################################################
    # Phase 1: Get table list from source with row counts
    #########################################################
    Write-LogMessage "Phase 1: Counting rows in all user tables in $($SourceDatabase) on $($SourceInstance)" -Level INFO

    $sourceQuery = @"
SELECT RTRIM(T.TABSCHEMA) || '.' || RTRIM(T.TABNAME) AS FULL_TABLE, CURRENT SERVER AS DB_NAME
FROM SYSCAT.TABLES T
WHERE T.TYPE = 'T'
  AND T.TABSCHEMA NOT IN ('SYSIBM','SYSCAT','SYSFUN','SYSSTAT','NULLID','SYSIBMADM','SYSIBMINTERNAL','SYSIBMTS','SYSPUBLIC','SYSTOOLS')
  AND NOT EXISTS (SELECT 1 FROM SYSCAT.NICKNAMES N WHERE N.TABSCHEMA = T.TABSCHEMA AND N.TABNAME = T.TABNAME)
ORDER BY T.TABSCHEMA, T.TABNAME
"@

    $listTablesCmd = @()
    $listTablesCmd += "set DB2INSTANCE=$($SourceInstance)"
    $listTablesCmd += "db2 connect to $($SourceDatabase)"
    $listTablesCmd += "db2 `"$($sourceQuery.Replace("`n", " "))`""
    $listTablesCmd += "db2 connect reset"
    $listTablesCmd += "db2 terminate"

    $tableListOutput = Invoke-Db2ContentAsScript -Content $listTablesCmd -ExecutionType BAT `
        -FileName (Join-Path $workFolder "ListTables_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors
    Write-LogMessage "Table list output: $($tableListOutput)" -Level INFO

    $tables = @()
    $lines = $tableListOutput -split "`n"
    $inData = $false
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\d+\s+(post\(er\)\s+er\s+valgt|record\(s\)\s+selected)') { $inData = $false; continue }
        if ($trimmed -match '^[A-Z]:\\.*>') { $inData = $false; continue }
        if ($trimmed -match '^-{4,}') { $inData = $true; continue }
        if ($inData -and -not [string]::IsNullOrWhiteSpace($trimmed)) {
            # Format: "SCHEMA.TABLE    DBNAME"
            # Split on 2+ whitespace to separate table name from DB name
            $parts = $trimmed -split '\s{2,}', 2
            if ($parts.Count -ge 1 -and $parts[0] -match '^\w+\.\w+') {
                $tables += $parts[0].Trim()
            }
        }
    }

    $tableCount = $tables.Count
    Write-LogMessage "Found $($tableCount) user tables to compare" -Level INFO

    if ($tableCount -eq 0) {
        throw "No user tables found in $($SourceDatabase)"
    }

    #########################################################
    # Phase 2: Count rows per table in source
    #########################################################
    Write-LogMessage "Phase 2: Counting rows per table in $($SourceDatabase)" -Level INFO

    $sourceCountCmd = @()
    $sourceCountCmd += "set DB2INSTANCE=$($SourceInstance)"
    $sourceCountCmd += "db2 connect to $($SourceDatabase)"

    foreach ($table in $tables) {
        $sourceCountCmd += "db2 `"SELECT '$($table)' AS TABLE_NAME, COUNT(*) AS ROW_COUNT, CURRENT SERVER AS DB_NAME FROM $($table)`""
    }

    $sourceCountCmd += "db2 connect reset"
    $sourceCountCmd += "db2 terminate"

    $sourceOutput = Invoke-Db2ContentAsScript -Content $sourceCountCmd -ExecutionType BAT `
        -FileName (Join-Path $workFolder "SourceCounts_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors
    Write-LogMessage "Source count output received" -Level INFO

    #########################################################
    # Phase 3: Count rows per table in target
    #########################################################
    Write-LogMessage "Phase 3: Counting rows per table in $($TargetDatabase)" -Level INFO

    $targetCountCmd = @()
    $targetCountCmd += "set DB2INSTANCE=$($TargetInstance)"
    $targetCountCmd += "db2 connect to $($TargetDatabase)"

    foreach ($table in $tables) {
        $targetCountCmd += "db2 `"SELECT '$($table)' AS TABLE_NAME, COUNT(*) AS ROW_COUNT, CURRENT SERVER AS DB_NAME FROM $($table)`""
    }

    $targetCountCmd += "db2 connect reset"
    $targetCountCmd += "db2 terminate"

    $targetOutput = Invoke-Db2ContentAsScript -Content $targetCountCmd -ExecutionType BAT `
        -FileName (Join-Path $workFolder "TargetCounts_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors
    Write-LogMessage "Target count output received" -Level INFO

    #########################################################
    # Phase 4: Parse and compare results
    #########################################################
    Write-LogMessage "Phase 4: Parsing and comparing row counts" -Level INFO

    function Parse-CountOutput {
        param([string]$Output)
        $results = @{}
        $currentTable = ""
        $outputLines = $Output -split "`n"
        foreach ($line in $outputLines) {
            $trimmed = $line.Trim()
            # Match lines with table name, row count, and DB name
            # Format after the dashes: "SCHEMA.TABLE     123     DBNAME"
            if ($trimmed -match '^(\w+\.\w+)\s+(\d+)\s+(\S+)') {
                $tblName = $matches[1]
                $rowCount = [long]$matches[2]
                $dbName = $matches[3]
                $results[$tblName] = @{ Count = $rowCount; DbName = $dbName }
            }
        }
        return $results
    }

    $sourceCounts = Parse-CountOutput -Output $sourceOutput
    $targetCounts = Parse-CountOutput -Output $targetOutput

    Write-LogMessage "Parsed $($sourceCounts.Count) source tables, $($targetCounts.Count) target tables" -Level INFO

    $matchCount = 0
    $mismatchCount = 0
    $missingCount = 0
    $mismatches = @()

    foreach ($table in $tables) {
        $srcEntry = $sourceCounts[$table]
        $tgtEntry = $targetCounts[$table]

        $srcCount = if ($srcEntry) { $srcEntry.Count } else { -1 }
        $srcDb = if ($srcEntry) { $srcEntry.DbName } else { "N/A" }
        $tgtCount = if ($tgtEntry) { $tgtEntry.Count } else { -1 }
        $tgtDb = if ($tgtEntry) { $tgtEntry.DbName } else { "N/A" }

        if ($srcCount -eq -1 -or $tgtCount -eq -1) {
            $missingCount++
            Write-LogMessage "MISSING: $($table) | Source($($srcDb)): $($srcCount) | Target($($tgtDb)): $($tgtCount)" -Level WARN
            $mismatches += "$($table): missing"
        }
        elseif ($srcCount -eq $tgtCount) {
            $matchCount++
            Write-LogMessage "MATCH: $($table) | Source($($srcDb)): $($srcCount) | Target($($tgtDb)): $($tgtCount)" -Level INFO
        }
        else {
            $mismatchCount++
            Write-LogMessage "MISMATCH: $($table) | Source($($srcDb)): $($srcCount) | Target($($tgtDb)): $($tgtCount) | Diff: $($srcCount - $tgtCount)" -Level WARN
            $mismatches += "$($table): src=$($srcCount) tgt=$($tgtCount)"
        }
    }

    Write-LogMessage "========================================" -Level INFO
    Write-LogMessage "VERIFICATION SUMMARY" -Level INFO
    Write-LogMessage "Total tables: $($tableCount)" -Level INFO
    Write-LogMessage "Matching: $($matchCount)" -Level INFO
    Write-LogMessage "Mismatched: $($mismatchCount)" -Level INFO
    Write-LogMessage "Missing: $($missingCount)" -Level INFO
    Write-LogMessage "========================================" -Level INFO

    if ($mismatchCount -eq 0 -and $missingCount -eq 0) {
        $smsMsg = "Row count verify OK: $($matchCount)/$($tableCount) tables match between $($SourceDatabase) and $($TargetDatabase). All rows accounted for."
        Write-LogMessage $smsMsg -Level INFO
        Import-Module GlobalFunctions -Force
        Send-Sms -Receiver "+4797188358" -Message $smsMsg
    }
    else {
        $smsMsg = "Row count verify: $($matchCount) match, $($mismatchCount) mismatch, $($missingCount) missing of $($tableCount) tables. Check log."
        Write-LogMessage $smsMsg -Level WARN
        Import-Module GlobalFunctions -Force
        Send-Sms -Receiver "+4797188358" -Message $smsMsg
        if ($mismatches.Count -gt 0) {
            Write-LogMessage "Mismatched/missing tables:" -Level WARN
            foreach ($m in $mismatches) { Write-LogMessage "  $($m)" -Level WARN }
        }
    }

    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    exit 1
}
finally {
    Reset-OverrideAppDataFolder
}
