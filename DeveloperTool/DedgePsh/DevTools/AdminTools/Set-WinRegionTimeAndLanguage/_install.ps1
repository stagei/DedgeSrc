
$scriptPath = Join-Path -Path $env:OptPath -ChildPath "DedgePshApps\Set-WinRegionTimeAndLanguage\Set-WinRegionTimeAndLanguage.ps1"
$executePwshUsingScript = "pwsh.exe -File " + $scriptPath
# Add to startup/login
$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$valueName = "Set-WinRegionTimeAndLanguage"
Set-ItemProperty -Path $runKey -Name $valueName -Value $executePwshUsingScript -Type String -Force
Write-Host "Added $scriptPath to startup/login" -ForegroundColor Green

