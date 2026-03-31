Import-Module Deploy-Handler -Force
Import-Module GlobalFunctions -Force

$toFolderPath = Join-Path $(Get-DevToolsWebPath) "Software And Infrastructure Tools" 
New-Item -Path $toFolderPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

$mdDeployPath = Join-Path $PSScriptRoot "Sjekkliste for tilgangsbestilling av ny utviklermaskin.md"
$toPath = Join-Path $toFolderPath "Sjekkliste for tilgangsbestilling av ny utviklermaskin.md"  
Copy-Item -Path $mdDeployPath -Destination $toPath -Force
Write-LogMessage -Message "Deployed `"Sjekkliste for tilgangsbestilling av ny utviklermaskin.md`" to $toPath"