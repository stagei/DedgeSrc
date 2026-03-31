#Requires -Version 7.0
<#
.SYNOPSIS
    Discovers all folders containing COBOL source files under a network root.
.DESCRIPTION
    Enumerates folders under the specified root path (default: \\DEDGE.fk.no\erputv\Utvikling)
    and checks each for .CBL, .CPY, or .CPB files. Skips already-known search folders.
    Outputs a JSON inventory of all discovered COBOL source folders with file counts
    and newest file dates.

    Scans top-level folders + one level of subfolders (depth 2 max) to avoid
    descending into massive trees. Does NOT copy files — inventory only.
.PARAMETER RootPath
    Network root to scan.
.PARAMETER KnownFolders
    Folders already searched by other scripts — will be skipped.
.PARAMETER OutputFolder
    Where to write the inventory JSON. Defaults to Get-ApplicationDataPath.
.EXAMPLE
    .\Search-VcCobolFolders.ps1
.EXAMPLE
    .\Search-VcCobolFolders.ps1 -RootPath '\\DEDGE.fk.no\erputv\Utvikling' -SendNotification
#>
[CmdletBinding()]
param(
    [string]$RootPath = '\\DEDGE.fk.no\erputv\Utvikling',

    [string[]]$KnownFolders = @(
        '\\DEDGE.fk.no\erputv\Utvikling\fkavd\NT',
        '\\DEDGE.fk.no\erputv\Utvikling\fkavd\utgatt',
        '\\DEDGE.fk.no\erputv\Utvikling\CBLARKIV'
    ),

    [string]$OutputFolder = '',

    [switch]$SendNotification
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

if ([string]::IsNullOrEmpty($OutputFolder)) {
    $OutputFolder = Get-ApplicationDataPath
}
New-Item -Path $OutputFolder -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$cobolExtensions = @('*.cbl', '*.cpy', '*.cpb')

Write-LogMessage "COBOL folder scan starting on $($RootPath)" -Level INFO

if (-not (Test-Path $RootPath)) {
    Write-LogMessage "Root path not accessible: $($RootPath)" -Level ERROR
    exit 1
}

$knownNormalized = $KnownFolders | ForEach-Object { $_.TrimEnd('\').ToUpper() }

$topFolders = Get-ChildItem -Path $RootPath -Directory -ErrorAction SilentlyContinue
Write-LogMessage "Found $($topFolders.Count) top-level folders to scan" -Level INFO

$results = [System.Collections.Generic.List[PSCustomObject]]::new()
$scanned = 0
$withHits = 0

foreach ($topDir in $topFolders) {
    $scanned++

    $foldersToCheck = @($topDir)
    try {
        $subDirs = Get-ChildItem -Path $topDir.FullName -Directory -ErrorAction SilentlyContinue
        if ($subDirs) { $foldersToCheck += $subDirs }
    } catch {
        Write-LogMessage "  Cannot enumerate subfolders of $($topDir.Name): $($_.Exception.Message)" -Level WARN
    }

    foreach ($dir in $foldersToCheck) {
        if ($knownNormalized -contains $dir.FullName.TrimEnd('\').ToUpper()) {
            continue
        }

        try {
            $cblCount = @(Get-ChildItem -Path $dir.FullName -Filter '*.cbl' -File -ErrorAction SilentlyContinue).Count
            $cpyCount = @(Get-ChildItem -Path $dir.FullName -Filter '*.cpy' -File -ErrorAction SilentlyContinue).Count
            $cpbCount = @(Get-ChildItem -Path $dir.FullName -Filter '*.cpb' -File -ErrorAction SilentlyContinue).Count
        } catch {
            continue
        }

        $totalFiles = $cblCount + $cpyCount + $cpbCount
        if ($totalFiles -eq 0) { continue }

        $newestFile = $null
        try {
            $newestFile = Get-ChildItem -Path $dir.FullName -Include $cobolExtensions -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
        } catch { }

        $entry = [PSCustomObject]@{
            Folder      = $dir.FullName
            ParentDir   = $topDir.Name
            CblCount    = $cblCount
            CpyCount    = $cpyCount
            CpbCount    = $cpbCount
            TotalFiles  = $totalFiles
            NewestFile  = if ($newestFile) { $newestFile.Name } else { '' }
            NewestDate  = if ($newestFile) { $newestFile.LastWriteTime.ToString('yyyy-MM-dd HH:mm') } else { '' }
        }
        $results.Add($entry)
        $withHits++

        Write-LogMessage "  HIT: $($dir.FullName) — CBL=$($cblCount) CPY=$($cpyCount) CPB=$($cpbCount)" -Level INFO
    }

    if ($scanned % 25 -eq 0) {
        Write-LogMessage "Progress: $($scanned)/$($topFolders.Count) top folders, $($withHits) with COBOL files" -Level INFO
    }
}

Write-LogMessage "Scan complete: $($scanned) top folders scanned, $($results.Count) folders with COBOL files" -Level INFO

$jsonData = [ordered]@{
    GeneratedAt    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Script         = 'Search-VcCobolFolders.ps1'
    RootPath       = $RootPath
    KnownFolders   = $KnownFolders
    TopFoldersScanned = $scanned
    FoldersWithCobol  = $results.Count
    Folders        = @($results | ForEach-Object {
        [ordered]@{
            Folder     = $_.Folder
            ParentDir  = $_.ParentDir
            CblCount   = $_.CblCount
            CpyCount   = $_.CpyCount
            CpbCount   = $_.CpbCount
            TotalFiles = $_.TotalFiles
            NewestFile = $_.NewestFile
            NewestDate = $_.NewestDate
        }
    })
}

$jsonPath = Join-Path $OutputFolder "CobolFolderInventory-$($timestamp).json"
$jsonData | ConvertTo-Json -Depth 4 | Out-File -FilePath $jsonPath -Encoding utf8 -Force
Write-LogMessage "JSON inventory: $($jsonPath)" -Level INFO

foreach ($r in ($results | Sort-Object -Property TotalFiles -Descending)) {
    Write-LogMessage "  $($r.Folder): $($r.TotalFiles) files (newest: $($r.NewestDate))" -Level INFO
}

if ($SendNotification) {
    $smsNumber = switch ($env:USERNAME) {
        'FKGEISTA' { '+4797188358' }
        'FKSVEERI' { '+4795762742' }
        'FKMISTA'  { '+4799348397' }
        'FKCELERI' { '+4745269945' }
        default    { '+4797188358' }
    }
    Send-Sms -Receiver $smsNumber -Message "CobolFolderScan: $($results.Count) folders with COBOL in $($scanned) scanned"
}
