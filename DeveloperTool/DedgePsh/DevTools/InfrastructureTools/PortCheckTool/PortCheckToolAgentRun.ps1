Import-Module -Name GlobalFunctions -Force
Import-Module -Name SoftwareUtils -Force

Install-OurPshApp -AppName "CommonModules"
Install-OurPshApp -AppName "PortCheckTool"
Install-OurPshApp -AppName "Run-Psh"

& Run-Psh -ReportType Computer

