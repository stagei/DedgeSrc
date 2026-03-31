Import-Module GlobalFunctions -Force
Import-Module Agent-Handler -Force
#$computerNameList = Get-ValidServerNameList
$computerNameList = @("*inlprd-db")
Deploy-AgentTask -TaskName "Install-LogFile-Remover" -SourceScript "Import-Module SoftwareUtils -Force; Install-OurPshApp -AppName LogFile-Remover" -ComputerNameList $computerNameList  -WaitForJsonFile $true

