<###
.SYNOPSIS
Create a multi-repo git change activity report for one or more authors.

.DESCRIPTION
Scans a root folder for git repositories (by locating .git folders), filters commits by author
(name/email) within a time window, and produces a Markdown report with:
- code line stats (excluding *.md)
- markdown line stats (separate category)fi
- per-file headline + stats

.NOTES
- Requires git.exe available in PATH.
- Author filtering uses `git log --author` with `--perl-regexp`.
###>

[CmdletBinding(DefaultParameterSetName = 'DaysBack')]
param(
  [Parameter(ParameterSetName = 'DaysBack')]
  [int] $DaysBack = 21,

  [Parameter(Mandatory, ParameterSetName = 'DateRange')]
  [datetime] $FromDate,

  [Parameter(Mandatory, ParameterSetName = 'DateRange')]
  [datetime] $ToDate,

  [string] $Root = 'C:\opt\src',

  [string[]] $Authors = @(
    'FKGEISTA',
    'geir.helge.starholm@Dedge.no',
    'STAGEI',
    'geir@starholm'
  ),

  [string] $OutputPath,

  [switch] $WriteJson,

  [switch] $VerifyTotals,

  # Produces a compact per-repo overview (no file listing).
  [switch] $Compact,

  # Exclude downloaded/generated/vendor/build/runtime folders (recommended default).
  [switch] $ExcludeVendorAndBuildFolders = $true,

  # When set, send the generated report as an email attachment (requires GlobalFunctions).
  [switch] $SendEmail,

  # When set, send an SMS notification when the report is created (requires GlobalFunctions).
  [switch] $SendSms,

  # Email recipient (defaults to current user if known).
  [string] $EmailTo,

  # Email sender (defaults to service account sender).
  [string] $EmailFrom = 'srv_Dedge_repo@Dedge.onmicrosoft.com',

  # SMS receiver (defaults to current user if known).
  [string] $SmsTo
)

$ErrorActionPreference = 'Stop'

# Normalize and de-duplicate authors early (ensures VerifyTotals + SMS are clean).
$Authors = @(
  $Authors |
    ForEach-Object {
      $s = if ($_ -is [string]) { $_ } else { [string]$_ }
      # Allow users to pass "-Authors a,b" as a single string; split on commas.
      $s -split ',' | ForEach-Object { $_.Trim() }
    } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    Select-Object -Unique
)

# Import GlobalFunctions for Write-LogMessage
Import-Module GlobalFunctions -Force

function Get-RepoRoots {
  param([Parameter(Mandatory)][string] $Path)

  Get-ChildItem -Path $Path -Directory -Force -Recurse -Filter '.git' |
    Where-Object { Test-Path (Join-Path $_.FullName 'HEAD') } |
    ForEach-Object { Split-Path -Parent $_.FullName } |
    Sort-Object -Unique
}

function Get-HeadlineForFile {
  param([Parameter(Mandatory)][string] $Path)

  if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
  if ($Path -match '[\x00]') { return $null }
  if (-not (Test-Path -LiteralPath $Path)) { return $null }

  try {
    $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    $lines = Get-Content -LiteralPath $Path -TotalCount 260

    switch ($ext) {
      '.cs' {
        $ns = ($lines | Select-String -Pattern '^\s*namespace\s+([^;{\s]+)' -AllMatches | Select-Object -First 1).Matches.Groups[1].Value

        # Handles both file-scoped and block-scoped namespaces
        # - file-scoped: namespace Foo.Bar;
        # - block-scoped: namespace Foo.Bar { ... }
        if ($ns) { $ns = $ns.Trim() }

        $typeMatch = ($lines | Select-String -Pattern '^\s*(?:\[(?<attr>[^\]]+)\]\s*)*(?:(public|internal|private|protected)\s+)?(?:(static|abstract|sealed|partial)\s+)*\b(class|record|struct|interface|enum)\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)' -AllMatches | Select-Object -First 1)
        $typeName = $typeMatch.Matches.Groups['name'].Value

        if ($typeName) {
          if ($ns) { return "$($ns).$($typeName)" }
          return $typeName
        }

        # Fallback: top-level static class Program or any type name may be further down
        $typeMatch2 = (Get-Content -LiteralPath $Path -TotalCount 1200 | Select-String -Pattern '^\s*(public|internal|private|protected)?\s*(static|abstract|sealed|partial)?\s*\b(class|record|struct|interface|enum)\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)' -AllMatches | Select-Object -First 1)
        $typeName2 = $typeMatch2.Matches.Groups['name'].Value
        if ($typeName2) {
          if ($ns) { return "$($ns).$($typeName2)" }
          return $typeName2
        }

        # Top-level programs in C# can have no explicit type declaration in the file.
        $hasTopLevelUsing = ($lines | Where-Object { $_ -match '^\s*using\s+' } | Select-Object -First 1)
        $hasMainLike = ($lines | Where-Object { $_ -match '\b(args|Console\.Write|return\s+|await\s+)\b' } | Select-Object -First 1)
        if ($hasTopLevelUsing -or $hasMainLike) { return 'C# top-level program' }

        return $null
      }

      '.ps1' {
        $syn = ($lines | Select-String -Pattern '^\s*\.SYNOPSIS\s*$' -SimpleMatch | Select-Object -First 1)
        if ($syn) {
          $idx = $syn.LineNumber - 1
          $after = $lines | Select-Object -Skip ($idx + 1) | Where-Object { $_ -match '\S' } | Select-Object -First 1
          if ($after) { return $after.Trim() }
        }

        $fn = ($lines | Select-String -Pattern '^\s*function\s+([A-Za-z_][A-Za-z0-9_-]*)\b' -AllMatches | Select-Object -First 1).Matches.Groups[1].Value
        if ($fn) { return "function $($fn)" }
        return $null
      }

      '.psm1' {
        $fn = ($lines | Select-String -Pattern '^\s*function\s+([A-Za-z_][A-Za-z0-9_-]*)\b' -AllMatches | Select-Object -First 1).Matches.Groups[1].Value
        if ($fn) { return "module exports incl. $($fn)" }
        return 'PowerShell module'
      }

      '.sql' {
        $stmt = ($lines | Select-String -Pattern '^\s*(CREATE|ALTER)\s+(PROC|PROCEDURE|FUNCTION|VIEW|TABLE)\s+(.+?)\b' -AllMatches | Select-Object -First 1).Line
        if ($stmt) { return ($stmt.Trim() -replace '\s+', ' ') }
        return $null
      }

      default { return $null }
    }
  }
  catch {
    return $null
  }
}

function Get-SafeExtension {
  param([Parameter(Mandatory)][string] $Path)
  try { return [IO.Path]::GetExtension($Path).ToLowerInvariant() } catch { return '' }
}

function Get-SafeFolder {
  param([Parameter(Mandatory)][string] $Path)
  try {
    $d = [IO.Path]::GetDirectoryName($Path)
    if ($d) { return ($d -replace '\\', '/') }
    return ''
  }
  catch {
    return ''
  }
}

# Exclude paths containing `_old` anywhere in the full path string (repo-relative),
# and optionally exclude common downloaded/generated/build/runtime folders.
function Test-IsExcludedPath {
  param([Parameter(Mandatory)][string] $Path)

  if ($Path -like '*_old*') { return $true }

  if (-not $ExcludeVendorAndBuildFolders) { return $false }

  # Regex: vendor/build/runtime folder detection (repo-relative paths)
  # - case-insensitive match
  # - matches full folder names (not partial)
  # - supports both Windows and POSIX path separators
  return ($Path -match '(?i)(^|[\\/])(bin|obj|packages|node_modules|dist|build|runtimes|site-packages|__pycache__|\.venv|venv|\.pytest_cache|\.mypy_cache|\.nuget)([\\/]|$)')
}

function Get-DefaultEmailForUser {
  param([string] $Username)

  switch ($Username) {
    'FKGEISTA' { return 'geir.helge.starholm@Dedge.no' }
    'FKSVEERI' { return 'svein.morten.erikstad@Dedge.no' }
    'FKMISTA' { return 'mina.marie.starholm@Dedge.no' }
    'FKCELERI' { return 'Celine.Andreassen.Erikstad@Dedge.no' }
    default { return $null }
  }
}

function Get-DefaultSmsForUser {
  param([string] $Username)

  switch ($Username) {
    'FKGEISTA' { return '+4797188358' }
    'FKSVEERI' { return '+4795762742' }
    'FKMISTA' { return '+4799348397' }
    'FKCELERI' { return '+4745269945' }
    default { return $null }
  }
}

function Get-ChangeKind {
  param(
    [Parameter(Mandatory)][string] $Path,
    [string] $Ext = ''
  )

  $leaf = ''
  try { $leaf = [IO.Path]::GetFileName($Path) } catch { $leaf = $Path }

  # Docs
  if ($Ext -in @('.md', '.txt', '.rst', '.adoc', '.markdown')) { return 'Doc' }
  if ($leaf -in @('.cursorrules', 'README', 'README.md', 'LICENSE', 'LICENSE.txt', 'CHANGELOG', 'CHANGELOG.md', 'IMPROVEMENTS.md')) { return 'Doc' }

  # Code (explicitly treat cs/bat/ps* as code)
  if ($Ext -in @('.cs', '.ps1', '.psm1', '.psd1', '.bat', '.cmd')) { return 'Code' }

  # Default: treat as code unless it is clearly documentation.
  return 'Code'
}

function Get-CompactRepoSummaryLines {
  param(
    [Parameter(Mandatory)][pscustomobject] $RepoReport,
    [int] $MaxLines = 10
  )

  # RepoReport expected keys:
  # - Name, Repo, Totals(Code/Docs), CommitSummary(CodeSubjects/DocSubjects)

  $lines = New-Object System.Collections.Generic.List[string]

  $lines.Add(('Repo: `{0}`' -f $RepoReport.Repo))
  $lines.Add(("Code: **+{0}/-{1}**  Docs: **+{2}/-{3}**" -f $RepoReport.Totals.Code.Added, $RepoReport.Totals.Code.Deleted, $RepoReport.Totals.Docs.Added, $RepoReport.Totals.Docs.Deleted))

  # Value-added: heuristic from commit subjects (offline summarization)
  $subjectsAll = @($RepoReport.CommitSummary.CodeSubjects + $RepoReport.CommitSummary.DocSubjects) | Where-Object { $_ }
  $focus = 'maintenance'
  if ($subjectsAll -match '(?i)fix|bug' ) { $focus = 'bug fixes and stability' }
  elseif ($subjectsAll -match '(?i)add|implement|feature|new' ) { $focus = 'new functionality' }
  elseif ($subjectsAll -match '(?i)refactor|cleanup' ) { $focus = 'refactoring/cleanup' }
  elseif ($subjectsAll -match '(?i)deploy|pipeline|ci|build' ) { $focus = 'build/deploy improvements' }

  $lines.Add(("- Value added: **{0}** (based on commit subjects)" -f $focus))

  $codeBullets = @($RepoReport.CommitSummary.CodeSubjects | Select-Object -First 4)
  if ($codeBullets.Count -gt 0) {
    $lines.Add('Code changes (from commit messages):')
    foreach ($s in $codeBullets) { $lines.Add(("- {0}" -f $s)) }
  }

  $docBullets = @($RepoReport.CommitSummary.DocSubjects | Select-Object -First 3)
  if ($docBullets.Count -gt 0) {
    $lines.Add('Documentation changes (from commit messages):')
    foreach ($s in $docBullets) { $lines.Add(("- {0}" -f $s)) }
  }

  return @($lines | Select-Object -First $MaxLines)
}

# Time window
$since = $null
$until = $null
if ($PSCmdlet.ParameterSetName -eq 'DateRange') {
  $since = $FromDate
  $until = $ToDate
}
else {
  $since = (Get-Date).AddDays(-$DaysBack)
  $until = Get-Date
}

$sinceIso = $since.ToString('o')
$untilIso = $until.ToString('o')

# Add secondary email for current user only if their primary email is in the Authors list.
# This ensures reports for the current user include all their email aliases, but reports
# for other users (e.g., FKSVEERI) don't get FKGEISTA's secondary email added.
$currentUserPrimaryEmail = Get-DefaultEmailForUser -Username $env:USERNAME
if ($currentUserPrimaryEmail -and ($Authors -contains $currentUserPrimaryEmail)) {
  $secondaryEmail = switch ($env:USERNAME) {
    'FKGEISTA' { 'geir@starholm.net' }
    default { $null }
  }
  if ($secondaryEmail -and ($Authors -notcontains $secondaryEmail)) {
    $Authors += $secondaryEmail
    # Re-normalize to ensure uniqueness
    $Authors = @($Authors | Select-Object -Unique)
  }
}

$authorRegex = '(' + (($Authors | ForEach-Object { [Regex]::Escape($_) }) -join '|') + ')'

if (-not $OutputPath) {
  $stamp = (Get-Date).ToString('yyyyMMdd_HHmm')
  $OutputPath = Join-Path $Root "change_activity_report_$($stamp).md"
}

$jsonPath = $null
if ($WriteJson) {
  $jsonPath = [IO.Path]::ChangeExtension($OutputPath, '.json')
}

Write-LogMessage "Scanning for repos under: $($Root)" -Level INFO
$repoRoots = Get-RepoRoots -Path $Root
Write-LogMessage "Found $($repoRoots.Count) repo roots. Filtering commits since $($since.ToString('yyyy-MM-dd'))" -Level INFO

$repoReports = @()
foreach ($repo in $repoRoots) {
  try {
    $has = & git -C $repo log --since=$sinceIso --until=$untilIso --perl-regexp --author="$authorRegex" --pretty=format:%H -n 1 2>$null
  }
  catch {
    continue
  }
  if ($LASTEXITCODE -ne 0) { continue }
  if (-not $has) { continue }

  try {
    $numstat = & git -C $repo log --since=$sinceIso --until=$untilIso --perl-regexp --author="$authorRegex" --no-merges --numstat --pretty=format:'commit %H|%ad|%s' --date=short 2>$null
  }
  catch {
    continue
  }
  if ($LASTEXITCODE -ne 0) { continue }
  if (-not $numstat) { continue }

  $fileMap = @{}
  $commitCountByFile = @{}
  $recentMsgsByFile = @{}
  $commitMeta = @{}
  $currentCommitHash = $null
  $commitDate = $null
  $commitMsg = $null

  foreach ($line in $numstat) {
    if ($line -like 'commit *') {
      $parts = $line.Substring(7).Split('|', 3)
      $currentCommitHash = $parts[0]
      $commitDate = $parts[1]
      $commitMsg = $parts[2]

      if (-not $commitMeta.ContainsKey($currentCommitHash)) {
        $commitMeta[$currentCommitHash] = [ordered]@{
          Date = $commitDate
          Subject = $commitMsg
          HasCode = $false
          HasDocs = $false
        }
      }
      continue
    }

    if ($line -match '^(?<add>\d+|-)\t(?<del>\d+|-)\t(?<path>.+)$') {
      $p = $Matches['path']

      if (Test-IsExcludedPath -Path $p) { continue }

      $add = $Matches['add']
      $del = $Matches['del']

      if (-not $fileMap.ContainsKey($p)) {
        $fileMap[$p] = [ordered]@{ added = 0; deleted = 0; binary = $false; lastDate = $commitDate }
      }

      $entry = $fileMap[$p]
      if ($add -eq '-' -or $del -eq '-') {
        $entry.binary = $true
      }
      else {
        $entry.added += [int]$add
        $entry.deleted += [int]$del
      }

      if ($commitDate -gt $entry.lastDate) { $entry.lastDate = $commitDate }

      if (-not $commitCountByFile.ContainsKey($p)) { $commitCountByFile[$p] = 0 }
      $commitCountByFile[$p]++

      if (-not $recentMsgsByFile.ContainsKey($p)) {
        $recentMsgsByFile[$p] = New-Object System.Collections.Generic.List[string]
      }
      if ($recentMsgsByFile[$p].Count -lt 3) {
        $recentMsgsByFile[$p].Add("$($commitDate): $($commitMsg)")
      }

      # Track whether commits touched code/docs (used for compact summary)
      if ($currentCommitHash -and $commitMeta.ContainsKey($currentCommitHash)) {
        $extForKind = Get-SafeExtension -Path $p
        $kind = Get-ChangeKind -Path $p -Ext $extForKind
        if ($kind -eq 'Doc') { $commitMeta[$currentCommitHash].HasDocs = $true }
        elseif ($kind -eq 'Code') { $commitMeta[$currentCommitHash].HasCode = $true }
      }
    }
  }

  $files = @(
    foreach ($k in $fileMap.Keys) {
      if (Test-IsExcludedPath -Path $k) { continue }

      $ext = Get-SafeExtension -Path $k
      $isMd = $ext -eq '.md'

      $abs = $null
      try { $abs = Join-Path $repo $k } catch { $abs = $null }

      [pscustomobject]@{
        Path = $k
        Ext = $ext
        IsMarkdown = $isMd
        Added = $fileMap[$k].added
        Deleted = $fileMap[$k].deleted
        Binary = $fileMap[$k].binary
        LastDate = $fileMap[$k].lastDate
        Commits = $commitCountByFile[$k]
        Headline = (Get-HeadlineForFile -Path $abs)
        RecentMessages = ($recentMsgsByFile[$k] -join ' | ')
        Folder = (Get-SafeFolder -Path $k)
      }
    }
  ) | Sort-Object -Property Added -Descending

  $commitSubjectsCode = @($commitMeta.Values | Where-Object { $_.HasCode } | ForEach-Object { $_.Subject } | Where-Object { $_ } | Sort-Object -Unique)
  $commitSubjectsDocs = @($commitMeta.Values | Where-Object { $_.HasDocs -and -not $_.HasCode } | ForEach-Object { $_.Subject } | Where-Object { $_ } | Sort-Object -Unique)

  $repoReports += [pscustomobject]@{
    Repo = $repo
    Files = $files
    CommitSummary = [pscustomobject]@{
      CodeSubjects = $commitSubjectsCode
      DocSubjects = $commitSubjectsDocs
    }
  }
}

$allFiles = $repoReports | ForEach-Object { $_.Files }
$codeFiles = $allFiles | Where-Object { -not $_.IsMarkdown -and -not $_.Binary }
$mdFiles = $allFiles | Where-Object { $_.IsMarkdown -and -not $_.Binary }

$repoCount = $repoReports.Count
$totalCodeAdded = ($codeFiles | Measure-Object -Property Added -Sum).Sum
$totalCodeDeleted = ($codeFiles | Measure-Object -Property Deleted -Sum).Sum
$totalMdAdded = ($mdFiles | Measure-Object -Property Added -Sum).Sum
$totalMdDeleted = ($mdFiles | Measure-Object -Property Deleted -Sum).Sum

if ($null -eq $totalCodeAdded) { $totalCodeAdded = 0 }
if ($null -eq $totalCodeDeleted) { $totalCodeDeleted = 0 }
if ($null -eq $totalMdAdded) { $totalMdAdded = 0 }
if ($null -eq $totalMdDeleted) { $totalMdDeleted = 0 }

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# Git change activity report')
[void]$sb.AppendLine('')
[void]$sb.AppendLine(('Generated: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm')))
[void]$sb.AppendLine(('Range: {0} .. {1}' -f $since.ToString('yyyy-MM-dd'), $until.ToString('yyyy-MM-dd')))
[void]$sb.AppendLine(('Root: `{0}`' -f $Root))
[void]$sb.AppendLine(('Authors matched: {0}' -f ($Authors -join ', ')))
[void]$sb.AppendLine(('Exclusions: _old + vendor/build/runtime folders = {0}' -f $ExcludeVendorAndBuildFolders))
[void]$sb.AppendLine('')

[void]$sb.AppendLine('## Summary')
[void]$sb.AppendLine('')
[void]$sb.AppendLine(('- Repositories with your changes: **{0}**' -f $repoCount))
[void]$sb.AppendLine(('- Code (non-markdown, non-binary): **+{0} / -{1}** lines' -f $totalCodeAdded, $totalCodeDeleted))
[void]$sb.AppendLine(('- Markdown: **+{0} / -{1}** lines' -f $totalMdAdded, $totalMdDeleted))
[void]$sb.AppendLine('')

$repoReportsSorted = $repoReports | Sort-Object {
  ($_.Files | Where-Object { -not $_.IsMarkdown -and -not $_.Binary } | Measure-Object -Property Added -Sum).Sum
} -Descending

foreach ($r in $repoReportsSorted) {
  $repoRoot = $r.Repo
  $name = Split-Path -Leaf $repoRoot

  $rCode = $r.Files | Where-Object { -not $_.IsMarkdown -and -not $_.Binary }
  $rMd = $r.Files | Where-Object { $_.IsMarkdown -and -not $_.Binary }

  $rCodeAdded = ($rCode | Measure-Object Added -Sum).Sum
  $rCodeDeleted = ($rCode | Measure-Object Deleted -Sum).Sum
  $rMdAdded = ($rMd | Measure-Object Added -Sum).Sum
  $rMdDeleted = ($rMd | Measure-Object Deleted -Sum).Sum

  if ($null -eq $rCodeAdded) { $rCodeAdded = 0 }
  if ($null -eq $rCodeDeleted) { $rCodeDeleted = 0 }
  if ($null -eq $rMdAdded) { $rMdAdded = 0 }
  if ($null -eq $rMdDeleted) { $rMdDeleted = 0 }

  [void]$sb.AppendLine(('## {0}' -f $name))
  [void]$sb.AppendLine('')

  if ($Compact) {
    $repoObj = [pscustomobject]@{
      Name = $name
      Repo = $repoRoot
      Totals = [pscustomobject]@{
        Code = [pscustomobject]@{ Added = $rCodeAdded; Deleted = $rCodeDeleted }
        Docs = [pscustomobject]@{ Added = $rMdAdded; Deleted = $rMdDeleted }
      }
      CommitSummary = $r.CommitSummary
    }

    # Keep at most ~10 text lines per repo including the heading above.
    foreach ($l in (Get-CompactRepoSummaryLines -RepoReport $repoObj -MaxLines 8)) {
      [void]$sb.AppendLine($l)
    }
    [void]$sb.AppendLine('')
    continue
  }

  [void]$sb.AppendLine(('Repo: `{0}`' -f $repoRoot))
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine(('- Project statistics: code **+{0} / -{1}**, markdown **+{2} / -{3}**' -f $rCodeAdded, $rCodeDeleted, $rMdAdded, $rMdDeleted))

  $folderGroups = $r.Files | Where-Object { -not $_.Binary } | Group-Object Folder | Sort-Object { ($_.Group | Measure-Object Added -Sum).Sum } -Descending

  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('### Functional overview (by folder)')
  [void]$sb.AppendLine('')

  foreach ($g in $folderGroups) {
    $gCode = $g.Group | Where-Object { -not $_.IsMarkdown }
    $gMd2 = $g.Group | Where-Object { $_.IsMarkdown }

    $ga = ($gCode | Measure-Object Added -Sum).Sum
    $gd = ($gCode | Measure-Object Deleted -Sum).Sum
    $gma = ($gMd2 | Measure-Object Added -Sum).Sum
    $gmd = ($gMd2 | Measure-Object Deleted -Sum).Sum

    if ($null -eq $ga) { $ga = 0 }
    if ($null -eq $gd) { $gd = 0 }
    if ($null -eq $gma) { $gma = 0 }
    if ($null -eq $gmd) { $gmd = 0 }

    $folderName = if ([string]::IsNullOrWhiteSpace($g.Name)) { '/' } else { $g.Name }
    $fileCount = $g.Group.Count

    [void]$sb.AppendLine(('- **{0}** ({1} files): code **+{2}/-{3}**, md **+{4}/-{5}**' -f $folderName, $fileCount, $ga, $gd, $gma, $gmd))
  }

  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('### Changed classes/scripts (headline + stats)')
  [void]$sb.AppendLine('')

  $top = $r.Files | Where-Object { -not $_.Binary } | Sort-Object Added -Descending
  foreach ($f in $top) {
    $headline = if ($f.Headline) { $f.Headline } else { '(no headline detected)' }
    $kind = if ($f.IsMarkdown) { 'md' } else { 'code' }

    [void]$sb.AppendLine(('- **{0}** — {1} **+{2}/-{3}**, commits: **{4}**, last: **{5}**' -f $f.Path, $kind, $f.Added, $f.Deleted, $f.Commits, $f.LastDate))
    [void]$sb.AppendLine(('  - Headline: {0}' -f $headline))

    if ($f.RecentMessages) {
      [void]$sb.AppendLine(('  - Recent commits: {0}' -f $f.RecentMessages))
    }
  }

  [void]$sb.AppendLine('')
}

$sb.ToString() | Set-Content -LiteralPath $OutputPath -Encoding UTF8

if ($WriteJson) {
  $json = [pscustomobject]@{
    GeneratedAt = (Get-Date)
    Range = [pscustomobject]@{
      From = $since
      To = $until
      DaysBack = if ($PSCmdlet.ParameterSetName -eq 'DaysBack') { $DaysBack } else { $null }
    }
    Root = $Root
    Authors = $Authors
    Summary = [pscustomobject]@{
      RepositoriesWithChanges = $repoCount
      Code = [pscustomobject]@{ Added = $totalCodeAdded; Deleted = $totalCodeDeleted }
      Markdown = [pscustomobject]@{ Added = $totalMdAdded; Deleted = $totalMdDeleted }
    }
    Repositories = @(
      foreach ($r in $repoReportsSorted) {
        $repoRoot = $r.Repo
        $name = Split-Path -Leaf $repoRoot

        $rCode = $r.Files | Where-Object { -not $_.IsMarkdown -and -not $_.Binary }
        $rMd = $r.Files | Where-Object { $_.IsMarkdown -and -not $_.Binary }

        $rCodeAdded = ($rCode | Measure-Object Added -Sum).Sum
        $rCodeDeleted = ($rCode | Measure-Object Deleted -Sum).Sum
        $rMdAdded = ($rMd | Measure-Object Added -Sum).Sum
        $rMdDeleted = ($rMd | Measure-Object Deleted -Sum).Sum

        if ($null -eq $rCodeAdded) { $rCodeAdded = 0 }
        if ($null -eq $rCodeDeleted) { $rCodeDeleted = 0 }
        if ($null -eq $rMdAdded) { $rMdAdded = 0 }
        if ($null -eq $rMdDeleted) { $rMdDeleted = 0 }

        [pscustomobject]@{
          Name = $name
          Repo = $repoRoot
          Totals = [pscustomobject]@{
            Code = [pscustomobject]@{ Added = $rCodeAdded; Deleted = $rCodeDeleted }
            Markdown = [pscustomobject]@{ Added = $rMdAdded; Deleted = $rMdDeleted }
          }
          CommitSummary = $r.CommitSummary
          TopFiles = @(
            $r.Files |
              Where-Object { -not $_.Binary } |
              Sort-Object Added -Descending |
              Select-Object -First 50 Path, Ext, IsMarkdown, Added, Deleted, Commits, LastDate, Headline, Folder
          )
        }
      }
    )
  }

  $json | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
  Write-LogMessage "JSON written: $($jsonPath)" -Level INFO
}

if ($VerifyTotals) {
  try {
    $testScript = Join-Path $PSScriptRoot 'Test-GitChangeActivityReportTotals.ps1'
    if (Test-Path -LiteralPath $testScript) {
      # Run verifier script in-process to avoid pwsh array-arg quoting issues.
      if ($PSCmdlet.ParameterSetName -eq 'DaysBack') {
        $result = & $testScript -ReportPath $OutputPath -DaysBack $DaysBack -Root $Root -Authors $Authors -SkipReportParse:$Compact `
          -ExpectedCodeAdded $totalCodeAdded -ExpectedCodeDeleted $totalCodeDeleted -ExpectedMdAdded $totalMdAdded -ExpectedMdDeleted $totalMdDeleted
      }
      else {
        $result = & $testScript -ReportPath $OutputPath -FromDate $since -ToDate $until -Root $Root -Authors $Authors -SkipReportParse:$Compact `
          -ExpectedCodeAdded $totalCodeAdded -ExpectedCodeDeleted $totalCodeDeleted -ExpectedMdAdded $totalMdAdded -ExpectedMdDeleted $totalMdDeleted
      }
      # Just print the object output from the test script
      $result
    }
  } catch {
    Write-LogMessage "VerifyTotals failed: $($_.Exception.Message)" -Level WARN
  }
}

Write-LogMessage "Report written: $($OutputPath)" -Level INFO

if (-not $EmailTo) { $EmailTo = Get-DefaultEmailForUser -Username $env:USERNAME }
if (-not $SmsTo) { $SmsTo = Get-DefaultSmsForUser -Username $env:USERNAME }

if ($SendEmail) {
  try {
    $subject = "Git change activity report $($since.ToString('yyyy-MM-dd'))..$($until.ToString('yyyy-MM-dd'))"
    $body = @"
Hi,

Attached: Git change activity report.

Root: $($Root)
Authors: $($Authors -join ', ')
Mode: $([string]::IsNullOrWhiteSpace(($Compact.ToString())) ? 'Detailed' : 'Compact')

"@
    if ($EmailTo) {
      Send-Email -To $EmailTo -From $EmailFrom -Subject $subject -Body $body -Attachments @($OutputPath)
      Write-LogMessage "Email sent to $($EmailTo): $($OutputPath)" -Level INFO
    }
    else {
      Write-LogMessage "SendEmail requested but EmailTo could not be resolved for $($env:USERNAME)" -Level WARN
    }
  }
  catch {
    Write-LogMessage "SendEmail failed: $($_.Exception.Message)" -Level ERROR -Exception $_
  }
}

if ($SendSms) {
  try {
    if ($SmsTo) {
      $matchFlag = $null
      if ($VerifyTotals -and $result -and ($null -ne $result.TotalsMatch)) {
        $matchFlag = if ($result.TotalsMatch) { 'OK' } else { 'MISMATCH' }
      }
      else {
        $matchFlag = 'NA'
      }

      $authorText = ($Authors -join ',')
      $periodText = "$($since.ToString('yyyy-MM-dd'))..$($until.ToString('yyyy-MM-dd'))"

      $projects = @(
        foreach ($r in $repoReportsSorted) {
          try { Split-Path -Leaf $r.Repo } catch { $r.Repo }
        }
      ) | Where-Object { $_ } | Select-Object -Unique

      $projText = if ($projects.Count -gt 0) { ($projects -join ',') } else { '(none)' }

      # Build a readable, structured SMS payload using explicit labels and `n newlines.
      $lines = @(
        "GitChangeActivityReport"
        "TimePeriod: $($periodText)"
        "VerifyTotals: $($matchFlag)"
        "Authors: $($authorText)"
        "Projects: $($projText)"
        "RepositoriesWithChanges: $($repoCount)"
        "Code: +$($totalCodeAdded)/-$($totalCodeDeleted)"
        "Docs: +$($totalMdAdded)/-$($totalMdDeleted)"
      )

      # SMS gateways often split long texts automatically, but to preserve formatting and avoid truncation,
      # send multiple SMS parts (<= 150 chars) split on line boundaries.
      $maxLen = 150
      $parts = New-Object System.Collections.Generic.List[string]
      $current = ''
      foreach ($line in $lines) {
        $candidate = if ([string]::IsNullOrEmpty($current)) { $line } else { "$($current)`n$($line)" }
        if ($candidate.Length -le $maxLen) {
          $current = $candidate
        }
        else {
          if (-not [string]::IsNullOrEmpty($current)) { $parts.Add($current) }
          $current = $line
        }
      }
      if (-not [string]::IsNullOrEmpty($current)) { $parts.Add($current) }

      foreach ($p in $parts) {
        Send-Sms -Receiver $SmsTo -Message $p
      }
      Write-LogMessage "SMS sent to $($SmsTo)" -Level INFO
    }
    else {
      Write-LogMessage "SendSms requested but SmsTo could not be resolved for $($env:USERNAME)" -Level WARN
    }
  }
  catch {
    Write-LogMessage "SendSms failed: $($_.Exception.Message)" -Level ERROR -Exception $_
  }
}

Write-Output $OutputPath
