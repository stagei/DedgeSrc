<#
.SYNOPSIS
    Creates a git-history export tree from ProjectWorkList.txt into a persistent
    Projects_<author>_<from>_<to> folder.

.DESCRIPTION
    Reads curated project paths from a worklist, mirrors folder structure under a
    deterministic output root, and writes GitHistory.md per project with commit metrics.
    Supports incremental updates: without -Force, only re-exports projects whose
    latest commit hash has changed since the last export.

.PARAMETER SourceRoot
    Root folder containing all source repos.

.PARAMETER WorkListPath
    Path to the curated worklist file.

.PARAMETER AuthorFilter
    Git author name/email filter. Empty = all authors.

.PARAMETER Since
    Start of the time range (e.g. '9 months ago', '2025-06-10').

.PARAMETER Until
    End of the time range. Empty = now.

.PARAMETER TopFiles
    Max number of top-changed files to list.

.PARAMETER Force
    Regenerate all GitHistory.md files regardless of whether they changed.
#>

param(
    [string]$SourceRoot = 'C:\opt\src',
    [string]$WorkListPath = (Join-Path $PSScriptRoot 'ProjectWorkList.txt'),
    [string]$AuthorFilter = 'geir.helge.starholm',
    [string]$Since = '9 months ago',
    [string]$Until = '',
    [int]$TopFiles = 30,
    [switch]$Force
)

Import-Module GlobalFunctions -Force

function Get-GitRepoRoot {
    param([Parameter(Mandatory)][string]$StartPath)
    $current = $StartPath
    while ($null -ne $current -and $current.Length -gt 0) {
        if (Test-Path -LiteralPath (Join-Path $current '.git')) { return $current }
        $parentInfo = Split-Path -Path $current -Parent
        if ([string]::IsNullOrWhiteSpace($parentInfo) -or $parentInfo -eq $current) { break }
        $current = $parentInfo
    }
    return $null
}

function Invoke-GitText {
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string[]]$GitArgs)
    $output = git -C $RepoRoot @GitArgs 2>$null
    if ($LASTEXITCODE -ne 0) { return @() }
    if ($null -eq $output) { return @() }
    return @($output)
}

$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$tick = [char]96

# ── Resolve dates for folder name ─────────────────────────────────────────────
function Resolve-RelativeDate {
    param([string]$DateExpr)
    # Handle "N <unit> ago" patterns
    if ($DateExpr -match '(\d+)\s+(month|months)\s+ago') {
        return (Get-Date).AddMonths(-[int]$Matches[1])
    }
    if ($DateExpr -match '(\d+)\s+(week|weeks)\s+ago') {
        return (Get-Date).AddDays(-([int]$Matches[1] * 7))
    }
    if ($DateExpr -match '(\d+)\s+(day|days)\s+ago') {
        return (Get-Date).AddDays(-[int]$Matches[1])
    }
    if ($DateExpr -match '(\d+)\s+(year|years)\s+ago') {
        return (Get-Date).AddYears(-[int]$Matches[1])
    }
    try { return [datetime]::Parse($DateExpr) }
    catch { return (Get-Date).AddMonths(-9) }
}

$sinceResolved = (Resolve-RelativeDate -DateExpr $Since).ToString('yyyyMMdd')

if (-not [string]::IsNullOrWhiteSpace($Until)) {
    $untilResolved = (Resolve-RelativeDate -DateExpr $Until).ToString('yyyyMMdd')
} else {
    $untilResolved = (Get-Date).ToString('yyyyMMdd')
}

$authorPart = if ([string]::IsNullOrWhiteSpace($AuthorFilter)) { 'all' }
              else { ($AuthorFilter -split '[.@ ]')[0].ToUpper() }

# ── Build deterministic folder name ──────────────────────────────────────────
$folderPrefix = "Projects_$($authorPart)_$($sinceResolved)_"
$folderName = "$($folderPrefix)$($untilResolved)"
$outputRoot = Join-Path $PSScriptRoot $folderName

# If an older folder with same author+since exists, copy its contents to seed incremental check
if (-not (Test-Path -LiteralPath $outputRoot)) {
    $oldFolder = Get-ChildItem -Path $PSScriptRoot -Directory -Filter "$($folderPrefix)*" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne $folderName } |
        Sort-Object Name -Descending | Select-Object -First 1
    if ($oldFolder) {
        Write-LogMessage "[$($scriptName)] Seeding $($folderName) from $($oldFolder.Name)" -Level INFO
        Copy-Item -LiteralPath $oldFolder.FullName -Destination $outputRoot -Recurse -Force
    } else {
        New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
    }
} else {
    Write-LogMessage "[$($scriptName)] Using existing folder $($folderName)" -Level INFO
}

Write-LogMessage "[$($scriptName)] Starting export generation" -Level INFO
Write-LogMessage "[$($scriptName)] Worklist: $($WorkListPath)" -Level INFO
Write-LogMessage "[$($scriptName)] Author  : $(if ([string]::IsNullOrWhiteSpace($AuthorFilter)) { '(all)' } else { $AuthorFilter })" -Level INFO
Write-LogMessage "[$($scriptName)] Since   : $($Since)" -Level INFO
if (-not [string]::IsNullOrWhiteSpace($Until)) {
    Write-LogMessage "[$($scriptName)] Until   : $($Until)" -Level INFO
}
Write-LogMessage "[$($scriptName)] Output  : $($outputRoot)" -Level INFO
Write-LogMessage "[$($scriptName)] Mode    : $(if ($Force) { 'Force (regenerate all)' } else { 'Incremental' })" -Level INFO

if (-not (Test-Path -LiteralPath $WorkListPath -PathType Leaf)) {
    Write-LogMessage "[$($scriptName)] Worklist not found: $($WorkListPath)" -Level ERROR
    exit 1
}

# ── Build git filter args ────────────────────────────────────────────────────
$gitFilterArgs = [System.Collections.Generic.List[string]]::new()
if (-not [string]::IsNullOrWhiteSpace($AuthorFilter)) {
    $gitFilterArgs.Add("--author=$AuthorFilter")
}
$gitFilterArgs.Add("--since=$Since")
if (-not [string]::IsNullOrWhiteSpace($Until)) {
    $gitFilterArgs.Add("--until=$Until")
}

$mdcExclude = ':(exclude)*.mdc'

$workLines = Get-Content -LiteralPath $WorkListPath -ErrorAction Stop
$sourcePaths = [System.Collections.Generic.List[string]]::new()

foreach ($line in $workLines) {
    $trimmed = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
    if ($trimmed.StartsWith('#')) { continue }
    $pathOnly = ($line -split '\s*#', 2)[0].Trim()
    if ([string]::IsNullOrWhiteSpace($pathOnly)) { continue }
    $sourcePaths.Add($pathOnly)
}

Write-LogMessage "[$($scriptName)] Parsed $($sourcePaths.Count) source paths from worklist" -Level INFO

$indexRows = [System.Collections.Generic.List[PSCustomObject]]::new()
$processed = 0
$skipped = 0
$unchanged = 0

foreach ($sourcePath in $sourcePaths) {
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
        Write-LogMessage "[$($scriptName)] Skip missing folder: $($sourcePath)" -Level WARN
        $skipped++
        continue
    }

    if (-not $sourcePath.StartsWith($SourceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-LogMessage "[$($scriptName)] Skip outside source root: $($sourcePath)" -Level WARN
        $skipped++
        continue
    }

    $repoRoot = Get-GitRepoRoot -StartPath $sourcePath
    if ([string]::IsNullOrWhiteSpace($repoRoot)) {
        Write-LogMessage "[$($scriptName)] Skip (no git repo found): $($sourcePath)" -Level WARN
        $skipped++
        continue
    }

    $relativeFromSource = $sourcePath.Substring($SourceRoot.Length).TrimStart('\', '/')
    if ([string]::IsNullOrWhiteSpace($relativeFromSource)) {
        $relativeFromSource = Split-Path -Path $sourcePath -Leaf
    }

    $reportFolder = Join-Path $outputRoot $relativeFromSource
    New-Item -ItemType Directory -Path $reportFolder -Force | Out-Null
    $reportPath = Join-Path $reportFolder 'GitHistory.md'

    $subPath = $sourcePath.Substring($repoRoot.Length).TrimStart('\', '/')

    # ── Get current latest commit hash for incremental check ──
    $latestHashArgs = @('log', '-1', '--format=%H') + @($gitFilterArgs)
    if (-not [string]::IsNullOrWhiteSpace($subPath)) {
        $latestHashArgs += @('--', $subPath.Replace('\', '/'), $mdcExclude)
    } else {
        $latestHashArgs += @('--', '.', $mdcExclude)
    }
    $latestHashLines = Invoke-GitText -RepoRoot $repoRoot -GitArgs $latestHashArgs
    $currentLatestHash = if ($latestHashLines.Count -gt 0) { ([string]$latestHashLines[0]).Trim() } else { '' }

    # ── Incremental check: compare with stored hash ──
    if (-not $Force -and (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
        $existingContent = Get-Content -LiteralPath $reportPath -Raw -ErrorAction SilentlyContinue
        if ($existingContent -and $existingContent -match 'Last commit hash:\s*(\S+)') {
            $storedHash = $Matches[1]
            if ($storedHash -eq $currentLatestHash -and -not [string]::IsNullOrWhiteSpace($currentLatestHash)) {
                $unchanged++
                $indexRows.Add([PSCustomObject]@{
                    SourcePath = $sourcePath; ReportPath = $reportPath
                    CommitCount = 0; First = ''; Last = '(unchanged)'
                })
                continue
            }
        }
    }

    $baseArgs = @('log') + @($gitFilterArgs)
    $commitArgs = $baseArgs + @('--date=short', '--format=%H|%ad|%an|%ae|%s')
    $nameOnlyArgs = $baseArgs + @('--name-only', '--format=')
    $shortStatArgs = $baseArgs + @('--shortstat', '--format=')

    if (-not [string]::IsNullOrWhiteSpace($subPath)) {
        $pathSpec = $subPath.Replace('\', '/')
        $commitArgs += @('--', $pathSpec, $mdcExclude)
        $nameOnlyArgs += @('--', $pathSpec, $mdcExclude)
        $shortStatArgs += @('--', $pathSpec, $mdcExclude)
    } else {
        $commitArgs += @('--', '.', $mdcExclude)
        $nameOnlyArgs += @('--', '.', $mdcExclude)
        $shortStatArgs += @('--', '.', $mdcExclude)
    }

    $commitLines = Invoke-GitText -RepoRoot $repoRoot -GitArgs $commitArgs
    if ($commitLines.Count -eq 0) {
        Write-LogMessage "[$($scriptName)] No commits for: $($sourcePath)" -Level WARN
        $skipped++
        continue
    }

    $commits = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($cl in $commitLines) {
        $parts = $cl -split '\|', 5
        if ($parts.Count -lt 5) { continue }
        $commits.Add([PSCustomObject]@{
            Hash = $parts[0]; Date = $parts[1]; Author = $parts[2]
            Email = $parts[3]; Message = $parts[4]
        })
    }

    if ($commits.Count -eq 0) {
        Write-LogMessage "[$($scriptName)] No parseable commits for: $($sourcePath)" -Level WARN
        $skipped++
        continue
    }

    $firstDate = ($commits | Select-Object -Last 1).Date
    $lastDate = ($commits | Select-Object -First 1).Date
    $lastHash = ($commits | Select-Object -First 1).Hash

    $firstEverArgs = @('log', '--reverse', '--format=%as', '--diff-filter=A')
    if (-not [string]::IsNullOrWhiteSpace($subPath)) {
        $firstEverArgs += @('--', $subPath.Replace('\', '/'), $mdcExclude)
    } else {
        $firstEverArgs += @('--', '.', $mdcExclude)
    }
    $firstEverLines = Invoke-GitText -RepoRoot $repoRoot -GitArgs $firstEverArgs
    $firstEverDate = if ($firstEverLines -and $firstEverLines.Count -gt 0) { $firstEverLines[0] } else { '' }
    if ([string]::IsNullOrWhiteSpace($firstEverDate)) {
        $fallbackArgs = @('log', '--reverse', '--format=%as')
        if (-not [string]::IsNullOrWhiteSpace($subPath)) {
            $fallbackArgs += @('--', $subPath.Replace('\', '/'), $mdcExclude)
        } else {
            $fallbackArgs += @('--', '.', $mdcExclude)
        }
        $fallbackLines = Invoke-GitText -RepoRoot $repoRoot -GitArgs $fallbackArgs
        $firstEverDate = if ($fallbackLines -and $fallbackLines.Count -gt 0) { $fallbackLines[0] } else { 'unknown' }
    }

    $nameOnlyLines = Invoke-GitText -RepoRoot $repoRoot -GitArgs $nameOnlyArgs
    $fileGroups = $nameOnlyLines |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Group-Object | Sort-Object Count -Descending
    $topChangedFiles = $fileGroups | Select-Object -First $TopFiles

    $shortStatLines = Invoke-GitText -RepoRoot $repoRoot -GitArgs $shortStatArgs
    $filesChangedTotal = 0; $insertionsTotal = 0; $deletionsTotal = 0
    foreach ($line in $shortStatLines) {
        if ($line -match '(\d+) files? changed') { $filesChangedTotal += [int]$Matches[1] }
        if ($line -match '(\d+) insertions?\(\+\)') { $insertionsTotal += [int]$Matches[1] }
        if ($line -match '(\d+) deletions?\(-\)') { $deletionsTotal += [int]$Matches[1] }
    }

    $remoteUrl = git -C $repoRoot remote get-url origin 2>$null
    if ([string]::IsNullOrWhiteSpace($remoteUrl)) { $remoteUrl = '' }

    $md = [System.Collections.Generic.List[string]]::new()
    $md.Add('# Git History Report')
    $md.Add('')
    $md.Add("- Source path: $($tick)$($sourcePath)$($tick)")
    $md.Add("- Repository root: $($tick)$($repoRoot)$($tick)")
    if (-not [string]::IsNullOrWhiteSpace($remoteUrl)) {
        $md.Add("- Remote URL: $($tick)$($remoteUrl)$($tick)")
    }
    if (-not [string]::IsNullOrWhiteSpace($subPath)) {
        $md.Add("- Repository subpath filter: $($tick)$($subPath.Replace('\', '/'))$($tick)")
    } else {
        $md.Add('- Repository subpath filter: *(repo root)*')
    }
    $md.Add("- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $md.Add("- Author filter: $($tick)$(if ([string]::IsNullOrWhiteSpace($AuthorFilter)) { '(all)' } else { $AuthorFilter })$($tick)")
    $md.Add("- Since: $($tick)$($Since)$($tick)")
    $md.Add('')
    $md.Add('## Summary')
    $md.Add('')
    $md.Add("- Commits: $($commits.Count)")
    $md.Add("- Last commit hash: $($lastHash)")
    $md.Add("- First ever commit: $($firstEverDate)")
    $md.Add("- First commit date in range: $($firstDate)")
    $md.Add("- Last commit date in range: $($lastDate)")
    $md.Add("- Aggregated files changed: $($filesChangedTotal)")
    $md.Add("- Aggregated insertions: $($insertionsTotal)")
    $md.Add("- Aggregated deletions: $($deletionsTotal)")

    $sourceExts = @('.ps1','.psm1','.psd1','.cs','.csproj','.sln','.py','.js','.ts','.cmd','.bat','.sh','.sql','.cbl','.cpy','.json','.xml','.yaml','.yml','.config','.cshtml','.razor','.jsx','.tsx','.css','.html')
    $sourceFiles = Get-ChildItem -LiteralPath $sourcePath -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in $sourceExts -and $_.FullName -notmatch '[\\/](bin|obj|node_modules|\.git|\.vs|packages|__pycache__)[\\/]' }
    $sourceFileCount = ($sourceFiles | Measure-Object).Count
    $totalCodeLines = 0
    foreach ($sf in $sourceFiles) {
        try { $totalCodeLines += (Get-Content -LiteralPath $sf.FullName -ErrorAction SilentlyContinue | Measure-Object -Line).Lines } catch {}
    }
    $md.Add("- Source file count: $($sourceFileCount)")
    $md.Add("- Total code lines: $($totalCodeLines)")
    $md.Add('')
    $md.Add('## Top Changed Files')
    $md.Add('')
    $md.Add('| File | Touch Count |')
    $md.Add('|---|---:|')
    foreach ($g in $topChangedFiles) {
        $md.Add("| $($tick)$($g.Name)$($tick) | $($g.Count) |")
    }
    $md.Add('')
    $md.Add('## Commit List')
    $md.Add('')
    $md.Add('| Date | Hash | Author | Message |')
    $md.Add('|---|---|---|---|')
    foreach ($c in $commits) {
        $shortHash = if ($c.Hash.Length -ge 8) { $c.Hash.Substring(0, 8) } else { $c.Hash }
        $safeMessage = $c.Message.Replace('|', '\|')
        $md.Add("| $($c.Date) | $($tick)$($shortHash)$($tick) | $($c.Author) | $($safeMessage) |")
    }
    $md.Add('')

    $md | Out-File -LiteralPath $reportPath -Encoding utf8

    $indexRows.Add([PSCustomObject]@{
        SourcePath = $sourcePath; ReportPath = $reportPath
        CommitCount = $commits.Count; First = $firstDate; Last = $lastDate
    })

    Write-LogMessage "[$($scriptName)] Report created: $($reportPath)" -Level INFO
    $processed++
}

$indexPath = Join-Path $outputRoot 'Index.md'
$idx = [System.Collections.Generic.List[string]]::new()
$idx.Add('# Git History Export Index')
$idx.Add('')
$idx.Add("- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$idx.Add("- Source root: $($tick)$($SourceRoot)$($tick)")
$idx.Add("- Worklist: $($tick)$($WorkListPath)$($tick)")
$idx.Add("- Author filter: $($tick)$(if ([string]::IsNullOrWhiteSpace($AuthorFilter)) { '(all)' } else { $AuthorFilter })$($tick)")
$idx.Add("- Since: $($tick)$($Since)$($tick)")
$idx.Add("- Processed: $($processed), Unchanged: $($unchanged), Skipped: $($skipped)")
$idx.Add('')
$idx.Add('| Source Path | Report Path | Commits | First | Last |')
$idx.Add('|---|---|---:|---|---|')

foreach ($row in $indexRows) {
    $reportRelative = $row.ReportPath.Substring($outputRoot.Length).TrimStart('\', '/')
    $idx.Add("| $($tick)$($row.SourcePath)$($tick) | $($tick)$($reportRelative.Replace('\', '/'))$($tick) | $($row.CommitCount) | $($row.First) | $($row.Last) |")
}

$idx | Out-File -LiteralPath $indexPath -Encoding utf8

Write-LogMessage "[$($scriptName)] Index created: $($indexPath)" -Level INFO
Write-LogMessage "[$($scriptName)] Done. Processed=$($processed), Unchanged=$($unchanged), Skipped=$($skipped)" -Level INFO
