Import-Module Infrastructure -Force
Import-Module $PSScriptRoot/Export-Array -Force

Write-Host "`nTesting Export Functions with Computer List:" -ForegroundColor Yellow
$computers = Get-ComputerObjectList

# Test CSV Export
Write-Host "`nExporting to CSV:" -ForegroundColor Cyan
$csvPath = $computers | Export-ArrayToCsvFile
Write-Host "CSV exported to: $csvPath"

# Test HTML Export
Write-Host "`nExporting to HTML:" -ForegroundColor Cyan
$htmlPath = $computers | Export-ArrayToHtmlFile -Title "Computer Status Report"
Write-Host "HTML exported to: $htmlPath"

# Test TXT Export
Write-Host "`nExporting to TXT:" -ForegroundColor Cyan
$txtPath = $computers | Export-ArrayToTxtFile -Title "Computer Status Report"
Write-Host "TXT exported to: $txtPath"

# Test JSON Export
Write-Host "`nExporting to JSON:" -ForegroundColor Cyan
$jsonPath = $computers | Export-ArrayToJsonFile -Pretty
Write-Host "JSON exported to: $jsonPath"

# Test XML Export
Write-Host "`nExporting to XML:" -ForegroundColor Cyan
$xmlPath = $computers | Export-ArrayToXmlFile -RootElementName "ComputerStatus"
Write-Host "XML exported to: $xmlPath"

# Test Markdown Export
Write-Host "`nExporting to Markdown:" -ForegroundColor Cyan
$mdPath = $computers | Export-ArrayToMarkdownFile -Title "Computer Status Report"
Write-Host "Markdown exported to: $mdPath"

# Show file contents preview
Write-Host "`nFile Content Previews:" -ForegroundColor Yellow

Write-Host "`nHTML Preview (first 50 lines):" -ForegroundColor Cyan
Get-Content $htmlPath | Select-Object -First 50

Write-Host "`nCSV Preview (first 50 lines):" -ForegroundColor Cyan
Get-Content $csvPath | Select-Object -First 50

Write-Host "`nJSON Preview (first 50 lines):" -ForegroundColor Cyan
Get-Content $jsonPath | Select-Object -First 50

Write-Host "`nXML Preview (first 50 lines):" -ForegroundColor Cyan
Get-Content $xmlPath | Select-Object -First 50

Write-Host "`nMarkdown Preview (first 50 lines):" -ForegroundColor Cyan
Get-Content $mdPath | Select-Object -First 50

Write-Host "`nTXT Preview (first 50 lines):" -ForegroundColor Cyan
Get-Content $txtPath | Select-Object -First 50

