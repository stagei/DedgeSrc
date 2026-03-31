<#
.SYNOPSIS
    Quickly finds project folders that contain Cursor content files.

.DESCRIPTION
    Scans for ".cursor" directories first (faster than scanning every file),
    then checks ".cursor\rules", ".cursor\commands", and ".cursor\skills".
    Returns one row per project root with typed counts and key paths.

.PARAMETER SourceRoot
    Root folder to scan. Default: $env:OptPath\src (fallback C:\opt\src).

.PARAMETER IncludeCommands
    Include ".cursor\commands\*.mdc" in counts. Default: true.

.PARAMETER IncludeSkills
    Include ".cursor\skills\**\SKILL.md" in counts. Default: true.

.PARAMETER OutputPath
    Optional path to write results (CSV when extension is .csv, otherwise JSON).

.PARAMETER RecurseDepth
    Maximum search depth for ".cursor" directories. Default: 8.

.EXAMPLE
    pwsh.exe -NoProfile -File .\Find-MdcProjects.ps1

.EXAMPLE
    pwsh.exe -NoProfile -File .\Find-MdcProjects.ps1 -OutputPath C:\temp\mdc-projects.csv
#>
[CmdletBinding()]
param(
    [string]$SourceRoot,
    [bool]$IncludeCommands = $true,
    [bool]$IncludeSkills = $true,
    [string]$OutputPath,
    [int]$RecurseDepth = 8
)

Import-Module GlobalFunctions -Force
$ErrorActionPreference = 'Stop'

if (-not $SourceRoot) {
    $optPath = $env:OptPath
    if (-not $optPath) { $optPath = 'C:\opt' }
    $SourceRoot = Join-Path $optPath 'src'
}

$SourceRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SourceRoot)
if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
    throw "SourceRoot does not exist: $SourceRoot"
}

function Write-Info {
    param([string]$Message)
    Write-LogMessage $Message -Level INFO
}

function Write-WarnMsg {
    param([string]$Message)
    Write-LogMessage $Message -Level WARN
}

Write-Info "Scanning for .cursor folders under $($SourceRoot)"

# Fast path: find ".cursor" directories, then inspect only expected subfolders.
$cursorDirs = Get-ChildItem -Path $SourceRoot -Directory -Recurse -Force -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -eq '.cursor' -and
        (($_.FullName.Substring($SourceRoot.Length).Split([System.IO.Path]::DirectorySeparatorChar, [System.StringSplitOptions]::RemoveEmptyEntries)).Count -le $RecurseDepth)
    }

$results = @()

foreach ($cursorDir in $cursorDirs) {
    $projectRoot = Split-Path -Parent $cursorDir.FullName
    $rulesDir = Join-Path $cursorDir.FullName 'rules'
    $commandsDir = Join-Path $cursorDir.FullName 'commands'
    $skillsDir = Join-Path $cursorDir.FullName 'skills'

    $rulesCount = 0
    $commandsCount = 0
    $skillsCount = 0

    if (Test-Path -LiteralPath $rulesDir -PathType Container) {
        $rulesCount = (Get-ChildItem -LiteralPath $rulesDir -Recurse -File -Filter '*.mdc' -ErrorAction SilentlyContinue | Measure-Object).Count
    }
    if ($IncludeCommands -and (Test-Path -LiteralPath $commandsDir -PathType Container)) {
        $commandsCount = (Get-ChildItem -LiteralPath $commandsDir -Recurse -File -Filter '*.mdc' -ErrorAction SilentlyContinue | Measure-Object).Count
    }
    if ($IncludeSkills -and (Test-Path -LiteralPath $skillsDir -PathType Container)) {
        $skillsCount = (Get-ChildItem -LiteralPath $skillsDir -Recurse -File -Filter 'SKILL.md' -ErrorAction SilentlyContinue | Measure-Object).Count
    }

    $total = $rulesCount + $commandsCount + $skillsCount
    if ($total -gt 0) {
        $results += [PSCustomObject]@{
            ProjectRoot   = $projectRoot
            CursorDir     = $cursorDir.FullName
            RulesMdc      = $rulesCount
            CommandsMdc   = $commandsCount
            SkillsMd      = $skillsCount
            TotalMdc      = $total
        }
    }
}

$results = $results | Sort-Object -Property ProjectRoot -Unique

if ($results.Count -eq 0) {
    Write-WarnMsg "No projects with cursor content files were found."
    return
}

Write-Info "Found $($results.Count) project(s) with cursor content files."
$results | Format-Table -AutoSize

if ($OutputPath) {
    $outPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
    $outDir = Split-Path -Parent $outPath
    if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
        New-Item -Path $outDir -ItemType Directory -Force | Out-Null
    }

    if ($outPath.ToLower().EndsWith('.csv')) {
        $results | Export-Csv -LiteralPath $outPath -NoTypeInformation -Encoding utf8
    } else {
        $results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $outPath -Encoding utf8
    }
    Write-Info "Wrote results to $($outPath)"
}
