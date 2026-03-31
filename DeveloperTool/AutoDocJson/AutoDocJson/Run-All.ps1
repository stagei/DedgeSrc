#Requires -Version 7
<#
.SYNOPSIS
    Regenerate all documentation (without cleaning output first).
.DESCRIPTION
    Re-processes every source file regardless of last-run state.
    Output folder is preserved, existing files are overwritten.
#>
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot 'AutoDocJson.exe'
& $exe -Regenerate All -Parallel -GenerateHtml
