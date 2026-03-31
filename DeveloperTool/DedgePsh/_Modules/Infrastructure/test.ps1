Import-Module Infrastructure -Force

Write-Host "`nServer List:" -ForegroundColor Yellow
Get-ServerList | Write-Host

Write-Host "`nServer List (with metadata):" -ForegroundColor Yellow
Get-ServerObjectList | Format-Table

Write-Host "`nDeveloper Machine List:" -ForegroundColor Yellow
Get-WorkstationList | Write-Host

Write-Host "`nDeveloper Machine List (with metadata):" -ForegroundColor Yellow
Get-WorkstationObjectList | Format-Table

Write-Host "`nComputer List:" -ForegroundColor Yellow
Get-ComputerList | Write-Host

Write-Host "`nComputer List (with metadata):" -ForegroundColor Yellow
Get-ComputerObjectList | Format-Table

Write-Host "`nServer Configuration:" -ForegroundColor Yellow
$serverConfig = Get-ServerConfiguration -ComputerName "t-no1fkmtst-app"
$serverConfig | Format-Table

