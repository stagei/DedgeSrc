#Requires -Version 7
<#
.SYNOPSIS
    Process only Object-Rexx files.
.DESCRIPTION
    Clean regeneration of Object-Rexx documentation only.
#>
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot 'AutoDocJson.exe'
& $exe -Regenerate All -FileTypes Rex -Parallel -GenerateHtml
