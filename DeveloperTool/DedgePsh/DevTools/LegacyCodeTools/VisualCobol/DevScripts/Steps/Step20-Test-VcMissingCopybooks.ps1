#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies which copybook files referenced by CBL programs are missing.
.DESCRIPTION
    Parses all COPY statements from CBL source files and checks whether each
    referenced copybook exists in the known copybook search paths. Produces a
    structured report (JSON + TSV) of missing copybooks and a summary of the
    most impactful gaps.

    Parsing covers:
      COPY "name.ext"   COPY 'name.ext'   COPY name   EXEC SQL INCLUDE name

    Search order per the COBOL copy element naming rule:
      1. Same folder as the CBL file
      2. cpy/ folder (.CPY, .CPB)
      3. sys/cpy/ folder (.DCL, .CPX)

    Leverages patterns from CblPackageBatch.ps1 HandleCopyElements and FkStack.
.PARAMETER SourceFolder
    Folder containing CBL files to scan.
.PARAMETER CopybookFolders
    Array of folders to search for copybooks. Defaults to repo + VCPATH paths.
.PARAMETER OutputFolder
    Where to write reports. Defaults to Get-ApplicationDataPath.
.PARAMETER SendNotification
    Send SMS summary on completion.
.EXAMPLE
    .\Test-VcMissingCopybooks.ps1
.EXAMPLE
    .\Test-VcMissingCopybooks.ps1 -SourceFolder 'C:\opt\data\AutoDocJson\tmp\DedgeRepository\Dedge\cbl'
#>
[CmdletBinding()]
param(
    [string]$SourceFolder = '',

    [string[]]$CopybookFolders = @(),

    [string]$OutputFolder = '',

    [switch]$SendNotification
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

# --- Resolve source folder ---
if ([string]::IsNullOrEmpty($SourceFolder)) {
    $candidates = @(
        'C:\opt\data\AutoDocJson\tmp\DedgeRepository\Dedge\cbl',
        (Join-Path (Get-ApplicationDataPath) 'LocalCopies\src\fkavd_NT')
    )
    $vcCbl = if ($env:VCPATH) { Join-Path $env:VCPATH 'src\cbl' } else { 'C:\fkavd\Dedge2\src\cbl' }
    $candidates += $vcCbl

    foreach ($c in $candidates) {
        if (Test-Path $c) {
            $SourceFolder = $c
            break
        }
    }
}

if ([string]::IsNullOrEmpty($SourceFolder) -or -not (Test-Path $SourceFolder)) {
    Write-LogMessage "No CBL source folder found. Specify -SourceFolder." -Level ERROR
    exit 1
}

# --- Resolve copybook search folders ---
if ($CopybookFolders.Count -eq 0) {
    $repoBase = 'C:\opt\data\AutoDocJson\tmp\DedgeRepository\Dedge'
    $vcPath = if ($env:VCPATH) { $env:VCPATH } else { 'C:\fkavd\Dedge2' }

    $defaultFolders = @(
        $SourceFolder,
        (Join-Path $repoBase 'cpy'),
        (Join-Path $repoBase 'sys\cpy'),
        (Join-Path $repoBase 'gs'),
        (Join-Path $vcPath 'src\cbl'),
        (Join-Path $vcPath 'src\cbl\cpy'),
        (Join-Path $vcPath 'src\cbl\cpy\sys\cpy'),
        (Join-Path $vcPath 'src\cbl\imp'),
        '\\DEDGE.fk.no\erputv\Utvikling\fkavd\NT',
        '\\DEDGE.fk.no\erputv\Utvikling\fkavd\Sys\cpy'
    )

    foreach ($df in $defaultFolders) {
        if (Test-Path $df -ErrorAction SilentlyContinue) {
            $CopybookFolders += $df
        }
    }
}

# --- Resolve output folder ---
if ([string]::IsNullOrEmpty($OutputFolder)) {
    $OutputFolder = Get-ApplicationDataPath
}
New-Item -Path $OutputFolder -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

Write-LogMessage "Test-VcMissingCopybooks starting" -Level INFO
Write-LogMessage "  Source folder: $($SourceFolder)" -Level INFO
Write-LogMessage "  Copybook search folders: $($CopybookFolders.Count)" -Level INFO
foreach ($cf in $CopybookFolders) {
    Write-LogMessage "    $($cf)" -Level DEBUG
}

# --- Build copybook index (case-insensitive lookup) ---
Write-LogMessage "Building copybook index from $($CopybookFolders.Count) folders..." -Level INFO

$copybookIndex = @{}
foreach ($folder in $CopybookFolders) {
    try {
        $files = Get-ChildItem -Path $folder -File -ErrorAction SilentlyContinue
        if (-not $files) { continue }
        foreach ($f in $files) {
            $key = $f.Name.ToUpper()
            if (-not $copybookIndex.ContainsKey($key)) {
                $copybookIndex[$key] = $f.FullName
            }
        }
    } catch {
        Write-LogMessage "  Cannot index folder: $($folder)" -Level WARN
    }
}

Write-LogMessage "Indexed $($copybookIndex.Count) unique copybook files" -Level INFO

# --- Parse COPY statements from CBL files ---
$cblFiles = Get-ChildItem -Path $SourceFolder -Filter '*.cbl' -File -ErrorAction SilentlyContinue
if (-not $cblFiles -or $cblFiles.Count -eq 0) {
    Write-LogMessage "No CBL files found in $($SourceFolder)" -Level ERROR
    exit 1
}

Write-LogMessage "Scanning $($cblFiles.Count) CBL files for COPY statements..." -Level INFO

# Regex patterns:
#   Pattern 1: COPY "file.ext" or COPY 'file.ext' (quoted, with extension)
#   Pattern 2: COPY BARE_NAME. (unquoted, no extension — e.g. COPY SQLENV.)
#   Pattern 3: EXEC SQL INCLUDE name END-EXEC
$patternQuoted = '(?i)^\s{0,6}\s*COPY\s+[""'']([^""'']+)[""'']'
$patternBare   = '(?i)^\s{0,6}\s*COPY\s+([A-Za-z0-9_-]+)\s*\.'
$patternExecSql = '(?i)EXEC\s+SQL\s+INCLUDE\s+([A-Za-z0-9_-]+)\s+END-EXEC'

$allReferences = [System.Collections.Generic.List[PSCustomObject]]::new()
$missingReferences = [System.Collections.Generic.List[PSCustomObject]]::new()
$foundCopybooks = @{}
$missingCopybooks = @{}
$programsScanned = 0

foreach ($cbl in $cblFiles) {
    $programsScanned++
    $progName = [System.IO.Path]::GetFileNameWithoutExtension($cbl.Name).ToUpper()

    try {
        $lines = Get-Content -Path $cbl.FullName -ErrorAction SilentlyContinue
    } catch {
        Write-LogMessage "  Cannot read $($cbl.Name)" -Level WARN
        continue
    }

    if (-not $lines) { continue }

    $progCopies = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($line in $lines) {
        $copyName = $null

        if ($line -match $patternQuoted) {
            $copyName = $Matches[1].Trim()
        }
        elseif ($line -match $patternBare) {
            $copyName = $Matches[1].Trim()
        }
        elseif ($line -match $patternExecSql) {
            $copyName = $Matches[1].Trim()
        }

        if ([string]::IsNullOrEmpty($copyName)) { continue }
        if ($progCopies.Contains($copyName)) { continue }
        [void]$progCopies.Add($copyName)

        $copyNameUpper = $copyName.ToUpper()
        $ext = [System.IO.Path]::GetExtension($copyName).ToUpper()

        # Determine expected folder based on extension
        $expectedFolder = switch ($ext) {
            '.DCL' { 'sys/cpy/' }
            '.CPX' { 'sys/cpy/' }
            '.CPB' { 'cpy/' }
            '.CPY' { 'cpy/' }
            '.MF'  { 'runtime' }
            '.GS'  { 'gs/' }
            '.IMP' { 'imp/' }
            default { 'cpy/ or same folder' }
        }

        $found = $false
        $foundIn = ''

        # Check index
        if ($copybookIndex.ContainsKey($copyNameUpper)) {
            $found = $true
            $foundIn = $copybookIndex[$copyNameUpper]
        }
        # Bare names (no extension) — try common extensions
        elseif ([string]::IsNullOrEmpty($ext)) {
            foreach ($tryExt in @('.CPY', '.CPB', '.DCL', '.CPX', '.MF', '.GS')) {
                $tryName = "$($copyNameUpper)$($tryExt)"
                if ($copybookIndex.ContainsKey($tryName)) {
                    $found = $true
                    $foundIn = $copybookIndex[$tryName]
                    $copyNameUpper = $tryName
                    break
                }
            }
        }

        $ref = [PSCustomObject]@{
            Program        = $progName
            CopyElement    = $copyName
            Extension      = if ([string]::IsNullOrEmpty($ext)) { '(bare)' } else { $ext }
            ExpectedFolder = $expectedFolder
            Status         = if ($found) { 'FOUND' } else { 'MISSING' }
            FoundIn        = $foundIn
        }
        $allReferences.Add($ref)

        if ($found) {
            if (-not $foundCopybooks.ContainsKey($copyNameUpper)) {
                $foundCopybooks[$copyNameUpper] = [System.Collections.Generic.List[string]]::new()
            }
            $foundCopybooks[$copyNameUpper].Add($progName)
        } else {
            $missingReferences.Add($ref)
            if (-not $missingCopybooks.ContainsKey($copyNameUpper)) {
                $missingCopybooks[$copyNameUpper] = [System.Collections.Generic.List[string]]::new()
            }
            $missingCopybooks[$copyNameUpper].Add($progName)
        }
    }

    if ($programsScanned % 500 -eq 0) {
        Write-LogMessage "  Progress: $($programsScanned)/$($cblFiles.Count) programs" -Level INFO
    }
}

Write-LogMessage "Scan complete: $($programsScanned) programs, $($allReferences.Count) COPY references" -Level INFO

# --- Generate reports ---
$uniqueMissing = $missingCopybooks.Keys | Sort-Object
$uniqueFound = $foundCopybooks.Keys | Sort-Object

# Most impactful missing copybooks (used by most programs)
$impactRanking = $missingCopybooks.GetEnumerator() |
    Sort-Object { $_.Value.Count } -Descending |
    Select-Object -First 30

# JSON report
$jsonReport = [ordered]@{
    GeneratedAt          = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Script               = 'Test-VcMissingCopybooks.ps1'
    SourceFolder         = $SourceFolder
    CopybookFoldersCount = $CopybookFolders.Count
    ProgramsScanned      = $programsScanned
    TotalCopyReferences  = $allReferences.Count
    UniqueCopybooksFound = $uniqueFound.Count
    UniqueCopybooksMissing = $uniqueMissing.Count
    MissingReferenceCount = $missingReferences.Count
    MostImpactedMissing  = @($impactRanking | ForEach-Object {
        [ordered]@{
            Copybook     = $_.Key
            UsedByCount  = $_.Value.Count
            UsedBy       = @($_.Value | Sort-Object)
        }
    })
    AllMissing           = @($missingReferences | ForEach-Object {
        [ordered]@{
            Program        = $_.Program
            CopyElement    = $_.CopyElement
            Extension      = $_.Extension
            ExpectedFolder = $_.ExpectedFolder
        }
    })
}

$jsonPath = Join-Path $OutputFolder "MissingCopybooks-$($timestamp).json"
$jsonReport | ConvertTo-Json -Depth 5 | Out-File -FilePath $jsonPath -Encoding utf8 -Force
Write-LogMessage "JSON report: $($jsonPath)" -Level INFO

# TSV report — missing references
$tsvPath = Join-Path $OutputFolder "MissingCopybooks-$($timestamp).tsv"
$tsvHeader = @('Program', 'CopyElement', 'Extension', 'ExpectedFolder', 'Status')
$tsvLines = [System.Collections.Generic.List[string]]::new()
$tsvLines.Add(($tsvHeader -join "`t"))
foreach ($r in $missingReferences) {
    $vals = @($r.Program, $r.CopyElement, $r.Extension, $r.ExpectedFolder, $r.Status)
    $tsvLines.Add(($vals -join "`t"))
}
$tsvLines | Out-File -FilePath $tsvPath -Encoding utf8 -Force
Write-LogMessage "TSV report: $($tsvPath)" -Level INFO

# TSV impact report — most impactful missing copybooks
$impactTsvPath = Join-Path $OutputFolder "MissingCopybooks-Impact-$($timestamp).tsv"
$impactHeader = @('Copybook', 'UsedByCount', 'UsedByPrograms')
$impactLines = [System.Collections.Generic.List[string]]::new()
$impactLines.Add(($impactHeader -join "`t"))
foreach ($item in $impactRanking) {
    $vals = @($item.Key, $item.Value.Count, ($item.Value -join ', '))
    $impactLines.Add(($vals -join "`t"))
}
$impactLines | Out-File -FilePath $impactTsvPath -Encoding utf8 -Force
Write-LogMessage "Impact TSV: $($impactTsvPath)" -Level INFO

# --- Console summary ---
Write-LogMessage '--- SUMMARY ---' -Level INFO
Write-LogMessage "Programs scanned:         $($programsScanned)" -Level INFO
Write-LogMessage "Total COPY references:    $($allReferences.Count)" -Level INFO
Write-LogMessage "Unique copybooks found:   $($uniqueFound.Count)" -Level INFO
Write-LogMessage "Unique copybooks MISSING: $($uniqueMissing.Count)" -Level INFO
Write-LogMessage "Missing references total: $($missingReferences.Count)" -Level INFO

if ($impactRanking.Count -gt 0) {
    Write-LogMessage '--- TOP 10 MOST IMPACTFUL MISSING COPYBOOKS ---' -Level INFO
    $top10 = $impactRanking | Select-Object -First 10
    foreach ($item in $top10) {
        Write-LogMessage "  $($item.Key): used by $($item.Value.Count) programs" -Level INFO
    }
}

# Extension breakdown of missing copybooks
$extBreakdown = $missingReferences | Group-Object Extension | Sort-Object Count -Descending
if ($extBreakdown.Count -gt 0) {
    Write-LogMessage '--- MISSING BY EXTENSION ---' -Level INFO
    foreach ($grp in $extBreakdown) {
        Write-LogMessage "  $($grp.Name): $($grp.Count) references" -Level INFO
    }
}

Write-LogMessage "JSON: $($jsonPath)" -Level INFO
Write-LogMessage "TSV:  $($tsvPath)" -Level INFO
Write-LogMessage "Impact: $($impactTsvPath)" -Level INFO

if ($SendNotification) {
    $smsNumber = switch ($env:USERNAME) {
        'FKGEISTA' { '+4797188358' }
        'FKSVEERI' { '+4795762742' }
        'FKMISTA'  { '+4799348397' }
        'FKCELERI' { '+4745269945' }
        default    { '+4797188358' }
    }
    $msg = "CopybookCheck: $($programsScanned) progs, $($uniqueFound.Count) found, $($uniqueMissing.Count) missing"
    Send-Sms -Receiver $smsNumber -Message $msg
}
