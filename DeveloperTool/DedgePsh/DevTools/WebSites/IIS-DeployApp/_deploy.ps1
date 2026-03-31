param (
    [bool]$DeployModules = $true
)
Import-Module Deploy-Handler -Force -ErrorAction Stop
Deploy-Files -FromFolder $PSScriptRoot -ComputerNameList @("dedge-server", "p-no1fkxprd-app", "p-no1fkxprd-db") -DeployModules $DeployModules
