<#
.SYNOPSIS
    Creates a new Azure DevOps repo initialized with only an empty README.md.

.DESCRIPTION
    Lightweight wrapper around New-AzureDevOpsRepo (AzureFunctions module) that:
      1. Creates a temporary folder
      2. Places an empty README.md inside it
      3. Creates the repo in Azure DevOps, commits, and pushes
      4. Clones the new repo to $env:OptPath\Src\<RepoName> (or a custom path)

    Useful for bootstrapping repos that will be populated later.

.PARAMETER RepoName
    Name of the new Azure DevOps repository (mandatory).

.PARAMETER Organization
    Azure DevOps organization. Default: Dedge.

.PARAMETER Project
    Azure DevOps project. Default: Dedge.

.PARAMETER CloneTo
    Local path to clone the new repo into after creation.
    Default: $env:OptPath\Src\<RepoName>.
    Use -SkipClone to skip cloning entirely.

.PARAMETER SkipClone
    Do not clone the repo locally after creation.

.PARAMETER SkipPush
    Create the repo and initialize git but do not commit or push.

.EXAMPLE
    .\New-EmptyAzDevOpsRepo.ps1 -RepoName "MyNewProject"
    # Creates repo, clones to $env:OptPath\Src\MyNewProject

.EXAMPLE
    .\New-EmptyAzDevOpsRepo.ps1 -RepoName "MyNewProject" -CloneTo "C:\opt\src\MyNewProject"

.EXAMPLE
    .\New-EmptyAzDevOpsRepo.ps1 -RepoName "InfraScripts" -Project "Infrastructure" -SkipClone
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$RepoName,

    [string]$Organization = "Dedge",

    [string]$Project = "Dedge",

    [string]$CloneTo = "",

    [switch]$SkipClone,

    [switch]$SkipPush
)

$ErrorActionPreference = 'Stop'

Import-Module GlobalFunctions -Force
Import-Module AzureFunctions -Force

if (-not $CloneTo -and -not $SkipClone) {
    $CloneTo = Join-Path $env:OptPath "Src\$($RepoName)"
}

Write-LogMessage "=== New Empty Azure DevOps Repository ===" -Level INFO
Write-LogMessage "  Repo Name    : $($RepoName)" -Level INFO
Write-LogMessage "  Organization : $($Organization)" -Level INFO
Write-LogMessage "  Project      : $($Project)" -Level INFO
if ($CloneTo) {
    Write-LogMessage "  Clone To     : $($CloneTo)" -Level INFO
}

# ── Create temp folder with empty README.md ──────────────────────────────
$tempRoot = Join-Path $env:TEMP "NewRepo_$($RepoName)_$(Get-Date -Format 'yyyyMMddHHmmss')"
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
Set-Content -Path (Join-Path $tempRoot "README.md") -Value "" -Encoding utf8
Write-LogMessage "Created temp folder with README.md: $($tempRoot)" -Level INFO

# ── Create repo via AzureFunctions module ────────────────────────────────
$result = New-AzureDevOpsRepo `
    -RepoName $RepoName `
    -LocalPath $tempRoot `
    -Organization $Organization `
    -Project $Project `
    -CommitMessage "Initial commit - empty README.md" `
    -SkipPush:$SkipPush

Write-Host ""
if ($result.Success) {
    Write-LogMessage "=== SUCCESS ===" -Level INFO
    Write-LogMessage "  Repo URL : $($result.RemoteUrl)" -Level INFO
    Write-LogMessage "  Repo ID  : $($result.RepoId)" -Level INFO

    if ($result.ErrorMessage -eq 'Repository already exists') {
        Write-LogMessage "  Note     : Repo already existed, remote was configured" -Level WARN
    }

    # ── Clone to local folder ────────────────────────────────────────────
    if ($CloneTo -and -not $SkipClone) {
        if (Test-Path $CloneTo) {
            Write-LogMessage "CloneTo path already exists: $($CloneTo) — skipping clone" -Level WARN
        }
        else {
            Write-LogMessage "Cloning to $($CloneTo)..." -Level INFO
            git clone $result.RemoteUrl $CloneTo 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-LogMessage "Cloned to $($CloneTo)" -Level INFO
            }
            else {
                Write-LogMessage "git clone failed (exit $($LASTEXITCODE))" -Level ERROR
            }
        }
    }
}
else {
    Write-LogMessage "=== FAILED ===" -Level ERROR
    Write-LogMessage "  Error: $($result.ErrorMessage)" -Level ERROR
    exit 1
}
finally {
    if (Test-Path $tempRoot) {
        Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        Write-LogMessage "Cleaned up temp folder" -Level DEBUG
    }
}
