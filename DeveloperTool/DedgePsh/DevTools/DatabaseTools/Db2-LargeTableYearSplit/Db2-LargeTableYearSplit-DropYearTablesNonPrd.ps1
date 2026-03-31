param(
    [Parameter(Mandatory = $false)]
    [string]$DatabaseName = "",
    [Parameter(Mandatory = $false)]
    [string]$ConfigFilePath = "$(Join-Path $PSScriptRoot "ArchiveTables.json")"
)

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

try {
    Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED
    Test-Db2ServerAndAdmin

    if (-not (Test-Path -Path $ConfigFilePath -PathType Leaf)) {
        throw "Config file not found: $($ConfigFilePath)"
    }

    $dbContext = Get-Db2DatabaseContext -RequestedDatabaseName $DatabaseName
    if ($dbContext.Environment -eq "PRD") {
        throw "This script is blocked for PRD databases. Selected database $($dbContext.DatabaseName) has environment PRD."
    }

    $workObject = Get-DefaultWorkObjectsCommon -DatabaseName $dbContext.DatabaseName -DatabaseType PrimaryDb -InstanceName $dbContext.InstanceName -QuickMode
    if ($workObject -is [array]) { $workObject = $workObject[-1] }

    $rules = Get-Content -Path $ConfigFilePath -Raw | ConvertFrom-Json
    $rulesForApp = @($rules | Where-Object { $_.ApplicationName.ToUpper() -eq $dbContext.Application.ToUpper() })
    if ($rulesForApp.Count -eq 0) {
        throw "No config rules found for application $($dbContext.Application)."
    }

    $candidateTables = @()
    foreach ($rule in $rulesForApp) {
        $tableParts = Split-Db2QualifiedTableName -QualifiedTableName $rule.TableName
        $candidateTables += Get-Db2YearSplitTables -WorkObject $workObject -SchemaName $tableParts.SchemaName -BaseName $tableParts.BaseName
    }
    $candidateTables = @($candidateTables | Sort-Object SchemaName, TableName -Unique)

    if ($candidateTables.Count -eq 0) {
        Write-LogMessage "No *_YYYY tables found to drop for $($dbContext.DatabaseName)." -Level INFO
        Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
        return
    }

    Write-LogMessage "Candidate *_YYYY tables for drop in database $($dbContext.DatabaseName):" -Level WARN
    Write-LogMessage ($candidateTables | Select-Object SchemaName, TableName, Year | Format-Table -AutoSize | Out-String) -Level WARN

    $confirmation = Get-UserConfirmationWithTimeout -PromptMessage "Drop these tables now? (Y/N)" -TimeoutSeconds 60 -AllowedResponses @("Y", "N") -DefaultResponse "N" -ProgressMessage "Confirm table drop"
    if ($confirmation -ne "Y") {
        Write-LogMessage "Drop cancelled by user." -Level WARN
        Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
        return
    }

    $dropCommands = @()
    $dropCommands += Get-SetInstanceNameCommand -WorkObject $workObject
    $dropCommands += Get-ConnectCommand -WorkObject $workObject
    foreach ($table in $candidateTables) {
        $dropCommands += "db2 `"DROP TABLE $($table.SchemaName).$($table.TableName)`""
    }
    $dropCommands += "db2 connect reset"
    $dropCommands += "db2 terminate"
    $dropOutput = Invoke-Db2ContentAsScript -Content $dropCommands -ExecutionType BAT -IgnoreErrors:$false

    Write-LogMessage "Drop completed. Output summary:" -Level INFO
    Write-LogMessage $dropOutput -Level INFO
    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error in non-PRD drop script: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    exit 1
}
