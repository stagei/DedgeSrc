param(
    [Parameter(Mandatory = $false)]
    [string[]]$SmsNumbers = @()
)

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

try {
    Write-LogMessage "$(Split-Path -Path $MyInvocation.MyCommand.Path -Leaf)" -Level JOB_STARTED

    if (-not (Test-IsServer)) {
        Write-LogMessage "This script must be run on a DB2 server" -Level ERROR
        exit 1
    }

    $appDataPath = Get-ApplicationDataPath
    Set-OverrideAppDataFolder -Path $appDataPath

    # Get all active databases on this server from DatabasesV2.json
    $allDbConfigs = Get-DatabasesV2Json | Where-Object {
        $_.ServerName.ToLower().Trim() -eq $env:COMPUTERNAME.ToLower().Trim() -and
        $_.Provider -eq "DB2" -and
        $_.IsActive -eq $true
    }

    if ($allDbConfigs.Count -eq 0) {
        Write-LogMessage "No active DB2 databases found on $($env:COMPUTERNAME)" -Level WARN
        exit 0
    }

    $exportedFiles = @()
    $failedDatabases = @()

    foreach ($dbConfig in $allDbConfigs) {
        # Find the PrimaryDb access point catalog name
        $primaryAp = $dbConfig.AccessPoints | Where-Object { $_.AccessPointType -eq "PrimaryDb" -and $_.IsActive -eq $true } | Select-Object -First 1
        if ($null -eq $primaryAp) { continue }

        $catalogName = $primaryAp.CatalogName
        try {
            Write-LogMessage "Exporting grants for $catalogName (Database=$($dbConfig.Database))" -Level INFO
            $exportedFile = Export-Db2Grants -DatabaseName $catalogName
            $exportedFiles += $exportedFile
            Write-LogMessage "Exported: $exportedFile" -Level INFO
        }
        catch {
            Write-LogMessage "Failed to export grants for $catalogName`: $($_.Exception.Message)" -Level ERROR -Exception $_
            $failedDatabases += $catalogName
        }

        # Also export federated database grants if one exists
        $fedAp = $dbConfig.AccessPoints | Where-Object { $_.AccessPointType -eq "FederatedDb" -and $_.IsActive -eq $true } | Select-Object -First 1
        if ($null -ne $fedAp) {
            $fedCatalogName = $fedAp.CatalogName
            try {
                Write-LogMessage "Exporting grants for federated $fedCatalogName" -Level INFO
                $exportedFile = Export-Db2Grants -DatabaseName $fedCatalogName
                $exportedFiles += $exportedFile
                Write-LogMessage "Exported: $exportedFile" -Level INFO
            }
            catch {
                Write-LogMessage "Failed to export grants for $fedCatalogName`: $($_.Exception.Message)" -Level ERROR -Exception $_
                $failedDatabases += $fedCatalogName
            }
        }
    }

    $message = "Grant export on $($env:COMPUTERNAME): $($exportedFiles.Count) exported"
    if ($failedDatabases.Count -gt 0) {
        $message += ", $($failedDatabases.Count) failed ($($failedDatabases -join ', '))"
    }
    Write-LogMessage $message -Level INFO

    foreach ($smsNumber in $SmsNumbers) {
        Send-Sms -Receiver $smsNumber -Message $message
    }

    Write-LogMessage "$(Split-Path -Path $PSScriptRoot -Leaf)" -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error during grant export: $($_.Exception.Message)" -Level ERROR -Exception $_
    foreach ($smsNumber in $SmsNumbers) {
        Send-Sms -Receiver $smsNumber -Message "Grant export FAILED on $($env:COMPUTERNAME): $($_.Exception.Message)"
    }
    Write-LogMessage "$(Split-Path -Path $PSScriptRoot -Leaf)" -Level JOB_FAILED -Exception $_
    exit 1
}
finally {
    Reset-OverrideAppDataFolder
}
