param(
    [Parameter(Mandatory = $false)]
    [string]$DatabaseName = "FKMKAT",
    [Parameter(Mandatory = $false)]
    [string]$InstanceName = "DB2"
)

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED

try {
    $reportFile = New-Db2ErrorDiagnosisReport -DatabaseName $DatabaseName -InstanceName $InstanceName
    Write-Host ""
    Write-Host "Report saved to: $reportFile" -ForegroundColor Green
    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error during diagnosis: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    exit 1
}
