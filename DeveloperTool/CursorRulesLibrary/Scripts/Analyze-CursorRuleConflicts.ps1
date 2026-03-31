<#
.SYNOPSIS
    Analyzes Cursor rules, commands, and skills across projects.

.DESCRIPTION
    Scans projects under $env:OptPath\src and inspects:
    - .cursor/rules/*.mdc
    - .cursor/commands/*.mdc
    - .cursor/skills/**/SKILL.md

    Generates a markdown report with duplicates, variants, missing metadata, and
    type-specific statistics for the new folder layout.

.PARAMETER SourceRoot
    Root folder containing projects. Default: $env:OptPath\src (fallback C:\opt\src).

.PARAMETER OutputPath
    Path for the markdown report. Default: CursorRulesLibrary\Reports\Rule-Conflict-Analysis.md

.EXAMPLE
    pwsh.exe -NoProfile -File .\Analyze-CursorRuleConflicts.ps1
#>

[CmdletBinding()]
param(
    [string] $SourceRoot,
    [string] $OutputPath
)

$ErrorActionPreference = 'Stop'

if (-not $SourceRoot) {
    $optPath = $env:OptPath
    if (-not $optPath) { $optPath = 'C:\opt' }
    $SourceRoot = Join-Path $optPath 'src'
}

if (-not $OutputPath) {
    $OutputPath = Join-Path $SourceRoot 'CursorRulesLibrary' 'Reports' 'Rule-Conflict-Analysis.md'
}

$outputDir = Split-Path $OutputPath -Parent
if (-not (Test-Path $outputDir)) {
    New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
}

function Get-MdcMetadata {
    param([string]$FilePath)
    $lines = Get-Content -LiteralPath $FilePath -TotalCount 20 -ErrorAction SilentlyContinue
    $desc = ''
    $alwaysApply = ''
    $globs = ''
    foreach ($line in $lines) {
        if ($line -match '^\s*description:\s*(.+)$') { $desc = $Matches[1].Trim().Trim('"').Trim("'") }
        if ($line -match '^\s*alwaysApply:\s*(.+)$') { $alwaysApply = $Matches[1].Trim() }
        if ($line -match '^\s*globs:\s*(.+)$') { $globs = $Matches[1].Trim() }
    }
    return @{ Description = $desc; AlwaysApply = $alwaysApply; Globs = $globs }
}

function Get-SkillMetadata {
    param([string]$FilePath)
    $lines = Get-Content -LiteralPath $FilePath -TotalCount 30 -ErrorAction SilentlyContinue
    $title = ''
    foreach ($line in $lines) {
        if ($line -match '^#\s+(.+)$') {
            $title = $Matches[1].Trim()
            break
        }
    }
    return @{ Description = $title; AlwaysApply = ''; Globs = '' }
}

$allFiles = @()
$projectDirs = Get-ChildItem -Path $SourceRoot -Directory -ErrorAction SilentlyContinue

foreach ($proj in $projectDirs) {
    $cursorDir = Join-Path $proj.FullName '.cursor'
    if (-not (Test-Path $cursorDir)) { continue }

    $rulesDir = Join-Path $cursorDir 'rules'
    if (Test-Path $rulesDir) {
        $ruleFiles = Get-ChildItem -Path $rulesDir -Filter '*.mdc' -Recurse -File -ErrorAction SilentlyContinue
        foreach ($f in $ruleFiles) {
            $meta = Get-MdcMetadata -FilePath $f.FullName
            $allFiles += [PSCustomObject]@{
                Project     = $proj.Name
                Type        = 'Rule'
                FileName    = $f.Name
                FullPath    = $f.FullName
                Hash        = (Get-FileHash $f.FullName -Algorithm SHA256).Hash
                Description = $meta.Description
                AlwaysApply = $meta.AlwaysApply
                Globs       = $meta.Globs
            }
        }
    }

    $commandsDir = Join-Path $cursorDir 'commands'
    if (Test-Path $commandsDir) {
        $commandFiles = Get-ChildItem -Path $commandsDir -Filter '*.mdc' -Recurse -File -ErrorAction SilentlyContinue
        foreach ($f in $commandFiles) {
            $meta = Get-MdcMetadata -FilePath $f.FullName
            $allFiles += [PSCustomObject]@{
                Project     = $proj.Name
                Type        = 'Command'
                FileName    = $f.Name
                FullPath    = $f.FullName
                Hash        = (Get-FileHash $f.FullName -Algorithm SHA256).Hash
                Description = $meta.Description
                AlwaysApply = $meta.AlwaysApply
                Globs       = $meta.Globs
            }
        }
    }

    $skillsDir = Join-Path $cursorDir 'skills'
    if (Test-Path $skillsDir) {
        $skillFiles = Get-ChildItem -Path $skillsDir -Filter 'SKILL.md' -Recurse -File -ErrorAction SilentlyContinue
        foreach ($f in $skillFiles) {
            $meta = Get-SkillMetadata -FilePath $f.FullName
            $allFiles += [PSCustomObject]@{
                Project     = $proj.Name
                Type        = 'Skill'
                FileName    = $f.Directory.Name
                FullPath    = $f.FullName
                Hash        = (Get-FileHash $f.FullName -Algorithm SHA256).Hash
                Description = $meta.Description
                AlwaysApply = $meta.AlwaysApply
                Globs       = $meta.Globs
            }
        }
    }
}

$groups = $allFiles | Group-Object -Property @{ Expression = { "$($_.Type)|$($_.FileName)" } }
$identicalDuplicates = @()
$contentVariants = @()
$missingDescription = @()
$alwaysApplyConflicts = @()

foreach ($g in $groups) {
    foreach ($item in $g.Group) {
        if ([string]::IsNullOrWhiteSpace($item.Description)) {
            $missingDescription += $item
        }
    }

    if ($g.Count -lt 2) { continue }

    $hashGroups = @($g.Group | Group-Object -Property Hash)
    $parts = $g.Name.Split('|', 2)
    $typeName = $parts[0]
    $fileName = $parts[1]

    if ($hashGroups.Count -eq 1) {
        $identicalDuplicates += [PSCustomObject]@{
            Type     = $typeName
            FileName = $fileName
            Count    = $g.Count
            Projects = ($g.Group | Select-Object -ExpandProperty Project) -join ', '
        }
    } else {
        $variants = foreach ($hg in $hashGroups) {
            [PSCustomObject]@{
                Hash     = $hg.Name.Substring(0, 8)
                Count    = $hg.Count
                Projects = ($hg.Group | Select-Object -ExpandProperty Project) -join ', '
            }
        }
        $contentVariants += [PSCustomObject]@{
            Type         = $typeName
            FileName     = $fileName
            TotalCount   = $g.Count
            VariantCount = $hashGroups.Count
            Variants     = $variants
        }
    }

    if ($typeName -eq 'Rule') {
        $applyValues = $g.Group | Select-Object -ExpandProperty AlwaysApply -Unique | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        if ($applyValues.Count -gt 1) {
            $alwaysApplyConflicts += [PSCustomObject]@{
                FileName = $fileName
                Values   = $applyValues -join ' vs '
                Projects = ($g.Group | ForEach-Object { "$($_.Project)=$($_.AlwaysApply)" }) -join ', '
            }
        }
    }
}

$sb = [System.Text.StringBuilder]::new()
$null = $sb.AppendLine("# Cursor Content Conflict Analysis")
$null = $sb.AppendLine("")
$null = $sb.AppendLine("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
$null = $sb.AppendLine("")
$null = $sb.AppendLine("Scanned **$($projectDirs.Count)** project directories under ``$SourceRoot``.")
$null = $sb.AppendLine("Found **$($allFiles.Count)** cursor content files across **$(($allFiles | Select-Object -ExpandProperty Project -Unique).Count)** projects.")
$null = $sb.AppendLine("")

$null = $sb.AppendLine("## Content Variants (Same Name+Type, Different Content)")
$null = $sb.AppendLine("")
if ($contentVariants.Count -eq 0) {
    $null = $sb.AppendLine("No content variants found.")
} else {
    foreach ($cv in ($contentVariants | Sort-Object Type, FileName)) {
        $null = $sb.AppendLine("### ``$($cv.Type):$($cv.FileName)`` ($($cv.TotalCount) copies, $($cv.VariantCount) variants)")
        $null = $sb.AppendLine("")
        $null = $sb.AppendLine("| Variant | Count | Projects |")
        $null = $sb.AppendLine("|---------|-------|----------|")
        foreach ($v in $cv.Variants) {
            $null = $sb.AppendLine("| $($v.Hash)... | $($v.Count) | $($v.Projects) |")
        }
        $null = $sb.AppendLine("")
    }
}

$null = $sb.AppendLine("## Identical Duplicates (Same Name+Type, Same Content)")
$null = $sb.AppendLine("")
if ($identicalDuplicates.Count -eq 0) {
    $null = $sb.AppendLine("No identical duplicates found.")
} else {
    $null = $sb.AppendLine("| Type | Name | Copies | Projects |")
    $null = $sb.AppendLine("|------|------|--------|----------|")
    foreach ($d in ($identicalDuplicates | Sort-Object -Property Count -Descending)) {
        $null = $sb.AppendLine("| $($d.Type) | ``$($d.FileName)`` | $($d.Count) | $($d.Projects) |")
    }
    $null = $sb.AppendLine("")
}

$null = $sb.AppendLine("## Missing Descriptions/Titles")
$null = $sb.AppendLine("")
if ($missingDescription.Count -eq 0) {
    $null = $sb.AppendLine("All scanned files have descriptions/titles.")
} else {
    $null = $sb.AppendLine("| Type | Name | Project |")
    $null = $sb.AppendLine("|------|------|---------|")
    foreach ($nd in ($missingDescription | Sort-Object Type, Project, FileName)) {
        $null = $sb.AppendLine("| $($nd.Type) | ``$($nd.FileName)`` | $($nd.Project) |")
    }
    $null = $sb.AppendLine("")
}

$null = $sb.AppendLine("## Rule AlwaysApply Inconsistencies")
$null = $sb.AppendLine("")
if ($alwaysApplyConflicts.Count -eq 0) {
    $null = $sb.AppendLine("No rule alwaysApply inconsistencies found.")
} else {
    $null = $sb.AppendLine("| Rule File | Values | Details |")
    $null = $sb.AppendLine("|-----------|--------|---------|")
    foreach ($ac in ($alwaysApplyConflicts | Sort-Object FileName)) {
        $null = $sb.AppendLine("| ``$($ac.FileName)`` | $($ac.Values) | $($ac.Projects) |")
    }
    $null = $sb.AppendLine("")
}

$typeStats = $allFiles | Group-Object Type | Sort-Object Name
$null = $sb.AppendLine("## Statistics")
$null = $sb.AppendLine("")
$null = $sb.AppendLine("| Metric | Count |")
$null = $sb.AppendLine("|--------|-------|")
$null = $sb.AppendLine("| Total scanned files | $($allFiles.Count) |")
$null = $sb.AppendLine("| Projects scanned (with cursor content) | $(($allFiles | Select-Object -ExpandProperty Project -Unique).Count) |")
$null = $sb.AppendLine("| Unique type+name keys | $($groups.Count) |")
foreach ($ts in $typeStats) {
    $null = $sb.AppendLine("| $($ts.Name) files | $($ts.Count) |")
}
$null = $sb.AppendLine("| Identical duplicate sets | $($identicalDuplicates.Count) |")
$null = $sb.AppendLine("| Content variant sets | $($contentVariants.Count) |")
$null = $sb.AppendLine("| Missing descriptions/titles | $($missingDescription.Count) |")
$null = $sb.AppendLine("| Rule alwaysApply conflicts | $($alwaysApplyConflicts.Count) |")

$sb.ToString() | Out-File -LiteralPath $OutputPath -Encoding utf8 -Force

Write-Host "Report written to: $OutputPath" -ForegroundColor Green
Write-Host "  Total files: $($allFiles.Count)"
Write-Host "  Identical duplicate sets: $($identicalDuplicates.Count)"
Write-Host "  Content variant sets: $($contentVariants.Count)"
Write-Host "  Missing descriptions/titles: $($missingDescription.Count)"
Write-Host "  Rule alwaysApply conflicts: $($alwaysApplyConflicts.Count)"
