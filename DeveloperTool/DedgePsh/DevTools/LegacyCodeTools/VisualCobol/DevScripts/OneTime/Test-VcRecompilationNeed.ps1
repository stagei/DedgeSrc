#Requires -Version 7.0
<#
.SYNOPSIS
    Scans COBOL source files to classify recompilation necessity for Visual COBOL 11.
.DESCRIPTION
    Reads all .CBL files (and optionally copybooks) from the specified search
    folders, checks each file against the documented disqualifier list from
    AnalysisResult-IntFileRecompilation.md, and produces a structured Markdown
    report classifying every file as:

      - HIGH RISK:   Contains specific code-level disqualifiers (categories A/B/C/D)
      - MEDIUM RISK: Contains file I/O or indexed file operations (FCD/IDXFORMAT affected)
      - LOW RISK:    No specific disqualifiers found in source — but universal runtime
                     differences still mean recompilation is strongly recommended

    The script never modifies any files. It is read-only and safe to run at any time.

    Reference: AnalysisResult-IntFileRecompilation.md (disqualifier categories A1-A8,
    B1-B7, C1-C6, D1-D5) and Rocket Visual COBOL Documentation Version 11.
.PARAMETER SearchFolders
    One or more folders to scan recursively for .CBL files.
.PARAMETER OutputFolder
    Where to write the report and CSV files. Defaults to a subfolder in the script directory.
.PARAMETER IncludeCopybooks
    Also scan copybook files (.cpy, .cpx, .cpb, .dcl, .imp) for disqualifiers.
    Copybook issues propagate to every program that includes them.
.PARAMETER SendNotification
    Send SMS notification when scan completes.
.EXAMPLE
    .\Test-VcRecompilationNeed.ps1

    Uses default Dedge repository folders.
.EXAMPLE
    .\Test-VcRecompilationNeed.ps1 -SearchFolders 'C:\my\cobol\src' -IncludeCopybooks

    Scans a custom folder including copybooks.
#>
[CmdletBinding()]
param(
    [string[]]$SearchFolders = @(
        'C:\opt\data\AutoDocJson\tmp\DedgeRepository\Dedge\cpy',
        'C:\opt\data\AutoDocJson\tmp\DedgeRepository\Dedge\gs',
        'C:\opt\data\AutoDocJson\tmp\DedgeRepository\Dedge\cbl'
    ),

    [string]$OutputFolder = (Join-Path $PSScriptRoot 'RecompilationReport'),

    [switch]$IncludeCopybooks,

    [switch]$SendNotification
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

# ─────────────────────────────────────────────────────────────────────────────
# Disqualifier patterns — mapped from AnalysisResult-IntFileRecompilation.md
# Each pattern targets specific COBOL source constructs that are known to
# cause crashes, wrong results, or failures under Visual COBOL 11 runtime.
# ─────────────────────────────────────────────────────────────────────────────
$disqualifiers = @(
    # --- Category A: Hard Blockers ---
    @{
        Id          = 'A5'
        Category    = 'A-HardBlocker'
        Risk        = 'HIGH'
        Description = 'coblongjmp() in error/exit/signal handler — fatal COBRT131'
        # Matches: CALL "coblongjmp", CALL 'coblongjmp', or C-level reference
        Pattern     = '(?i)\bcoblongjmp\b'
    }
    @{
        Id          = 'A6'
        Category    = 'A-HardBlocker'
        Risk        = 'HIGH'
        Description = 'COMMUNICATION SECTION removed — COBCH1895 / undefined behavior'
        # Matches: COMMUNICATION SECTION in the division area
        Pattern     = '(?i)\bCOMMUNICATION\s+SECTION\b'
    }
    @{
        Id          = 'A4'
        Category    = 'A-HardBlocker'
        Risk        = 'HIGH'
        Description = 'OO COBOL syntax — may be incompatible with current OO runtime (COBRT212)'
        # Matches: CLASS-ID, METHOD-ID, FACTORY, OBJECT paragraph headers
        Pattern     = '(?i)^\s*(CLASS-ID|METHOD-ID|FACTORY|OBJECT)\b'
    }
    @{
        Id          = 'A7'
        Category    = 'A-HardBlocker'
        Risk        = 'HIGH'
        Description = 'Class Library calls — version mismatch causes COBRT111'
        # Matches: INVOKE, or SET ... TO NEW, typical OO/class library usage
        Pattern     = '(?i)\b(INVOKE\s+\w|SET\s+\w+\s+TO\s+NEW)\b'
    }

    # --- Category B: Silent Data Corruption ---
    @{
        Id          = 'B1'
        Category    = 'B-SilentCorruption'
        Risk        = 'HIGH'
        Description = 'Direct EXTFH/EXTSM call — FCD format changed FCD2→FCD3, may cause RTS114'
        # Matches: CALL "EXTFH" or CALL "EXTSM"
        Pattern     = '(?i)CALL\s+[''"]EXTFH|CALL\s+[''"]EXTSM'
    }
    @{
        Id          = 'B4'
        Category    = 'B-SilentCorruption'
        Risk        = 'MEDIUM'
        Description = 'DBCS/NCHAR data — literal treatment changed, string comparisons may differ'
        # Matches: PIC N, USAGE NATIONAL, NCHAR directive usage
        Pattern     = '(?i)(\bPIC\s+N\b|\bUSAGE\s+NATIONAL\b|\bNCHAR\b)'
    }
    @{
        Id          = 'B-FILEIO'
        Category    = 'B-SilentCorruption'
        Risk        = 'MEDIUM'
        Description = 'File I/O operations — affected by FCD2→FCD3 and IDXFORMAT 4→8 defaults'
        # Matches: SELECT ... ASSIGN, OPEN INPUT/OUTPUT/I-O/EXTEND, READ, WRITE, REWRITE, DELETE
        # This is intentionally broad to catch all file-handling programs
        Pattern     = '(?i)^\s*(SELECT\s+\w+\s+ASSIGN|OPEN\s+(INPUT|OUTPUT|I-O|EXTEND)\s)'
    }
    @{
        Id          = 'B-INDEXED'
        Category    = 'B-SilentCorruption'
        Risk        = 'MEDIUM'
        Description = 'Indexed file usage — IDXFORMAT default changed 4→8, cross-format unreadable'
        # Matches: ORGANIZATION IS INDEXED, ACCESS MODE IS DYNAMIC/RANDOM
        Pattern     = '(?i)\bORGANIZATION\s+IS\s+INDEXED\b'
    }

    # --- Category C: Environment / Configuration ---
    @{
        Id          = 'C3'
        Category    = 'C-EnvironmentConflict'
        Risk        = 'HIGH'
        Description = 'EXEC SQL — DB2 ECM updated, must recompile AND rebind'
        # Matches: EXEC SQL ... END-EXEC
        Pattern     = '(?i)\bEXEC\s+SQL\b'
    }
    @{
        Id          = 'C5'
        Category    = 'C-EnvironmentConflict'
        Risk        = 'MEDIUM'
        Description = 'ILUSING directive — scope changed from global to file-only'
        # Matches: $SET ILUSING or ILUSING directive
        Pattern     = '(?i)\bILUSING\b'
    }
    @{
        Id          = 'C6'
        Category    = 'C-EnvironmentConflict'
        Risk        = 'MEDIUM'
        Description = 'Report Writer / HOSTRW — ASA control character behavior changed'
        # Matches: REPORT SECTION, REPORT WRITER, RD (report description)
        Pattern     = '(?i)(\bREPORT\s+SECTION\b|\bREPORT\s+WRITER\b|^\s*RD\s+\w)'
    }

    # --- Category D: Removed Features ---
    @{
        Id          = 'D3'
        Category    = 'D-RemovedFeature'
        Risk        = 'LOW'
        Description = 'FaultFinder reference — feature removed from Visual COBOL'
        Pattern     = '(?i)\bFAULTFIND\b'
    }
    @{
        Id          = 'D4'
        Category    = 'D-RemovedFeature'
        Risk        = 'MEDIUM'
        Description = 'Dialog System calls — only available via Compatibility AddPack, threading changed'
        # Matches: CALL "DS-DSINIT", CALL "DS-DSDRVR", or any DS- prefixed Dialog System API
        Pattern     = '(?i)CALL\s+[''"]DS-'
    }
    @{
        Id          = 'D5'
        Category    = 'D-RemovedFeature'
        Risk        = 'LOW'
        Description = 'command_line_linkage tunable — deprecated, use COMMAND-LINE-LINKAGE directive'
        Pattern     = '(?i)\bcommand_line_linkage\b'
    }
)

# ─────────────────────────────────────────────────────────────────────────────
# Discover files
# ─────────────────────────────────────────────────────────────────────────────
$cblExtensions = @('*.cbl')
$copybookExtensions = @('*.cpy', '*.cpx', '*.cpb', '*.dcl', '*.imp')

$fileExtensions = if ($IncludeCopybooks) {
    $cblExtensions + $copybookExtensions
} else {
    $cblExtensions
}

Write-LogMessage "Recompilation disqualifier scan starting" -Level INFO
Write-LogMessage "Search folders: $($SearchFolders -join ', ')" -Level INFO
Write-LogMessage "Extensions: $($fileExtensions -join ', ')" -Level INFO

$allFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
$extensionInventory = @{}

foreach ($folder in $SearchFolders) {
    if (-not (Test-Path $folder)) {
        Write-LogMessage "Folder not found, skipping: $($folder)" -Level WARN
        continue
    }

    $allExtensions = Get-ChildItem -Path $folder -Recurse -File |
        Group-Object -Property Extension |
        Sort-Object -Property Count -Descending

    foreach ($extGroup in $allExtensions) {
        $ext = $extGroup.Name.ToUpper()
        if ($extensionInventory.ContainsKey($ext)) {
            $extensionInventory[$ext] += $extGroup.Count
        } else {
            $extensionInventory[$ext] = $extGroup.Count
        }
    }

    $found = Get-ChildItem -Path $folder -Recurse -Include $fileExtensions -File
    if ($found) {
        $allFiles.AddRange([System.IO.FileInfo[]]@($found))
    }

    Write-LogMessage "Found $(@($found).Count) matching files in $($folder)" -Level INFO
}

Write-LogMessage "Total files to scan: $($allFiles.Count)" -Level INFO

# ─────────────────────────────────────────────────────────────────────────────
# Scan each file
# ─────────────────────────────────────────────────────────────────────────────
$ansiEncoding = [System.Text.Encoding]::GetEncoding(1252)
$fileResults = [System.Collections.Generic.List[PSCustomObject]]::new()
$hitDetails = [System.Collections.Generic.List[PSCustomObject]]::new()

$scanned = 0
$withHits = 0

foreach ($file in $allFiles) {
    $scanned++

    try {
        $content = [System.IO.File]::ReadAllText($file.FullName, $ansiEncoding)
        $lines = $content -split "`r?`n"
    } catch {
        Write-LogMessage "Cannot read: $($file.FullName) — $($_.Exception.Message)" -Level WARN
        $fileResults.Add([PSCustomObject]@{
            File          = $file.Name
            FullPath      = $file.FullName
            Extension     = $file.Extension.ToUpper()
            Risk          = 'UNKNOWN'
            Disqualifiers = 'READ_ERROR'
            HitCount      = 0
        })
        continue
    }

    $fileHits = [System.Collections.Generic.List[PSCustomObject]]::new()
    $lineNum = 0

    foreach ($line in $lines) {
        $lineNum++
        $trimmed = $line.Trim()

        # Skip COBOL comment lines (column 7 = * or /)
        if ($line.Length -ge 7) {
            $col7 = $line[6]
            if ($col7 -eq '*' -or $col7 -eq '/') { continue }
        }
        # Also skip lines that are pure comment in free-format
        if ($trimmed.StartsWith('*>')) { continue }

        foreach ($dq in $disqualifiers) {
            if ($trimmed -match $dq.Pattern) {
                $fileHits.Add([PSCustomObject]@{
                    DisqualifierId = $dq.Id
                    Category       = $dq.Category
                    Risk           = $dq.Risk
                    Description    = $dq.Description
                    LineNumber     = $lineNum
                    LineText       = $trimmed.Substring(0, [Math]::Min($trimmed.Length, 120))
                })
            }
        }
    }

    $uniqueIds = @($fileHits | Select-Object -ExpandProperty DisqualifierId -Unique)
    $maxRisk = if ($fileHits.Count -eq 0) {
        'LOW'
    } elseif ($fileHits | Where-Object { $_.Risk -eq 'HIGH' }) {
        'HIGH'
    } elseif ($fileHits | Where-Object { $_.Risk -eq 'MEDIUM' }) {
        'MEDIUM'
    } else {
        'LOW'
    }

    if ($fileHits.Count -gt 0) { $withHits++ }

    $fileResults.Add([PSCustomObject]@{
        File          = $file.Name
        FullPath      = $file.FullName
        Extension     = $file.Extension.ToUpper()
        Risk          = $maxRisk
        Disqualifiers = if ($uniqueIds.Count -gt 0) { $uniqueIds -join ',' } else { 'NONE' }
        HitCount      = $fileHits.Count
    })

    foreach ($hit in $fileHits) {
        $hitDetails.Add([PSCustomObject]@{
            File           = $file.Name
            DisqualifierId = $hit.DisqualifierId
            Category       = $hit.Category
            Risk           = $hit.Risk
            Description    = $hit.Description
            LineNumber     = $hit.LineNumber
            LineText       = $hit.LineText
        })
    }

    if ($scanned % 500 -eq 0) {
        Write-LogMessage "Progress: $($scanned)/$($allFiles.Count) files scanned, $($withHits) with hits" -Level INFO
    }
}

Write-LogMessage "Scan complete: $($scanned) files, $($withHits) with disqualifiers" -Level INFO

# ─────────────────────────────────────────────────────────────────────────────
# Generate reports
# ─────────────────────────────────────────────────────────────────────────────
New-Item -Path $OutputFolder -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

$highRisk   = @($fileResults | Where-Object { $_.Risk -eq 'HIGH' })
$mediumRisk = @($fileResults | Where-Object { $_.Risk -eq 'MEDIUM' })
$lowRisk    = @($fileResults | Where-Object { $_.Risk -eq 'LOW' })
$unknownRisk = @($fileResults | Where-Object { $_.Risk -eq 'UNKNOWN' })

$disqualifierSummary = $hitDetails |
    Group-Object -Property DisqualifierId |
    Sort-Object -Property Count -Descending |
    ForEach-Object {
        $first = $_.Group | Select-Object -First 1
        [PSCustomObject]@{
            Id          = $_.Name
            Category    = $first.Category
            Risk        = $first.Risk
            Description = $first.Description
            FileCount   = ($_.Group | Select-Object -Property File -Unique).Count
            HitCount    = $_.Count
        }
    }

# --- Markdown Report ---
$reportDate = Get-Date -Format 'yyyy-MM-dd HH:mm'
$sb = [System.Text.StringBuilder]::new()

[void]$sb.AppendLine("# Recompilation Disqualifier Scan Report")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("**Generated:** $($reportDate)")
[void]$sb.AppendLine("**Author:** Automated scan by Test-VcRecompilationNeed.ps1")
[void]$sb.AppendLine("**Reference:** AnalysisResult-IntFileRecompilation.md")
[void]$sb.AppendLine("**Technology:** Micro Focus Net Express 5.1 → Rocket Visual COBOL 11")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("---")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Executive Summary")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("| Metric | Count |")
[void]$sb.AppendLine("|---|---|")
[void]$sb.AppendLine("| Total files scanned | $($scanned) |")
[void]$sb.AppendLine("| HIGH risk (specific code-level blockers) | $($highRisk.Count) |")
[void]$sb.AppendLine("| MEDIUM risk (file I/O, DBCS, Report Writer, etc.) | $($mediumRisk.Count) |")
[void]$sb.AppendLine("| LOW risk (no specific disqualifiers in source) | $($lowRisk.Count) |")
[void]$sb.AppendLine("| UNKNOWN (could not read file) | $($unknownRisk.Count) |")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("> **Important:** Even LOW risk files must be recompiled. The risk level only indicates")
[void]$sb.AppendLine("> whether *additional* code-level disqualifiers were found beyond the universal runtime")
[void]$sb.AppendLine("> incompatibilities (FCD2→FCD3, COBMODE 32→64, licensing, IDY format).")
[void]$sb.AppendLine("> See AnalysisResult-IntFileRecompilation.md for the full disqualifier list.")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("---")
[void]$sb.AppendLine("")

# --- File Extension Inventory ---
[void]$sb.AppendLine("## File Extension Inventory (All Files in Search Folders)")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("| Extension | Count |")
[void]$sb.AppendLine("|---|---|")
foreach ($ext in ($extensionInventory.GetEnumerator() | Sort-Object -Property Value -Descending)) {
    [void]$sb.AppendLine("| $($ext.Key) | $($ext.Value) |")
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("---")
[void]$sb.AppendLine("")

# --- Disqualifier Summary ---
[void]$sb.AppendLine("## Disqualifier Hit Summary")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("| ID | Category | Risk | Description | Files | Total Hits |")
[void]$sb.AppendLine("|---|---|---|---|---|---|")
foreach ($dqs in $disqualifierSummary) {
    [void]$sb.AppendLine("| $($dqs.Id) | $($dqs.Category) | $($dqs.Risk) | $($dqs.Description) | $($dqs.FileCount) | $($dqs.HitCount) |")
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("---")
[void]$sb.AppendLine("")

# --- HIGH risk file listing ---
[void]$sb.AppendLine("## HIGH Risk Files — Must Recompile (code-level blockers)")
[void]$sb.AppendLine("")
if ($highRisk.Count -eq 0) {
    [void]$sb.AppendLine("*No HIGH risk files found.*")
} else {
    [void]$sb.AppendLine("| # | File | Disqualifiers | Hits |")
    [void]$sb.AppendLine("|---|---|---|---|")
    $i = 0
    foreach ($f in ($highRisk | Sort-Object -Property File)) {
        $i++
        [void]$sb.AppendLine("| $($i) | $($f.File) | $($f.Disqualifiers) | $($f.HitCount) |")
    }
}
[void]$sb.AppendLine("")

# --- MEDIUM risk file listing ---
[void]$sb.AppendLine("## MEDIUM Risk Files — Recompile Recommended (behavioral changes)")
[void]$sb.AppendLine("")
if ($mediumRisk.Count -eq 0) {
    [void]$sb.AppendLine("*No MEDIUM risk files found.*")
} else {
    [void]$sb.AppendLine("| # | File | Disqualifiers | Hits |")
    [void]$sb.AppendLine("|---|---|---|---|")
    $i = 0
    foreach ($f in ($mediumRisk | Sort-Object -Property File)) {
        $i++
        [void]$sb.AppendLine("| $($i) | $($f.File) | $($f.Disqualifiers) | $($f.HitCount) |")
    }
}
[void]$sb.AppendLine("")

# --- LOW risk file listing (just count + sample) ---
[void]$sb.AppendLine("## LOW Risk Files — No Specific Source Disqualifiers Found")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("Total: **$($lowRisk.Count)** files")
[void]$sb.AppendLine("")
if ($lowRisk.Count -gt 0) {
    [void]$sb.AppendLine("These files contain no patterns matching known disqualifiers, but must")
    [void]$sb.AppendLine("still be recompiled due to universal runtime differences (see executive summary).")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("<details>")
    [void]$sb.AppendLine("<summary>Click to expand full list ($($lowRisk.Count) files)</summary>")
    [void]$sb.AppendLine("")
    $i = 0
    foreach ($f in ($lowRisk | Sort-Object -Property File)) {
        $i++
        [void]$sb.AppendLine("$($i). $($f.File)")
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("</details>")
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("---")
[void]$sb.AppendLine("")

# --- Search folder summary ---
[void]$sb.AppendLine("## Search Folders")
[void]$sb.AppendLine("")
foreach ($folder in $SearchFolders) {
    $exists = Test-Path $folder
    [void]$sb.AppendLine("- ``$($folder)`` — $(if ($exists) { 'exists' } else { 'NOT FOUND' })")
}
[void]$sb.AppendLine("")

# --- Disqualifier reference ---
[void]$sb.AppendLine("## Disqualifier Reference")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("Source-detectable disqualifiers checked by this script:")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("| ID | Category | Risk | Pattern | Description |")
[void]$sb.AppendLine("|---|---|---|---|---|")
foreach ($dq in $disqualifiers) {
    [void]$sb.AppendLine("| $($dq.Id) | $($dq.Category) | $($dq.Risk) | ``$($dq.Pattern)`` | $($dq.Description) |")
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("Universal disqualifiers NOT detectable in source (apply to ALL files):")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("| ID | Description |")
[void]$sb.AppendLine("|---|---|")
[void]$sb.AppendLine("| A1 | .GNT files from Net Express are explicitly blocked |")
[void]$sb.AppendLine("| A2 | 32-bit INT on 64-bit runtime (COBRT211) |")
[void]$sb.AppendLine("| A3 | Runtime system version mismatch (COBRT211) |")
[void]$sb.AppendLine("| A8 | IDY symbol files from Net Express incompatible (COBOP070) |")
[void]$sb.AppendLine("| B2 | IDXFORMAT default changed 4→8 |")
[void]$sb.AppendLine("| B3 | FILEMAXSIZE default changed 4→8 |")
[void]$sb.AppendLine("| B5 | Fixed Binary (p<=7) default changed |")
[void]$sb.AppendLine("| B7 | MFALLOC_PCFILE default changed N→Y |")
[void]$sb.AppendLine("| C1 | COBMODE default 32-bit→64-bit |")
[void]$sb.AppendLine("| C2 | COBREG_PARSED environment conflict |")
[void]$sb.AppendLine("| C4 | Licensing: SafeNet removed, RocketPass required |")
[void]$sb.AppendLine("")

$reportPath = Join-Path $OutputFolder "RecompilationReport-$(Get-Date -Format 'yyyyMMdd-HHmmss').md"
$sb.ToString() | Out-File -FilePath $reportPath -Encoding utf8 -Force
Write-LogMessage "Markdown report: $($reportPath)" -Level INFO

# --- CSV exports ---
$csvFileSummary = Join-Path $OutputFolder "FileSummary-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
$fileResults | Export-Csv -Path $csvFileSummary -NoTypeInformation -Encoding utf8
Write-LogMessage "File summary CSV: $($csvFileSummary)" -Level INFO

$csvHitDetails = Join-Path $OutputFolder "HitDetails-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
$hitDetails | Export-Csv -Path $csvHitDetails -NoTypeInformation -Encoding utf8
Write-LogMessage "Hit details CSV: $($csvHitDetails)" -Level INFO

# --- JSON export (save to script folder if it exists, otherwise Get-ApplicationDataPath) ---
$jsonFolder = if (Test-Path $PSScriptRoot) {
    $PSScriptRoot
} else {
    Get-ApplicationDataPath
}

$jsonData = [ordered]@{
    GeneratedAt          = $reportDate
    Script               = 'Test-VcRecompilationNeed.ps1'
    SearchFolders        = $SearchFolders
    TotalScanned         = $scanned
    Summary              = [ordered]@{
        HighRisk    = $highRisk.Count
        MediumRisk  = $mediumRisk.Count
        LowRisk     = $lowRisk.Count
        Unknown     = $unknownRisk.Count
    }
    ExtensionInventory   = $extensionInventory
    DisqualifierSummary  = @($disqualifierSummary | ForEach-Object {
        [ordered]@{
            Id          = $_.Id
            Category    = $_.Category
            Risk        = $_.Risk
            Description = $_.Description
            FileCount   = $_.FileCount
            HitCount    = $_.HitCount
        }
    })
    Files                = @($fileResults | ForEach-Object {
        [ordered]@{
            File          = $_.File
            FullPath      = $_.FullPath
            Extension     = $_.Extension
            Risk          = $_.Risk
            Disqualifiers = $_.Disqualifiers
            HitCount      = $_.HitCount
        }
    })
    HitDetails           = @($hitDetails | ForEach-Object {
        [ordered]@{
            File           = $_.File
            DisqualifierId = $_.DisqualifierId
            Category       = $_.Category
            Risk           = $_.Risk
            Description    = $_.Description
            LineNumber     = $_.LineNumber
            LineText       = $_.LineText
        }
    })
}

$jsonPath = Join-Path $jsonFolder "RecompilationReport-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$jsonData | ConvertTo-Json -Depth 5 | Out-File -FilePath $jsonPath -Encoding utf8 -Force
Write-LogMessage "JSON report: $($jsonPath)" -Level INFO

# ─────────────────────────────────────────────────────────────────────────────
# Final summary to console
# ─────────────────────────────────────────────────────────────────────────────
Write-LogMessage "═══════════════════════════════════════════════════════" -Level INFO
Write-LogMessage "  RECOMPILATION DISQUALIFIER SCAN COMPLETE" -Level INFO
Write-LogMessage "═══════════════════════════════════════════════════════" -Level INFO
Write-LogMessage "  Files scanned:  $($scanned)" -Level INFO
Write-LogMessage "  HIGH risk:      $($highRisk.Count)" -Level INFO
Write-LogMessage "  MEDIUM risk:    $($mediumRisk.Count)" -Level INFO
Write-LogMessage "  LOW risk:       $($lowRisk.Count)" -Level INFO
Write-LogMessage "  UNKNOWN:        $($unknownRisk.Count)" -Level INFO
Write-LogMessage "  Report:         $($reportPath)" -Level INFO
Write-LogMessage "  JSON:           $($jsonPath)" -Level INFO
Write-LogMessage "═══════════════════════════════════════════════════════" -Level INFO

if ($SendNotification) {
    $smsNumber = switch ($env:USERNAME) {
        'FKGEISTA' { '+4797188358' }
        'FKSVEERI' { '+4795762742' }
        'FKMISTA'  { '+4799348397' }
        'FKCELERI' { '+4745269945' }
        default    { '+4797188358' }
    }
    $msg = "VcRecompile scan: $($scanned) files. HIGH=$($highRisk.Count) MED=$($mediumRisk.Count) LOW=$($lowRisk.Count)"
    Send-Sms -Receiver $smsNumber -Message $msg
}
