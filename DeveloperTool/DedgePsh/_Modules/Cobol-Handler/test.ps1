Import-Module -Name Cobol-Handler -Force

$returnObject = Get-CobolEnvironmentVariables -Application "INL" -Environment "TST" -Version "MF" -Architecture "x86" -EnvironmentSource "User"

Write-Host ($returnObject | ConvertTo-Json -Depth 10)

