<#
.SYNOPSIS
    Replays captured DDL (indexes, grants, views, FKs) from a persisted JSON file.

.DESCRIPTION
    After Db2-LargeTableYearSplit captures DDL and saves it to a JSON file,
    this script can re-apply any missing objects. For indexes, it renames the
    old index on the _TMP table (appending _TMP suffix to free the original
    name) then creates it on the new table. Designed to run on the DB server
    via Cursor-ServerOrchestrator.

.PARAMETER DdlFile
    Path to the captured DDL JSON file. If not provided, auto-discovers
    files in the default RenameAndReload data folder.

.PARAMETER TableFilter
    Optional schema-qualified table name (e.g. DBM.D365_BUNTER) to replay
    only that table's DDL. If omitted, replays all discovered JSON files.

.PARAMETER DatabaseName
    Database catalog name (e.g. FKMMIG). Auto-detected from server hostname
    if omitted.

.PARAMETER SkipIndexes
    Skip index recreation.

.PARAMETER SkipGrants
    Skip grant replay.

.PARAMETER SkipViews
    Skip view recreation.

.PARAMETER SkipForeignKeys
    Skip FK replay.
#>
[CmdletBinding()]
param(
    [string]$DdlFile,
    [string]$TableFilter,
    [string]$DatabaseName,
    [switch]$SkipIndexes,
    [switch]$SkipGrants,
    [switch]$SkipViews,
    [switch]$SkipForeignKeys
)

Import-Module GlobalFunctions -Force
Set-OverrideAppDataFolder -AppName 'Db2-LargeTableYearSplit'

if (-not $DatabaseName) {
    Import-Module Db2-Handler -Force
    $dbInfo = Get-DatabaseInfoFromHostname
    $DatabaseName = $dbInfo.CatalogName
    Write-LogMessage "Auto-detected database: $DatabaseName" -Level INFO
}

$dataDir = Join-Path (Get-ApplicationDataPath) 'RenameAndReload'
$resultFile = Join-Path (Get-ApplicationDataPath) 'replay_ddl_result.txt'
if (Test-Path $resultFile) { Remove-Item $resultFile -Force }

if ($DdlFile) {
    $ddlFiles = @(Get-Item $DdlFile)
}
else {
    $ddlFiles = @(Get-ChildItem -Path $dataDir -Filter '*_captured_ddl.json' -ErrorAction SilentlyContinue)
    if ($TableFilter) {
        $filterPattern = ($TableFilter -replace '\.', '_') + '_captured_ddl.json'
        $ddlFiles = @($ddlFiles | Where-Object { $_.Name -eq $filterPattern })
    }
}

if ($ddlFiles.Count -eq 0) {
    Write-LogMessage "No captured DDL files found. Nothing to replay." -Level WARN
    exit 0
}

Write-LogMessage "=== Replay-CapturedDdl: $($ddlFiles.Count) file(s) to process ===" -Level INFO

foreach ($file in $ddlFiles) {
    $ddl = Get-Content $file.FullName -Raw | ConvertFrom-Json
    $table = $ddl.Table
    $schema = $ddl.Schema
    $baseName = $ddl.TableName
    $tmpTable = "$($schema).$($baseName)_TMP"

    Write-LogMessage "--- Replaying DDL for $table (captured $($ddl.CapturedAt)) ---" -Level INFO
    "=== $table ===" | Out-File -FilePath $resultFile -Append -Encoding utf8

    $batLines = @("set DB2INSTANCE=DB2", "db2 connect to $DatabaseName")
    $stepCount = 0

    if (-not $SkipIndexes -and $ddl.IndexStatements.Count -gt 0) {
        $batLines += "echo --- RENAME indexes on $tmpTable to free original names --- >> `"$resultFile`""
        foreach ($stmt in $ddl.IndexStatements) {
            # Regex: CREATE + optional UNIQUE + INDEX + <schema.name> + ON
            #   Group 1 = schema-qualified index name (e.g. DBM.TABLE_I1)
            if ($stmt -match '(?i)^CREATE\s+(?:UNIQUE\s+)?INDEX\s+(\S+)\s+ON\s') {
                $idxFullName = $matches[1]
                $idxParts = $idxFullName -split '\.'
                $idxNameOnly = $idxParts[-1]
                # Db2 identifier max = 128 bytes; truncate if appending _TMP exceeds limit
                $newName = if ($idxNameOnly.Length -gt 124) { $idxNameOnly.Substring(0, 124) + '_TMP' } else { "$($idxNameOnly)_TMP" }
                $batLines += "db2 `"RENAME INDEX $idxFullName TO $newName`" >> `"$resultFile`" 2>&1"
            }
        }

        $batLines += "echo --- CREATE indexes on $table --- >> `"$resultFile`""
        foreach ($stmt in $ddl.IndexStatements) {
            $stepCount++
            $batLines += "echo [IDX $stepCount] >> `"$resultFile`""
            $batLines += "db2 `"$stmt`" >> `"$resultFile`" 2>&1"
        }
    }

    if (-not $SkipViews -and $ddl.ViewStatements.Count -gt 0) {
        $batLines += "echo --- CREATE views --- >> `"$resultFile`""
        foreach ($stmt in $ddl.ViewStatements) {
            $stepCount++
            $batLines += "echo [VIEW $stepCount] >> `"$resultFile`""
            $batLines += "db2 `"$stmt`" >> `"$resultFile`" 2>&1"
        }
    }

    if (-not $SkipGrants -and $ddl.GrantStatements.Count -gt 0) {
        $batLines += "echo --- GRANT permissions on $table --- >> `"$resultFile`""
        foreach ($stmt in $ddl.GrantStatements) {
            $stepCount++
            $batLines += "echo [GRANT $stepCount] >> `"$resultFile`""
            $batLines += "db2 `"$stmt`" >> `"$resultFile`" 2>&1"
        }
    }

    if (-not $SkipForeignKeys -and $ddl.FkAddStatements.Count -gt 0) {
        $batLines += "echo --- ADD foreign keys --- >> `"$resultFile`""
        foreach ($stmt in $ddl.FkAddStatements) {
            $stepCount++
            $batLines += "echo [FK $stepCount] >> `"$resultFile`""
            $batLines += "db2 `"$stmt`" >> `"$resultFile`" 2>&1"
        }
    }

    $batLines += "echo --- VERIFICATION for $table --- >> `"$resultFile`""
    $batLines += "db2 `"SELECT COUNT(*) AS IDX_COUNT FROM SYSCAT.INDEXES WHERE RTRIM(TABSCHEMA)='$schema' AND TABNAME='$baseName'`" >> `"$resultFile`" 2>&1"
    $batLines += "db2 `"SELECT COUNT(*) AS GRANT_COUNT FROM SYSCAT.TABAUTH WHERE RTRIM(TABSCHEMA)='$schema' AND TABNAME='$baseName'`" >> `"$resultFile`" 2>&1"
    $batLines += "db2 `"SELECT COUNT(*) AS VIEW_DEP FROM SYSCAT.TABDEP WHERE RTRIM(BSCHEMA)='$schema' AND BNAME='$baseName' AND DTYPE='V'`" >> `"$resultFile`" 2>&1"
    $batLines += "db2 `"SELECT COUNT(*) AS FK_IN FROM SYSCAT.REFERENCES WHERE RTRIM(REFTABSCHEMA)='$schema' AND REFTABNAME='$baseName'`" >> `"$resultFile`" 2>&1"
    $batLines += "db2 `"SELECT COUNT(*) AS FK_OUT FROM SYSCAT.REFERENCES WHERE RTRIM(TABSCHEMA)='$schema' AND TABNAME='$baseName'`" >> `"$resultFile`" 2>&1"
    $batLines += "db2 connect reset >> `"$resultFile`" 2>&1"
    $batLines += "db2 terminate >> `"$resultFile`" 2>&1"

    $batContent = $batLines -join "`r`n"
    $batFile = Join-Path $env:TEMP "replay_ddl_$($schema)_$($baseName).bat"
    $batContent | Out-File -FilePath $batFile -Encoding ascii -Force

    Write-LogMessage "Executing $stepCount DDL statements for $table via db2cmd.exe..." -Level INFO
    $proc = Start-Process -FilePath 'C:\DbInst\BIN\db2cmd.exe' -ArgumentList '-w', '-c', $batFile -Wait -NoNewWindow -PassThru
    Write-LogMessage "db2cmd.exe exited with code $($proc.ExitCode) for $table" -Level INFO
}

if (Test-Path $resultFile) {
    $output = Get-Content $resultFile -Raw
    Write-LogMessage "Result file content:`n$output" -Level INFO
    Write-Host $output
}

Write-LogMessage "=== Replay-CapturedDdl complete ===" -Level INFO
