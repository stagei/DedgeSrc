# Composer message: Run this powershell script for windows in composer agent, and use the output file to generate relase info. Only run script, do not generate a powershell script

# Composer Context Generator for Release Description
# This script uses Cursor agent commands to gather solution information

# Add parameter for solution root path
param(
    [Parameter(Position = 0)]
    [string]$TargetPath,
    [Parameter(Position = 1)]
    [string]$Days,
    [Parameter(Position = 2)]
    [switch]$FindGitReposRecursive,
    [Parameter(Position = 3)]
    [switch]$CurrentUserOnly
)

function Write-ErrorDetails {
    param (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [string]$Context = "",
        [switch]$Warning
    )

    $details = @"

=== Error Details ===
Context: $Context
Line Number: $($ErrorRecord.InvocationInfo.ScriptLineNumber)
Line: $($ErrorRecord.InvocationInfo.Line.Trim())
Error Message: $($ErrorRecord.Exception.Message)
Command: $($ErrorRecord.InvocationInfo.MyCommand)
Script: $($ErrorRecord.InvocationInfo.ScriptName)
Position: $($ErrorRecord.InvocationInfo.PositionMessage)
Category: $($ErrorRecord.CategoryInfo.Category)
"@

    if ($Warning) {
        Write-Error $details
    }
    else {
        Write-Error $details
    }

    # Add to verbose output for debugging
    Write-Verbose "Stack Trace: $($ErrorRecord.ScriptStackTrace)"
}

function Get-TargetGitPath ([string]$RepoPath, [string]$TargetPath) {
    if ($RepoPath -eq $TargetPath) {
        $targetGitPath = ""
    }
    else {
        $targetGitPath = $TargetPath.Split($RepoPath)[1]
        $targetGitPath = $targetGitPath.TrimStart("\")
        $targetGitPath = $targetGitPath.TrimEnd("\")
        $targetGitPath = $targetGitPath.Replace("\", "/")
    }
    return $targetGitPath
}

function Test-FileForContext {
    param (
        [string]$FilePath,
        [string]$TargetPath
    )

    # Skip files in node_modules
    if ($filePath -match "node_modules") {
        Write-Verbose "Skipping node_modules file: $filePath"
        return $false
    }

    # Skip files in assistant_snippets
    if ($filePath -like "*assistant_snippet*") {
        Write-Verbose "Skipping assistant_snippet file: $filePath"
        return $false
    }

    # Skip image files (common formats)
    if ($filePath -match "\.(png|jpg|jpeg|gif|bmp|ico|svg|webp|tiff|psd|raw|heif|eps|ai)$") {
        Write-Verbose "Skipping image file: $filePath"
        return $false
    }

    # Keep script files, but skip executable files
    if ($filePath -match "\.(exe|dll|bin|dat|db|o|so|dylib|lib|a|class|jar|war|ear|zip|tar|gz|7z|rar|iso|dmg|pkg|msi|app|sys|drv|dat)$") {
        Write-Verbose "Skipping executable/binary file: $filePath"
        return $false
    }

    # Skip binary files and large files
    $gitAttributes = git check-attr -a $filePath
    if ($gitAttributes -match "binary: set" -or (Test-Path $filePath -PathType Leaf) -and (Get-Item $filePath -ErrorAction SilentlyContinue).Length -gt 1MB) {
        Write-Verbose "Skipping binary or large file: $filePath"
        return $false
    }

    return $true
}

function Get-CommitHistory {
    param (
        [string]$RepoPath,
        [string]$TargetPath,
        [string]$Since,
        [bool]$CurrentUserOnly
    )

    $targetGitPath = Get-TargetGitPath -RepoPath $RepoPath -TargetPath $TargetPath

    $commits = @()

    if ($CurrentUserOnly) {
        $currentUser = git config user.name
        $rawCommits = git log --since=$Since --numstat --format='%h|%an|%ad|%s' --numstat --date=iso --author=$currentUser
    }
    else {
        $rawCommits = git log --since=$Since --numstat --format='%h|%an|%ad|%s' --numstat --date=iso
    }

    $totalCommits = ($rawCommits | Where-Object { $_ -match '^[a-f0-9]+\|' }).Count
    $currentCommit = 0

    $currentCommitInfo = $null
    $files = @()

    foreach ($line in $rawCommits) {
        # If line starts with commit hash pattern
        if ($line -match '^([a-f0-9]+)\|(.+)\|(.+)\|(.+)$') {
            # If we have a previous commit, add it to the array
            if ($currentCommitInfo) {
                $currentCommitInfo.Files = $files
                $commits += $currentCommitInfo
                $files = @()
            }

            $currentCommitInfo = @{
                Hash         = $matches[1]
                Author       = $matches[2]
                Date         = $matches[3]
                Message      = $matches[4]
                Files        = @()
                AddedLines   = 0
                DeletedLines = 0
            }

            $currentCommit++
            Write-Progress -Activity "Processing Commits" -Status "Commit $currentCommit of $totalCommits" -PercentComplete (($currentCommit / $totalCommits) * 100)
        }
        # If line matches the numstat pattern (additions deletions filename)
        elseif ($line -match '^\s*(\d+|-)\s+(\d+|-)\s+(.+)$' -and $currentCommitInfo) {
            $added = if ($matches[1] -eq '-') { 0 } else { [int]$matches[1] }
            $deleted = if ($matches[2] -eq '-') { 0 } else { [int]$matches[2] }
            $filename = $matches[3]

            # Filter files based on targetGitPath if specified
            if ($targetGitPath -ne "") {
                if (-not $filename.ToUpper().StartsWith($targetGitPath.ToUpper())) {
                    continue
                }
            }

            # Create full file paths
            $gitFilePath = $filename
            $fullFilePath = Join-Path $RepoPath $filename

            $fileInfo = @{
                FileName     = $filename
                GitFilePath  = $gitFilePath
                FullFilePath = $fullFilePath
                Added        = $added
                Deleted      = $deleted
            }

            $files += $fileInfo
            $currentCommitInfo.AddedLines += $added
            $currentCommitInfo.DeletedLines += $deleted
        }
    }

    # Add the last commit
    if ($currentCommitInfo) {
        $currentCommitInfo.Files = $files
        $commits += $currentCommitInfo
    }

    # Remove all commits that have no files
    $commits = $commits | Where-Object { $_.Files.Count -gt 0 }

    return $commits
}

# Add this function after Get-UncommittedChanges
function Get-UncommittedChanges {
    param (
        [string]$RepoPath,
        [string]$TargetPath
    )

    Write-Log "Getting uncommitted changes for repository: $RepoPath"
    $targetGitPath = Get-TargetGitPath -RepoPath $RepoPath -TargetPath $TargetPath
    try {
        # Save current location
        $previousLocation = Get-Location
        Set-Location $RepoPath

        $changes = @{
            staged       = @{
                added    = @()
                modified = @()
                deleted  = @()
            }
            unstaged     = @{
                added    = @()
                modified = @()
                deleted  = @()
            }
            untracked    = @()
            stats        = @{
                files_changed = 0
                insertions    = 0
                deletions     = 0
            }
            diff_content = $null  # Add field for diff content
        }

        # Get staged and unstaged changes
        $status = git status --porcelain
        foreach ($line in $status) {
            $index = $line[0]
            $worktree = $line[1]
            $file = $line.Substring(3)

            # Filter files based on targetGitPath if specified
            if ($targetGitPath -ne "") {
                if (-not $file.ToUpper().StartsWith($targetGitPath.ToUpper())) {
                    continue
                }
            }

            # Handle staged changes
            switch ($index) {
                'A' { $changes.staged.added += $file }
                'M' { $changes.staged.modified += $file }
                'D' { $changes.staged.deleted += $file }
            }

            # Handle unstaged changes
            switch ($worktree) {
                '?' { $changes.untracked += $file }
                'M' { $changes.unstaged.modified += $file }
                'D' { $changes.unstaged.deleted += $file }
            }
        }

        # Get detailed diff stats
        $diffStats = git diff --numstat
        foreach ($line in $diffStats) {
            if ($line -match '^(\d+)\s+(\d+)\s+(.+)$') {
                $file = $matches[3]

                # Filter files based on targetGitPath if specified
                if ($targetGitPath -ne "") {
                    if (-not $file.ToUpper().StartsWith($targetGitPath.ToUpper())) {
                        continue
                    }
                }

                $changes.stats.insertions += [int]$matches[1]
                $changes.stats.deletions += [int]$matches[2]
                $changes.stats.files_changed++
            }
        }

        # Get staged diff stats
        $stagedDiffStats = git diff --cached --numstat
        foreach ($line in $stagedDiffStats) {
            if ($line -match '^(\d+)\s+(\d+)\s+(.+)$') {
                $file = $matches[3]

                # Filter files based on targetGitPath if specified
                if ($targetGitPath -ne "") {
                    if (-not $file.ToUpper().StartsWith($targetGitPath.ToUpper())) {
                        continue
                    }
                }

                $changes.stats.insertions += [int]$matches[1]
                $changes.stats.deletions += [int]$matches[2]
                $changes.stats.files_changed++
            }
        }

        # Get diff content
        $changes.diff_content = Get-UncommittedDiffContent -RepoPath $RepoPath

        return $changes
    }
    catch {
        Write-ErrorDetails -ErrorRecord $_ -Context "Failed to get uncommitted changes"
        return $null
    }
    finally {
        # Restore previous location
        Set-Location $previousLocation
    }
}

# Add this function after Get-UncommittedChanges
function Get-UncommittedChangesSummary {
    param (
        [Parameter(Mandatory = $true)]
        [object]$Changes
    )

    if ($null -eq $Changes) {
        return "No uncommitted changes found."
    }

    $summary = @()

    # Add stats summary
    $summary += "Changes Summary:"
    $summary += "- Files Changed: $($Changes.stats.files_changed)"
    $summary += "- Lines Added: $($Changes.stats.insertions)"
    $summary += "- Lines Deleted: $($Changes.stats.deletions)"

    # Add staged changes
    if ($Changes.staged.added.Count -gt 0 -or
        $Changes.staged.modified.Count -gt 0 -or
        $Changes.staged.deleted.Count -gt 0) {

        $summary += "`nStaged Changes:"
        if ($Changes.staged.added.Count -gt 0) {
            $summary += "- Added ($($Changes.staged.added.Count)):"
            $Changes.staged.added | ForEach-Object { $summary += "  * $_" }
        }
        if ($Changes.staged.modified.Count -gt 0) {
            $summary += "- Modified ($($Changes.staged.modified.Count)):"
            $Changes.staged.modified | ForEach-Object { $summary += "  * $_" }
        }
        if ($Changes.staged.deleted.Count -gt 0) {
            $summary += "- Deleted ($($Changes.staged.deleted.Count)):"
            $Changes.staged.deleted | ForEach-Object { $summary += "  * $_" }
        }
    }

    # Add unstaged changes
    if ($Changes.unstaged.modified.Count -gt 0 -or
        $Changes.unstaged.deleted.Count -gt 0) {

        $summary += "`nUnstaged Changes:"
        if ($Changes.unstaged.modified.Count -gt 0) {
            $summary += "- Modified ($($Changes.unstaged.modified.Count)):"
            $Changes.unstaged.modified | ForEach-Object { $summary += "  * $_" }
        }
        if ($Changes.unstaged.deleted.Count -gt 0) {
            $summary += "- Deleted ($($Changes.unstaged.deleted.Count)):"
            $Changes.unstaged.deleted | ForEach-Object { $summary += "  * $_" }
        }
    }

    # Add untracked files
    if ($Changes.untracked.Count -gt 0) {
        $summary += "`nUntracked Files ($($Changes.untracked.Count)):"
        $Changes.untracked | ForEach-Object { $summary += "  * $_" }
    }

    return $summary -join "`n"
}
function Get-UncommittedDiffContent {
    param (
        [string]$RepoPath
    )

    Write-Log "Getting diff content for uncommitted changes in: $RepoPath"

    try {
        # Save current location
        $previousLocation = Get-Location
        Set-Location $RepoPath

        $diffContent = @{
            unstaged = ""
            staged   = ""
        }

        # Get unstaged changes diff
        $unstagedDiff = git diff
        if ($unstagedDiff) {
            $diffContent.unstaged = $unstagedDiff
        }

        # Get staged changes diff
        $stagedDiff = git diff --cached
        if ($stagedDiff) {
            $diffContent.staged = $stagedDiff
        }

        return $diffContent
    }
    catch {
        Write-ErrorDetails -ErrorRecord $_ -Context "Failed to get diff content"
        return $null
    }
    finally {
        # Restore previous location
        Set-Location $previousLocation
    }
}

# Add helper functions right after the param block
function Start-CursorProcess {
    param(
        [string]$TargetPath,
        [string]$WorkingDirectory,
        [string]$Instructions,
        [bool]$IsHistoryMode = $false
    )

    try {
        $contextFile = Join-Path $TargetPath "composer_context.json"
        # Check if file exists
        if (-not (Test-Path $contextFile -PathType Leaf)) {
            Write-Error "Context file not found: $contextFile"
            return
        }

        # Get the filename for display
        #$filename = "composer_context.json"
        # Create paths for result files

        $pasteInfoFile = Join-Path $TargetPath "composer_instructions.txt"
        $historyModeMessage = @"
=== OPERATOR INSTRUCTIONS ===
1. Open the file in Cursor
2. Create a new chat
3. Copy and paste the following text into Cursor chat:

=== PASTE THIS INTO CURSOR ===
Create a new file composer_result_file.md based on context file composer_context.json and instructions below:
Use the file as context to generate a Git repository analysis report.

Cursor Agent Composer Instructions:
$Instructions

## Input Data
composer_instructions.txt

## Output Data
composer_result_file.md

=== END OF PASTE ===

The report will be generated based on the JSON data in the context file.
Wait for Cursor to analyze and generate the complete report.
"@

        # extract the pasteinfo from the historyModeMessage
        $pasteInfo = $historyModeMessage -replace '=== PASTE THIS INTO CURSOR ===', '' -replace '=== END OF PASTE ===', ''
        #save pastinfo to a textfile based on the filename
        $pasteInfo | Out-File $pasteInfoFile -Encoding UTF8

        $gitHistoryMessage = $historyModeMessage  # Use the same format for both modes

        if ($IsHistoryMode) {
            Write-Host $historyModeMessage -ForegroundColor Green
        }
        else {
            Write-Host $gitHistoryMessage -ForegroundColor Green
        }

        # Try to start Cursor if available
        $cursorPath = "cursor"
        if (Get-Command $cursorPath -ErrorAction SilentlyContinue) {
            Start-Process $cursorPath -ArgumentList $contextFile
            # Wait for 2 seconds
            Start-Sleep -Seconds 4
            Start-Process $cursorPath -ArgumentList $pasteInfoFile
        }
    }
    catch {
        Write-Warning "Failed to start Cursor process: $_"
        # Continue execution since this is not critical
    }
}

function Write-Log {
    param(
        [string]$Message,
        [object]$Exception,
        [string]$Context
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"

    if ($Exception) {
        $logMessage += "`nException: $($Exception.ToString())"
        if ($Context) {
            $logMessage += "`nContext: $Context"
        }
        if ($Exception.StackTrace) {
            $logMessage += "`nStack Trace: $($Exception.StackTrace)"
        }
    }

    Write-Host $logMessage -ForegroundColor Yellow

    # If running in verbose mode, output more details
    if ($VerbosePreference -eq 'Continue') {
        Write-Verbose $logMessage
    }
}

function Test-GitStatus {
    param (
        [string]$RepoPath,
        [string]$LogPath = (Join-Path $env:TEMP "GitStatus_$(Get-Date -Format 'yyyyMMdd_HHmmss').log")
    )

    Write-Log "Checking git status for repository: $RepoPath"

    try {
        # Save current location
        $previousLocation = Get-Location
        Set-Location $RepoPath

        # Execute git status and redirect output to log file
        $output = git status 2>&1 | Tee-Object -FilePath $LogPath

        # Check for fatal errors
        if ($output -match "fatal" -or $LASTEXITCODE -ne 0) {
            $errorMessage = Get-Content $LogPath -Raw
            Write-Log "Git status contains fatal error: $errorMessage"
            throw "Git operation failed: $errorMessage"
        }

        Write-Log "Git status check passed"
        return $true
    }
    catch {
        Write-Log -Exception $_ -Context "Git status check failed for $RepoPath"
        return $false
    }
    finally {
        # Restore previous location
        Set-Location $previousLocation
    }
}

# Help parameter handling
if ([string]::IsNullOrEmpty($TargetPath) -or
    $TargetPath -eq "?" -or
    $TargetPath -like "-help*" -or
    $TargetPath -like "--help*") {

    # Get the script's directory
    $scriptPath = $PSScriptRoot
    $readmePath = Join-Path $scriptPath "readme.md"

    # Try to open readme with default app
    if (Test-Path $readmePath) {
        Start-Process $readmePath
    }
    else {
        Write-Warning "README.md not found at: $readmePath"
    }
    exit 0
}

# Add this function at the start of the script, after the param block
function Test-GitMsgCommand {
    $windowsAppsPath = Join-Path $env:OptPath "QuickRun"Join-Path $env:OptPath "QuickRun"
    $gitmsgPath = Join-Path $windowsAppsPath "gitmsg.bat"

    if (-not (Test-Path $gitmsgPath)) {
        Write-Verbose "Creating gitmsg.bat in Windows Apps directory..."
        try {
            $scriptPath = Join-Path $PSScriptRoot "CursorReleaseContextGenerator.ps1"
            $batContent = @"
@echo off
pwsh.exe -NoProfile -ExecutionPolicy remotesigned -Command "$scriptPath %1 %2"
"@
            $batContent | Out-File -FilePath $gitmsgPath -Encoding ASCII -Force
            Write-Host "Created gitmsg command in $windowsAppsPath" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to create gitmsg.bat: $_"
        }
    }
}

# Add this function after the existing Test-GitMsgCommand function
function Test-GitHistCommand {
    $windowsAppsPath = Join-Path $env:OptPath "QuickRun"Join-Path $env:OptPath "QuickRun"
    $githistPath = Join-Path $windowsAppsPath "githist.bat"

    if (-not (Test-Path $githistPath)) {
        Write-Verbose "Creating githist.bat in Windows Apps directory..."
        try {
            $scriptPath = Join-Path $PSScriptRoot "CursorReleaseContextGenerator.ps1"
            $batContent = @"
@echo off
pwsh.exe -NoProfile -ExecutionPolicy remotesigned -Command "$scriptPath -HistoryMode %1 %2"
"@
            $batContent | Out-File -FilePath $githistPath -Encoding ASCII -Force
            Write-Host "Created githist command in $windowsAppsPath" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to create githist.bat: $_"
        }
    }
}

# Add new function to find repositories recursively
function Find-GitRepositoriesRecursive {
    param (
        [string]$BasePath
    )

    $repositories = @()
    Write-Verbose "Scanning directory: $BasePath"

    try {
        # Skip if current directory starts with 'old' or '_old' (case-insensitive)
        $dirName = Split-Path $BasePath -Leaf
        if ($dirName -match '^_?old') {
            Write-Verbose "Skipping old directory: $BasePath"
            return $repositories
        }

        # Check if current directory is a git repository first
        if (Test-Path (Join-Path $BasePath ".git") -PathType Container) {
            Write-Verbose "Found git repository: $BasePath"
            $repositories += $BasePath
        }

        # Get all directories except system folders and 'old' folders
        $directories = Get-ChildItem -Path $BasePath -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -notmatch '^(\.git|\.vs|node_modules|bin|obj|packages|Debug|Release|TestResults|.vscode|.idea|_cursor_release_context)$' -and
            $_.Name -notmatch '^_?old' -and # Only match at start of name
            -not $_.Attributes.HasFlag([System.IO.FileAttributes]::System) -and
            -not $_.Attributes.HasFlag([System.IO.FileAttributes]::Hidden)
        }

        # Process each directory
        foreach ($dir in $directories) {
            try {
                Write-Verbose "Checking directory: $($dir.FullName)"
                if (Test-Path -Path $dir.FullName -ErrorAction Stop) {
                    $subRepos = Find-GitRepositoriesRecursive -BasePath $dir.FullName
                    if ($subRepos) {
                        $repositories += $subRepos
                    }
                }
            }
            catch {
                Write-Warning "Skipping inaccessible directory $($dir.FullName): $_"
                continue
            }
        }
    }
    catch {
        Write-Warning "Error scanning directory $BasePath : $_"
    }

    return $repositories | Select-Object -Unique
}

# Add these helper functions for performance and progress tracking
function Write-ProgressHelper {
    param(
        [string]$Activity,
        [string]$Status,
        [int]$PercentComplete,
        [int]$Id = 0
    )

    Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete -Id $Id
}

# Add this function before Get-RepositoryStatistics
function Convert-FileTypeStats {
    param (
        [Parameter(Mandatory = $true)]
        [object]$FileTypes,
        [string]$Context = "file type conversion"
    )

    Write-Verbose "Starting file type conversion"
    $result = [PSCustomObject]@{}

    try {
        # Get all keys first to avoid enumeration issues
        $typeKeys = @($FileTypes.Keys)
        Write-Verbose "Processing $($typeKeys.Count) file types"

        foreach ($type in $typeKeys) {
            if ($null -eq $type) { continue }

            try {
                $stats = $FileTypes[$type]
                Write-Verbose "Converting stats for type: $type"

                # Create standardized object with default values
                # Add the property to the PSCustomObject directly
                Add-Member -InputObject $result -MemberType NoteProperty -Name $type -Value ([PSCustomObject]@{
                        count     = [int]($stats.count ?? 0)
                        changes   = [int]($stats.changes ?? 0)
                        additions = [int]($stats.additions ?? 0)
                        deletions = [int]($stats.deletions ?? 0)
                        files     = @()
                    })
            }
            catch {
                Write-Warning "Failed to convert file type '$type': $($_.Exception.Message)"
                continue
            }
        }

        Write-Verbose "Successfully converted all file types"
        return $result
    }
    catch {
        Write-ErrorDetails -ErrorRecord $_ -Context $Context
        return [PSCustomObject]@{}
    }
}

# Update the Get-RepositoryStatistics function to ensure string keys
function Get-RepositoryStatistics {
    param(
        [Parameter(Position = 0)]
        [string]$RepoPath,
        [Parameter(Position = 1)]
        [datetime]$FromDate,
        [Parameter(Position = 2)]
        [string]$TargetPath,
        [Parameter(Position = 3)]
        [bool]$CurrentUserOnly,
        [Parameter(Position = 4)]
        [object]$CommitHistory
    )

    Set-Location $RepoPath
    Get-TargetGitPath -RepoPath $RepoPath -TargetPath $TargetPath
    # Get current user's git config name
    $currentUser = git config user.name
    if (-not $currentUser) {
        $currentUser = $env:USERNAME
    }
    if ($CurrentUserOnly) {
        Write-Host "Analyzing your changes for $currentUser" -ForegroundColor Yellow
    }
    else {
        Write-Host "Analyzing changes for all users" -ForegroundColor Yellow
    }

    $stats = @{
        total_commits        = 0
        total_lines_affected = 0
        authors              = @{}
        file_types           = @{}
        commit_times         = @{}
        impact               = @{
            additions            = 0
            deletions            = 0
            total_lines_affected = 0
        }
    }

    # Process the pre-filtered commit history
    foreach ($commit in $CommitHistory) {
        try {
            # Get or create author stats
            $author = $commit.Author
            if ([string]::IsNullOrWhiteSpace($author)) {
                Write-Verbose "Found invalid author name, using Unknown"
                $author = "Unknown"
            }

            if (-not $stats.authors[$author]) {
                $stats.authors[$author] = @{
                    name                 = $author
                    is_current_user      = ($author -eq $currentUser)
                    commits              = 0
                    additions            = 0
                    deletions            = 0
                    total_lines_affected = 0
                    files_changed        = @{}
                    commit_times         = [ordered]@{}
                    recent_commits       = @()
                }
            }

            # Update author stats
            $stats.authors[$author].commits++
            $stats.total_commits++

            # Track commit details
            $stats.authors[$author].recent_commits += @{
                hash    = $commit.Hash
                date    = [datetime]::Parse($commit.Date)
                message = $commit.Message
            }

            # Update commit time distribution
            $commitDate = [datetime]::Parse($commit.Date)
            $hour = $commitDate.Hour.ToString("00")

            if (-not $stats.authors[$author].commit_times[$hour]) {
                $stats.authors[$author].commit_times[$hour] = 0
            }
            $stats.authors[$author].commit_times[$hour]++

            if (-not $stats.commit_times[$hour]) {
                $stats.commit_times[$hour] = 0
            }
            $stats.commit_times[$hour]++

            # Process files in commit
            foreach ($file in $commit.Files) {
                $fileType = [System.IO.Path]::GetExtension($file.FileName)

                # Update file type statistics
                if (-not $stats.file_types[$fileType]) {
                    $stats.file_types[$fileType] = @{
                        count     = 0
                        changes   = 0
                        additions = 0
                        deletions = 0
                    }
                }
                $stats.file_types[$fileType].count++
                $stats.file_types[$fileType].changes++
                $stats.file_types[$fileType].additions += $file.Added
                $stats.file_types[$fileType].deletions += $file.Deleted

                # Update author's impact
                $stats.authors[$author].additions += $file.Added
                $stats.authors[$author].deletions += $file.Deleted
                $stats.authors[$author].total_lines_affected += ($file.Added + $file.Deleted)

                # Track author's file changes
                if (-not $stats.authors[$author].files_changed[$file.FileName]) {
                    $stats.authors[$author].files_changed[$file.FileName] = @{
                        changes   = 0
                        additions = 0
                        deletions = 0
                    }
                }
                $stats.authors[$author].files_changed[$file.FileName].changes++
                $stats.authors[$author].files_changed[$file.FileName].additions += $file.Added
                $stats.authors[$author].files_changed[$file.FileName].deletions += $file.Deleted

                # Update total impact
                $stats.impact.additions += $file.Added
                $stats.impact.deletions += $file.Deleted
                $stats.total_lines_affected += ($file.Added + $file.Deleted)
            }
        }
        catch {
            Write-Warning "Error processing commit $($commit.Hash): $($_.Exception.Message)"
            continue
        }
    }

    # Convert all hashtables to PSCustomObjects for proper serialization
    try {
        $convertedAuthors = @()
        foreach ($authorEntry in $stats.authors.GetEnumerator()) {
            try {
                $author = $authorEntry.Value

                # Validate author name
                if ([string]::IsNullOrWhiteSpace($author.name)) {
                    Write-Warning "Skipping author with empty name"
                    continue
                }

                Write-Verbose "Converting author data for: $($author.name)"

                # Initialize default values for all properties
                $authorData = @{
                    PSTypeName           = 'GitAuthorStats'
                    name                 = [string]($author.name)
                    is_current_user      = $false
                    commits              = 0
                    additions            = 0
                    deletions            = 0
                    total_lines_affected = 0
                    files_changed        = @{}
                    commit_times         = @{}
                    recent_commits       = @()
                }

                # Safely convert commit_times
                if ($author.commit_times) {
                    $commitTimes = @{}
                    foreach ($hour in $author.commit_times.Keys) {
                        if ($null -ne $hour) {
                            $commitTimes[$hour] = [int]($author.commit_times[$hour])
                        }
                    }
                    $authorData.commit_times = [PSCustomObject]$commitTimes
                }

                # Safely convert files_changed
                if ($author.files_changed) {
                    $filesChanged = @{}
                    foreach ($file in $author.files_changed.Keys) {
                        if ($null -ne $file) {
                            try {
                                $fileData = $author.files_changed[$file]
                                $filesChanged[$file] = [PSCustomObject]@{
                                    changes   = [int]($fileData.changes ?? 0)
                                    additions = [int]($fileData.additions ?? 0)
                                    deletions = [int]($fileData.deletions ?? 0)
                                }
                            }
                            catch {
                                Write-Warning "Failed to convert file data for '$file' in author '$($author.name)': $($_.Exception.Message)"
                                continue
                            }
                        }
                    }
                    $authorData.files_changed = [PSCustomObject]$filesChanged
                }

                # Safely convert recent_commits
                if ($author.recent_commits) {
                    $recentCommits = @()
                    foreach ($commit in $author.recent_commits) {
                        if ($null -ne $commit) {
                            try {
                                $recentCommits += [PSCustomObject]@{
                                    hash    = [string]($commit.hash ?? '')
                                    date    = $commit.date ?? (Get-Date)
                                    message = [string]($commit.message ?? '')
                                }
                            }
                            catch {
                                Write-Warning "Failed to convert commit data in author '$($author.name)': $($_.Exception.Message)"
                                continue
                            }
                        }
                    }
                    $authorData.recent_commits = $recentCommits
                }

                # Update numeric values with null coalescing
                $authorData.is_current_user = [bool]($author.is_current_user ?? $false)
                $authorData.commits = [int]($author.commits ?? 0)
                $authorData.additions = [int]($author.additions ?? 0)
                $authorData.deletions = [int]($author.deletions ?? 0)
                $authorData.total_lines_affected = [int]($author.total_lines_affected ?? 0)

                # Create author object with explicit type conversion
                $convertedAuthor = [PSCustomObject]$authorData
                $convertedAuthors += $convertedAuthor

            }
            catch {
                Write-Warning "Failed to convert author data for '$($authorEntry.Key)': $($_.Exception.Message)"
                continue
            }
        }

        # Convert file_types array to PSCustomObject properly
        try {
            $convertedFileTypes = Convert-FileTypeStats -FileTypes $stats.file_types -Context "Converting repository file types"
        }
        catch {
            Write-ErrorDetails -ErrorRecord $_ -Context "Failed to convert file types" -Warning
            $convertedFileTypes = [PSCustomObject]@{}
        }

        try {
            $convertedImpact = [PSCustomObject]@{
                additions            = $stats.impact.additions
                deletions            = $stats.impact.deletions
                total_lines_affected = $stats.impact.total_lines_affected
            }
        }
        catch {
            Write-Warning "Failed to create impact object: $($_.Exception.Message)"
            $convertedImpact = [PSCustomObject]@{
                additions            = 0
                deletions            = 0
                total_lines_affected = 0
            }
        }

        $convertedStats = @{
            total_commits        = $stats.total_commits
            total_lines_affected = $stats.total_lines_affected
            authors              = @($convertedAuthors)  # Force array
            file_types           = $convertedFileTypes
            commit_times         = $stats.commit_times
            impact               = $convertedImpact
        }

        # Convert to PSCustomObject after ensuring arrays
        $convertedStats = [PSCustomObject]$convertedStats

        return $convertedStats

    }
    catch {
        Write-Warning "Failed to process repository statistics: $($_.Exception.Message)"
        Write-Host "Error details:" -ForegroundColor Red
        Write-Host "  Line number: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
        Write-Host "  Line element: $($_.InvocationInfo.Line)" -ForegroundColor Red
        Write-Host "  Error message: $($_.Exception.Message)" -ForegroundColor Red
        # Return a minimal valid stats object instead of throwing
        return [PSCustomObject]@{
            total_commits        = 0
            total_lines_affected = 0
            authors              = @()
            file_types           = Convert-FileTypeStats -FileTypes @{} -Context "Creating empty file types"
            commit_times         = [PSCustomObject]@{}
            impact               = [PSCustomObject]@{
                additions            = 0
                deletions            = 0
                total_lines_affected = 0
            }
        }
    }
}

# Add this function before Test-GitStatus

# Modify the Get-GitHistoryContext function to include the changes summary
function Get-GitHistoryContext {
    param (
        [string]$RepoPath,
        [int]$Days,
        [switch]$CurrentUserOnly,
        [string]$TargetPath
    )

    Set-Location $RepoPath
    Write-ProgressHelper -Activity "Processing Repository" -Status "Getting repository age..." -PercentComplete 10

    # Get repository age and first commit with progress
    $firstCommitHash = git rev-list --max-parents=0 HEAD 2>$null
    $firstCommitDate = $null
    if ($firstCommitHash) {
        $firstCommitDate = git show -s --format=%ci $firstCommitHash
        $repoAge = (New-TimeSpan -Start ([DateTime]::Parse($firstCommitDate)) -End (Get-Date)).Days
    }

    Write-ProgressHelper -Activity "Processing Repository" -Status "Analyzing commit history..." -PercentComplete 30

    # Adjust date range based on repository age
    $since = if ($firstCommitDate -and $Days -gt $repoAge) {
        ([DateTime]::Parse($firstCommitDate)).ToString("yyyy-MM-dd")
    }
    else {
        (Get-Date).AddDays(-$Days).ToString("yyyy-MM-dd")
    }

    # Get commit history with progress
    $commits = Get-CommitHistory -RepoPath $RepoPath -TargetPath $TargetPath -Since $since -CurrentUserOnly $CurrentUserOnly

    Write-ProgressHelper -Activity "Processing Repository" -Status "Gathering repository statistics..." -PercentComplete 80

    # Get repository information and statistics
    $repoName = Split-Path $RepoPath -Leaf
    $branches = @(git branch --sort=-committerdate | ForEach-Object { $_.TrimStart('* ') })
    $tags = @(git tag --sort=-creatordate)
    $stats = Get-RepositoryStatistics -RepoPath $RepoPath -FromDate ([datetime]::Parse($since)) -TargetPath $TargetPath -CurrentUserOnly $CurrentUserOnly -CommitHistory $commits

    Write-ProgressHelper -Activity "Processing Repository" -Status "Creating history context..." -PercentComplete 90

    # Create enhanced history context
    $historyContext = @{
        repository     = @{
            name           = $repoName
            path           = $RepoPath
            current_branch = (git branch --show-current)
            branches       = $branches
            tags           = $tags
            age_days       = $repoAge
            first_commit   = $firstCommitDate
            source_tree    = @{
                files     = @(git ls-files)  # List all tracked files
                structure = @{}  # Will hold directory structure
            }
        }
        history_period = @{
            days  = $Days
            since = $since
            until = (Get-Date).ToString("yyyy-MM-dd")
        }
        commits        = $commits
        statistics     = @{
            total_commits        = $stats.total_commits
            total_lines_affected = $stats.total_lines_affected
            current_user         = $stats.current_user
            authors              = $stats.authors
            file_types           = Convert-FileTypeStats -FileTypes $stats.file_types -Context "Converting history context file types"
            commit_times         = $stats.commit_times
            impact               = $stats.impact
            branches_modified    = @($commits | ForEach-Object {
                    git branch --contains $_.hash
                } | Select-Object -Unique)
        }
        performance    = @{
            processing_time = [math]::Round(((Get-Date) - $script:startTime).TotalSeconds, 2)
            memory_used     = [math]::Round((Get-Process -Id $PID).WorkingSet64 / 1MB, 2)
        }
    }

    Set-Location $TargetPath
    # create a _cursor_release_context directory
    $cursorReleaseContextDir = Join-Path $TargetPath "_cursor_release_context"
    if (-not (Test-Path $cursorReleaseContextDir -PathType Container)) {
        New-Item -ItemType Directory -Path $cursorReleaseContextDir
    }

    # gitignore path to folder
    $gitFilePath = $cursorReleaseContextDir.Replace($RepoPath, "")
    $gitFilePath = $gitFilePath.Replace("\", "/")
    # Remove leading slash if exists
    if ($gitFilePath.StartsWith("/")) {
        $gitFilePath = $gitFilePath.Substring(1)
    }

    # Add folder to gitignore
    $gitIgnoreFilePath = Join-Path $RepoPath ".gitignore"
    if (-not (Test-Path $gitIgnoreFilePath -PathType Leaf)) {
        New-Item -ItemType File -Path $gitIgnoreFilePath
    }
    Add-Content $gitIgnoreFilePath $gitFilePath

    # Build directory structure with file contents
    $fileContents = @{}

    # Get unique files from commit history using both FileName and GitFilePath
    $files = $commits | ForEach-Object {
        $_.Files | ForEach-Object {
            $fileName = $_.FileName
            $gitPath = $_.GitFilePath
            if ($fileName -like "*=>*") {
                $fileName = ($fileName -split "=>")[1].Trim()
            }
            if ($gitPath -like "*=>*") {
                $gitPath = ($gitPath -split "=>")[1].Trim()
            }
            [PSCustomObject]@{
                FileName = $fileName
                GitFilePath = $gitPath
            }
        }
    } | Sort-Object -Property FileName -Unique

    foreach ($file in $files) {
        try {
            $filePath = $file.FileName
            $gitPath = $file.GitFilePath
            $cursorReleaseContextFolderPath = Join-Path $cursorReleaseContextDir (Split-Path $gitPath)

            if (-not (Test-Path $cursorReleaseContextFolderPath -PathType Container)) {
                try {
                    New-Item -ItemType Directory -Path $cursorReleaseContextFolderPath -Force | Out-Null
                }
                catch {
                    Write-Warning "Failed to create directory $cursorReleaseContextFolderPath : $($_.Exception.Message)"
                    continue
                }
            }
            $cursorReleaseContextFilePath = Join-Path $cursorReleaseContextDir $gitPath

            if (-not (Test-FileForContext -FilePath $filePath -TargetPath $TargetPath)) {
                continue
            }

            Write-Log "Exporting source file to report: $filePath"
            # Copy the file to the _cursor_release_context directory
            Copy-Item $filePath $cursorReleaseContextFilePath -Force -ErrorAction SilentlyContinue
            # Add the $cursorReleaseContextFilePath to the fileContents
            $fileContents[$gitPath] = $cursorReleaseContextFilePath

            # # Get file content
            # $content = Get-Content $filePath -Raw -ErrorAction SilentlyContinue

            # if ($null -ne $content) {
            #     $fileContents[$gitPath] = $content
            # }
        }
        catch {
            Write-Warning "Failed to read file $($file.FileName) : $($_.Exception.Message)"
            continue
        }
    }

    # Add file contents to repository structure
    $historyContext.repository.source_tree.contents = $fileContents

    Write-ProgressHelper -Activity "Processing Repository" -Status "Complete" -PercentComplete 100
    return $historyContext
}

# Call the function right after param block
Test-GitMsgCommand

# Normalize the path if provided
if (-not [string]::IsNullOrWhiteSpace($TargetPath)) {
    $TargetPath = [System.IO.Path]::GetFullPath($TargetPath)
}

if ([string]::IsNullOrWhiteSpace($TargetPath)) {
    Write-Host @"
Git Message Generator For Cursor
================================
This PowerShell script generates a context file for creating release notes from your project changes.

Usage:
  gitmsg <target_directory>

The 'gitmsg' command is available system-wide as it's installed in %USERPROFILE%\AppData\Local\Microsoft\WindowsApps, if you previously executed the deploy.bat script.

Alternative Usage: (will create gitmsg.bat in Windows Apps directory on first run)
  .\CursorReleaseContextGenerator.ps1 -TargetPath <path_to_target_directory>

Parameters:
  target_directory or TargetPath (Required)
      The directory path to analyze for changes. This can be any project directory.

What it does:
  1. Analyzes your project structure
  2. Captures differences between the current branch and the target directory
  3. Generates a detailed context file and saves it to the target directory
  4. Opens the context file in Cursor. Create a new chat with context: Use the file as context
  5. Generates the git commit message in Cursor, for you to paste into the Git Commit Message in any application that supports it

"@ -ForegroundColor White

    Write-Host "`nPlease provide a target directory path.`n" -ForegroundColor Yellow
    exit 0
}

# Validate path exists
if (-not (Test-Path $TargetPath -PathType Container)) {
    Write-Error "Target directory does not exist: $TargetPath"
    exit 1
}

# Clean up old release context files
Write-Verbose "Cleaning up old release context files..."
try {
    $oldContextFiles = Get-ChildItem -Path $TargetPath -Filter "release_context_*.json" -File
    if ($oldContextFiles) {
        Write-Host "Found $($oldContextFiles.Count) old release context file(s). Removing..."
        $oldContextFiles | ForEach-Object {
            Remove-Item $_.FullName -Force
            Write-Verbose "Removed: $($_.Name)"
        }
    }
}
catch {
    Write-Warning "Failed to clean up old release context files: $_"
    # Continue execution since this is not critical
}

# Replace the Find-GitRepository function with this updated version
function Find-GitRepository {
    param (
        [string]$StartPath,
        [bool]$FindGitReposRecursive = $false
    )

    Write-Verbose "Looking for git repository in: $StartPath"

    # First check if current directory is a git repository
    if (Test-Path (Join-Path $StartPath ".git") -PathType Container) {
        Write-Verbose "Found git repository at: $StartPath"
        return $StartPath
    }

    # If recursive search is enabled, look in subdirectories
    if ($FindGitReposRecursive) {
        Write-Verbose "Searching subdirectories recursively..."
        return Find-GitRepositoriesRecursive -BasePath $StartPath
    }

    # If not recursive and no repository found, return null
    Write-Verbose "No git repository found in $StartPath"
    return $null
}
function Find-GitRepositoryUpwards {
    param (
        [string]$StartPath
    )

    Write-Verbose "Looking for git repository from folder towards root in: $StartPath"

    # First check if current directory is a git repository
    if (Test-Path (Join-Path $StartPath ".git") -PathType Container) {
        Write-Verbose "Found git repository at: $StartPath"
        return $StartPath
    }

    # Loop up through parent folders until we find a repo or hit the root
    while ($true) {
        $parentPath = Split-Path $StartPath -Parent

        # Break if we've hit the root (parent path same as current)
        if ($parentPath -eq $StartPath) {
            break
        }

        # Check if parent has a .git folder
        if (Test-Path (Join-Path $parentPath ".git") -PathType Container) {
            return $parentPath
        }

        # Move up to parent and continue loop
        $StartPath = $parentPath
    }

    # If no repository found, return null
    return $null

}
# Add this function before the history mode check
function Start-GitRepository {
    param (
        [string]$RepoPath,
        [int]$Days,
        [bool]$IsRetry = $false,
        [switch]$CurrentUserOnly
    )

    Write-Log "Processing repository: $RepoPath"
    Write-Log "Days to analyze: $Days"

    try {
        # Check git status first
        Write-Log "Checking git status..."
        if (-not (Test-GitStatus -RepoPath $RepoPath)) {
            if ($IsRetry) {
                Write-Log "Git status check failed after retry"
                throw "Git status check failed after retry"
            }

            Write-Log "Retrying repository processing with clean state..."
            Set-Location $RepoPath
            Write-Log "Running git reset --hard"
            git reset --hard
            Write-Log "Running git clean -fd"
            git clean -fd
            return Start-GitRepository -RepoPath $RepoPath -Days $Days -IsRetry $true -CurrentUserOnly $CurrentUserOnly
        }

        Write-Log "Git status check passed"

        # Get repository history
        Write-Log "Getting repository history..."
        try {
            $historyContext = Get-GitHistoryContext -RepoPath $RepoPath -Days $Days -CurrentUserOnly $CurrentUserOnly -TargetPath $TargetPath
            Write-Log "Successfully retrieved repository history"
            return $historyContext
        }
        catch {
            Write-ErrorDetails -ErrorRecord $_ -Context "Failed to get repository history for $RepoPath" -Warning
            Write-Log "History retrieval error: $($_.Exception.Message)"
            Write-Log "Stack trace: $($_.ScriptStackTrace)"
            throw
        }
    }
    catch {
        Write-ErrorDetails -ErrorRecord $_ -Context "Failed to process repository: $RepoPath" -Warning
        Write-Log "Processing error: $($_.Exception.Message)"
        Write-Log "Stack trace: $($_.ScriptStackTrace)"
        throw
    }
}

# Add this function before the main logic
function New-CursorContext {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Mode,
        [Parameter(Mandatory = $true)]
        [string]$TargetPath,
        [Parameter(Mandatory = $true)]
        [string]$RepoPath,
        [Parameter(Mandatory = $false)]
        [object]$SourceTree,
        [Parameter(Mandatory = $false)]
        [object]$UncommittedChanges,
        [Parameter(Mandatory = $false)]
        [string]$UncommittedSummary,
        [Parameter(Mandatory = $false)]
        [object]$AdditionalData
    )

    $readmeFile = Join-Path $TargetPath "cursor-result.md"

    # Create base repository structure
    $repository = @{
        name           = Split-Path $RepoPath -Leaf
        path           = $RepoPath
        current_branch = (git branch --show-current)
        target_path    = $TargetPath
        source_tree    = $SourceTree
        analysis       = @{
            changes     = @{
                uncommitted = $UncommittedChanges
                summary     = $UncommittedSummary
                impact      = @{
                    files_changed = $UncommittedChanges.stats.files_changed
                    total_lines   = $UncommittedChanges.stats.insertions + $UncommittedChanges.stats.deletions
                    net_changes   = $UncommittedChanges.stats.insertions - $UncommittedChanges.stats.deletions
                }
            }
            file_groups = @{
                modified = @{
                    staged   = $UncommittedChanges.staged.modified
                    unstaged = $UncommittedChanges.unstaged.modified
                }
                added    = @{
                    staged    = $UncommittedChanges.staged.added
                    untracked = $UncommittedChanges.untracked
                }
                deleted  = @{
                    staged   = $UncommittedChanges.staged.deleted
                    unstaged = $UncommittedChanges.unstaged.deleted
                }
            }
            diffs       = @{
                staged   = $UncommittedChanges.diff_content.staged
                unstaged = $UncommittedChanges.diff_content.unstaged
            }
        }
    }

    # Add any additional data specific to the mode
    if ($AdditionalData) {
        foreach ($key in $AdditionalData.Keys) {
            $repository[$key] = $AdditionalData[$key]
        }
    }

    # Create the context structure
    $cursorContext = @{
        cursorContext        = @{
            scan_info        = @{
                base_path = $TargetPath
                repo_path = $RepoPath
                scan_date = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                mode      = $Mode
            }
            repository       = $repository
            analysis_summary = @{
                change_scope    = if ($Mode -eq "HistoryMode") { "Historical Changes" } else { "Working Directory Changes" }
                primary_changes = @{
                    files = @{
                        total    = $repository.analysis.changes.impact.files_changed
                        modified = ($repository.analysis.file_groups.modified.staged + $repository.analysis.file_groups.modified.unstaged).Count
                        added    = ($repository.analysis.file_groups.added.staged + $repository.analysis.file_groups.added.untracked).Count
                        deleted  = ($repository.analysis.file_groups.deleted.staged + $repository.analysis.file_groups.deleted.unstaged).Count
                    }
                    lines = @{
                        total = $repository.analysis.changes.impact.total_lines
                        net   = $repository.analysis.changes.impact.net_changes
                    }
                }
                change_status   = @{
                    has_staged    = ($repository.analysis.file_groups.modified.staged +
                        $repository.analysis.file_groups.added.staged +
                        $repository.analysis.file_groups.deleted.staged).Count -gt 0
                    has_unstaged  = ($repository.analysis.file_groups.modified.unstaged +
                        $repository.analysis.file_groups.deleted.unstaged).Count -gt 0
                    has_untracked = $repository.analysis.file_groups.added.untracked.Count -gt 0
                }
            }
        }
        composerInstructions = @"
Use the file as context to create a Git Commit message that:
- Groups changes by project/folder.
- Describes added/modified/deleted files in human-readable language.
- Includes the purpose and impact of changes.
- Indent changes in relation to the heading it relates to.
- Impact analysis per project/folder clearly indented.

Analysis Guidelines:
1. Start with a high-level summary of changes
2. Group changes by their type (modified, added, deleted)
3. For each file:
   - Explain what changed
   - Why it matters
   - Impact on the codebase
4. Include statistics about the changes
5. Note any special considerations

Remember to:
- Use clear, concise language
- Highlight significant changes
- Explain technical changes in business terms
- Include relevant metrics and impact analysis
"@
        contextMode          = if ($Mode -eq "HistoryMode") { "History" } else { "Differences" }
        targetPath           = $TargetPath
        cursorResultFile     = "@$(Split-Path $readmeFile -Leaf)"
    }

    return $cursorContext
}

# Add this function to handle path conversion
function Get-RelativePath {
    param (
        [string]$Path,
        [string]$BasePath
    )

    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path)
        $fullBasePath = [System.IO.Path]::GetFullPath($BasePath)

        # If paths are on different drives, return the full path
        if ([System.IO.Path]::GetPathRoot($fullPath) -ne [System.IO.Path]::GetPathRoot($fullBasePath)) {
            return $fullPath
        }

        # Get the relative path
        $uri = New-Object System.Uri($fullBasePath)
        $relativePath = [System.Uri]::UnescapeDataString($uri.MakeRelativeUri((New-Object System.Uri($fullPath))).ToString()).Replace('/', '\')

        # If the path starts with ..\, it's outside the target directory
        if ($relativePath.StartsWith('..')) {
            return $fullPath
        }

        return $relativePath
    }
    catch {
        Write-Warning "Failed to get relative path for $Path : $($_.Exception.Message)"
        return $Path
    }
}

# Update the source tree creation in both modes to use relative paths
function Get-SourceTreeDifferences {
    param (
        [string]$RepoPath,
        [string]$TargetPath,
        [string]$CursorReferenceFolderPath,
        [object]$UncommittedChanges
    )
    $targetGitPath = Get-TargetGitPath -RepoPath $RepoPath -TargetPath $TargetPath

    # Save current location
    $previousLocation = Get-Location
    Set-Location $RepoPath

    try {
        $sourceTree = @{
            files      = @()
            file_paths = @()
        }

        $sourceTree.changes = $UncommittedChanges.diff_content

        # Get all tracked files
        $files = git ls-files
        foreach ($file in $files) {
            try {
                # Filter files based on targetGitPath if specified
                if ($targetGitPath -ne "") {
                    if (-not $file.ToUpper().StartsWith($targetGitPath.ToUpper())) {
                        continue
                    }
                }
                if (-not (Test-FileForContext -FilePath $filePath -TargetPath $TargetPath)) {
                    continue
                }

                # Get the full path and convert to relative path
                $fullPath = Join-Path $RepoPath $file
                $relativePath = Get-RelativePath -Path $fullPath -BasePath $RepoPath

                Write-Log "Adding file path to source tree: $relativePath"

                # Add file path to both lists
                $sourceTree.files += $relativePath
                $sourceTree.file_paths += $relativePath

            }
            catch {
                Write-Warning "Failed to process file $file : $($_.Exception.Message)"
                continue
            }
        }

        return $sourceTree
    }
    finally {
        # Restore previous location
        Set-Location $previousLocation
    }
}

# Add this function before the main logic
function Clear-CursorReferenceFolder {
    param (
        [Parameter(Mandatory = $true)]
        [string]$TargetPath,
        [bool]$IsHistoryMode,
        [bool]$SkipRecreate = $false
    )

    if ($IsHistoryMode) {
        $CursorReferenceFolderPath = Join-Path $TargetPath "_cursor_release_context" "history"
    }
    else {
        $CursorReferenceFolderPath = Join-Path $TargetPath "_cursor_release_context" "difference"
    }

    if (Test-Path $CursorReferenceFolderPath -PathType Container) {
        try {
            Remove-Item -Path $CursorReferenceFolderPath -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
            Write-Log "Cleaned up existing _cursor_release_context folder"
        }
        catch {
            Write-Log "Failed to clean up _cursor_release_context folder: $($_.Exception.Message)"
        }
    }
    if (-not $SkipRecreate) {
        # Recreate the folder
        New-Item -Path $CursorReferenceFolderPath -ItemType Directory -Force | Out-Null
    }
    return $CursorReferenceFolderPath
}

# Add these functions before the main section
function Invoke-HistoryMode {
    param (
        [string]$TargetPath,
        [int]$Days,
        [bool]$FindGitReposRecursive,
        [bool]$CurrentUserOnly
    )

    try {
        # Clean up temp folder
        $cursorReferenceFolderPath = Clear-CursorReferenceFolder -TargetPath $TargetPath -IsHistoryMode $true

        # Always use recursive search in history mode
        #$findGitReposRecursive = $FindGitReposRecursive
        $findGitReposRecursive = $true

        Write-Host "Searching for git repositories in $TargetPath..." -ForegroundColor Cyan

        # Use Find-GitRepository which now handles recursive search
        $repositories = Find-GitRepository -StartPath $TargetPath -FindGitReposRecursive $FindGitReposRecursive
        if (-not $repositories) {
            $repositories = Find-GitRepositoryUpwards -StartPath $TargetPath
        }

        if (-not $repositories) {
            Write-Error "No git repositories found in $TargetPath or its subdirectories"
            exit 1
        }

        # Convert single repository to array if needed
        if ($repositories -is [string]) {
            $repositories = @($repositories)
        }

        Write-Host "Found $($repositories.Count) repositories" -ForegroundColor Green

        # Calculate date range
        $toDate = Get-Date
        $fromDate = $toDate.AddDays(-$Days)

        # Create scan info
        $scanContext = @{
            scan_info    = @{
                started_by         = $env:USERNAME
                filter_criteria    = @{
                    current_user_only = $CurrentUserOnly
                    days              = $Days
                    path              = $TargetPath
                }
                date_range         = @{
                    from = $fromDate.ToString("yyyy-MM-dd")
                    to   = $toDate.ToString("yyyy-MM-dd")
                }
                scan_date          = $toDate.ToString("yyyy-MM-dd HH:mm:ss")
                repositories_found = $repositories.Count
            }
            repositories = @()
        }

        # Add at the start of the script
        $script:startTime = Get-Date

        # Process repositories
        $script:totalRepos = $repositories.Count
        $script:currentRepo = 0

        foreach ($repoPath in $repositories) {
            $script:currentRepo++
            $repoName = Split-Path $repoPath -Leaf
            $percentComplete = [math]::Round(($script:currentRepo / $script:totalRepos) * 100)

            Write-ProgressHelper -Activity "Processing Repositories" -Status "Processing $repoName ($script:currentRepo of $script:totalRepos)" -PercentComplete $percentComplete

            try {
                Write-Host "`nProcessing repository: $repoPath" -ForegroundColor Cyan
                Write-Host "Analyzing history from $($fromDate.ToString('yyyy-MM-dd')) to $($toDate.ToString('yyyy-MM-dd'))" -ForegroundColor Yellow

                Write-Log "Starting repository analysis for: $repoPath"
                Write-Log "Current progress: Repository $script:currentRepo of $script:totalRepos"
                Write-Log "Date range: $($fromDate) to $($toDate)"

                $historyContext = Start-GitRepository -RepoPath $repoPath -Days $Days -CurrentUserOnly $CurrentUserOnly -TargetPath $TargetPath
                if ($null -eq $historyContext) {
                    Write-Log "Warning: Start-GitRepository returned null for $repoPath"
                    continue
                }

                $scanContext.repositories += $historyContext
                Write-Log "Successfully completed processing for: $repoPath"
            }
            catch {
                Write-ErrorDetails -ErrorRecord $_ -Context "Failed to process repository: $repoPath" -Warning
                Write-Log "Repository processing failed with error: $($_.Exception.Message)"
                continue
            }
        }

        Write-Log "Completed processing all repositories"
        Write-Log "Successfully processed: $($scanContext.repositories.Count) of $($script:totalRepos)"

        if ($scanContext.repositories.Count -eq 0) {
            throw "No repositories were successfully processed"
        }

        # Define composer instructions for history mode
        $historyInstructions = @"
Use the file as context to generate a Git repository detailed analysis report as a new markdownfile, using all aspects of the file as context, and exported code here $cursorReferenceFolderPath and subfolders as context.
All information to be used in the report must be found in the context provided or in reference files in the $cursorReferenceFolderPath and subfolders.

# Report Structure
- Use markdown formatting with consistent indentation
- Each repository must be a Level 1 header (#)
- All subsections must be Level 2 headers (##)
- Group changes logically by repository and project
- Include impact analysis at each level
- Use mermaid diagrams to visualize the code if needed
- Report boundaries
    - TargetPath: ${TargetPath} (The path to be analyzed)
    - Days: ${Days} (Number of days to analyze)
    - FindGitReposRecursive: ${FindGitReposRecursive} (Whether to recursively find git repos)
    - CurrentUserOnly: ${CurrentUserOnly} (Whether to only include current user's commits)
    - DateRange: ${fromDate} to ${toDate} (The date range to analyze)
- Structure if one project is found in the target path:
    - Introduction
    - Analysis
    - Statistics
    - Conclusion
- Structure if multiple projects are found in the repository:
    - Solution 1
        - General Introduction
        - Project 1
            - Introduction
            - Analysis
            - Statistics
            - Conclusion
        - Project 2
            - Introduction
            - Analysis
            - Statistics
            - Conclusion
    - Solution 2
        - Project 1
            - Introduction
            - Analysis
            - Statistics
            - Conclusion
        - Project 2
            - Introduction
            - Analysis
            - Statistics
            - Conclusion

## Required Sections Per Repository/Project
1. Repository Overview
   - Repository name and path
   - Branch and tag information
   - Overall statistics and metrics
   - Detailed Code Purpose Analysis of current code:
     * Analyze the latest version of code in the repository in detail
     * Explain what problems the code is trying to solve in detail
     * Describe the main functionality and purpose in detail
     * Identify key features and components in detail
   - Code statistics
   - Current Git Commit Id

2. Code Analysis
   - Analyze implications of changes in the code (medium level)
   - Identify key files and their purpose
   - Describe the relationships between files, and use mermaid diagrams to visualize the relationships if needed.
   - Explain how the file structure supports the code's purpose
   - Analyze implications of added files in the code (high level)

3. Author Analysis
   - Show contribution breakdown
   - Include lines added/deleted
   - List file types modified
   - Show commit patterns
   - Calculate impact metrics

## Code Analysis Focus
- Examine the latest code state to understand functionality
- Identify main problems being solved
- Describe architectural approaches used
- Highlight key algorithms and patterns
- Note important dependencies and integrations
- Describe the business impact of the changes
- Describe in depth the new files added and the purpose of the files
- Use mermaid diagrams to visualize the code if needed
"@

# $readmeInstructions = @"
# # Cursor Instructions
# /Composerinfo: Read the file in great detail: @$env:OptPath\src\DevTools\composer_context.json

# /Composerinfo: All information to be used in the report must be found in the context provided or in reference files in the $env:OptPath\src\DevTools\_cursor_release_context\history and subfolders.

# /Composerinfo: Use the file as context to generate a detailed analysis report as a new markdownfile, using all aspects of the file as context, and exported code here $env:OptPath\src\DevTools\_cursor_release_context\history and subfolders as context.

# /Composerinfo: Provide detailed analysis on each module or sub-project
# "@
        $readmeFile = Join-Path $TargetPath "cursor_instructions.md"
        # add instructions to the readme file
        Add-Content -Path $readmeFile -Value $historyInstructions

        try {
            # Create cursor context
            $cursorContext = @{
                cursorContext        = @{
                    scan_info    = $scanContext.scan_info
                    repositories = $scanContext.repositories
                }
                composerInstructions = $historyInstructions
                contextMode          = "History"
                targetPath          = $TargetPath
                cursorResultFile     = "@$(Split-Path $readmeFile -Leaf)"
            }
        }
        catch {
            Write-Log -Exception $_ -Context "Failed to create cursor context" -LineNumber $_.InvocationInfo.ScriptLineNumber
            throw
        }

        # Save and start Cursor
        Save-FormattedJson -Content $cursorContext -TargetPath $TargetPath
        Start-CursorProcess -TargetPath $TargetPath -WorkingDirectory $TargetPath -Instructions $historyInstructions -IsHistoryMode $true

        # Show performance summary
        $totalTime = [math]::Round(((Get-Date) - $script:startTime).TotalSeconds, 2)
        Write-Host "`nPerformance Summary:" -ForegroundColor Cyan
        Write-Host "Total Processing Time: $totalTime seconds" -ForegroundColor Yellow
        Write-Host "Repositories Processed: $($scanContext.repositories.Count) of $($script:totalRepos)" -ForegroundColor Yellow
        Write-Host "Memory Used: $([math]::Round((Get-Process -Id $PID).WorkingSet64 / 1MB, 2)) MB" -ForegroundColor Yellow

    }
    catch {
        Write-Output ($_.Exception.Message + " " + $_.InvocationInfo.ScriptLineNumber)
        Write-Log -Exception $_ -Context "History mode processing failed" -LineNumber $_.InvocationInfo.ScriptLineNumber
        Write-ErrorDetails -ErrorRecord $_ -Context "History mode processing failed" -Warning
        throw
    }
}

function Invoke-DifferenceMode {
    param (
        [string]$TargetPath
    )

    try {
        # Clean up temp folder
        $CursorReferenceFolderPath = Clear-CursorReferenceFolder -TargetPath $TargetPath -IsHistoryMode $false

        Write-Host "Analyzing git differences in $TargetPath..." -ForegroundColor Cyan

        # Find git repository
        $repoPath = Find-GitRepository -StartPath $TargetPath -FindGitReposRecursive $false
        if (-not $repoPath) {
            $repoPath = Find-GitRepositoryUpwards -StartPath $TargetPath
        }

        if (-not $repoPath) {
            Write-Error "No git repository found in $TargetPath"
            exit 1
        }

        Write-Host "Found git repository at: $repoPath" -ForegroundColor Green

        # Get uncommitted changes
        Write-Host "Getting uncommitted changes..." -ForegroundColor Yellow
        $uncommittedChanges = Get-UncommittedChanges -RepoPath $repoPath -TargetPath $TargetPath

        if ($null -eq $uncommittedChanges) {
            Write-Host "No uncommitted changes found." -ForegroundColor Yellow
            exit 0
        }

        $commitInstructions = @"
Use the file as context to generate a Git repository analysis between the current commit and the previous commit.
The goal is to use this as a commit message for the current commit.

# Parameter values
- TargetPath: ${TargetPath} (The path to the git repository)

# Analysis Requirements
Analyze the code changes and generate a comprehensive report covering:

1. Changes Overview
- Summarize code modifications and new files
- Explain key files and their relationships
- Describe how changes fit into overall structure

2. Technical Details
- Analyze code implementation and patterns
- Identify architectural approaches
- Note dependencies and integrations
- Evaluate code quality impact

3. Business Impact
- Explain purpose and benefits of changes
- Describe effect on functionality
- Assess value added to codebase

Include metrics on:
- Lines added/modified/deleted
- File types changed
- Author contributions
- Overall change impact

"@

        # Get source tree and create context
        $sourceTree = Get-SourceTreeDifferences -RepoPath $repoPath -TargetPath $TargetPath -UncommittedChanges $uncommittedChanges -CursorReferenceFolderPath $CursorReferenceFolderPath

        # Create cursor context
        $cursorContext = New-CursorContext `
            -Mode "GitDifferenceMode" `
            -TargetPath $TargetPath `
            -RepoPath $repoPath `
            -SourceTree $sourceTree `
            -UncommittedChanges $uncommittedChanges `
            -UncommittedSummary (Get-UncommittedChangesSummary -Changes $uncommittedChanges)

        # Save and start Cursor
        Save-FormattedJson -Content $cursorContext -TargetPath $TargetPath
        Start-CursorProcess -TargetPath $TargetPath -WorkingDirectory $TargetPath -Instructions $commitInstructions -IsHistoryMode $false
    }
    catch {
        Write-Log -Exception $_ -Context "Git difference mode processing failed"
        Write-ErrorDetails -ErrorRecord $_ -Context "Git difference mode processing failed" -Warning
        throw
    }
}

function Save-FormattedJson {
    param (
        [Parameter(Mandatory = $true)]
        [object]$Content,
        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    $outputFile = Join-Path $TargetPath "composer_context.json"

    # Convert to JSON with proper formatting
    $jsonContent = $Content | ConvertTo-Json -Depth 100

    # Format JSON with proper indentation
    $formattedJson = @()
    $indentLevel = 0
    $jsonLines = $jsonContent -split "`n"

    foreach ($line in $jsonLines) {
        $line = $line.TrimEnd()

        # Decrease indent for closing brackets/braces
        if ($line -match '^\s*[\}\]]') {
            $indentLevel = [Math]::Max(0, $indentLevel - 1)
        }

        # Add indented line
        if ($line.Trim()) {
            $formattedJson += (' ' * ($indentLevel * 2)) + $line.Trim()
        }

        # Increase indent for opening brackets/braces
        if ($line -match '[\{\[]\s*$') {
            $indentLevel++
        }
    }

    # Write the formatted JSON to file with UTF8 encoding
    $formattedJson | Out-File $outputFile -Encoding UTF8
    Write-Host "`nOutput saved to: $outputFile" -ForegroundColor Green
}

########################################################################################################################################################################################################################
########################################################################################################################################################################################################################
# Main
########################################################################################################################################################################################################################
########################################################################################################################################################################################################################

# Validate and normalize target path
if ([string]::IsNullOrWhiteSpace($TargetPath)) {
    $TargetPath = "."
}

$TargetPath = [System.IO.Path]::GetFullPath($TargetPath)
# Clean up _cursor_release_context folder if it exists
if (-not [string]::IsNullOrWhiteSpace($TargetPath)) {
    $CursorReferenceFolderPath = Join-Path $TargetPath "_cursor_release_context"
    if (Test-Path $CursorReferenceFolderPath -PathType Container) {
        try {
            Remove-Item -Path $CursorReferenceFolderPath -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
            Write-Log "Cleaned up existing _cursor_release_context folder"
        }
        catch {
            Write-Log "Failed to clean up _cursor_release_context folder: $($_.Exception.Message)"
        }
    }
}

# Validate target path exists
if (-not (Test-Path $TargetPath -PathType Container)) {
    Write-Error "Target directory does not exist: $TargetPath"
    exit 1
}

# Execute appropriate mode based on $Days parameter
try {
    if ($Days) {
        # Validate days parameter
        if (-not [int]::TryParse($Days, [ref]$null)) {
            Write-Error "Days parameter must be a number"
            exit 1
        }
        $Days = [int]$Days  # Convert to integer

        Invoke-HistoryMode -TargetPath $TargetPath -Days $Days -CurrentUserOnly $CurrentUserOnly -FindGitReposRecursive $FindGitReposRecursive
    }
    else {
        Invoke-DifferenceMode -TargetPath $TargetPath
    }
    exit 0
}
catch {
    Write-ErrorDetails -ErrorRecord $_ -Context "Script execution failed"
    exit 1
}

