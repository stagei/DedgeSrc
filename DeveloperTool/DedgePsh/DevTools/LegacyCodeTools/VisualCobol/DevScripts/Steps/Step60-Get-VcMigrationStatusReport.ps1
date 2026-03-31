#Requires -Version 7.0
<#
.SYNOPSIS
    Generates a unified migration status report for COBOL programs.
.DESCRIPTION
    Combines three data sources into a single report that shows exactly which
    programs need recompilation, where source code exists, and which programs
    are still in active use:

    1. DBM.MODUL (COBDOK database) — program registry with SYSTEM field
       (UTGATT = retired/no longer in use), modultype, description, SQL usage
    2. SYSCAT.PACKAGES (FKAVDNT database) — DB2 package bind metadata with
       ALTER_TIME showing the last time each package was bound/rebound
    3. File system — scans production INT folder and multiple source locations
       to determine source availability and location

    The report classifies every program into:
    - UTGATT:       Marked as retired in COBDOK — skip recompilation
    - NO_SOURCE:    Active but no source found — needs investigation
    - HAS_SOURCE:   Active with source located — ready for recompilation
    - NO_INT:       In COBDOK but no production INT file — informational

    Additionally embeds Ollama uncertain file resolution data from Step15
    (CBL) and Step25 (CPY) if their log files exist.

    Outputs: JSON + TSV (tab-separated) files.

    Uses Get-QueryResultDirect from Db2-Handler module for ODBC queries.
.PARAMETER IntPath
    UNC path to production INT files.
.PARAMETER SourceSearchFolders
    Array of folders to search for .CBL source files.
.PARAMETER CobdokDsn
    ODBC DSN name for the COBDOK database (contains DBM.MODUL).
.PARAMETER FkavdntDsn
    ODBC DSN name for the FKAVDNT database (contains SYSCAT.PACKAGES).
.PARAMETER OutputFolder
    Where to write the report files. Defaults to script folder or Get-ApplicationDataPath.
.PARAMETER SkipDb2
    Skip DB2 queries (use cached CSV files from previous AutoDoc export if available).
.PARAMETER SendNotification
    Send SMS notification when report is complete.
.EXAMPLE
    .\Get-VcMigrationStatusReport.ps1
.EXAMPLE
    .\Get-VcMigrationStatusReport.ps1 -SkipDb2
    Uses cached modul.csv from AutoDoc export instead of live DB2 query.
#>
[CmdletBinding()]
param(
    [string]$IntPath = '\\DEDGE.fk.no\erpprog\COBNT',

    [string[]]$SourceSearchFolders = @(
        '\\DEDGE.fk.no\erputv\Utvikling\fkavd\NT',
        '\\DEDGE.fk.no\erputv\Utvikling\fkavd\utgatt',
        '\\DEDGE.fk.no\erputv\Utvikling\CBLARKIV',
        'C:\opt\data\AutoDocJson\tmp\DedgeRepository\Dedge\cbl',
        'C:\opt\data\AutoDocJson\tmp\DedgeRepository\Dedge\gs'
    ),

    [string]$CobdokDsn = 'COBDOK',
    [string]$FkavdntDsn = 'BASISVCT',

    [string]$OutputFolder = '',

    [switch]$SkipDb2,

    [switch]$SendNotification
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

# ─────────────────────────────────────────────────────────────────────────────
# Resolve output and local working folder via Get-ApplicationDataPath
# ─────────────────────────────────────────────────────────────────────────────
$appDataPath = Get-ApplicationDataPath
if ([string]::IsNullOrEmpty($OutputFolder)) { $OutputFolder = $appDataPath }
New-Item -Path $OutputFolder -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

$localWorkRoot = Join-Path $appDataPath 'LocalCopies'
$localIntFolder = Join-Path $localWorkRoot 'int'
$localSrcRoot   = Join-Path $localWorkRoot 'src'
foreach ($d in @($localWorkRoot, $localIntFolder, $localSrcRoot)) {
    New-Item -Path $d -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
Write-LogMessage "Migration Status Report starting" -Level INFO
Write-LogMessage "  Output folder:     $($OutputFolder)" -Level INFO
Write-LogMessage "  Local copies root: $($localWorkRoot)" -Level INFO

# ─────────────────────────────────────────────────────────────────────────────
# Step 1: Query DBM.MODUL from COBDOK
# ─────────────────────────────────────────────────────────────────────────────
Write-LogMessage "Step 1: Retrieving program registry from COBDOK (DBM.MODUL)..." -Level INFO

$cobdokModules = @()
$cobdokCacheDir = if ($env:OptPath) { "$($env:OptPath)\data\AzureDevOpsGitCheckIn\cobdok" } else { $env:TEMP }
$cobdokCacheFile = Join-Path $cobdokCacheDir 'modul.csv'

if ($SkipDb2) {
    if (Test-Path $cobdokCacheFile) {
        Write-LogMessage "Using cached modul.csv from: $($cobdokCacheFile)" -Level INFO
        $cobdokModules = Import-Csv -Path $cobdokCacheFile -Delimiter ';' -Encoding UTF8
    } else {
        $autoDocCache = Join-Path $env:OptPath 'data\AutoDocJson\cobdok\modul.csv'
        if (Test-Path $autoDocCache) {
            Write-LogMessage "Using AutoDoc cached modul.csv from: $($autoDocCache)" -Level INFO
            $cobdokModules = Import-Csv -Path $autoDocCache -Delimiter ';' -Encoding UTF8
        } else {
            Write-LogMessage "No cached modul.csv found — COBDOK data will be empty" -Level WARN
        }
    }
} else {
    try {
        $cobdokModules = Get-QueryResultDirect -RemoteDatabaseName $CobdokDsn -Query @"
SELECT MODUL, SYSTEM, DELSYSTEM, MODULTYPE, TEKST,
       BENYTTER_SQL, BENYTTER_DS, FRA_DATO, ANTALL_LINJER, FILENAVN
FROM DBM.MODUL
ORDER BY MODUL
"@
        Write-LogMessage "Retrieved $($cobdokModules.Count) modules from COBDOK" -Level INFO
    } catch {
        Write-LogMessage "COBDOK query failed: $($_.Exception.Message) — trying cached file" -Level WARN
        if (Test-Path $cobdokCacheFile) {
            $cobdokModules = Import-Csv -Path $cobdokCacheFile -Delimiter ';' -Encoding UTF8
            Write-LogMessage "Loaded $($cobdokModules.Count) modules from cache" -Level INFO
        }
    }
}

$cobdokLookup = @{}
foreach ($mod in $cobdokModules) {
    $key = ($mod.MODUL ?? $mod.modul ?? '').ToString().Trim().ToUpper()
    if ($key) { $cobdokLookup[$key] = $mod }
}
Write-LogMessage "COBDOK lookup built: $($cobdokLookup.Count) programs" -Level INFO

# ─────────────────────────────────────────────────────────────────────────────
# Step 2: Query SYSCAT.PACKAGES from FKAVDNT for last bind timestamps
# ─────────────────────────────────────────────────────────────────────────────
Write-LogMessage "Step 2: Retrieving DB2 package bind dates from FKAVDNT (SYSCAT.PACKAGES)..." -Level INFO

$packageLookup = @{}

if (-not $SkipDb2) {
    try {
        # ALTER_TIME = last time package was bound/rebound/altered
        # CREATE_TIME = original bind time
        # VALID = Y/N — whether the package is valid
        $packages = Get-QueryResultDirect -RemoteDatabaseName $FkavdntDsn -Query @"
SELECT PKGNAME, PKGSCHEMA, VALID,
       CHAR(CREATE_TIME) AS CREATE_TIME,
       CHAR(ALTER_TIME) AS ALTER_TIME
FROM SYSCAT.PACKAGES
WHERE PKGSCHEMA = 'DBM'
ORDER BY PKGNAME
"@
        foreach ($pkg in $packages) {
            $key = ($pkg.PKGNAME ?? '').ToString().Trim().ToUpper()
            if ($key -and -not $packageLookup.ContainsKey($key)) {
                $packageLookup[$key] = $pkg
            }
        }
        Write-LogMessage "Retrieved $($packageLookup.Count) packages from SYSCAT.PACKAGES" -Level INFO
    } catch {
        Write-LogMessage "SYSCAT.PACKAGES query failed: $($_.Exception.Message)" -Level WARN
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 3: Scan production INT files — copy to local first (per remote-log-reading rule)
# ─────────────────────────────────────────────────────────────────────────────
Write-LogMessage "Step 3: Scanning production INT files from $($IntPath)..." -Level INFO

$intFiles = @{}
if (Test-Path $IntPath) {
    Write-LogMessage "  Copying INT files to local: $($localIntFolder)" -Level INFO
    $intItems = Get-ChildItem -Path $IntPath -Filter '*.int' -ErrorAction SilentlyContinue
    $copyCount = 0
    foreach ($f in $intItems) {
        $localDest = Join-Path $localIntFolder $f.Name
        try {
            if ([string]::Equals($f.FullName, $localDest, [System.StringComparison]::OrdinalIgnoreCase)) {
                # When IntPath already points to local copy folder, skip self-copy noise.
            } else {
                Copy-Item -Path $f.FullName -Destination $localDest -Force
                $copyCount++
            }
        } catch {
            Write-LogMessage "  Copy failed: $($f.Name) — $($_.Exception.Message)" -Level WARN
        }
        $key = $f.BaseName.ToUpper()
        $intFiles[$key] = [PSCustomObject]@{
            Name         = $f.Name
            Size         = $f.Length
            LastModified = $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
            LocalPath    = $localDest
        }
    }
    Write-LogMessage "  Copied $($copyCount)/$(@($intItems).Count) INT files locally" -Level INFO
    Write-LogMessage "Found $($intFiles.Count) production INT files" -Level INFO
} else {
    Write-LogMessage "INT path not accessible: $($IntPath)" -Level WARN
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 4: Search for source files — copy all to local (per remote-log-reading rule)
# ─────────────────────────────────────────────────────────────────────────────
Write-LogMessage "Step 4: Searching for source files across $($SourceSearchFolders.Count) locations..." -Level INFO

$sourceLookup = @{}
$totalCopied = 0

foreach ($folder in $SourceSearchFolders) {
    if (-not (Test-Path $folder)) {
        Write-LogMessage "  Source folder not accessible, skipping: $($folder)" -Level WARN
        continue
    }

    $folderLabel = Split-Path $folder -Leaf
    $parentLabel = Split-Path (Split-Path $folder -Parent) -Leaf
    $localSrcDest = Join-Path $localSrcRoot "$($parentLabel)_$($folderLabel)"
    New-Item -Path $localSrcDest -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

    Write-LogMessage "  Scanning: $($folder)" -Level INFO
    $sourceFiles = Get-ChildItem -Path $folder -Filter '*.cbl' -Recurse -ErrorAction SilentlyContinue
    $foundCount = 0
    $copyCount = 0

    foreach ($sf in $sourceFiles) {
        $key = $sf.BaseName.ToUpper()
        $localDest = Join-Path $localSrcDest $sf.Name

        try {
            Copy-Item -Path $sf.FullName -Destination $localDest -Force
            $copyCount++
        } catch {
            Write-LogMessage "  Copy failed: $($sf.Name) — $($_.Exception.Message)" -Level WARN
        }

        if (-not $sourceLookup.ContainsKey($key)) {
            $reliability = switch -Wildcard ($folder) {
                '*\NT'       { 'HIGH — active development folder' }
                '*\cbl'      { 'HIGH — Git repository (Dedge)' }
                '*\gs'       { 'MEDIUM — generated source' }
                '*\utgatt'   { 'LOW — retired/archived folder' }
                '*\CBLARKIV' { 'LOW — code archive (may be outdated)' }
                default      { 'MEDIUM — other location' }
            }

            $sourceLookup[$key] = [PSCustomObject]@{
                FullPath    = $sf.FullName
                LocalPath   = $localDest
                Location    = "$($parentLabel)\$($folderLabel)"
                Folder      = $folder
                Reliability = $reliability
                Size        = $sf.Length
                Modified    = $sf.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
            }
            $foundCount++
        }
    }

    $totalCopied += $copyCount
    Write-LogMessage "  $($folder): $($foundCount) new unique sources, $($copyCount) files copied to $($localSrcDest)" -Level INFO
}

Write-LogMessage "Source lookup built: $($sourceLookup.Count) unique programs with source ($($totalCopied) total files copied locally)" -Level INFO

# ─────────────────────────────────────────────────────────────────────────────
# Step 5: Build unified report
# ─────────────────────────────────────────────────────────────────────────────
Write-LogMessage "Step 5: Building unified migration status report..." -Level INFO

$allProgramNames = @($cobdokLookup.Keys) + @($intFiles.Keys) + @($sourceLookup.Keys) |
    Sort-Object -Unique

$report = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($pgm in $allProgramNames) {
    $cobdok  = $cobdokLookup[$pgm]
    $intFile = $intFiles[$pgm]
    $source  = $sourceLookup[$pgm]
    $package = $packageLookup[$pgm]

    $system     = ($cobdok.SYSTEM ?? $cobdok.system ?? '').ToString().Trim()
    $isUtgatt   = $system -match 'UTGATT'
    $hasInt     = $null -ne $intFile
    $hasSource  = $null -ne $source
    $hasPkg     = $null -ne $package

    $status = if ($isUtgatt) {
        'UTGATT'
    } elseif ($hasInt -and -not $hasSource) {
        'NO_SOURCE'
    } elseif ($hasInt -and $hasSource) {
        'HAS_SOURCE'
    } elseif (-not $hasInt -and $hasSource) {
        'NO_INT'
    } elseif (-not $hasInt -and -not $hasSource -and $cobdok) {
        'COBDOK_ONLY'
    } else {
        'SOURCE_ONLY'
    }

    $entry = [PSCustomObject]@{
        Program          = $pgm
        Status           = $status
        IntFileExists    = if ($hasInt) { 'Y' } else { 'N' }
        IntFileSize      = if ($hasInt) { $intFile.Size } else { '' }
        IntFileDate      = if ($hasInt) { $intFile.LastModified } else { '' }
        SourceFound      = if ($hasSource) { 'Y' } else { 'N' }
        SourceLocation   = if ($hasSource) { $source.Location } else { '' }
        SourceFullPath   = if ($hasSource) { $source.FullPath } else { '' }
        SourceLocalPath  = if ($hasSource) { $source.LocalPath } else { '' }
        SourceReliability = if ($hasSource) { $source.Reliability } else { '' }
        SourceDate       = if ($hasSource) { $source.Modified } else { '' }
        CobdokSystem     = $system
        CobdokModultype  = ($cobdok.MODULTYPE ?? $cobdok.modultype ?? '').ToString().Trim()
        CobdokDescription = ($cobdok.TEKST ?? $cobdok.tekst ?? '').ToString().Trim()
        CobdokUsesSQL    = ($cobdok.BENYTTER_SQL ?? $cobdok.benytter_sql ?? '').ToString().Trim()
        CobdokUsesDS     = ($cobdok.BENYTTER_DS ?? $cobdok.benytter_ds ?? '').ToString().Trim()
        CobdokLineCount  = ($cobdok.ANTALL_LINJER ?? $cobdok.antall_linjer ?? '').ToString().Trim()
        PkgValid         = if ($hasPkg) { ($package.VALID ?? '').ToString().Trim() } else { '' }
        PkgCreateTime    = if ($hasPkg) { ($package.CREATE_TIME ?? '').ToString().Trim() } else { '' }
        PkgLastBindTime  = if ($hasPkg) { ($package.ALTER_TIME ?? '').ToString().Trim() } else { '' }
    }

    $report.Add($entry)
}

Write-LogMessage "Report built: $($report.Count) total programs" -Level INFO

# ─────────────────────────────────────────────────────────────────────────────
# Step 6: Generate summary statistics
# ─────────────────────────────────────────────────────────────────────────────
$statusGroups = $report | Group-Object -Property Status
$summary = [ordered]@{
    TotalPrograms    = $report.Count
    UTGATT           = ($statusGroups | Where-Object Name -eq 'UTGATT' | Select-Object -ExpandProperty Count) + 0
    HAS_SOURCE       = ($statusGroups | Where-Object Name -eq 'HAS_SOURCE' | Select-Object -ExpandProperty Count) + 0
    NO_SOURCE        = ($statusGroups | Where-Object Name -eq 'NO_SOURCE' | Select-Object -ExpandProperty Count) + 0
    NO_INT           = ($statusGroups | Where-Object Name -eq 'NO_INT' | Select-Object -ExpandProperty Count) + 0
    COBDOK_ONLY      = ($statusGroups | Where-Object Name -eq 'COBDOK_ONLY' | Select-Object -ExpandProperty Count) + 0
    SOURCE_ONLY      = ($statusGroups | Where-Object Name -eq 'SOURCE_ONLY' | Select-Object -ExpandProperty Count) + 0
    IntFilesTotal    = $intFiles.Count
    SourcesFound     = $sourceLookup.Count
    CobdokModules    = $cobdokLookup.Count
    Db2Packages      = $packageLookup.Count
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 7: Export as JSON
# ─────────────────────────────────────────────────────────────────────────────
Write-LogMessage "Step 6: Exporting reports..." -Level INFO

$jsonData = [ordered]@{
    GeneratedAt     = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Script          = 'Get-VcMigrationStatusReport.ps1'
    DataSources     = [ordered]@{
        COBDOK_DBM_MODUL   = "DSN=$($CobdokDsn) — DBM.MODUL ($($cobdokLookup.Count) modules)"
        FKAVDNT_SYSCAT_PKG = "DSN=$($FkavdntDsn) — SYSCAT.PACKAGES WHERE PKGSCHEMA='DBM' ($($packageLookup.Count) packages)"
        IntFileFolder      = "$($IntPath) ($($intFiles.Count) files)"
        SourceFolders      = $SourceSearchFolders
        LocalCopiesRoot    = $localWorkRoot
    }
    Summary         = $summary
    StatusLegend    = [ordered]@{
        UTGATT      = 'Marked as retired in COBDOK — no recompilation needed'
        HAS_SOURCE  = 'Active program with source found — ready for recompilation'
        NO_SOURCE   = 'Active program, INT exists but NO source found — needs investigation'
        NO_INT      = 'In COBDOK/source but no production INT — informational'
        COBDOK_ONLY = 'Registered in COBDOK but no INT or source found'
        SOURCE_ONLY = 'Source file found but not registered in COBDOK and no INT'
    }
    Programs        = @($report | ForEach-Object {
        [ordered]@{
            Program           = $_.Program
            Status            = $_.Status
            IntFileExists     = $_.IntFileExists
            IntFileSize       = $_.IntFileSize
            IntFileDate       = $_.IntFileDate
            SourceFound       = $_.SourceFound
            SourceLocation    = $_.SourceLocation
            SourceFullPath    = $_.SourceFullPath
            SourceLocalPath   = $_.SourceLocalPath
            SourceReliability = $_.SourceReliability
            SourceDate        = $_.SourceDate
            CobdokSystem      = $_.CobdokSystem
            CobdokModultype   = $_.CobdokModultype
            CobdokDescription = $_.CobdokDescription
            CobdokUsesSQL     = $_.CobdokUsesSQL
            CobdokUsesDS      = $_.CobdokUsesDS
            CobdokLineCount   = $_.CobdokLineCount
            PkgValid          = $_.PkgValid
            PkgCreateTime     = $_.PkgCreateTime
            PkgLastBindTime   = $_.PkgLastBindTime
        }
    })
}

# --- Embed Ollama uncertain file resolution data if available ---
$projectRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$dataDir = Join-Path $projectRoot 'Data'

$cblResolvedData = @()
$cblResolvedPath = Join-Path $dataDir 'cbl-uncertain-files-moved.json'
if (Test-Path $cblResolvedPath) {
    try {
        $cblResolvedData = @(Get-Content -LiteralPath $cblResolvedPath -Raw -Encoding utf8 | ConvertFrom-Json)
        Write-LogMessage "Loaded $($cblResolvedData.Count) resolved CBL entries from Step15" -Level INFO
    } catch {
        Write-LogMessage "Failed to parse cbl-uncertain-files-moved.json: $($_.Exception.Message)" -Level WARN
    }
}

$cpyResolvedData = @()
$cpyResolvedPath = Join-Path $dataDir 'cpy-uncertain-files-moved.json'
if (Test-Path $cpyResolvedPath) {
    try {
        $cpyResolvedData = @(Get-Content -LiteralPath $cpyResolvedPath -Raw -Encoding utf8 | ConvertFrom-Json)
        Write-LogMessage "Loaded $($cpyResolvedData.Count) resolved CPY entries from Step25" -Level INFO
    } catch {
        Write-LogMessage "Failed to parse cpy-uncertain-files-moved.json: $($_.Exception.Message)" -Level WARN
    }
}

$jsonData.UncertainResolution = [ordered]@{
    CblResolved = [ordered]@{
        Total          = $cblResolvedData.Count
        SingleCandidate = @($cblResolvedData | Where-Object { $_.confidence -eq 'only-candidate' }).Count
        OllamaAnalyzed  = @($cblResolvedData | Where-Object { $_.confidence -ne 'only-candidate' }).Count
        HighConfidence  = @($cblResolvedData | Where-Object { $_.confidence -eq 'high' }).Count
        MediumConfidence = @($cblResolvedData | Where-Object { $_.confidence -eq 'medium' }).Count
        LowConfidence   = @($cblResolvedData | Where-Object { $_.confidence -eq 'low' }).Count
        Entries         = @($cblResolvedData)
    }
    CpyResolved = [ordered]@{
        Total          = $cpyResolvedData.Count
        SingleCandidate = @($cpyResolvedData | Where-Object { $_.confidence -eq 'only-candidate' }).Count
        OllamaAnalyzed  = @($cpyResolvedData | Where-Object { $_.confidence -ne 'only-candidate' }).Count
        HighConfidence  = @($cpyResolvedData | Where-Object { $_.confidence -eq 'high' }).Count
        MediumConfidence = @($cpyResolvedData | Where-Object { $_.confidence -eq 'medium' }).Count
        LowConfidence   = @($cpyResolvedData | Where-Object { $_.confidence -eq 'low' }).Count
        Entries         = @($cpyResolvedData)
    }
}

$jsonPath = Join-Path $OutputFolder "MigrationStatusReport-$($timestamp).json"
$jsonData | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding utf8 -Force
Write-LogMessage "JSON report: $($jsonPath)" -Level INFO

# ─────────────────────────────────────────────────────────────────────────────
# Step 8: Export as TSV (tab-separated)
# ─────────────────────────────────────────────────────────────────────────────
$tsvPath = Join-Path $OutputFolder "MigrationStatusReport-$($timestamp).tsv"
$report | Export-Csv -Path $tsvPath -Delimiter "`t" -NoTypeInformation -Encoding utf8
Write-LogMessage "TSV report: $($tsvPath)" -Level INFO

# ─────────────────────────────────────────────────────────────────────────────
# Console summary
# ─────────────────────────────────────────────────────────────────────────────
Write-LogMessage "═══════════════════════════════════════════════════════" -Level INFO
Write-LogMessage "  MIGRATION STATUS REPORT COMPLETE" -Level INFO
Write-LogMessage "═══════════════════════════════════════════════════════" -Level INFO
Write-LogMessage "  Total programs:     $($summary.TotalPrograms)" -Level INFO
Write-LogMessage "  UTGATT (retired):   $($summary.UTGATT)  — skip recompilation" -Level INFO
Write-LogMessage "  HAS_SOURCE (ready): $($summary.HAS_SOURCE)  — recompile these" -Level INFO
Write-LogMessage "  NO_SOURCE (urgent): $($summary.NO_SOURCE)  — find source or retire" -Level INFO
Write-LogMessage "  NO_INT (info only): $($summary.NO_INT)" -Level INFO
Write-LogMessage "  COBDOK_ONLY:        $($summary.COBDOK_ONLY)" -Level INFO
Write-LogMessage "  SOURCE_ONLY:        $($summary.SOURCE_ONLY)" -Level INFO
Write-LogMessage "───────────────────────────────────────────────────────" -Level INFO
Write-LogMessage "  INT files:          $($summary.IntFilesTotal)" -Level INFO
Write-LogMessage "  Sources found:      $($summary.SourcesFound)" -Level INFO
Write-LogMessage "  COBDOK modules:     $($summary.CobdokModules)" -Level INFO
Write-LogMessage "  DB2 packages:       $($summary.Db2Packages)" -Level INFO
if ($cblResolvedData.Count -gt 0 -or $cpyResolvedData.Count -gt 0) {
    Write-LogMessage "───────────────────────────────────────────────────────" -Level INFO
    Write-LogMessage "  Uncertain Resolution (Ollama AI):" -Level INFO
    Write-LogMessage "    CBL resolved:     $($cblResolvedData.Count)" -Level INFO
    Write-LogMessage "    CPY resolved:     $($cpyResolvedData.Count)" -Level INFO
}
Write-LogMessage "───────────────────────────────────────────────────────" -Level INFO
Write-LogMessage "  JSON: $($jsonPath)" -Level INFO
Write-LogMessage "  TSV:  $($tsvPath)" -Level INFO
Write-LogMessage "═══════════════════════════════════════════════════════" -Level INFO

if ($SendNotification) {
    $smsNumber = switch ($env:USERNAME) {
        'FKGEISTA' { '+4797188358' }
        'FKSVEERI' { '+4795762742' }
        'FKMISTA'  { '+4799348397' }
        'FKCELERI' { '+4745269945' }
        default    { '+4797188358' }
    }
    $msg = "MigrationReport: $($summary.TotalPrograms) pgms. UTGATT=$($summary.UTGATT) OK=$($summary.HAS_SOURCE) NOSRC=$($summary.NO_SOURCE)"
    Send-Sms -Receiver $smsNumber -Message $msg
}
