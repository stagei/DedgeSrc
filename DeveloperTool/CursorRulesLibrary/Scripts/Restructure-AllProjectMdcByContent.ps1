<#
.SYNOPSIS
    Restructures all project .mdc files into .cursor/rules, .cursor/commands, and .cursor/skills.

.DESCRIPTION
    Scans each project folder under SourceRoot for *.mdc recursively and moves files into the
    modern Cursor layout based on Library filename matches first, then content heuristics.

    Classification order:
    1) Filename exists in Library/Commands -> command
    2) Filename exists in Library/Skills   -> skill
    3) Filename exists in other Library folders -> rule
    4) Heuristic from file content/name -> command/skill/rule

    Destination paths:
    - Rule:    <project>\.cursor\rules\<file>.mdc
    - Command: <project>\.cursor\commands\<file>.mdc
    - Skill:   <project>\.cursor\skills\<name>\SKILL.md (converted from .mdc body)

    If destination exists and differs, file is not overwritten unless -ForceOverwrite is used.
    Conflicts and unresolved items are written to a report.

.PARAMETER SourceRoot
    Root folder containing projects. Default: $env:OptPath\src (fallback C:\opt\src).

.PARAMETER LibraryRoot
    Library root path. Default: <this repo>\Library.

.PARAMETER ProjectName
    Optional single project folder name under SourceRoot.

.PARAMETER ForceOverwrite
    Overwrite destination files when content differs.

.PARAMETER ReportPath
    Optional report output path. Default: CursorRulesLibrary\Reports\Restructure-AllProjectMdcByContent.md

.EXAMPLE
    pwsh.exe -NoProfile -File .\Restructure-AllProjectMdcByContent.ps1 -WhatIf

.EXAMPLE
    pwsh.exe -NoProfile -File .\Restructure-AllProjectMdcByContent.ps1
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $SourceRoot,
    [string] $LibraryRoot,
    [string] $ProjectName,
    [switch] $ForceOverwrite,
    [string] $ReportPath
)

$ErrorActionPreference = 'Stop'

function Write-Log {
    param(
        [string] $Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string] $Level = 'INFO'
    )

    try {
        $null = Get-Command Write-LogMessage -ErrorAction Stop
        Write-LogMessage $Message -Level $Level
    } catch {
        if ($Level -eq 'ERROR') {
            Write-Host $Message -ForegroundColor Red
        } elseif ($Level -eq 'WARN') {
            Write-Host $Message -ForegroundColor Yellow
        } elseif ($Level -eq 'DEBUG') {
            Write-Host $Message -ForegroundColor DarkGray
        } else {
            Write-Host $Message
        }
    }
}

function Get-StringHash {
    param([string] $Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '')
    } finally {
        $sha.Dispose()
    }
}

function Get-MdcDescription {
    param([string] $FilePath)
    $lines = Get-Content -LiteralPath $FilePath -TotalCount 20 -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
        if ($line -match '^\s*description:\s*(.+)$') {
            return $Matches[1].Trim().Trim('"').Trim("'")
        }
    }
    return ''
}

function Test-IsCommand {
    param([string] $FileName, [string] $Description)

    if ($FileName -match '^command-') { return $true }
    if ($FileName -eq 'commands.mdc' -or $FileName -eq 'commands.md') { return $true }
    if ($FileName -match '^chat-command-') { return $true }

    if ($Description -match 'Command\s+/') { return $true }
    if ($Description -match 'When user (says|types|writes|requests|enters)\s+/') { return $true }
    if ($Description -match 'Custom\s+(Cursor\s+)?commands') { return $true }
    if ($Description -match 'When user\s+\w+\s+/(publish|deploy|test|commitAll)') { return $true }
    if ($Description -match '^When user\s+(asks|says|types|writes)' -and $Description -match '\brun\b') { return $true }

    return $false
}

function Test-IsSkillHeuristic {
    param([string] $FilePath, [string] $FileName, [string] $Description)

    $knownSkillNames = @(
        'autonomous-task-completion.mdc',
        'capture-learnings.mdc',
        'check-existing-rules.mdc',
        'error-investigation.mdc'
    )
    if ($knownSkillNames -contains $FileName.ToLowerInvariant()) { return $true }

    $content = Get-Content -LiteralPath $FilePath -Raw -ErrorAction SilentlyContinue
    if (-not $content) { return $false }
    if ($content -match '(?i)\bcore principle\b' -and $content -match '(?i)\bwhat this means in practice\b') { return $true }
    if ($content -match '(?i)\bwhen to capture\b' -and $content -match '(?i)\brules for the rules\b') { return $true }
    if ($Description -match '(?i)\bprotocol\b|\balways search\b|\bautonomous task\b') { return $true }

    return $false
}

function Convert-MdcToSkillMarkdown {
    param([string] $SourceFile)
    $text = Get-Content -LiteralPath $SourceFile -Raw -ErrorAction Stop
    $withoutFrontmatter = $text -replace '(?s)\A---\r?\n.*?\r?\n---\r?\n?', ''
    return $withoutFrontmatter.TrimStart("`r", "`n")
}

function Add-TouchedPath {
    param(
        [string] $RepoRoot,
        [string] $FullPath,
        [hashtable] $RepoTouchedPaths
    )
    if (-not $RepoTouchedPaths.ContainsKey($RepoRoot)) {
        $RepoTouchedPaths[$RepoRoot] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }
    if ($FullPath.StartsWith($RepoRoot, [StringComparison]::OrdinalIgnoreCase)) {
        $relative = $FullPath.Substring($RepoRoot.Length).TrimStart('\', '/')
        if (-not [string]::IsNullOrWhiteSpace($relative)) {
            $null = $RepoTouchedPaths[$RepoRoot].Add($relative)
        }
    }
}

if (-not $SourceRoot) {
    $optPath = $env:OptPath
    if (-not $optPath) { $optPath = 'C:\opt' }
    $SourceRoot = Join-Path $optPath 'src'
}
$SourceRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SourceRoot)

if (-not $LibraryRoot) {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $LibraryRoot = Join-Path $repoRoot 'Library'
}
$LibraryRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LibraryRoot)

if (-not $ReportPath) {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $ReportPath = Join-Path $repoRoot 'Reports' 'Restructure-AllProjectMdcByContent.md'
}
$ReportPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReportPath)
$reportDir = Split-Path -Parent $ReportPath
if (-not (Test-Path -LiteralPath $reportDir)) {
    New-Item -Path $reportDir -ItemType Directory -Force | Out-Null
}

if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
    throw "Source root does not exist: $($SourceRoot)"
}
if (-not (Test-Path -LiteralPath $LibraryRoot -PathType Container)) {
    throw "Library root does not exist: $($LibraryRoot)"
}

$commandsLibraryDir = Join-Path $LibraryRoot 'Commands'
$skillsLibraryDir = Join-Path $LibraryRoot 'Skills'

$libraryCommandNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$librarySkillNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$libraryRuleNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

if (Test-Path -LiteralPath $commandsLibraryDir) {
    Get-ChildItem -Path $commandsLibraryDir -File -Filter '*.mdc' -ErrorAction SilentlyContinue | ForEach-Object {
        $null = $libraryCommandNames.Add($_.Name)
    }
}
if (Test-Path -LiteralPath $skillsLibraryDir) {
    Get-ChildItem -Path $skillsLibraryDir -File -Filter '*.mdc' -ErrorAction SilentlyContinue | ForEach-Object {
        $null = $librarySkillNames.Add($_.Name)
    }
}
Get-ChildItem -Path $LibraryRoot -Recurse -File -Filter '*.mdc' -ErrorAction SilentlyContinue | Where-Object {
    -not $_.FullName.StartsWith($commandsLibraryDir, [StringComparison]::OrdinalIgnoreCase) -and
    -not $_.FullName.StartsWith($skillsLibraryDir, [StringComparison]::OrdinalIgnoreCase)
} | ForEach-Object {
    $null = $libraryRuleNames.Add($_.Name)
}

$projects = if ($ProjectName) {
    $singleProject = Join-Path $SourceRoot $ProjectName
    if (-not (Test-Path -LiteralPath $singleProject -PathType Container)) {
        throw "Project not found: $($singleProject)"
    }
    @(Get-Item -LiteralPath $singleProject)
} else {
    Get-ChildItem -Path $SourceRoot -Directory -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq '.cursor' } |
        ForEach-Object { Get-Item -LiteralPath (Split-Path -Parent $_.FullName) } |
        Sort-Object -Property FullName -Unique
}

$stats = [ordered]@{
    ProjectsScanned     = 0
    ProjectsWithMdc     = 0
    RulesMoved          = 0
    CommandsMoved       = 0
    SkillsMoved         = 0
    SourceDuplicatesDel = 0
    SkippedSamePlace    = 0
    Conflicts           = 0
}

$conflicts = [System.Collections.Generic.List[object]]::new()
$manualReview = [System.Collections.Generic.List[object]]::new()
$modifiedRepos = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$repoTouchedPaths = @{}

foreach ($project in $projects) {
    if ($project.Name -eq 'CursorRulesLibrary') { continue }
    $stats.ProjectsScanned++

    $projectPrefix = $project.FullName.TrimEnd('\') + '\'
    $childProjectRoots = @($projects | Where-Object {
            $_.FullName -ne $project.FullName -and $_.FullName.StartsWith($projectPrefix, [StringComparison]::OrdinalIgnoreCase)
        } | Select-Object -ExpandProperty FullName)

    $allMdc = Get-ChildItem -Path $project.FullName -Recurse -File -Filter '*.mdc' -ErrorAction SilentlyContinue | Where-Object {
        $file = $_
        if ($file.FullName -match '[\\/]\.git[\\/]' -or $file.FullName -match '[\\/]node_modules[\\/]' -or $file.FullName -match '[\\/]_AllFoundRules[\\/]') {
            return $false
        }
        foreach ($childRoot in $childProjectRoots) {
            $childPrefix = $childRoot.TrimEnd('\') + '\'
            if ($file.FullName.StartsWith($childPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                return $false
            }
        }
        return $true
    }
    if (-not $allMdc) { continue }

    $stats.ProjectsWithMdc++
    $cursorDir = Join-Path $project.FullName '.cursor'
    $rulesDir = Join-Path $cursorDir 'rules'
    $commandsDir = Join-Path $cursorDir 'commands'
    $skillsDir = Join-Path $cursorDir 'skills'
    Write-Log "`n=== $($project.Name) ===" -Level INFO

    foreach ($file in $allMdc) {
        $desc = Get-MdcDescription -FilePath $file.FullName
        $type = 'rule'
        $reason = 'heuristic-default'

        if ($libraryCommandNames.Contains($file.Name)) {
            $type = 'command'
            $reason = 'library-command-filename'
        } elseif ($librarySkillNames.Contains($file.Name)) {
            $type = 'skill'
            $reason = 'library-skill-filename'
        } elseif ($libraryRuleNames.Contains($file.Name)) {
            $type = 'rule'
            $reason = 'library-rule-filename'
        } elseif (Test-IsCommand -FileName $file.Name -Description $desc) {
            $type = 'command'
            $reason = 'content-command'
        } elseif (Test-IsSkillHeuristic -FilePath $file.FullName -FileName $file.Name -Description $desc) {
            $type = 'skill'
            $reason = 'content-skill'
        } else {
            $manualReview.Add([PSCustomObject]@{
                Project = $project.Name
                File    = $file.FullName
                Reason  = 'Unknown pattern treated as rule'
            }) | Out-Null
        }

        $targetPath = ''
        if ($type -eq 'command') {
            $targetPath = Join-Path $commandsDir $file.Name
        } elseif ($type -eq 'rule') {
            $targetPath = Join-Path $rulesDir $file.Name
        } else {
            $skillName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            $targetPath = Join-Path (Join-Path $skillsDir $skillName) 'SKILL.md'
        }

        if ($file.FullName -ieq $targetPath) {
            $stats.SkippedSamePlace++
            continue
        }

        $targetExists = Test-Path -LiteralPath $targetPath
        $sameContent = $false

        if ($type -eq 'skill') {
            $converted = Convert-MdcToSkillMarkdown -SourceFile $file.FullName
            if ($targetExists) {
                $targetText = Get-Content -LiteralPath $targetPath -Raw -ErrorAction SilentlyContinue
                $sameContent = (Get-StringHash -Text $converted) -eq (Get-StringHash -Text $targetText)
            }

            if ($targetExists -and -not $sameContent -and -not $ForceOverwrite) {
                $stats.Conflicts++
                $conflicts.Add([PSCustomObject]@{
                    Project = $project.Name
                    Type    = 'Skill'
                    Source  = $file.FullName
                    Target  = $targetPath
                    Reason  = $reason
                }) | Out-Null
                continue
            }

            if ($targetExists -and $sameContent) {
                if ($PSCmdlet.ShouldProcess($file.FullName, 'Remove duplicate source after matching target')) {
                    Remove-Item -LiteralPath $file.FullName -Force
                    $null = $modifiedRepos.Add($project.FullName)
                    Add-TouchedPath -RepoRoot $project.FullName -FullPath $file.FullName -RepoTouchedPaths $repoTouchedPaths
                }
                $stats.SourceDuplicatesDel++
                continue
            }

            if ($PSCmdlet.ShouldProcess($targetPath, "Move as skill ($($reason))")) {
                $targetDir = Split-Path -Parent $targetPath
                if (-not (Test-Path -LiteralPath $targetDir)) {
                    New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
                }
                Set-Content -LiteralPath $targetPath -Value $converted -Encoding utf8
                Remove-Item -LiteralPath $file.FullName -Force
                $null = $modifiedRepos.Add($project.FullName)
                Add-TouchedPath -RepoRoot $project.FullName -FullPath $targetPath -RepoTouchedPaths $repoTouchedPaths
                Add-TouchedPath -RepoRoot $project.FullName -FullPath $file.FullName -RepoTouchedPaths $repoTouchedPaths
            }
            $stats.SkillsMoved++
            continue
        }

        if ($targetExists) {
            $sameContent = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash
            if ($sameContent) {
                if ($PSCmdlet.ShouldProcess($file.FullName, 'Remove duplicate source after matching target')) {
                    Remove-Item -LiteralPath $file.FullName -Force
                    $null = $modifiedRepos.Add($project.FullName)
                    Add-TouchedPath -RepoRoot $project.FullName -FullPath $file.FullName -RepoTouchedPaths $repoTouchedPaths
                }
                $stats.SourceDuplicatesDel++
                continue
            }
            if (-not $ForceOverwrite) {
                $stats.Conflicts++
                $conflicts.Add([PSCustomObject]@{
                    Project = $project.Name
                    Type    = (Get-Culture).TextInfo.ToTitleCase($type)
                    Source  = $file.FullName
                    Target  = $targetPath
                    Reason  = $reason
                }) | Out-Null
                continue
            }
        }

        if ($PSCmdlet.ShouldProcess($targetPath, "Move as $($type) ($($reason))")) {
            $targetDir = Split-Path -Parent $targetPath
            if (-not (Test-Path -LiteralPath $targetDir)) {
                New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
            }
            Move-Item -LiteralPath $file.FullName -Destination $targetPath -Force
            $null = $modifiedRepos.Add($project.FullName)
            Add-TouchedPath -RepoRoot $project.FullName -FullPath $targetPath -RepoTouchedPaths $repoTouchedPaths
            Add-TouchedPath -RepoRoot $project.FullName -FullPath $file.FullName -RepoTouchedPaths $repoTouchedPaths
        }

        if ($type -eq 'command') {
            $stats.CommandsMoved++
        } else {
            $stats.RulesMoved++
        }
    }
}

$report = [System.Text.StringBuilder]::new()
$null = $report.AppendLine("# Restructure All Project MDC By Content")
$null = $report.AppendLine("")
$null = $report.AppendLine("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$null = $report.AppendLine("")
$null = $report.AppendLine("## Summary")
$null = $report.AppendLine("")
$null = $report.AppendLine("| Metric | Count |")
$null = $report.AppendLine("|--------|-------|")
foreach ($key in $stats.Keys) {
    $null = $report.AppendLine("| $($key) | $($stats[$key]) |")
}

$null = $report.AppendLine("")
$null = $report.AppendLine("## Conflicts (manual merge needed)")
$null = $report.AppendLine("")
if ($conflicts.Count -eq 0) {
    $null = $report.AppendLine("None.")
} else {
    $null = $report.AppendLine("| Project | Type | Source | Target | Reason |")
    $null = $report.AppendLine("|---------|------|--------|--------|--------|")
    foreach ($c in $conflicts) {
        $null = $report.AppendLine("| $($c.Project) | $($c.Type) | ``$($c.Source)`` | ``$($c.Target)`` | $($c.Reason) |")
    }
}

$null = $report.AppendLine("")
$null = $report.AppendLine("## Manually Reviewed-As-Rule Candidates")
$null = $report.AppendLine("")
if ($manualReview.Count -eq 0) {
    $null = $report.AppendLine("None.")
} else {
    $null = $report.AppendLine("| Project | File | Reason |")
    $null = $report.AppendLine("|---------|------|--------|")
    foreach ($m in $manualReview) {
        $null = $report.AppendLine("| $($m.Project) | ``$($m.File)`` | $($m.Reason) |")
    }
}

if ($PSCmdlet.ShouldProcess($ReportPath, 'Write report')) {
    Set-Content -LiteralPath $ReportPath -Value $report.ToString() -Encoding utf8
}

Write-Log "`n--- Summary ---" -Level INFO
foreach ($key in $stats.Keys) {
    Write-Log "$($key): $($stats[$key])" -Level INFO
}
Write-Log "Report: $($ReportPath)" -Level INFO

# Auto git add/commit/push for repos modified by this run (skip on -WhatIf)
if (-not $WhatIfPreference -and $modifiedRepos.Count -gt 0) {
    Write-Log "`n--- Git ---" -Level INFO
    foreach ($repoPath in $modifiedRepos) {
        $gitDir = Join-Path $repoPath '.git'
        if (-not (Test-Path -LiteralPath $gitDir)) {
            Write-Log "[SKIP] $($repoPath | Split-Path -Leaf): not a git repo" -Level WARN
            continue
        }

        Push-Location $repoPath
        try {
            $status = git status --porcelain
            if ($LASTEXITCODE -ne 0) { throw 'git status failed' }
            if (-not $status) {
                Write-Log "[SKIP] $($repoPath | Split-Path -Leaf): no changes" -Level INFO
                continue
            }

            $touched = @()
            if ($repoTouchedPaths.ContainsKey($repoPath)) {
                $touched = @($repoTouchedPaths[$repoPath])
            }
            if ($touched.Count -gt 0) {
                & git add -A -- @($touched)
            } else {
                git add -A -- '.cursor/rules' '.cursor/commands' '.cursor/skills'
            }
            if ($LASTEXITCODE -ne 0) { throw 'git add failed' }

            $staged = git diff --cached --name-only
            if ($LASTEXITCODE -ne 0) { throw 'git diff --cached failed' }
            if (-not $staged) {
                Write-Log "[SKIP] $($repoPath | Split-Path -Leaf): no staged changes" -Level INFO
                continue
            }

            git commit -m "Restructure cursor content into rules, commands, and skills"
            if ($LASTEXITCODE -ne 0) { throw 'git commit failed' }

            $upstream = git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null
            $hasUpstream = ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($upstream))
            if ($hasUpstream) {
                git push
                if ($LASTEXITCODE -ne 0) { throw 'git push failed' }
            } else {
                $branch = git rev-parse --abbrev-ref HEAD
                if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) {
                    throw 'Unable to determine current branch for push'
                }
                $hasOrigin = @(git remote) -contains 'origin'
                if (-not $hasOrigin) {
                    Write-Log "[WARN] $($repoPath | Split-Path -Leaf): committed locally (no origin remote)" -Level WARN
                    continue
                }
                git push -u origin $branch
                if ($LASTEXITCODE -ne 0) { throw "git push -u origin $($branch) failed" }
            }

            Write-Log "[OK] $($repoPath | Split-Path -Leaf): committed and pushed" -Level INFO
        } catch {
            Write-Log "[ERR] $($repoPath | Split-Path -Leaf): $_" -Level ERROR
        } finally {
            Pop-Location
        }
    }
}
