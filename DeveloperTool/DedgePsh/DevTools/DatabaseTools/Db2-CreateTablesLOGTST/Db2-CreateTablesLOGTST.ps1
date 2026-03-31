Import-Module GlobalFunctions -Force -ErrorAction Stop
Import-Module Db2-Handler -Force -ErrorAction Stop

try {
    Write-LogMessage "Creating tables for LOGTST database" -Level INFO
    $workObject = Get-DefaultWorkObjects -DatabaseType "PrimaryDb" -InstanceName "DB2" -SmsNumbers @("+4797188358") -QuickMode
    $db2Commands = (Get-Content -Path $(Join-Path $PSScriptRoot "DB2_Schema.sql") -Raw) -split "`n"
    $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType SQL -FileName $(Join-Path $WorkObject.WorkFolder "DB2_Schema.sql") -InstanceName $workObject.InstanceName -IgnoreErrors
    $workObject = Add-ScriptAndOutputToWorkObject -WorkObject $workObject -Name "CreateTablesLOGTST" -Script $db2Commands -Output $output
    if ($workObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $workObject = $workObject[-1] }
    Export-WorkObjectToJson -WorkObject $workObject -Path $(Join-Path $workObject.WorkFolder "WorkObject.json")
    Export-WorkObjectToHtml -WorkObject $workObject -Path $(Join-Path $workObject.WorkFolder "WorkObject.html")
    Start-Process -FilePath $(Join-Path $workObject.WorkFolder "WorkObject.html")
}
catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR
    throw $_
}
finally {
    Write-LogMessage "Script completed" -Level INFO
}

