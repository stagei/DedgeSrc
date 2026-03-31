param(
    [Parameter(Mandatory = $false)]
    [string[]]$SmsNumbers = @()
)

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force
Import-Module Infrastructure -Force
<#
.SYNOPSIS
    Returns DB2 grant commands for the environment-matching DEDGE RDO and DBA users.
.DESCRIPTION
    Resolves the correct RDO and DBA user names from WorkObject.Environment and returns:
    - RDO user: GRANT CONNECT ON DATABASE
    - DBA user: GRANT CONNECT ON DATABASE + full DBADM permissions (Get-CommandsForDatabasePermissions)
.PARAMETER WorkObject
    Work object from Get-DefaultWorkObjects (must have .Environment property).
.OUTPUTS
    [PSCustomObject] with RdoUser, DbaUser, and Db2Commands properties.
#>
function Get-DEDGEDb2UserGrantCommands {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )
    $envName = $WorkObject.Environment
    $rdoUser = switch ($envName) {
        "PRD" { "FKPRDRDO" }
        "DEV" { "FKDEVDRDO" }
        default { "FKTSTDRDO" }
    }
    $dbaUser = switch ($envName) {
        "PRD" { "FKPRDDBA" }
        "DEV" { "FKDEVDBA" }
        default { "FKTSTDBA" }
    }
    $db2Commands = @()
    $db2Commands += "db2 grant connect on database to user $rdoUser"
    $db2Commands += "db2 grant connect on database to user $dbaUser"
    $db2Commands += @(Get-CommandsForDatabasePermissions -UserName $dbaUser)
    return [PSCustomObject]@{
        RdoUser     = $rdoUser
        DbaUser     = $dbaUser
        Db2Commands = $db2Commands
    }
}

########################################################################################################
# Main
########################################################################################################
# Create an empty array to hold user account PSObjects

Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED
# Check if script is running on a db2 server and as administrator
Test-Db2ServerAndAdmin

$smsNumbers = Get-SmsNumbers
$applicationDataFolder = Get-ApplicationDataPath
Set-OverrideAppDataFolder -Path $applicationDataFolder
try {
    $instanceList = Get-InstanceNameList
    $additionalMessage = ""
    foreach ($instance in $instanceList) {
        Write-LogMessage "Processing instance $($instance)" -Level INFO
        $primaryDatabaseNames = Get-DatabaseNameList -InstanceName $instance -DatabaseType "PrimaryDb"
        $federatedDatabaseNames = Get-DatabaseNameList -InstanceName $instance -DatabaseType "FederatedDb"
        $allDatabaseInfos = @()
        foreach ($db in $primaryDatabaseNames) { $allDatabaseInfos += [PSCustomObject]@{ DatabaseName = $db; DatabaseType = "PrimaryDb" } }
        foreach ($db in $federatedDatabaseNames) { $allDatabaseInfos += [PSCustomObject]@{ DatabaseName = $db; DatabaseType = "FederatedDb" } }

        foreach ($databaseInfo in $allDatabaseInfos) {
            $workObject = Get-DefaultWorkObjects -DatabaseName $databaseInfo.DatabaseName -InstanceName $instance -DatabaseType $databaseInfo.DatabaseType -SkipDb2StateInfo -QuickMode
            if ($null -eq $workObject -or ($workObject -is [array] -and $workObject.Count -eq 0)) {
                Write-LogMessage "Could not get work object for $($databaseInfo.DatabaseName). Skipping." -Level WARN
                continue
            }
            if ($workObject -is [array]) { Write-LogMessage "Multiple database configurations returned" -Level WARN; $workObject = $workObject[-1] }

            $grantResult = Get-DEDGEDb2UserGrantCommands -WorkObject $workObject

            $db2Commands = @()
            $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $workObject)
            $db2Commands += $(Get-ConnectCommand -WorkObject $workObject)
            $db2Commands += "db2 connect to $($workObject.DatabaseName)"
            $db2Commands += $grantResult.Db2Commands
            $db2Commands += "db2 terminate"

            $additionalMessage += "RDO=$($grantResult.RdoUser), DBA=$($grantResult.DbaUser) on $($workObject.DatabaseName)`n"

            $fileName = Join-Path $workObject.WorkFolder "Db2-AddNewUserAccounts_$($workObject.DatabaseName)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat"
            $null = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName $fileName -IgnoreErrors
            Write-LogMessage "Applied DEDGE grants for $($workObject.DatabaseName)" -Level INFO

            $workObject = Add-SpecificGrants -WorkObject $workObject
            if ($workObject -is [array]) { Write-LogMessage "Multiple database configurations returned" -Level WARN; $workObject = $workObject[-1] }
        }
    }

    $message = "Db2-AddNewUserAccounts SUCCESS on $($env:COMPUTERNAME)`n$($additionalMessage)"
    Send-FkAlert -Program $(Get-InitScriptName) -Code "0000" -Message $message -Force
    foreach ($smsNumber in $smsNumbers) {
        Send-Sms -Receiver $smsNumber -Message $message
    }

    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error during Db2-AddNewUserAccounts on $($env:COMPUTERNAME): $($_.Exception.Message)" -Level ERROR -Exception $_
    $message = "Error during Db2-AddNewUserAccounts on $($env:COMPUTERNAME): $($_.Exception.Message)"
    foreach ($smsNumber in $smsNumbers) {
        Send-Sms -Receiver $smsNumber -Message $message
    }
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    exit 1
}
finally {
    Reset-OverrideAppDataFolder
}

