<#
.SYNOPSIS
    Generates markdown files per the SPEC-DB2-Objects-RAG-Export-Format.

.DESCRIPTION
    Takes parsed catalog data and DDL map, produces one .md file per object:
    Format 1 (Tables), Format 2 (Views), Format 3 (Procedures),
    Format 4 (Functions), Format 5 (Triggers), Format 6 (Reference Data).
#>

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

        # Columns
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

        # Primary Key
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

        # Foreign Keys
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

        # Incoming FKs
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

        # Indexes
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

        # Triggers summary
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("## Triggers")
        [void]$sb.AppendLine("")
        if ($CatalogData.TriggersByTable.ContainsKey($tableKey)) {
            [void]$sb.AppendLine("| Trigger Name | Event | Timing | Granularity | Targets Table |")
            [void]$sb.AppendLine("|--------------|-------|--------|-------------|---------------|")
            foreach ($trig in $CatalogData.TriggersByTable[$tableKey]) {
                $event = Format-TriggerEvent -Event $trig.Event
                $timing = Format-TriggerTiming -Timing $trig.Timing
                $gran = if ($trig.Granularity -eq 'S') { 'FOR EACH STATEMENT' } else { 'FOR EACH ROW' }
                [void]$sb.AppendLine("| $($trig.TrigName) | $($event) | $($timing) | $($gran) | $($tableKey) |")
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
                            if ($v -eq '' -or $v -eq $null) { '*(null)*' } else { $v }
                        }
                        [void]$sb.AppendLine("| $($formatted -join ' | ') |")
                    }
                }
            }
        }

        # DDL
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

        # View columns
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

        # Source tables
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

        # DDL
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

        # Tables Referenced (parsed from body)
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

        # Procedures/Functions Called
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

        # Body
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
        $event = Format-TriggerEvent -Event $trig.Event
        [void]$sb.AppendLine("**Event:** $($event)")
        $timing = Format-TriggerTiming -Timing $trig.Timing
        [void]$sb.AppendLine("**Timing:** $($timing)")
        $gran = if ($trig.Granularity -eq 'S') { 'FOR EACH STATEMENT' } else { 'FOR EACH ROW' }
        [void]$sb.AppendLine("**Granularity:** $($gran)")

        # UPDATE columns detection from trigger text
        if ($trig.Event -eq 'U' -and $trig.Text -match 'UPDATE\s+OF\s+([^)]+?)\s+ON') {
            [void]$sb.AppendLine("**Update columns:** $($matches[1].Trim())")
        }
        else {
            [void]$sb.AppendLine("**Update columns:** all")
        }

        [void]$sb.AppendLine("**Valid:** $($trig.Valid)")
        [void]$sb.AppendLine("**Created:** $($trig.CreateTime)")
        [void]$sb.AppendLine("**Comment:** $($trig.Remarks)")

        # Tables Referenced
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

        # Body
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
                    if ($v -eq '' -or $v -eq $null) { '*(null)*' } else { $v }
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

# ---- HELPER FUNCTIONS ----

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
    param([string]$Event)
    switch ($Event) {
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
    #   ($schemaPattern)  -- group 1: schema name (one of the known schemas)
    #   \.                -- literal dot
    #   ([A-Z_][A-Z0-9_]+)  -- group 2: object name starting with letter/underscore
    $pattern = "(?i)\b($($schemaPattern))\.([A-Z_][A-Z0-9_]+)\b"
    $matches2 = [regex]::Matches($Body, $pattern)

    foreach ($m in $matches2) {
        $tableRef = "$($m.Groups[1].Value.ToUpper()).$($m.Groups[2].Value.ToUpper())"
        if (-not $refs.ContainsKey($tableRef)) { $refs[$tableRef] = [System.Collections.ArrayList]::new() }
    }

    # Determine operations by looking at SQL keywords preceding the table reference
    $lines = $Body.ToUpper() -split "`n"
    $fullText = $Body.ToUpper()

    foreach ($tblRef in @($refs.Keys)) {
        $ops = [System.Collections.ArrayList]::new()
        # Regex: match SQL DML keywords followed by whitespace and the table reference
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
    #   CALL\s+  -- literal CALL followed by whitespace
    #   ($schemaPattern)  -- group 1: schema
    #   \.([A-Z_][A-Z0-9_]+) -- group 2: routine name
    $pattern = "(?i)\bCALL\s+($($schemaPattern))\.([A-Z_][A-Z0-9_]+)\b"
    $matches2 = [regex]::Matches($Body, $pattern)

    foreach ($m in $matches2) {
        $callRef = "$($m.Groups[1].Value.ToUpper()).$($m.Groups[2].Value.ToUpper())"
        if ($calls -notcontains $callRef) { $calls += $callRef }
    }

    return $calls
}
