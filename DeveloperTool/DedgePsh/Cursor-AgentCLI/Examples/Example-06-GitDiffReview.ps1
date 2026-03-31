<#
.SYNOPSIS
    Review the latest git changes in a repository.
    Demonstrates combining shell output with the model prompt.
#>
param(
    [string]$RepoPath = 'C:\opt\src\SystemAnalyzer',
    [int]$CommitCount = 1
)

$invoker = Join-Path $PSScriptRoot '..\Invoke-CursorAgent.ps1'

Push-Location $RepoPath
try {
    $diff = git diff "HEAD~$($CommitCount)" 2>&1 | Out-String
    $log  = git log --oneline -n $CommitCount 2>&1 | Out-String
} finally {
    Pop-Location
}

if (-not $diff.Trim()) {
    Write-Host "No changes found in the last $($CommitCount) commit(s)." -ForegroundColor Yellow
    exit 0
}

$prompt = @"
Review this git diff from the repository at $($RepoPath).

Recent commits:
$log

Diff:
$diff

Provide:
1. A summary of what changed
2. Any potential issues (bugs, security, performance)
3. Suggestions for improvement
"@

$result = & $invoker -Prompt $prompt -Model 'composer-2'

Write-Host "`n=== Git Diff Review ===" -ForegroundColor Cyan
Write-Host $result.Result
Write-Host "`nReview completed in $($result.DurationMs)ms" -ForegroundColor DarkGray
