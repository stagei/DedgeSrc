<#
.SYNOPSIS
    Exports DB2 SYSCAT.TABLES and SYSCAT.PACKAGES catalogs for each configured database
    into AnalysisStatic/Databases/.

.DESCRIPTION
    For each database in the databaseMap, connects via ODBC and exports to AnalysisCommon/Databases/.
    Queries:
      1. SYSCAT.TABLES   — all tables/views excluding system schemas → syscat_tables.csv/.json
      2. SYSCAT.PACKAGES — bound packages for known app schemas     → syscat_packages.csv/.json

.PARAMETER DatabaseFilter
    Optional. Only export this specific database folder (e.g. 'COBDOK'). Default: all folders.

.EXAMPLE
    pwsh.exe -NoProfile -File .\Export-DatabaseCatalogs.ps1
    pwsh.exe -NoProfile -File .\Export-DatabaseCatalogs.ps1 -DatabaseFilter COBDOK
#>
param(
    [string]$DatabaseFilter = ''
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

$scriptRoot = $PSScriptRoot
$dbRoot     = Join-Path $scriptRoot 'AnalysisCommon\Databases'

$databaseMap = @{
    'BASISRAP' = @{ Alias = 'BASISRAP'; Description = 'Dedge production report database' }
    'COBDOK'   = @{ Alias = 'COBDOK';   Description = 'CobDok document handling database' }
    'FKKONTO'  = @{ Alias = 'FKKONTO';  Description = 'FkKonto/Innlan accounting database' }
}

foreach ($dbName in $databaseMap.Keys) {
    $dir = Join-Path $dbRoot $dbName
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

$queryTables = @"
SELECT
    TRIM(TABNAME)    AS TABNAME,
    TRIM(TABSCHEMA)  AS TABSCHEMA,
    TYPE,
    TRIM(REMARKS)    AS REMARKS,
    COLCOUNT,
    TRIM(TABSCHEMA) || '.' || TRIM(TABNAME) AS QUALIFIED_NAME
FROM SYSCAT.TABLES
WHERE TABSCHEMA NOT LIKE '%SYS%'
  AND TABSCHEMA NOT LIKE '%IBM%'
  AND TABSCHEMA <> 'ROA'
ORDER BY TABSCHEMA, TABNAME
"@

$queryPackages = @"
SELECT
    TRIM(PKGSCHEMA)  AS PKGSCHEMA,
    TRIM(PKGNAME)    AS PKGNAME,
    TRIM(PKGNAME)    AS QUALIFIED_NAME,
    TRIM(PKGNAME) || '.CBL' AS SOURCE_FILENAME
FROM SYSCAT.PACKAGES
WHERE PKGSCHEMA IN ('FK','FKPROC','LOG','HST','CRM','TV','F0001','TCA','INL','DBM','Dedge')
ORDER BY PKGSCHEMA, PKGNAME
"@

function Invoke-CatalogExport {
    param(
        [System.Data.Odbc.OdbcConnection]$Connection,
        [string]$QueryText,
        [hashtable[]]$Columns,
        [string]$OutputDir,
        [string]$FileBaseName,
        [string]$JsonRootKey,
        [string]$FolderName,
        [string]$DbAlias,
        [string]$ServerValue,
        [string]$DbDescription,
        [scriptblock]$SummaryBuilder
    )

    $cmd = $Connection.CreateCommand()
    $cmd.CommandText = $QueryText
    $cmd.CommandTimeout = 120
    $reader = $cmd.ExecuteReader()

    $rows = [System.Collections.ArrayList]::new()
    while ($reader.Read()) {
        $row = [ordered]@{}
        for ($c = 0; $c -lt $Columns.Count; $c++) {
            $col = $Columns[$c]
            if ($reader.IsDBNull($c)) {
                $row[$col.Name] = $col.NullDefault
            } elseif ($col.Type -eq 'int16') {
                $row[$col.Name] = $reader.GetInt16($c)
            } elseif ($col.Type -eq 'trimString') {
                $row[$col.Name] = $reader.GetString($c).Trim()
            } else {
                $row[$col.Name] = $reader.GetString($c)
            }
        }
        [void]$rows.Add([PSCustomObject]$row)
    }
    $reader.Close()
    $cmd.Dispose()

    $summary = & $SummaryBuilder $rows

    Write-LogMessage "  [$($FileBaseName)] Found $($rows.Count) rows — $($summary.LogLine)" -Level INFO

    $csvPath = Join-Path $OutputDir "$($FileBaseName).csv"
    $rows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding utf8
    Write-LogMessage "  [$($FileBaseName)] CSV: $csvPath" -Level INFO

    $jsonData = [ordered]@{
        database    = $FolderName
        db2Alias    = $DbAlias
        server      = $ServerValue
        description = $DbDescription
        exportedAt  = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
        exportedBy  = $env:USERNAME
        query       = $QueryText.Trim()
        summary     = $summary.Data
        $JsonRootKey = @($rows)
    }

    $jsonPath = Join-Path $OutputDir "$($FileBaseName).json"
    $jsonData | ConvertTo-Json -Depth 5 | Out-File -FilePath $jsonPath -Encoding utf8
    Write-LogMessage "  [$($FileBaseName)] JSON: $jsonPath" -Level INFO

    return $rows.Count
}

# ── Column definitions ───────────────────────────────────────────────

$tableColumns = @(
    @{ Name = 'tabName';       Type = 'string';     NullDefault = $null }
    @{ Name = 'tabSchema';     Type = 'string';     NullDefault = $null }
    @{ Name = 'type';          Type = 'trimString'; NullDefault = $null }
    @{ Name = 'remarks';       Type = 'string';     NullDefault = $null }
    @{ Name = 'colCount';      Type = 'int16';      NullDefault = 0 }
    @{ Name = 'qualifiedName'; Type = 'string';     NullDefault = $null }
)

$packageColumns = @(
    @{ Name = 'pkgSchema';      Type = 'string'; NullDefault = $null }
    @{ Name = 'pkgName';        Type = 'string'; NullDefault = $null }
    @{ Name = 'qualifiedName';  Type = 'string'; NullDefault = $null }
    @{ Name = 'sourceFilename'; Type = 'string'; NullDefault = $null }
)

# ── Summary builders ─────────────────────────────────────────────────

$tableSummaryBuilder = {
    param($rows)
    $tableCount = ($rows | Where-Object { $_.type -eq 'T' }).Count
    $viewCount  = ($rows | Where-Object { $_.type -eq 'V' }).Count
    $schemas    = @($rows | Select-Object -ExpandProperty tabSchema -Unique | Sort-Object)
    @{
        LogLine = "$tableCount tables, $viewCount views in schemas: $($schemas -join ', ')"
        Data    = [ordered]@{
            totalObjects = $rows.Count
            tables       = $tableCount
            views        = $viewCount
            schemas      = $schemas
        }
    }
}

$packageSummaryBuilder = {
    param($rows)
    $schemas   = @($rows | Select-Object -ExpandProperty pkgSchema -Unique | Sort-Object)
    $perSchema = [ordered]@{}
    foreach ($s in $schemas) {
        $perSchema[$s] = ($rows | Where-Object { $_.pkgSchema -eq $s }).Count
    }
    @{
        LogLine = "$($rows.Count) packages in schemas: $($schemas -join ', ')"
        Data    = [ordered]@{
            totalPackages = $rows.Count
            schemas       = $schemas
            perSchema     = $perSchema
        }
    }
}

# ── Main loop ────────────────────────────────────────────────────────

$folders = Get-ChildItem $dbRoot -Directory
if ($DatabaseFilter) {
    $folders = $folders | Where-Object { $_.Name -eq $DatabaseFilter }
    if (-not $folders) {
        Write-LogMessage "No folder found for filter '$($DatabaseFilter)'" -Level ERROR
        exit 1
    }
}

$totalExported = 0

foreach ($folder in $folders) {
    $folderName = $folder.Name
    $mapping    = $databaseMap[$folderName]

    if (-not $mapping) {
        Write-LogMessage "No database mapping for folder '$($folderName)' — skipping" -Level WARN
        continue
    }

    $dbAlias = $mapping.Alias
    $dbDesc  = $mapping.Description
    $outDir  = $folder.FullName

    Write-LogMessage "Exporting catalogs for $($folderName) (DSN=$($dbAlias)) — $dbDesc" -Level INFO

    $conn = $null
    try {
        $conn = New-Object System.Data.Odbc.OdbcConnection("DSN=$dbAlias")
        $conn.Open()

        $serverValue = ''
        try {
            $srvCmd = $conn.CreateCommand()
            $srvCmd.CommandText = "VALUES CURRENT SERVER"
            $serverValue = $srvCmd.ExecuteScalar()
            $srvCmd.Dispose()
        } catch { }

        Write-LogMessage "  Connected: DSN=$($dbAlias) → server=$($serverValue)" -Level INFO

        $commonParams = @{
            Connection    = $conn
            OutputDir     = $outDir
            FolderName    = $folderName
            DbAlias       = $dbAlias
            ServerValue   = $serverValue
            DbDescription = $dbDesc
        }

        Invoke-CatalogExport @commonParams `
            -QueryText      $queryTables `
            -Columns        $tableColumns `
            -FileBaseName   'syscat_tables' `
            -JsonRootKey    'tables' `
            -SummaryBuilder $tableSummaryBuilder

        Invoke-CatalogExport @commonParams `
            -QueryText      $queryPackages `
            -Columns        $packageColumns `
            -FileBaseName   'syscat_packages' `
            -JsonRootKey    'packages' `
            -SummaryBuilder $packageSummaryBuilder

        $totalExported++

    } catch {
        Write-LogMessage "  FAILED for $($folderName) (DSN=$($dbAlias)): $($_.Exception.Message)" -Level ERROR
    } finally {
        if ($conn -and $conn.State -eq 'Open') { $conn.Close() }
        if ($conn) { $conn.Dispose() }
    }

    Write-LogMessage "" -Level INFO
}

Write-LogMessage "Done — exported $totalExported of $($folders.Count) databases" -Level INFO
