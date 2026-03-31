#Requires -Version 7
<#
.SYNOPSIS
    Incremental documentation update (default mode).
.DESCRIPTION
    Only processes files that have changed since the last run.
    Fastest option for daily use.
#>
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot 'AutoDocJson.exe'
& $exe -Regenerate Incremental -Parallel
