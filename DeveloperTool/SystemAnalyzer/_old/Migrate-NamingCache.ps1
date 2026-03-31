<#
.SYNOPSIS
    Migrates the naming cache from old format to new self-contained format.
.DESCRIPTION
    Old format:
      - TableNames/{TABLE}.json  -> futureName, namespace (no columns)
      - ColumnNames/{TABLE}.json -> tableName, columns[] (table-keyed)
    New format:
      - TableNames/{TABLE}.json  -> futureName, namespace, columns[] (self-contained)
      - ColumnNames/{COLUMN}.json -> originalName, futureName, finalContext, contexts[] (per-column)
.PARAMETER RebuildColumnRegistry
    Instead of migrating old-format ColumnNames, rebuild the entire column registry
    from all TableNames files that already have columns[] (useful after data loss).
#>
param(
    [string]$NamingRoot = 'C:\opt\src\SystemAnalyzer\AnalysisCommon\Naming',
    [string]$AnalysisAlias = 'Migration',
    [switch]$RebuildColumnRegistry
)

$ErrorActionPreference = 'Stop'
$tableDir  = Join-Path $NamingRoot 'TableNames'
$columnDir = Join-Path $NamingRoot 'ColumnNames'

if (-not (Test-Path $tableDir) -or -not (Test-Path $columnDir)) {
    Write-Host "Naming directories not found at $NamingRoot" -ForegroundColor Red
    exit 1
}

Write-Host "=== Naming Cache Migration ===" -ForegroundColor Cyan
Write-Host "  TableNames:  $tableDir"
Write-Host "  ColumnNames: $columnDir"
Write-Host ""

# Phase 1: Merge ColumnNames/{TABLE}.json -> TableNames/{TABLE}.json
$oldColumnFiles = @(Get-ChildItem -LiteralPath $columnDir -Filter '*.json' -File)
$mergedCount = 0
$skippedCount = 0
$orphanedColumns = [System.Collections.ArrayList]::new()

Write-Host "Phase 1: Merging column data into TableNames files..." -ForegroundColor Yellow
foreach ($cf in $oldColumnFiles) {
    if ($cf.Name -eq 'README.md') { continue }
    try {
        $colData = Get-Content -LiteralPath $cf.FullName -Raw -Encoding UTF8 | ConvertFrom-Json

        # Old format has tableName + columns[] — this is table-keyed
        if (-not $colData.tableName -or -not $colData.columns) {
            # Might already be new-format (has originalName) — skip
            if ($colData.originalName) {
                $skippedCount++
                continue
            }
            Write-Host "  SKIP: $($cf.Name) — no tableName or columns" -ForegroundColor Gray
            $skippedCount++
            continue
        }

        $tableName = $colData.tableName
        $tableFile = Join-Path $tableDir "$($tableName.ToUpperInvariant()).json"

        if (Test-Path $tableFile) {
            $tableData = Get-Content -LiteralPath $tableFile -Raw -Encoding UTF8 | ConvertFrom-Json

            # Only merge if TableNames file doesn't already have columns
            if (-not $tableData.columns -or $tableData.columns.Count -eq 0) {
                if ($tableData -is [System.Management.Automation.PSCustomObject]) {
                    $tableData | Add-Member -NotePropertyName 'columns' -NotePropertyValue @($colData.columns) -Force
                }
                $tableData | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tableFile -Encoding UTF8
                $mergedCount++
                Write-Host "  MERGED: $($cf.Name) -> $($tableName).json ($($colData.columns.Count) columns)" -ForegroundColor Green
            } else {
                Write-Host "  SKIP: $($tableName) already has columns ($($tableData.columns.Count))" -ForegroundColor Gray
                $skippedCount++
            }
        } else {
            Write-Host "  ORPHAN: $($cf.Name) — no matching TableNames file" -ForegroundColor DarkYellow
        }

        # Collect columns for Phase 2
        foreach ($col in $colData.columns) {
            if ($col.name) {
                [void]$orphanedColumns.Add([ordered]@{
                    columnName  = $col.name
                    tableName   = $tableName
                    futureName  = $col.futureName
                    description = $col.description
                })
            }
        }
    } catch {
        Write-Host "  ERROR: $($cf.Name) — $($_.Exception.Message)" -ForegroundColor Red
    }
}
Write-Host "  Merged: $mergedCount | Skipped: $skippedCount | Columns collected: $($orphanedColumns.Count)"
Write-Host ""

# Phase 2: Build column registry entries (merging with existing new-format files)
Write-Host "Phase 2: Building cross-analysis column registry..." -ForegroundColor Yellow
$columnRegistry = @{}
foreach ($entry in $orphanedColumns) {
    $colKey = $entry.columnName.ToUpperInvariant()
    if (-not $columnRegistry.ContainsKey($colKey)) {
        # Check if there's already a new-format file we should merge with
        $existingPath = Join-Path $columnDir "$colKey.json"
        $existingData = $null
        if (Test-Path $existingPath) {
            try {
                $existingData = Get-Content -LiteralPath $existingPath -Raw -Encoding UTF8 | ConvertFrom-Json
            } catch { }
        }

        if ($existingData -and $existingData.originalName) {
            # Merge with existing new-format file
            $columnRegistry[$colKey] = [ordered]@{
                originalName       = $existingData.originalName
                futureName         = $existingData.futureName
                finalContext        = $existingData.finalContext
                contexts           = [System.Collections.ArrayList]::new()
                usedInTables       = [System.Collections.ArrayList]::new()
                isTypicalForeignKey = if ($existingData.isTypicalForeignKey) { $existingData.isTypicalForeignKey } else { $false }
                typicalTarget      = $existingData.typicalTarget
                model              = $existingData.model
                lastResolvedAt     = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
            }
            $reg = $columnRegistry[$colKey]
            if ($existingData.contexts) {
                foreach ($c in $existingData.contexts) { [void]$reg.contexts.Add($c) }
            }
            if ($existingData.usedInTables) {
                foreach ($t in $existingData.usedInTables) {
                    if ($reg.usedInTables -notcontains $t) { [void]$reg.usedInTables.Add($t) }
                }
            }
        } else {
            $columnRegistry[$colKey] = [ordered]@{
                originalName       = $colKey
                futureName         = $entry.futureName
                finalContext        = $entry.description
                contexts           = [System.Collections.ArrayList]::new()
                usedInTables       = [System.Collections.ArrayList]::new()
                isTypicalForeignKey = $false
                typicalTarget      = $null
                model              = 'migration'
                lastResolvedAt     = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
            }
        }
    }
    $reg = $columnRegistry[$colKey]
    if ($entry.tableName -and $reg.usedInTables -notcontains $entry.tableName) {
        [void]$reg.usedInTables.Add($entry.tableName)
    }

    $existingCtx = $reg.contexts | Where-Object { $_.analysis -eq $AnalysisAlias -and $_.description -eq $entry.description }
    if (-not $existingCtx) {
        [void]$reg.contexts.Add([ordered]@{
            analysis    = $AnalysisAlias
            description = $entry.description
            analyzedAt  = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
        })
    }
}

Write-Host "  Unique columns from migration: $($columnRegistry.Count)"

# Phase 3: Delete old table-keyed files, write/update column-keyed files
Write-Host ""
Write-Host "Phase 3: Replacing old ColumnNames files with new column-keyed files..." -ForegroundColor Yellow
$deletedOld = 0
foreach ($cf in $oldColumnFiles) {
    if ($cf.Name -eq 'README.md') { continue }
    try {
        $data = Get-Content -LiteralPath $cf.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($data.tableName -and $data.columns) {
            Remove-Item -LiteralPath $cf.FullName -Force
            $deletedOld++
        }
    } catch {
        Remove-Item -LiteralPath $cf.FullName -Force -ErrorAction SilentlyContinue
        $deletedOld++
    }
}
Write-Host "  Deleted $deletedOld old table-keyed files"

$writtenNew = 0
foreach ($colKey in $columnRegistry.Keys) {
    $reg = $columnRegistry[$colKey]
    $outPath = Join-Path $columnDir "$colKey.json"
    try {
        [PSCustomObject]$reg | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $outPath -Encoding UTF8
        $writtenNew++
    } catch {
        Write-Host "  ERROR writing $($colKey): $($_.Exception.Message)" -ForegroundColor Red
    }
}
Write-Host "  Written/updated $writtenNew column-keyed files"

Write-Host ""
Write-Host "=== Migration Complete ===" -ForegroundColor Cyan
Write-Host "  TableNames: $mergedCount files updated with columns[]"
Write-Host "  ColumnNames: $deletedOld old files removed, $writtenNew new/updated files"

# ── Phase 4 (optional): Rebuild column registry from ALL TableNames files ──
if ($RebuildColumnRegistry) {
    Write-Host ""
    Write-Host "Phase 4: Rebuilding FULL column registry from all TableNames files..." -ForegroundColor Yellow
    $allTableFiles = @(Get-ChildItem -LiteralPath $tableDir -Filter '*.json' -File)
    $rebuildRegistry = @{}
    $totalColumnsProcessed = 0

    foreach ($tf in $allTableFiles) {
        try {
            $tData = Get-Content -LiteralPath $tf.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if (-not $tData.columns -or $tData.columns.Count -eq 0) { continue }
            $tableName = $tData.tableName

            foreach ($col in $tData.columns) {
                if (-not $col.name) { continue }
                $colKey = $col.name.ToUpperInvariant()
                $totalColumnsProcessed++

                if (-not $rebuildRegistry.ContainsKey($colKey)) {
                    $rebuildRegistry[$colKey] = [ordered]@{
                        originalName       = $colKey
                        futureName         = $col.futureName
                        finalContext        = $col.description
                        contexts           = [System.Collections.ArrayList]::new()
                        usedInTables       = [System.Collections.ArrayList]::new()
                        isTypicalForeignKey = $false
                        typicalTarget      = $null
                        model              = 'rebuild'
                        lastResolvedAt     = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
                    }
                }
                $reg = $rebuildRegistry[$colKey]
                if ($tableName -and $reg.usedInTables -notcontains $tableName) {
                    [void]$reg.usedInTables.Add($tableName)
                }

                $existing = $reg.contexts | Where-Object { $_.analysis -eq $AnalysisAlias -and $_.description -eq $col.description }
                if (-not $existing) {
                    [void]$reg.contexts.Add([ordered]@{
                        analysis    = $AnalysisAlias
                        description = $col.description
                        analyzedAt  = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
                    })
                }
            }
        } catch { }
    }

    Write-Host "  Processed: $totalColumnsProcessed columns from $($allTableFiles.Count) tables"
    Write-Host "  Unique columns: $($rebuildRegistry.Count)"

    $rebuildWritten = 0
    foreach ($colKey in $rebuildRegistry.Keys) {
        $reg = $rebuildRegistry[$colKey]
        $outPath = Join-Path $columnDir "$colKey.json"
        try {
            [PSCustomObject]$reg | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $outPath -Encoding UTF8
            $rebuildWritten++
        } catch {
            Write-Host "  ERROR writing $($colKey): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    Write-Host "  Written: $rebuildWritten column registry files"
    Write-Host ""
    Write-Host "=== Rebuild Complete ===" -ForegroundColor Cyan
}
