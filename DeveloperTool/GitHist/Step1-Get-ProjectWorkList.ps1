<#
.SYNOPSIS
    Scans all git repos under c:\opt\src and builds an editable worklist of projects
    with commits by the specified author in a given timeframe.

.DESCRIPTION
    Phase 1 of the Git History extraction process.
    Discovers git repositories, filters by author activity, and writes
    ProjectWorkList.txt — a plain text file with one project path per line.
    The user curates that file (removing unwanted lines) before Phase 2.

.PARAMETER SourceRoot
    Root folder to scan for git repos.

.PARAMETER AuthorFilter
    Author to filter by. Accepts:
      - Git author name (e.g. 'geir.helge.starholm')
      - Email address (e.g. 'geir.helge.starholm@Dedge.no')
      - Windows username (e.g. 'FKGEISTA') — resolved to email via team lookup
      - Empty string — includes all authors (no filter)

.PARAMETER Since
    Start of the time range for git log (e.g. '9 months ago', '2025-06-01').

.PARAMETER Until
    End of the time range for git log (e.g. '2026-03-01'). Empty = now.

.PARAMETER OutputFile
    Path for the generated worklist file.

.NOTES
    DedgePsh special handling:
      - DevTools/<Theme>/<Project> paths are listed individually
      - _Modules/<ModuleName> paths are listed individually
    All other repos are listed by their repo root.
#>

param(
    [string]$SourceRoot = 'C:\opt\src',
    [string]$AuthorFilter = 'geir.helge.starholm',
    [string]$Since = '9 months ago',
    [string]$Until = '',
    [string]$OutputFile = (Join-Path $PSScriptRoot 'ProjectWorkList.txt')
)

Import-Module GlobalFunctions -Force

$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)

$usernameLookup = @{
    'FKGEISTA' = 'geir.helge.starholm'
    'FKSVEERI' = 'svein.morten.erikstad'
    'FKMISTA'  = 'mina.marie.starholm'
    'FKCELERI' = 'celine.andreassen.erikstad'
}

$resolvedAuthor = $AuthorFilter
if ([string]::IsNullOrWhiteSpace($AuthorFilter)) {
    $resolvedAuthor = ''
    Write-LogMessage "[$($scriptName)] Author filter: (none - all authors)" -Level INFO
}
elseif ($usernameLookup.ContainsKey($AuthorFilter.ToUpper())) {
    $resolvedAuthor = $usernameLookup[$AuthorFilter.ToUpper()]
    Write-LogMessage "[$($scriptName)] Resolved username $($AuthorFilter) to author: $($resolvedAuthor)" -Level INFO
}
else {
    Write-LogMessage "[$($scriptName)] Author filter: $($resolvedAuthor)" -Level INFO
}

$gitFilterArgs = [System.Collections.Generic.List[string]]::new()
if (-not [string]::IsNullOrWhiteSpace($resolvedAuthor)) {
    $gitFilterArgs.Add("--author=$resolvedAuthor")
}
$gitFilterArgs.Add("--since=$Since")
if (-not [string]::IsNullOrWhiteSpace($Until)) {
    $gitFilterArgs.Add("--until=$Until")
}

$mdcExclude = ':(exclude)*.mdc'

Write-LogMessage "[$($scriptName)] Starting project worklist generation" -Level INFO
Write-LogMessage "[$($scriptName)] Source root : $($SourceRoot)" -Level INFO
Write-LogMessage "[$($scriptName)] Since       : $($Since)" -Level INFO
if (-not [string]::IsNullOrWhiteSpace($Until)) {
    Write-LogMessage "[$($scriptName)] Until       : $($Until)" -Level INFO
}

# ── Step 1: Discover git repos ──────────────────────────────────────────────
Write-LogMessage "[$($scriptName)] Discovering git repositories..." -Level INFO

$gitDirs = Get-ChildItem -Path $SourceRoot -Directory -Recurse -Depth 2 -Filter '.git' -Force -ErrorAction SilentlyContinue

$repoRoots = $gitDirs | ForEach-Object { $_.Parent.FullName } | Sort-Object -Unique | Where-Object {
    $_ -notmatch 'DedgeSrc' -and
    $_ -notmatch 'GitHist' -and
    $_ -notmatch '[\\/]_' -and
    $_ -notmatch '- Copy'
}

Write-LogMessage "[$($scriptName)] Found $($repoRoots.Count) repos (excluding DedgeSrc, GitHist)" -Level INFO

# ── Step 2 & 3: Check each repo for author commits and collect stats ────────
$standaloneProjects = [System.Collections.Generic.List[PSCustomObject]]::new()
$devToolsProjects   = [System.Collections.Generic.List[PSCustomObject]]::new()
$moduleProjects     = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($repoRoot in $repoRoots) {
    $repoName = Split-Path $repoRoot -Leaf

    $logLines = git -C $repoRoot log @gitFilterArgs --oneline -- . $mdcExclude 2>$null
    if (-not $logLines -or $logLines.Count -eq 0) { continue }

    $commitCount = $logLines.Count
    $firstDate = git -C $repoRoot log @gitFilterArgs --reverse --format="%as" -- . $mdcExclude 2>$null | Select-Object -First 1
    $lastDate  = git -C $repoRoot log @gitFilterArgs --format="%as" -1 -- . $mdcExclude 2>$null

    Write-LogMessage "[$($scriptName)] $($repoName): $($commitCount) commits ($($firstDate) .. $($lastDate))" -Level INFO

    # ── DedgePsh special handling ──
    if ($repoName -eq 'DedgePsh') {
        $changedFiles = git -C $repoRoot log @gitFilterArgs --name-only --format="" -- . $mdcExclude 2>$null |
            Where-Object { $_ -ne '' } | Sort-Object -Unique

        # DevTools: group by Theme/Project
        $dtFiles = $changedFiles | Where-Object { $_ -match '^DevTools/' }
        $dtGrouped = @{}
        foreach ($f in $dtFiles) {
            $parts = $f -split '/'
            if ($parts.Count -ge 3) {
                $theme   = $parts[1]
                $project = $parts[2]
                $key = "$($theme)/$($project)"
                if (-not $dtGrouped.ContainsKey($key)) {
                    $dtGrouped[$key] = @{ Theme = $theme; Project = $project; Files = [System.Collections.Generic.List[string]]::new() }
                }
                $dtGrouped[$key].Files.Add($f)
            }
        }

        foreach ($entry in $dtGrouped.GetEnumerator()) {
            $info = $entry.Value
            if ([System.IO.Path]::HasExtension($info.Project)) { continue }
            if ($info.Theme.StartsWith('_') -or $info.Project.StartsWith('_')) { continue }

            $projectPath = Join-Path $repoRoot "DevTools\$($info.Theme)\$($info.Project)"
            if (-not (Test-Path -LiteralPath $projectPath -PathType Container)) { continue }

            $dtCommits = git -C $repoRoot log @gitFilterArgs --oneline -- "DevTools/$($info.Theme)/$($info.Project)" $mdcExclude 2>$null
            $dtCount = if ($dtCommits) { $dtCommits.Count } else { 0 }
            if ($dtCount -eq 0) { continue }

            $dtFirst = git -C $repoRoot log @gitFilterArgs --reverse --format="%as" -- "DevTools/$($info.Theme)/$($info.Project)" $mdcExclude 2>$null | Select-Object -First 1
            $dtLast  = git -C $repoRoot log @gitFilterArgs --format="%as" -1 -- "DevTools/$($info.Theme)/$($info.Project)" $mdcExclude 2>$null

            $devToolsProjects.Add([PSCustomObject]@{
                Path     = $projectPath
                Theme    = $info.Theme
                Project  = $info.Project
                Commits  = $dtCount
                First    = $dtFirst
                Last     = $dtLast
            })
        }

        # Modules: group by module name
        $modFiles = $changedFiles | Where-Object { $_ -match '^_Modules/' }
        $modGrouped = @{}
        foreach ($f in $modFiles) {
            $parts = $f -split '/'
            if ($parts.Count -ge 2) {
                $modName = $parts[1]
                if (-not $modGrouped.ContainsKey($modName)) {
                    $modGrouped[$modName] = 0
                }
                $modGrouped[$modName]++
            }
        }

        foreach ($modName in $modGrouped.Keys) {
            if ([System.IO.Path]::HasExtension($modName)) { continue }
            if ($modName.StartsWith('_')) { continue }

            $modPath = Join-Path $repoRoot "_Modules\$($modName)"
            if (-not (Test-Path -LiteralPath $modPath -PathType Container)) { continue }

            $modCommits = git -C $repoRoot log @gitFilterArgs --oneline -- "_Modules/$($modName)" $mdcExclude 2>$null
            $modCount = if ($modCommits) { $modCommits.Count } else { 0 }
            if ($modCount -eq 0) { continue }

            $modFirst = git -C $repoRoot log @gitFilterArgs --reverse --format="%as" -- "_Modules/$($modName)" $mdcExclude 2>$null | Select-Object -First 1
            $modLast  = git -C $repoRoot log @gitFilterArgs --format="%as" -1 -- "_Modules/$($modName)" $mdcExclude 2>$null

            $moduleProjects.Add([PSCustomObject]@{
                Path    = $modPath
                Module  = $modName
                Commits = $modCount
                First   = $modFirst
                Last    = $modLast
            })
        }

        # Direct subfolders of DedgePsh (excluding DevTools, _Modules, _ prefixed)
        $fkSubDirs = Get-ChildItem -LiteralPath $repoRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -ne 'DevTools' -and
                $_.Name -ne '_Modules' -and
                -not $_.Name.StartsWith('_') -and
                -not $_.Name.StartsWith('.') -and
                $_.Name -notmatch '- Copy'
            }

        foreach ($subDir in $fkSubDirs) {
            $subRel = $subDir.Name
            $subCommits = git -C $repoRoot log @gitFilterArgs --oneline -- $subRel $mdcExclude 2>$null
            $subCount = if ($subCommits) { $subCommits.Count } else { 0 }
            if ($subCount -eq 0) { continue }

            $subFirst = git -C $repoRoot log @gitFilterArgs --reverse --format="%as" -- $subRel $mdcExclude 2>$null | Select-Object -First 1
            $subLast  = git -C $repoRoot log @gitFilterArgs --format="%as" -1 -- $subRel $mdcExclude 2>$null

            $standaloneProjects.Add([PSCustomObject]@{
                Path    = $subDir.FullName
                Name    = "$($repoName)/$($subRel)"
                Commits = $subCount
                First   = $subFirst
                Last    = $subLast
            })
        }

        # Root-level files in DedgePsh (not in any subfolder)
        $rootOnlyFiles = $changedFiles | Where-Object {
            ($_ -split '/').Count -eq 1
        }
        if ($rootOnlyFiles -and $rootOnlyFiles.Count -gt 0) {
            $standaloneProjects.Add([PSCustomObject]@{
                Path    = $repoRoot
                Name    = "$($repoName) (root-level files)"
                Commits = $commitCount
                First   = $firstDate
                Last    = $lastDate
            })
        }

        continue
    }

    # ── Standard repo ──
    if (-not (Test-Path -LiteralPath $repoRoot -PathType Container)) { continue }

    # ── Detect multi-project C# solutions ──
    $slnFiles = Get-ChildItem -LiteralPath $repoRoot -Filter '*.sln' -File -Depth 1 -ErrorAction SilentlyContinue
    $csprojFiles = Get-ChildItem -LiteralPath $repoRoot -Filter '*.csproj' -Recurse -Depth 3 -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/](bin|obj|packages|\.vs)[\\/]' }

    if ($slnFiles -and $csprojFiles.Count -gt 1) {
        $standaloneProjects.Add([PSCustomObject]@{
            Path    = $repoRoot
            Name    = "$($repoName) (solution root)"
            Commits = $commitCount
            First   = $firstDate
            Last    = $lastDate
        })

        foreach ($csproj in $csprojFiles) {
            $subDir = $csproj.DirectoryName
            if ($subDir -eq $repoRoot) { continue }
            if (-not (Test-Path -LiteralPath $subDir -PathType Container)) { continue }
            $subRel = $subDir.Substring($repoRoot.Length).TrimStart('\', '/').Replace('\', '/')

            $subCommits = git -C $repoRoot log @gitFilterArgs --oneline -- $subRel $mdcExclude 2>$null
            $subCount = if ($subCommits) { $subCommits.Count } else { 0 }
            if ($subCount -eq 0) { continue }

            $subFirst = git -C $repoRoot log @gitFilterArgs --reverse --format="%as" -- $subRel $mdcExclude 2>$null | Select-Object -First 1
            $subLast  = git -C $repoRoot log @gitFilterArgs --format="%as" -1 -- $subRel $mdcExclude 2>$null

            $standaloneProjects.Add([PSCustomObject]@{
                Path    = $subDir
                Name    = Split-Path $subDir -Leaf
                Commits = $subCount
                First   = $subFirst
                Last    = $subLast
            })
        }
    }
    else {
        $standaloneProjects.Add([PSCustomObject]@{
            Path    = $repoRoot
            Name    = $repoName
            Commits = $commitCount
            First   = $firstDate
            Last    = $lastDate
        })
    }
}

# ── Step 5: Write worklist ──────────────────────────────────────────────────
Write-LogMessage "[$($scriptName)] Writing worklist to $($OutputFile)" -Level INFO

$standaloneProjects = $standaloneProjects | Sort-Object Commits -Descending
$devToolsProjects   = $devToolsProjects   | Sort-Object Theme, @{Expression={$_.Commits}; Descending=$true}
$moduleProjects     = $moduleProjects     | Sort-Object Commits -Descending

$maxPathLen = 0
$allPaths = @($standaloneProjects.Path) + @($devToolsProjects.Path) + @($moduleProjects.Path)
foreach ($p in $allPaths) {
    if ($p -and $p.Length -gt $maxPathLen) { $maxPathLen = $p.Length }
}
$padWidth = $maxPathLen + 4

$lines = [System.Collections.Generic.List[string]]::new()
$authorDisplay = if ([string]::IsNullOrWhiteSpace($resolvedAuthor)) { '(all authors)' } else { $resolvedAuthor }
$untilDisplay = if ([string]::IsNullOrWhiteSpace($Until)) { (Get-Date).ToString('yyyy-MM-dd') } else { $Until }
$lines.Add("# Git Activity Worklist")
$lines.Add("# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm') | Period: $($Since) to $($untilDisplay)")
$lines.Add("# Author: $($authorDisplay)")
$lines.Add("#")
$lines.Add("# Remove lines for projects you want to skip from Phase 2.")
$lines.Add("# Lines starting with # are ignored by Phase 2.")
$lines.Add("")

if ($standaloneProjects.Count -gt 0) {
    $lines.Add("# --- Standalone repos ---")
    foreach ($p in $standaloneProjects) {
        $comment = "# $($p.Commits) commits | $($p.First) .. $($p.Last)"
        $lines.Add("$($p.Path.PadRight($padWidth))$comment")
    }
    $lines.Add("")
}

if ($devToolsProjects.Count -gt 0) {
    $lines.Add("# --- DedgePsh DevTools projects (Theme / Project) ---")
    $currentTheme = ''
    foreach ($p in $devToolsProjects) {
        if ($p.Theme -ne $currentTheme) {
            $lines.Add("# [$($p.Theme)]")
            $currentTheme = $p.Theme
        }
        $comment = "# $($p.Commits) commits | $($p.First) .. $($p.Last)"
        $lines.Add("$($p.Path.PadRight($padWidth))$comment")
    }
    $lines.Add("")
}

if ($moduleProjects.Count -gt 0) {
    $lines.Add("# --- DedgePsh Modules ---")
    foreach ($p in $moduleProjects) {
        $comment = "# $($p.Commits) commits | $($p.First) .. $($p.Last)"
        $lines.Add("$($p.Path.PadRight($padWidth))$comment")
    }
    $lines.Add("")
}

$totalProjects = $standaloneProjects.Count + $devToolsProjects.Count + $moduleProjects.Count
$lines.Add("# --- Summary: $($totalProjects) projects found across $($standaloneProjects.Count) repos, $($devToolsProjects.Count) DevTools projects, $($moduleProjects.Count) modules ---")

$lines | Out-File -FilePath $OutputFile -Encoding utf8

Write-LogMessage "[$($scriptName)] Worklist written: $($totalProjects) projects total" -Level INFO
Write-LogMessage "[$($scriptName)] Output: $($OutputFile)" -Level INFO
Write-LogMessage "[$($scriptName)] Done. Review the file and remove projects you want to skip." -Level INFO
