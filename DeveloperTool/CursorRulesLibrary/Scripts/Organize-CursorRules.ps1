<#
.SYNOPSIS
    Organizes Cursor content into rules, commands, and skills folders.

.DESCRIPTION
    Scans .cursor/rules/ in all projects under $env:OptPath\src (or a specified root).
    Classifies each .mdc file as Rule, Command, or Skill.
    - Commands -> .cursor/commands/
    - Skills   -> .cursor/skills/<name>/SKILL.md
    - Rules    -> remain in .cursor/rules/

    Legacy .cursor/rules/Commands/ is treated as command input and cleaned up when empty.

.PARAMETER SourceRoot
    Root folder containing projects. Default: $env:OptPath\src (fallback C:\opt\src).

.PARAMETER ProjectName
    Process only this project (folder name under SourceRoot). Omit to process all.

.PARAMETER Preview
    Preview what would be moved without making changes.

.EXAMPLE
    pwsh.exe -File .\Organize-CursorRules.ps1 -Preview
    pwsh.exe -File .\Organize-CursorRules.ps1
    pwsh.exe -File .\Organize-CursorRules.ps1 -ProjectName AutoDocJson
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $SourceRoot,
    [string] $ProjectName,
    [switch] $Preview
)

$ErrorActionPreference = 'Stop'

if (-not $SourceRoot) {
    $optPath = $env:OptPath
    if (-not $optPath) { $optPath = 'C:\opt' }
    $SourceRoot = Join-Path $optPath 'src'
}

function Test-IsCommand {
    param([string]$FileName, [string]$Description)

    # Filename patterns
    if ($FileName -match '^command-') { return $true }
    if ($FileName -eq 'commands.mdc') { return $true }
    if ($FileName -match '^chat-command-') { return $true }

    # Description patterns - slash command triggers
    if ($Description -match 'Command\s+/') { return $true }
    if ($Description -match 'When user (says|types|writes|requests|enters)\s+/') { return $true }
    if ($Description -match 'Custom\s+(Cursor\s+)?commands') { return $true }

    # Description patterns - deploy/publish/test triggers with slash
    if ($Description -match 'When user\s+\w+\s+/(publish|deploy|test|commitAll)') { return $true }

    # Description patterns - workflow triggers (natural language command)
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
    $lines = Get-Content -LiteralPath $FilePath -TotalCount 10 -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
        if ($line -match '^\s*description:\s*(.+)$') {
            return $Matches[1].Trim().Trim('"').Trim("'")
        }
    }
    return ''
}

$useWhatIf = $Preview -or $WhatIfPreference

$projectDirs = if ($ProjectName) {
    $p = Join-Path $SourceRoot $ProjectName
    if (Test-Path $p) { @(Get-Item $p) } else { Write-Error "Project not found: $p"; return }
} else {
    Get-ChildItem -Path $SourceRoot -Directory -ErrorAction SilentlyContinue
}

$totalMoved = 0
$totalSkillsMoved = 0
$totalSkipped = 0
$totalAlreadyOrganized = 0

foreach ($proj in $projectDirs) {
    $rulesDir = Join-Path $proj.FullName '.cursor' 'rules'
    if (-not (Test-Path $rulesDir)) { continue }

    $rootMdcFiles = @(Get-ChildItem -Path $rulesDir -Filter '*.mdc' -File -ErrorAction SilentlyContinue)
    $legacyCommandsDir = Join-Path $rulesDir 'Commands'
    if (Test-Path $legacyCommandsDir) {
        $rootMdcFiles += Get-ChildItem -Path $legacyCommandsDir -Filter '*.mdc' -File -ErrorAction SilentlyContinue
    }
    if (-not $rootMdcFiles -or $rootMdcFiles.Count -eq 0) { continue }

    $commandsDir = Join-Path $proj.FullName '.cursor' 'commands'
    $skillsDir = Join-Path $proj.FullName '.cursor' 'skills'
    $commands = @()
    $skills = @()
    $rules = @()

    foreach ($file in $rootMdcFiles) {
        $desc = Get-MdcDescription -FilePath $file.FullName
        if (Test-IsSkill -FileName $file.Name) {
            $skills += [PSCustomObject]@{ File = $file; Description = $desc }
        } elseif (Test-IsCommand -FileName $file.Name -Description $desc) {
            $commands += [PSCustomObject]@{ File = $file; Description = $desc }
        } else {
            $rules += [PSCustomObject]@{ File = $file; Description = $desc }
        }
    }

    if ($commands.Count -eq 0 -and $skills.Count -eq 0) { continue }

    Write-Host "`n=== $($proj.Name) ===" -ForegroundColor Cyan
    Write-Host "  Commands: $($commands.Count)  |  Skills: $($skills.Count)  |  Rules: $($rules.Count)"

    foreach ($cmd in $commands) {
        $destPath = Join-Path $commandsDir $cmd.File.Name

        # Check if already exists in Commands/ (duplicate)
        if (Test-Path $destPath) {
            $srcHash = (Get-FileHash $cmd.File.FullName -Algorithm SHA256).Hash
            $dstHash = (Get-FileHash $destPath -Algorithm SHA256).Hash
            if ($srcHash -eq $dstHash) {
                Write-Host "  DEL (dup)  $($cmd.File.Name)" -ForegroundColor DarkYellow
                if ($PSCmdlet.ShouldProcess($cmd.File.FullName, 'Remove duplicate') -and -not $useWhatIf) {
                    Remove-Item -LiteralPath $cmd.File.FullName -Force
                }
                $totalAlreadyOrganized++
            } else {
                Write-Host "  SKIP (differs) $($cmd.File.Name) - manual merge needed" -ForegroundColor Red
                $totalSkipped++
            }
            continue
        }

        Write-Host "  MOVE $($cmd.File.Name) -> .cursor/commands/" -ForegroundColor Green
        if ($PSCmdlet.ShouldProcess($destPath, 'Move to .cursor/commands/') -and -not $useWhatIf) {
            if (-not (Test-Path $commandsDir)) {
                New-Item -Path $commandsDir -ItemType Directory -Force | Out-Null
            }
            Move-Item -LiteralPath $cmd.File.FullName -Destination $destPath -Force
        }
        $totalMoved++
    }

    foreach ($skill in $skills) {
        $skillName = [System.IO.Path]::GetFileNameWithoutExtension($skill.File.Name)
        $skillTargetDir = Join-Path $skillsDir $skillName
        $destPath = Join-Path $skillTargetDir 'SKILL.md'
        $sourceText = Get-Content -LiteralPath $skill.File.FullName -Raw -ErrorAction SilentlyContinue
        $skillText = $sourceText -replace '(?s)\A---\r?\n.*?\r?\n---\r?\n?', ''

        Write-Host "  MOVE $($skill.File.Name) -> .cursor/skills/$($skillName)/SKILL.md" -ForegroundColor Green
        if ($PSCmdlet.ShouldProcess($destPath, 'Move to .cursor/skills/') -and -not $useWhatIf) {
            if (-not (Test-Path $skillTargetDir)) {
                New-Item -Path $skillTargetDir -ItemType Directory -Force | Out-Null
            }
            Set-Content -LiteralPath $destPath -Value $skillText.TrimStart("`r", "`n") -Encoding utf8
            Remove-Item -LiteralPath $skill.File.FullName -Force
        }
        $totalSkillsMoved++
    }

    if (Test-Path $legacyCommandsDir) {
        $remaining = Get-ChildItem -Path $legacyCommandsDir -Recurse -ErrorAction SilentlyContinue
        if (-not $remaining) {
            if ($PSCmdlet.ShouldProcess($legacyCommandsDir, 'Remove empty legacy Commands folder') -and -not $useWhatIf) {
                Remove-Item -LiteralPath $legacyCommandsDir -Force
            }
        }
    }
}

Write-Host "`n--- Summary ---" -ForegroundColor White
Write-Host "Moved to .cursor/commands/: $totalMoved"
Write-Host "Moved to .cursor/skills/: $totalSkillsMoved"
Write-Host "Already organized (duplicates removed): $totalAlreadyOrganized"
Write-Host "Skipped (manual merge needed): $totalSkipped"
