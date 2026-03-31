$repoRoot = 'C:\opt\src\GUIDGen'
$mdcExclude = ':(exclude)*.mdc'

$hashResult = git -C $repoRoot log -1 --format=%H --since=2015-01-01 -- . $mdcExclude 2>$null
Write-Host "Current hash: [$hashResult]"

$reportPath = 'C:\opt\src\GitHist\Projects_all_20150101_20260311\GUIDGen\GitHistory.md'
$existingContent = Get-Content -LiteralPath $reportPath -Raw -ErrorAction SilentlyContinue
if ($existingContent -match 'Last commit hash:\s*(\S+)') {
    $storedHash = $Matches[1]
    Write-Host "Stored  hash: [$storedHash]"
    Write-Host "Match: $($storedHash -eq $hashResult)"
} else {
    Write-Host "No hash found in report"
}
