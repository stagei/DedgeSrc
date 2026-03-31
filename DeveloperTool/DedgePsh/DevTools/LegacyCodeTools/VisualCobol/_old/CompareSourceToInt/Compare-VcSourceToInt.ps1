#Requires -Version 7.0
<#
.SYNOPSIS
    Audits production .INT files against COBOL source availability.
.DESCRIPTION
    For every .INT file deployed to production, determines whether a matching .CBL
    source file exists and whether the compiled module is still in active use.
    Generates CSV reports and SQL INSERT statements for DB2 tracking.

    Replaces: OldScripts\VisualCobolCompareSrcToInt\VisualCobolCompareSrcToInt.ps1
    Changes from old version:
    - Uses GlobalFunctions Write-LogMessage
    - Parameterized paths instead of hardcoded UNC paths
    - Replaced year-by-year filter list (2001-2024) with regex pattern
    - Cleaned up commented-out DB2 connection code
    - Proper error handling with try/catch
    - Reports summary statistics

    Note: Production paths default to UNC paths at DEDGE.fk.no. Files are copied
    locally before processing per the remote-log-reading rule.
.EXAMPLE
    .\Compare-VcSourceToInt.ps1
    .\Compare-VcSourceToInt.ps1 -IntPath '\\DEDGE.fk.no\erpprog\COBNT' -QuickMode
#>
[CmdletBinding()]
param(
    [string]$IntPath = '\\DEDGE.fk.no\erpprog\COBNT',
    [string]$SrcPath = '\\DEDGE.fk.no\erputv\Utvikling\fkavd\NT',
    [string]$SrcUtgattPath = '\\DEDGE.fk.no\erputv\Utvikling\fkavd\utgatt',
    [string]$ArchivePath = '\\DEDGE.fk.no\erputv\Utvikling\CBLARKIV',
    [string]$ProdAppPath = '\\p-no1fkmprd-app.DEDGE.fk.no\opt\DedgePshApps',
    [string]$LocalWorkFolder = $(if ($env:OptPath) { "$($env:OptPath)\work\VisualCobolCompareSrcToInt" } else { 'C:\opt\work\VisualCobolCompareSrcToInt' }),
    [string]$DbName = 'BASISPRO',
    [switch]$QuickMode,
    [switch]$SkipSourceCollection
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

$localSrcFolder = Join-Path $LocalWorkFolder 'src'
$localTmpFolder = Join-Path $LocalWorkFolder 'tmp'
$prodSrcFolder = Join-Path $LocalWorkFolder 'prd'
$discardedFolder = Join-Path $localSrcFolder 'DISCARDED'
$outputFolder = Split-Path -Parent $MyInvocation.MyCommand.Definition

foreach ($dir in @($localSrcFolder, $localTmpFolder, $prodSrcFolder, $discardedFolder)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

Write-LogMessage "Starting source-to-INT comparison audit" -Level INFO

# --- Collect INT file inventory ---
$intFiles = Get-ChildItem -Path $IntPath -Filter '*.int' -ErrorAction Stop
$intArray = $intFiles | ForEach-Object { $_.BaseName.ToUpper() }
Write-LogMessage "Found $($intFiles.Count) .INT files in production" -Level INFO

# --- Collect production file list ---
$prodArray = @()
$prodFiles = @()
foreach ($ext in @('*.bat', '*.cmd', '*.rex', '*.int')) {
    $prodFiles += Get-ChildItem -Path $IntPath -Filter $ext -ErrorAction SilentlyContinue
}
foreach ($file in $prodFiles) {
    $prodArray += if ($file.Extension.ToUpper() -eq '.INT') { "$($file.BaseName.ToUpper()).CBL" } else { $file.Name.ToUpper() }
}

# --- Collect source files (unless skipped) ---
if (-not $SkipSourceCollection -and -not $QuickMode) {
    Write-LogMessage "Collecting source files from network locations..." -Level INFO
    Collect-SourceFiles -LocalSrcFolder $localSrcFolder -LocalTmpFolder $localTmpFolder `
        -IntFiles $intFiles -ProdArray $prodArray -ProdSrcFolder $prodSrcFolder `
        -SrcPath $SrcPath -SrcUtgattPath $SrcUtgattPath -ArchivePath $ArchivePath `
        -ProdAppPath $ProdAppPath -DiscardedFolder $discardedFolder
}

# --- Build source inventory ---
$srcArray = Get-ChildItem -Path $prodSrcFolder -Filter '*.cbl' -ErrorAction SilentlyContinue |
    ForEach-Object { $_.BaseName.ToUpper() }

# --- Compare INT vs source ---
Write-LogMessage "Comparing $($intArray.Count) INT files against source..." -Level INFO
$allResults = [System.Collections.Generic.List[PSCustomObject]]::new()
$missingResults = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($intFile in $intArray) {
    try {
        $usedByList = ''
        $programInUse = 'N'

        if ($srcArray -notcontains $intFile) {
            if (-not $QuickMode) {
                $usedBy = Find-FileUsage -FileName "$($intFile).CBL" -SearchFolder $prodSrcFolder -UsedByList @()
                if ($usedBy.Count -gt 0) {
                    $usedByList = $usedBy -join ','
                    $programInUse = 'Y'
                }
            }
        } else {
            $usedByList = 'Not checked (source exists)'
            $programInUse = 'Y'
        }

        $existsSrc = if ($srcArray -contains $intFile) { 'Y' } else { 'N' }
        $existsDiscarded = 'N/A'
        $comment = ''

        if ($existsSrc -eq 'N') {
            $discardedCount = (Get-ChildItem -Path $discardedFolder -Filter "$($intFile)*.*" -ErrorAction SilentlyContinue).Count
            if ($discardedCount -gt 0) {
                $existsDiscarded = 'Y'
                $comment = 'Version(s) exist in DISCARDED folder'
            } else {
                $existsDiscarded = 'N'
            }
        }

        $entry = [PSCustomObject]@{
            PackageSchemaName       = 'DBM'
            PackageName             = $intFile
            IntFile                 = "$($intFile).INT"
            SrcFile                 = "$($prodSrcFolder)\$($intFile).CBL"
            ExistSrcFile            = $existsSrc
            ExistSrcFileDiscarded   = $existsDiscarded
            ProgramInUse            = $programInUse
            Comment                 = $comment
            User                    = ''
            UsedBy                  = $usedByList
        }

        $allResults.Add($entry)
        if ($existsSrc -eq 'N') { $missingResults.Add($entry) }
    } catch {
        Write-LogMessage "Error processing $($intFile): $($_.Exception.Message)" -Level WARN
    }
}

# --- Generate reports ---
$missingCsvPath = Join-Path $outputFolder 'MissingSourceReport.csv'
$allCsvPath = Join-Path $outputFolder 'AllSourceReport.csv'
$sqlPath = Join-Path $outputFolder 'InsertSourceReport.sql'

$missingResults | Export-Csv -Path $missingCsvPath -NoTypeInformation -Delimiter ';' -Encoding UTF8
$allResults | Export-Csv -Path $allCsvPath -NoTypeInformation -Delimiter ';' -Encoding UTF8

# --- Generate SQL INSERT statements ---
$sqlContent = [System.Text.StringBuilder]::new()
foreach ($obj in $allResults) {
    [void]$sqlContent.AppendLine(@"
INSERT INTO DBM.DB_STAT_SOURCE_REPORT (
    PACKAGE_SCHEMA_NAME, PACKAGE_NAME, INT_FILE, SRC_FILE,
    EXIST_SRC_FILE, EXIST_SRC_FILE_IN_DISCARDED_FOLDER,
    PROGRAM_IN_USE, COMMENT, USER, USED_BY
) VALUES (
    '$($obj.PackageSchemaName)', '$($obj.PackageName)', '$($obj.IntFile)',
    '$($obj.SrcFile)', '$($obj.ExistSrcFile)', '$($obj.ExistSrcFileDiscarded)',
    '$($obj.ProgramInUse)', '$($obj.Comment)', '$($obj.User)', '$($obj.UsedBy)'
);
"@)
}
Set-Content -Path $sqlPath -Value $sqlContent.ToString() -Encoding UTF8

$srcExist = ($allResults | Where-Object { $_.ExistSrcFile -eq 'Y' }).Count
$srcMissing = ($allResults | Where-Object { $_.ExistSrcFile -eq 'N' }).Count
Write-LogMessage "Audit complete: $($allResults.Count) total, $($srcExist) with source, $($srcMissing) missing source" -Level INFO
Write-LogMessage "Reports: $($missingCsvPath), $($allCsvPath), $($sqlPath)" -Level INFO

# --- Helper functions ---

function Collect-SourceFiles {
    param(
        [string]$LocalSrcFolder, [string]$LocalTmpFolder, $IntFiles,
        [string[]]$ProdArray, [string]$ProdSrcFolder,
        [string]$SrcPath, [string]$SrcUtgattPath, [string]$ArchivePath,
        [string]$ProdAppPath, [string]$DiscardedFolder
    )

    Copy-Item -Path "$($SrcPath)\*.cbl" -Destination $LocalSrcFolder -Force -ErrorAction SilentlyContinue
    Copy-Item -Path "$($SrcUtgattPath)\*.cbl" -Destination $LocalSrcFolder -Force -ErrorAction SilentlyContinue

    foreach ($intFile in $IntFiles) {
        $archDir = Join-Path $ArchivePath $intFile.BaseName.ToUpper()
        if (Test-Path $archDir) {
            $extractDir = Join-Path $LocalTmpFolder $intFile.BaseName.ToUpper()
            if (-not (Test-Path $extractDir)) {
                $latestZip = Get-ChildItem -Path $archDir -Filter '*.zip' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($latestZip) {
                    New-Item -Path $extractDir -ItemType Directory -Force | Out-Null
                    Expand-Archive -Path $latestZip.FullName -DestinationPath $extractDir -Force
                    Get-ChildItem -Path $extractDir -Filter '*.cbl' | Copy-Item -Destination $LocalSrcFolder -Force
                }
            }
        }
    }

    # Collect _del files as candidates
    foreach ($srcDir in @($SrcPath, $SrcUtgattPath)) {
        Get-ChildItem -Path $srcDir -Filter '*.cbl_del' -ErrorAction SilentlyContinue | ForEach-Object {
            $destName = $_.Name.ToUpper().Replace('_DEL', '')
            $destFile = Join-Path $LocalSrcFolder $destName
            if (-not (Test-Path $destFile)) {
                Copy-Item -Path $_.FullName -Destination $destFile -Force
                Copy-Item -Path $_.FullName -Destination (Join-Path $DiscardedFolder $destName) -Force
            }
        }
    }

    # Collect production scripts
    if (Test-Path $ProdAppPath) {
        Get-ChildItem -Path $ProdAppPath -File -Filter '*.ps*' -Recurse -ErrorAction SilentlyContinue | Copy-Item -Destination $ProdSrcFolder -Force
        Get-ChildItem -Path $ProdAppPath -File -Filter '*.bat' -Recurse -ErrorAction SilentlyContinue | Copy-Item -Destination $ProdSrcFolder -Force
    }

    # Clean noise files: backups with date patterns, old versions, spaces
    $cleanFiles = Get-ChildItem -Path $LocalSrcFolder -File -ErrorAction SilentlyContinue
    foreach ($file in $cleanFiles) {
        $shouldDiscard = $false
        # Files with 6-8 digit date patterns
        if ($file.BaseName -match '\d{6,8}') { $shouldDiscard = $true }
        # Files with spaces
        if ($file.BaseName -match '\s') { $shouldDiscard = $true }
        # Old/new version markers
        if ($file.BaseName -match '[-_](GML|NY)') { $shouldDiscard = $true }
        # Year-stamped files (any 4-digit year from 2000-2029)
        if ($file.BaseName -match '20[0-2]\d') { $shouldDiscard = $true }

        if ($shouldDiscard) {
            Move-Item -Path $file.FullName -Destination $DiscardedFolder -Force -ErrorAction SilentlyContinue
        }
    }

    # Copy production CBL files
    foreach ($src in $ProdArray) {
        if ($src -notlike '*.CBL') { continue }
        $srcFile = Join-Path $LocalSrcFolder $src
        $destFile = Join-Path $ProdSrcFolder $src
        if ((Test-Path $srcFile) -and -not (Test-Path $destFile)) {
            Copy-Item -Path $srcFile -Destination $destFile -Force
        }
    }
}

function Find-FileUsage {
    param([string]$FileName, [string]$SearchFolder, [string[]]$UsedByList)
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName).ToUpper()
    $ext = [System.IO.Path]::GetExtension($FileName).ToUpper().TrimStart('.')

    $includeFilter = switch ($ext) {
        { $_ -in 'BAT', 'PS1' } { @('*.ps1', '*.bat', '*.rex', '*.xml') }
        'PSM1' { @('*.ps1', '*.psm1') }
        'REX' { @('*.ps1', '*.bat', '*.rex', '*.xml') }
        'CBL' { @('*.ps1', '*.bat', '*.rex', '*.cbl') }
        default { @() }
    }

    $searchPattern = if ($ext -eq 'CBL') { $baseName } else { $FileName }
    if ($includeFilter.Count -eq 0 -or -not $searchPattern) { return $UsedByList }

    $hits = Get-ChildItem -Path $SearchFolder -Include $includeFilter -Recurse -ErrorAction SilentlyContinue |
        Select-String $searchPattern -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Path -Unique

    foreach ($hitPath in $hits) {
        $hitName = (Get-Item $hitPath).Name.ToUpper()
        if ($hitName -eq $FileName -or $UsedByList -contains $hitName) { continue }
        $UsedByList += $hitName
        $UsedByList = Find-FileUsage -FileName $hitName -SearchFolder $SearchFolder -UsedByList $UsedByList
    }

    return $UsedByList
}
