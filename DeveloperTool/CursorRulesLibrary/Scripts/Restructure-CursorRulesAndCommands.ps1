<#
.SYNOPSIS
    Restructures Cursor rules and commands to the official Cursor layout.

.DESCRIPTION
    Per Cursor docs and Gemini:
    - .cursor/rules/   = Persistent rules (Always Apply, Apply Intelligently, Apply to Specific Files, Apply Manually)
    - .cursor/commands/ = Slash commands (prompt templates triggered by /name)
    - .cursor/skills/<name>/SKILL.md = Reusable project skills
    Commands must NOT live inside .cursor/rules/Commands/ — they belong in .cursor/commands/ (sibling folder).
    Skill-like .mdc files should be in .cursor/skills/<name>/SKILL.md.

    Scans all projects under $env:OptPath\src (or c:\opt\src), finds command files in .cursor/rules/
    (including rules/Commands/ subfolder from legacy layout), and moves them to .cursor/commands/.

.PARAMETER SourceRoot
    Root folder containing projects. Default: $env:OptPath\src (fallback C:\opt\src).

.PARAMETER ProjectName
    Process only this project (folder name under SourceRoot). Omit to process all.

.PARAMETER WhatIf
    Preview changes without making them.

.EXAMPLE
    pwsh.exe -File .\Restructure-CursorRulesAndCommands.ps1 -WhatIf
    pwsh.exe -File .\Restructure-CursorRulesAndCommands.ps1
    pwsh.exe -File .\Restructure-CursorRulesAndCommands.ps1 -ProjectName AutoDocJson
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $SourceRoot,
    [string] $ProjectName
)

$ErrorActionPreference = 'Stop'

if (-not $SourceRoot) {
    $optPath = $env:OptPath
    if (-not $optPath) { $optPath = 'C:\opt' }
    $SourceRoot = Join-Path $optPath 'src'
}

function Test-IsCommand {
    param([string]$FileName, [string]$Description)

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

function Test-IsSkill {
    param([string]$FileName)
    $skillNames = @(
        'autonomous-task-completion.mdc',
        'capture-learnings.mdc',
        'check-existing-rules.mdc',
        'error-investigation.mdc'
    )
    return $skillNames -contains $FileName.ToLowerInvariant()
}

function Get-MdcDescription {
    param([string]$FilePath)
    $lines = Get-Content -LiteralPath $FilePath -TotalCount 15 -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
        if ($line -match '^\s*description:\s*(.+)$') {
            return $Matches[1].Trim().Trim('"').Trim("'")
        }
    }
    return ''
}

$projectDirs = if ($ProjectName) {
    $p = Join-Path $SourceRoot $ProjectName
    if (Test-Path $p) { @(Get-Item $p) } else { Write-Error "Project not found: $p"; return }
} else {
    Get-ChildItem -Path $SourceRoot -Directory -ErrorAction SilentlyContinue
}

$totalMoved = 0
$totalSkillsMoved = 0
$totalSkipped = 0
$totalDeleted = 0
$modifiedRepos = @()

foreach ($proj in $projectDirs) {
    $rulesDir = Join-Path $proj.FullName '.cursor' 'rules'
    $commandsDir = Join-Path $proj.FullName '.cursor' 'commands'
    $skillsDir = Join-Path $proj.FullName '.cursor' 'skills'

    if (-not (Test-Path $rulesDir)) { continue }

    # Collect all .mdc and .md under .cursor/rules (including Commands subfolder)
    $allRuleFiles = Get-ChildItem -Path $rulesDir -Filter '*.mdc' -Recurse -File -ErrorAction SilentlyContinue
    $allRuleFiles += Get-ChildItem -Path $rulesDir -Filter '*.md' -Recurse -File -ErrorAction SilentlyContinue
    $allRuleFiles = $allRuleFiles | Sort-Object FullName -Unique

    if (-not $allRuleFiles -or $allRuleFiles.Count -eq 0) { continue }

    $toMove = @()
    $toSkill = @()
    foreach ($file in $allRuleFiles) {
        if (Test-IsSkill -FileName $file.Name) {
            $toSkill += $file
            continue
        }
        $desc = Get-MdcDescription -FilePath $file.FullName
        if (Test-IsCommand -FileName $file.Name -Description $desc) {
            $toMove += $file
        }
    }

    if ($toMove.Count -eq 0 -and $toSkill.Count -eq 0) { continue }

    Write-Host "`n=== $($proj.Name) ===" -ForegroundColor Cyan
    Write-Host "  Moving $($toMove.Count) command(s) to .cursor/commands/ and $($toSkill.Count) skill(s) to .cursor/skills/"

    foreach ($file in $toMove) {
        $destPath = Join-Path $commandsDir $file.Name

        if (Test-Path $destPath) {
            $srcHash = (Get-FileHash $file.FullName -Algorithm SHA256).Hash
            $dstHash = (Get-FileHash $destPath -Algorithm SHA256).Hash
            if ($srcHash -eq $dstHash) {
                Write-Host "  DEL (dup) $($file.Name)" -ForegroundColor DarkYellow
                if ($PSCmdlet.ShouldProcess($file.FullName, 'Remove duplicate')) {
                    Remove-Item -LiteralPath $file.FullName -Force
                    $totalDeleted++
                    if ($modifiedRepos -notcontains $proj.FullName) { $modifiedRepos += $proj.FullName }
                }
            } else {
                Write-Host "  SKIP (differs) $($file.Name)" -ForegroundColor Red
                $totalSkipped++
            }
            continue
        }

        Write-Host "  MOVE $($file.Name) -> .cursor/commands/" -ForegroundColor Green
        if ($PSCmdlet.ShouldProcess($destPath, 'Move to .cursor/commands/')) {
            if (-not (Test-Path $commandsDir)) {
                New-Item -Path $commandsDir -ItemType Directory -Force | Out-Null
            }
            Move-Item -LiteralPath $file.FullName -Destination $destPath -Force
            $totalMoved++
            if ($modifiedRepos -notcontains $proj.FullName) { $modifiedRepos += $proj.FullName }
        }
    }

    foreach ($file in $toSkill) {
        $skillName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $skillTargetDir = Join-Path $skillsDir $skillName
        $skillTargetPath = Join-Path $skillTargetDir 'SKILL.md'
        $sourceText = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
        $skillText = $sourceText -replace '(?s)\A---\r?\n.*?\r?\n---\r?\n?', ''

        if (Test-Path $skillTargetPath) {
            $targetText = Get-Content -LiteralPath $skillTargetPath -Raw -ErrorAction SilentlyContinue
            if ($targetText -eq $skillText.TrimStart("`r", "`n")) {
                Write-Host "  DEL (dup skill) $($file.Name)" -ForegroundColor DarkYellow
                if ($PSCmdlet.ShouldProcess($file.FullName, 'Remove duplicate skill source')) {
                    Remove-Item -LiteralPath $file.FullName -Force
                    $totalDeleted++
                    if ($modifiedRepos -notcontains $proj.FullName) { $modifiedRepos += $proj.FullName }
                }
            } else {
                Write-Host "  SKIP (skill differs) $($file.Name)" -ForegroundColor Red
                $totalSkipped++
            }
            continue
        }

        Write-Host "  MOVE $($file.Name) -> .cursor/skills/$($skillName)/SKILL.md" -ForegroundColor Green
        if ($PSCmdlet.ShouldProcess($skillTargetPath, 'Move to .cursor/skills/')) {
            if (-not (Test-Path $skillTargetDir)) {
                New-Item -Path $skillTargetDir -ItemType Directory -Force | Out-Null
            }
            Set-Content -LiteralPath $skillTargetPath -Value $skillText.TrimStart("`r", "`n") -Encoding utf8
            Remove-Item -LiteralPath $file.FullName -Force
            $totalSkillsMoved++
            if ($modifiedRepos -notcontains $proj.FullName) { $modifiedRepos += $proj.FullName }
        }
    }

    # Remove empty .cursor/rules/Commands/ folder
    $legacyCommandsFolder = Join-Path $rulesDir 'Commands'
    if (Test-Path $legacyCommandsFolder) {
        $remaining = Get-ChildItem -Path $legacyCommandsFolder -Recurse -ErrorAction SilentlyContinue
        if (-not $remaining -or $remaining.Count -eq 0) {
            Write-Host "  REMOVE empty .cursor/rules/Commands/" -ForegroundColor DarkGray
            if ($PSCmdlet.ShouldProcess($legacyCommandsFolder, 'Remove directory')) {
                Remove-Item -LiteralPath $legacyCommandsFolder -Force
                if ($modifiedRepos -notcontains $proj.FullName) { $modifiedRepos += $proj.FullName }
            }
        }
    }
}

Write-Host "`n--- Summary ---" -ForegroundColor White
Write-Host "Moved to .cursor/commands/: $totalMoved"
Write-Host "Moved to .cursor/skills/: $totalSkillsMoved"
Write-Host "Duplicates removed: $totalDeleted"
Write-Host "Skipped (manual merge): $totalSkipped"
Write-Host "`nCorrect structure:"
Write-Host "  .cursor/rules/     = rules only (behavior, patterns, constraints)"
Write-Host "  .cursor/commands/ = slash commands only (/fix, /commit, etc.)"
Write-Host "  .cursor/skills/   = reusable project skills"

# Git add, commit, push for projects with changes (skip when -WhatIf)
if (-not $WhatIfPreference -and $modifiedRepos.Count -gt 0) {
    Write-Host "`n--- Git ---" -ForegroundColor White
    foreach ($repoPath in $modifiedRepos) {
        $gitDir = Join-Path $repoPath '.git'
        if (-not (Test-Path $gitDir)) {
            Write-Host "  [SKIP] $($repoPath | Split-Path -Leaf): not a git repo"
            continue
        }
        Push-Location $repoPath
        try {
            $status = git status --porcelain
            if ($LASTEXITCODE -ne 0) {
                throw "git status failed"
            }
            if (-not $status) {
                Write-Host "  [SKIP] $($repoPath | Split-Path -Leaf): no changes"
                continue
            }

            # Stage only the folders this script modifies, to avoid accidentally adding nested repos.
            git add -A -- '.cursor/rules' '.cursor/commands' '.cursor/skills'
            if ($LASTEXITCODE -ne 0) {
                throw "git add failed"
            }

            $staged = git diff --cached --name-only
            if ($LASTEXITCODE -ne 0) {
                throw "git diff --cached failed"
            }
            if (-not $staged) {
                Write-Host "  [SKIP] $($repoPath | Split-Path -Leaf): no staged .cursor changes"
                continue
            }

            git commit -m "Restructure: move cursor content into rules, commands, and skills folders"
            if ($LASTEXITCODE -ne 0) {
                throw "git commit failed"
            }

            $upstream = git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null
            $hasUpstream = ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($upstream))
            if ($hasUpstream) {
                git push
                if ($LASTEXITCODE -ne 0) {
                    throw "git push failed"
                }
            } else {
                $branch = git rev-parse --abbrev-ref HEAD
                if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) {
                    throw "Unable to determine current branch for push"
                }
                $hasOrigin = @(git remote) -contains 'origin'
                if (-not $hasOrigin) {
                    Write-Host "  [WARN] $($repoPath | Split-Path -Leaf): committed locally (no origin remote for push)" -ForegroundColor Yellow
                    continue
                }
                git push -u origin $branch
                if ($LASTEXITCODE -ne 0) {
                    throw "git push -u origin $($branch) failed"
                }
            }

            Write-Host "  [OK] $($repoPath | Split-Path -Leaf): committed and pushed"
        } catch {
            Write-Host "  [ERR] $($repoPath | Split-Path -Leaf): $_" -ForegroundColor Red
        } finally {
            Pop-Location
        }
    }
}
