Import-Module GlobalFunctions -Force
Import-Module SoftwareUtils -Force
try {
    Write-LogMessage $(Split-Path -Path $MyInvocation.MyCommand.Path) -Level JOB_STARTED
    Set-CursorAndVsCodeConfiguration
    Write-LogMessage $(Split-Path -Path $MyInvocation.MyCommand.Path) -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage $(Split-Path -Path $MyInvocation.MyCommand.Path) -Level JOB_FAILED
}

