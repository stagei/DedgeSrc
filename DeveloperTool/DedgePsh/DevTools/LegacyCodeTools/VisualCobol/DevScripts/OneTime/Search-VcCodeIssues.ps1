#Requires -Version 7.0
<#
.SYNOPSIS
    Scans COBOL source files for migration portability issues.
.DESCRIPTION
    Scans all COBOL source files in a repository or folder for patterns that are
    problematic during migration to Rocket Visual COBOL. Detects UNC paths, drive
    letter paths, DB2 commands, database aliases, REXX calls, and other migration-sensitive
    patterns. Results are written to structured output files.

    Replaces: OldScripts\VisualCobolCodeMigration\VisualCobolCodeSearch.ps1
    Changes from old version:
    - Uses GlobalFunctions Write-LogMessage and Send-Sms
    - Fixed $$ bug (now uses $PSScriptRoot)
    - Removed global variable pollution (uses script-scoped collections)
    - Cleaner pattern matching with documented regex
    - Removed duplicate path-cleaning loops
    - Properly handles encoding via .NET instead of external TilUTF8.exe

    Source: Rocket Visual COBOL Documentation Version 11 - Compiling COBOL Applications
.EXAMPLE
    .\Search-VcCodeIssues.ps1 -SourceFolder 'C:\opt\work\Dedge'
    .\Search-VcCodeIssues.ps1 -SourceFolder 'C:\opt\work\Dedge' -OutputFolder 'C:\temp\migration-results'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SourceFolder,

    [string]$OutputFolder = (Join-Path $PSScriptRoot 'SearchResults'),
    [string]$VcPath = $(if ($env:VCPATH) { $env:VCPATH } else { 'C:\fkavd\Dedge2' }),
    [switch]$SendNotification
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

if (-not (Test-Path $SourceFolder)) {
    Write-LogMessage "Source folder not found: $($SourceFolder)" -Level ERROR
    exit 1
}

New-Item -Path $OutputFolder -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

if ($SendNotification) {
    $smsNumber = switch ($env:USERNAME) {
        'FKGEISTA' { '+4797188358' }
        'FKSVEERI' { '+4795762742' }
        'FKMISTA'  { '+4799348397' }
        'FKCELERI' { '+4745269945' }
        default    { '+4797188358' }
    }
    Send-Sms -Receiver $smsNumber -Message "CodeSearch started for $($SourceFolder | Split-Path -Leaf)"
}

Write-LogMessage "Scanning source folder: $($SourceFolder)" -Level INFO

$searchPatterns = @(
    @{ Pattern = '\\\\[^\s\\]+.*?(?=[''"\),\s>]|$)'; Type = 'UNC' }
    @{ Pattern = '[a-zA-Z]:\\+.*?(?=[''"\),\s>]|$)';  Type = 'DRIVE' }
    @{ Pattern = '(?<!N:\\)COBNT|(?<!N:\\)COBTST|(?<!K:\\)FKAVD\\NT\\'; Type = 'MISC' }
    @{ Pattern = '^\s*DB2CMD\s+';                       Type = 'DB2CMD' }
    @{ Pattern = '^\s*RUNW?\s+';                        Type = 'RUN' }
    @{ Pattern = 'CALL\s+RUNW?\s+';                     Type = 'CALLRUN' }
    @{ Pattern = 'SET DB2.*DB=FKAVDNT';                 Type = 'SETDB2' }
    @{ Pattern = 'SET DB2.*DB=(?!FKAVDNT)\w+';          Type = 'INVALID_SETDB2' }
    @{ Pattern = 'COPY.*SQLENV.*.';                     Type = 'SQLENV' }
    @{ Pattern = 'REXX\s+';                             Type = 'REXX' }
    @{ Pattern = 'BASISPRO|BASISHST|BASISRAP|BASISTST|VISMABUS|VISMAHST|FKKONTO|FKAVDNT|BASISMIG|BASISSIT|VISMAMIG'; Type = 'DBALIAS' }
)

$includeExtensions = @('*.cbl', '*.cpy', '*.cpb', '*.cpx', '*.imp', '*.dcl', '*.ps1', '*.psm1', '*.bat', '*.rex', '*.cmd')
$fileArray = Get-ChildItem $SourceFolder -Recurse -Include $includeExtensions -File

$results = [System.Collections.Generic.List[string]]::new()
$resultPaths = [System.Collections.Generic.List[string]]::new()
$resultMachines = [System.Collections.Generic.List[string]]::new()
$resultFiles = [System.Collections.Generic.List[string]]::new()
$newPaths = [System.Collections.Generic.List[string]]::new()
$fileChanges = [System.Collections.Generic.List[string]]::new()

$fileCounter = 0
$matchCounter = 0

$combinedPattern = ($searchPatterns | ForEach-Object { $_.Pattern }) -join '|'

foreach ($file in $fileArray) {
    $fileCounter++

    try {
        $content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::GetEncoding(1252))
        $lines = $content -split "`r?`n"
    } catch {
        Write-LogMessage "Could not read file: $($file.FullName) - $($_.Exception.Message)" -Level WARN
        continue
    }

    $quickCheck = $lines | Select-String -Pattern $combinedPattern -Quiet
    if (-not $quickCheck) { continue }

    foreach ($line in $lines) {
        $lineNumber = [array]::IndexOf($lines, $line) + 1

        if (Test-IsCommentLine -Line $line -Extension $file.Extension) { continue }

        foreach ($sp in $searchPatterns) {
            if ($file.Extension.ToUpper() -ne '.CPX' -and $sp.Type -eq 'CPX') { continue }
            if ($line -match 'SET DB2' -and $sp.Type -eq 'DBALIAS') { continue }

            $matches = [regex]::Matches($line, $sp.Pattern)
            foreach ($m in $matches) {
                $matchText = $m.Value
                $cleanPath = Clean-MatchPath -RawMatch $matchText -Type $sp.Type

                $relFile = $file.FullName.Replace("$($SourceFolder)\", '')
                $results.Add("$($relFile);$($sp.Type);$($cleanPath);$($lineNumber);$($line.Trim())")

                if ($cleanPath.StartsWith('\\') -and $cleanPath.Length -gt 2) {
                    $server = $cleanPath.TrimStart('\').Split('\')[0]
                    if ($server) { $resultMachines.Add($server) }
                }

                if ($cleanPath.Trim().Length -gt 0) { $resultPaths.Add($cleanPath) }
                $resultFiles.Add($file.FullName)

                $newPath = Convert-ToVcPath -CleanPath $cleanPath -Type $sp.Type -VcPath $VcPath
                if ($newPath) { $newPaths.Add($newPath) }

                $origPath = if ($sp.Type -eq 'SETDB2') { $line } else { $cleanPath }
                $destPath = if ($sp.Type -eq 'SETDB2') { $line.Replace('DB=FKAVDNT', 'DB=DB2DEV') } else { $newPath }
                $fileChanges.Add("$($file.FullName);$($sp.Type);$($lineNumber);$($origPath);$($destPath)")

                $matchCounter++
            }
        }
    }

    if ($fileCounter % 500 -eq 0) {
        Write-LogMessage "Progress: $($fileCounter)/$($fileArray.Count) files, $($matchCounter) matches" -Level INFO
    }
}

# --- Write output files ---
$outputFiles = @{
    'ResultTexts.txt'    = ($results | Sort-Object -Unique)
    'ResultPaths.txt'    = ($resultPaths | Sort-Object -Unique)
    'ResultMachines.txt' = ($resultMachines | Sort-Object -Unique)
    'Files.txt'          = ($resultFiles | Sort-Object -Unique)
    'NewPaths.txt'       = ($newPaths | Sort-Object -Unique)
    'FileChanges.txt'    = ($fileChanges | Sort-Object -Unique)
}

foreach ($entry in $outputFiles.GetEnumerator()) {
    $outPath = Join-Path $OutputFolder $entry.Key
    $entry.Value | Out-File -FilePath $outPath -Encoding utf8 -Force
    Write-LogMessage "Wrote $($entry.Value.Count) entries to $($entry.Key)" -Level INFO
}

# --- Create new path directories ---
foreach ($path in ($newPaths | Sort-Object -Unique)) {
    try {
        New-Item -Path $path -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    } catch {
        Write-LogMessage "Could not create directory: $($path) - $($_.Exception.Message)" -Level WARN
    }
}

Write-LogMessage "Code search complete: $($fileCounter) files scanned, $($matchCounter) matches found" -Level INFO

if ($SendNotification) {
    Send-Sms -Receiver $smsNumber -Message "CodeSearch done. $($matchCounter) matches in $($fileCounter) files."
}

# --- Helper functions ---

function Test-IsCommentLine {
    param([string]$Line, [string]$Extension)
    $ext = $Extension.ToUpper()
    $trimmed = $Line.Trim()
    switch ($ext) {
        { $_ -in '.BAT', '.CMD' } { return ($trimmed -match '^@?REM\b') }
        { $_ -in '.PS1', '.PSM1' } { return $trimmed.StartsWith('#') }
        { $_ -in '.CBL', '.DCL', '.CPY', '.CPB' } { return $trimmed.StartsWith('*') }
        '.REX' { return $trimmed.StartsWith('/*') }
        default { return $false }
    }
}

function Clean-MatchPath {
    param([string]$RawMatch, [string]$Type)
    $path = $RawMatch -replace '[\x0A\x00\x0D\x1A]', ''
    if ($Type -in 'UNC', 'DRIVE') {
        foreach ($delim in @(' ', "'", ')', '"', ',')) {
            $pos = $path.IndexOf($delim)
            if ($pos -gt 0) { $path = $path.Substring(0, $pos) }
        }
        $lastDot = $path.LastIndexOf('.')
        $lastSlash = $path.LastIndexOf('\')
        if ($lastDot -gt $lastSlash -and $lastDot -gt 0) {
            $path = $path.Substring(0, $lastSlash + 1)
        }
        $path = $path.TrimEnd('\') + '\'
    }

    if ($path.StartsWith('\\')) {
        $path = '\\' + ($path.TrimStart('\') -replace '\\{2,}', '\')
    } elseif ($path.Length -gt 2 -and $path[1] -eq ':') {
        $drive = $path.Substring(0, 2)
        $rest = $path.Substring(2) -replace '\\{2,}', '\'
        $path = $drive + $rest
    }

    return $path
}

function Convert-ToVcPath {
    param([string]$CleanPath, [string]$Type, [string]$VcPath)
    if ($Type -eq 'UNC' -and $CleanPath.StartsWith('\\') -and $CleanPath.Length -gt 2) {
        return "$($VcPath)\net\srv\" + $CleanPath.TrimStart('\')
    }
    if ($Type -eq 'DRIVE' -and $CleanPath.Length -gt 2 -and $CleanPath[1] -eq ':') {
        return "$($VcPath)\net\drv\" + $CleanPath[0] + '\' + $CleanPath.Substring(2).TrimEnd('\') + '\'
    }
    return $null
}
