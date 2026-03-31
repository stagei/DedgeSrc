Import-Module Infrastructure -Force
$allShortcuts = Update-ServerShorcuts -OutputPath "$env:OptPath\ServerShortcuts"
$jsonOutputPath = Join-Path $(Get-ApplicationDataPath) "ShortcutInfo.json"
$allShortcuts | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonOutputPath
Write-LogMessage "Saved shortcuts to json file $jsonOutputPath" -Level INFO

