Import-Module -Name FKASendSMSDirect -Force
FKASendSMSDirect -receiver "+4797188358" -message "Orchestrator.ps1 is starting"
$pathHere = $$
$pos = $pathHere.LastIndexOf("\")
$pathHere = $pathHere.Substring(0, $pos)

Set-Location "$env:OptPath\src\DedgePsh\DevTools\VisualCobolRunScripts"
$command = "$env:OptPath\src\DedgePsh\DevTools\VisualCobolRunScripts" + "\SetupEnv.bat"
Invoke-Expression $command
$command = "$env:OptPath\src\DedgePsh\DevTools\VisualCobolRunScripts" + "\deploy.bat"
Invoke-Expression $command

# Start local powershell scripts
Set-Location $pathHere
.\VisualCobolCodeSearch.ps1
.\VisualCobolCodeReplace.ps1
.\VisualCobolMoveCode.ps1

Set-Location "$env:OptPath\src\DedgePsh\DevTools\VisualCobolBatchCompile"
.\VisualCobolBatchCompile.ps1

FKASendSMSDirect -receiver "+4797188358" -message "Orchestrator.ps1 is done with EVERYTHING!!!"

