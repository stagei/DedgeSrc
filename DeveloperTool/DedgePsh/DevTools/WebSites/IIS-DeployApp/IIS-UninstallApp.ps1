param(
    [string]$SiteName = "",
    [switch]$RemoveFiles,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

Import-Module GlobalFunctions -Force
Import-Module IIS-Handler -Force
Set-OverrideAppDataFolder -Path $(Join-Path $env:OptPath "data" "IIS-DeployApp")
Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_STARTED

try {
    Uninstall-IISApp -SiteName $SiteName -RemoveFiles:$RemoveFiles -Force:$Force
    Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "$($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_FAILED
    exit 1
}
finally {
    Reset-OverrideAppDataFolder
}