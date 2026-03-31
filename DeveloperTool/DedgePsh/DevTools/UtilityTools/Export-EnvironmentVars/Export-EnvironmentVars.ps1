# Get environment variables for both Machine and User
$machineVars = [Environment]::GetEnvironmentVariables('Machine')
$userVars = [Environment]::GetEnvironmentVariables('User')

# Create timestamp for filenames
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# Export Machine environment variables
$machineExportPath = ".\MachineEnvVars_$timestamp.txt"
$machineVars.GetEnumerator() | Sort-Object Name | ForEach-Object {
    "$($_.Name)=$($_.Value)"
} | Out-File -FilePath $machineExportPath -Encoding UTF8

# Export User environment variables
$userExportPath = ".\UserEnvVars_$timestamp.txt"
$userVars.GetEnumerator() | Sort-Object Name | ForEach-Object {
    "$($_.Name)=$($_.Value)"
} | Out-File -FilePath $userExportPath -Encoding UTF8

Write-Host "Environment variables exported successfully:" -ForegroundColor Green
Write-Host "Machine variables: $machineExportPath" -ForegroundColor Cyan
Write-Host "User variables: $userExportPath" -ForegroundColor Cyan

