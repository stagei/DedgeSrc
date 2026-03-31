# Run-GetApp.ps1
# Wrapper script to call Get-App with the right parameters

param (
    [Parameter(Mandatory = $false)]
    [string]$Command = "",

    [Parameter(Mandatory = $false)]
    [string]$AppType = "--All"
)

# Display script parameters
Write-Host "Run-GetApp.ps1 - Wrapper for Get-App" -ForegroundColor Cyan
Write-Host "Command: $Command" -ForegroundColor Cyan
Write-Host "AppType: $AppType" -ForegroundColor Cyan

# Import required modules
Import-Module SoftwareUtils -Force

# Call Install-SelectedApps with the correct AppType directly
if ($Command -eq "--update") {
    # For update command, call Get-App with update parameter
    & "${env:OptPath}\DedgePshApps\Get-App\Get-App.ps1" "--update"
}
else {
    # For all other cases, call Install-SelectedApps directly with the AppType
    Write-Host "Calling Install-SelectedApps with AppType: $AppType" -ForegroundColor Green
    Install-SelectedApps -AppType $AppType
}

Write-Host "Run-GetApp.ps1 completed" -ForegroundColor Cyan

