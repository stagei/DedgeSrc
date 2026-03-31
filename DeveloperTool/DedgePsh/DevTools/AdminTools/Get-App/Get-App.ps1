
param (
    [Parameter(Mandatory = $false)]
    [string]$AppType = "",
    [Parameter(Mandatory = $false)]
    [string]$Options = ""
    )
Import-Module SoftwareUtils -Force
Import-Module GlobalFunctions -Force
Import-Module Deploy-Handler -Force
if ($AppType -eq "" -or $AppType -eq "--All") {
    Install-SelectedApps -AppType "--All" -Options $Options
}
elseif ($AppType -eq "--OurPsh" -or $AppType -eq "--OurWin" -or $AppType -eq "--Windows" -or $AppType -eq "--Winget") {
    Install-SelectedApps -AppType $AppType -Options $Options
}
elseif ($Options -eq "--updateAll" -and ($AppType -eq "--OurPsh" -or $AppType -eq "--OurWin")) {
    Install-SelectedApps -AppType $AppType -Options "--updateAll"
}
else {
    Write-Host "Usage: Get-App [--OurPsh] [--OurWin] [--Windows] [--Winget] [--updateAll]"
    Write-Host " "
    Write-Host "Options:"
    Write-Host "  --updateAll   Update all installed applications (PowerShell apps only)"
    Write-Host "Example:"
    Write-Host "  Get-App                                     # Shows all available apps"
    Write-Host "  Get-App --OurPsh                             # Shows available OurPsh apps"
    Write-Host "  Get-App --OurWin                             # Shows available OurWin apps"
    Write-Host "  Get-App --Windows                           # Shows available Windows apps"
    Write-Host "  Get-App --Winget                            # Shows available Winget apps"
    Write-Host "  Get-App --OurPsh --updateAll                 # Updates all OurPsh apps"
    Write-Host "  Get-App --OurWin --updateAll                 # Updates all OurWin apps"
    exit
}

