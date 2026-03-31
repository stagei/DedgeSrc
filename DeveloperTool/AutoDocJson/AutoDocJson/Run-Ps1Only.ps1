#Requires -Version 7
<#
.SYNOPSIS
    Process only PowerShell files.
.DESCRIPTION
    Clean regeneration of PowerShell documentation only.
#>
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot 'AutoDocJson.exe'
& $exe -Regenerate All -FileTypes Ps1 -Parallel -GenerateHtml
