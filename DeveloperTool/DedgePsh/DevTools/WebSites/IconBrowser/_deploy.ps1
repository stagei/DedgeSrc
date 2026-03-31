Import-Module Deploy-Handler -Force
Import-Module GlobalFunctions -Force

$toFolderPath = Join-Path $(Get-DevToolsWebPath) "Programmering" 
New-Item -Path $toFolderPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

$htmlDeployPath = Join-Path $PSScriptRoot "IconBrowser.html"
$toPath = Join-Path $toFolderPath "IconBrowser.html"  
Copy-Item -Path $htmlDeployPath -Destination $toPath -Force 
Write-LogMessage -Message "Deployed `"IconBrowser.html`" to $toPath"
