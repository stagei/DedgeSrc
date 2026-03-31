Import-Module GlobalFunctions -Force -ErrorAction Stop
Import-Module Db2-Handler -Force -ErrorAction Stop

try {
    Write-LogMessage "Creating tables for DBQTST database" -Level INFO
    $workObject = Get-DefaultWorkObjects -DatabaseType "PrimaryDb" -InstanceName "DB2Q" -SmsNumbers @("+4797188358") -QuickMode
    # Handle Db2CreateDBQA_Teardown.sql file
    $db2Commands = (Get-Content -Path $(Join-Path $PSScriptRoot "Db2CreateDBQA_Teardown.sql") -Raw) -split "`n"
    $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType SQL  -IgnoreErrors -FileName $(Join-Path $WorkObject.WorkFolder "Db2CreateDBQA_Teardown.sql") -InstanceName $workObject.InstanceName
    $workObject = Add-ScriptAndOutputToWorkObject -WorkObject $workObject -Name "CreateTablesTeardown" -Script $db2Commands -Output $output
    if ($workObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $workObject = $workObject[-1] }

    # Handle Db2CreateDBQA_Related.sql file
    $db2Commands = (Get-Content -Path $(Join-Path $PSScriptRoot "Db2CreateDBQA_Related.sql") -Raw) -split "`n"
    $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType SQL -IgnoreErrors -FileName $(Join-Path $WorkObject.WorkFolder "Db2CreateDBQA_Related.sql") -InstanceName $workObject.InstanceName
    $workObject = Add-ScriptAndOutputToWorkObject -WorkObject $workObject -Name "CreateTablesRelated" -Script $db2Commands -Output $output
    if ($workObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $workObject = $workObject[-1] }

    # Handle Db2CreateDBQA_NonRelated.sql file
    $db2Commands = (Get-Content -Path $(Join-Path $PSScriptRoot "Db2CreateDBQA_NonRelated.sql") -Raw) -split "`n"
    $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType SQL -IgnoreErrors -FileName $(Join-Path $WorkObject.WorkFolder "Db2CreateDBQA_NonRelated.sql") -InstanceName $workObject.InstanceName
    $workObject = Add-ScriptAndOutputToWorkObject -WorkObject $workObject -Name "CreateTablesNonRelated" -Script $db2Commands -Output $output
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

