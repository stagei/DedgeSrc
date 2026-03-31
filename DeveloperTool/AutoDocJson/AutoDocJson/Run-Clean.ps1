#Requires -Version 7
<#
.SYNOPSIS
    Full clean regeneration of all documentation.
.DESCRIPTION
    Wipes all generated output and regenerates everything from scratch.
    Use this after major changes or to fix corrupted output.
#>
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot 'AutoDocJson.exe'
& $exe -Regenerate Clean -Parallel -GenerateHtml
