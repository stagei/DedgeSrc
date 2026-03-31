<#
.SYNOPSIS
    Applies database permissions to INLTST after restore.

.DESCRIPTION
    Standalone fix script that grants all necessary database-level privileges
    to admin users on the INLTST database (DB2 instance). Uses Windows auth
    (service account) instead of db2nt credentials to avoid SQL1060N issues
    after a cross-instance restore.

    This script exists because Set-DatabasePermissions may fail if db2nt
    lacks CONNECT privilege immediately after restore.
#>

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

. (Join-Path $PSScriptRoot "_helpers\_Shared.ps1")
$cfgPath = if ($env:Db2ShadowConfigPath -and (Test-Path $env:Db2ShadowConfigPath)) { $env:Db2ShadowConfigPath } else { Get-ShadowDatabaseConfigPath -ScriptRoot $PSScriptRoot }
if (-not (Test-Path $cfgPath)) { throw "Config not found. Ensure config.*.json exists for this computer." }
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json

$instanceName = $cfg.SourceInstance
$databaseName = $cfg.SourceDatabase

$ctlWorkObj = Get-DefaultWorkObjects -DatabaseType PrimaryDb -DatabaseName $databaseName -QuickMode -SkipDb2StateInfo
if ($ctlWorkObj -is [array]) { $ctlWorkObj = $ctlWorkObj[-1] }
$ctlWorkObj = Get-ControlSqlStatement -WorkObject $ctlWorkObj -SelectCount -ForceGetControlSqlStatement
if ($ctlWorkObj -is [array]) { $ctlWorkObj = $ctlWorkObj[-1] }
$controlTable = $ctlWorkObj.TableToCheck

Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED
Write-LogMessage "Applying permissions to $($databaseName) on instance $($instanceName)" -Level INFO

$adminUsers = @("FKGEISTA", "FKSVEERI", "SRV_SFKSS07", "SRV_DB2", "t1_srv_inltst_db",
                "FKPRDADM", "FKTSTADM", "FKDEVADM", "DB2NT")

try {
    $workFolder = Get-ApplicationDataPath
    $batFile = Join-Path $workFolder "Fix-ApplyPermissions_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat"

    $db2Commands = @()
    $db2Commands += "set DB2INSTANCE=$($instanceName)"
    $db2Commands += "db2 connect to $($databaseName)"

    foreach ($user in $adminUsers) {
        if ($user.ToLower().Trim() -eq $env:USERNAME.ToLower().Trim()) {
            continue
        }
        $db2Commands += "db2 grant bindadd on database to user $($user)"
        $db2Commands += "db2 grant connect on database to user $($user)"
        $db2Commands += "db2 grant createtab on database to user $($user)"
        $db2Commands += "db2 grant dbadm on database to user $($user)"
        $db2Commands += "db2 grant implicit_schema on database to user $($user)"
        $db2Commands += "db2 grant load on database to user $($user)"
        $db2Commands += "db2 grant quiesce_connect on database to user $($user)"
        $db2Commands += "db2 grant secadm on database to user $($user)"
        $db2Commands += "db2 grant sqladm on database to user $($user)"
        $db2Commands += "db2 grant wlmadm on database to user $($user)"
        $db2Commands += "db2 grant explain on database to user $($user)"
        $db2Commands += "db2 grant dataaccess on database to user $($user)"
        $db2Commands += "db2 grant accessctrl on database to user $($user)"
        $db2Commands += "db2 grant create_secure_object on database to user $($user)"
        $db2Commands += "db2 grant create_external_routine on database to user $($user)"
        $db2Commands += "db2 grant create_not_fenced_routine on database to user $($user)"
    }

    $db2Commands += "db2 `"SELECT COUNT(*) AS ROW_COUNT FROM $($controlTable)`""
    $db2Commands += "db2 connect reset"
    $db2Commands += "db2 terminate"

    $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName $batFile -IgnoreErrors
    Write-LogMessage "Grant output: $($output)" -Level INFO

    if ($output -match "SQL1024N") {
        throw "SQL1024N: No database connection - grants could not be applied"
    }

    if ($output -match "(\d+)\s+post(?:er)?\s+er\s+valgt") {
        $countMatch = [regex]::Match($output, "(\d+)\s+post(?:er)?\s+er\s+valgt")
        $rowCount = $countMatch.Groups[1].Value
        Write-LogMessage "Control SQL verified: $($controlTable) = $($rowCount) rows" -Level INFO
    }
    elseif ($output -match "ROW_COUNT\s*\r?\n\s*-+\s*\r?\n\s*(\d+)") {
        $countMatch = [regex]::Match($output, "ROW_COUNT\s*\r?\n\s*-+\s*\r?\n\s*(\d+)")
        $rowCount = $countMatch.Groups[1].Value
        Write-LogMessage "Control SQL verified: $($controlTable) = $($rowCount) rows" -Level INFO
    }
    else {
        Write-LogMessage "Could not parse row count from control SQL output" -Level WARN
    }

    Write-LogMessage "Permissions applied successfully to $($databaseName)" -Level INFO

    $smsNumber = switch ($env:USERNAME) {
        "FKGEISTA" { "+4797188358" }
        "FKSVEERI" { "+4795762742" }
        "FKMISTA"  { "+4799348397" }
        "FKCELERI" { "+4745269945" }
        default    { "+4797188358" }
    }
    Send-Sms -Receiver $smsNumber -Message "Fix-ApplyPermissions DONE: $($databaseName) on $($instanceName). Grants applied for $($adminUsers.Count) users."

    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
    exit 0
}
catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
    Send-Sms -Receiver "+4797188358" -Message "Fix-ApplyPermissions FAILED: $($_.Exception.Message)"
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    exit 1
}
