#Requires -Version 7
<#
.SYNOPSIS
    Process only SQL table files.
.DESCRIPTION
    Clean regeneration of SQL table documentation only.
#>
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot 'AutoDocJson.exe'
& $exe -Regenerate All -FileTypes Sql -Parallel -GenerateHtml
