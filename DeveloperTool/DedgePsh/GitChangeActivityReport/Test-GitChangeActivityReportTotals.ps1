[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [string] $ReportPath,

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

  # When the main report is in compact mode, the markdown file no longer contains per-file lines.
  # In that case, skip parsing and only compute totals from git.
  [switch] $SkipReportParse,

  # Optional: pass expected totals from the caller when SkipReportParse is used.
  [int] $ExpectedCodeAdded = 0,
  [int] $ExpectedCodeDeleted = 0,
  [int] $ExpectedMdAdded = 0,
  [int] $ExpectedMdDeleted = 0
)

$ErrorActionPreference = 'Stop'

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
$authorRegex = '(' + (($Authors | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')'

# Exclude paths containing `_old` anywhere in the full path string (repo-relative),
# and exclude common downloaded/generated/build/runtime folders.
function Test-IsExcludedPath {
  param([Parameter(Mandatory)][string] $Path)
  if ($Path -like '*_old*') { return $true }

  <#
  Regex: vendor/build/runtime folder detection (repo-relative paths)

  (?i)                         = case-insensitive
  (^|[\\/])                    = start OR a path separator (Windows '\' or POSIX '/')
  (bin|obj|node_modules|...)   = folder names to exclude
  ([\\/]|$)                    = next separator OR end (ensures folder match, not partial)
  #>
  $rx = '(?i)(^|[\\/])(bin|obj|packages|node_modules|dist|build|runtimes|site-packages|__pycache__|\\.venv|venv|\\.pytest_cache|\\.mypy_cache|\\.nuget)([\\/]|$)'
  return ($Path -match $rx)
}

# ---- 1) parse report file entries and resummarize by unique path (skippable)
$parsed = @()
$dupes = @()
$agg = @()
$reportCodeAdd = 0
$reportCodeDel = 0
$reportMdAdd = 0
$reportMdDel = 0

if (-not $SkipReportParse) {
  $lines = Get-Content -LiteralPath $ReportPath

  $rx = '^\- \*\*(?<path>.+?)\*\* — (?<kind>md|code) \*\*\+(?<add>\d+)\/(?<junk>-)?\-(?<del>\d+)\*\*'
  $parsed = foreach ($l in $lines) {
    if ($l -match $rx) {
      if (Test-IsExcludedPath -Path $Matches.path) { continue }
      [pscustomobject]@{ Path=$Matches.path; Kind=$Matches.kind; Added=[int]$Matches.add; Deleted=[int]$Matches.del }
    }
  }

  $dupes = $parsed | Group-Object Path | Where-Object { $_.Count -gt 1 } | Sort-Object Count -Descending
  $agg = $parsed | Group-Object Path | ForEach-Object {
    $g = $_.Group
    [pscustomobject]@{
      Path = $_.Name
      Entries = $_.Count
      Kind = ($g | Select-Object -First 1).Kind
      Added = ($g | Measure-Object Added -Sum).Sum
      Deleted = ($g | Measure-Object Deleted -Sum).Sum
    }
  }

  $reportCode = $agg | Where-Object { $_.Kind -eq 'code' }
  $reportMd = $agg | Where-Object { $_.Kind -eq 'md' }

  $reportCodeAdd = ($reportCode | Measure-Object Added -Sum).Sum
  $reportCodeDel = ($reportCode | Measure-Object Deleted -Sum).Sum
  $reportMdAdd = ($reportMd | Measure-Object Added -Sum).Sum
  $reportMdDel = ($reportMd | Measure-Object Deleted -Sum).Sum

  foreach ($v in 'reportCodeAdd','reportCodeDel','reportMdAdd','reportMdDel') {
    if ($null -eq (Get-Variable -Name $v -ValueOnly)) { Set-Variable -Name $v -Value 0 }
  }
}
else {
  $reportCodeAdd = $ExpectedCodeAdded
  $reportCodeDel = $ExpectedCodeDeleted
  $reportMdAdd = $ExpectedMdAdded
  $reportMdDel = $ExpectedMdDeleted
}

# ---- 2) recompute totals from git directly
$repoRoots = Get-ChildItem -Path $Root -Directory -Force -Recurse -Filter '.git' |
  Where-Object { Test-Path (Join-Path $_.FullName 'HEAD') } |
  ForEach-Object { Split-Path -Parent $_.FullName } |
  Sort-Object -Unique

$gitCodeAdd=0; $gitCodeDel=0; $gitMdAdd=0; $gitMdDel=0
$reposWithChanges=0

foreach ($repo in $repoRoots) {
  $has = $null
  try {
    $has = & git -C $repo log --since=$sinceIso --until=$untilIso --perl-regexp --author=$authorRegex --pretty=format:%H -n 1 2>$null
  } catch { continue }
  if ($LASTEXITCODE -ne 0) { continue }
  if (-not $has) { continue }

  $reposWithChanges++

  $numstat = $null
  try {
    $numstat = & git -C $repo log --since=$sinceIso --until=$untilIso --perl-regexp --author=$authorRegex --no-merges --numstat --pretty=format:'' 2>$null
  } catch { continue }
  if ($LASTEXITCODE -ne 0) { continue }

  foreach ($row in $numstat) {
    if ($row -match '^(?<add>\d+|-)\t(?<del>\d+|-)\t(?<path>.+)$') {
      if ($Matches.add -eq '-' -or $Matches.del -eq '-') { continue }
      $p = $Matches.path

      if (Test-IsExcludedPath -Path $p) { continue }

      $add = [int]$Matches.add
      $del = [int]$Matches.del

      $ext = ''
      try { $ext = [IO.Path]::GetExtension($p).ToLowerInvariant() } catch { $ext = '' }
      if ($ext -eq '.md') { $gitMdAdd += $add; $gitMdDel += $del }
      else { $gitCodeAdd += $add; $gitCodeDel += $del }
    }
  }
}

[pscustomobject]@{
  ReportPath = $ReportPath
  Range = "$($since.ToString('yyyy-MM-dd'))..$($until.ToString('yyyy-MM-dd'))"
  DaysBack = if ($PSCmdlet.ParameterSetName -eq 'DaysBack') { $DaysBack } else { $null }
  Root = $Root
  Authors = ($Authors -join ', ')
  Report_ParsedEntries = $parsed.Count
  Report_UniqueFiles = $agg.Count
  Report_DuplicatePaths = $dupes.Count
  Report_Totals_Code = "+$reportCodeAdd/-$reportCodeDel"
  Report_Totals_Md = "+$reportMdAdd/-$reportMdDel"
  Git_ReposWithChanges = $reposWithChanges
  Git_Totals_Code = "+$gitCodeAdd/-$gitCodeDel"
  Git_Totals_Md = "+$gitMdAdd/-$gitMdDel"
  TotalsMatch = (($gitCodeAdd -eq $reportCodeAdd) -and ($gitCodeDel -eq $reportCodeDel) -and ($gitMdAdd -eq $reportMdAdd) -and ($gitMdDel -eq $reportMdDel))
}

if (-not $SkipReportParse -and $dupes.Count -gt 0) {
  ''
  'Top duplicated paths in report:'
  $dupes | Select-Object -First 20 Name, Count
}
