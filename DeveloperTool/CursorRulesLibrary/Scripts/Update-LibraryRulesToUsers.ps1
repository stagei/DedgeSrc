<#
.SYNOPSIS
    Syncs typed Library content into project Cursor rules, commands, and skills.

.DESCRIPTION
    Exports content from CursorRulesLibrary\Library to user projects under SourceRoot:
    - Rules from Library\<Theme>\*.mdc      -> .cursor\rules\
    - Commands from Library\Commands\*.mdc  -> .cursor\commands\
    - Skills from Library\Skills\*.mdc      -> .cursor\skills\<name>\SKILL.md

    Rule sync is pattern-based:
    - Always include Agent, Git, Documentation, Security when present.
    - Add themes from project technology signals (C#, WebApp, WPF, Db2, Logging, etc.).

    Existing files are handled safely:
    - same content: skip
    - different content: report DIFFERS (or overwrite with -ForceOverwrite)

.PARAMETER SourceRoot
    Root folder containing user projects. Default: $env:OptPath\src (fallback C:\opt\src).

.PARAMETER LibraryRoot
    Path to the Library folder. Default: <this repo>\Library

.PARAMETER ProjectName
    Optional single project folder name under SourceRoot to process.

.PARAMETER SkipCommands
    Skip command export from Library\Commands.

.PARAMETER SkipSkills
    Skip skill export from Library\Skills.

.PARAMETER ForceOverwrite
    Overwrite target files when content differs.

.EXAMPLE
    pwsh.exe -NoProfile -File .\Update-LibraryRulesToUsers.ps1 -WhatIf

.EXAMPLE
    pwsh.exe -NoProfile -File .\Update-LibraryRulesToUsers.ps1 -ProjectName AutoDocJson
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $SourceRoot,
    [string] $LibraryRoot,
    [string] $ProjectName,
    [switch] $SkipCommands,
    [switch] $SkipSkills,
    [switch] $ForceOverwrite
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
    param([string]$FilePath)
    $lines = Get-Content -LiteralPath $FilePath -TotalCount 15 -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
        if ($line -match '^\s*description:\s*(.+)$') {
            return $Matches[1].Trim().Trim('"').Trim("'")
        }
    }
    return ''
}

function Convert-MdcToSkillMarkdown {
    param([string] $SourceFile)
    $text = Get-Content -LiteralPath $SourceFile -Raw -ErrorAction Stop
    $withoutFrontmatter = $text -replace '(?s)\A---\r?\n.*?\r?\n---\r?\n?', ''
    return $withoutFrontmatter.TrimStart("`r", "`n")
}

function Test-ProjectContains {
    param(
        [string] $ProjectRoot,
        [string] $Pattern
    )
    return [bool](Get-ChildItem -Path $ProjectRoot -Recurse -File -Filter $Pattern -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Test-ProjectContainsText {
    param(
        [string] $ProjectRoot,
        [string] $Glob,
        [string] $Pattern
    )
    $files = Get-ChildItem -Path $ProjectRoot -Recurse -File -Filter $Glob -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        if (Select-String -Path $f.FullName -Pattern $Pattern -Quiet -SimpleMatch -ErrorAction SilentlyContinue) {
            return $true
        }
    }
    return $false
}

function Get-ProjectThemes {
    param([string] $ProjectRoot, [string[]] $AvailableThemes)

    $themes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($baseTheme in @('Agent', 'Git', 'Documentation', 'Security')) {
        if ($AvailableThemes -contains $baseTheme) { $null = $themes.Add($baseTheme) }
    }

    $csprojFiles = Get-ChildItem -Path $ProjectRoot -Recurse -File -Filter '*.csproj' -ErrorAction SilentlyContinue
    if ($csprojFiles) {
        if ($AvailableThemes -contains 'CSharp-WinApp') { $null = $themes.Add('CSharp-WinApp') }
        foreach ($csproj in $csprojFiles) {
            $content = Get-Content -LiteralPath $csproj.FullName -Raw -ErrorAction SilentlyContinue
            if (-not $content) { continue }
            if ($content.Contains('Microsoft.AspNetCore') -and $AvailableThemes -contains 'CSharp-WebApp') {
                $null = $themes.Add('CSharp-WebApp')
            }
            if ($content.Contains('<UseWPF>true') -and $AvailableThemes -contains 'WPF') {
                $null = $themes.Add('WPF')
            }
            if (($content.Contains('IBM.Data.Db2') -or $content.Contains('Net.IBM.Data.Db2')) -and $AvailableThemes -contains 'Db2') {
                $null = $themes.Add('Db2')
            }
            if (($content.Contains('NLog') -or $content.Contains('Serilog')) -and $AvailableThemes -contains 'Logging') {
                $null = $themes.Add('Logging')
            }
            if ($content.Contains('DedgeAuth') -and $AvailableThemes -contains 'DedgeAuth') {
                $null = $themes.Add('DedgeAuth')
            }
        }
    }

    if (Test-ProjectContains -ProjectRoot $ProjectRoot -Pattern '*.ps1' -and $AvailableThemes -contains 'PowerShell') {
        $null = $themes.Add('PowerShell')
    }
    if (((Test-ProjectContains -ProjectRoot $ProjectRoot -Pattern '*.wxs') -or (Test-ProjectContains -ProjectRoot $ProjectRoot -Pattern '*.wixproj')) -and $AvailableThemes -contains 'Installer') {
        $null = $themes.Add('Installer')
    }
    if (((Test-ProjectContains -ProjectRoot $ProjectRoot -Pattern '*.html') -or (Test-ProjectContains -ProjectRoot $ProjectRoot -Pattern '*.css') -or (Test-ProjectContains -ProjectRoot $ProjectRoot -Pattern '*.js')) -and $AvailableThemes -contains 'Web-UI') {
        $null = $themes.Add('Web-UI')
    }
    if (((Test-ProjectContains -ProjectRoot $ProjectRoot -Pattern '*Tests.csproj') -or (Test-ProjectContains -ProjectRoot $ProjectRoot -Pattern '*Test*.csproj')) -and $AvailableThemes -contains 'Testing') {
        $null = $themes.Add('Testing')
    }
    if ($AvailableThemes -contains 'Server' -and ((Test-ProjectContainsText -ProjectRoot $ProjectRoot -Glob '*.ps1' -Pattern '\\') -or (Test-ProjectContainsText -ProjectRoot $ProjectRoot -Glob '*.cs' -Pattern '\\'))) {
        $null = $themes.Add('Server')
    }

    return @($themes | Sort-Object)
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

if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
    throw "Source root does not exist: $($SourceRoot)"
}
if (-not (Test-Path -LiteralPath $LibraryRoot -PathType Container)) {
    throw "Library root does not exist: $($LibraryRoot)"
}

$commandsLibraryDir = Join-Path $LibraryRoot 'Commands'
$skillsLibraryDir = Join-Path $LibraryRoot 'Skills'
$themeDirs = Get-ChildItem -Path $LibraryRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notin @('Commands', 'Skills') }
$availableThemes = @($themeDirs | Select-Object -ExpandProperty Name)

$ruleFilesByTheme = @{}
foreach ($themeDir in $themeDirs) {
    $ruleFilesByTheme[$themeDir.Name] = @(Get-ChildItem -Path $themeDir.FullName -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in '.mdc', '.md' })
}

$libraryCommandFiles = @()
if (-not $SkipCommands -and (Test-Path -LiteralPath $commandsLibraryDir -PathType Container)) {
    $libraryCommandFiles = @(Get-ChildItem -Path $commandsLibraryDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in '.mdc', '.md' })
}

$librarySkillFiles = @()
if (-not $SkipSkills -and (Test-Path -LiteralPath $skillsLibraryDir -PathType Container)) {
    $librarySkillFiles = @(Get-ChildItem -Path $skillsLibraryDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in '.mdc', '.md' })
}

$projects = if ($ProjectName) {
    $singleProjectPath = Join-Path $SourceRoot $ProjectName
    if (-not (Test-Path -LiteralPath $singleProjectPath -PathType Container)) {
        throw "Project not found: $($singleProjectPath)"
    }
    @(Get-Item -LiteralPath $singleProjectPath)
} else {
    Get-ChildItem -Path $SourceRoot -Directory -ErrorAction SilentlyContinue
}

$processedProjects = 0
$skippedProjects = 0

$stats = [ordered]@{
    RulesAdded      = 0
    RulesUpdated    = 0
    RulesSkipped    = 0
    RulesDiffers    = 0
    CommandsAdded   = 0
    CommandsUpdated = 0
    CommandsSkipped = 0
    CommandsDiffers = 0
    SkillsAdded     = 0
    SkillsUpdated   = 0
    SkillsSkipped   = 0
    SkillsDiffers   = 0
}

foreach ($project in $projects) {
    if ($project.Name -eq 'CursorRulesLibrary') { continue }

    $cursorDir = Join-Path $project.FullName '.cursor'
    if (-not (Test-Path -LiteralPath $cursorDir -PathType Container)) {
        $skippedProjects++
        continue
    }

    $projectRuleDir = Join-Path $cursorDir 'rules'
    $projectCommandDir = Join-Path $cursorDir 'commands'
    $projectSkillsDir = Join-Path $cursorDir 'skills'
    $processedProjects++

    $themes = Get-ProjectThemes -ProjectRoot $project.FullName -AvailableThemes $availableThemes
    Write-Log "`n=== $($project.Name) ===" -Level INFO
    Write-Log "Themes: $($themes -join ', ')" -Level DEBUG

    foreach ($theme in $themes) {
        $sourceFiles = @($ruleFilesByTheme[$theme])
        foreach ($sourceFile in $sourceFiles) {
            $targetPath = Join-Path $projectRuleDir $sourceFile.Name
            $targetExists = Test-Path -LiteralPath $targetPath
            $isSame = $false
            if ($targetExists) {
                $isSame = (Get-FileHash -LiteralPath $sourceFile.FullName -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash
            }
            if ($targetExists -and $isSame) {
                $stats.RulesSkipped++
                continue
            }
            if ($targetExists -and -not $isSame -and -not $ForceOverwrite) {
                Write-Log "DIFFERS rule: $($project.Name)\$($sourceFile.Name)" -Level WARN
                $stats.RulesDiffers++
                continue
            }

            if ($PSCmdlet.ShouldProcess($targetPath, 'Sync rule from Library')) {
                if (-not (Test-Path -LiteralPath $projectRuleDir -PathType Container)) {
                    New-Item -Path $projectRuleDir -ItemType Directory -Force | Out-Null
                }
                Copy-Item -LiteralPath $sourceFile.FullName -Destination $targetPath -Force
                if ($targetExists) { $stats.RulesUpdated++ } else { $stats.RulesAdded++ }
            }
        }
    }

    foreach ($sourceFile in $libraryCommandFiles) {
        $targetPath = Join-Path $projectCommandDir $sourceFile.Name
        $targetExists = Test-Path -LiteralPath $targetPath
        $isSame = $false
        if ($targetExists) {
            $isSame = (Get-FileHash -LiteralPath $sourceFile.FullName -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash
        }
        if ($targetExists -and $isSame) {
            $stats.CommandsSkipped++
            continue
        }
        if ($targetExists -and -not $isSame -and -not $ForceOverwrite) {
            Write-Log "DIFFERS command: $($project.Name)\$($sourceFile.Name)" -Level WARN
            $stats.CommandsDiffers++
            continue
        }

        if ($PSCmdlet.ShouldProcess($targetPath, 'Sync command from Library')) {
            if (-not (Test-Path -LiteralPath $projectCommandDir -PathType Container)) {
                New-Item -Path $projectCommandDir -ItemType Directory -Force | Out-Null
            }
            Copy-Item -LiteralPath $sourceFile.FullName -Destination $targetPath -Force
            if ($targetExists) { $stats.CommandsUpdated++ } else { $stats.CommandsAdded++ }
        }
    }

    foreach ($sourceFile in $librarySkillFiles) {
        $skillName = [System.IO.Path]::GetFileNameWithoutExtension($sourceFile.Name)
        $targetDir = Join-Path $projectSkillsDir $skillName
        $targetPath = Join-Path $targetDir 'SKILL.md'
        $targetExists = Test-Path -LiteralPath $targetPath
        $skillContent = Convert-MdcToSkillMarkdown -SourceFile $sourceFile.FullName
        $isSame = $false
        if ($targetExists) {
            $targetContent = Get-Content -LiteralPath $targetPath -Raw -ErrorAction SilentlyContinue
            $isSame = (Get-StringHash -Text $skillContent) -eq (Get-StringHash -Text $targetContent)
        }
        if ($targetExists -and $isSame) {
            $stats.SkillsSkipped++
            continue
        }
        if ($targetExists -and -not $isSame -and -not $ForceOverwrite) {
            Write-Log "DIFFERS skill: $($project.Name)\$($skillName)\SKILL.md" -Level WARN
            $stats.SkillsDiffers++
            continue
        }

        if ($PSCmdlet.ShouldProcess($targetPath, 'Sync skill from Library')) {
            if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
                New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
            }
            Set-Content -LiteralPath $targetPath -Value $skillContent -Encoding utf8
            if ($targetExists) { $stats.SkillsUpdated++ } else { $stats.SkillsAdded++ }
        }
    }
}

Write-Log "`n--- Summary ---" -Level INFO
Write-Log "Projects processed: $($processedProjects)" -Level INFO
Write-Log "Projects skipped (no .cursor): $($skippedProjects)" -Level INFO
Write-Log "Rules   added/updated/skipped/differs: $($stats.RulesAdded)/$($stats.RulesUpdated)/$($stats.RulesSkipped)/$($stats.RulesDiffers)" -Level INFO
Write-Log "Commands added/updated/skipped/differs: $($stats.CommandsAdded)/$($stats.CommandsUpdated)/$($stats.CommandsSkipped)/$($stats.CommandsDiffers)" -Level INFO
Write-Log "Skills   added/updated/skipped/differs: $($stats.SkillsAdded)/$($stats.SkillsUpdated)/$($stats.SkillsSkipped)/$($stats.SkillsDiffers)" -Level INFO

