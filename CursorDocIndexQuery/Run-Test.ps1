#Requires -Version 7.0
<#
.SYNOPSIS
    Installs Cursor CLI if missing, then runs a test codebase query and writes Markdown output.

.DESCRIPTION
    Runs Install-CursorCli.ps1 when agent/cursor is not in PATH, then runs
    Test-CursorDocIndexQuery.ps1. Optional parameters are passed to the test script.

.EXAMPLE
    pwsh.exe -File .\Run-Test.ps1
    pwsh.exe -File .\Run-Test.ps1 -Query "List all .ps1 files. Answer in Markdown."
#>

param(
    [string] $Query = "",
    [string] $WorkspacePath = "",
    [string] $OutputPath = "",
    [switch] $SkipInstall
)

$scriptDir = $PSScriptRoot
$installScript = Join-Path $scriptDir 'Install-CursorCli.ps1'
$testScript = Join-Path $scriptDir 'Test-CursorDocIndexQuery.ps1'

# Ensure CLI is available unless skip requested
if (-not $SkipInstall) {
    $hasAgent = Get-Command -Name 'agent' -ErrorAction SilentlyContinue
    $hasCursor = Get-Command -Name 'cursor' -ErrorAction SilentlyContinue
    if (-not $hasAgent -and -not $hasCursor) {
        Write-Host "Cursor CLI not found. Running install..."
        & $installScript
        # Reload PATH so agent might be found in same session if install added it
        $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'User') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    }
}

$testArgs = @()
if ($Query) { $testArgs += '-Query', $Query }
if ($WorkspacePath) { $testArgs += '-WorkspacePath', $WorkspacePath }
if ($OutputPath) { $testArgs += '-OutputPath', $OutputPath }

& $testScript @testArgs
