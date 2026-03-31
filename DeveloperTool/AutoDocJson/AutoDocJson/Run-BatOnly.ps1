#Requires -Version 7
<#
.SYNOPSIS
    Process only Batch files.
.DESCRIPTION
    Clean regeneration of Batch file documentation only.
#>
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot 'AutoDocJson.exe'
& $exe -Regenerate All -FileTypes Bat -Parallel -GenerateHtml
