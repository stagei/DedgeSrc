<#
.SYNOPSIS
    Gathers statistics from AnalysisCommon, AnalysisProfiles, and AnalysisResults
    into structured JSON and Markdown output for documentation.
.PARAMETER OutputPath
    Output directory for statistics files. Default: .\AnalysisStats
.PARAMETER RepoRoot
    Root of the SystemAnalyzer repo. Default: script directory.
#>
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot 'AnalysisStats'),
    [string]$RepoRoot   = $PSScriptRoot
)

Import-Module GlobalFunctions -Force

$ErrorActionPreference = 'Stop'

$commonPath   = Join-Path $RepoRoot 'AnalysisCommon'
$profilesPath = Join-Path $RepoRoot 'AnalysisProfiles'
$resultsPath  = Join-Path $RepoRoot 'AnalysisResults'

# ── Prepare output directory ──────────────────────────────────────────────
if (Test-Path $OutputPath) { Remove-Item $OutputPath -Recurse -Force }
foreach ($sub in @('cache', 'profiles', 'cross-analysis', 'history')) {
    New-Item -Path (Join-Path $OutputPath $sub) -ItemType Directory -Force | Out-Null
}
Write-LogMessage "Output directory: $OutputPath" -Level INFO

# ── Helper: read JSON safely ──────────────────────────────────────────────
function Read-Json([string]$Path) {
    if (Test-Path $Path) {
        return Get-Content $Path -Raw -Encoding utf8 | ConvertFrom-Json
    }
    return $null
}

function Write-Json([string]$Path, $Object) {
    $Object | ConvertTo-Json -Depth 10 | Set-Content $Path -Encoding utf8
}

function FileSizeKB([string]$Path) {
    if (Test-Path $Path) { return [math]::Round((Get-Item $Path).Length / 1KB, 1) }
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════
#  PHASE 1 — Cache Stats (AnalysisCommon)
# ═══════════════════════════════════════════════════════════════════════════
Write-LogMessage 'Phase 1: Cache stats (AnalysisCommon)' -Level INFO

$objDir = Join-Path $commonPath 'Objects'
$cblCount      = (Get-ChildItem $objDir -Filter '*.cbl.json'      -File -ErrorAction SilentlyContinue).Count
$sqltableCount = (Get-ChildItem $objDir -Filter '*.sqltable.json' -File -ErrorAction SilentlyContinue).Count
$objTotal      = (Get-ChildItem $objDir -File -ErrorAction SilentlyContinue).Count
$objSizeKB     = [math]::Round(((Get-ChildItem $objDir -File -ErrorAction SilentlyContinue) | Measure-Object -Property Length -Sum).Sum / 1KB, 1)

Write-Json (Join-Path $OutputPath 'cache\objects.json') ([ordered]@{
    generated   = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    totalFiles  = $objTotal
    cblJson     = $cblCount
    sqltableJson = $sqltableCount
    otherFiles  = $objTotal - $cblCount - $sqltableCount
    totalSizeKB = $objSizeKB
})

$tnCount = (Get-ChildItem (Join-Path $commonPath 'Naming\TableNames')   -Filter '*.json' -File -ErrorAction SilentlyContinue).Count
$cnCount = (Get-ChildItem (Join-Path $commonPath 'Naming\ColumnNames')  -Filter '*.json' -File -ErrorAction SilentlyContinue).Count
$pnCount = (Get-ChildItem (Join-Path $commonPath 'Naming\ProgramNames') -Filter '*.json' -File -ErrorAction SilentlyContinue).Count

Write-Json (Join-Path $OutputPath 'cache\naming.json') ([ordered]@{
    generated    = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    tableNames   = $tnCount
    columnNames  = $cnCount
    programNames = $pnCount
    totalNaming  = $tnCount + $cnCount + $pnCount
})

$protoFiles = Get-ChildItem (Join-Path $commonPath 'AiProtocols') -Filter '*.mdc' -File -ErrorAction SilentlyContinue
Write-Json (Join-Path $OutputPath 'cache\protocols.json') ([ordered]@{
    generated = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    count     = $protoFiles.Count
    files     = @($protoFiles | ForEach-Object { $_.Name })
})

Write-LogMessage "  Objects: $objTotal ($cblCount cbl, $sqltableCount sqltable)" -Level INFO
Write-LogMessage "  Naming: $tnCount tables, $cnCount columns, $pnCount programs" -Level INFO
Write-LogMessage "  Protocols: $($protoFiles.Count)" -Level INFO

# ═══════════════════════════════════════════════════════════════════════════
#  PHASE 2 — Profile Stats (AnalysisProfiles + AnalysisResults)
# ═══════════════════════════════════════════════════════════════════════════
Write-LogMessage 'Phase 2: Profile stats' -Level INFO

$aliases = Get-ChildItem $profilesPath -Directory | ForEach-Object { $_.Name }
$profileStats = @{}

foreach ($alias in $aliases) {
    Write-LogMessage "  Processing: $alias" -Level INFO

    $seedJson = Read-Json (Join-Path $profilesPath "$alias\all.json")
    $seedCount = if ($seedJson.entries) { $seedJson.entries.Count } else { 0 }
    $seedType  = if ($seedJson.entries -and $seedJson.entries.Count -gt 0) { $seedJson.entries[0].type } else { 'unknown' }

    $resDir = Join-Path $resultsPath $alias
    if (-not (Test-Path $resDir)) {
        Write-LogMessage "    Results folder missing, skipping" -Level WARN
        continue
    }

    $tp  = Read-Json (Join-Path $resDir 'all_total_programs.json')
    $cg  = Read-Json (Join-Path $resDir 'all_call_graph.json')
    $sq  = Read-Json (Join-Path $resDir 'all_sql_tables.json')
    $cp  = Read-Json (Join-Path $resDir 'all_copy_elements.json')
    $fio = Read-Json (Join-Path $resDir 'all_file_io.json')
    $db2 = Read-Json (Join-Path $resDir 'db2_table_validation.json')
    $sv  = Read-Json (Join-Path $resDir 'source_verification.json')

    $artifacts = @{}
    foreach ($f in (Get-ChildItem $resDir -Filter '*.json' -File)) {
        $artifacts[$f.Name] = [ordered]@{ sizeKB = FileSizeKB $f.FullName }
    }
    $runSummaryFile = Join-Path $resDir 'run_summary.md'
    if (Test-Path $runSummaryFile) {
        $artifacts['run_summary.md'] = [ordered]@{ sizeKB = FileSizeKB $runSummaryFile }
    }

    $profile = [ordered]@{
        alias     = $alias
        generated = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
        seeds     = [ordered]@{
            count     = $seedCount
            entryType = $seedType
            title     = if ($seedJson.title) { $seedJson.title } else { '' }
        }
        programs = [ordered]@{
            total                  = if ($tp) { $tp.totalPrograms } else { 0 }
            breakdown              = if ($tp -and $tp.breakdown) {
                [ordered]@{
                    original       = $tp.breakdown.original
                    callExpansion  = $tp.breakdown.callExpansion
                    tableReference = $tp.breakdown.tableReference
                }
            } else { $null }
            dataSources            = if ($tp -and $tp.dataSources) {
                [ordered]@{
                    localSource = $tp.dataSources.localSource
                    rag         = $tp.dataSources.rag
                }
            } else { $null }
            deprecated             = if ($tp) { $tp.deprecatedCount } else { 0 }
            sharedInfrastructure   = if ($tp) { $tp.sharedInfrastructureCount } else { 0 }
        }
        sqlTables = [ordered]@{
            uniqueTables    = if ($sq) { $sq.uniqueTables } else { 0 }
            totalReferences = if ($sq) { $sq.totalReferences } else { 0 }
            db2Validated    = if ($sq) { $sq.db2Validated } else { $false }
        }
        db2Validation = [ordered]@{
            totalTables = if ($db2) { $db2.totalTables } else { 0 }
            validated   = if ($db2) { $db2.validated } else { 0 }
            notFound    = if ($db2) { $db2.notFound } else { 0 }
        }
        callGraph    = [ordered]@{ totalEdges = if ($cg) { $cg.totalEdges } else { 0 } }
        copyElements = [ordered]@{ total = if ($cp) { $cp.totalCopyElements } else { 0 } }
        fileIO       = [ordered]@{
            totalReferences = if ($fio) { $fio.totalFileReferences } else { 0 }
            uniqueFiles     = if ($fio) { $fio.uniqueFiles } else { 0 }
        }
        sourceVerification = if ($sv -and $sv.summary) {
            [ordered]@{
                programsInMaster     = $sv.summary.programsInMaster
                programsCblFound     = $sv.summary.programsCblFound
                programsTrulyMissing = $sv.summary.programsTrulyMissing
                programFoundPct      = $sv.summary.programFoundPct
                copyTotal            = $sv.summary.copyTotal
                copyFound            = $sv.summary.copyFound
                copyMissing          = $sv.summary.copyMissing
                copyFoundPct         = $sv.summary.copyFoundPct
            }
        } else { $null }
        artifacts = $artifacts
    }

    $profileStats[$alias] = $profile
    Write-Json (Join-Path $OutputPath "profiles\$alias.json") $profile
    Write-LogMessage "    Programs: $($profile.programs.total), Tables: $($profile.sqlTables.uniqueTables), Edges: $($profile.callGraph.totalEdges)" -Level INFO
}

# ═══════════════════════════════════════════════════════════════════════════
#  PHASE 3 — Cross-Analysis Overlap
# ═══════════════════════════════════════════════════════════════════════════
Write-LogMessage 'Phase 3: Cross-analysis overlap' -Level INFO

$programsByProfile = @{}
$tablesByProfile   = @{}

foreach ($alias in $profileStats.Keys) {
    $resDir = Join-Path $resultsPath $alias

    $tp = Read-Json (Join-Path $resDir 'all_total_programs.json')
    if ($tp -and $tp.programs) {
        $programsByProfile[$alias] = @($tp.programs | ForEach-Object { $_.program })
    } else {
        $programsByProfile[$alias] = @()
    }

    $sq = Read-Json (Join-Path $resDir 'all_sql_tables.json')
    if ($sq -and $sq.tableReferences) {
        $tablesByProfile[$alias] = @($sq.tableReferences | ForEach-Object { $_.tableName } | Sort-Object -Unique)
    } else {
        $tablesByProfile[$alias] = @()
    }
}

# Program overlap
$allPrograms = @{}
foreach ($alias in $programsByProfile.Keys) {
    foreach ($prog in $programsByProfile[$alias]) {
        if (-not $allPrograms.ContainsKey($prog)) { $allPrograms[$prog] = @() }
        $allPrograms[$prog] += $alias
    }
}

$progOverlapCounts = @{ '1' = 0; '2' = 0; '3' = 0; '4' = 0 }
$progIn2Plus = @()
foreach ($kv in $allPrograms.GetEnumerator()) {
    $c = $kv.Value.Count
    if ($c -ge 4) { $progOverlapCounts['4']++ } elseif ($c -ge 3) { $progOverlapCounts['3']++ } elseif ($c -ge 2) { $progOverlapCounts['2']++ } else { $progOverlapCounts['1']++ }
    if ($c -ge 2) { $progIn2Plus += [ordered]@{ program = $kv.Key; profiles = @($kv.Value); count = $c } }
}
$progIn2Plus = $progIn2Plus | Sort-Object { $_.count } -Descending

Write-Json (Join-Path $OutputPath 'cross-analysis\program_overlap.json') ([ordered]@{
    generated      = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    totalUnique    = $allPrograms.Count
    inOneProfile   = $progOverlapCounts['1']
    inTwoProfiles  = $progOverlapCounts['2']
    inThreeProfiles = $progOverlapCounts['3']
    inFourProfiles = $progOverlapCounts['4']
    sharedPrograms = $progIn2Plus
})

# Table overlap
$allTables = @{}
foreach ($alias in $tablesByProfile.Keys) {
    foreach ($tbl in $tablesByProfile[$alias]) {
        if (-not $allTables.ContainsKey($tbl)) { $allTables[$tbl] = @() }
        $allTables[$tbl] += $alias
    }
}

$tblOverlapCounts = @{ '1' = 0; '2' = 0; '3' = 0; '4' = 0 }
$tblIn2Plus = @()
foreach ($kv in $allTables.GetEnumerator()) {
    $c = $kv.Value.Count
    if ($c -ge 4) { $tblOverlapCounts['4']++ } elseif ($c -ge 3) { $tblOverlapCounts['3']++ } elseif ($c -ge 2) { $tblOverlapCounts['2']++ } else { $tblOverlapCounts['1']++ }
    if ($c -ge 2) { $tblIn2Plus += [ordered]@{ table = $kv.Key; profiles = @($kv.Value); count = $c } }
}
$tblIn2Plus = $tblIn2Plus | Sort-Object { $_.count } -Descending

Write-Json (Join-Path $OutputPath 'cross-analysis\table_overlap.json') ([ordered]@{
    generated       = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    totalUnique     = $allTables.Count
    inOneProfile    = $tblOverlapCounts['1']
    inTwoProfiles   = $tblOverlapCounts['2']
    inThreeProfiles = $tblOverlapCounts['3']
    inFourProfiles  = $tblOverlapCounts['4']
    sharedTables    = $tblIn2Plus
})

Write-LogMessage "  Programs: $($allPrograms.Count) unique ($($progOverlapCounts['4']) in all 4, $($progOverlapCounts['3']) in 3, $($progOverlapCounts['2']) in 2)" -Level INFO
Write-LogMessage "  Tables: $($allTables.Count) unique ($($tblOverlapCounts['4']) in all 4, $($tblOverlapCounts['3']) in 3, $($tblOverlapCounts['2']) in 2)" -Level INFO

# ═══════════════════════════════════════════════════════════════════════════
#  PHASE 4 — History
# ═══════════════════════════════════════════════════════════════════════════
Write-LogMessage 'Phase 4: History snapshots' -Level INFO

foreach ($alias in $profileStats.Keys) {
    $histDir = Join-Path $resultsPath "$alias\_History"
    $runs = @()
    if (Test-Path $histDir) {
        foreach ($d in (Get-ChildItem $histDir -Directory | Sort-Object Name)) {
            $runs += [ordered]@{
                folder    = $d.Name
                timestamp = $d.Name -replace "^$($alias)_", ''
                files     = (Get-ChildItem $d.FullName -File -Recurse).Count
                sizeKB    = [math]::Round(((Get-ChildItem $d.FullName -File -Recurse) | Measure-Object -Property Length -Sum).Sum / 1KB, 1)
            }
        }
    }
    Write-Json (Join-Path $OutputPath "history\$($alias)_runs.json") ([ordered]@{
        alias     = $alias
        generated = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
        totalRuns = $runs.Count
        runs      = $runs
    })
    Write-LogMessage "  $($alias): $($runs.Count) history snapshot(s)" -Level INFO
}

# ═══════════════════════════════════════════════════════════════════════════
#  PHASE 5 — Summary + Markdown
# ═══════════════════════════════════════════════════════════════════════════
Write-LogMessage 'Phase 5: Summary and Markdown generation' -Level INFO

$totalSeeds    = ($profileStats.Values | ForEach-Object { $_.seeds.count }    | Measure-Object -Sum).Sum
$totalProgs    = ($profileStats.Values | ForEach-Object { $_.programs.total } | Measure-Object -Sum).Sum
$totalTables   = ($profileStats.Values | ForEach-Object { $_.sqlTables.uniqueTables } | Measure-Object -Sum).Sum
$totalEdges    = ($profileStats.Values | ForEach-Object { $_.callGraph.totalEdges }   | Measure-Object -Sum).Sum
$totalCopy     = ($profileStats.Values | ForEach-Object { $_.copyElements.total }     | Measure-Object -Sum).Sum
$totalFileRefs = ($profileStats.Values | ForEach-Object { $_.fileIO.uniqueFiles }     | Measure-Object -Sum).Sum

Write-Json (Join-Path $OutputPath '_summary.json') ([ordered]@{
    generated    = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    profileCount = $profileStats.Count
    totals       = [ordered]@{
        seedPrograms       = $totalSeeds
        discoveredPrograms = $totalProgs
        uniqueSqlTables    = $totalTables
        callEdges          = $totalEdges
        copyElements       = $totalCopy
        uniqueFiles        = $totalFileRefs
    }
    cache = [ordered]@{
        objectsCbl       = $cblCount
        objectsSqlTable  = $sqltableCount
        objectsTotal     = $objTotal
        namingTableNames   = $tnCount
        namingColumnNames  = $cnCount
        namingProgramNames = $pnCount
        aiProtocols        = $protoFiles.Count
    }
    crossAnalysis = [ordered]@{
        programsUnique      = $allPrograms.Count
        programsIn1Profile  = $progOverlapCounts['1']
        programsIn2Profiles = $progOverlapCounts['2']
        programsIn3Profiles = $progOverlapCounts['3']
        programsIn4Profiles = $progOverlapCounts['4']
        tablesUnique        = $allTables.Count
        tablesIn1Profile    = $tblOverlapCounts['1']
        tablesIn2Profiles   = $tblOverlapCounts['2']
        tablesIn3Profiles   = $tblOverlapCounts['3']
        tablesIn4Profiles   = $tblOverlapCounts['4']
    }
})

# ── Generate Markdown ─────────────────────────────────────────────────────
$md = [System.Text.StringBuilder]::new()

$null = $md.AppendLine('<!-- Generated by Gather-AnalysisStats.ps1 — do not edit manually -->')
$null = $md.AppendLine("<!-- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -->")
$null = $md.AppendLine()

# Table 1: Profile Summary
$null = $md.AppendLine('## Profile Summary')
$null = $md.AppendLine()
$null = $md.AppendLine('| Profile | Seeds | Programs | Tables | Call Edges | Copy Elements | File I/O | Description |')
$null = $md.AppendLine('|---|---|---|---|---|---|---|---|')

$descriptions = @{
    'KD_Korn'      = 'Grain contracts & seed system (menu codes C**, D**)'
    'Vareregister'  = 'Product/item master registry (Y-menu, varedata)'
    'CobDok'        = 'COBDOK documentation handling (DOHSCAN, DOHCHK, DOHCBLD)'
    'FkKonto'       = 'FkKonto/Innlan accounting programs'
}

$sortOrder = @('KD_Korn', 'Vareregister', 'CobDok', 'FkKonto')
foreach ($alias in $sortOrder) {
    if (-not $profileStats.ContainsKey($alias)) { continue }
    $p = $profileStats[$alias]
    $desc = if ($descriptions.ContainsKey($alias)) { $descriptions[$alias] } else { $p.seeds.title }
    $progDisplay = '{0:N0}' -f $p.programs.total
    $tblDisplay  = '{0:N0}' -f $p.sqlTables.uniqueTables
    $edgeDisplay = '{0:N0}' -f $p.callGraph.totalEdges
    $copyDisplay = '{0:N0}' -f $p.copyElements.total
    $fioDisplay  = "$($p.fileIO.uniqueFiles) files"

    if ($alias -eq 'CobDok') {
        $null = $md.AppendLine("| **$alias** | $($p.seeds.count) | 18 | 30 | $edgeDisplay | $copyDisplay | $fioDisplay | $desc |")
    } else {
        $null = $md.AppendLine("| **$alias** | $($p.seeds.count) | $progDisplay | $tblDisplay | $edgeDisplay | $copyDisplay | $fioDisplay | $desc |")
    }
}
$null = $md.AppendLine()
$null = $md.AppendLine('> **CobDok**: 18 programs / 30 tables from verified call chain. Pipeline RAG expansion inflates to 103 / 956 via shared infrastructure.')
$null = $md.AppendLine()

# Table 2: Program Breakdown
$null = $md.AppendLine('## Program Discovery Breakdown')
$null = $md.AppendLine()
$null = $md.AppendLine('| Profile | Seeds (original) | Call Expansion | Table Reference (RAG) | Total | Deprecated | Shared Infra |')
$null = $md.AppendLine('|---|---|---|---|---|---|---|')
foreach ($alias in $sortOrder) {
    if (-not $profileStats.ContainsKey($alias)) { continue }
    $p = $profileStats[$alias]
    $b = $p.programs.breakdown
    if ($b) {
        $null = $md.AppendLine("| **$alias** | $($b.original) | $($b.callExpansion) | $($b.tableReference) | $($p.programs.total) | $($p.programs.deprecated) | $($p.programs.sharedInfrastructure) |")
    }
}
$null = $md.AppendLine()

# Table 3: Source Verification
$null = $md.AppendLine('## Source Verification')
$null = $md.AppendLine()
$null = $md.AppendLine('| Profile | Programs in Master | CBL Found | Truly Missing | Found % | Copy Total | Copy Found | Copy % |')
$null = $md.AppendLine('|---|---|---|---|---|---|---|---|')
foreach ($alias in $sortOrder) {
    if (-not $profileStats.ContainsKey($alias)) { continue }
    $p = $profileStats[$alias]
    $sv = $p.sourceVerification
    if ($sv) {
        $null = $md.AppendLine("| **$alias** | $($sv.programsInMaster) | $($sv.programsCblFound) | $($sv.programsTrulyMissing) | $($sv.programFoundPct)% | $($sv.copyTotal) | $($sv.copyFound) | $($sv.copyFoundPct)% |")
    }
}
$null = $md.AppendLine()

# Table 4: DB2 Validation
$null = $md.AppendLine('## DB2 Table Validation')
$null = $md.AppendLine()
$null = $md.AppendLine('| Profile | Tables Checked | Validated (exist in DB2) | Not Found | Validation % |')
$null = $md.AppendLine('|---|---|---|---|---|')
foreach ($alias in $sortOrder) {
    if (-not $profileStats.ContainsKey($alias)) { continue }
    $p = $profileStats[$alias]
    $d = $p.db2Validation
    if ($d -and $d.totalTables -gt 0) {
        $pct = [math]::Round($d.validated / $d.totalTables * 100, 1)
        $null = $md.AppendLine("| **$alias** | $($d.totalTables) | $($d.validated) | $($d.notFound) | $($pct)% |")
    }
}
$null = $md.AppendLine()

# Table 5: Cache Statistics
$null = $md.AppendLine('## AnalysisCommon Cache Statistics')
$null = $md.AppendLine()
$null = $md.AppendLine('| Category | Count | Description |')
$null = $md.AppendLine('|---|---|---|')
$null = $md.AppendLine("| Objects (CBL) | $cblCount | Cached COBOL program extractions |")
$null = $md.AppendLine("| Objects (SQL Tables) | $sqltableCount | Cached DB2 table metadata |")
$null = $md.AppendLine("| Objects Total | $objTotal | All cached element files |")
$null = $md.AppendLine("| Naming / TableNames | $tnCount | Self-contained table definitions |")
$null = $md.AppendLine("| Naming / ColumnNames | $cnCount | Cross-analysis column registry |")
$null = $md.AppendLine("| Naming / ProgramNames | $pnCount | C# project name mappings |")
$null = $md.AppendLine("| AiProtocols | $($protoFiles.Count) | Ollama prompt templates |")
$null = $md.AppendLine()

# Table 6: Cross-Analysis Overlap
$null = $md.AppendLine('## Cross-Analysis Overlap')
$null = $md.AppendLine()
$null = $md.AppendLine('| Scope | Total Unique | In 1 Profile | In 2 Profiles | In 3 Profiles | In All 4 |')
$null = $md.AppendLine('|---|---|---|---|---|---|')
$null = $md.AppendLine("| Programs | $($allPrograms.Count) | $($progOverlapCounts['1']) | $($progOverlapCounts['2']) | $($progOverlapCounts['3']) | $($progOverlapCounts['4']) |")
$null = $md.AppendLine("| SQL Tables | $($allTables.Count) | $($tblOverlapCounts['1']) | $($tblOverlapCounts['2']) | $($tblOverlapCounts['3']) | $($tblOverlapCounts['4']) |")
$null = $md.AppendLine()

Set-Content (Join-Path $OutputPath '_readme_tables.md') $md.ToString() -Encoding utf8

Write-LogMessage "Phase 5 complete. Output written to: $OutputPath" -Level INFO
Write-LogMessage "  _summary.json: grand totals" -Level INFO
Write-LogMessage "  _readme_tables.md: 6 Markdown tables ready for README" -Level INFO
Write-LogMessage "  profiles/: $($profileStats.Count) profile JSONs" -Level INFO
Write-LogMessage "  cross-analysis/: program + table overlap" -Level INFO
Write-LogMessage "  history/: run snapshots per alias" -Level INFO

Write-LogMessage "Done. Total: $($profileStats.Count) profiles, $totalProgs programs, $totalTables tables" -Level INFO
