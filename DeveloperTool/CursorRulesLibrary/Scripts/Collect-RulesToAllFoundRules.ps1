<#
.SYNOPSIS
    Collects Cursor rules, commands, and skills from projects into _AllFoundRules.

.DESCRIPTION
    Scans $env:OptPath\src for:
    - .cursor\rules\*.mdc
    - .cursor\commands\*.mdc
    - .cursor\skills\**\SKILL.md
    Copies each to _AllFoundRules\<relative path from src>.
    Skips the repo that contains _AllFoundRules (this repo) so Library and _AllFoundRules are not overwritten.
    Requires PowerShell 7+ (pwsh).

.PARAMETER SourceRoot
    Root folder to scan for cursor content files. Default: $env:OptPath\src (fallback: C:\opt\src).

.PARAMETER DestinationRoot
    Root folder for _AllFoundRules. Default: _AllFoundRules under the script directory.

.EXAMPLE
    pwsh.exe -File .\Collect-RulesToAllFoundRules.ps1

.EXAMPLE
    pwsh.exe -File .\Collect-RulesToAllFoundRules.ps1 -WhatIf
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string] $SourceRoot,

    [Parameter()]
    [string] $DestinationRoot
)

$ErrorActionPreference = 'Stop'

# Resolve source root: $env:OptPath\src, fallback C:\opt\src
if (-not $SourceRoot) {
    $optPath = $env:OptPath
    if (-not $optPath) { $optPath = 'C:\opt' }
    $SourceRoot = Join-Path $optPath 'src'
}

# Resolve destination: _AllFoundRules under repo root (parent of Scripts)
if (-not $DestinationRoot) {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $DestinationRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath((Join-Path $repoRoot '_AllFoundRules'))
} else {
    $DestinationRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationRoot)
}

$SourceRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SourceRoot)

# Avoid copying from the repo that contains _AllFoundRules (this repo)
$destParent = Split-Path $DestinationRoot -Parent
$skipPath = $destParent.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar

if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
    Write-Error "Source root does not exist: $SourceRoot"
}

$mdcFiles = Get-ChildItem -Path $SourceRoot -Filter '*.mdc' -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '[\\/]\.cursor[\\/](rules|commands)[\\/]' }
$skillFiles = Get-ChildItem -Path $SourceRoot -Filter 'SKILL.md' -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '[\\/]\.cursor[\\/]skills[\\/]' }
$cursorFiles = @($mdcFiles + $skillFiles)

$copied = 0
$skipped = 0

foreach ($file in $cursorFiles) {
    $fullName = $file.FullName

    # Skip files under the repo that contains _AllFoundRules
    if ($fullName.StartsWith($skipPath, [StringComparison]::OrdinalIgnoreCase)) {
        $skipped++
        continue
    }

    $relativePath = $fullName.Substring($SourceRoot.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar)
    $destPath = Join-Path $DestinationRoot $relativePath
    $destDir = Split-Path -Parent $destPath

    if ($PSCmdlet.ShouldProcess($destPath, 'Copy')) {
        if (-not (Test-Path -LiteralPath $destDir -PathType Container)) {
            New-Item -Path $destDir -ItemType Directory -Force | Out-Null
        }
        Copy-Item -LiteralPath $fullName -Destination $destPath -Force
        $copied++
    }
}

# Prefer Write-LogMessage if GlobalFunctions is available
$msg = "Collect-RulesToAllFoundRules: copied $copied cursor content file(s), skipped $skipped (under destination repo)."
try {
    $null = Get-Command Write-LogMessage -ErrorAction Stop
    Write-LogMessage $msg -Level INFO
} catch {
    Write-Host $msg
}
