param(
    [Parameter(Mandatory = $true)]
    [string]$InstanceName
)
Import-Module Deploy-Handler -Force -ErrorAction Stop
Import-Module Db2-Handler -Force -ErrorAction Stop

$workObject = Get-DefaultWorkObjects -DatabaseType "PrimaryDb" -InstanceName $InstanceName -QuickMode
$db2Commands = @()
$db2Commands += "db2 rollforward db $($workObject.DatabaseName) to end of logs and stop overflow log path($($workObject.LogtargetFolder))"
$db2Commands += "db2start"
$db2Commands += "db2 activate db $($workObject.DatabaseName)"
$db2Commands += " "

$output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName "$(Join-Path $workObject.WorkFolder "RollForward.bat")"
$workObject = Add-ScriptAndOutputToWorkObject -WorkObject $workObject -Name "RollForward" -Script ($db2Commands -join "`n") -Output $output
Write-LogMessage "Rollforward completed" -Level INFO

