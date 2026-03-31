<###
.SYNOPSIS
Create an AI-style narrative summary from a GitChangeActivityReport JSON.

.DESCRIPTION
Consumes the JSON produced by `New-GitChangeActivityReport.ps1 -WriteJson` and generates a
human-friendly overview ("AI generated report") focused on:
- overall stats and scope
- top repositories by churn
- hotspot folders/files
- anomalies (vendor/runtime folders, huge deletes/adds, duplicated file names)

This is **local / offline** summarization (no external AI API calls).
###>

[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [string] $InputJsonPath,

  [string] $OutputPath,

  [int] $TopRepos = 10,

  [int] $TopFilesPerRepo = 15
)

$ErrorActionPreference = 'Stop'

# Import GlobalFunctions for Write-LogMessage
Import-Module GlobalFunctions -Force

if (-not (Test-Path -LiteralPath $InputJsonPath)) {
  throw "InputJsonPath not found: $($InputJsonPath)"
}

if (-not $OutputPath) {
  $OutputPath = [IO.Path]::ChangeExtension($InputJsonPath, '.AI_SUMMARY.md')
}

$data = Get-Content -LiteralPath $InputJsonPath -Raw | ConvertFrom-Json

$repos = @($data.Repositories)

function ConvertTo-IntValue {
  param(
    [Parameter(ValueFromPipeline)]
    $Value,
    [int] $Default = 0
  )

  try {
    if ($null -eq $Value) { return $Default }

    # Occasionally the JSON shape (or pipeline) can produce arrays for scalar values.
    if ($Value -is [System.Array]) {
      if ($Value.Count -eq 0) { return $Default }
      $Value = $Value[0]
    }

    if ($Value -is [int]) { return $Value }
    if ($Value -is [long]) { return [int]$Value }
    if ($Value -is [double]) { return [int][math]::Round($Value) }
    if ($Value -is [decimal]) { return [int][math]::Round([double]$Value) }

    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) { return $Default }

    $n = 0
    if ([int]::TryParse($s, [ref]$n)) { return $n }
    return [int][math]::Round([double]$s)
  }
  catch {
    return $Default
  }
}

function ConvertTo-DateTimeValue {
  param(
    [Parameter(ValueFromPipeline)]
    $Value,
    [datetime] $Default = [datetime]::MinValue
  )

  try {
    if ($null -eq $Value) { return $Default }
    if ($Value -is [System.Array]) {
      if ($Value.Count -eq 0) { return $Default }
      $Value = $Value[0]
    }
    if ($Value -is [datetime]) { return $Value }
    return [datetime]$Value
  }
  catch {
    return $Default
  }
}

$topNRepos = (ConvertTo-IntValue $TopRepos -Default 10)
$topNFilesPerRepo = (ConvertTo-IntValue $TopFilesPerRepo -Default 15)
if ($topNRepos -lt 1) { $topNRepos = 1 }
if ($topNFilesPerRepo -lt 1) { $topNFilesPerRepo = 1 }

# Score repos by churn (adds+deletes, code only)
$repoScores = @(
  foreach ($r in $repos) {
    $codeAdded = ConvertTo-IntValue $r.Totals.Code.Added
    $codeDeleted = ConvertTo-IntValue $r.Totals.Code.Deleted
    [pscustomobject]@{
      Name = $r.Name
      Repo = $r.Repo
      CodeAdded = $codeAdded
      CodeDeleted = $codeDeleted
      MdAdded = ConvertTo-IntValue $r.Totals.Markdown.Added
      MdDeleted = ConvertTo-IntValue $r.Totals.Markdown.Deleted
      Churn = ($codeAdded + $codeDeleted)
    }
  }
) | Sort-Object Churn -Descending

$topRepoList = $repoScores | Select-Object -First $topNRepos

# Detect likely vendor/runtime folders (simple heuristics)
$vendorRx = '(?i)(\\|/)(node_modules|runtimes|site-packages|dist|build|bin|obj|packages)(\\|/)' 

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# AI generated change summary (offline)')
[void]$sb.AppendLine('')
[void]$sb.AppendLine(('Generated: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm')))
[void]$sb.AppendLine(('Input: `{0}`' -f $InputJsonPath))
[datetime]$from = (ConvertTo-DateTimeValue $data.Range.From -Default (Get-Date).Date)
[datetime]$to = (ConvertTo-DateTimeValue $data.Range.To -Default (Get-Date).Date)
[void]$sb.AppendLine(('Range: {0} .. {1}' -f $from.ToString('yyyy-MM-dd'), $to.ToString('yyyy-MM-dd')))
[void]$sb.AppendLine(('Root: `{0}`' -f $data.Root))
[void]$sb.AppendLine(('Authors: {0}' -f ($data.Authors -join ', ')))
[void]$sb.AppendLine('')

[void]$sb.AppendLine('## Executive summary')
[void]$sb.AppendLine('')
[void]$sb.AppendLine(('- Repositories changed: **{0}**' -f $data.Summary.RepositoriesWithChanges))
[void]$sb.AppendLine(('- Code (excl. *.md): **+{0} / -{1}** lines' -f $data.Summary.Code.Added, $data.Summary.Code.Deleted))
[void]$sb.AppendLine(('- Markdown: **+{0} / -{1}** lines' -f $data.Summary.Markdown.Added, $data.Summary.Markdown.Deleted))
[void]$sb.AppendLine('')

[void]$sb.AppendLine('## Top repositories by code churn')
[void]$sb.AppendLine('')
foreach ($r in $topRepoList) {
  [void]$sb.AppendLine(('- **{0}** — code **+{1}/-{2}** (churn {3}), md **+{4}/-{5}**' -f $r.Name, $r.CodeAdded, $r.CodeDeleted, $r.Churn, $r.MdAdded, $r.MdDeleted))
  [void]$sb.AppendLine(('  - Repo: `{0}`' -f $r.Repo))
}
[void]$sb.AppendLine('')

[void]$sb.AppendLine('## Hotspots & anomalies')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('- **Heuristics**: flags large churn files and likely vendor/runtime/generated folders (node_modules, runtimes, site-packages, bin/obj, dist/build).')
[void]$sb.AppendLine('')

foreach ($tr in $topRepoList) {
  $repoObj = $repos | Where-Object { $_.Repo -eq $tr.Repo } | Select-Object -First 1
  if (-not $repoObj) { continue }

  [void]$sb.AppendLine(('### {0}' -f $tr.Name))

  $files = @($repoObj.TopFiles) | Where-Object { $_.Path } | ForEach-Object {
    $p = [string]$_.Path
    $isVendor = $p -match $vendorRx
    [pscustomobject]@{
      Path = $p
      Added = ConvertTo-IntValue $_.Added
      Deleted = ConvertTo-IntValue $_.Deleted
      Commits = ConvertTo-IntValue $_.Commits
      LastDate = [string]$_.LastDate
      Headline = [string]$_.Headline
      Folder = [string]$_.Folder
      IsMarkdown = [bool]$_.IsMarkdown
      IsVendorLike = $isVendor
      Churn = ((ConvertTo-IntValue $_.Added) + (ConvertTo-IntValue $_.Deleted))
    }
  }

  $topFiles = $files | Sort-Object Churn -Descending | Select-Object -First $topNFilesPerRepo
  $vendorFiles = $topFiles | Where-Object { $_.IsVendorLike } | Select-Object -First 8

  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('**Top changed files (by churn):**')
  foreach ($f in $topFiles) {
    $kind = if ($f.IsMarkdown) { 'md' } else { 'code' }
    $hl = if ([string]::IsNullOrWhiteSpace($f.Headline)) { '(no headline detected)' } else { $f.Headline }
    $vendorNote = if ($f.IsVendorLike) { ' [vendor/runtime-like]' } else { '' }
    [void]$sb.AppendLine(('- `{0}` — {1} +{2}/-{3}, commits {4}, last {5}{6}' -f $f.Path, $kind, $f.Added, $f.Deleted, $f.Commits, $f.LastDate, $vendorNote))
    [void]$sb.AppendLine(('  - Headline: {0}' -f $hl))
  }

  if ($vendorFiles.Count -gt 0) {
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('**Note:** This repo has high churn in folders that look like vendored/generated/runtime content. If unintended, consider excluding these from commits or adding repo rules.')
  }

  [void]$sb.AppendLine('')
}

$sb.ToString() | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-LogMessage "AI summary written: $($OutputPath)" -Level INFO
Write-Output $OutputPath
