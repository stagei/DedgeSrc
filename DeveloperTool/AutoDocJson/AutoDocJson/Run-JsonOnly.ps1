#Requires -Version 7
<#
.SYNOPSIS
    Regenerate JSON index files only.
.DESCRIPTION
    Rebuilds the JSON index/metadata without re-parsing any source files.
    Use after manual edits to output or to refresh indexes.
#>
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot 'AutoDocJson.exe'
& $exe -Regenerate JsonOnly -Parallel
