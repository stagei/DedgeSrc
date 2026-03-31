param(
    [Parameter(Mandatory = $true)]
    [string]$DatabaseName,
    [Parameter(Mandatory = $false)]
    [string]$InstanceName = "DB2"
)

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

try {
    Write-LogMessage "$(Split-Path -Path $PSScriptRoot -Leaf)" -Level JOB_STARTED

    $appDataPath = Get-ApplicationDataPath
    Set-OverrideAppDataFolder -Path $appDataPath

    Write-LogMessage "=== Db2 Connect Diagnostic for $($DatabaseName) on $($env:COMPUTERNAME) ===" -Level INFO

    $db2pdCommands = @()
    $db2pdCommands += "set DB2INSTANCE=$($InstanceName)"
    $db2pdCommands += "echo === DB2PD RECOVERY STATUS ==="
    $db2pdCommands += "db2pd -db $($DatabaseName) -recovery"
    $db2pdCommands += "echo === DB2PD ACTIVE DATABASES ==="
    $db2pdCommands += "db2pd -alldbs -active"
    $db2pdCommands += "echo === DB2PD DATABASE SUMMARY ==="
    $db2pdCommands += "db2pd -db $($DatabaseName) -dbcfg"
    $db2pdCommands += "echo === DONE ==="

    Write-LogMessage "Running db2pd diagnostic commands..." -Level INFO
    $output = Invoke-Db2ContentAsScript -Content $db2pdCommands -ExecutionType BAT -IgnoreErrors

    Write-LogMessage "=== FULL OUTPUT ===" -Level INFO
    Write-Output $output

    $svcInfo = Get-CimInstance Win32_Service |
        Where-Object { $_.Name -match '^DB2' } |
        Select-Object Name, DisplayName, StartName, State |
        Format-Table -AutoSize | Out-String
    Write-LogMessage "=== DB2 WINDOWS SERVICES ===" -Level INFO
    Write-Output $svcInfo

    Write-LogMessage "$(Split-Path -Path $PSScriptRoot -Leaf)" -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Diagnostic failed: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage "$(Split-Path -Path $PSScriptRoot -Leaf)" -Level JOB_FAILED
    exit 1
}
finally {
    Reset-OverrideAppDataFolder
}
