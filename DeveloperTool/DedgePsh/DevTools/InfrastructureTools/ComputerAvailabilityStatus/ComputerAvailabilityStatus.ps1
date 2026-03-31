Import-Module Infrastructure -Force
Import-Module GlobalFunctions -Force

try {
    Write-LogMessage  $(Get-InitScriptName) -Level JOB_STARTED
    Set-ComputerAvailabilityStatus
    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED

    Exit 9
}

