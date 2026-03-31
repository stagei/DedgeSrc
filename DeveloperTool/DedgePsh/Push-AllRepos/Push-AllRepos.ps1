<#
.SYNOPSIS
    Finds all git repos under a root folder and commits + pushes any uncommitted changes.

.DESCRIPTION
    Scans all immediate subfolders under -Root for git repositories.
    For each repo with uncommitted changes (tracked or untracked):
    1. git add -A
    2. git commit with an auto-generated message based on changed files
    3. git push
    4. Verifies the push succeeded

    Repos with clean working trees are skipped.

.PARAMETER Root
    Root folder to scan for git repos. Default: C:\opt\src

.PARAMETER DryRun
    Show what would be committed without actually doing it.

.EXAMPLE
    .\Push-AllRepos.ps1
    .\Push-AllRepos.ps1 -Root "C:\opt\src" -DryRun
#>

[CmdletBinding()]
param(
    [string]$Root = "C:\opt\src",
    [switch]$DryRun
)
$ErrorActionPreference = "Stop"

Import-Module GlobalFunctions -Force

Set-OverrideAppDataFolder -Path (Get-ApplicationDataPath)
Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_STARTED

try {
    if (-not (Test-Path $Root -PathType Container)) {
        Write-LogMessage "Root folder not found: $($Root)" -Level ERROR
        Write-LogMessage "Root folder not found: $($Root)" -Level JOB_FAILED
        exit 1
    }

    # ── Discover git repos (immediate subfolders with a .git directory) ──────────
    $repos = Get-ChildItem -Path $Root -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName '.git') -PathType Container } |
        Sort-Object Name

    if ($repos.Count -eq 0) {
        Write-LogMessage "No git repositories found under $($Root)" -Level WARN
        Write-LogMessage "No git repositories found under $($Root)" -Level JOB_COMPLETED
        exit 0
    }

    Write-LogMessage "Found $($repos.Count) git repo(s) under $($Root)" -Level INFO

    $stats = @{ Skipped = 0; Committed = 0; Failed = 0 }

    foreach ($repo in $repos) {
        $repoPath = $repo.FullName
        $repoName = $repo.Name

        # Check for uncommitted changes (porcelain output is empty when clean)
        $status = git -C $repoPath status --porcelain 2>&1
        if (-not $status) {
            Write-LogMessage "[$($repoName)] Clean — skipping" -Level INFO
            $stats.Skipped++
            continue
        }

        # Count changes for summary
        $changedFiles = @($status)
        $fileCount = $changedFiles.Count

        # Build a commit message from the changed file names
        $changeTypes = @{ A = 0; M = 0; D = 0; R = 0; U = 0 }
        foreach ($line in $changedFiles) {
            $code = $line.Substring(0, 2).Trim()
            switch -Wildcard ($code) {
                'A*'  { $changeTypes.A++ }
                'M*'  { $changeTypes.M++ }
                'D*'  { $changeTypes.D++ }
                'R*'  { $changeTypes.R++ }
                '??'  { $changeTypes.U++ }
                default { $changeTypes.M++ }
            }
        }

        $parts = @()
        if ($changeTypes.A -gt 0) { $parts += "$($changeTypes.A) added" }
        if ($changeTypes.M -gt 0) { $parts += "$($changeTypes.M) modified" }
        if ($changeTypes.D -gt 0) { $parts += "$($changeTypes.D) deleted" }
        if ($changeTypes.R -gt 0) { $parts += "$($changeTypes.R) renamed" }
        if ($changeTypes.U -gt 0) { $parts += "$($changeTypes.U) new" }
        $changeSummary = $parts -join ', '

        $commitMsg = "chore($($repoName)): $($changeSummary) ($($fileCount) file$(if ($fileCount -ne 1) { 's' }))"

        Write-LogMessage "[$($repoName)] $($fileCount) change(s): $($changeSummary)" -Level INFO

        if ($DryRun) {
            Write-LogMessage "[$($repoName)] DRY RUN — would commit: $($commitMsg)" -Level INFO
            foreach ($line in $changedFiles) {
                Write-Host "    $line" -ForegroundColor DarkGray
            }
            $stats.Skipped++
            continue
        }

        try {
            # Stage all
            git -C $repoPath add -A 2>&1 | Out-Null

            # Commit
            $commitOutput = git -C $repoPath commit -m $commitMsg 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-LogMessage "[$($repoName)] Commit failed: $($commitOutput)" -Level ERROR
                $stats.Failed++
                continue
            }
            Write-LogMessage "[$($repoName)] Committed: $($commitMsg)" -Level INFO

            # Push
            $pushOutput = git -C $repoPath push 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-LogMessage "[$($repoName)] Push failed: $($pushOutput)" -Level ERROR
                $stats.Failed++
                continue
            }

            # Verify
            $verifyStatus = git -C $repoPath status --branch --porcelain 2>&1
            if ($verifyStatus -match 'ahead') {
                Write-LogMessage "[$($repoName)] WARNING: Still ahead of remote after push" -Level WARN
                $stats.Failed++
            } else {
                Write-LogMessage "[$($repoName)] Pushed and verified" -Level INFO
                $stats.Committed++
            }
        }
        catch {
            Write-LogMessage "[$($repoName)] Error: $($_.Exception.Message)" -Level ERROR
            $stats.Failed++
        }
    }

    # ── Summary ──────────────────────────────────────────────────────────────────
    $summary = "Committed: $($stats.Committed)  Skipped: $($stats.Skipped)  Failed: $($stats.Failed)"
    Write-LogMessage $summary -Level INFO

    if ($stats.Failed -gt 0) {
        Write-LogMessage $summary -Level JOB_FAILED
    }
    else {
        Write-LogMessage $summary -Level JOB_COMPLETED
    }
}
catch {
    Write-LogMessage "Unexpected error: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage "Push-AllRepos failed" -Level JOB_FAILED
    exit 1
}
