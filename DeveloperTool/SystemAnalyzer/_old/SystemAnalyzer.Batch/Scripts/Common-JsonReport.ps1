function Get-JsonFileContent {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Write-RunSummaryMarkdown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunDir,
        [string]$OutputPath = ''
    )

    if (-not (Test-Path -LiteralPath $RunDir)) {
        throw "Run directory not found: $RunDir"
    }

    if (-not $OutputPath) {
        $OutputPath = Join-Path $RunDir 'run_summary.md'
    }

    $master = Get-JsonFileContent -Path (Join-Path $RunDir 'dependency_master.json')
    $progs  = Get-JsonFileContent -Path (Join-Path $RunDir 'all_total_programs.json')
    $sql    = Get-JsonFileContent -Path (Join-Path $RunDir 'all_sql_tables.json')
    $copy   = Get-JsonFileContent -Path (Join-Path $RunDir 'all_copy_elements.json')
    $call   = Get-JsonFileContent -Path (Join-Path $RunDir 'all_call_graph.json')
    $fio    = Get-JsonFileContent -Path (Join-Path $RunDir 'all_file_io.json')
    $verify = Get-JsonFileContent -Path (Join-Path $RunDir 'source_verification.json')
    $db2    = Get-JsonFileContent -Path (Join-Path $RunDir 'db2_table_validation.json')
    $excl   = Get-JsonFileContent -Path (Join-Path $RunDir 'applied_exclusions.json')
    $class  = Get-JsonFileContent -Path (Join-Path $RunDir 'classified_programs.json')

    $lines = [System.Collections.Generic.List[string]]::new()
    $generated = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    $lines.Add('# Pipeline Run Summary')
    $lines.Add('')
    $lines.Add("Generated: $generated")
    $lines.Add("Run folder: ``$RunDir``")
    if ($master -and $master.database) {
        $lines.Add("Database: **$($master.database)** (alias: $($master.db2Alias))")
    }
    $lines.Add('')

    $lines.Add('## Main Statistics')
    $lines.Add('')
    $lines.Add('| Metric | Value |')
    $lines.Add('|---|---:|')
    if ($master) { $lines.Add("| Programs in dependency master | $($master.totalPrograms) |") }
    if ($progs)  { $lines.Add("| Total programs (all included) | $($progs.totalPrograms) |") }
    if ($sql)    { $lines.Add("| SQL references | $($sql.totalReferences) |") }
    if ($sql)    { $lines.Add("| Unique SQL tables | $($sql.uniqueTables) |") }
    if ($copy)   { $lines.Add("| Unique COPY elements | $($copy.totalCopyElements) |") }
    if ($call)   { $lines.Add("| Call graph edges | $($call.totalEdges) |") }
    if ($fio)    { $lines.Add("| File I/O references | $($fio.totalFileReferences) |") }
    if ($fio)    { $lines.Add("| Unique files | $($fio.uniqueFiles) |") }
    if ($verify) {
        $programPct = if ($verify.summary.PSObject.Properties.Name -contains 'programFoundPct') {
            $verify.summary.programFoundPct
        } else {
            $verify.summary.programFoundPctReal
        }
        $lines.Add("| Program source found (real %) | $programPct |")
    }
    if ($verify) { $lines.Add("| COPY found (%) | $($verify.summary.copyFoundPct) |") }
    if ($db2)    {
        $totalKey = if ($db2.totalQualified) { $db2.totalQualified } else { $db2.totalTables }
        $lines.Add("| DB2 validated tables | $($db2.validated) / $($totalKey) |")
    }
    if ($master -and $master.boundaryStats) {
        $lines.Add("| Database boundary | $($master.boundaryStats.database) ($($master.boundaryStats.catalogQualified) qualifiedNames) |")
        $lines.Add("| Programs rejected (foreign tables) | $($master.boundaryStats.programsRejected) |")
        $lines.Add("| SQL ops stripped (non-matching) | $($master.boundaryStats.sqlOpsStripped) |")
    }
    if ($progs -and $progs.deprecatedCount -gt 0) {
        $lines.Add("| Deprecated (UTGATT) | $($progs.deprecatedCount) |")
    }
    if ($excl)   { $lines.Add("| Exclusion candidates (tagged) | $($excl.totalCandidates) |") }
    if ($class)  { $lines.Add("| Classified programs | $($class.totalClassified) |") }
    $lines.Add('')

    if ($progs -and $progs.breakdown) {
        $lines.Add('## Program Discovery Breakdown')
        $lines.Add('')
        $lines.Add('| Source | Count |')
        $lines.Add('|---|---:|')
        $lines.Add("| Original | $($progs.breakdown.original) |")
        $lines.Add("| CALL expansion | $($progs.breakdown.callExpansion) |")
        $lines.Add("| Table reference | $($progs.breakdown.tableReference) |")
        if ($progs.dataSources) {
            $lines.Add("| Local source | $($progs.dataSources.localSource) |")
            $lines.Add("| RAG | $($progs.dataSources.rag) |")
        }
        $lines.Add('')
    }

    if ($verify -and $verify.summary) {
        $programsInMaster = if ($verify.summary.PSObject.Properties.Name -contains 'programsInMaster') {
            [int]$verify.summary.programsInMaster
        } else { 0 }
        $cblExact = if ($verify.summary.PSObject.Properties.Name -contains 'programsCblFound') {
            [int]$verify.summary.programsCblFound
        } else { 0 }
        $uvFuzzy = if ($verify.summary.PSObject.Properties.Name -contains 'programsUvFuzzyMatch') {
            [int]$verify.summary.programsUvFuzzyMatch
        } else { 0 }
        $uncertain = if ($verify.summary.PSObject.Properties.Name -contains 'programsUncertainFound') {
            [int]$verify.summary.programsUncertainFound
        } else { 0 }
        $otherType = if ($verify.summary.PSObject.Properties.Name -contains 'programsOtherType') {
            [int]$verify.summary.programsOtherType
        } else { 0 }
        $noise = if ($verify.summary.PSObject.Properties.Name -contains 'programsNoise') {
            [int]$verify.summary.programsNoise
        } else { 0 }

        $foundInCblFamily = $cblExact + $uvFuzzy
        $missingFromCblFolder = [math]::Max(0, $programsInMaster - $foundInCblFamily)

        $copyExpected = if ($verify.summary.PSObject.Properties.Name -contains 'copyInMaster') {
            [int]$verify.summary.copyInMaster
        } elseif ($verify.summary.PSObject.Properties.Name -contains 'copyTotal') {
            [int]$verify.summary.copyTotal
        } else { 0 }
        $copyFound = if ($verify.summary.PSObject.Properties.Name -contains 'copyFound') {
            [int]$verify.summary.copyFound
        } else { 0 }
        $copyMissing = if ($verify.summary.PSObject.Properties.Name -contains 'copyMissing') {
            [int]$verify.summary.copyMissing
        } else { [math]::Max(0, $copyExpected - $copyFound) }

        $lines.Add('### CBL/CPY Folder Coverage')
        $lines.Add('')
        $lines.Add('| Folder | Expected | Found | Missing |')
        $lines.Add('|---|---:|---:|---:|')
        $lines.Add("| CBL folder (exact + U/V fuzzy) | $programsInMaster | $foundInCblFamily | $missingFromCblFolder |")
        $lines.Add("| CPY folder (copy elements) | $copyExpected | $copyFound | $copyMissing |")
        $lines.Add('')

        $lines.Add('## Source Verification')
        $lines.Add('')
        $lines.Add('| Status | Count |')
        $lines.Add('|---|---:|')
        $lines.Add("| CBL exact | $cblExact |")
        if ($verify.summary.PSObject.Properties.Name -contains 'programsUncertainFound') {
            $lines.Add("| Uncertain folder match | $uncertain |")
        }
        $lines.Add("| U/V fuzzy match | $uvFuzzy |")
        $lines.Add("| Other type found | $otherType |")
        $lines.Add("| Noise filtered | $noise |")
        $lines.Add("| Truly missing | $($verify.summary.programsTrulyMissing) |")
        $lines.Add('')
    }

    if ($excl -and $excl.totalCandidates -gt 0) {
        $lines.Add('## Exclusion Candidates (tagged, not removed)')
        $lines.Add('')
        $lines.Add('> These programs are **not** removed from outputs. They are tagged as')
        $lines.Add('> potential exclusion candidates for downstream filtering.')
        $lines.Add('')
        $lines.Add('| Program | Reason | Rule | Detail |')
        $lines.Add('|---|---|---|---|')
        foreach ($c in @($excl.candidates)) {
            foreach ($r in @($c.reasons)) {
                $lines.Add("| $($c.program) | $($r.reason) | $($r.rule) | $($r.detail) |")
            }
        }
        $lines.Add('')
    }

    if ($class -and $class.categoryCounts) {
        $lines.Add('## Classification Snapshot')
        $lines.Add('')
        $lines.Add('| Category | Count |')
        $lines.Add('|---|---:|')
        foreach ($p in ($class.categoryCounts.PSObject.Properties | Sort-Object Name)) {
            $lines.Add("| $($p.Name) | $($p.Value) |")
        }
        $lines.Add('')
    }

    Set-Content -LiteralPath $OutputPath -Value ($lines -join "`r`n") -Encoding UTF8
    return $OutputPath
}
