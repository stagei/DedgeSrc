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
    $db2Commands = @()
    $instanceList = Get-InstanceNameList
    $additionalMessage = ""
    foreach ($instance in $instanceList) {
        $databaseList = Get-DatabaseNameList -InstanceName $instance -DatabaseType "PrimaryDb"
        $databaseList += Get-DatabaseNameList -InstanceName $instance -DatabaseType "FederatedDb"
        $db2Commands += "set DB2INSTANCE=$($instance)"
        $db2Commands += "db2start"
        foreach ($database in $databaseList) {
            $db2Commands += "db2 activate database $($database)"
            $additionalMessage += "Database $($database) activated on instance $($instance)`n"
        }
        $db2Commands += "db2 terminate"
        $db2Commands += ""
    }
    $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $applicationDataFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -IgnoreErrors
    $output | Out-File -FilePath "$(Join-Path $applicationDataFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').txt")"

    $message = "Db2-StartAfterReboot SUCCESS of databases on $($env:COMPUTERNAME)`n$($additionalMessage)"
    Send-FkAlert -Program $(Get-InitScriptName) -Code "0000" -Message $message -Force
    foreach ($smsNumber in $smsNumbers) {
        Send-Sms -Receiver $smsNumber -Message $message
    }

    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error during starting Db2 databases on $($env:COMPUTERNAME): $($_.Exception.Message)" -Level ERROR
    $message = "Error during starting Db2 databases on $($env:COMPUTERNAME): $($_.Exception.Message)"
    foreach ($smsNumber in $smsNumbers) {
        Send-Sms -Receiver $smsNumber -Message $message
    }
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    exit 1
}
finally {
    Reset-OverrideAppDataFolder
}

