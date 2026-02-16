#Requires -Version 7.0
<#
.SYNOPSIS
    Runs a Cursor CLI (agent) codebase query and writes the result to Markdown.

.DESCRIPTION
    Ensures the Cursor CLI is available, then runs agent -p with the given query
    from the specified workspace directory. Output is written to a .md file.

.PARAMETER Query
    Natural-language question (codebase will be used as context). Default: short project summary.

.PARAMETER WorkspacePath
    Folder to run the query from (must be your Cursor workspace so index is available). Default: parent of this script (DedgeSrc root).

.PARAMETER OutputPath
    Path to the output .md file. Default: .\output\result_yyyyMMdd_HHmmss.md

.PARAMETER SkipInstallCheck
    Do not check for agent/cursor in PATH; run anyway (may fail).

.EXAMPLE
    pwsh.exe -File .\Test-CursorDocIndexQuery.ps1
    pwsh.exe -File .\Test-CursorDocIndexQuery.ps1 -Query "List all PowerShell scripts in this repo. Answer in Markdown."
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string] $Query = "List the main folders and important files in this project. Answer in Markdown with a short bullet list.",
    [string] $WorkspacePath = (Split-Path $PSScriptRoot -Parent),
    [string] $OutputPath = "",
    [switch] $SkipInstallCheck
)

$ErrorActionPreference = 'Stop'

if (-not $OutputPath) {
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $outDir = Join-Path $PSScriptRoot 'output'
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    $OutputPath = Join-Path $outDir "result_$($timestamp).md"
}

# Resolve workspace to absolute path
$WorkspacePath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($WorkspacePath)
if (-not (Test-Path -LiteralPath $WorkspacePath -PathType Container)) {
    Write-Error "WorkspacePath does not exist: $($WorkspacePath)"
}

# Find Cursor CLI: prefer 'agent', then 'cursor'
$cliName = $null
if (-not $SkipInstallCheck) {
    foreach ($name in @('agent', 'cursor')) {
        $exe = Get-Command -Name $name -ErrorAction SilentlyContinue
        if ($exe) {
            $cliName = $name
            break
        }
    }
    if (-not $cliName) {
        Write-Host "Cursor CLI (agent) not found in PATH. Run: pwsh.exe -File $($PSScriptRoot)\Install-CursorCli.ps1"
        Write-Host "Then add the install directory to PATH (e.g. $env:USERPROFILE\.local\bin) and try again."
        exit 1
    }
} else {
    $cliName = 'agent'
}

Write-Host "Using CLI: $($cliName), Workspace: $($WorkspacePath), Output: $($OutputPath)"
Write-Host "Query: $($Query)"

$prevPwd = Get-Location
try {
    Set-Location -LiteralPath $WorkspacePath
    $output = & $cliName -p $Query 2>&1
    $output | Out-File -FilePath $OutputPath -Encoding utf8
    Write-Host "Result written to: $($OutputPath)"
} finally {
    Set-Location -LiteralPath $prevPwd
}
