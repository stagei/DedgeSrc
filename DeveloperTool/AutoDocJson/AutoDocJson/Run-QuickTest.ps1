#Requires -Version 7
<#
.SYNOPSIS
    Quick test run - 5 files per type.
.DESCRIPTION
    Clean regeneration limited to 5 files per type for fast validation.
    Good for testing parser changes without waiting for a full run.
#>
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot 'AutoDocJson.exe'
& $exe -Regenerate Clean -MaxFilesPerType 5 -Parallel -GenerateHtml
