<#
.SYNOPSIS
    Exports SYSCAT catalog data to DEL files via DB2 EXPORT command.

.DESCRIPTION
    Runs bulk SYSCAT queries for tables, columns, keys, indexes, views,
    triggers, routines, and routine parameters. Each query produces a
    DEL (comma-delimited) file. Also parses the DEL files into PowerShell
    objects for downstream use.
#>

function Export-CatalogData {
    param(
        [string]$InstanceName,
        [string]$DatabaseName,
        [string]$SchemaFilter,
        [string]$ExportDir,
        [string]$AppDataPath
    )

    $queries = @{
        tables = @"
SELECT RTRIM(TABSCHEMA), RTRIM(TABNAME), TYPE, CARD, REMARKS,
       VARCHAR_FORMAT(CREATE_TIME, 'YYYY-MM-DD HH24:MI:SS'),
       VARCHAR_FORMAT(ALTER_TIME, 'YYYY-MM-DD HH24:MI:SS'),
       DATACAPTURE
FROM SYSCAT.TABLES
WHERE TABSCHEMA IN ($($SchemaFilter)) AND TYPE IN ('T','S','G')
ORDER BY TABSCHEMA, TABNAME
"@
        columns = @"
SELECT RTRIM(TABSCHEMA), RTRIM(TABNAME), COLNO, RTRIM(COLNAME),
       RTRIM(TYPENAME), LENGTH, SCALE, NULLS, DEFAULT, REMARKS,
       IDENTITY
FROM SYSCAT.COLUMNS
WHERE TABSCHEMA IN ($($SchemaFilter))
ORDER BY TABSCHEMA, TABNAME, COLNO
"@
        primary_keys = @"
SELECT RTRIM(tc.TABSCHEMA), RTRIM(tc.TABNAME), RTRIM(tc.CONSTNAME),
       kc.COLSEQ, RTRIM(kc.COLNAME)
FROM SYSCAT.TABCONST tc
JOIN SYSCAT.KEYCOLUSE kc ON tc.CONSTNAME = kc.CONSTNAME
     AND tc.TABSCHEMA = kc.TABSCHEMA AND tc.TABNAME = kc.TABNAME
WHERE tc.TYPE = 'P' AND tc.TABSCHEMA IN ($($SchemaFilter))
ORDER BY tc.TABSCHEMA, tc.TABNAME, kc.COLSEQ
"@
        foreign_keys = @"
SELECT RTRIM(r.TABSCHEMA), RTRIM(r.TABNAME), RTRIM(r.CONSTNAME),
       RTRIM(r.REFTABSCHEMA), RTRIM(r.REFTABNAME), RTRIM(r.REFKEYNAME),
       r.DELETERULE, r.UPDATERULE,
       RTRIM(kc.COLNAME), kc.COLSEQ
FROM SYSCAT.REFERENCES r
JOIN SYSCAT.KEYCOLUSE kc ON r.CONSTNAME = kc.CONSTNAME
     AND r.TABSCHEMA = kc.TABSCHEMA AND r.TABNAME = kc.TABNAME
WHERE r.TABSCHEMA IN ($($SchemaFilter))
ORDER BY r.TABSCHEMA, r.TABNAME, r.CONSTNAME, kc.COLSEQ
"@
        incoming_fks = @"
SELECT RTRIM(r.REFTABSCHEMA), RTRIM(r.REFTABNAME),
       RTRIM(r.TABSCHEMA), RTRIM(r.TABNAME), RTRIM(r.CONSTNAME),
       RTRIM(kc.COLNAME), kc.COLSEQ
FROM SYSCAT.REFERENCES r
JOIN SYSCAT.KEYCOLUSE kc ON r.CONSTNAME = kc.CONSTNAME
     AND r.TABSCHEMA = kc.TABSCHEMA AND r.TABNAME = kc.TABNAME
WHERE r.REFTABSCHEMA IN ($($SchemaFilter))
ORDER BY r.REFTABSCHEMA, r.REFTABNAME, r.CONSTNAME, kc.COLSEQ
"@
        indexes = @"
SELECT RTRIM(i.INDSCHEMA), RTRIM(i.INDNAME), RTRIM(i.TABSCHEMA), RTRIM(i.TABNAME),
       i.UNIQUERULE, i.INDEXTYPE,
       RTRIM(ic.COLNAME), ic.COLSEQ, ic.COLORDER
FROM SYSCAT.INDEXES i
JOIN SYSCAT.INDEXCOLUSE ic ON i.INDSCHEMA = ic.INDSCHEMA AND i.INDNAME = ic.INDNAME
WHERE i.TABSCHEMA IN ($($SchemaFilter))
ORDER BY i.TABSCHEMA, i.TABNAME, i.INDNAME, ic.COLSEQ
"@
        views = @"
SELECT RTRIM(v.VIEWSCHEMA), RTRIM(v.VIEWNAME), v.READONLY, v.VALID,
       v.TEXT
FROM SYSCAT.VIEWS v
WHERE v.VIEWSCHEMA IN ($($SchemaFilter))
ORDER BY v.VIEWSCHEMA, v.VIEWNAME, v.SEQNO
"@
        view_deps = @"
SELECT RTRIM(VIEWSCHEMA), RTRIM(VIEWNAME),
       RTRIM(BSCHEMA), RTRIM(BNAME), BTYPE
FROM SYSCAT.VIEWDEP
WHERE VIEWSCHEMA IN ($($SchemaFilter))
ORDER BY VIEWSCHEMA, VIEWNAME, BSCHEMA, BNAME
"@
        view_columns = @"
SELECT RTRIM(TABSCHEMA), RTRIM(TABNAME), COLNO, RTRIM(COLNAME),
       RTRIM(TYPENAME), LENGTH, SCALE, NULLS
FROM SYSCAT.COLUMNS
WHERE TABSCHEMA IN ($($SchemaFilter))
  AND TABNAME IN (SELECT VIEWNAME FROM SYSCAT.VIEWS WHERE VIEWSCHEMA IN ($($SchemaFilter)))
ORDER BY TABSCHEMA, TABNAME, COLNO
"@
        triggers = @"
SELECT RTRIM(TRIGSCHEMA), RTRIM(TRIGNAME), RTRIM(TABSCHEMA), RTRIM(TABNAME),
       TRIGEVENT, TRIGTIME, GRANULARITY, VALID,
       VARCHAR_FORMAT(CREATE_TIME, 'YYYY-MM-DD HH24:MI:SS'),
       REMARKS, TEXT
FROM SYSCAT.TRIGGERS
WHERE TABSCHEMA IN ($($SchemaFilter))
ORDER BY TABSCHEMA, TABNAME, TRIGNAME
"@
        routines = @"
SELECT RTRIM(ROUTINESCHEMA), RTRIM(ROUTINENAME), ROUTINETYPE,
       RTRIM(LANGUAGE), RTRIM(SQL_DATA_ACCESS), DETERMINISTIC,
       VARCHAR_FORMAT(CREATE_TIME, 'YYYY-MM-DD HH24:MI:SS'),
       REMARKS, TEXT, SPECIFICNAME
FROM SYSCAT.ROUTINES
WHERE ROUTINESCHEMA IN ($($SchemaFilter))
  AND ORIGIN = 'Q'
ORDER BY ROUTINESCHEMA, ROUTINENAME, SPECIFICNAME
"@
        routine_parms = @"
SELECT RTRIM(r.ROUTINESCHEMA), RTRIM(r.SPECIFICNAME), RTRIM(r.ROUTINENAME),
       p.ORDINAL, RTRIM(p.PARMNAME), RTRIM(p.TYPENAME),
       p.LENGTH, p.SCALE, p.ROWTYPE
FROM SYSCAT.ROUTINEPARMS p
JOIN SYSCAT.ROUTINES r ON p.SPECIFICNAME = r.SPECIFICNAME
     AND p.ROUTINESCHEMA = r.ROUTINESCHEMA
WHERE r.ROUTINESCHEMA IN ($($SchemaFilter)) AND r.ORIGIN = 'Q'
ORDER BY r.ROUTINESCHEMA, r.SPECIFICNAME, p.ORDINAL
"@
        table_remarks = @"
SELECT RTRIM(TABSCHEMA), RTRIM(TABNAME), REMARKS
FROM SYSCAT.TABLES
WHERE TABSCHEMA IN ($($SchemaFilter)) AND REMARKS IS NOT NULL AND REMARKS <> ''
ORDER BY TABSCHEMA, TABNAME
"@
    }

    $exportCommands = @()
    $exportCommands += "set DB2INSTANCE=$($InstanceName)"
    $exportCommands += "db2 connect to $($DatabaseName)"

    foreach ($name in $queries.Keys) {
        $delFile = Join-Path $ExportDir "$($name).del"
        $sql = $queries[$name] -replace "`r`n", " " -replace "`n", " "
        $exportCommands += "db2 `"EXPORT TO '$($delFile)' OF DEL $($sql)`""
    }

    $exportCommands += "db2 connect reset"
    $exportCommands += "db2 terminate"

    Write-LogMessage "Running $($queries.Count) EXPORT TO DEL queries" -Level INFO
    Invoke-Db2ContentAsScript -Content $exportCommands -ExecutionType BAT `
        -FileName (Join-Path $AppDataPath "catalog_export_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors | Out-Null

    $result = Parse-AllDelFiles -ExportDir $ExportDir
    return $result
}

function Parse-DelFile {
    param(
        [string]$FilePath,
        [switch]$RawLines
    )

    if (-not (Test-Path $FilePath)) {
        Write-LogMessage "DEL file not found: $($FilePath)" -Level WARN
        return @()
    }

    $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
    $fileText  = [System.Text.Encoding]::GetEncoding(1252).GetString($fileBytes)
    $lines     = $fileText -split "`n"
    if ($RawLines) { return $lines }

    # Accumulate multi-line quoted fields into logical records.
    # A logical record is complete when the total number of
    # double-quote characters is even (all quoted fields are closed).
    $rows = @()
    $buffer = $null

    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line) -and $null -eq $buffer) { continue }

        if ($null -eq $buffer) {
            $buffer = $line
        }
        else {
            $buffer += "`n" + $line
        }

        $quoteCount = 0
        foreach ($ch in $buffer.ToCharArray()) { if ($ch -eq '"') { $quoteCount++ } }

        if ($quoteCount % 2 -eq 0) {
            $fields = Parse-DelLine -Line $buffer
            $rows += , $fields
            $buffer = $null
        }
    }

    if ($null -ne $buffer) {
        $fields = Parse-DelLine -Line $buffer
        $rows += , $fields
    }

    return $rows
}

function Parse-DelLine {
    param([string]$Line)

    $fields = [System.Collections.ArrayList]::new()
    $current = [System.Text.StringBuilder]::new()
    $inQuote = $false
    $chars = $Line.ToCharArray()

    for ($i = 0; $i -lt $chars.Length; $i++) {
        $c = $chars[$i]
        if ($inQuote) {
            if ($c -eq '"') {
                if ($i + 1 -lt $chars.Length -and $chars[$i + 1] -eq '"') {
                    $current.Append('"') | Out-Null
                    $i++
                }
                else {
                    $inQuote = $false
                }
            }
            else {
                $current.Append($c) | Out-Null
            }
        }
        else {
            if ($c -eq '"') {
                $inQuote = $true
            }
            elseif ($c -eq ',') {
                [void]$fields.Add($current.ToString())
                $current.Clear() | Out-Null
            }
            else {
                $current.Append($c) | Out-Null
            }
        }
    }
    [void]$fields.Add($current.ToString())
    return $fields.ToArray()
}

function Parse-AllDelFiles {
    param([string]$ExportDir)

    $data = @{}

    # Tables
    $data.Tables = @{}
    $tableRows = Parse-DelFile -FilePath (Join-Path $ExportDir "tables.del")
    foreach ($row in $tableRows) {
        if ($row.Count -lt 8) { continue }
        $key = "$($row[0]).$($row[1])"
        $data.Tables[$key] = @{
            Schema      = $row[0]
            Name        = $row[1]
            Type        = $row[2]
            Card        = if ($row[3] -match '^\d+') { [long]$row[3] } else { -1 }
            Remarks     = $row[4]
            CreateTime  = $row[5]
            AlterTime   = $row[6]
            DataCapture = $row[7]
        }
    }
    $data.TableCount = $data.Tables.Count

    # Columns grouped by table
    $data.Columns = @{}
    $colRows = Parse-DelFile -FilePath (Join-Path $ExportDir "columns.del")
    foreach ($row in $colRows) {
        if ($row.Count -lt 11) { continue }
        $key = "$($row[0]).$($row[1])"
        if (-not $data.Columns.ContainsKey($key)) { $data.Columns[$key] = @() }
        $data.Columns[$key] += , @{
            ColNo    = if ($row[2] -match '^\d+') { [int]$row[2] } else { 0 }
            ColName  = $row[3]
            TypeName = $row[4]
            Length   = $row[5]
            Scale    = $row[6]
            Nulls    = $row[7]
            Default  = $row[8]
            Remarks  = $row[9]
            Identity = $row[10]
        }
    }

    # Primary keys grouped by table
    $data.PrimaryKeys = @{}
    $pkRows = Parse-DelFile -FilePath (Join-Path $ExportDir "primary_keys.del")
    foreach ($row in $pkRows) {
        if ($row.Count -lt 5) { continue }
        $key = "$($row[0]).$($row[1])"
        if (-not $data.PrimaryKeys.ContainsKey($key)) {
            $data.PrimaryKeys[$key] = @{ ConstraintName = $row[2]; Columns = @() }
        }
        $data.PrimaryKeys[$key].Columns += , @{ Seq = [int]$row[3]; ColName = $row[4] }
    }

    # Foreign keys grouped by table
    $data.ForeignKeys = @{}
    $fkRows = Parse-DelFile -FilePath (Join-Path $ExportDir "foreign_keys.del")
    foreach ($row in $fkRows) {
        if ($row.Count -lt 10) { continue }
        $key = "$($row[0]).$($row[1])"
        $fkName = $row[2]
        if (-not $data.ForeignKeys.ContainsKey($key)) { $data.ForeignKeys[$key] = @{} }
        if (-not $data.ForeignKeys[$key].ContainsKey($fkName)) {
            $data.ForeignKeys[$key][$fkName] = @{
                ConstraintName = $fkName
                RefSchema      = $row[3]
                RefTable       = $row[4]
                RefKeyName     = $row[5]
                DeleteRule     = $row[6]
                UpdateRule     = $row[7]
                Columns        = @()
            }
        }
        $data.ForeignKeys[$key][$fkName].Columns += , @{ ColName = $row[8]; Seq = [int]$row[9] }
    }

    # Incoming FKs grouped by referenced table
    $data.IncomingFKs = @{}
    $ifkRows = Parse-DelFile -FilePath (Join-Path $ExportDir "incoming_fks.del")
    foreach ($row in $ifkRows) {
        if ($row.Count -lt 7) { continue }
        $key = "$($row[0]).$($row[1])"
        $fkName = $row[4]
        if (-not $data.IncomingFKs.ContainsKey($key)) { $data.IncomingFKs[$key] = @{} }
        if (-not $data.IncomingFKs[$key].ContainsKey($fkName)) {
            $data.IncomingFKs[$key][$fkName] = @{
                SourceTable    = "$($row[2]).$($row[3])"
                ConstraintName = $fkName
                Columns        = @()
            }
        }
        $data.IncomingFKs[$key][$fkName].Columns += $row[5]
    }

    # Indexes grouped by table
    $data.Indexes = @{}
    $idxRows = Parse-DelFile -FilePath (Join-Path $ExportDir "indexes.del")
    foreach ($row in $idxRows) {
        if ($row.Count -lt 9) { continue }
        $tableKey = "$($row[2]).$($row[3])"
        $idxKey = "$($row[0]).$($row[1])"
        if (-not $data.Indexes.ContainsKey($tableKey)) { $data.Indexes[$tableKey] = @{} }
        if (-not $data.Indexes[$tableKey].ContainsKey($idxKey)) {
            $data.Indexes[$tableKey][$idxKey] = @{
                IndSchema  = $row[0]
                IndName    = $row[1]
                UniqueRule = $row[4]
                IndexType  = $row[5]
                Columns    = @()
            }
        }
        $order = switch ($row[8]) { 'A' { 'ASC' } 'D' { 'DESC' } default { '' } }
        $data.Indexes[$tableKey][$idxKey].Columns += , @{ ColName = $row[6]; Seq = [int]$row[7]; Order = $order }
    }

    # Views
    $data.Views = @{}
    $viewRows = Parse-DelFile -FilePath (Join-Path $ExportDir "views.del")
    foreach ($row in $viewRows) {
        if ($row.Count -lt 5) { continue }
        $key = "$($row[0]).$($row[1])"
        if ($data.Views.ContainsKey($key)) {
            $data.Views[$key].Text += $row[4]
        }
        else {
            $data.Views[$key] = @{
                Schema   = $row[0]
                Name     = $row[1]
                ReadOnly = $row[2]
                Valid    = $row[3]
                Text     = $row[4]
            }
        }
    }
    $data.ViewCount = $data.Views.Count

    # View deps
    $data.ViewDeps = @{}
    $vdRows = Parse-DelFile -FilePath (Join-Path $ExportDir "view_deps.del")
    foreach ($row in $vdRows) {
        if ($row.Count -lt 5) { continue }
        $key = "$($row[0]).$($row[1])"
        if (-not $data.ViewDeps.ContainsKey($key)) { $data.ViewDeps[$key] = @() }
        $data.ViewDeps[$key] += , @{
            BSchema = $row[2]
            BName   = $row[3]
            BType   = $row[4]
        }
    }

    # View columns
    $data.ViewColumns = @{}
    $vcRows = Parse-DelFile -FilePath (Join-Path $ExportDir "view_columns.del")
    foreach ($row in $vcRows) {
        if ($row.Count -lt 8) { continue }
        $key = "$($row[0]).$($row[1])"
        if (-not $data.ViewColumns.ContainsKey($key)) { $data.ViewColumns[$key] = @() }
        $data.ViewColumns[$key] += , @{
            ColNo    = if ($row[2] -match '^\d+') { [int]$row[2] } else { 0 }
            ColName  = $row[3]
            TypeName = $row[4]
            Length   = $row[5]
            Scale    = $row[6]
            Nulls    = $row[7]
        }
    }

    # Triggers
    $data.Triggers = @{}
    $trigRows = Parse-DelFile -FilePath (Join-Path $ExportDir "triggers.del")
    foreach ($row in $trigRows) {
        if ($row.Count -lt 11) { continue }
        $key = "$($row[2]).$($row[3]).$($row[1])"
        $data.Triggers[$key] = @{
            TrigSchema  = $row[0]
            TrigName    = $row[1]
            TabSchema   = $row[2]
            TabName     = $row[3]
            Event       = $row[4]
            Timing      = $row[5]
            Granularity = $row[6]
            Valid       = $row[7]
            CreateTime  = $row[8]
            Remarks     = $row[9]
            Text        = $row[10]
        }
    }
    $data.TriggerCount = $data.Triggers.Count

    # Triggers grouped by table (for table file summary)
    $data.TriggersByTable = @{}
    foreach ($tKey in $data.Triggers.Keys) {
        $trig = $data.Triggers[$tKey]
        $tableKey = "$($trig.TabSchema).$($trig.TabName)"
        if (-not $data.TriggersByTable.ContainsKey($tableKey)) { $data.TriggersByTable[$tableKey] = @() }
        $data.TriggersByTable[$tableKey] += $trig
    }

    # Routines
    $data.Routines = @{}
    $routRows = Parse-DelFile -FilePath (Join-Path $ExportDir "routines.del")
    foreach ($row in $routRows) {
        if ($row.Count -lt 10) { continue }
        $key = "$($row[0]).$($row[9])"
        $data.Routines[$key] = @{
            Schema        = $row[0]
            Name          = $row[1]
            RoutineType   = $row[2]
            Language      = $row[3]
            SqlDataAccess = $row[4]
            Deterministic = $row[5]
            CreateTime    = $row[6]
            Remarks       = $row[7]
            Text          = $row[8]
            SpecificName  = $row[9]
        }
    }
    $data.RoutineCount = $data.Routines.Count

    # Routine parameters grouped by specificname
    $data.RoutineParms = @{}
    $rpRows = Parse-DelFile -FilePath (Join-Path $ExportDir "routine_parms.del")
    foreach ($row in $rpRows) {
        if ($row.Count -lt 9) { continue }
        $key = "$($row[0]).$($row[1])"
        if (-not $data.RoutineParms.ContainsKey($key)) { $data.RoutineParms[$key] = @() }
        $data.RoutineParms[$key] += , @{
            Ordinal  = if ($row[3] -match '^\d+') { [int]$row[3] } else { 0 }
            ParmName = $row[4]
            TypeName = $row[5]
            Length   = $row[6]
            Scale    = $row[7]
            RowType  = $row[8]
        }
    }

    return $data
}

function Export-ReferenceData {
    param(
        [string]$InstanceName,
        [string]$DatabaseName,
        [hashtable]$CatalogData,
        [string]$ExportDir,
        [string]$AppDataPath,
        [string[]]$Schemas,
        [int]$RefDataMaxRows = 1000,
        [string[]]$AlwaysExportTables = @('DBM.TEKSTER')
    )

    $refDataDir = Join-Path $ExportDir "refdata"
    if (-not (Test-Path $refDataDir)) {
        New-Item -Path $refDataDir -ItemType Directory -Force | Out-Null
    }

    # Columns that indicate credentials - never export tables with these
    $credentialCols = @('BRUKERID', 'PASSORD', 'PASSWORD', 'TOKEN', 'SECRET')

    $candidateCount = 0
    $exportedCount = 0

    foreach ($tableKey in $CatalogData.Tables.Keys) {
        $table = $CatalogData.Tables[$tableKey]
        $isAlwaysExport = $AlwaysExportTables -contains $tableKey

        if ($table.Schema -eq 'LOG') { continue }

        # Regex: match table names ending with _HIST, starting with H_, ending with _TEMP, or starting with TMP_
        if ($table.Name -match '(_HIST$|^H_|_TEMP$|^TMP_)') { continue }

        $card = $table.Card
        if (-not $isAlwaysExport -and ($card -lt 0 -or $card -gt 5000)) { continue }

        $tableCols = $CatalogData.Columns[$tableKey]
        if ($tableCols) {
            $hasCredCol = $false
            foreach ($col in $tableCols) {
                if ($credentialCols -contains $col.ColName) { $hasCredCol = $true; break }
            }
            if ($hasCredCol) { continue }
        }

        $candidateCount++
    }

    Write-LogMessage "Reference data: $($candidateCount) candidate tables (CARD <= 5000 + always-export, excluding LOG/HIST/cred)" -Level INFO

    $exportCommands = @()
    $exportCommands += "set DB2INSTANCE=$($InstanceName)"
    $exportCommands += "db2 connect to $($DatabaseName)"

    $tablesToExport = @()
    foreach ($tableKey in $CatalogData.Tables.Keys) {
        $table = $CatalogData.Tables[$tableKey]
        $isAlwaysExport = $AlwaysExportTables -contains $tableKey

        if ($table.Schema -eq 'LOG') { continue }
        if ($table.Name -match '(_HIST$|^H_|_TEMP$|^TMP_)') { continue }
        $card = $table.Card
        if (-not $isAlwaysExport -and ($card -lt 0 -or $card -gt 5000)) { continue }

        $tableCols = $CatalogData.Columns[$tableKey]
        if ($tableCols) {
            $hasCredCol = $false
            foreach ($col in $tableCols) {
                if ($credentialCols -contains $col.ColName) { $hasCredCol = $true; break }
            }
            if ($hasCredCol) { continue }
        }

        $delFile = Join-Path $refDataDir "$($tableKey).del"
        $exportCommands += "db2 `"EXPORT TO '$($delFile)' OF DEL SELECT * FROM $($table.Schema).$($table.Name)`""
        $tablesToExport += $tableKey
        if ($isAlwaysExport) {
            Write-LogMessage "Always-export table included: $($tableKey) (CARD=$($card))" -Level INFO
        }
    }

    $exportCommands += "db2 connect reset"
    $exportCommands += "db2 terminate"

    if ($tablesToExport.Count -gt 0) {
        Write-LogMessage "Exporting reference data for $($tablesToExport.Count) tables" -Level INFO
        Invoke-Db2ContentAsScript -Content $exportCommands -ExecutionType BAT `
            -FileName (Join-Path $AppDataPath "refdata_export_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors | Out-Null
        Write-LogMessage "Reference data export complete" -Level INFO
    }

    # Count exported rows
    $countCommands = @()
    $countCommands += "set DB2INSTANCE=$($InstanceName)"
    $countCommands += "db2 connect to $($DatabaseName)"
    foreach ($tableKey in $tablesToExport) {
        $table = $CatalogData.Tables[$tableKey]
        $countCommands += "db2 `"SELECT '$($tableKey)' AS TBL, COUNT(*) AS CNT FROM $($table.Schema).$($table.Name)`""
    }
    $countCommands += "db2 connect reset"
    $countCommands += "db2 terminate"

    if ($tablesToExport.Count -gt 0) {
        Write-LogMessage "Verifying row counts for $($tablesToExport.Count) reference data tables" -Level INFO
        $countOutput = Invoke-Db2ContentAsScript -Content $countCommands -ExecutionType BAT `
            -FileName (Join-Path $AppDataPath "refdata_counts_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors

        # Parse count output and store actual counts
        $CatalogData.ActualCounts = @{}
        $lines = $countOutput -split "`n"
        foreach ($line in $lines) {
            $trimmed = $line.Trim()
            if ($trimmed -match '^(\w+\.\w+)\s+(\d+)') {
                $CatalogData.ActualCounts[$matches[1]] = [long]$matches[2]
            }
        }
        Write-LogMessage "Verified counts for $($CatalogData.ActualCounts.Count) tables" -Level INFO
    }
}
