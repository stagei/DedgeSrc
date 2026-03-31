<#
.SYNOPSIS
    Copies projects from convertapps.json and rebrands Fk/Felleskjøpet → Dedge.

.DESCRIPTION
    Re-runnable: deletes previous target copy, creates fresh copy, applies rebranding.
    Driven entirely by convertapps.json — add/remove entries to control scope.

.EXAMPLE
    pwsh.exe -File .\Convert-AppsToDedge.ps1
    pwsh.exe -File .\Convert-AppsToDedge.ps1 -DryRun
#>
param(
    [string]$JsonPath = (Join-Path $PSScriptRoot 'convertapps.json'),
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Script:LogFile = Join-Path $PSScriptRoot "Convert-AppsToDedge_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

$Script:BinaryExtensions = '.dll','.exe','.pdb','.nupkg','.snupkg','.snk',
    '.pdf','.png','.jpg','.jpeg','.gif','.bmp','.ico','.svg','.webp',
    '.zip','.gz','.tar','.7z','.rar','.cab','.mshc',
    '.woff','.woff2','.ttf','.eot','.otf',
    '.db','.sqlite','.mdf','.ldf','.bak',
    '.pyc','.pyo','.whl','.msi','.msm','.msp',
    '.mp3','.mp4','.wav','.avi','.lock'

$Script:ExcludeDirs = '.git','bin','obj','node_modules','__pycache__','.vs','packages','TestResults'

# ═══════════════════════════════════════════════════════════════════════════════
#  BUILD REPLACEMENT TABLES (using .Add() to avoid PowerShell array flattening)
# ═══════════════════════════════════════════════════════════════════════════════

# UNC path replacements — these are REGEX patterns (backslashes pre-escaped)
$Script:UncRules = [System.Collections.Generic.List[hashtable]]::new()
$Script:UncRules.Add(@{ Pattern = '\\\\t-no1fkxtst-app\\FkCommon';      Replace = 'C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon' })
$Script:UncRules.Add(@{ Pattern = '\\\\t-no1fkxtst-app\\DocViewContent'; Replace = 'C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DocView' })
$Script:UncRules.Add(@{ Pattern = '\\\\t-no1fkxtst-app\\CommonLogging';  Replace = 'C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Commonlogging' })
$Script:UncRules.Add(@{ Pattern = '\\\\t-no1fkxtst-app\\Opt';            Replace = 'C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt' })
$Script:UncRules.Add(@{ Pattern = '\\\\t-no1fkxtst-app';                 Replace = 'dedge-server' })
$Script:UncRules.Add(@{ Pattern = 't-no1fkxtst-app';                     Replace = 'dedge-server' })

# Content replacements — REGEX patterns, ordered most-specific first
$Script:ContentRules = [System.Collections.Generic.List[hashtable]]::new()
$Script:ContentRules.Add(@{ Pattern = 'FKA\.FKMeny\.FkCommon';  Replace = 'Dedge.DedgeCommon' })
$Script:ContentRules.Add(@{ Pattern = 'FKA\.FKMeny';            Replace = 'Dedge' })
$Script:ContentRules.Add(@{ Pattern = 'FkRemoteConnect';        Replace = 'DedgeRemoteConnect' })
$Script:ContentRules.Add(@{ Pattern = 'FKRemoteConnect';        Replace = 'DedgeRemoteConnect' })
$Script:ContentRules.Add(@{ Pattern = 'FkDbHandler';            Replace = 'DedgeDbHandler' })
$Script:ContentRules.Add(@{ Pattern = 'FkConnection';           Replace = 'DedgeConnection' })
$Script:ContentRules.Add(@{ Pattern = 'FkNLog';                 Replace = 'DedgeNLog' })
$Script:ContentRules.Add(@{ Pattern = 'FkNlog';                 Replace = 'DedgeNLog' })
$Script:ContentRules.Add(@{ Pattern = 'FkWinApps';              Replace = 'DedgeWinApps' })
$Script:ContentRules.Add(@{ Pattern = 'FkPshApps';              Replace = 'DedgePshApps' })
$Script:ContentRules.Add(@{ Pattern = 'FkSign';                 Replace = 'DedgeSign' })
$Script:ContentRules.Add(@{ Pattern = 'FkAuth';                 Replace = 'DedgeAuth' })
$Script:ContentRules.Add(@{ Pattern = 'FKAuth';                 Replace = 'DedgeAuth' })
$Script:ContentRules.Add(@{ Pattern = 'FkCommon';               Replace = 'DedgeCommon' })
$Script:ContentRules.Add(@{ Pattern = 'FKCommon';               Replace = 'DedgeCommon' })
$Script:ContentRules.Add(@{ Pattern = 'FKMenyPSH';              Replace = 'DedgePsh' })
$Script:ContentRules.Add(@{ Pattern = 'FkMenyPSH';              Replace = 'DedgePsh' })
$Script:ContentRules.Add(@{ Pattern = 'FKMeny';                 Replace = 'Dedge' })
$Script:ContentRules.Add(@{ Pattern = 'FkMeny';                 Replace = 'Dedge' })
$Script:ContentRules.Add(@{ Pattern = 'Felleskj.pet\s+Agri\s+SA'; Replace = 'Dedge AS' })
$Script:ContentRules.Add(@{ Pattern = 'Felleskj.pet\s+Agri';   Replace = 'Dedge' })
$Script:ContentRules.Add(@{ Pattern = 'Felleskj.petAgri';       Replace = 'Dedge' })
$Script:ContentRules.Add(@{ Pattern = 'Felleskj.pet';           Replace = 'Dedge' })
$Script:ContentRules.Add(@{ Pattern = 'felleskj.pet';           Replace = 'Dedge' })
$Script:ContentRules.Add(@{ Pattern = 'FKA_logo--desktop\.svg';  Replace = 'dedge-logo.svg' })
$Script:ContentRules.Add(@{ Pattern = 'fkauth-admin\.png';      Replace = 'dedgeauth-admin.png' })
$Script:ContentRules.Add(@{ Pattern = 'fkauth-logged-in\.png';  Replace = 'dedgeauth-logged-in.png' })
$Script:ContentRules.Add(@{ Pattern = 'fkauth-login\.png';      Replace = 'dedgeauth-login.png' })
$Script:ContentRules.Add(@{ Pattern = 'FkBanner\.png';          Replace = 'DedgeBanner.png' })
$Script:ContentRules.Add(@{ Pattern = '(?<![a-zA-Z])fk\.ico';   Replace = 'dedge.ico' })
$Script:ContentRules.Add(@{ Pattern = '(?<![a-zA-Z])fk\.svg';   Replace = 'dedge.svg' })
$Script:ContentRules.Add(@{ Pattern = 'FKNETT';                 Replace = 'DEDGE' })
$Script:ContentRules.Add(@{ Pattern = 'fknett';                 Replace = 'dedge' })
$Script:ContentRules.Add(@{ Pattern = 'Fknett';                 Replace = 'Dedge' })
$Script:ContentRules.Add(@{ Pattern = '[a-zA-Z0-9_.+-]+@felleskj.pet\.no'; Replace = 'geir.helge.starholm@dedge.no' })
$Script:ContentRules.Add(@{ Pattern = '[a-zA-Z0-9_.+-]+@fk[a-z]*\.no';    Replace = 'geir.helge.starholm@dedge.no' })
$Script:ContentRules.Add(@{ Pattern = 'https?://[a-zA-Z0-9.-]*felleskj.pet[a-zA-Z0-9.-]*\.no'; Replace = 'https://www.dedge.no' })

# File/folder renames — LITERAL string find/replace (not regex)
$Script:RenameRules = [System.Collections.Generic.List[hashtable]]::new()
$Script:RenameRules.Add(@{ Find = 'FkRemoteConnect';  To = 'DedgeRemoteConnect' })
$Script:RenameRules.Add(@{ Find = 'FkDbHandler';      To = 'DedgeDbHandler' })
$Script:RenameRules.Add(@{ Find = 'FkConnection';     To = 'DedgeConnection' })
$Script:RenameRules.Add(@{ Find = 'FkNLog';           To = 'DedgeNLog' })
$Script:RenameRules.Add(@{ Find = 'FkNlog';           To = 'DedgeNLog' })
$Script:RenameRules.Add(@{ Find = 'FkWinApps';        To = 'DedgeWinApps' })
$Script:RenameRules.Add(@{ Find = 'FkSign';           To = 'DedgeSign' })
$Script:RenameRules.Add(@{ Find = 'FkAuth';           To = 'DedgeAuth' })
$Script:RenameRules.Add(@{ Find = 'FKAuth';           To = 'DedgeAuth' })
$Script:RenameRules.Add(@{ Find = 'FkCommon';         To = 'DedgeCommon' })
$Script:RenameRules.Add(@{ Find = 'FKCommon';         To = 'DedgeCommon' })
$Script:RenameRules.Add(@{ Find = 'FKMenyPSH';        To = 'DedgePsh' })
$Script:RenameRules.Add(@{ Find = 'FKMeny';           To = 'Dedge' })
$Script:RenameRules.Add(@{ Find = 'FkMeny';           To = 'Dedge' })
$Script:RenameRules.Add(@{ Find = 'FKA_logo--desktop'; To = 'dedge-logo' })
$Script:RenameRules.Add(@{ Find = 'fka-logo';         To = 'dedge-logo' })
$Script:RenameRules.Add(@{ Find = 'fkauth-admin';     To = 'dedgeauth-admin' })
$Script:RenameRules.Add(@{ Find = 'fkauth-logged-in'; To = 'dedgeauth-logged-in' })
$Script:RenameRules.Add(@{ Find = 'fkauth-login';     To = 'dedgeauth-login' })
$Script:RenameRules.Add(@{ Find = 'FkBanner';         To = 'DedgeBanner' })
$Script:RenameRules.Add(@{ Find = 'fk.ico';           To = 'dedge.ico' })
$Script:RenameRules.Add(@{ Find = 'fk.svg';           To = 'dedge.svg' })

# Source icon for binary replacement (actual Dedge-branded icon from DbExplorer)
$Script:DedgeIconSource = 'C:\opt\src\DedgeSrc\DbExplorer\Resources\dEdge.ico'

# ═══════════════════════════════════════════════════════════════════════════════
#  HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

function Write-Log ([string]$Message, [string]$Level = 'INFO') {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$($Level)] $($Message)"
    $color = switch ($Level) { 'ERROR' { 'Red' } 'WARN' { 'Yellow' } 'OK' { 'Green' } default { 'Gray' } }
    Write-Host $line -ForegroundColor $color
    [System.IO.File]::AppendAllText($Script:LogFile, "$($line)`r`n")
}

function Test-BinaryFile ([string]$Path) {
    $Script:BinaryExtensions -contains [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
}

function Copy-ProjectFolder ([string]$Source, [string]$Target) {
    if (-not (Test-Path $Source)) { Write-Log "SKIP source missing: $($Source)" -Level WARN; return $false }
    if ($DryRun) { Write-Log "  [DryRun] Would copy" ; return $false }
    if (Test-Path $Target) {
        Write-Log "  Removing previous copy"
        Remove-Item $Target -Recurse -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 300
    }
    Write-Log "  Copying..."
    $xd = $Script:ExcludeDirs | ForEach-Object { '/XD'; $_ }
    $null = & robocopy $Source $Target /E /NP /NFL /NDL /NJS /NJH /R:1 /W:1 @xd
    return (Test-Path $Target)
}

function Invoke-ContentReplacement ([string]$FilePath) {
    if (Test-BinaryFile $FilePath) { return $false }
    $item = Get-Item $FilePath -ErrorAction SilentlyContinue
    if (-not $item -or $item.PSIsContainer) { return $false }
    try { $sz = $item.Length } catch { return $false }
    if ($sz -eq 0 -or $sz -gt 10MB) { return $false }
    try { $content = [System.IO.File]::ReadAllText($FilePath) } catch { return $false }
    $original = $content

    foreach ($rule in $Script:UncRules) {
        if ($content -match $rule.Pattern) {
            $content = $content -replace $rule.Pattern, $rule.Replace
        }
    }
    foreach ($rule in $Script:ContentRules) {
        if ($content -match $rule.Pattern) {
            $content = $content -replace $rule.Pattern, $rule.Replace
        }
    }
    if ($content -cne $original) {
        [System.IO.File]::WriteAllText($FilePath, $content, [System.Text.UTF8Encoding]::new($true))
        return $true
    }
    return $false
}

function Invoke-FileRenames ([string]$Root) {
    $count = 0
    foreach ($f in (Get-ChildItem $Root -Recurse -File)) {
        $newName = $f.Name
        foreach ($rule in $Script:RenameRules) {
            if ($newName.Contains($rule.Find)) {
                $newName = $newName.Replace($rule.Find, $rule.To)
            }
        }
        if ($newName -cne $f.Name -and -not (Test-Path (Join-Path $f.DirectoryName $newName))) {
            Rename-Item $f.FullName $newName
            Write-Log "    File: $($f.Name) -> $($newName)"
            $count++
        }
    }
    foreach ($d in (Get-ChildItem $Root -Recurse -Directory | Sort-Object { $_.FullName.Length } -Descending)) {
        $newName = $d.Name
        foreach ($rule in $Script:RenameRules) {
            if ($newName.Contains($rule.Find)) {
                $newName = $newName.Replace($rule.Find, $rule.To)
            }
        }
        if ($newName -cne $d.Name -and -not (Test-Path (Join-Path $d.Parent.FullName $newName))) {
            Rename-Item $d.FullName $newName
            Write-Log "    Dir:  $($d.Name) -> $($newName)"
            $count++
        }
    }
    return $count
}

function Invoke-IconReplacement ([string]$Root) {
    if (-not (Test-Path $Script:DedgeIconSource)) {
        Write-Log "  Icon source not found: $($Script:DedgeIconSource)" -Level WARN
        return 0
    }
    $count = 0
    $icoFiles = @(Get-ChildItem $Root -Recurse -File -Filter 'dedge.ico' -ErrorAction SilentlyContinue)
    foreach ($ico in $icoFiles) {
        try {
            Copy-Item $Script:DedgeIconSource $ico.FullName -Force
            Write-Log "    Icon: $($ico.FullName | Split-Path -Leaf) replaced with dEdge.ico"
            $count++
        } catch {
            Write-Log "    Icon replace failed: $($ico.Name) — $($_.Exception.Message)" -Level WARN
        }
    }
    return $count
}

# ═══════════════════════════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════════════════════════

Write-Log '================================================================='
Write-Log 'Convert-AppsToDedge: Rebrand Fk/Felleskjopet to Dedge'
Write-Log '================================================================='
if ($DryRun) { Write-Log '*** DRY RUN ***' -Level WARN }

if (-not (Test-Path $JsonPath)) { Write-Log "JSON not found: $($JsonPath)" -Level ERROR; exit 1 }
$config = Get-Content $JsonPath -Raw | ConvertFrom-Json
Write-Log "Loaded $($config.projects.Count) projects"
Write-Log "Rename rules: $($Script:RenameRules.Count)  Content rules: $($Script:ContentRules.Count)  UNC rules: $($Script:UncRules.Count)"

$stats = @{ Copied = 0; Skipped = 0; Modified = 0; Renamed = 0; Icons = 0 }
$sw = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($proj in $config.projects) {
    Write-Log ''
    Write-Log "--- [$($proj.name)] ---"
    Write-Log "  From: $($proj.currentPath)"
    Write-Log "  To:   $($proj.copyToPath)"

    if (-not (Copy-ProjectFolder $proj.currentPath $proj.copyToPath)) { $stats.Skipped++; continue }
    $stats.Copied++

    $textFiles = @(Get-ChildItem $proj.copyToPath -Recurse -File -ErrorAction SilentlyContinue | Where-Object { -not (Test-BinaryFile $_.FullName) })
    $mod = 0
    foreach ($tf in $textFiles) { if (Invoke-ContentReplacement $tf.FullName) { $mod++ } }
    Write-Log "  Content: $($mod)/$($textFiles.Count) files modified"
    $stats.Modified += $mod

    $ren = Invoke-FileRenames $proj.copyToPath
    Write-Log "  Renames: $($ren)"
    $stats.Renamed += $ren

    $ico = Invoke-IconReplacement $proj.copyToPath
    if ($ico -gt 0) { Write-Log "  Icons replaced: $($ico)" }
    $stats.Icons += $ico

    Write-Log "  Complete" -Level OK
}

$sw.Stop()
Write-Log ''
Write-Log '================================================================='
Write-Log "DONE  Copied=$($stats.Copied)  Skipped=$($stats.Skipped)  Modified=$($stats.Modified)  Renamed=$($stats.Renamed)  Icons=$($stats.Icons)  Time=$($sw.Elapsed.ToString('hh\:mm\:ss'))"
Write-Log "Log: $($Script:LogFile)"
Write-Log '================================================================='
