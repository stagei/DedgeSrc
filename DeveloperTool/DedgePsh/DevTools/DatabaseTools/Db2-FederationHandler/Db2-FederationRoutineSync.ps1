param(
    [Parameter(Mandatory = $false)]
    [string]$InstanceName = "DB2",
    [Parameter(Mandatory = $false)]
    [string]$TargetDatabaseName = "",
    [Parameter(Mandatory = $false)]
    [string]$LinkedDatabaseName = "",
    [Parameter(Mandatory = $false)]
    [string[]]$SmsNumbers = @()
)

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

try {
    Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED

    Test-Db2ServerAndAdmin

    if (-not $PSBoundParameters.ContainsKey('SmsNumbers')) {
        $SmsNumbers = Get-UserChoiceForSmsNumbers
    }

    if ([string]::IsNullOrEmpty($TargetDatabaseName)) {
        $TargetDatabaseName = Get-FederatedDbNameFromInstanceName -InstanceName $InstanceName
        if ([string]::IsNullOrEmpty($TargetDatabaseName)) {
            Write-LogMessage "Federated database not found for instance $($InstanceName). Aborting." -Level WARN
            exit 1
        }
    }
    if ([string]::IsNullOrEmpty($LinkedDatabaseName)) {
        $LinkedDatabaseName = Get-PrimaryDbNameFromInstanceName -InstanceName $InstanceName
    }

    Write-LogMessage "Routine sync via db2look: $($LinkedDatabaseName) (primary) -> $($TargetDatabaseName) (federated)" -Level INFO

    $targetWorkObject = Get-DefaultWorkObjectsCommon -DatabaseName $TargetDatabaseName -SkipRecreateDb2Folders -SkipDb2StateInfo
    if ($targetWorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $targetWorkObject = $targetWorkObject[-1] }

    $linkedWorkObject = Get-DefaultWorkObjectsCommon -DatabaseName $LinkedDatabaseName -SkipRecreateDb2Folders -SkipDb2StateInfo
    if ($linkedWorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $linkedWorkObject = $linkedWorkObject[-1] }

    Add-Member -InputObject $targetWorkObject -NotePropertyName "LinkedPrimaryDatabaseName" -NotePropertyValue $linkedWorkObject.DatabaseName -Force
    Add-Member -InputObject $targetWorkObject -NotePropertyName "LinkedPrimaryInstanceName" -NotePropertyValue $linkedWorkObject.InstanceName -Force

    $targetWorkObject = Sync-FederatedRoutines -WorkObject $targetWorkObject

    $message = "Routine sync $($TargetDatabaseName)<-$($LinkedDatabaseName) on $($env:COMPUTERNAME): $($targetWorkObject.RoutinesAdded) added, $($targetWorkObject.RoutinesDropped) dropped"
    Write-LogMessage $message -Level INFO
    foreach ($smsNumber in $SmsNumbers) {
        Send-Sms -Receiver $smsNumber -Message $message
    }

    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    $message = "Error during routine sync $($TargetDatabaseName)<-$($LinkedDatabaseName) on $($env:COMPUTERNAME): $($_.Exception.Message)"
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED -Exception $_
    foreach ($smsNumber in $SmsNumbers) {
        Send-Sms -Receiver $smsNumber -Message $message
    }
    exit 1
}
finally {
    Reset-OverrideAppDataFolder
}
