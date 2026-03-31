
# Import the module
Import-Module SoftwareUtils -Force

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "Test-RunPsh.ps1: Starting test of Run-Psh parameter passing" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

Start-OurPshApp -AppName "Run-Psh" -Arguments @("Db2Server-InstallHandler\Db2Server-Install.ps1")

