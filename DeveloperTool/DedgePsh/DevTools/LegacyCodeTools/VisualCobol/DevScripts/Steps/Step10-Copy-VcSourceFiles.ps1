#Requires -Version 7.0
<#
.SYNOPSIS
    Copies COBOL source files from a repository into the VCPATH folder layout.
.DESCRIPTION
    Copies .CBL, .CPY, .CPX, .CPB, .DCL, .REX, and .BAT files from the Dedge
    repository structure into the standardized VCPATH source layout required by
    the Visual COBOL compilation environment.

    Replaces: OldScripts\VisualCobolCodeMigration\VisualCobolMoveCode.ps1
    Changes from old version:
    - Uses GlobalFunctions Write-LogMessage and Send-Sms
    - Fixed $$ bug (now uses $PSScriptRoot)
    - Parameterized source folder instead of hardcoded PSWorkPath
    - Reports file counts after copy
    - Added -FindMissing mode and additional network search paths

    Source: Rocket Visual COBOL Documentation Version 11 - Compiling COBOL Applications
.EXAMPLE
    .\Copy-VcSourceFiles.ps1 -SourceRepoFolder 'C:\opt\work\VisualCobolCodeMigration\Dedge'
    .\Copy-VcSourceFiles.ps1 -SourceRepoFolder 'C:\opt\work\Dedge' -VcPath 'D:\CobolWork\Dedge2'
.EXAMPLE
    .\Copy-VcSourceFiles.ps1 -SourceRepoFolder 'C:\opt\work\Dedge' -FindMissing -MissingPrograms @('BRHDEBX','BSAOPVA')
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SourceRepoFolder = '',

    [string]$VcPath = $(if ($env:VCPATH) { $env:VCPATH } else { $(Join-Path $env:OptPath 'data\VisualCobol\Copy-VcSourceFiles\Sources') }),

    [switch]$CleanTargetFirst,
    [switch]$SendNotification,

    [switch]$FindMissing,

    [switch]$CollectAll,

    [string]$DestinationFolder = '',

    [string[]]$MissingPrograms = @(),

    [string]$FolderInventoryJson = ''
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

if ($SendNotification) {
    $smsNumber = switch ($env:USERNAME) {
        'FKGEISTA' { '+4797188358' }
        'FKSVEERI' { '+4795762742' }
        'FKMISTA'  { '+4799348397' }
        'FKCELERI' { '+4745269945' }
        default    { '+4797188358' }
    }
}

# --- Additional network source paths discovered by Search-VcCobolFolders.ps1 ---
# Priority: NT/utgatt/CBLARKIV first, then BACKUP-20160310 as trusted source of truth
$additionalSourcePaths = @(
    '\\DEDGE.fk.no\erputv\Utvikling\fkavd\NT',
    '\\DEDGE.fk.no\erputv\Utvikling\fkavd\utgatt',
    '\\DEDGE.fk.no\erputv\Utvikling\CBLARKIV',
    '\\DEDGE.fk.no\erputv\Utvikling\fkavd\BACKUP-20160310',  # Sure find if exact match
    '\\DEDGE.fk.no\erputv\Utvikling\fka\ref',
    '\\DEDGE.fk.no\erputv\Utvikling\fka\work',
    '\\DEDGE.fk.no\erputv\Utvikling\OPT\WORK',
    '\\DEDGE.fk.no\erputv\Utvikling\fkavd\prod',
    '\\DEDGE.fk.no\erputv\Utvikling\fkavd\test',
    '\\DEDGE.fk.no\erputv\Utvikling\fkavd\m3_source',
    '\\DEDGE.fk.no\erputv\Utvikling\fkavd\Copy of WKT_test',
    '\\DEDGE.fk.no\erputv\Utvikling\ROA\CPY',
    '\\DEDGE.fk.no\erputv\Utvikling\fka\sys',
    '\\DEDGE.fk.no\erputv\Utvikling\erik',
    '\\DEDGE.fk.no\erputv\Utvikling\SVI',
    '\\DEDGE.fk.no\erputv\Utvikling\SVI\CPY',
    '\\DEDGE.fk.no\erputv\Utvikling\COBDOK',
    '\\DEDGE.fk.no\erputv\Utvikling\meh',
    '\\DEDGE.fk.no\erputv\Utvikling\esten',
    '\\DEDGE.fk.no\erputv\Utvikling\esten\cbl',
    '\\DEDGE.fk.no\erputv\Utvikling\tru',
    '\\DEDGE.fk.no\erputv\Utvikling\tru\wkmon',
    '\\DEDGE.fk.no\erputv\Utvikling\vkr',
    '\\DEDGE.fk.no\erputv\Utvikling\vkr\backup',
    '\\DEDGE.fk.no\erputv\Utvikling\fkavd\vkat',
    '\\DEDGE.fk.no\erputv\Utvikling\fkavd\wkmoni',
    '\\DEDGE.fk.no\erputv\Utvikling\fkavd\soap',
    '\\DEDGE.fk.no\erputv\Utvikling\Root EDB',
    '\\DEDGE.fk.no\erputv\Utvikling\CITRIX\Backup',
    '\\DEDGE.fk.no\erputv\Utvikling\CITRIX\Backup2',
    '\\DEDGE.fk.no\erputv\Utvikling\Driftregnskap\drfiler',
    '\\DEDGE.fk.no\erputv\Utvikling\Driftregnskap\SV',
    '\\DEDGE.fk.no\erputv\Utvikling\Driftregnskap\VISMA',
    '\\DEDGE.fk.no\erputv\Utvikling\fraktavregning',
    '\\DEDGE.fk.no\erputv\Utvikling\INTERMEC',
    '\\DEDGE.fk.no\erputv\Utvikling\MayLiss',
    '\\DEDGE.fk.no\erputv\Utvikling\MayLiss\CPY',
    '\\DEDGE.fk.no\erputv\Utvikling\ROA',
    '\\DEDGE.fk.no\erputv\Utvikling\OPT\SQL',
    '\\DEDGE.fk.no\erputv\Utvikling\Storksource',
    '\\DEDGE.fk.no\erputv\Utvikling\tru\BUNTER',
    '\\DEDGE.fk.no\erputv\Utvikling\ebj',
    '\\DEDGE.fk.no\erputv\Utvikling\erik\Ny mappe',
    '\\DEDGE.fk.no\erputv\Utvikling\EZTPROG',
    '\\DEDGE.fk.no\erputv\Utvikling\fka\prod',
    '\\DEDGE.fk.no\erputv\Utvikling\fkavare\eksport',
    '\\DEDGE.fk.no\erputv\Utvikling\fkavd',
    '\\DEDGE.fk.no\erputv\Utvikling\fkavd\sql',
    '\\DEDGE.fk.no\erputv\Utvikling\maskloaderFINNg',
    '\\DEDGE.fk.no\erputv\Utvikling\mfkhist\mo25',
    '\\DEDGE.fk.no\erputv\Utvikling\nytt_kd_system'
)

# Dynamically load from folder inventory JSON if provided or discovered
if ([string]::IsNullOrEmpty($FolderInventoryJson)) {
    $appDataPath = Get-ApplicationDataPath
    $invCandidate = Get-ChildItem -Path $appDataPath -Filter 'CobolFolderInventory-*.json' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($invCandidate) { $FolderInventoryJson = $invCandidate.FullName }
}
if (-not [string]::IsNullOrEmpty($FolderInventoryJson) -and (Test-Path $FolderInventoryJson)) {
    $invData = Get-Content $FolderInventoryJson -Raw | ConvertFrom-Json
    foreach ($f in $invData.Folders) {
        if ($additionalSourcePaths -notcontains $f.Folder) {
            $additionalSourcePaths += $f.Folder
        }
    }
    Write-LogMessage "Loaded folder inventory: $($FolderInventoryJson) ($($invData.Folders.Count) folders)" -Level DEBUG
}

# Also include the Git repo source folders
$repoFolders = @(
    'C:\opt\data\AutoDocJson\tmp\DedgeRepository\Dedge\cbl',
    'C:\opt\data\AutoDocJson\tmp\DedgeRepository\Dedge\cpy',
    'C:\opt\data\AutoDocJson\tmp\DedgeRepository\Dedge\gs'
)
foreach ($rf in $repoFolders) {
    if ((Test-Path $rf) -and ($additionalSourcePaths -notcontains $rf)) {
        $additionalSourcePaths += $rf
    }
}

# --- COBOL content verification ---
function Test-CobolContent {
    param([string]$FilePath)

    $markers = @(
        'IDENTIFICATION DIVISION', 'ID DIVISION', 'PROGRAM-ID',
        'DATA DIVISION', 'PROCEDURE DIVISION', 'WORKING-STORAGE SECTION',
        'EXEC SQL', 'ENVIRONMENT DIVISION', 'FILE SECTION', 'LINKAGE SECTION'
    )

    $result = [PSCustomObject]@{
        IsCobol      = $false
        Confidence   = 'NONE'
        MarkerCount  = 0
        MarkersFound = @()
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
            if ($line.Length -ge 7 -and $line[6] -eq '*') { $col7Comments++ }
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

# ============================================================================
# COLLECT-ALL MODE: sweep all source paths into structured output folders
# ============================================================================
if ($CollectAll) {
    Write-LogMessage 'Running in COLLECT-ALL mode' -Level INFO

    $scriptBaseName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
    if ([string]::IsNullOrEmpty($DestinationFolder)) {
        $optPath = if ($env:OptPath) { $env:OptPath } else { 'C:\opt' }
        $DestinationFolder = Join-Path $optPath "data\VisualCobol\$($scriptBaseName)\Sources"
    }

    $cblFolder            = Join-Path $DestinationFolder 'cbl'
    $cblUncertainFolder   = Join-Path $DestinationFolder 'cbl_uncertain'
    $cpyFolder            = Join-Path $DestinationFolder 'cpy'
    $cpyUncertainFolder   = Join-Path $DestinationFolder 'cpy_uncertain'
    foreach ($d in @($DestinationFolder, $cblFolder, $cblUncertainFolder, $cpyFolder, $cpyUncertainFolder)) {
        New-Item -Path $d -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    }

    foreach ($d in @($cblFolder, $cblUncertainFolder, $cpyFolder, $cpyUncertainFolder)) {
        $existing = Get-ChildItem -Path $d -File -ErrorAction SilentlyContinue
        if ($existing.Count -gt 0) {
            Write-LogMessage "Cleaning $($existing.Count) files from $($d)" -Level INFO
            Remove-Item -Path (Join-Path $d '*') -Force -ErrorAction SilentlyContinue
        }
    }

    Write-LogMessage "Destination:       $($DestinationFolder)" -Level INFO
    Write-LogMessage "  cbl/             $($cblFolder)" -Level INFO
    Write-LogMessage "  cbl_uncertain/   $($cblUncertainFolder)" -Level INFO
    Write-LogMessage "  cpy/             $($cpyFolder)" -Level INFO
    Write-LogMessage "  cpy_uncertain/   $($cpyUncertainFolder)" -Level INFO
    Write-LogMessage "Source folders:    $($additionalSourcePaths.Count)" -Level INFO

    $knownCblExtensions = @('.CBL', '.COB')
    $knownCpyExtensions = @('.CPY', '.CPB', '.DCL', '.CPX', '.GS', '.IMP', '.MF', '.INT', '.IDY')
    $skipExtensions     = @('.BND')

    $intSourceFolder = '\\DEDGE.fk.no\erpprog\cobnt'
    $knownIntBasenames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    Write-LogMessage "Loading .int basenames from $($intSourceFolder)..." -Level INFO
    $intFiles = Get-ChildItem -Path $intSourceFolder -Filter '*.int' -File -ErrorAction SilentlyContinue
    foreach ($intFile in $intFiles) {
        [void]$knownIntBasenames.Add([System.IO.Path]::GetFileNameWithoutExtension($intFile.Name))
    }
    Write-LogMessage "  Loaded $($knownIntBasenames.Count) .int basenames" -Level INFO

    # Regex: filenames with date suffixes, backup markers, or spaces → uncertain (used for CPY only)
    # ^(BACKUP|KOPI|...)[-_]  prefix markers before the real program name (BACKUP_OIAAUTO)
    # [\s_-]\d{4,}            underscore/dash/space + 4+ digits (date suffixes like _170108)
    # [-_](OLD|NY|...)        suffix markers after the program name (_BCK, _NY, _ASK)
    #   (?=[-_\s]|$)          lookahead: suffix must end at separator or end-of-string
    #                         (can't use \b because _ is a word char, so NY_V1 wouldn't match)
    # \s                      any spaces in the name
    # \d{6,}                  6+ consecutive digits anywhere (date stamps)
    $uncertainNamePattern = '^(BACKUP|KOPI|COPY|OLD|BCK|BAK|GML|GAMMEL)[-_]|[\s_-]\d{4,}|[-_](OLD|GML|GAMMEL|BCK|BAK|KOPI|COPY|ASK|NY|VERSJON)(?=[-_\s]|$)|\s|\d{6,}'

    $stats = @{ cbl = 0; cbl_uncertain = 0; cpy = 0; cpy_uncertain = 0; skipped = 0 }
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $fileIndex = [System.Collections.Generic.List[hashtable]]::new()

    $seenCblNames = @{}
    $seenCpyNames = @{}

    $priorityFolders = @(
        '\\DEDGE.fk.no\erputv\Utvikling\fkavd\NT',
        '\\DEDGE.fk.no\erputv\Utvikling\fkavd\utgatt',
        '\\DEDGE.fk.no\erputv\Utvikling\CBLARKIV',
        '\\DEDGE.fk.no\erputv\Utvikling\fkavd\BACKUP-20160310'
    )

    foreach ($folder in $additionalSourcePaths) {
        if (-not (Test-Path $folder -ErrorAction SilentlyContinue)) { continue }

        try {
            $files = Get-ChildItem -Path $folder -File -ErrorAction SilentlyContinue
        } catch { continue }

        if (-not $files -or $files.Count -eq 0) { continue }

        $isPriorityFolder = $folder -in $priorityFolders
        Write-LogMessage "  Scanning: $($folder) ($($files.Count) files)$(if ($isPriorityFolder) { ' [PRIORITY]' })" -Level INFO

        foreach ($file in $files) {
            $ext = $file.Extension.ToUpper()

            if ($ext -in $skipExtensions) {
                $stats.skipped++
                continue
            }

            $fileBaseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            $lookupKey = $fileBaseName.ToUpper()
            $fileRecord = [ordered]@{
                BaseName          = $lookupKey
                OriginalName      = $file.Name
                SourcePath        = $file.FullName
                SourceFolder      = $folder
                Extension         = $ext
                Type              = $null
                IsPrioritySource  = $isPriorityFolder
                CreationTime      = $file.CreationTime.ToString('yyyy-MM-dd HH:mm:ss')
                LastWriteTime     = $file.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
                FileSize          = $file.Length
                Action            = $null
                Reason            = $null
                DestinationPath   = $null
                DestinationFolder = $null
                RenamedTo         = $null
                DisplacedBy       = $null
                MatchTag          = $null
                IntMatch          = $null
                PostValidation    = $null
            }

            # --- Known CBL or CPY extension: apply priority dedup ---
            if ($ext -in $knownCblExtensions -or $ext -in $knownCpyExtensions) {
                $isCblType       = $ext -in $knownCblExtensions
                $seenDict        = if ($isCblType) { $seenCblNames } else { $seenCpyNames }
                $certainFolder   = if ($isCblType) { $cblFolder } else { $cpyFolder }
                $uncFolder       = if ($isCblType) { $cblUncertainFolder } else { $cpyUncertainFolder }
                $statCertain     = if ($isCblType) { 'cbl' } else { 'cpy' }
                $statUncertain   = if ($isCblType) { 'cbl_uncertain' } else { 'cpy_uncertain' }
                $fileRecord.Type = if ($isCblType) { 'cbl' } else { 'cpy' }

                if ($isCblType) {
                    $hasIntMatch = $knownIntBasenames.Contains($lookupKey)
                    $isUncertainName = -not $hasIntMatch
                    $fileRecord.IntMatch = $hasIntMatch
                } else {
                    $isUncertainName = $fileBaseName -match $uncertainNamePattern
                }

                if ($isUncertainName) {
                    $destPath = Join-Path $uncFolder $file.Name
                    $renamedTo = $null
                    if (Test-Path $destPath) {
                        $existingSize = (Get-Item $destPath).Length
                        if ($existingSize -eq $file.Length) {
                            $fileRecord.Action = 'skipped'
                            $fileRecord.Reason = 'Duplicate: same size file already in uncertain folder'
                            $fileRecord.DestinationFolder = $statUncertain
                            $fileIndex.Add($fileRecord)
                            continue
                        }
                        $counter = 2
                        $bn = $fileBaseName
                        $fe = $file.Extension
                        do {
                            $destPath = Join-Path $uncFolder "$($bn)_$($counter)$($fe)"
                            $counter++
                        } while (Test-Path $destPath)
                        $renamedTo = [System.IO.Path]::GetFileName($destPath)
                    }
                    try {
                        Copy-Item -Path $file.FullName -Destination $destPath -Force -ErrorAction SilentlyContinue
                        $di = Get-Item -Path $destPath -ErrorAction SilentlyContinue
                        if ($di) { $di.CreationTime = $file.CreationTime; $di.LastWriteTime = $file.LastWriteTime }
                    } catch {
                        Write-LogMessage "  Copy failed: $($file.FullName): $($_.Exception.Message)" -Level WARN
                    }
                    $stats[$statUncertain]++
                    $fileRecord.Action = 'copied'
                    $fileRecord.Reason = if ($isCblType) { 'No matching .int basename in cobnt' } else { 'Uncertain name pattern match (CPY regex)' }
                    $fileRecord.DestinationPath = $destPath
                    $fileRecord.DestinationFolder = $statUncertain
                    $fileRecord.RenamedTo = $renamedTo
                    $fileIndex.Add($fileRecord)
                    continue
                }

                # Clean name → priority dedup logic
                if ($seenDict.ContainsKey($lookupKey)) {
                    $existing = $seenDict[$lookupKey]

                    if ($existing.IsPriority) {
                        # Case B: existing came from a priority folder → skip
                        $stats.skipped++
                        $fileRecord.Action = 'skipped'
                        $fileRecord.Reason = 'Case B: priority source already collected'
                        $fileRecord.DestinationFolder = 'skipped'
                        $fileIndex.Add($fileRecord)
                        continue
                    }

                    if ($isPriorityFolder) {
                        # Case C: priority displaces non-priority
                        $oldPath = $existing.Path
                        $matchNum = $existing.MatchCount + 1
                        $tagName = "$($lookupKey)_match$($matchNum - 1)$([System.IO.Path]::GetExtension($oldPath))"
                        $tagPath = Join-Path $uncFolder $tagName
                        $displacedRecord = [ordered]@{
                            BaseName = $lookupKey; OriginalName = [System.IO.Path]::GetFileName($oldPath)
                            SourcePath = $existing.OriginalSourcePath; SourceFolder = $existing.OriginalSourceFolder
                            Extension = [System.IO.Path]::GetExtension($oldPath).ToUpper()
                            Type = $fileRecord.Type; IsPrioritySource = $false
                            CreationTime = $existing.OriginalCreationTime; LastWriteTime = $existing.OriginalLastWriteTime
                            FileSize = $existing.OriginalFileSize
                            Action = 'displaced'; Reason = 'Case C: displaced by priority source'
                            DestinationPath = $tagPath; DestinationFolder = $statUncertain
                            RenamedTo = $null; DisplacedBy = $file.FullName
                            MatchTag = "_match$($matchNum - 1)"; PostValidation = $null
                        }
                        try {
                            $oldItem = Get-Item -Path $oldPath -ErrorAction SilentlyContinue
                            $oldCreate = $oldItem.CreationTime
                            $oldWrite  = $oldItem.LastWriteTime
                            Move-Item -Path $oldPath -Destination $tagPath -Force
                            $movedItem = Get-Item -Path $tagPath -ErrorAction SilentlyContinue
                            if ($movedItem) { $movedItem.CreationTime = $oldCreate; $movedItem.LastWriteTime = $oldWrite }
                        } catch {
                            Write-LogMessage "  Move failed: $($oldPath): $($_.Exception.Message)" -Level WARN
                        }
                        $stats[$statUncertain]++
                        $fileIndex.Add($displacedRecord)

                        $destPath = Join-Path $certainFolder $file.Name
                        try {
                            Copy-Item -Path $file.FullName -Destination $destPath -Force -ErrorAction SilentlyContinue
                            $di = Get-Item -Path $destPath -ErrorAction SilentlyContinue
                            if ($di) { $di.CreationTime = $file.CreationTime; $di.LastWriteTime = $file.LastWriteTime }
                        } catch {
                            Write-LogMessage "  Copy failed: $($file.FullName): $($_.Exception.Message)" -Level WARN
                        }
                        $seenDict[$lookupKey] = @{
                            Path = $destPath; LastWriteTime = $file.LastWriteTime; IsPriority = $true; MatchCount = $matchNum
                            OriginalSourcePath = $file.FullName; OriginalSourceFolder = $folder
                            OriginalCreationTime = $fileRecord.CreationTime; OriginalLastWriteTime = $fileRecord.LastWriteTime
                            OriginalFileSize = $file.Length
                        }
                        $fileRecord.Action = 'copied'
                        $fileRecord.Reason = 'Case C: priority source replaces non-priority'
                        $fileRecord.DestinationPath = $destPath
                        $fileRecord.DestinationFolder = $statCertain
                        $fileIndex.Add($fileRecord)
                        continue
                    }

                    # Case D/E: both >Pri4 — compare dates
                    $matchNum = $existing.MatchCount + 1

                    if ($file.LastWriteTime -gt $existing.LastWriteTime) {
                        # Case D: new is newer → displace old to uncertain, copy new to certain
                        $oldPath = $existing.Path
                        $tagName = "$($lookupKey)_match$($matchNum - 1)$([System.IO.Path]::GetExtension($oldPath))"
                        $tagPath = Join-Path $uncFolder $tagName
                        $displacedRecord = [ordered]@{
                            BaseName = $lookupKey; OriginalName = [System.IO.Path]::GetFileName($oldPath)
                            SourcePath = $existing.OriginalSourcePath; SourceFolder = $existing.OriginalSourceFolder
                            Extension = [System.IO.Path]::GetExtension($oldPath).ToUpper()
                            Type = $fileRecord.Type; IsPrioritySource = $false
                            CreationTime = $existing.OriginalCreationTime; LastWriteTime = $existing.OriginalLastWriteTime
                            FileSize = $existing.OriginalFileSize
                            Action = 'displaced'; Reason = 'Case D: displaced by newer file'
                            DestinationPath = $tagPath; DestinationFolder = $statUncertain
                            RenamedTo = $null; DisplacedBy = $file.FullName
                            MatchTag = "_match$($matchNum - 1)"; PostValidation = $null
                        }
                        try {
                            $oldItem = Get-Item -Path $oldPath -ErrorAction SilentlyContinue
                            $oldCreate = $oldItem.CreationTime
                            $oldWrite  = $oldItem.LastWriteTime
                            Move-Item -Path $oldPath -Destination $tagPath -Force
                            $movedItem = Get-Item -Path $tagPath -ErrorAction SilentlyContinue
                            if ($movedItem) { $movedItem.CreationTime = $oldCreate; $movedItem.LastWriteTime = $oldWrite }
                        } catch {
                            Write-LogMessage "  Move failed: $($oldPath): $($_.Exception.Message)" -Level WARN
                        }
                        $stats[$statUncertain]++
                        $fileIndex.Add($displacedRecord)

                        $destPath = Join-Path $certainFolder $file.Name
                        try {
                            Copy-Item -Path $file.FullName -Destination $destPath -Force -ErrorAction SilentlyContinue
                            $di = Get-Item -Path $destPath -ErrorAction SilentlyContinue
                            if ($di) { $di.CreationTime = $file.CreationTime; $di.LastWriteTime = $file.LastWriteTime }
                        } catch {
                            Write-LogMessage "  Copy failed: $($file.FullName): $($_.Exception.Message)" -Level WARN
                        }
                        $seenDict[$lookupKey] = @{
                            Path = $destPath; LastWriteTime = $file.LastWriteTime; IsPriority = $false; MatchCount = $matchNum
                            OriginalSourcePath = $file.FullName; OriginalSourceFolder = $folder
                            OriginalCreationTime = $fileRecord.CreationTime; OriginalLastWriteTime = $fileRecord.LastWriteTime
                            OriginalFileSize = $file.Length
                        }
                        $fileRecord.Action = 'copied'
                        $fileRecord.Reason = 'Case D: newer file replaces older'
                        $fileRecord.DestinationPath = $destPath
                        $fileRecord.DestinationFolder = $statCertain
                        $fileIndex.Add($fileRecord)
                    } else {
                        # Case E: new is older or same → put new in uncertain
                        $tagName = "$($lookupKey)_match$($matchNum)$($file.Extension)"
                        $tagPath = Join-Path $uncFolder $tagName
                        try {
                            Copy-Item -Path $file.FullName -Destination $tagPath -Force -ErrorAction SilentlyContinue
                            $di = Get-Item -Path $tagPath -ErrorAction SilentlyContinue
                            if ($di) { $di.CreationTime = $file.CreationTime; $di.LastWriteTime = $file.LastWriteTime }
                        } catch {
                            Write-LogMessage "  Copy failed: $($file.FullName): $($_.Exception.Message)" -Level WARN
                        }
                        $stats[$statUncertain]++
                        $seenDict[$lookupKey] = @{
                            Path = $existing.Path; LastWriteTime = $existing.LastWriteTime
                            IsPriority = $existing.IsPriority; MatchCount = $matchNum
                            OriginalSourcePath = $existing.OriginalSourcePath; OriginalSourceFolder = $existing.OriginalSourceFolder
                            OriginalCreationTime = $existing.OriginalCreationTime; OriginalLastWriteTime = $existing.OriginalLastWriteTime
                            OriginalFileSize = $existing.OriginalFileSize
                        }
                        $fileRecord.Action = 'copied'
                        $fileRecord.Reason = 'Case E: older/same-age copy sent to uncertain'
                        $fileRecord.DestinationPath = $tagPath
                        $fileRecord.DestinationFolder = $statUncertain
                        $fileRecord.MatchTag = "_match$($matchNum)"
                        $fileIndex.Add($fileRecord)
                    }
                    continue
                }

                # Case A: basename not seen yet → copy to certain folder
                $destPath = Join-Path $certainFolder $file.Name
                try {
                    Copy-Item -Path $file.FullName -Destination $destPath -Force -ErrorAction SilentlyContinue
                    $di = Get-Item -Path $destPath -ErrorAction SilentlyContinue
                    if ($di) { $di.CreationTime = $file.CreationTime; $di.LastWriteTime = $file.LastWriteTime }
                } catch {
                    Write-LogMessage "  Copy failed: $($file.FullName): $($_.Exception.Message)" -Level WARN
                }
                $seenDict[$lookupKey] = @{
                    Path = $destPath; LastWriteTime = $file.LastWriteTime; IsPriority = $isPriorityFolder; MatchCount = 1
                    OriginalSourcePath = $file.FullName; OriginalSourceFolder = $folder
                    OriginalCreationTime = $fileRecord.CreationTime; OriginalLastWriteTime = $fileRecord.LastWriteTime
                    OriginalFileSize = $file.Length
                }
                $stats[$statCertain]++
                $fileRecord.Action = 'copied'
                $fileRecord.Reason = "Case A: first clean match$(if ($isPriorityFolder) { ' (priority)' })"
                $fileRecord.DestinationPath = $destPath
                $fileRecord.DestinationFolder = $statCertain
                $fileIndex.Add($fileRecord)
                continue
            }

            # --- Unknown extension: content-check → always uncertain, no dedup ---
            $check = Test-CobolContent -FilePath $file.FullName
            if ($check.Confidence -in @('HIGH', 'MEDIUM')) {
                $hasProgStructure = ($check.MarkersFound |
                    Where-Object { $_ -in @('PROGRAM-ID', 'IDENTIFICATION DIVISION', 'ID DIVISION') }).Count -gt 0
                if ($hasProgStructure) {
                    $targetFolder = $cblUncertainFolder
                    $fileRecord.Type = 'cbl'
                    $fileRecord.DestinationFolder = 'cbl_uncertain'
                    $stats.cbl_uncertain++
                } else {
                    $targetFolder = $cpyUncertainFolder
                    $fileRecord.Type = 'cpy'
                    $fileRecord.DestinationFolder = 'cpy_uncertain'
                    $stats.cpy_uncertain++
                }
            } elseif ($check.Confidence -eq 'LOW') {
                $targetFolder = $cpyUncertainFolder
                $fileRecord.Type = 'cpy'
                $fileRecord.DestinationFolder = 'cpy_uncertain'
                $stats.cpy_uncertain++
            } else {
                $stats.skipped++
                $fileRecord.Action = 'skipped'
                $fileRecord.Reason = "Content check: no COBOL markers (confidence=$($check.Confidence))"
                $fileRecord.DestinationFolder = 'skipped'
                $fileIndex.Add($fileRecord)
                continue
            }

            $destPath = Join-Path $targetFolder $file.Name
            $renamedTo = $null
            if (Test-Path $destPath) {
                $existingSize = (Get-Item $destPath).Length
                if ($existingSize -eq $file.Length) {
                    $fileRecord.Action = 'skipped'
                    $fileRecord.Reason = 'Duplicate: same size file already exists'
                    $fileIndex.Add($fileRecord)
                    continue
                }
                $counter = 2
                $baseName = $fileBaseName
                $fileExt = $file.Extension
                do {
                    $destPath = Join-Path $targetFolder "$($baseName)_$($counter)$($fileExt)"
                    $counter++
                } while (Test-Path $destPath)
                $renamedTo = [System.IO.Path]::GetFileName($destPath)
            }

            try {
                Copy-Item -Path $file.FullName -Destination $destPath -Force -ErrorAction SilentlyContinue
                $di = Get-Item -Path $destPath -ErrorAction SilentlyContinue
                if ($di) { $di.CreationTime = $file.CreationTime; $di.LastWriteTime = $file.LastWriteTime }
            } catch {
                Write-LogMessage "  Copy failed: $($file.FullName): $($_.Exception.Message)" -Level WARN
            }
            $fileRecord.Action = 'copied'
            $fileRecord.Reason = "Content check: $($check.Confidence) confidence"
            $fileRecord.DestinationPath = $destPath
            $fileRecord.RenamedTo = $renamedTo
            $fileIndex.Add($fileRecord)
        }
    }

    # ====================================================================
    # POST-COLLECTION: validate cpy/ basenames against COPY references
    # Parse all CBL files for COPY statements, move unreferenced cpy files
    # ====================================================================
    Write-LogMessage '=== POST-COLLECTION: validating cpy basenames against CBL COPY statements ===' -Level INFO

    $referencedCopyNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $cblFiles = Get-ChildItem -Path $cblFolder -File -ErrorAction SilentlyContinue
    # Regex: COBOL COPY statement — COPY <element-name> with optional OF/IN library
    #   ^\s{0,6}\d{0,6}\s*  optional sequence number area (cols 1-6) then spaces
    #   COPY\s+              the COPY verb
    #   ([A-Za-z0-9_-]+)     capture group 1: the copy element basename
    $copyPattern = '(?i)(?:^|\s)COPY\s+([A-Za-z0-9_-]+)'

    foreach ($cblFile in $cblFiles) {
        try {
            $content = Get-Content -Path $cblFile.FullName -Raw -ErrorAction SilentlyContinue
            if ($content) {
                $copyMatches = [regex]::Matches($content, $copyPattern)
                foreach ($m in $copyMatches) {
                    [void]$referencedCopyNames.Add($m.Groups[1].Value.ToUpper())
                }
            }
        } catch { }
    }

    Write-LogMessage "  Parsed $($cblFiles.Count) CBL files, found $($referencedCopyNames.Count) unique COPY references" -Level INFO

    $cpyFiles = Get-ChildItem -Path $cpyFolder -File -ErrorAction SilentlyContinue
    $movedCount = 0

    $cpyIndexLookup = @{}
    for ($i = 0; $i -lt $fileIndex.Count; $i++) {
        $rec = $fileIndex[$i]
        if ($rec.DestinationFolder -eq 'cpy' -and $rec.Action -eq 'copied' -and $rec.DestinationPath) {
            $cpyIndexLookup[$rec.DestinationPath] = $i
        }
    }

    foreach ($cpyFile in $cpyFiles) {
        $cpyBaseName = [System.IO.Path]::GetFileNameWithoutExtension($cpyFile.Name).ToUpper()
        if (-not $referencedCopyNames.Contains($cpyBaseName)) {
            $destPath = Join-Path $cpyUncertainFolder $cpyFile.Name
            $renamedTo = $null
            if (Test-Path $destPath) {
                $counter = 2
                $bn = [System.IO.Path]::GetFileNameWithoutExtension($cpyFile.Name)
                $fe = $cpyFile.Extension
                do {
                    $destPath = Join-Path $cpyUncertainFolder "$($bn)_$($counter)$($fe)"
                    $counter++
                } while (Test-Path $destPath)
                $renamedTo = [System.IO.Path]::GetFileName($destPath)
            }
            try {
                $origCreate = $cpyFile.CreationTime
                $origWrite  = $cpyFile.LastWriteTime
                $oldFullPath = $cpyFile.FullName
                Move-Item -Path $cpyFile.FullName -Destination $destPath -Force
                $movedItem = Get-Item -Path $destPath -ErrorAction SilentlyContinue
                if ($movedItem) { $movedItem.CreationTime = $origCreate; $movedItem.LastWriteTime = $origWrite }
                $movedCount++
                $stats.cpy--
                $stats.cpy_uncertain++

                if ($cpyIndexLookup.ContainsKey($oldFullPath)) {
                    $idx = $cpyIndexLookup[$oldFullPath]
                    $fileIndex[$idx].Action = 'moved_post_validation'
                    $fileIndex[$idx].DestinationPath = $destPath
                    $fileIndex[$idx].DestinationFolder = 'cpy_uncertain'
                    $fileIndex[$idx].PostValidation = 'Not referenced by any CBL COPY statement'
                    if ($renamedTo) { $fileIndex[$idx].RenamedTo = $renamedTo }
                }
            } catch {
                Write-LogMessage "  Move failed: $($cpyFile.Name): $($_.Exception.Message)" -Level WARN
            }
        }
    }

    Write-LogMessage "  Moved $($movedCount) unreferenced cpy files to cpy_uncertain" -Level INFO

    $totalCollected = $stats.cbl + $stats.cbl_uncertain + $stats.cpy + $stats.cpy_uncertain
    Write-LogMessage '=== COLLECTION SUMMARY ===' -Level INFO
    Write-LogMessage "Total collected: $($totalCollected)  (skipped: $($stats.skipped))" -Level INFO
    Write-LogMessage "  cbl:             $($stats.cbl)" -Level INFO
    Write-LogMessage "  cbl_uncertain:   $($stats.cbl_uncertain)" -Level INFO
    Write-LogMessage "  cpy:             $($stats.cpy)" -Level INFO
    Write-LogMessage "  cpy_uncertain:   $($stats.cpy_uncertain)" -Level INFO
    Write-LogMessage "Destination: $($DestinationFolder)" -Level INFO

    $parentFolder = Split-Path $DestinationFolder -Parent
    $indexPath = Join-Path $parentFolder "FileIndex-$($timestamp).json"
    Write-LogMessage "Writing file index ($($fileIndex.Count) records)..." -Level INFO
    $fileIndex | ConvertTo-Json -Depth 4 | Out-File -FilePath $indexPath -Encoding utf8 -Force
    Write-LogMessage "FileIndex JSON: $($indexPath)" -Level INFO

    $tsvPath = $indexPath -replace '\.json$', '.tsv'
    $tsvHeader = "BaseName`tAction`tSourceFolder`tDestinationFolder`tReason`tOriginalName`tRenamedTo`tMatchTag`tIntMatch`tPostValidation"
    $tsvLines = [System.Collections.Generic.List[string]]::new()
    $tsvLines.Add($tsvHeader)
    foreach ($rec in $fileIndex) {
        $tsvLines.Add("$($rec.BaseName)`t$($rec.Action)`t$($rec.SourceFolder)`t$($rec.DestinationFolder)`t$($rec.Reason)`t$($rec.OriginalName)`t$($rec.RenamedTo)`t$($rec.MatchTag)`t$($rec.IntMatch)`t$($rec.PostValidation)")
    }
    $tsvLines | Out-File -FilePath $tsvPath -Encoding utf8 -Force
    Write-LogMessage "FileIndex TSV:  $($tsvPath)" -Level INFO

    $reportPath = Join-Path $parentFolder "CollectAll-$($timestamp).json"
    [ordered]@{
        GeneratedAt         = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Script              = $scriptBaseName
        DestinationFolder   = $DestinationFolder
        IntSourceFolder     = $intSourceFolder
        IntBasenamesCount   = $knownIntBasenames.Count
        SearchFoldersCount  = $additionalSourcePaths.Count
        TotalCollected      = $totalCollected
        Skipped             = $stats.skipped
        Stats               = $stats
        FileIndexPath       = $indexPath
        FileIndexCount      = $fileIndex.Count
        PostValidationMoved = $movedCount
    } | ConvertTo-Json -Depth 3 | Out-File -FilePath $reportPath -Encoding utf8 -Force
    Write-LogMessage "Report: $($reportPath)" -Level INFO

    if ($SendNotification) {
        Send-Sms -Receiver $smsNumber -Message "CollectAll: $($totalCollected) files (cbl:$($stats.cbl) cpy:$($stats.cpy) uncertain:$($stats.cbl_uncertain + $stats.cpy_uncertain)). $($additionalSourcePaths.Count) folders scanned."
    }

    exit 0
}

# ============================================================================
# FIND-MISSING MODE: search additional paths for specific missing programs
# ============================================================================
if ($FindMissing) {
    Write-LogMessage 'Running in FIND-MISSING mode' -Level INFO

    if ($MissingPrograms.Count -eq 0) {
        $migReport = Get-ChildItem -Path (Get-ApplicationDataPath) -Filter 'MigrationStatusReport-*.json' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($migReport) {
            $data = Get-Content $migReport.FullName -Raw | ConvertFrom-Json
            $MissingPrograms = @($data.Programs | Where-Object { $_.Status -eq 'NO_SOURCE' } | ForEach-Object { $_.Program })
            Write-LogMessage "Loaded $($MissingPrograms.Count) missing programs from $($migReport.Name)" -Level INFO
        }
    }

    if ($MissingPrograms.Count -eq 0) {
        Write-LogMessage 'No missing programs specified or found in reports' -Level WARN
        exit 0
    }

    if ($SendNotification) {
        Send-Sms -Receiver $smsNumber -Message "FindMissing: searching $($MissingPrograms.Count) programs in $($additionalSourcePaths.Count) folders"
    }

    $targetCbl = Join-Path $VcPath 'src\cbl'
    if (-not (Test-Path $targetCbl)) {
        New-Item -ItemType Directory -Path $targetCbl -Force | Out-Null
    }

    $found = 0
    $notFound = 0

    foreach ($prog in $MissingPrograms) {
        $progBase = ($prog -replace '\s.*$', '').Trim().ToUpper()
        $matchFound = $false

        foreach ($folder in $additionalSourcePaths) {
            if (-not (Test-Path $folder -ErrorAction SilentlyContinue)) { continue }

            $cblFile = Get-ChildItem -Path $folder -Filter "$($progBase).cbl" -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($cblFile) {
                Copy-Item -Path $cblFile.FullName -Destination (Join-Path $targetCbl "$($progBase).CBL") -Force
                Write-LogMessage "FOUND $($prog) -> $($cblFile.FullName)" -Level INFO
                $found++
                $matchFound = $true
                break
            }
        }

        if (-not $matchFound) {
            $notFound++
            Write-LogMessage "NOT FOUND: $($prog)" -Level WARN
        }
    }

    Write-LogMessage "Find-Missing complete: $($found) found, $($notFound) not found" -Level INFO

    if ($SendNotification) {
        Send-Sms -Receiver $smsNumber -Message "FindMissing done: $($found)/$($MissingPrograms.Count) found, $($notFound) missing"
    }

    exit 0
}

# ============================================================================
# STANDARD COPY MODE: copy from repository structure to VCPATH
# ============================================================================
if ([string]::IsNullOrEmpty($SourceRepoFolder) -or -not (Test-Path $SourceRepoFolder)) {
    Write-LogMessage "Source repository folder not found: $($SourceRepoFolder)" -Level ERROR
    exit 1
}

if ($SendNotification) {
    Send-Sms -Receiver $smsNumber -Message "Move Code starting -> $($VcPath)"
}

Write-LogMessage "Moving source files from $($SourceRepoFolder) to $($VcPath)" -Level INFO

# --- Ensure target directories exist ---
$targetDirs = @(
    "$($VcPath)\src"
    "$($VcPath)\src\cbl"
    "$($VcPath)\src\cbl\cpy"
    "$($VcPath)\src\cbl\cpy\sys"
    "$($VcPath)\src\cbl\cpy\sys\cpy"
    "$($VcPath)\src\cbl\imp"
    "$($VcPath)\src\rex"
    "$($VcPath)\src\bat"
)

foreach ($dir in $targetDirs) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# --- Clean target folders if requested ---
if ($CleanTargetFirst) {
    Write-LogMessage "Cleaning target folders..." -Level INFO
    foreach ($dir in $targetDirs) {
        Get-ChildItem -Path $dir -File -ErrorAction SilentlyContinue | Remove-Item -Force
    }
}

# --- Copy file mappings: source subfolder -> target subfolder + extensions ---
$copyMappings = @(
    @{ Src = 'cbl';       Dest = "$($VcPath)\src\cbl";              Exts = @('*.cbl') }
    @{ Src = 'cpy';       Dest = "$($VcPath)\src\cbl\cpy";          Exts = @('*.cpy', '*.cpx', '*.cpb', '*.dcl') }
    @{ Src = 'sys\cpy';   Dest = "$($VcPath)\src\cbl\cpy\sys\cpy";  Exts = @('*.cpy', '*.cpx', '*.cpb', '*.dcl') }
    @{ Src = 'imp';       Dest = "$($VcPath)\src\cbl\imp";           Exts = @('*.*') }
    @{ Src = 'rexx';      Dest = "$($VcPath)\src\rex";               Exts = @('*.*') }
    @{ Src = 'rexx_prod'; Dest = "$($VcPath)\src\rex";               Exts = @('*.*') }
    @{ Src = 'bat';       Dest = "$($VcPath)\src\bat";               Exts = @('*.*') }
    @{ Src = 'bat_prod';  Dest = "$($VcPath)\src\bat";               Exts = @('*.*') }
)

$totalCopied = 0

foreach ($mapping in $copyMappings) {
    $srcDir = Join-Path $SourceRepoFolder $mapping.Src
    if (-not (Test-Path $srcDir)) {
        Write-LogMessage "Source subfolder not found (skipping): $($srcDir)" -Level DEBUG
        continue
    }

    foreach ($ext in $mapping.Exts) {
        $files = Get-ChildItem -Path $srcDir -Filter $ext -File -ErrorAction SilentlyContinue
        if ($files) {
            $files | Copy-Item -Destination $mapping.Dest -Force
            $totalCopied += $files.Count
        }
    }
    Write-LogMessage "Copied from $($mapping.Src) -> $($mapping.Dest)" -Level DEBUG
}

# --- Report results ---
$cblCount = (Get-ChildItem -Path "$($VcPath)\src\cbl" -Filter '*.cbl' -File -ErrorAction SilentlyContinue).Count
$cpyCount = (Get-ChildItem -Path "$($VcPath)\src\cbl\cpy" -File -ErrorAction SilentlyContinue).Count
$rexCount = (Get-ChildItem -Path "$($VcPath)\src\rex" -File -ErrorAction SilentlyContinue).Count
$batCount = (Get-ChildItem -Path "$($VcPath)\src\bat" -File -ErrorAction SilentlyContinue).Count

Write-LogMessage "Move complete: $($totalCopied) files copied. CBL=$($cblCount), CPY=$($cpyCount), REX=$($rexCount), BAT=$($batCount)" -Level INFO

if ($SendNotification) {
    Send-Sms -Receiver $smsNumber -Message "Move Code done. $($totalCopied) files to $($VcPath)"
}
