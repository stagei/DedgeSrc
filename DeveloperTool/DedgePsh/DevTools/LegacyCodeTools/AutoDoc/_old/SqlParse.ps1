# SqlParse.ps1
# SQL Table Parser - Thin wrapper
# Geir Helge Starholm
# Parse and extract SQL table metadata for AutoDoc HTML generation
#
# This script delegates to Start-SqlParse in the AutodocFunctions module.
# The full implementation is in _Modules/AutodocFunctions/SqlParseFunctions.psm1

param(
    [Parameter(Mandatory)][string]$sqlTable,
    [bool]$show = $false,
    [string]$outputFolder = "$env:OptPath\Webs\AutoDoc",
    [bool]$cleanUp = $true,
    [string]$tmpRootFolder = "$env:OptPath\data\AutoDoc\tmp",
    [string]$srcRootFolder = "$env:OptPath\data\AutoDoc\src"
)

Import-Module -Name GlobalFunctions -Force
Import-Module -Name AutodocFunctions -Force

# Delegate to module function
Start-SqlParse -SqlTable $sqlTable `
    -Show $show `
    -OutputFolder $outputFolder `
    -CleanUp $cleanUp `
    -TmpRootFolder $tmpRootFolder `
    -SrcRootFolder $srcRootFolder
