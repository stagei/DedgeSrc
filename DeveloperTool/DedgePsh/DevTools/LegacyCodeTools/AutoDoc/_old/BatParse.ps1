# BatParse.ps1
# Windows Batch Parser - Thin wrapper
# Geir Helge Starholm
# Parse and extract Windows Batch script flow for mermaid.js diagrams for visualisation
#
# This script delegates to Start-BatParse in the AutodocFunctions module.
# The full implementation is in _Modules/AutodocFunctions/BatParseFunctions.psm1

param(
    [Parameter(Mandatory)][string]$sourceFile,
    [bool]$show = $false,
    [string]$outputFolder = "$env:OptPath\Webs\AutoDoc",
    [bool]$cleanUp = $true,
    [string]$tmpRootFolder = "$env:OptPath\data\AutoDoc\tmp",
    [string]$srcRootFolder = "$env:OptPath\data\AutoDoc\src",
    [switch]$ClientSideRender,
    [switch]$saveMmdFiles
)

Import-Module -Name GlobalFunctions -Force
Import-Module -Name AutodocFunctions -Force

# Delegate to module function
Start-BatParse -SourceFile $sourceFile `
    -Show $show `
    -OutputFolder $outputFolder `
    -CleanUp $cleanUp `
    -TmpRootFolder $tmpRootFolder `
    -SrcRootFolder $srcRootFolder `
    -ClientSideRender:$ClientSideRender `
    -SaveMmdFiles:$saveMmdFiles
