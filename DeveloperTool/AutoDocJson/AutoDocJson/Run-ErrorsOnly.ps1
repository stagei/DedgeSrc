#Requires -Version 7
<#
.SYNOPSIS
    Retry only files that previously failed.
.DESCRIPTION
    Re-processes only files that had errors in the last run.
    Useful after fixing a parser bug to reprocess just the failures.
#>
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot 'AutoDocJson.exe'
& $exe -Regenerate Errors -Parallel
