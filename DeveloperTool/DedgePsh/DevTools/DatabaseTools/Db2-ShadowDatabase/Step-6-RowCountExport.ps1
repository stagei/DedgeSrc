<#
.SYNOPSIS
    Exports row counts for all user tables in a database to a JSON file.

.DESCRIPTION
    Standalone row count export designed to run as a background process alongside
    other pipeline steps. Queries SYSCAT.TABLES for all user tables (excluding
    nicknames and system schemas), then counts rows in batches of 50 using
    UNION ALL queries.

    Outputs a JSON file with structure:
    { Timestamp, Instance, Database, RowCounts: { "SCHEMA.TABLE": count, ... }, TableCount }

.PARAMETER InstanceName
    DB2 instance name.

.PARAMETER DatabaseName
    Database name to export row counts from.

.PARAMETER OutputPath
    Full path for the output JSON file.

.EXAMPLE
    .\Step-6-RowCountExport.ps1 -InstanceName DB2 -DatabaseName FKMVFT -OutputPath C:\temp\rowcounts.json
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$InstanceName,

    [Parameter(Mandatory = $false)]
    [string]$DatabaseName,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

. (Join-Path $PSScriptRoot "_helpers\_Shared.ps1")
$cfgPath = if ($env:Db2ShadowConfigPath -and (Test-Path $env:Db2ShadowConfigPath)) { $env:Db2ShadowConfigPath } else { Get-ShadowDatabaseConfigPath -ScriptRoot $PSScriptRoot }
if (-not (Test-Path $cfgPath)) { throw "Config not found. Ensure config.*.json exists for this computer." }
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
if ([string]::IsNullOrEmpty($InstanceName))  { $InstanceName = $cfg.SourceInstance }
if ([string]::IsNullOrEmpty($DatabaseName))  { $DatabaseName = $cfg.SourceDatabase }

$systemSchemas = "'SYSIBM','SYSCAT','SYSFUN','SYSSTAT','NULLID','SYSIBMADM','SYSIBMINTERNAL','SYSIBMTS','SYSPUBLIC','SYSTOOLS'"

function Invoke-Db2QueryLocal {
    param(
        [string]$Inst,
        [string]$Db,
        [string]$Query,
        [string]$Folder,
        [string]$Label
    )
    $cleanQuery = $Query -replace '[\r\n]+', ' '
    $cmds = @()
    $cmds += "set DB2INSTANCE=$Inst"
    $cmds += "db2 connect to $Db"
    $cmds += "db2 `"$cleanQuery`""
    $cmds += "db2 connect reset"
    $cmds += "db2 terminate"
    $output = Invoke-Db2ContentAsScript -Content $cmds -ExecutionType BAT `
        -FileName (Join-Path $Folder "$($Label)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors
    return $output
}

function Parse-RowCountOutput {
    param([string]$Output)
    $counts = [ordered]@{}
    $lines = $Output -split "`n"
    $inData = $false
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\d+\s+(post\(er\)\s+er\s+valgt|record\(s\)\s+selected)') { $inData = $false; continue }
        if ($trimmed -match '^[A-Z]:\\.*>') { $inData = $false; continue }
        if ($trimmed -match '^-{4,}') { $inData = $true; continue }
        if ($inData -and -not [string]::IsNullOrWhiteSpace($trimmed)) {
            $parts = $trimmed -split '\s{2,}'
            if ($parts.Count -ge 2 -and $parts[0] -match '^\w+\.') {
                $counts[$parts[0].Trim()] = [long]$parts[1].Trim()
            }
        }
    }
    return $counts
}

try {
    Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED
    Write-LogMessage "Row Count Export: $($DatabaseName) on instance $($InstanceName)" -Level INFO

    Test-Db2ServerAndAdmin

    $workFolder = Get-ApplicationDataPath
    Set-OverrideAppDataFolder -Path $workFolder

    $tableQuery = "SELECT RTRIM(T.TABSCHEMA) || '.' || RTRIM(T.TABNAME) AS FULL_TABLE FROM SYSCAT.TABLES T WHERE T.TYPE = 'T' AND T.TABSCHEMA NOT IN ($systemSchemas) AND NOT EXISTS (SELECT 1 FROM SYSCAT.NICKNAMES N WHERE N.TABSCHEMA = T.TABSCHEMA AND N.TABNAME = T.TABNAME) ORDER BY T.TABSCHEMA, T.TABNAME"

    $tablesOutput = Invoke-Db2QueryLocal -Inst $InstanceName -Db $DatabaseName `
        -Query $tableQuery -Folder $workFolder -Label "TableList_RowExport"

    $tableNames = @()
    $lines = $tablesOutput -split "`n"
    $inData = $false
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\d+\s+(post\(er\)\s+er\s+valgt|record\(s\)\s+selected)') { $inData = $false; continue }
        if ($trimmed -match '^[A-Z]:\\.*>') { $inData = $false; continue }
        if ($trimmed -match '^-{4,}') { $inData = $true; continue }
        if ($inData -and -not [string]::IsNullOrWhiteSpace($trimmed)) {
            $parts = $trimmed -split '\s{2,}', 2
            if ($parts.Count -ge 1 -and $parts[0] -match '^\w+\.') {
                $tableNames += $parts[0].Trim()
            }
        }
    }

    Write-LogMessage "Found $($tableNames.Count) tables for row count export" -Level INFO

    $allCounts = [ordered]@{}
    $batchSize = 50
    for ($i = 0; $i -lt $tableNames.Count; $i += $batchSize) {
        $batch = $tableNames[$i..[Math]::Min($i + $batchSize - 1, $tableNames.Count - 1)]
        $batchQueries = @()
        foreach ($tbl in $batch) {
            $batchQueries += "SELECT '$($tbl)' AS TBL, COUNT(*) AS CNT FROM $($tbl)"
        }
        $unionQuery = $batchQueries -join " UNION ALL "

        $batchOut = Invoke-Db2QueryLocal -Inst $InstanceName -Db $DatabaseName `
            -Query $unionQuery -Folder $workFolder -Label "RowBatch_$($i)"

        $batchCounts = Parse-RowCountOutput -Output $batchOut
        foreach ($key in $batchCounts.Keys) {
            $allCounts[$key] = $batchCounts[$key]
        }

        Write-LogMessage "Row counts: processed $([Math]::Min($i + $batchSize, $tableNames.Count))/$($tableNames.Count) tables" -Level INFO
    }

    $outputDir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $outputDir -PathType Container)) {
        New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
    }

    $result = [ordered]@{
        Timestamp  = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Instance   = $InstanceName
        Database   = $DatabaseName
        TableCount = $tableNames.Count
        RowCounts  = $allCounts
    }

    $result | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8 -Force
    Write-LogMessage "Row counts exported to: $($OutputPath) ($($tableNames.Count) tables)" -Level INFO

    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Row Count Export FAILED: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    exit 1
}
