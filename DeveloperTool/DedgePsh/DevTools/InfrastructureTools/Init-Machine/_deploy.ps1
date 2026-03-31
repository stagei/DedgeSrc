Import-Module Deploy-Handler -Force
Import-Module GlobalFunctions -Force
Deploy-Files -FromFolder $PSScriptRoot

$toFolderPath = Join-Path $(Get-DevToolsWebPath) "Rutiner\Oppsett av maskiner" 
New-Item -Path $toFolderPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

$htmlDeployPath = Join-Path $PSScriptRoot "Oppsett av ny utviklermaskin.html"
$toPath = Join-Path $toFolderPath "Oppsett av ny utviklermaskin.html"  
Copy-Item -Path $htmlDeployPath -Destination $toPath -Force 
Write-LogMessage -Message "Deployed `"Oppsett av ny utviklermaskin.html`" to $toPath"

$htmlDeployPath = Join-Path $PSScriptRoot "Oppsett av ny server.html"
$toPath = Join-Path $toFolderPath "Oppsett av ny server.html"  
Copy-Item -Path $htmlDeployPath -Destination $toPath -Force
Write-LogMessage -Message "Deployed `"Oppsett av ny server.html`" to $toPath"

$htmlDeployPath = Join-Path $PSScriptRoot "Oppsett av ny andre FK brukere.html"
$toPath = Join-Path $toFolderPath "Oppsett av ny andre FK brukere.html"
Copy-Item -Path $htmlDeployPath -Destination $toPath -Force
Write-LogMessage -Message "Deployed `"Oppsett av ny andre FK brukere.html`" to $toPath"

$htmlDeployPath = Join-Path $PSScriptRoot "Oppsett av ny utviklermaskin på AVD.html"
$toPath = Join-Path $toFolderPath "Oppsett av ny utviklermaskin på AVD.html"  
Copy-Item -Path $htmlDeployPath -Destination $toPath -Force
Write-LogMessage -Message "Deployed `"Oppsett av ny utviklermaskin på AVD.html`" to $toPath"
