Import-Module GlobalFunctions -Force
Import-Module Deploy-Handler -Force

$pushAllToDb2 = $true
$ComputerNameList = "*-db"
#find all the deploy.ps1 files and run them
$deployFiles = @()
$deployFiles += Get-ChildItem -Path $PSScriptRoot -Recurse -Include _deploy.ps1
foreach ($item in $deployFiles) {
  if ($item.FullName -like "*_old*" -or $item.FullName -like "*_UNSORTED MISC F9ILES*" -or $item.FullName -like "*DEPRECATED*" ) {
    continue
  }
  Write-Host "Running $($item.FullName)" -ForegroundColor Yellow
  Push-Location -Path $item.Directory
  if ($pushAllToDb2) {
    Deploy-Files -FromFolder $item.Directory -DeployModules $false -ComputerNameList $ComputerNameList
  }
  else {
    & $item.FullName
  }

  Pop-Location
}
$path = "$env:OptPath\src\DedgePsh\_Modules"
Set-Location $path
Import-Module Deploy-Handler -Force
if ($pushAllToDb2) {
  Deploy-Files -FromFolder $path -DeployModules $true -ForcePush
}
else {
  Deploy-Files -FromFolder $path -DeployModules $true -ComputerNameList $ComputerNameList
}

GlobalFunctions\Send-Sms -Receiver "+4797188358" -Message "DeployAll.ps1 completed"

