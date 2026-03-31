<#
.SYNOPSIS
    Fixes SRVCON_AUTH and ALTERNATE_AUTH_ENC to allow JDBC password connections.

.DESCRIPTION
    Sets SRVCON_AUTH to KRB_SERVER_ENCRYPT (was KERBEROS) so incoming
    JDBC connections can use encrypted password fallback.
    Sets ALTERNATE_AUTH_ENC to AES_256_CBC for JCC Type 4 driver compatibility.
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
Write-LogMessage "Fixing SRVCON_AUTH and ALTERNATE_AUTH_ENC on instance $($instanceName)" -Level INFO

try {
    $workFolder = Get-ApplicationDataPath
    $batFile = Join-Path $workFolder "FixSrvconAuth_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat"

    $db2Commands = @()
    $db2Commands += "set DB2INSTANCE=$($instanceName)"
    $db2Commands += "echo === BEFORE ==="
    $db2Commands += "db2 get dbm cfg | findstr /i `"SRVCON_AUTH ALTERNATE_AUTH_ENC AUTHENTICATION`""
    $db2Commands += "db2 update dbm cfg using SRVCON_AUTH KRB_SERVER_ENCRYPT"
    $db2Commands += "db2 update dbm cfg using ALTERNATE_AUTH_ENC AES_256_CBC"
    $db2Commands += "echo === AFTER (pending restart) ==="
    $db2Commands += "db2 get dbm cfg | findstr /i `"SRVCON_AUTH ALTERNATE_AUTH_ENC AUTHENTICATION`""
    $db2Commands += "db2stop force"
    $db2Commands += "db2start"
    $db2Commands += "echo === AFTER RESTART ==="
    $db2Commands += "db2 get dbm cfg | findstr /i `"SRVCON_AUTH ALTERNATE_AUTH_ENC AUTHENTICATION`""
    $db2Commands += "db2 terminate"

    $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName $batFile -IgnoreErrors
    Write-LogMessage "Fix output:`n$($output)" -Level INFO

    Send-Sms -Receiver "+4797188358" -Message "SRVCON_AUTH fixed to KRB_SERVER_ENCRYPT + AES_256_CBC. JDBC should work now."

    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
    exit 0
}
catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
    Send-Sms -Receiver "+4797188358" -Message "SRVCON_AUTH fix FAILED: $($_.Exception.Message)"
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    exit 1
}
