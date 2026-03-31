param(
    [Parameter(Mandatory = $false)]
    [string[]]$SmsNumbers = @()
)

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force
Import-Module Infrastructure -Force
Import-Module Export-Array -Force

########################################################################################################
# Main
########################################################################################################

Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED
Set-LogLevel -Level TRACE
# Check if script is running on a db2 server and as administrator
# $smsNumbers = Get-SmsNumbers
$smsNumbers = @()
$applicationDataFolder = Get-ApplicationDataPath
Set-OverrideAppDataFolder -Path $applicationDataFolder
try {
    # Get list of databases
    $allDb2Databases = Get-DatabasesV2Json | Where-Object { $_.IsActive -eq $true -and $_.Provider -eq "DB2" }
    #$allDb2Databases = Get-DatabasesV2Json | Where-Object { $_.IsActive -eq $true -and $_.Provider -eq "DB2" -and $_.Database -like "*INL*" }

    # Get work objects for each database
    $workObjectList = @()
    foreach ($dbConfig in $allDb2Databases) {
        # Get work object for database
        $workObject = Get-DefaultWorkObjectsCommon -DatabaseName $dbConfig.Database -DatabaseType "PrimaryDb" -QuickMode
        if ($workObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $workObject = $workObject[-1] }

        # Build common param object for Db2 client configuration
        $commonParamObject = [PSCustomObject]@{
            ServerName           = $workObject.ServerName
            Platform             = $workObject.Platform
            Version              = $workObject.Version
            DatabaseName         = $workObject.DatabaseName
            ServiceUserName      = $workObject.ServiceUserName
            AuthenticationType   = $workObject.RemoteAccessPoint.AuthenticationType
            IsActive             = $true
            AccessPointType      = $workObject.RemoteAccessPoint.AccessPointType
            RemotePort           = $workObject.RemoteAccessPoint.Port
            RemoteServiceName    = $workObject.RemoteAccessPoint.ServiceName
            RemoteNodeName       = $workObject.RemoteAccessPoint.NodeName
            RemoteDatabaseName   = $workObject.RemoteAccessPoint.CatalogName
        }
        # Get db2 script for client configuration
        $commonParamObject = Invoke-Db2ClientConfiguration -CommonParamObject $commonParamObject
        $db2CatalogScript = $commonParamObject.ClientTypeResultArray | Where-Object { $_.ClientType -eq "Db2Client" } | Select-Object -ExpandProperty Result

        # Get control sql statement
        $workObject = Get-ControlSqlStatement -WorkObject $workObject
        if ($workObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $workObject = $workObject[-1] }

        $controlSqlStatement = $workObject.ControlSqlStatement

        $db2Commands = @()
        #$db2Commands += $($db2CatalogScript.Split("`n") | Where-Object { $_ -ne "" })
        $db2Commands += "db2 connect to $($commonParamObject.RemoteDatabaseName)"
        $db2Commands += $controlSqlStatement
        $db2Commands += "db2 connect reset"
        try {
            $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $workObject.WorkFolder "$($MyInvocation.MyCommand.Name)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat")" -Quiet
            $workObject = Add-ScriptAndOutputToWorkObject -WorkObject $workObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output
            $resultObj = [PSCustomObject]@{
                DatabaseName       = $workObject.DatabaseName
                RemoteDatabaseName = $workObject.RemoteAccessPoint.CatalogName
                Result             = $true
                Level              = "INFO"
                Message            = "Successfully verified connection"
            }
            Add-Member -InputObject $workObject -NotePropertyName "ResultObject" -NotePropertyValue $resultObj -Force
            Write-LogMessage "Successfully verified connection" -Level INFO
        }
        catch {
            Write-LogMessage "Error executing db2 commands for database $($workObject.DatabaseName): $($_.Exception.Message)" -Level WARN
            $workObject = Add-ScriptAndOutputToWorkObject -WorkObject $workObject -Name "$($MyInvocation.MyCommand.Name)" -Script $($db2Commands -join "`n") -Output $output
            $resultObj = [PSCustomObject]@{
                DatabaseName       = $workObject.DatabaseName
                RemoteDatabaseName = $workObject.RemoteAccessPoint.CatalogName
                Result             = $false
                Level              = "ERROR"
                Message            = $_.Exception.Message
            }
            Add-Member -InputObject $workObject -NotePropertyName "ResultObject" -NotePropertyValue $resultObj -Force
        }
        # Write-Output $output
        # Add work object to list
        $workObjectList += $workObject
    }

    # create pscustomobject from work object list fileds database name, control sql statement result
    $result = @()
    foreach ($workObject in $workObjectList) {
        $result += $workObject.ResultObject
    }
    $result | Format-Table -AutoSize

    # Save the result as JSON to the network share
    $jsonResult = $result | ConvertTo-Json -Depth 8
    $outputPath = "$(Get-CommonLogPath)\Db2\Server"
    if (-not(Test-Path $outputPath)) {
        New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
    }
    $outputFileJson = Join-Path $outputPath "Db2VerifyConnectivityFrom$(Get-CurrentComputerPlatform)Computer_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    [System.IO.File]::WriteAllText($outputFileJson, $jsonResult, [System.Text.Encoding]::UTF8)
    Write-LogMessage "Saved verification result as JSON to $outputFileJson" -Level INFO

    $outputFileHtml = Join-Path (Get-ApplicationDataPath) "Db2-VerifyDatabaseConnectivity From$(Get-CurrentComputerPlatform) Platform.html"
    Export-ArrayToHtmlFile -Content $result -OutputPath $outputFileHtml -Title "Db2-VerifyDatabaseConnectivity from $(Get-CurrentComputerPlatform) platform" -AddToDevToolsWebPath $true -DevToolsWebDirectory "Db2"
    Write-LogMessage "Saved verification result as HTML to $outputFileHtml" -Level INFO

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

