param(
    [string]$SiteName = "",
    [string]$ParentSite = "Default Web Site"
)

$ErrorActionPreference = "Continue"

Import-Module GlobalFunctions -Force
Import-Module IIS-Handler -Force
Set-OverrideAppDataFolder -Path $(Join-Path $env:OptPath "data" "IIS-DeployApp")
Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_STARTED

try {
    Test-IISSite -SiteName $SiteName -ParentSite $ParentSite
    Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "$($_.Exception.Message)" -Level ERROR 
    Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_FAILED
    exit 1
}
finally {
    Reset-OverrideAppDataFolder
}