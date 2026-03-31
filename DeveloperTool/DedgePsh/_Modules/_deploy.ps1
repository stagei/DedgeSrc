param (
    [string]$ComputerNameList = "", 
    [switch]$ForcePush = $false
)

# if ($env:PsModulePath -eq "") {
#   $env:PsModulePath = "$env:USERPROFILE\Documents\PowerShell\Modules;C:\Program Files\PowerShell\Modules;c:\program files\powershell\7\Modules;C:\Program Files\WindowsPowerShell\Modules;C:\Windows\system32\WindowsPowerShell\v1.0\Modules;$env:OptPath\src\DedgePsh\_Modules;$env:OptPath\DedgePshApps\CommonModules;$env:OptPath\DedgePshApps\_Modules"
# }
# $env:PsModulePath = "$env:USERPROFILE\Documents\PowerShell\Modules;C:\Program Files\PowerShell\Modules;c:\program files\powershell\7\Modules;C:\Program Files\WindowsPowerShell\Modules;C:\Windows\system32\WindowsPowerShell\v1.0\Modules;$env:OptPath\src\DedgePsh\_Modules;$env:OptPath\DedgePshApps\CommonModules;$env:OptPath\DedgePshApps\_Modules"
# REG DELETE "HKEY_CURRENT_USER\Environment" /f /v "PsModulePath" | Out-Null
# REG DELETE "HKEY_LOCAL_MACHINE\Environment" /f /v "PsModulePath" | Out-Null
# [System.Environment]::SetEnvironmentVariable('PsModulePath', $env:PsModulePath, [System.EnvironmentVariableTarget]::Machine)

# if ([string]::IsNullOrEmpty($env:OptPath)) {
#   $env:OptPath = "$env:OptPath"
# }
# REG DELETE "HKEY_CURRENT_USER\Environment" /f /v "OptPath" | Out-Null
# REG DELETE "HKEY_LOCAL_MACHINE\Environment" /f /v "OptPath" | Out-Null
# [System.Environment]::SetEnvironmentVariable('OptPath', $env:OptPath, [System.EnvironmentVariableTarget]::Machine)
# Refresh list of available modules
# Write-Host "Refreshing list of available modules before deployment" -ForegroundColor Blue
# Get-Module -ListAvailable -Refresh 

Write-Host "------------------------------------------------------------------------------------------------" -ForegroundColor White
Write-Host "PsModulePath:" -ForegroundColor Blue
Write-Host "------------------------------------------------------------------------------------------------" -ForegroundColor White
$env:PsModulePath.Split(';') | ForEach-Object { Write-Host "   $_" -ForegroundColor White }
Write-Host "------------------------------------------------------------------------------------------------" -ForegroundColor White

Import-Module GlobalFunctions -Force
Import-Module Deploy-Handler -Force
Write-Host "Resetting list of available modules before deployment" -ForegroundColor Blue
Start-ModuleRefresh

# Deploy DedgeSign from folder
Write-Host "Deploying DedgeSign before all module deployments" -ForegroundColor Blue
Deploy-Files -FromFolder "$env:OptPath\src\DedgePsh\DevTools\CodingTools\DedgeSign" 

# Deploy all modules from folder
Write-Host "Deploying all modules from $PSScriptRoot" -ForegroundColor Blue
Deploy-Files -FromFolder $PSScriptRoot -ComputerNameList @(Get-ValidServerNameList) -ForcePush:$ForcePush


#Send-Sms -Receiver "+4797188358" -Message "Deploying all modules"
