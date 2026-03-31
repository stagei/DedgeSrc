# Test run for Pdf2Markdown with Rocket Visual Cobol readme PDF
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$inputPdf = 'C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\Rocket Visual Cobol For Visual Studio 2022\visual_cobol_for_visual_studio_2022_11.0_patch_update_3_readme.pdf'
$outputDir = Join-Path $PSScriptRoot 'output'

& py pdf2markdown.py $inputPdf -o $outputDir --open
