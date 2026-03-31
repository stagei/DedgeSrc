<#
.SYNOPSIS
    Export all project repository states (code versions) for each commit in a date range.

.DESCRIPTION
    Clones or updates a given git repository, finds all commits within the given date range,
    and exports the complete codebase as it existed at each commit into timestamped subfolders.
    Useful for auditing, change analysis, and historical debugging of project code evolution.

.PARAMETER GitRepository
    The URL of the git repository to extract the historical versions from.
    Defaults to the DedgePsh remote repository.

.PARAMETER FromDate
    The start date (inclusive) for the commit history to extract.
    Defaults to 2024-05-01.

.PARAMETER ToDate
    The end date (inclusive) for the commit history to extract.
    Defaults to 2024-09-01.
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$GitRepository = "https://Dedge.visualstudio.com/DefaultCollection/Dedge/_git/DedgePsh",
    [Parameter(Mandatory = $false)]
    [datetime]$FromDate = [DateTime]::Parse("2024-05-01"),
    [Parameter(Mandatory = $false)]
    [datetime]$ToDate = [DateTime]::Parse("2024-09-01")
)

Import-Module GlobalFunctions -Force
$appDatafolder = Get-ApplicationDataPath

# Get all git commits for the project in the given date range and create a subfolder with all code that were current at the time of the commit into a subfolder with <date>_<commit_id>

try {
    Write-LogMessage "Starting git version export for repository: $($GitRepository)" -Level INFO
    Write-LogMessage "Date range: $($FromDate.ToString('yyyy-MM-dd')) to $($ToDate.ToString('yyyy-MM-dd'))" -Level INFO

    # Create work folder for git clone
    $workFolder = Join-Path $appDatafolder "GitVersions_Work"
    if (-not (Test-Path $workFolder)) {
        New-Item -Path $workFolder -ItemType Directory -Force | Out-Null
        Write-LogMessage "Created work folder: $($workFolder)" -Level INFO
    }

    # Set up clone path
    $clonePath = Join-Path $workFolder "repo_clone"

    # Clone or update repository
    if (Test-Path $clonePath) {
        Write-LogMessage "Existing clone found, updating..." -Level INFO
        Push-Location $clonePath
        try {
            $fetchResult = git fetch --all 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-LogMessage "Failed to fetch updates: $($fetchResult)" -Level WARN
                Write-LogMessage "Removing existing clone and re-cloning..." -Level INFO
                Pop-Location
                Remove-Item -Path $clonePath -Recurse -Force
                Push-Location $workFolder
                Write-LogMessage "Cloning repository: $($GitRepository)" -Level INFO
                $cloneResult = git clone $GitRepository "repo_clone" 2>&1
                if ($LASTEXITCODE -ne 0) {
                    throw "Failed to clone repository: $($cloneResult)"
                }
                Pop-Location
                Push-Location $clonePath
            } else {
                Write-LogMessage "Repository updated successfully" -Level INFO
            }
        }
        catch {
            Pop-Location
            throw
        }
    } else {
        Push-Location $workFolder
        try {
            Write-LogMessage "Cloning repository: $($GitRepository)" -Level INFO
            $cloneResult = git clone $GitRepository "repo_clone" 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to clone repository: $($cloneResult)"
            }
            Write-LogMessage "Repository cloned successfully" -Level INFO
        }
        finally {
            Pop-Location
        }
        Push-Location $clonePath
    }

    # Create output folder in appdata
    $outputFolder = Join-Path $appDatafolder "GitVersions"
    if (-not (Test-Path $outputFolder)) {
        New-Item -Path $outputFolder -ItemType Directory -Force | Out-Null
        Write-LogMessage "Created output folder: $($outputFolder)" -Level INFO
    }
    try {
        $currentBranch = git rev-parse --abbrev-ref HEAD 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to get current branch: $($currentBranch)"
        }
        Write-LogMessage "Current branch: $($currentBranch)" -Level INFO

        # Get all commits in date range
        $fromDateStr = $FromDate.ToString("yyyy-MM-dd")
        $toDateStr = $ToDate.ToString("yyyy-MM-dd")

        Write-LogMessage "Fetching commits from $($fromDateStr) to $($toDateStr)..." -Level INFO
        $commits = git log --after="$($fromDateStr)" --before="$($toDateStr)" --pretty=format:"%H|%ai|%s" --reverse 2>&1

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to get git commits: $($commits)"
        }

        if (-not $commits) {
            Write-LogMessage "No commits found in the specified date range" -Level WARN
            return
        }

        # Parse commits
        $commitList = @()
        foreach ($line in $commits) {
            if ($line -match '^([a-f0-9]+)\|(.+?)\|(.+)$') {
                $commitList += [PSCustomObject]@{
                    Hash = $Matches[1]
                    Date = [DateTime]::Parse($Matches[2])
                    Message = $Matches[3]
                }
            }
        }

        Write-LogMessage "Found $($commitList.Count) commits to export" -Level INFO

        # Process each commit
        $exportCount = 0
        foreach ($commit in $commitList) {
            try {
                $dateStr = $commit.Date.ToString("yyyyMMdd_HHmmss")
                $shortHash = $commit.Hash.Substring(0, 7)
                $folderName = "$($dateStr)_$($shortHash)"
                $exportPath = Join-Path $outputFolder $folderName

                Write-LogMessage "Processing commit $($shortHash): $($commit.Message)" -Level INFO

                # Checkout the commit
                $checkoutResult = git checkout $commit.Hash 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-LogMessage "Failed to checkout commit $($shortHash): $($checkoutResult)" -Level ERROR
                    continue
                }

                # Create export folder
                if (Test-Path $exportPath) {
                    Write-LogMessage "Export folder already exists, skipping: $($folderName)" -Level WARN
                    continue
                }

                New-Item -Path $exportPath -ItemType Directory -Force | Out-Null

                # Copy all files except .git folder
                Write-LogMessage "Exporting files to: $($exportPath)" -Level INFO

                # Use robocopy for efficient copying, excluding .git folder
                $robocopyArgs = @(
                    $clonePath,
                    $exportPath,
                    "/E",           # Copy subdirectories including empty ones
                    "/XD", ".git",  # Exclude .git directory
                    "/NFL",         # No file list
                    "/NDL",         # No directory list
                    "/NJH",         # No job header
                    "/NJS",         # No job summary
                    "/NC",          # No class
                    "/NS",          # No size
                    "/NP"           # No progress
                )

                robocopy @robocopyArgs 2>&1 | Out-Null

                # Robocopy exit codes: 0-7 are success/partial success, 8+ are errors
                if ($LASTEXITCODE -ge 8) {
                    Write-LogMessage "Warning: robocopy reported issues (exit code: $($LASTEXITCODE))" -Level WARN
                }

                $exportCount++
                Write-LogMessage "Successfully exported commit $($shortHash) to $($folderName)" -Level INFO

            }
            catch {
                Write-LogMessage "Error processing commit $($commit.Hash): $($_.Exception.Message)" -Level ERROR -Exception $_
            }
        }

        Write-LogMessage "Export complete. Exported $($exportCount) of $($commitList.Count) commits" -Level INFO

    }
    finally {
        # Restore original branch
        Write-LogMessage "Restoring original branch: $($currentBranch)" -Level INFO
        $restoreResult = git checkout $currentBranch 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-LogMessage "Failed to restore original branch: $($restoreResult)" -Level ERROR
        }

        Pop-Location
    }

    Write-LogMessage "Git version export completed successfully. Output folder: $($outputFolder)" -Level INFO
}
catch {
    Write-LogMessage "Fatal error during git version export: $($_.Exception.Message)" -Level ERROR -Exception $_
    throw
}

