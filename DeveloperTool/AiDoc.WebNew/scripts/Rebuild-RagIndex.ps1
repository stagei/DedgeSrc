<#
.SYNOPSIS
    Rebuild a RAG ChromaDB index by name using build_index.py.

.DESCRIPTION
    All-in-one script for the Dedge-code RAG pipeline. When -RagName is
    Dedge-code (or -All), it automatically:
      1. Clones/pulls all Azure DevOps repos into library\Dedge-code\code\
      2. Updates .Dedge-rag-config.json with discovered repos
      3. Exports DB2 schemas to library\Dedge-code\_databases\ (requires DB2 client)
      4. Builds the ChromaDB vector index via build_index.py

    For other RAG names, only step 4 runs.

    Writes a .running status file with live progress (percentage) during indexing.

.PARAMETER RagName
    Name of the RAG library to rebuild (e.g. Dedge-code, db2-docs, visual-cobol-docs).
    Required unless -All is specified.

.PARAMETER AiDocRoot
    Override path to the AiDoc root. If omitted, auto-detected based on
    username (dev machines use src\AiDoc, servers use FkPythonApps\AiDoc).

.PARAMETER All
    Rebuild ALL RAG indexes under library/ (ignores -RagName).

.EXAMPLE
    pwsh.exe -NoProfile -File Rebuild-RagIndex.ps1 -RagName Dedge-code
.EXAMPLE
    pwsh.exe -NoProfile -File Rebuild-RagIndex.ps1 -All
.EXAMPLE
    pwsh.exe -NoProfile -File Rebuild-RagIndex.ps1 -RagName db2-docs -AiDocRoot C:\opt\src\AiDoc
#>
[CmdletBinding()]
param(
    [string]$RagName,
    [string]$AiDocRoot,
    [switch]$All
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

function Export-Db2ForRagDedgeCode {
    <#
    .SYNOPSIS
        Exports DB2 database objects to structured markdown for RAG indexing.
    .DESCRIPTION
        Connects to DB2 via the local client, extracts DDL (db2look), queries
        SYSCAT catalog views, and generates one markdown file per object.
        Dot-sources helpers from the Db2-ExportForRag folder.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$InstanceName = "DB2",

        [Parameter(Mandatory = $false)]
        [string[]]$DatabaseNames = @("BASISPRO", "BASISHST", "FKKONTO", "COBDOK"),

        [Parameter(Mandatory = $false)]
        [string[]]$Schemas,

        [Parameter(Mandatory = $false)]
        [int]$RefDataMaxRows = 1000,

        [Parameter(Mandatory = $false)]
        [switch]$SkipRefData,

        [Parameter(Mandatory = $false)]
        [switch]$SkipDdl,

        [Parameter(Mandatory = $false)]
        [string[]]$AlwaysExportTables = @('DBM.TEKSTER'),

        [Parameter(Mandatory = $false)]
        [ValidateSet('1a', '1b', '1c', '2a', '2b')]
        [string]$ResumeFrom,

        [Parameter(Mandatory = $false)]
        [switch]$SkipRagCopy,

        [Parameter(Mandatory = $false)]
        [string]$RagLibraryPath
    )

    Import-Module GlobalFunctions -Force
    Import-Module Db2-Handler -Force

    # ── Inline helper functions (from Db2-ExportForRag\_helpers) ────────────

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

    function Parse-AllDelFiles {
        param([string]$ExportDir)

        $data = @{}

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

        $data.TriggersByTable = @{}
        foreach ($tKey in $data.Triggers.Keys) {
            $trig = $data.Triggers[$tKey]
            $tableKey = "$($trig.TabSchema).$($trig.TabName)"
            if (-not $data.TriggersByTable.ContainsKey($tableKey)) { $data.TriggersByTable[$tableKey] = @() }
            $data.TriggersByTable[$tableKey] += $trig
        }

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

        $credentialCols = @('BRUKERID', 'PASSORD', 'PASSWORD', 'TOKEN', 'SECRET')

        $candidateCount = 0

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

    function Parse-Db2LookDdl {
        param(
            [Parameter(Mandatory = $true)]
            [string]$DdlFilePath
        )

        if (-not (Test-Path $DdlFilePath)) {
            Write-LogMessage "DDL file not found: $($DdlFilePath)" -Level WARN
            return @{}
        }

        $rawBytes = [System.IO.File]::ReadAllBytes($DdlFilePath)
        $rawContent = [System.Text.Encoding]::GetEncoding(1252).GetString($rawBytes)

        $statements = $rawContent -split '(?m)^@\s*$|(?<=\S)\s*@\s*$'

        $ddlMap = @{}

        foreach ($stmt in $statements) {
            $trimmed = $stmt.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
            if ($trimmed -match '^--') {
                $nonComment = ($trimmed -split "`n" | Where-Object { $_ -notmatch '^\s*--' -and -not [string]::IsNullOrWhiteSpace($_) }) -join "`n"
                if ([string]::IsNullOrWhiteSpace($nonComment)) { continue }
                $trimmed = $nonComment.Trim()
            }

            $objectKey = Get-DdlObjectKey -Statement $trimmed
            if ($objectKey) {
                if (-not $ddlMap.ContainsKey($objectKey)) {
                    $ddlMap[$objectKey] = @()
                }
                $ddlMap[$objectKey] += $stmt.Trim()
            }
        }

        return $ddlMap
    }

    function Get-DdlObjectKey {
        param([string]$Statement)

        $s = $Statement

        # Regex: CREATE TABLE "SCHEMA"."TABLENAME" or CREATE TABLE SCHEMA.TABLENAME
        #   CREATE\s+TABLE\s+  -- literal CREATE TABLE
        #   "?(\w+)"?\."?(\w+)"?  -- optional-quoted SCHEMA.NAME
        if ($s -match 'CREATE\s+TABLE\s+"?(\w+)"?\."?(\w+)"?') {
            return "$($matches[1]).$($matches[2])"
        }

        if ($s -match 'ALTER\s+TABLE\s+"?(\w+)"?\."?(\w+)"?') {
            return "$($matches[1]).$($matches[2])"
        }

        # Key by target table, not the index name
        if ($s -match 'CREATE\s+(?:UNIQUE\s+)?INDEX\s+"?\w+"?\."?\w+"?\s+ON\s+"?(\w+)"?\."?(\w+)"?') {
            return "$($matches[1]).$($matches[2])"
        }

        if ($s -match 'CREATE\s+(?:OR\s+REPLACE\s+)?VIEW\s+"?(\w+)"?\."?(\w+)"?') {
            return "$($matches[1]).$($matches[2])"
        }

        if ($s -match 'CREATE\s+(?:OR\s+REPLACE\s+)?PROCEDURE\s+"?(\w+)"?\."?(\w+)"?') {
            return "$($matches[1]).$($matches[2])"
        }

        if ($s -match 'CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+"?(\w+)"?\."?(\w+)"?') {
            return "$($matches[1]).$($matches[2])"
        }

        if ($s -match 'CREATE\s+(?:OR\s+REPLACE\s+)?TRIGGER\s+"?(\w+)"?\."?(\w+)"?') {
            return "$($matches[1]).$($matches[2])"
        }

        if ($s -match 'COMMENT\s+ON\s+TABLE\s+"?(\w+)"?\."?(\w+)"?') {
            return "$($matches[1]).$($matches[2])"
        }
        if ($s -match 'COMMENT\s+ON\s+COLUMN\s+"?(\w+)"?\."?(\w+)"?\.') {
            return "$($matches[1]).$($matches[2])"
        }

        if ($s -match 'GRANT\s+.*\s+ON\s+(?:TABLE\s+)?"?(\w+)"?\."?(\w+)"?') {
            return "$($matches[1]).$($matches[2])"
        }

        return $null
    }

    function Format-FkRule {
        param([string]$Rule)
        switch ($Rule) {
            'A' { 'NO ACTION' }
            'C' { 'CASCADE' }
            'N' { 'SET NULL' }
            'R' { 'RESTRICT' }
            default { $Rule }
        }
    }

    function Format-TriggerEvent {
        param([string]$TrigEvent)
        switch ($TrigEvent) {
            'I' { 'INSERT' }
            'U' { 'UPDATE' }
            'D' { 'DELETE' }
            default { $Event }
        }
    }

    function Format-TriggerTiming {
        param([string]$Timing)
        switch ($Timing) {
            'B' { 'BEFORE' }
            'A' { 'AFTER' }
            'I' { 'INSTEAD OF' }
            default { $Timing }
        }
    }

    function Get-TableReferences {
        param(
            [string]$Body,
            [string[]]$KnownSchemas
        )

        $refs = @{}
        if (-not $Body) { return $refs }

        $schemaPattern = ($KnownSchemas | ForEach-Object { [regex]::Escape($_) }) -join '|'

        # Regex: find SCHEMA.OBJECTNAME references where SCHEMA is one of the known schemas
        #   ($schemaPattern)       -- group 1: schema name
        #   \.                     -- literal dot
        #   ([A-Z_][A-Z0-9_]+)    -- group 2: object name
        $pattern = "(?i)\b($($schemaPattern))\.([A-Z_][A-Z0-9_]+)\b"
        $matches2 = [regex]::Matches($Body, $pattern)

        foreach ($m in $matches2) {
            $tableRef = "$($m.Groups[1].Value.ToUpper()).$($m.Groups[2].Value.ToUpper())"
            if (-not $refs.ContainsKey($tableRef)) { $refs[$tableRef] = [System.Collections.ArrayList]::new() }
        }

        $fullText = $Body.ToUpper()

        foreach ($tblRef in @($refs.Keys)) {
            $ops = [System.Collections.ArrayList]::new()
            # Regex: match SQL DML keywords followed by the table reference
            if ($fullText -match "SELECT\s+.*\bFROM\b.*\b$([regex]::Escape($tblRef))\b") { [void]$ops.Add('SELECT') }
            if ($fullText -match "INSERT\s+INTO\s+$([regex]::Escape($tblRef))\b") { [void]$ops.Add('INSERT') }
            if ($fullText -match "UPDATE\s+$([regex]::Escape($tblRef))\b") { [void]$ops.Add('UPDATE') }
            if ($fullText -match "DELETE\s+FROM\s+$([regex]::Escape($tblRef))\b") { [void]$ops.Add('DELETE') }
            if ($fullText -match "CALL\s+$([regex]::Escape($tblRef))\b") { [void]$ops.Add('CALL') }

            if ($ops.Count -eq 0) { [void]$ops.Add('REFERENCED') }
            $refs[$tblRef] = $ops
        }

        return $refs
    }

    function Get-RoutineCalls {
        param(
            [string]$Body,
            [string[]]$KnownSchemas
        )

        $calls = @()
        if (-not $Body) { return $calls }

        $schemaPattern = ($KnownSchemas | ForEach-Object { [regex]::Escape($_) }) -join '|'

        # Regex: match CALL SCHEMA.ROUTINE_NAME
        #   CALL\s+                    -- literal CALL followed by whitespace
        #   ($schemaPattern)           -- group 1: schema
        #   \.([A-Z_][A-Z0-9_]+)      -- group 2: routine name
        $pattern = "(?i)\bCALL\s+($($schemaPattern))\.([A-Z_][A-Z0-9_]+)\b"
        $matches2 = [regex]::Matches($Body, $pattern)

        foreach ($m in $matches2) {
            $callRef = "$($m.Groups[1].Value.ToUpper()).$($m.Groups[2].Value.ToUpper())"
            if ($calls -notcontains $callRef) { $calls += $callRef }
        }

        return $calls
    }

    function Write-RagMarkdown {
        param(
            [hashtable]$CatalogData,
            [hashtable]$DdlMap,
            [string]$OutputDir,
            [string]$ExportDir,
            [string]$DatabaseName,
            [int]$RefDataMaxRows = 1000,
            [switch]$SkipRefData,
            [string[]]$AlwaysExportTables = @('DBM.TEKSTER')
        )

        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $footer = "`n---`n*Generated: $($timestamp). Source: $($DatabaseName) catalog.*`n"

        $knownSchemas = @('DBM', 'INL', 'LOG', 'TCA', 'TV', 'CRM', 'Dedge', 'FK', 'FKPROC', 'HST')

        $stats = @{ Tables = 0; Views = 0; Procedures = 0; Functions = 0; Triggers = 0; RefData = 0; Total = 0 }

        # ---- FORMAT 1: TABLES ----
        foreach ($tableKey in $CatalogData.Tables.Keys) {
            $table = $CatalogData.Tables[$tableKey]
            $sb = [System.Text.StringBuilder]::new()

            [void]$sb.AppendLine("# Table: $($tableKey)")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("**Schema:** $($table.Schema)")
            [void]$sb.AppendLine("**Table:** $($table.Name)")
            [void]$sb.AppendLine("**Database:** $($DatabaseName)")
            $remark = if ($table.Remarks) { $table.Remarks } else { "" }
            [void]$sb.AppendLine("**Comment:** $($remark)")
            $typeLabel = switch ($table.Type) { 'T' { 'BASE TABLE' } 'S' { 'MATERIALIZED QUERY TABLE' } 'G' { 'STAGING TABLE' } default { $table.Type } }
            [void]$sb.AppendLine("**Table type:** $($typeLabel)")
            $rowCount = if ($CatalogData.ActualCounts -and $CatalogData.ActualCounts.ContainsKey($tableKey)) { $CatalogData.ActualCounts[$tableKey] } else { $table.Card }
            [void]$sb.AppendLine("**Row count:** $($rowCount)")
            $dc = switch ($table.DataCapture) { 'N' { 'NONE' } 'Y' { 'CHANGES' } default { $table.DataCapture } }
            [void]$sb.AppendLine("**Data Capture:** $($dc)")
            [void]$sb.AppendLine("**Created:** $($table.CreateTime)")
            [void]$sb.AppendLine("**Last altered:** $($table.AlterTime)")

            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("## Columns")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("| # | Column | Data Type | Length | Scale | Nullable | Default | Comment |")
            [void]$sb.AppendLine("|---|--------|-----------|--------|-------|----------|---------|---------|")
            $cols = $CatalogData.Columns[$tableKey]
            if ($cols) {
                $sortedCols = $cols | Sort-Object { $_.ColNo }
                foreach ($col in $sortedCols) {
                    $nullable = if ($col.Nulls -eq 'Y') { 'YES' } else { 'NOT NULL' }
                    $def = if ($col.Default) { $col.Default.Trim() } else { '' }
                    $rem = if ($col.Remarks) { $col.Remarks } else { '' }
                    [void]$sb.AppendLine("| $($col.ColNo) | $($col.ColName) | $($col.TypeName) | $($col.Length) | $($col.Scale) | $($nullable) | $($def) | $($rem) |")
                }
            }

            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("## Primary Key")
            [void]$sb.AppendLine("")
            if ($CatalogData.PrimaryKeys.ContainsKey($tableKey)) {
                $pk = $CatalogData.PrimaryKeys[$tableKey]
                [void]$sb.AppendLine("**Constraint name:** $($pk.ConstraintName)")
                [void]$sb.AppendLine("")
                [void]$sb.AppendLine("| Position | Column |")
                [void]$sb.AppendLine("|----------|--------|")
                $sortedPkCols = $pk.Columns | Sort-Object { $_.Seq }
                foreach ($pkCol in $sortedPkCols) {
                    [void]$sb.AppendLine("| $($pkCol.Seq) | $($pkCol.ColName) |")
                }
            }
            else {
                [void]$sb.AppendLine("*(No primary key defined)*")
            }

            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("## Foreign Keys")
            [void]$sb.AppendLine("")
            if ($CatalogData.ForeignKeys.ContainsKey($tableKey)) {
                [void]$sb.AppendLine("| Constraint | Column(s) | References | Referenced Column(s) | Rule (Delete/Update) |")
                [void]$sb.AppendLine("|------------|-----------|------------|---------------------|---------------------|")
                foreach ($fkName in $CatalogData.ForeignKeys[$tableKey].Keys) {
                    $fk = $CatalogData.ForeignKeys[$tableKey][$fkName]
                    $colNames = ($fk.Columns | Sort-Object { $_.Seq } | ForEach-Object { $_.ColName }) -join ', '
                    $refTable = "$($fk.RefSchema).$($fk.RefTable)"
                    $delRule = Format-FkRule -Rule $fk.DeleteRule
                    $updRule = Format-FkRule -Rule $fk.UpdateRule
                    [void]$sb.AppendLine("| $($fk.ConstraintName) | $($colNames) | $($refTable) | | $($delRule) / $($updRule) |")
                }
            }
            else {
                [void]$sb.AppendLine("*(No foreign keys defined)*")
            }

            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("## Referenced By (Incoming FKs)")
            [void]$sb.AppendLine("")
            if ($CatalogData.IncomingFKs.ContainsKey($tableKey)) {
                [void]$sb.AppendLine("| Source Table | Constraint | Column(s) |")
                [void]$sb.AppendLine("|-------------|------------|-----------|")
                foreach ($ifkName in $CatalogData.IncomingFKs[$tableKey].Keys) {
                    $ifk = $CatalogData.IncomingFKs[$tableKey][$ifkName]
                    $colStr = $ifk.Columns -join ', '
                    [void]$sb.AppendLine("| $($ifk.SourceTable) | $($ifk.ConstraintName) | $($colStr) |")
                }
            }
            else {
                [void]$sb.AppendLine("*(No incoming foreign key references)*")
            }

            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("## Indexes")
            [void]$sb.AppendLine("")
            if ($CatalogData.Indexes.ContainsKey($tableKey)) {
                [void]$sb.AppendLine("| Index Name | Schema | Columns | Unique | Clustered |")
                [void]$sb.AppendLine("|------------|--------|---------|--------|-----------|")
                foreach ($idxName in $CatalogData.Indexes[$tableKey].Keys) {
                    $idx = $CatalogData.Indexes[$tableKey][$idxName]
                    $colStr = ($idx.Columns | Sort-Object { $_.Seq } | ForEach-Object { "$($_.ColName) $($_.Order)" }) -join ', '
                    $unique = if ($idx.UniqueRule -eq 'U' -or $idx.UniqueRule -eq 'P') { 'YES' } else { 'NO' }
                    $clustered = if ($idx.IndexType -eq 'CLUS') { 'YES' } else { 'NO' }
                    [void]$sb.AppendLine("| $($idx.IndName) | $($idx.IndSchema) | $($colStr) | $($unique) | $($clustered) |")
                }
            }
            else {
                [void]$sb.AppendLine("*(No indexes defined)*")
            }

            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("## Triggers")
            [void]$sb.AppendLine("")
            if ($CatalogData.TriggersByTable.ContainsKey($tableKey)) {
                [void]$sb.AppendLine("| Trigger Name | Event | Timing | Granularity | Targets Table |")
                [void]$sb.AppendLine("|--------------|-------|--------|-------------|---------------|")
                foreach ($trig in $CatalogData.TriggersByTable[$tableKey]) {
                    $trigEvent = Format-TriggerEvent -TrigEvent $trig.Event
                    $timing = Format-TriggerTiming -Timing $trig.Timing
                    $gran = if ($trig.Granularity -eq 'S') { 'FOR EACH STATEMENT' } else { 'FOR EACH ROW' }
                    [void]$sb.AppendLine("| $($trig.TrigName) | $($trigEvent) | $($timing) | $($gran) | $($tableKey) |")
                }
            }
            else {
                [void]$sb.AppendLine("*(No triggers defined)*")
            }

            $isAlwaysExport = $AlwaysExportTables -contains $tableKey
            $includeInlineRefData = (-not $SkipRefData) -and (($rowCount -ge 0 -and $rowCount -lt $RefDataMaxRows) -or $isAlwaysExport)

            if ($includeInlineRefData) {
                $refDelFile = Join-Path $ExportDir "refdata\$($tableKey).del"
                if (Test-Path $refDelFile) {
                    $refBytes = [System.IO.File]::ReadAllBytes($refDelFile)
                    $refText  = [System.Text.Encoding]::GetEncoding(1252).GetString($refBytes)
                    $refLines = $refText -split "`n"
                    if ($refLines -and $refLines.Count -gt 0) {
                        [void]$sb.AppendLine("")
                        [void]$sb.AppendLine("## Reference Data (Full Content)")
                        [void]$sb.AppendLine("")
                        [void]$sb.AppendLine("*Row count: $($refLines.Count). Exported: $(Get-Date -Format 'yyyy-MM-dd').*")
                        [void]$sb.AppendLine("")

                        if ($isAlwaysExport) {
                            [void]$sb.AppendLine("> **AI Context:** This table is a cross-cutting reference data table.")
                            [void]$sb.AppendLine("> When analyzing any other table that has columns for type codes, status codes,")
                            [void]$sb.AppendLine("> category codes, or similar coded values **without a formal foreign key**,")
                            [void]$sb.AppendLine("> check this table (``$($tableKey)``) for matching descriptions and context.")
                            [void]$sb.AppendLine("> Many tables use codes from ``$($tableKey)`` without FK constraints.")
                            [void]$sb.AppendLine("")
                        }

                        $colHeaders = if ($cols) { ($cols | Sort-Object { $_.ColNo } | ForEach-Object { $_.ColName }) } else { @() }
                        if ($colHeaders.Count -gt 0) {
                            [void]$sb.AppendLine("| $($colHeaders -join ' | ') |")
                            $dashes = ($colHeaders | ForEach-Object { '---' }) -join ' | '
                            [void]$sb.AppendLine("| $($dashes) |")
                        }

                        foreach ($refLine in $refLines) {
                            $fields = Parse-DelLine -Line $refLine
                            $formatted = $fields | ForEach-Object {
                                $v = $_.Trim()
                                if ($v -eq '' -or $null -eq $v) { '*(null)*' } else { $v }
                            }
                            [void]$sb.AppendLine("| $($formatted -join ' | ') |")
                        }
                    }
                }
            }

            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("## DDL")
            [void]$sb.AppendLine("")
            if ($DdlMap.ContainsKey($tableKey)) {
                [void]$sb.AppendLine('```sql')
                foreach ($ddlStmt in $DdlMap[$tableKey]) {
                    [void]$sb.AppendLine($ddlStmt)
                    [void]$sb.AppendLine("")
                }
                [void]$sb.AppendLine('```')
            }
            else {
                [void]$sb.AppendLine("*(DDL not available)*")
            }

            [void]$sb.Append($footer)

            $filePath = Join-Path $OutputDir "tables\$($tableKey).md"
            Set-Content -Path $filePath -Value $sb.ToString() -Encoding UTF8 -NoNewline
            $stats.Tables++
        }

        # ---- FORMAT 2: VIEWS ----
        foreach ($viewKey in $CatalogData.Views.Keys) {
            $view = $CatalogData.Views[$viewKey]
            $sb = [System.Text.StringBuilder]::new()

            [void]$sb.AppendLine("# View: $($viewKey)")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("**Schema:** $($view.Schema)")
            [void]$sb.AppendLine("**View:** $($view.Name)")
            [void]$sb.AppendLine("**Database:** $($DatabaseName)")
            $ro = if ($view.ReadOnly -eq 'Y') { 'YES' } else { 'NO' }
            [void]$sb.AppendLine("**Read-only:** $($ro)")
            [void]$sb.AppendLine("**Valid:** $($view.Valid)")

            $viewRemarks = ""
            if ($CatalogData.Tables.ContainsKey($viewKey)) {
                $viewRemarks = $CatalogData.Tables[$viewKey].Remarks
            }
            [void]$sb.AppendLine("**Comment:** $($viewRemarks)")

            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("## Columns")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("| # | Column | Data Type | Length | Scale | Nullable |")
            [void]$sb.AppendLine("|---|--------|-----------|--------|-------|----------|")
            $vcols = $CatalogData.ViewColumns[$viewKey]
            if ($vcols) {
                $sortedVcols = $vcols | Sort-Object { $_.ColNo }
                foreach ($vc in $sortedVcols) {
                    $nullable = if ($vc.Nulls -eq 'Y') { 'YES' } else { 'NOT NULL' }
                    [void]$sb.AppendLine("| $($vc.ColNo) | $($vc.ColName) | $($vc.TypeName) | $($vc.Length) | $($vc.Scale) | $($nullable) |")
                }
            }

            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("## Source Tables")
            [void]$sb.AppendLine("")
            if ($CatalogData.ViewDeps.ContainsKey($viewKey)) {
                [void]$sb.AppendLine("| Table | Schema | Dependency Type |")
                [void]$sb.AppendLine("|-------|--------|----------------|")
                foreach ($dep in $CatalogData.ViewDeps[$viewKey]) {
                    $depType = switch ($dep.BType) {
                        'T' { 'Table' } 'V' { 'View' } 'A' { 'Alias' }
                        'N' { 'Nickname' } 'S' { 'MQT' } default { $dep.BType }
                    }
                    [void]$sb.AppendLine("| $($dep.BName) | $($dep.BSchema) | $($depType) |")
                }
            }

            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("## DDL")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine('```sql')
            if ($view.Text) {
                [void]$sb.AppendLine($view.Text)
            }
            elseif ($DdlMap.ContainsKey($viewKey)) {
                foreach ($ddlStmt in $DdlMap[$viewKey]) {
                    [void]$sb.AppendLine($ddlStmt)
                }
            }
            else {
                [void]$sb.AppendLine("-- DDL not available")
            }
            [void]$sb.AppendLine('```')

            [void]$sb.Append($footer)

            $filePath = Join-Path $OutputDir "views\$($viewKey).md"
            Set-Content -Path $filePath -Value $sb.ToString() -Encoding UTF8 -NoNewline
            $stats.Views++
        }

        # ---- FORMAT 3 & 4: PROCEDURES AND FUNCTIONS ----
        $procCount = @{}
        $funcCount = @{}
        foreach ($routKey in $CatalogData.Routines.Keys) {
            $routine = $CatalogData.Routines[$routKey]
            $nameKey = "$($routine.Schema).$($routine.Name)"
            $isProcedure = ($routine.RoutineType -eq 'P')
            $isFunction = ($routine.RoutineType -eq 'F')

            if (-not $isProcedure -and -not $isFunction) { continue }

            $sb = [System.Text.StringBuilder]::new()

            $parms = @()
            if ($CatalogData.RoutineParms.ContainsKey($routKey)) {
                $parms = $CatalogData.RoutineParms[$routKey] | Sort-Object { $_.Ordinal }
            }

            if ($isProcedure) {
                if (-not $procCount.ContainsKey($nameKey)) { $procCount[$nameKey] = 0 }
                $procCount[$nameKey]++

                [void]$sb.AppendLine("# Procedure: $($nameKey)")
                [void]$sb.AppendLine("")
                [void]$sb.AppendLine("**Schema:** $($routine.Schema)")
                [void]$sb.AppendLine("**Procedure:** $($routine.Name)")
                [void]$sb.AppendLine("**Database:** $($DatabaseName)")
                [void]$sb.AppendLine("**Language:** $($routine.Language)")
                [void]$sb.AppendLine("**SQL Data Access:** $($routine.SqlDataAccess)")
                $det = if ($routine.Deterministic -eq 'Y') { 'YES' } else { 'NO' }
                [void]$sb.AppendLine("**Deterministic:** $($det)")
                [void]$sb.AppendLine("**Created:** $($routine.CreateTime)")
                [void]$sb.AppendLine("**Comment:** $($routine.Remarks)")

                [void]$sb.AppendLine("")
                [void]$sb.AppendLine("## Parameters")
                [void]$sb.AppendLine("")
                if ($parms.Count -gt 0) {
                    [void]$sb.AppendLine("| # | Name | Direction | Data Type | Length | Scale |")
                    [void]$sb.AppendLine("|---|------|-----------|-----------|--------|-------|")
                    foreach ($p in $parms) {
                        if ($p.RowType -eq 'C') { continue }
                        $dir = switch ($p.RowType) { 'P' { 'IN' } 'O' { 'OUT' } 'B' { 'INOUT' } default { $p.RowType } }
                        [void]$sb.AppendLine("| $($p.Ordinal) | $($p.ParmName) | $($dir) | $($p.TypeName) | $($p.Length) | $($p.Scale) |")
                    }
                }
                else {
                    [void]$sb.AppendLine("*(No parameters)*")
                }
            }
            else {
                if (-not $funcCount.ContainsKey($nameKey)) { $funcCount[$nameKey] = 0 }
                $funcCount[$nameKey]++

                [void]$sb.AppendLine("# Function: $($nameKey)")
                [void]$sb.AppendLine("")
                [void]$sb.AppendLine("**Schema:** $($routine.Schema)")
                [void]$sb.AppendLine("**Function:** $($routine.Name)")
                [void]$sb.AppendLine("**Database:** $($DatabaseName)")
                [void]$sb.AppendLine("**Language:** $($routine.Language)")
                [void]$sb.AppendLine("**SQL Data Access:** $($routine.SqlDataAccess)")
                $det = if ($routine.Deterministic -eq 'Y') { 'YES' } else { 'NO' }
                [void]$sb.AppendLine("**Deterministic:** $($det)")

                $returnParm = $parms | Where-Object { $_.RowType -eq 'C' } | Select-Object -First 1
                $retType = if ($returnParm) { "$($returnParm.TypeName)($($returnParm.Length),$($returnParm.Scale))" } else { 'UNKNOWN' }
                [void]$sb.AppendLine("**Returns:** $($retType)")

                $hasTableReturn = ($parms | Where-Object { $_.RowType -eq 'C' }).Count -gt 1
                $returnKind = if ($hasTableReturn) { 'TABLE' } else { 'SCALAR' }
                [void]$sb.AppendLine("**Return type:** $($returnKind)")
                [void]$sb.AppendLine("**Created:** $($routine.CreateTime)")
                [void]$sb.AppendLine("**Comment:** $($routine.Remarks)")

                [void]$sb.AppendLine("")
                [void]$sb.AppendLine("## Parameters")
                [void]$sb.AppendLine("")
                $inputParms = $parms | Where-Object { $_.RowType -ne 'C' }
                if ($inputParms.Count -gt 0) {
                    [void]$sb.AppendLine("| # | Name | Data Type | Length | Scale |")
                    [void]$sb.AppendLine("|---|------|-----------|--------|-------|")
                    foreach ($p in $inputParms) {
                        [void]$sb.AppendLine("| $($p.Ordinal) | $($p.ParmName) | $($p.TypeName) | $($p.Length) | $($p.Scale) |")
                    }
                }
                else {
                    [void]$sb.AppendLine("*(No parameters)*")
                }
            }

            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("## Tables Referenced")
            [void]$sb.AppendLine("")
            $refs = Get-TableReferences -Body $routine.Text -KnownSchemas $knownSchemas
            if ($refs.Count -gt 0) {
                [void]$sb.AppendLine("| Table | Operations |")
                [void]$sb.AppendLine("|-------|-----------|")
                foreach ($ref in $refs.GetEnumerator()) {
                    [void]$sb.AppendLine("| $($ref.Key) | $($ref.Value -join ', ') |")
                }
            }
            else {
                [void]$sb.AppendLine("*(No table references found in body)*")
            }

            $calls = Get-RoutineCalls -Body $routine.Text -KnownSchemas $knownSchemas
            if ($isProcedure) {
                [void]$sb.AppendLine("")
                [void]$sb.AppendLine("## Procedures Called")
                [void]$sb.AppendLine("")
                if ($calls.Count -gt 0) {
                    [void]$sb.AppendLine("| Procedure |")
                    [void]$sb.AppendLine("|-----------|")
                    foreach ($call in $calls) {
                        [void]$sb.AppendLine("| $($call) |")
                    }
                }
                else {
                    [void]$sb.AppendLine("*(No procedure calls found)*")
                }
            }
            else {
                [void]$sb.AppendLine("")
                [void]$sb.AppendLine("## Functions/Procedures Called")
                [void]$sb.AppendLine("")
                if ($calls.Count -gt 0) {
                    [void]$sb.AppendLine("| Routine | Type |")
                    [void]$sb.AppendLine("|---------|------|")
                    foreach ($call in $calls) {
                        [void]$sb.AppendLine("| $($call) | PROCEDURE |")
                    }
                }
                else {
                    [void]$sb.AppendLine("*(No routine calls found)*")
                }
            }

            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("## Body")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine('```sql')
            if ($routine.Text) {
                [void]$sb.AppendLine($routine.Text)
            }
            elseif ($DdlMap.ContainsKey($nameKey)) {
                foreach ($ddlStmt in $DdlMap[$nameKey]) { [void]$sb.AppendLine($ddlStmt) }
            }
            else {
                [void]$sb.AppendLine("-- Body not available (external routine or not stored in catalog)")
            }
            [void]$sb.AppendLine('```')

            [void]$sb.Append($footer)

            if ($isProcedure) {
                $fileName = if ($procCount[$nameKey] -gt 1) { "$($nameKey).$($procCount[$nameKey]).md" } else { "$($nameKey).md" }
                $filePath = Join-Path $OutputDir "procedures\$($fileName)"
                $stats.Procedures++
            }
            else {
                $fileName = if ($funcCount[$nameKey] -gt 1) { "$($nameKey).$($funcCount[$nameKey]).md" } else { "$($nameKey).md" }
                $filePath = Join-Path $OutputDir "functions\$($fileName)"
                $stats.Functions++
            }

            Set-Content -Path $filePath -Value $sb.ToString() -Encoding UTF8 -NoNewline
        }

        # ---- FORMAT 5: TRIGGERS ----
        foreach ($trigKey in $CatalogData.Triggers.Keys) {
            $trig = $CatalogData.Triggers[$trigKey]
            $sb = [System.Text.StringBuilder]::new()

            [void]$sb.AppendLine("# Trigger: $($trig.TrigSchema).$($trig.TrigName)")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("**Schema:** $($trig.TrigSchema)")
            [void]$sb.AppendLine("**Trigger:** $($trig.TrigName)")
            [void]$sb.AppendLine("**Database:** $($DatabaseName)")
            [void]$sb.AppendLine("**Table:** $($trig.TabSchema).$($trig.TabName)")
            $trigEvent = Format-TriggerEvent -TrigEvent $trig.Event
            [void]$sb.AppendLine("**Event:** $($trigEvent)")
            $timing = Format-TriggerTiming -Timing $trig.Timing
            [void]$sb.AppendLine("**Timing:** $($timing)")
            $gran = if ($trig.Granularity -eq 'S') { 'FOR EACH STATEMENT' } else { 'FOR EACH ROW' }
            [void]$sb.AppendLine("**Granularity:** $($gran)")

            if ($trig.Event -eq 'U' -and $trig.Text -match 'UPDATE\s+OF\s+([^)]+?)\s+ON') {
                [void]$sb.AppendLine("**Update columns:** $($matches[1].Trim())")
            }
            else {
                [void]$sb.AppendLine("**Update columns:** all")
            }

            [void]$sb.AppendLine("**Valid:** $($trig.Valid)")
            [void]$sb.AppendLine("**Created:** $($trig.CreateTime)")
            [void]$sb.AppendLine("**Comment:** $($trig.Remarks)")

            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("## Tables Referenced")
            [void]$sb.AppendLine("")
            $refs = Get-TableReferences -Body $trig.Text -KnownSchemas $knownSchemas
            $ownTable = "$($trig.TabSchema).$($trig.TabName)"
            $filteredRefs = @{}
            foreach ($r in $refs.GetEnumerator()) {
                if ($r.Key -ne $ownTable) { $filteredRefs[$r.Key] = $r.Value }
            }
            if ($filteredRefs.Count -gt 0) {
                [void]$sb.AppendLine("| Table | Operation |")
                [void]$sb.AppendLine("|-------|-----------|")
                foreach ($ref in $filteredRefs.GetEnumerator()) {
                    [void]$sb.AppendLine("| $($ref.Key) | $($ref.Value -join ', ') |")
                }
            }
            else {
                [void]$sb.AppendLine("*(No external table references)*")
            }

            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("## Body")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine('```sql')
            if ($trig.Text) {
                [void]$sb.AppendLine($trig.Text)
            }
            elseif ($DdlMap.ContainsKey("$($trig.TrigSchema).$($trig.TrigName)")) {
                foreach ($ddlStmt in $DdlMap["$($trig.TrigSchema).$($trig.TrigName)"]) { [void]$sb.AppendLine($ddlStmt) }
            }
            else {
                [void]$sb.AppendLine("-- Body not available")
            }
            [void]$sb.AppendLine('```')

            [void]$sb.Append($footer)

            $filePath = Join-Path $OutputDir "triggers\$($trig.TabSchema).$($trig.TabName).$($trig.TrigName).md"
            Set-Content -Path $filePath -Value $sb.ToString() -Encoding UTF8 -NoNewline
            $stats.Triggers++
        }

        # ---- FORMAT 6: REFERENCE DATA (SEPARATE FILES) ----
        if (-not $SkipRefData) {
            $credentialCols = @('BRUKERID', 'PASSORD', 'PASSWORD', 'TOKEN', 'SECRET')
            # Regex: table names containing lookup-like keywords
            $lookupPattern = '(KODE|KODER|TYPE|TYPER|PARAM|GRUPPE|STATUS|TEKST|SONE|TABELL|TAB)'

            foreach ($tableKey in $CatalogData.Tables.Keys) {
                $table = $CatalogData.Tables[$tableKey]
                $isAlwaysExport = $AlwaysExportTables -contains $tableKey
                $rowCount = if ($CatalogData.ActualCounts -and $CatalogData.ActualCounts.ContainsKey($tableKey)) { $CatalogData.ActualCounts[$tableKey] } else { $table.Card }

                if (-not $isAlwaysExport) {
                    if ($rowCount -lt $RefDataMaxRows -or $rowCount -gt 5000) { continue }
                }
                if ($table.Schema -eq 'LOG') { continue }
                if ($table.Name -match '(_HIST$|^H_|_TEMP$|^TMP_)') { continue }

                $tableCols = $CatalogData.Columns[$tableKey]
                if ($tableCols) {
                    $hasCredCol = $false
                    foreach ($col in $tableCols) {
                        if ($credentialCols -contains $col.ColName) { $hasCredCol = $true; break }
                    }
                    if ($hasCredCol) { continue }
                }

                if (-not $isAlwaysExport) {
                    $isLookup = ($table.Name -match "^Z_") -or ($table.Name -match $lookupPattern)
                    if (-not $isLookup) {
                        if ($tableCols -and $tableCols.Count -le 10) {
                            $hasKeyDesc = ($tableCols | Where-Object { $_.ColName -match '(KODE|TYPE|GRUPPE|ID)' }) -and
                                          ($tableCols | Where-Object { $_.ColName -match '(NAVN|TEKST|BESKRIVELSE|DESC)' })
                            if ($hasKeyDesc) { $isLookup = $true }
                        }
                    }
                    if (-not $isLookup) { continue }
                }

                $refDelFile = Join-Path $ExportDir "refdata\$($tableKey).del"
                if (-not (Test-Path $refDelFile)) { continue }

                $refBytes2 = [System.IO.File]::ReadAllBytes($refDelFile)
                $refText2  = [System.Text.Encoding]::GetEncoding(1252).GetString($refBytes2)
                $refLines  = $refText2 -split "`n"
                if (-not $refLines -or $refLines.Count -eq 0) { continue }

                $sb = [System.Text.StringBuilder]::new()
                [void]$sb.AppendLine("# Reference Data: $($tableKey)")
                [void]$sb.AppendLine("")
                [void]$sb.AppendLine("**Schema:** $($table.Schema)")
                [void]$sb.AppendLine("**Table:** $($table.Name)")
                [void]$sb.AppendLine("**Table definition:** See ``tables/$($tableKey).md``")
                [void]$sb.AppendLine("**Row count:** $($refLines.Count)")
                [void]$sb.AppendLine("**Exported:** $(Get-Date -Format 'yyyy-MM-dd')")
                [void]$sb.AppendLine("")

                if ($isAlwaysExport) {
                    [void]$sb.AppendLine("> **AI Context:** This table is a cross-cutting reference data table that provides")
                    [void]$sb.AppendLine("> descriptive text for status codes, type codes, and category codes used throughout")
                    [void]$sb.AppendLine("> the system. Many tables reference codes from ``$($tableKey)`` **without formal")
                    [void]$sb.AppendLine("> foreign key constraints**. When encountering a type, status, or code column in")
                    [void]$sb.AppendLine("> another table that has no FK, look up matching values in this table for context.")
                    [void]$sb.AppendLine("")
                }

                $cols = $CatalogData.Columns[$tableKey]
                $colHeaders = if ($cols) { ($cols | Sort-Object { $_.ColNo } | ForEach-Object { $_.ColName }) } else { @() }
                if ($colHeaders.Count -gt 0) {
                    [void]$sb.AppendLine("| $($colHeaders -join ' | ') |")
                    $dashes = ($colHeaders | ForEach-Object { '---' }) -join ' | '
                    [void]$sb.AppendLine("| $($dashes) |")
                }

                foreach ($refLine in $refLines) {
                    $fields = Parse-DelLine -Line $refLine
                    $formatted = $fields | ForEach-Object {
                        $v = $_.Trim()
                        if ($v -eq '' -or $null -eq $v) { '*(null)*' } else { $v }
                    }
                    [void]$sb.AppendLine("| $($formatted -join ' | ') |")
                }

                [void]$sb.Append($footer)

                $filePath = Join-Path $OutputDir "reference-data\$($tableKey).DATA.md"
                Set-Content -Path $filePath -Value $sb.ToString() -Encoding UTF8 -NoNewline
                $stats.RefData++
            }
        }

        $stats.Total = $stats.Tables + $stats.Views + $stats.Procedures + $stats.Functions + $stats.Triggers + $stats.RefData
        return $stats
    }

    # ── End of inline helpers ────────────────────────────────────────────────

    $phaseOrder = @('1a', '1b', '1c', '2a', '2b')
    $resumeIndex = 0
    if ($ResumeFrom) { $resumeIndex = $phaseOrder.IndexOf($ResumeFrom) }

    function ShouldRun([string]$phase) {
        $idx = $phaseOrder.IndexOf($phase)
        return $idx -ge $resumeIndex
    }

    $defaultSchemasByDb = @{
        'BASISPRO' = @('DBM', 'INL', 'LOG', 'TCA', 'TV', 'CRM', 'Dedge', 'FK', 'FKPROC')
        'BASISHST' = @('DBM', 'INL', 'LOG', 'TCA', 'TV', 'CRM', 'Dedge', 'FK', 'FKPROC', 'HST')
        'FKKONTO'  = @('DBM', 'INL', 'LOG', 'TCA', 'TV', 'CRM', 'Dedge', 'FK', 'FKPROC')
        'COBDOK'   = @('DBM', 'ROA', 'TV', 'RDBI', 'Q')
    }

    $defaultRagLibraryPath = 'C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\AiDoc.Library\Dedge-code\_databases'

    function Export-SingleDatabase {
        param(
            [string]$DatabaseName,
            [string]$InstanceName,
            [string[]]$DbSchemas,
            [int]$RefDataMaxRows,
            [switch]$SkipRefData,
            [switch]$SkipDdl,
            [string[]]$AlwaysExportTables,
            [string]$ResumeFrom,
            [switch]$SkipRagCopy,
            [string]$RagLibraryPath
        )

        $dbNameLower = $DatabaseName.ToLower()
        $appDataPath = Join-Path $env:TEMP "Db2-ExportForRag\$($dbNameLower)"
        if (-not (Test-Path $appDataPath)) {
            New-Item -Path $appDataPath -ItemType Directory -Force | Out-Null
        }
        Set-OverrideAppDataFolder -Path $appDataPath

        Write-LogMessage "=== Exporting database: $($DatabaseName) ===" -Level INFO
        Write-LogMessage "Work folder: $($appDataPath)" -Level INFO

        $exportDir = Join-Path $appDataPath "_export"
        $ddlDir = Join-Path $appDataPath "_ddl"
        $outputDir = Join-Path $appDataPath "Dedge-db2"

        foreach ($dir in @($exportDir, $ddlDir, $outputDir)) {
            if (-not (Test-Path $dir)) {
                New-Item -Path $dir -ItemType Directory -Force | Out-Null
            }
        }

        $schemaFilter = ($DbSchemas | ForEach-Object { "'$($_)'" }) -join ','

        ##########################################################
        # Phase 1: Data Collection
        ##########################################################

        $ddlFile = Join-Path $ddlDir "db2look_full.sql"
        if (ShouldRun '1a') {
            if (-not $SkipDdl) {
                Write-LogMessage "Phase 1a: Running db2look for $($DatabaseName)" -Level INFO
                $ddlCommands = @()
                $ddlCommands += "set DB2INSTANCE=$($InstanceName)"
                $ddlCommands += "db2look -d $($DatabaseName) -e -l -td @ -o `"$($ddlFile)`""

                Invoke-Db2ContentAsScript -Content $ddlCommands -ExecutionType BAT `
                    -FileName (Join-Path $appDataPath "db2look_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors
                Write-LogMessage "Phase 1a: db2look complete -> $($ddlFile)" -Level INFO
            }
            else {
                Write-LogMessage "Phase 1a: SKIPPED (-SkipDdl). Using existing $($ddlFile)" -Level INFO
            }
        }
        else {
            Write-LogMessage "Phase 1a: SKIPPED (resuming from $($ResumeFrom)). Using existing $($ddlFile)" -Level INFO
        }

        if (ShouldRun '1b') {
            Write-LogMessage "Phase 1b: Exporting SYSCAT catalog data for $($DatabaseName)" -Level INFO
            $catalogData = Export-CatalogData -InstanceName $InstanceName -DatabaseName $DatabaseName `
                -SchemaFilter $schemaFilter -ExportDir $exportDir -AppDataPath $appDataPath
        }
        else {
            Write-LogMessage "Phase 1b: SKIPPED (resuming from $($ResumeFrom)). Parsing existing DEL files." -Level INFO
            $catalogData = Parse-AllDelFiles -ExportDir $exportDir
        }
        Write-LogMessage "Phase 1b: Catalog data ready ($($catalogData.TableCount) tables, $($catalogData.ViewCount) views, $($catalogData.RoutineCount) routines, $($catalogData.TriggerCount) triggers)" -Level INFO

        if (ShouldRun '1c') {
            if (-not $SkipRefData) {
                Write-LogMessage "Phase 1c: Exporting reference data for small tables" -Level INFO
                Export-ReferenceData -InstanceName $InstanceName -DatabaseName $DatabaseName `
                    -CatalogData $catalogData -ExportDir $exportDir -AppDataPath $appDataPath -Schemas $DbSchemas `
                    -RefDataMaxRows $RefDataMaxRows -AlwaysExportTables $AlwaysExportTables
                Write-LogMessage "Phase 1c: Reference data export complete" -Level INFO
            }
            else {
                Write-LogMessage "Phase 1c: SKIPPED (-SkipRefData)" -Level INFO
            }
        }
        else {
            Write-LogMessage "Phase 1c: SKIPPED (resuming from $($ResumeFrom)). Using existing reference data." -Level INFO
        }

        ##########################################################
        # Phase 2: Markdown Generation
        ##########################################################

        $ddlMap = @{}
        if (ShouldRun '2a') {
            Write-LogMessage "Phase 2a: Parsing db2look output" -Level INFO
            if (Test-Path $ddlFile) {
                $ddlMap = Parse-Db2LookDdl -DdlFilePath $ddlFile
                Write-LogMessage "Phase 2a: Parsed DDL for $($ddlMap.Count) objects" -Level INFO
            }
            else {
                Write-LogMessage "Phase 2a: No DDL file found at $($ddlFile). Markdown will have empty DDL sections." -Level WARN
            }
        }
        else {
            Write-LogMessage "Phase 2a: SKIPPED (resuming from $($ResumeFrom))." -Level INFO
            if (Test-Path $ddlFile) {
                $ddlMap = Parse-Db2LookDdl -DdlFilePath $ddlFile
                Write-LogMessage "Phase 2a: Re-parsed DDL for $($ddlMap.Count) objects (needed by 2b)" -Level INFO
            }
        }

        Write-LogMessage "Phase 2b: Generating markdown files" -Level INFO

        foreach ($subDir in @("tables", "views", "procedures", "functions", "triggers", "reference-data")) {
            $targetDir = Join-Path $outputDir $subDir
            if (-not (Test-Path $targetDir)) {
                New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
            }
        }

        $stats = Write-RagMarkdown -CatalogData $catalogData -DdlMap $ddlMap `
            -OutputDir $outputDir -ExportDir $exportDir -DatabaseName $DatabaseName `
            -RefDataMaxRows $RefDataMaxRows -SkipRefData:$SkipRefData -AlwaysExportTables $AlwaysExportTables

        Write-LogMessage "Phase 2b: Markdown generation complete for $($DatabaseName)" -Level INFO
        Write-LogMessage "  Tables:         $($stats.Tables)" -Level INFO
        Write-LogMessage "  Views:          $($stats.Views)" -Level INFO
        Write-LogMessage "  Procedures:     $($stats.Procedures)" -Level INFO
        Write-LogMessage "  Functions:      $($stats.Functions)" -Level INFO
        Write-LogMessage "  Triggers:       $($stats.Triggers)" -Level INFO
        Write-LogMessage "  Reference data: $($stats.RefData)" -Level INFO
        Write-LogMessage "  Total files:    $($stats.Total)" -Level INFO
        Write-LogMessage "Output: $($outputDir)" -Level INFO

        ##########################################################
        # Phase 3: Copy to RAG library
        ##########################################################
        if (-not $SkipRagCopy) {
            $ragTargetDir = Join-Path $RagLibraryPath $dbNameLower
            Write-LogMessage "Phase 3: Copying markdown to RAG library -> $($ragTargetDir)" -Level INFO

            if (-not (Test-Path -LiteralPath $ragTargetDir)) {
                New-Item -ItemType Directory -Path $ragTargetDir -Force | Out-Null
            }

            $copyCount = 0
            Get-ChildItem -LiteralPath $outputDir -Filter '*.md' -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                $relPath = $_.FullName.Substring($outputDir.Length + 1)
                $destPath = Join-Path $ragTargetDir $relPath
                $destDir = Split-Path $destPath -Parent
                if (-not (Test-Path -LiteralPath $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                Copy-Item -LiteralPath $_.FullName -Destination $destPath -Force
                $copyCount++
            }
            Write-LogMessage "Phase 3: Copied $($copyCount) markdown file(s) to $($ragTargetDir)" -Level INFO
        }
        else {
            Write-LogMessage "Phase 3: SKIPPED (-SkipRagCopy)" -Level INFO
        }

        Reset-OverrideAppDataFolder
        return $stats
    }

    # ============================================================
    # Main: loop over all requested databases
    # ============================================================
    try {
        Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED
        if ($ResumeFrom) {
            Write-LogMessage "RESUMING from phase $($ResumeFrom) - skipping phases before it" -Level INFO
        }

        if ([string]::IsNullOrWhiteSpace($RagLibraryPath)) {
            $candidatePaths = @(
                $defaultRagLibraryPath,
                'C:\opt\src\AiDoc\AiDoc.Library\Dedge-code\_databases'
            )
            if ($env:OptPath) {
                $candidatePaths += Join-Path $env:OptPath 'data\AiDoc.Library\Dedge-code\_databases'
            }
            foreach ($candidate in $candidatePaths) {
                if (Test-Path -LiteralPath $candidate) {
                    $RagLibraryPath = $candidate
                    break
                }
            }
            if ([string]::IsNullOrWhiteSpace($RagLibraryPath)) {
                Write-LogMessage "RAG library path not reachable. Will skip copy step. Use -RagLibraryPath to specify." -Level WARN
            }
        }

        $allStats = @{}
        foreach ($dbName in $DatabaseNames) {
            $dbSchemas = $Schemas
            if (-not $dbSchemas -or $dbSchemas.Count -eq 0) {
                $dbSchemas = $defaultSchemasByDb[$dbName.ToUpper()]
                if (-not $dbSchemas) {
                    $dbSchemas = @('DBM', 'INL', 'LOG', 'TCA', 'TV', 'CRM', 'Dedge', 'FK', 'FKPROC')
                }
            }

            $skipCopy = $SkipRagCopy -or [string]::IsNullOrWhiteSpace($RagLibraryPath)
            $dbStats = Export-SingleDatabase -DatabaseName $dbName -InstanceName $InstanceName `
                -DbSchemas $dbSchemas -RefDataMaxRows $RefDataMaxRows `
                -SkipRefData:$SkipRefData -SkipDdl:$SkipDdl `
                -AlwaysExportTables $AlwaysExportTables -ResumeFrom $ResumeFrom `
                -SkipRagCopy:$skipCopy -RagLibraryPath $RagLibraryPath

            $allStats[$dbName] = $dbStats
        }

        Write-LogMessage "=== All databases exported ===" -Level INFO
        foreach ($dbName in $allStats.Keys) {
            $s = $allStats[$dbName]
            Write-LogMessage "  $($dbName): $($s.Total) files (T:$($s.Tables) V:$($s.Views) P:$($s.Procedures) F:$($s.Functions) Tr:$($s.Triggers) R:$($s.RefData))" -Level INFO
        }

        Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
    }
    catch {
        Write-LogMessage "DB2 export error: $($_.Exception.Message)" -Level ERROR -Exception $_
        Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
        throw
    }
    finally {
        Reset-OverrideAppDataFolder
    }
}

function Update-DedgeCodeReposConfig {
    <#
    .SYNOPSIS
        Clones/pulls all Dedge repos and updates .Dedge-rag-config.json.
    .DESCRIPTION
        Uses Azure-DevOpsCloneRepositories.ps1 to clone or pull repos into
        library\Dedge-code\code\, then scans for discovered repos and
        updates the repos array in .Dedge-rag-config.json.
    #>
    param(
        [string]$AiDocRoot,
        [switch]$FetchOnly,
        [switch]$SkipConfigUpdate
    )

    if (-not $env:OptPath) { throw 'Environment variable OptPath is not set.' }

    # ── Resolve AiDoc root ──────────────────────────────────────────────────
    if (-not $AiDocRoot) {
        if ($env:USERNAME -in @('FKGEISTA', 'FKSVEERI')) {
            $AiDocRoot = Join-Path $env:OptPath 'src\AiDoc'
        }
        else {
            $AiDocRoot = Join-Path $env:OptPath 'FkPythonApps\AiDoc'
        }
    }

    $ragDir = Join-Path $libraryDir 'Dedge-code'
    $codeDir = Join-Path $ragDir 'code'
    $configFile = Join-Path $ragDir '.Dedge-rag-config.json'

    Write-LogMessage "Sync-DedgeCodeRepos starting" -Level INFO
    Write-LogMessage "  AiDocRoot:  $($AiDocRoot)" -Level INFO
    Write-LogMessage "  Code dir:   $($codeDir)" -Level INFO

    if (-not (Test-Path -LiteralPath $codeDir)) {
        New-Item -ItemType Directory -Path $codeDir -Force | Out-Null
        Write-LogMessage "Created code directory: $($codeDir)" -Level INFO
    }

    # ── Clone / Pull repos ──────────────────────────────────────────────────
    $cloneScriptCandidates = @(
        (Join-Path $env:OptPath 'DedgePshApps\Azure-DevOpsCloneRepositories\Azure-DevOpsCloneRepositories.ps1'),
        (Join-Path $env:OptPath 'src\DedgePsh\DevTools\CodingTools\Azure-DevOpsCloneRepositories\Azure-DevOpsCloneRepositories.ps1')
    )
    $cloneScript = $null
    foreach ($c in $cloneScriptCandidates) {
        if (Test-Path -LiteralPath $c) { $cloneScript = $c; break }
    }

    $cloneUsed = $false
    if ($cloneScript -and -not $FetchOnly) {
        Write-LogMessage "Using clone script: $($cloneScript)" -Level INFO
        try {
            & $cloneScript -CloneAll -TargetPath $codeDir -PullOnlyIfAllExist
            $cloneUsed = $true
            Write-LogMessage "Clone/pull via Azure-DevOpsCloneRepositories complete" -Level INFO
        }
        catch {
            Write-LogMessage "Clone script failed: $($_.Exception.Message). Falling back to manual git operations." -Level WARN
        }
    }

    if (-not $cloneUsed) {
        $gitCmd = if ($FetchOnly) { 'fetch' } else { 'pull' }
        Write-LogMessage "Running git $($gitCmd) on existing repos in $($codeDir)" -Level INFO

        $repoDirs = Get-ChildItem -LiteralPath $codeDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName '.git') -PathType Container }

        if ($repoDirs.Count -eq 0) {
            Write-LogMessage "No git repos found in $($codeDir). Run with a clone script available for initial clone." -Level WARN
        }
        else {
            foreach ($repo in $repoDirs) {
                Write-LogMessage "  git $($gitCmd) $($repo.Name)..." -Level INFO
                try {
                    Push-Location -LiteralPath $repo.FullName
                    $null = & git $gitCmd 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-LogMessage "  $($repo.Name): OK" -Level INFO
                    }
                    else {
                        Write-LogMessage "  $($repo.Name): git $($gitCmd) exit $($LASTEXITCODE)" -Level WARN
                    }
                }
                catch {
                    Write-LogMessage "  $($repo.Name): FAILED - $($_.Exception.Message)" -Level ERROR
                }
                finally {
                    Pop-Location
                }
            }
        }
    }

    # ── Update .Dedge-rag-config.json ──────────────────────────────────────
    if (-not $SkipConfigUpdate) {
        Write-LogMessage "Scanning code directory for repos..." -Level INFO

        $discoveredRepos = @(
            Get-ChildItem -LiteralPath $codeDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName '.git') -PathType Container } |
            Select-Object -ExpandProperty Name |
            Sort-Object
        )

        if ($discoveredRepos.Count -eq 0) {
            Write-LogMessage "No repos discovered, skipping config update" -Level WARN
        }
        elseif (-not (Test-Path -LiteralPath $configFile)) {
            Write-LogMessage "Config file not found at $($configFile), skipping config update" -Level WARN
        }
        else {
            $config = Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json
            $existingRepos = @($config.repos)
            $changed = $false

            if ($discoveredRepos.Count -ne $existingRepos.Count) {
                $changed = $true
            }
            else {
                for ($i = 0; $i -lt $discoveredRepos.Count; $i++) {
                    if ($discoveredRepos[$i] -ne $existingRepos[$i]) {
                        $changed = $true
                        break
                    }
                }
            }

            if ($changed) {
                $config.repos = $discoveredRepos
                $config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $configFile -Encoding utf8
                Write-LogMessage "Updated .Dedge-rag-config.json: $($discoveredRepos.Count) repos ($($discoveredRepos -join ', '))" -Level INFO
            }
            else {
                Write-LogMessage "Config unchanged ($($existingRepos.Count) repos)" -Level INFO
            }
        }
    }
    else {
        Write-LogMessage "Config update skipped (-SkipConfigUpdate)" -Level INFO
    }

    Write-LogMessage "Sync-DedgeCodeRepos complete" -Level INFO
}

# ════════════════════════════════════════════════════════════════════════
# Main execution
# ════════════════════════════════════════════════════════════════════════

if (-not $All -and [string]::IsNullOrWhiteSpace($RagName)) {
    throw 'Specify -RagName <name> or -All to rebuild all indexes.'
}
if (-not $env:OptPath) { throw 'Environment variable OptPath is not set.' }

# ── Resolve AiDoc root ──────────────────────────────────────────────────
if (-not $AiDocRoot) {
    if ($env:USERNAME -in @('FKGEISTA', 'FKSVEERI')) {
        $AiDocRoot = Join-Path $env:OptPath 'src\AiDoc'
    }
    else {
        $AiDocRoot = Join-Path $env:OptPath 'FkPythonApps\AiDoc'
    }
}

$pythonDir = $null
$embeddedPython = Join-Path $PSScriptRoot '..\python'
if (Test-Path -LiteralPath $embeddedPython) {
    $pythonDir = (Resolve-Path $embeddedPython).Path
}
if (-not $pythonDir -or -not (Test-Path -LiteralPath $pythonDir)) {
    $pythonDir = Join-Path $env:OptPath 'FkPythonApps\AiDoc.Python'
}
if (-not (Test-Path -LiteralPath $pythonDir)) {
    $pythonDir = Join-Path $AiDocRoot 'AiDoc.Python'
}
$libraryDir = Join-Path $env:OptPath 'data\AiDoc.Library'
if (-not (Test-Path -LiteralPath $libraryDir)) {
    $libraryDir = Join-Path $AiDocRoot 'AiDoc.Library'
}
$buildScript = Join-Path $pythonDir 'build_index.py'

Write-LogMessage "Rebuild-RagIndex starting" -Level INFO
Write-LogMessage "  AiDocRoot: $($AiDocRoot)" -Level INFO
Write-LogMessage "  Mode:     $(if ($All) { 'ALL' } else { $RagName })" -Level INFO

if (-not (Test-Path -LiteralPath $buildScript)) {
    Write-LogMessage "build_index.py not found at $($buildScript)" -Level ERROR
    throw "build_index.py not found at $($buildScript)"
}

if (-not $All) {
    $ragDir = Join-Path $libraryDir $RagName
    if (-not (Test-Path -LiteralPath $ragDir)) {
        Write-LogMessage "RAG library folder not found: $($ragDir)" -Level ERROR
        throw "RAG library folder not found: $($ragDir)"
    }
}

# ── Find Python ─────────────────────────────────────────────────────────
$pythonExe = $null
$venvPython = Join-Path $pythonDir '.venv\Scripts\python.exe'
if (Test-Path -LiteralPath $venvPython) {
    $pythonExe = $venvPython
    Write-LogMessage "Using venv Python: $($pythonExe)" -Level INFO
}
else {
    foreach ($ver in @('3.14', '3.13', '3.12', '3.11')) {
        try { $pythonExe = (py "-$ver" -c "import sys; print(sys.executable)" 2>$null) } catch {}
        if ($pythonExe -and (Test-Path -LiteralPath $pythonExe)) { break }
        $pythonExe = $null
    }
    if (-not $pythonExe) {
        $p = Get-Command python -ErrorAction SilentlyContinue
        if ($p -and $p.Source -notmatch 'WindowsApps') { $pythonExe = $p.Source }
    }
}

if (-not $pythonExe -or -not (Test-Path -LiteralPath $pythonExe)) {
    Write-LogMessage "No suitable Python found. Install Python 3.11+ or create a venv in $($pythonDir)" -Level ERROR
    throw "No suitable Python found."
}
Write-LogMessage "Python: $($pythonExe)" -Level INFO

# ── Pre-build: sync repos and export DB2 for Dedge-code ────────────────
if ($RagName -eq 'Dedge-code' -or $All) {
    Write-LogMessage "Syncing Dedge-code repos and updating config..." -Level INFO
    Update-DedgeCodeReposConfig -AiDocRoot $AiDocRoot

    $ragDbDir = Join-Path $libraryDir 'Dedge-code\_databases'
    Write-LogMessage "Exporting DB2 schemas to $($ragDbDir)..." -Level INFO
    try {
        Export-Db2ForRagDedgeCode -RagLibraryPath $ragDbDir
    } catch {
        Write-LogMessage "DB2 export failed: $($_.Exception.Message). Continuing with existing database metadata." -Level WARN
    }
}

# ── Status file ─────────────────────────────────────────────────────────
$statusDir = Join-Path $env:OptPath 'data\Rebuild-RagIndex'
if (-not (Test-Path -LiteralPath $statusDir)) {
    New-Item -ItemType Directory -Path $statusDir -Force | Out-Null
}
$statusFileName = if ($All) { 'all.running' } else { "$($RagName).running" }
$statusFile = Join-Path $statusDir $statusFileName

$statusData = [ordered]@{
    ragName    = if ($All) { '__all__' } else { $RagName }
    startedAt  = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    startedBy  = $env:USERNAME
    server     = $env:COMPUTERNAME
    pid        = $PID
    indexed    = 0
    total      = 0
    percentage = 0
}
$statusData | ConvertTo-Json | Set-Content -LiteralPath $statusFile -Encoding utf8
Write-LogMessage "Status file created: $($statusFile)" -Level INFO

function Update-StatusFile {
    param([int]$Indexed, [int]$Total)
    $statusData.indexed = $Indexed
    $statusData.total = $Total
    $statusData.percentage = if ($Total -gt 0) { [math]::Round(($Indexed / $Total) * 100, 1) } else { 0 }
    $statusData.updatedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $statusData | ConvertTo-Json | Set-Content -LiteralPath $statusFile -Encoding utf8
}

# ── Build index ─────────────────────────────────────────────────────────
$sw = [System.Diagnostics.Stopwatch]::StartNew()

Push-Location -LiteralPath $pythonDir
try {
    $buildArgs = if ($All) { @('build_index.py', '--all') } else { @('build_index.py', '--rag', $RagName) }
    $logTarget = if ($All) { 'ALL' } else { $RagName }
    Write-LogMessage "Building RAG index: $($logTarget)..." -Level INFO

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo.FileName = $pythonExe
    $proc.StartInfo.Arguments = $buildArgs -join ' '
    $proc.StartInfo.WorkingDirectory = $pythonDir
    $proc.StartInfo.UseShellExecute = $false
    $proc.StartInfo.RedirectStandardOutput = $true
    $proc.StartInfo.RedirectStandardError = $true
    $proc.StartInfo.CreateNoWindow = $true
    # Force Python to flush stdout per line
    $proc.StartInfo.EnvironmentVariables['PYTHONUNBUFFERED'] = '1'
    $proc.Start() | Out-Null

    # Regex: match "Indexed <current>/<total>" output from build_index.py
    #   Indexed\s+  - literal "Indexed" followed by whitespace
    #   (\d+)       - capture group 1: current count (digits)
    #   /           - literal slash
    #   (\d+)       - capture group 2: total count (digits)
    $indexPattern = 'Indexed\s+(\d+)/(\d+)'
    $lastStatusWrite = [datetime]::MinValue

    while (-not $proc.StandardOutput.EndOfStream) {
        $line = $proc.StandardOutput.ReadLine()
        Write-Host $line
        if ($line -match $indexPattern) {
            $now = Get-Date
            if (($now - $lastStatusWrite).TotalSeconds -ge 60) {
                Update-StatusFile -Indexed ([int]$Matches[1]) -Total ([int]$Matches[2])
                $lastStatusWrite = $now
            }
        }
    }
    $stderrOutput = $proc.StandardError.ReadToEnd()
    if ($stderrOutput) { Write-Host $stderrOutput }
    $proc.WaitForExit()

    if ($proc.ExitCode -ne 0) {
        Write-LogMessage "build_index.py failed with exit code $($proc.ExitCode)" -Level ERROR
        throw "build_index.py failed with exit code $($proc.ExitCode)"
    }
}
finally {
    Pop-Location
    if (Test-Path -LiteralPath $statusFile) {
        Remove-Item -LiteralPath $statusFile -Force
        Write-LogMessage "Status file removed: $($statusFile)" -Level INFO
    }
}

$sw.Stop()
$target = if ($All) { 'all indexes' } else { $RagName }
Write-LogMessage "Rebuild-RagIndex complete: $($target) in $($sw.Elapsed.ToString('hh\:mm\:ss'))" -Level INFO
