<#
.SYNOPSIS
    Reconfigures DB2 instance authentication to KRB_SERVER_ENCRYPT.

.DESCRIPTION
    Updates the DBM configuration on the DB2 (SourceInstance) to use
    KRB_SERVER_ENCRYPT instead of plain KERBEROS. This allows both
    Kerberos and server-encrypted password authentication.
    Requires db2stop/db2start to take effect.
#>

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

. (Join-Path $PSScriptRoot "_helpers\_Shared.ps1")
$cfgPath = if ($env:Db2ShadowConfigPath -and (Test-Path $env:Db2ShadowConfigPath)) { $env:Db2ShadowConfigPath } else { Get-ShadowDatabaseConfigPath -ScriptRoot $PSScriptRoot }
if (-not (Test-Path $cfgPath)) { throw "Config not found. Ensure config.*.json exists for this computer." }
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json

$instanceName = $cfg.SourceInstance

Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED
Write-LogMessage "Reconfiguring authentication on instance $($instanceName) to KRB_SERVER_ENCRYPT" -Level INFO

try {
    $workFolder = Get-ApplicationDataPath
    $batFile = Join-Path $workFolder "ReconfigAuth_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat"

    $db2Commands = @()
    $db2Commands += "set DB2INSTANCE=$($instanceName)"
    $db2Commands += "db2 get dbm cfg | findstr /i AUTHENTICATION"
    $db2Commands += "db2 update dbm cfg using authentication KRB_SERVER_ENCRYPT"
    $db2Commands += "db2 get dbm cfg | findstr /i AUTHENTICATION"
    $db2Commands += "db2stop force"
    $db2Commands += "db2start"
    $db2Commands += "db2 get dbm cfg | findstr /i AUTHENTICATION"
    $db2Commands += "db2 terminate"

    $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName $batFile -IgnoreErrors
    Write-LogMessage "Reconfig output: $($output)" -Level INFO

    Write-LogMessage "Authentication reconfigured to KRB_SERVER_ENCRYPT on instance $($instanceName)" -Level INFO
    Send-Sms -Receiver "+4797188358" -Message "DB2 auth reconfig DONE: $($instanceName) set to KRB_SERVER_ENCRYPT."

    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
    exit 0
}
catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
    Send-Sms -Receiver "+4797188358" -Message "DB2 auth reconfig FAILED: $($_.Exception.Message)"
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    exit 1
}
