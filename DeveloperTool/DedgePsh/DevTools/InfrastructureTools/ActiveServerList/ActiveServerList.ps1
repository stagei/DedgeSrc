# Requires -Version 5.1
Import-Module CommonFunctions -Force
Import-Module Infrastructure -Force
Import-Module Export-Array -Force
$array = Get-ServerObjectList

$ouputFolder = Join-Path $(Get-DevToolsWebPath) "Active Server List"
if (-not (Test-Path $ouputFolder -PathType Container)) {
    New-Item -ItemType Directory -Path $ouputFolder
}
$outputPath = Join-Path $ouputFolder "Active Server List.html"
$result = Export-ArrayToHtmlFile -Content $array -Title "Active Server List" -AutoOpen:$false -OutputPath $outputPath -AddToDevToolsWebPath "Server"
if ($null -ne $result) {
    Write-LogMessage "Exported results to HTML file: " $result -Level INFO
}
else {
    Write-LogMessage "Failed to export results to HTML file" -Level ERROR
}

$ouputFolder = $(Get-ScriptLogPath)
if (-not (Test-Path $ouputFolder -PathType Container)) {
    New-Item -ItemType Directory -Path $ouputFolder
}

$outputPath = Join-Path $ouputFolder "Active Server List.csv"
Write-LogMessage "Exported results to HTML file: " $(Export-ArrayToCsvFile -Content $array -OutputPath $outputPath -Delimiter "|" -AutoOpen ) -Level INFO

