#Requires -Version 7
<#
.SYNOPSIS
    Process only COBOL files.
.DESCRIPTION
    Clean regeneration of COBOL documentation only.
#>
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot 'AutoDocJson.exe'
& $exe -Regenerate All -FileTypes Cbl -Parallel -GenerateHtml
