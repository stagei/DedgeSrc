#Requires -Version 7
<#
.SYNOPSIS
    Process only C# solution files.
.DESCRIPTION
    Clean regeneration of C# solution documentation only.
#>
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot 'AutoDocJson.exe'
& $exe -Regenerate All -FileTypes CSharp -Parallel -GenerateHtml
