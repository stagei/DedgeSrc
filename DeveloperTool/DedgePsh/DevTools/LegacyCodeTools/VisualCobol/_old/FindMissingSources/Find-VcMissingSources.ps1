#Requires -Version 7.0
<#
.SYNOPSIS
    Deep fuzzy search for missing COBOL source programs across discovered folders.
.DESCRIPTION
    Two-phase COBOL source collection and analysis.

    Phase 1 — Comprehensive sweep: copies ALL files from every search folder
    into a structured destination tree:
      cbl/             .CBL/.COB files (certain COBOL sources)
      cbl_uncertain/   Unknown-extension files with COBOL program structure
      cpy/             Known copybook/artifact extensions (.CPY .CPB .DCL .CPX
                       .GS .IMP .MF .INT .IDY)
      cpy_uncertain/   Unknown-extension files with some COBOL markers

    Phase 2 — Missing program analysis: searches for specific missing program
    names using exact and fuzzy filename matching, references files already
    collected in Phase 1, and produces a report with recommendations and
    move commands.

    Search strategy per program (e.g. BKFINFA):
      1. Exact match: BKFINFA.CBL (case-insensitive)
      2. Fuzzy: any file whose name contains BKFINFA as a substring
      3. All-extension: BKFINFA.* — catches .cbl_del, .bak, .old, etc.

    COBOL content verification checks first 50 lines for markers:
      IDENTIFICATION DIVISION, PROGRAM-ID, DATA DIVISION, PROCEDURE DIVISION,
      WORKING-STORAGE SECTION, Column 7 * comments, EXEC SQL.
.PARAMETER MigrationReportJson
    Path to the migration status report JSON (to extract NO_SOURCE programs).
.PARAMETER FolderInventoryJson
    Path to the CobolFolderInventory JSON from Search-VcCobolFolders.ps1.
.PARAMETER MissingPrograms
    Override: explicit list of missing program names (skips reading from JSON).
.PARAMETER GeneralSourceFolder
    Target folder for confirmed sources. Used in generated move commands.
.PARAMETER OutputFolder
    Where to write reports (JSON, TSV).
.PARAMETER DestinationFolder
    Where to copy found source files. Defaults to $env:OptPath\data\VisualCobol\Sources.
    Creates four subfolders: cbl\, cbl_uncertain\, cpy\, cpy_uncertain\.
    Classification is based on file extension and COBOL content analysis.
.PARAMETER SendNotification
    Send SMS summary on completion.
.EXAMPLE
    .\Find-VcMissingSources.ps1
.EXAMPLE
    .\Find-VcMissingSources.ps1 -MissingPrograms @('BRHDEBX','BSAOPVA') -SendNotification
#>
[CmdletBinding()]
param(
    [string]$MigrationReportJson = '',
    [string]$FolderInventoryJson = '',
    [string[]]$MissingPrograms = @(),
    [string]$GeneralSourceFolder = '',
    [string]$OutputFolder = '',
    [string]$DestinationFolder = '',
    [switch]$SendNotification
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

# --- Resolve output folder ---
if ([string]::IsNullOrEmpty($OutputFolder)) {
    $OutputFolder = Get-ApplicationDataPath
}
New-Item -Path $OutputFolder -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

# --- Resolve destination folder for found sources ---
if ([string]::IsNullOrEmpty($DestinationFolder)) {
    $optPath = if ($env:OptPath) { $env:OptPath } else { 'C:\opt' }
    $DestinationFolder = Join-Path $optPath 'data\VisualCobol\Sources'
}
$cblFolder = Join-Path $DestinationFolder 'cbl'
$cblUncertainFolder = Join-Path $DestinationFolder 'cbl_uncertain'
$cpyFolder = Join-Path $DestinationFolder 'cpy'
$cpyUncertainFolder = Join-Path $DestinationFolder 'cpy_uncertain'
foreach ($d in @($DestinationFolder, $cblFolder, $cblUncertainFolder, $cpyFolder, $cpyUncertainFolder)) {
    New-Item -Path $d -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
}

# --- Resolve general source folder (for move commands) ---
if ([string]::IsNullOrEmpty($GeneralSourceFolder)) {
    $vcPath = if ($env:VCPATH) { $env:VCPATH } else { 'C:\fkavd\Dedge2' }
    $GeneralSourceFolder = Join-Path $vcPath 'src\cbl'
}

Write-LogMessage "Find-VcMissingSources starting" -Level INFO
Write-LogMessage "  Output folder:         $($OutputFolder)" -Level INFO
Write-LogMessage "  Destination folder:    $($DestinationFolder)" -Level INFO
Write-LogMessage "    cbl/                 $($cblFolder)" -Level INFO
Write-LogMessage "    cbl_uncertain/       $($cblUncertainFolder)" -Level INFO
Write-LogMessage "    cpy/                 $($cpyFolder)" -Level INFO
Write-LogMessage "    cpy_uncertain/       $($cpyUncertainFolder)" -Level INFO
Write-LogMessage "  General source:        $($GeneralSourceFolder)" -Level INFO

# --- Load missing programs ---
if ($MissingPrograms.Count -eq 0) {
    if ([string]::IsNullOrEmpty($MigrationReportJson)) {
        $candidates = Get-ChildItem -Path (Join-Path (Split-Path $OutputFolder) '*') -Filter 'MigrationStatusReport-*.json' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $candidates) {
            $candidates = Get-ChildItem -Path "$($OutputFolder)\MigrationStatusReport-*.json" -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
        }
        if ($candidates) { $MigrationReportJson = $candidates.FullName }
    }

    if (-not [string]::IsNullOrEmpty($MigrationReportJson) -and (Test-Path $MigrationReportJson)) {
        Write-LogMessage "Loading missing programs from: $($MigrationReportJson)" -Level INFO
        $reportData = Get-Content $MigrationReportJson -Raw | ConvertFrom-Json
        $MissingPrograms = @($reportData.Programs | Where-Object { $_.Status -eq 'NO_SOURCE' } | ForEach-Object { $_.Program })
    }
}

if ($MissingPrograms.Count -eq 0) {
    $MissingPrograms = @(
        'BRHDEBX', 'BSAOPVA', 'BSFOPVA', 'D4BCUSTP', 'DBFBRAPG', 'DRHRRAPG',
        'GMAFRTIMEH', 'GMAGUTT', 'GMAMONI', 'GMAMVAGQ', 'GMAOPN3', 'GMAPAYD - KOPI',
        'GMVOKLT', 'GMVSUBR', 'ILXKTAJN', 'M3AM3FMA', 'M3CIDMAS', 'M3HARTGR',
        'M3MITMAS', 'M3VARTGR', 'OKABVFAMEH', 'OKAIOTAT', 'OKHRSPT', 'OKHS430',
        'OKHS450', 'ONHKTSX', 'OSAFORIMEH', 'OSALSTABCK', 'OSATMSCMEH', 'PAOPOP',
        'RDBLAGR_BCK', 'REBGRLAG', 'RKHAVST', 'RKHOBEHMEH', 'TMAVARSI', 'TMBVARSI'
    )
}

Write-LogMessage "Searching for $($MissingPrograms.Count) missing programs" -Level INFO

# --- Load search folders ---
$searchFolders = [System.Collections.Generic.List[string]]::new()

$knownFolders = @(
    '\\DEDGE.fk.no\erputv\Utvikling\fkavd\NT',
    '\\DEDGE.fk.no\erputv\Utvikling\fkavd\utgatt',
    '\\DEDGE.fk.no\erputv\Utvikling\CBLARKIV'
)
foreach ($kf in $knownFolders) { $searchFolders.Add($kf) }

if ([string]::IsNullOrEmpty($FolderInventoryJson)) {
    $invCandidates = Get-ChildItem -Path $OutputFolder -Filter 'CobolFolderInventory-*.json' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $invCandidates) {
        $parentDir = Split-Path $OutputFolder -Parent
        $invCandidates = Get-ChildItem -Path $parentDir -Filter 'CobolFolderInventory-*.json' -Recurse -Depth 1 -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
    }
    if ($invCandidates) { $FolderInventoryJson = $invCandidates.FullName }
}

if (-not [string]::IsNullOrEmpty($FolderInventoryJson) -and (Test-Path $FolderInventoryJson)) {
    Write-LogMessage "Loading folder inventory: $($FolderInventoryJson)" -Level INFO
    $invData = Get-Content $FolderInventoryJson -Raw | ConvertFrom-Json
    foreach ($f in $invData.Folders) {
        if ($searchFolders -notcontains $f.Folder) {
            $searchFolders.Add($f.Folder)
        }
    }
}

# Also add the Git repo source folders
$repoFolders = @(
    'C:\opt\data\AutoDocJson\tmp\DedgeRepository\Dedge\cbl',
    'C:\opt\data\AutoDocJson\tmp\DedgeRepository\Dedge\cpy',
    'C:\opt\data\AutoDocJson\tmp\DedgeRepository\Dedge\gs'
)
foreach ($rf in $repoFolders) {
    if ((Test-Path $rf) -and ($searchFolders -notcontains $rf)) {
        $searchFolders.Add($rf)
    }
}

Write-LogMessage "Total search folders: $($searchFolders.Count)" -Level INFO

# --- COBOL content verification ---
function Test-CobolContent {
    param([string]$FilePath)

    $markers = @(
        'IDENTIFICATION DIVISION',
        'ID DIVISION',
        'PROGRAM-ID',
        'DATA DIVISION',
        'PROCEDURE DIVISION',
        'WORKING-STORAGE SECTION',
        'EXEC SQL',
        'ENVIRONMENT DIVISION',
        'FILE SECTION',
        'LINKAGE SECTION'
    )

    $result = [PSCustomObject]@{
        IsCobol       = $false
        Confidence    = 'NONE'
        MarkerCount   = 0
        MarkersFound  = @()
    }

    try {
        $lines = Get-Content -Path $FilePath -TotalCount 80 -ErrorAction SilentlyContinue
        if (-not $lines -or $lines.Count -eq 0) { return $result }

        $foundMarkers = [System.Collections.Generic.List[string]]::new()
        $col7Comments = 0

        foreach ($line in $lines) {
            $upper = $line.ToUpper().Trim()
            foreach ($m in $markers) {
                if ($upper -match [regex]::Escape($m) -and ($foundMarkers -notcontains $m)) {
                    $foundMarkers.Add($m)
                }
            }
            # Column 7 comment marker (lines must be at least 7 chars, position 6 = '*')
            if ($line.Length -ge 7 -and $line[6] -eq '*') {
                $col7Comments++
            }
        }

        if ($col7Comments -ge 2) { $foundMarkers.Add('COL7-COMMENTS') }

        $result.MarkersFound = @($foundMarkers)
        $result.MarkerCount = $foundMarkers.Count

        if ($foundMarkers.Count -ge 3) {
            $result.IsCobol = $true
            $result.Confidence = 'HIGH'
        } elseif ($foundMarkers.Count -ge 2) {
            $result.IsCobol = $true
            $result.Confidence = 'MEDIUM'
        } elseif ($foundMarkers.Count -ge 1) {
            $result.IsCobol = $false
            $result.Confidence = 'LOW'
        }
    } catch {
        Write-LogMessage "  Error reading $($FilePath): $($_.Exception.Message)" -Level WARN
    }

    return $result
}

# --- Phase 1: Comprehensive file collection from all search folders ---
Write-LogMessage '=== PHASE 1: Collecting ALL files from search folders ===' -Level INFO

$knownCblExtensions = @('.CBL', '.COB')
$knownCpyExtensions = @('.CPY', '.CPB', '.DCL', '.CPX', '.GS', '.IMP', '.MF', '.INT', '.IDY')
$skipExtensions = @('.BND')

$collectStats = @{ cbl = 0; cbl_uncertain = 0; cpy = 0; cpy_uncertain = 0; skipped = 0 }
$collectedFiles = [System.Collections.Generic.Dictionary[string, string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)

foreach ($folder in $searchFolders) {
    if (-not (Test-Path $folder -ErrorAction SilentlyContinue)) { continue }

    try {
        $files = Get-ChildItem -Path $folder -File -ErrorAction SilentlyContinue
    } catch { continue }

    if (-not $files -or $files.Count -eq 0) { continue }

    Write-LogMessage "  Scanning: $($folder) ($($files.Count) files)" -Level INFO

    foreach ($file in $files) {
        $ext = $file.Extension.ToUpper()

        if ($ext -in $skipExtensions) {
            $collectStats.skipped++
            continue
        }

        $targetFolder = $null

        if ($ext -in $knownCblExtensions) {
            $targetFolder = $cblFolder
            $collectStats.cbl++
        } elseif ($ext -in $knownCpyExtensions) {
            $targetFolder = $cpyFolder
            $collectStats.cpy++
        } else {
            $check = Test-CobolContent -FilePath $file.FullName
            if ($check.Confidence -in @('HIGH', 'MEDIUM')) {
                $hasProgStructure = ($check.MarkersFound |
                    Where-Object { $_ -in @('PROGRAM-ID', 'IDENTIFICATION DIVISION', 'ID DIVISION') }).Count -gt 0
                if ($hasProgStructure) {
                    $targetFolder = $cblUncertainFolder
                    $collectStats.cbl_uncertain++
                } else {
                    $targetFolder = $cpyUncertainFolder
                    $collectStats.cpy_uncertain++
                }
            } elseif ($check.Confidence -eq 'LOW') {
                $targetFolder = $cpyUncertainFolder
                $collectStats.cpy_uncertain++
            } else {
                $collectStats.skipped++
                continue
            }
        }

        $destPath = Join-Path $targetFolder $file.Name
        if (Test-Path $destPath) {
            $existingSize = (Get-Item $destPath).Length
            if ($existingSize -eq $file.Length) { continue }
            $counter = 2
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            $fileExt = $file.Extension
            do {
                $destPath = Join-Path $targetFolder "$($baseName)_$($counter)$($fileExt)"
                $counter++
            } while (Test-Path $destPath)
        }

        try {
            Copy-Item -Path $file.FullName -Destination $destPath -Force -ErrorAction SilentlyContinue
            $collectedFiles[$file.FullName] = $destPath
        } catch {
            Write-LogMessage "  Copy failed: $($file.FullName): $($_.Exception.Message)" -Level WARN
        }
    }
}

$totalCollected = $collectStats.cbl + $collectStats.cbl_uncertain + $collectStats.cpy + $collectStats.cpy_uncertain
Write-LogMessage "Collection complete: $($totalCollected) files collected, $($collectStats.skipped) skipped" -Level INFO
Write-LogMessage "  cbl: $($collectStats.cbl)  cbl_uncertain: $($collectStats.cbl_uncertain)" -Level INFO
Write-LogMessage "  cpy: $($collectStats.cpy)  cpy_uncertain: $($collectStats.cpy_uncertain)" -Level INFO

# --- Phase 2: Missing program analysis ---
Write-LogMessage '=== PHASE 2: Missing program analysis ===' -Level INFO
$allResults = [System.Collections.Generic.List[PSCustomObject]]::new()
$programsFound = 0
$programsNotFound = 0

foreach ($prog in $MissingPrograms) {
    Write-LogMessage "Searching for: $($prog)" -Level INFO

    # Normalize program name: strip spaces and special chars for fuzzy matching
    $progClean = $prog -replace '\s+', '' -replace '-', '' -replace '_', ''
    $progBase = ($prog -replace '\s.*$', '').Trim()  # "GMAPAYD - KOPI" -> "GMAPAYD"

    $candidates = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($folder in $searchFolders) {
        if (-not (Test-Path $folder -ErrorAction SilentlyContinue)) { continue }

        try {
            $allFiles = Get-ChildItem -Path $folder -File -ErrorAction SilentlyContinue
        } catch {
            continue
        }

        if (-not $allFiles -or $allFiles.Count -eq 0) { continue }

        foreach ($file in $allFiles) {
            $ext = $file.Extension.ToUpper()

            # Skip non-source artifacts that are never valid CBL candidates
            if ($ext -eq '.BND') { continue }

            $nameNoExt = [System.IO.Path]::GetFileNameWithoutExtension($file.Name).ToUpper()
            $nameNoExtClean = $nameNoExt -replace '\s+', '' -replace '-', '' -replace '_', ''
            $matchType = ''

            # Exact match: filename without extension matches program name exactly
            if ($nameNoExt -eq $progBase.ToUpper() -or $nameNoExt -eq $prog.ToUpper()) {
                $matchType = 'EXACT'
            }
            # Fuzzy: filename contains the program name as substring
            elseif ($nameNoExtClean -match [regex]::Escape($progClean.ToUpper())) {
                $matchType = 'FUZZY_CONTAINS'
            }
            # Fuzzy: program name contains the filename (shorter filename matches)
            elseif ($progClean.ToUpper() -match [regex]::Escape($nameNoExtClean) -and $nameNoExtClean.Length -ge 4) {
                $matchType = 'FUZZY_REVERSE'
            }

            if ([string]::IsNullOrEmpty($matchType)) { continue }

            # Check COBOL content for non-.CBL files or fuzzy matches
            $cobolCheck = $null
            if ($ext -ne '.CBL' -or $matchType -ne 'EXACT') {
                $cobolCheck = Test-CobolContent -FilePath $file.FullName
            } else {
                $cobolCheck = [PSCustomObject]@{
                    IsCobol      = $true
                    Confidence   = 'HIGH'
                    MarkerCount  = 99
                    MarkersFound = @('CBL_EXTENSION')
                }
            }

            $candidate = [PSCustomObject]@{
                Program          = $prog
                CandidateFile    = $file.Name
                CandidateFullPath = $file.FullName
                MatchType        = $matchType
                Extension        = $ext
                LastModified     = $file.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
                LastModifiedSort = $file.LastWriteTime
                FileSize         = $file.Length
                CobolConfidence  = $cobolCheck.Confidence
                MarkerCount      = $cobolCheck.MarkerCount
                MarkersFound     = ($cobolCheck.MarkersFound -join '; ')
                ProposedFilename = "$($progBase.ToUpper()).CBL"
                LocalCopyPath    = ''
                MoveCommand      = ''
                Folder           = $folder
            }

            $candidates.Add($candidate)
        }
    }

    if ($candidates.Count -gt 0) {
        $programsFound++
        Write-LogMessage "  Found $($candidates.Count) candidate(s) for $($prog)" -Level INFO

        # Sort: EXACT first, then prioritize trusted folders (NT > BACKUP-20160310 > others), then by date
        $sorted = $candidates | Sort-Object -Property @(
            @{ Expression = { if ($_.MatchType -eq 'EXACT') { 0 } else { 1 } }; Ascending = $true },
            @{ Expression = {
                if ($_.Folder -match '\\fkavd\\NT$') { 0 }
                elseif ($_.Folder -match '\\fkavd\\utgatt$') { 1 }
                elseif ($_.Folder -match 'CBLARKIV$') { 2 }
                elseif ($_.Folder -match 'BACKUP-20160310') { 3 }
                else { 4 }
            }; Ascending = $true },
            @{ Expression = { $_.LastModifiedSort }; Descending = $true }
        )

        $isRecommended = $true
        foreach ($c in $sorted) {
            # Reference the file already collected in Phase 1
            if ($collectedFiles.ContainsKey($c.CandidateFullPath)) {
                $c.LocalCopyPath = $collectedFiles[$c.CandidateFullPath]
            } else {
                $c.LocalCopyPath = 'NOT_COLLECTED'
            }

            # Move command targets the VCPATH source tree; cpy for non-CBL extensions
            $moveTarget = if ($c.Extension -eq '.CBL') {
                "$($GeneralSourceFolder)\$($c.ProposedFilename)"
            } else {
                "$($GeneralSourceFolder)\cpy\$($c.CandidateFile)"
            }
            $localRef = if ($c.LocalCopyPath -ne 'NOT_COLLECTED') { $c.LocalCopyPath } else { $c.CandidateFullPath }
            $c.MoveCommand = "Move-Item -Path '$($localRef)' -Destination '$($moveTarget)' -Force"

            # Tag the first (best) candidate as recommended
            if ($isRecommended) {
                $c | Add-Member -NotePropertyName 'Recommended' -NotePropertyValue $true -Force
                $isRecommended = $false
            } else {
                $c | Add-Member -NotePropertyName 'Recommended' -NotePropertyValue $false -Force
            }

            $allResults.Add($c)
        }
    } else {
        $programsNotFound++
        Write-LogMessage "  No candidates found for $($prog)" -Level WARN

        $allResults.Add([PSCustomObject]@{
            Program          = $prog
            CandidateFile    = ''
            CandidateFullPath = ''
            MatchType        = 'NOT_FOUND'
            Extension        = ''
            LastModified     = ''
            LastModifiedSort = [datetime]::MinValue
            FileSize         = 0
            CobolConfidence  = 'NONE'
            MarkerCount      = 0
            MarkersFound     = ''
            ProposedFilename = "$($progBase.ToUpper()).CBL"
            LocalCopyPath    = ''
            MoveCommand      = ''
            Folder           = ''
            Recommended      = $false
        })
    }
}

# --- Generate report ---
Write-LogMessage "Results: $($programsFound) found, $($programsNotFound) still missing" -Level INFO

# JSON report
$jsonReport = [ordered]@{
    GeneratedAt      = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Script           = 'Find-VcMissingSources.ps1'
    TotalPrograms    = $MissingPrograms.Count
    ProgramsFound    = $programsFound
    ProgramsNotFound = $programsNotFound
    DestinationFolder    = $DestinationFolder
    CblFolder            = $cblFolder
    CblUncertainFolder   = $cblUncertainFolder
    CpyFolder            = $cpyFolder
    CpyUncertainFolder   = $cpyUncertainFolder
    CollectionStats      = $collectStats
    TotalFilesCollected  = $totalCollected
    GeneralSourceFolder  = $GeneralSourceFolder
    SearchFoldersCount = $searchFolders.Count
    Results          = @($allResults | ForEach-Object {
        [ordered]@{
            Program          = $_.Program
            CandidateFile    = $_.CandidateFile
            CandidateFullPath = $_.CandidateFullPath
            MatchType        = $_.MatchType
            Extension        = $_.Extension
            LastModified     = $_.LastModified
            FileSize         = $_.FileSize
            CobolConfidence  = $_.CobolConfidence
            MarkerCount      = $_.MarkerCount
            MarkersFound     = $_.MarkersFound
            ProposedFilename = $_.ProposedFilename
            LocalCopyPath    = $_.LocalCopyPath
            MoveCommand      = $_.MoveCommand
            Folder           = $_.Folder
            Recommended      = $_.Recommended
        }
    })
}

$jsonPath = Join-Path $OutputFolder "MissingSources-$($timestamp).json"
$jsonReport | ConvertTo-Json -Depth 5 | Out-File -FilePath $jsonPath -Encoding utf8 -Force
Write-LogMessage "JSON report: $($jsonPath)" -Level INFO

# TSV report
$tsvPath = Join-Path $OutputFolder "MissingSources-$($timestamp).tsv"
$tsvHeader = @('Program', 'CandidateFile', 'CandidateFullPath', 'MatchType', 'Extension',
               'LastModified', 'FileSize', 'CobolConfidence', 'MarkerCount', 'MarkersFound',
               'ProposedFilename', 'LocalCopyPath', 'MoveCommand', 'Folder', 'Recommended')
$tsvLines = [System.Collections.Generic.List[string]]::new()
$tsvLines.Add(($tsvHeader -join "`t"))
foreach ($r in $allResults) {
    $vals = @(
        $r.Program, $r.CandidateFile, $r.CandidateFullPath, $r.MatchType, $r.Extension,
        $r.LastModified, $r.FileSize, $r.CobolConfidence, $r.MarkerCount, $r.MarkersFound,
        $r.ProposedFilename, $r.LocalCopyPath, $r.MoveCommand, $r.Folder, $r.Recommended
    )
    $tsvLines.Add(($vals -join "`t"))
}
$tsvLines | Out-File -FilePath $tsvPath -Encoding utf8 -Force
Write-LogMessage "TSV report: $($tsvPath)" -Level INFO

# --- Console summary ---
Write-LogMessage '=== SUMMARY ===' -Level INFO
Write-LogMessage "Phase 1 - File collection:" -Level INFO
Write-LogMessage "  Total collected: $($totalCollected)  (skipped: $($collectStats.skipped))" -Level INFO
Write-LogMessage "  cbl:             $($collectStats.cbl)" -Level INFO
Write-LogMessage "  cbl_uncertain:   $($collectStats.cbl_uncertain)" -Level INFO
Write-LogMessage "  cpy:             $($collectStats.cpy)" -Level INFO
Write-LogMessage "  cpy_uncertain:   $($collectStats.cpy_uncertain)" -Level INFO
Write-LogMessage "Phase 2 - Missing program analysis:" -Level INFO
Write-LogMessage "  Programs searched:        $($MissingPrograms.Count)" -Level INFO
Write-LogMessage "  Programs with candidates: $($programsFound)" -Level INFO
Write-LogMessage "  Programs still missing:   $($programsNotFound)" -Level INFO
Write-LogMessage "  Total candidates:         $(($allResults | Where-Object { $_.MatchType -ne 'NOT_FOUND' }).Count)" -Level INFO
Write-LogMessage "Reports:" -Level INFO
Write-LogMessage "  JSON: $($jsonPath)" -Level INFO
Write-LogMessage "  TSV:  $($tsvPath)" -Level INFO
Write-LogMessage "Destination: $($DestinationFolder)" -Level INFO

# List recommended moves
$recommended = $allResults | Where-Object { $_.Recommended -eq $true -and $_.MatchType -ne 'NOT_FOUND' }
if ($recommended.Count -gt 0) {
    Write-LogMessage '--- RECOMMENDED MOVE COMMANDS ---' -Level INFO
    foreach ($r in $recommended) {
        Write-LogMessage "  $($r.Program): $($r.MoveCommand)" -Level INFO
    }
}

# List still missing
$stillMissing = $allResults | Where-Object { $_.MatchType -eq 'NOT_FOUND' }
if ($stillMissing.Count -gt 0) {
    Write-LogMessage '--- STILL MISSING (no candidates) ---' -Level WARN
    foreach ($m in $stillMissing) {
        Write-LogMessage "  $($m.Program)" -Level WARN
    }
}

if ($SendNotification) {
    $smsNumber = switch ($env:USERNAME) {
        'FKGEISTA' { '+4797188358' }
        'FKSVEERI' { '+4795762742' }
        'FKMISTA'  { '+4799348397' }
        'FKCELERI' { '+4745269945' }
        default    { '+4797188358' }
    }
    $msg = "VcSources: $($totalCollected) files collected (cbl:$($collectStats.cbl) cpy:$($collectStats.cpy) uncertain:$($collectStats.cbl_uncertain + $collectStats.cpy_uncertain)). MissingProg: $($programsFound)/$($MissingPrograms.Count) found, $($programsNotFound) still missing"
    Send-Sms -Receiver $smsNumber -Message $msg
}
