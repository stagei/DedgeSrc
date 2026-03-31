<#
.SYNOPSIS
    Diagnostic script to check DB2 authentication configuration for JDBC compatibility.
#>

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

. (Join-Path $PSScriptRoot "_helpers\_Shared.ps1")
$cfgPath = if ($env:Db2ShadowConfigPath -and (Test-Path $env:Db2ShadowConfigPath)) { $env:Db2ShadowConfigPath } else { Get-ShadowDatabaseConfigPath -ScriptRoot $PSScriptRoot }
if (-not (Test-Path $cfgPath)) { throw "Config not found. Ensure config.*.json exists for this computer." }
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
$instanceName = $cfg.SourceInstance

Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED
Write-LogMessage "Checking authentication config on instance $($instanceName)" -Level INFO

try {
    $workFolder = Get-ApplicationDataPath
    $batFile = Join-Path $workFolder "CheckAuthConfig_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat"

    $db2Commands = @()
    $db2Commands += "set DB2INSTANCE=$($instanceName)"
    $db2Commands += "echo === DBM CONFIG ==="
    $db2Commands += "db2 get dbm cfg | findstr /i `"AUTHENTICATION SRVCON_AUTH ALTERNATE_AUTH_ENC CLNT_KRB_PLUGIN CLNT_PW_PLUGIN SRVCON_PW_PLUGIN SRV_PLUGIN_MODE LOCAL_GSSPLUGIN SRVCON_GSSPLUGIN`""
    $db2Commands += "echo === DB2COMM ==="
    $db2Commands += "db2set -all"
    $db2Commands += "echo === DB2 REGISTRY ==="
    $db2Commands += "db2set -i $($instanceName) -all"
    $db2Commands += "db2 terminate"

    $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName $batFile -IgnoreErrors
    Write-LogMessage "Auth config output:`n$($output)" -Level INFO

    Send-Sms -Receiver "+4797188358" -Message "DB2 auth config check done for $($instanceName). Check log."

    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
    exit 0
}
catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    exit 1
}
