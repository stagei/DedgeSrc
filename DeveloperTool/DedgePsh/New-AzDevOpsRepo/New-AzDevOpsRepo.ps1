<#
.SYNOPSIS
    Interactive wrapper for creating a new Azure DevOps repo from a local source folder.

.DESCRIPTION
    Provides a guided workflow to publish a local project to Azure DevOps:
      1. Detects repo name from the folder name (or accepts -RepoName override)
      2. Validates the local path exists and contains source files
      3. Creates the repo in Azure DevOps via New-AzureDevOpsRepo
      4. Commits all code and pushes to the new remote

    The heavy lifting is done by the New-AzureDevOpsRepo function in the
    AzureFunctions module.

.PARAMETER LocalPath
    Path to the local source folder. Default: current directory.

.PARAMETER RepoName
    Name for the new Azure DevOps repository. Default: folder name of LocalPath.

.PARAMETER Organization
    Azure DevOps organization. Default: Dedge.

.PARAMETER Project
    Azure DevOps project. Default: Dedge.

.PARAMETER CommitMessage
    Initial commit message. Default: "Initial commit - <RepoName>".

.PARAMETER GitIgnoreContent
    Content for .gitignore. Use 'dotnet' for standard .NET ignores.
    If empty, no .gitignore is created (use existing or none).

.PARAMETER SkipPush
    Create the repo and initialize git but do not commit or push.

.EXAMPLE
    .\New-AzDevOpsRepo.ps1 -LocalPath "C:\opt\src\MyProject"

.EXAMPLE
    .\New-AzDevOpsRepo.ps1 -LocalPath "C:\opt\src\MyApp" -GitIgnoreContent 'dotnet' -CommitMessage "Initial commit"

.EXAMPLE
    .\New-AzDevOpsRepo.ps1 -RepoName "CustomName" -LocalPath "C:\opt\src\MyApp" -Project "Infrastructure"
#>
[CmdletBinding()]
param(
    [string]$LocalPath = (Get-Location).Path,
    [string]$RepoName = "",
    [string]$Organization = "Dedge",
    [string]$Project = "Dedge",
    [string]$CommitMessage = "",
    [string]$GitIgnoreContent = "",
    [switch]$SkipPush
)

$ErrorActionPreference = 'Stop'

Import-Module GlobalFunctions -Force
Import-Module AzureFunctions -Force

$LocalPath = (Resolve-Path $LocalPath -ErrorAction Stop).Path

if ([string]::IsNullOrWhiteSpace($RepoName)) {
    $RepoName = Split-Path $LocalPath -Leaf
}

Write-LogMessage "=== New Azure DevOps Repository ===" -Level INFO
Write-LogMessage "  Repo Name    : $($RepoName)" -Level INFO
Write-LogMessage "  Local Path   : $($LocalPath)" -Level INFO
Write-LogMessage "  Organization : $($Organization)" -Level INFO
Write-LogMessage "  Project      : $($Project)" -Level INFO
Write-LogMessage "  Skip Push    : $($SkipPush)" -Level INFO

$fileCount = (Get-ChildItem -Path $LocalPath -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notlike "*\.git\*" -and $_.FullName -notlike "*\bin\*" -and $_.FullName -notlike "*\obj\*" }).Count
Write-LogMessage "  Source files : $($fileCount)" -Level INFO

if ($fileCount -eq 0) {
    Write-LogMessage "No source files found in $($LocalPath). Aborting." -Level ERROR
    exit 1
}

Write-Host ""
$result = New-AzureDevOpsRepo `
    -RepoName $RepoName `
    -LocalPath $LocalPath `
    -Organization $Organization `
    -Project $Project `
    -CommitMessage $CommitMessage `
    -GitIgnoreContent $GitIgnoreContent `
    -SkipPush:$SkipPush

Write-Host ""
if ($result.Success) {
    Write-LogMessage "=== SUCCESS ===" -Level INFO
    Write-LogMessage "  Repo URL : $($result.RemoteUrl)" -Level INFO
    Write-LogMessage "  Repo ID  : $($result.RepoId)" -Level INFO
    if ($result.ErrorMessage -eq 'Repository already exists') {
        Write-LogMessage "  Note     : Repo already existed, remote was configured" -Level WARN
    }
}
else {
    Write-LogMessage "=== FAILED ===" -Level ERROR
    Write-LogMessage "  Error: $($result.ErrorMessage)" -Level ERROR
    exit 1
}
