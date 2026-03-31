param(
    [Parameter(Mandatory = $false)]
    [string[]]$SmsNumbers = @()
)

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force
Import-Module Infrastructure -Force

########################################################################################################
# Main
########################################################################################################

Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED
# Check if script is running on a db2 server and as administrator
Test-Db2ServerAndAdmin

$smsNumbers = Get-SmsNumbers
$applicationDataFolder = Get-ApplicationDataPath
Set-OverrideAppDataFolder -Path $applicationDataFolder
try {
    # Send alert that system shutdown/restart event was detected
    $message = "ALERT: System shutdown/restart detected on $($env:COMPUTERNAME)"
    
    Write-LogMessage "Sending shutdown alert for $($env:COMPUTERNAME)" -Level INFO
    Send-FkAlert -Program $(Get-InitScriptName) -Code "7777" -Message $message -Force
    
    foreach ($smsNumber in $smsNumbers) {
        Send-Sms -Receiver $smsNumber -Message $message
    }

    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error during shutdown alert on $($env:COMPUTERNAME): $($_.Exception.Message)" -Level ERROR -Exception $_
    $message = "Error during shutdown alert on $($env:COMPUTERNAME): $($_.Exception.Message)"
    foreach ($smsNumber in $smsNumbers) {
        Send-Sms -Receiver $smsNumber -Message $message
    }
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    exit 1
}
finally {
    Reset-OverrideAppDataFolder
}

