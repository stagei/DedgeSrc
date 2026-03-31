Import-Module GlobalFunctions -Force
Import-Module Deploy-Handler -Force

$pushAllToFkx = $false

#find all the deploy.ps1 files and run them
Get-ChildItem -Path $PSScriptRoot -Recurse -Include _deploy.ps1 | ForEach-Object {
  Write-Host "Running $($_.FullName)" -ForegroundColor Yellow
  Push-Location -Path $_.Directory
  if ($pushAllToFkx) {
    Deploy-Files -FromFolder $_.Directory -DeployModules $false -ForcePush
  }
  else {
    & $_.FullName
  }

  Pop-Location
}
$path = "$env:OptPath\src\DedgePsh\_Modules"
Set-Location $path
Import-Module Deploy-Handler -Force
if ($pushAllToFkx) {
  Deploy-Files -FromFolder $path -DeployModules $true -ForcePush
}
else {
  Deploy-Files -FromFolder $path -DeployModules $true -ComputerNameList "*"
}

# Get-ChildItem -Path . -Filter "deploy.ps1" -Recurse | ForEach-Object {
#   $newName = $_.DirectoryName + "\_deploy.ps1"
#   Rename-Item -Path $_.FullName -NewName $newName -Force -Verbose
# }

GlobalFunctions\Send-Sms -Receiver "+4797188358" -Message "DeployAll.ps1 completed"

