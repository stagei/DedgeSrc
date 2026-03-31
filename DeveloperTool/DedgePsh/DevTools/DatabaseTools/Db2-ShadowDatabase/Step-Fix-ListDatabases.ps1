<#
.SYNOPSIS
    Lists all databases on the DB2 instance and checks FKKTOTST specifically.
#>

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

. (Join-Path $PSScriptRoot "_helpers\_Shared.ps1")
$cfgPath = if ($env:Db2ShadowConfigPath -and (Test-Path $env:Db2ShadowConfigPath)) { $env:Db2ShadowConfigPath } else { Get-ShadowDatabaseConfigPath -ScriptRoot $PSScriptRoot }
if (-not (Test-Path $cfgPath)) { throw "Config not found. Ensure config.*.json exists for this computer." }
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
$instanceName = $cfg.SourceInstance

Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED

try {
    $workFolder = Get-ApplicationDataPath
    $batFile = Join-Path $workFolder "ListDatabases_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat"

    $db2Commands = @()
    $db2Commands += "set DB2INSTANCE=$($instanceName)"
    $db2Commands += "echo === DATABASE DIRECTORY ==="
    $db2Commands += "db2 list database directory"
    $db2Commands += "echo === NODE DIRECTORY ==="
    $db2Commands += "db2 list node directory"
    $db2Commands += "echo === DB CFG FOR FKKTOTST ==="
    $db2Commands += "db2 get db cfg for FKKTOTST | findstr /i `"AUTHENTICATION`""
    $db2Commands += "echo === DB CFG FOR INLTST ==="
    $db2Commands += "db2 get db cfg for INLTST | findstr /i `"AUTHENTICATION`""
    $db2Commands += "db2 terminate"

    $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName $batFile -IgnoreErrors
    Write-LogMessage "Output:`n$($output)" -Level INFO

    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
    exit 0
}
catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    exit 1
}
