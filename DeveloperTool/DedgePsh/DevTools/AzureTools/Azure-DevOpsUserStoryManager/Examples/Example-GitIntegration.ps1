# Example: Git Integration - Auto-link commits to work items
# This can be used as a git hook or run manually after commits

param(
    [int]$WorkItemId,
    [string]$CommitHash,
    [switch]$AutoDetect
)

$scriptPath = Join-Path $PSScriptRoot "..\Azure-DevOpsUserStoryManager.ps1"

function Get-WorkItemFromBranch {
    # Extract work item ID from branch name (e.g., feature/12345-feature-name)
    $branch = git branch --show-current
    if ($branch -match '(\d{4,})') {
        return [int]$matches[1]
    }
    return $null
}

function Get-WorkItemFromCommit {
    param([string]$Hash)
    # Extract work item ID from commit message (e.g., "Fix #12345: Bug description")
    $message = git log -1 --pretty=%B $Hash
    if ($message -match '#(\d{4,})') {
        return [int]$matches[1]
    }
    return $null
}

# Auto-detect work item ID if not provided
if ($AutoDetect -and -not $WorkItemId) {
    Write-Host "Auto-detecting work item ID..." -ForegroundColor Yellow
    
    # Try branch name first
    $WorkItemId = Get-WorkItemFromBranch
    
    # Try commit message if still not found
    if (-not $WorkItemId -and $CommitHash) {
        $WorkItemId = Get-WorkItemFromCommit -Hash $CommitHash
    }
    
    if ($WorkItemId) {
        Write-Host "✓ Detected work item: $WorkItemId" -ForegroundColor Green
    }
    else {
        Write-Host "✗ Could not auto-detect work item ID" -ForegroundColor Red
        Write-Host "Please specify -WorkItemId manually or include work item ID in branch/commit" -ForegroundColor Yellow
        exit 1
    }
}

if (-not $WorkItemId) {
    Write-Host "Error: WorkItemId is required" -ForegroundColor Red
    exit 1
}

Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Git Integration - Linking Commits to Work Item               ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "Work Item: $WorkItemId`n" -ForegroundColor Yellow

# Get commit information
if (-not $CommitHash) {
    $CommitHash = git rev-parse HEAD
}

$commitMessage = git log -1 --pretty=%B $CommitHash
$commitAuthor = git log -1 --pretty=%an $CommitHash
$commitDate = git log -1 --pretty=%ad $CommitHash

Write-Host "Commit: $CommitHash" -ForegroundColor Gray
Write-Host "Author: $commitAuthor" -ForegroundColor Gray
Write-Host "Date: $commitDate" -ForegroundColor Gray
Write-Host "Message: $commitMessage`n" -ForegroundColor Gray

# Get changed files
$changedFiles = git diff-tree --no-commit-id --name-only -r $CommitHash

Write-Host "Changed files: $($changedFiles.Count)" -ForegroundColor Yellow

# Add commit comment
Write-Host "`n[1/2] Adding commit comment..." -ForegroundColor Green
$comment = @"
Git Commit: $CommitHash
Author: $commitAuthor
Date: $commitDate

Message: $commitMessage

Files changed: $($changedFiles.Count)
"@

& $scriptPath -WorkItemId $WorkItemId -Action Comment -Comment $comment

# Link changed files
Write-Host "[2/2] Linking changed files..." -ForegroundColor Green
$fileCount = 0
foreach ($file in $changedFiles) {
    try {
        & $scriptPath -WorkItemId $WorkItemId -Action Link `
            -Url $file `
            -Title "Modified in $($CommitHash.Substring(0, 7))"
        $fileCount++
    }
    catch {
        Write-Host "  ⚠ Failed to link: $file" -ForegroundColor Yellow
    }
}

Write-Host "`n✓ Git integration completed!" -ForegroundColor Green
Write-Host "Linked $fileCount files to work item $WorkItemId`n" -ForegroundColor Cyan

<#
.SYNOPSIS
Links git commits and changed files to Azure DevOps work items

.EXAMPLE
# Manual - specify work item and commit
.\Example-GitIntegration.ps1 -WorkItemId 12345 -CommitHash abc123

.EXAMPLE
# Auto-detect from branch name (e.g., feature/12345-login)
.\Example-GitIntegration.ps1 -AutoDetect

.EXAMPLE
# Auto-detect from latest commit message (e.g., "Fix #12345: Login bug")
.\Example-GitIntegration.ps1 -AutoDetect

.EXAMPLE
# Use as git post-commit hook - add to .git/hooks/post-commit:
#!/usr/bin/env pwsh
& "C:\opt\src\DedgePsh\DevTools\AdminTools\Azure-DevOpsUserStoryManager\Examples\Example-GitIntegration.ps1" -AutoDetect
#>
