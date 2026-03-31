param(
    [Parameter(Mandatory = $false)]
    [string]$DatabaseName = "",
    [Parameter(Mandatory = $false)]
    [string]$ConfigFilePath = "$(Join-Path $PSScriptRoot "ArchiveTables.json")",
    [Parameter(Mandatory = $false)]
    [switch]$SkipApply,
    [Parameter(Mandatory = $false)]
    [ValidateSet("ExportLoad", "InsertSelect", "Legacy")]
    [string]$Method = "ExportLoad",
    [Parameter(Mandatory = $false)]
    [int]$BatchSize = 100000,
    [Parameter(Mandatory = $false)]
    [switch]$KeepTmpTable
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

    Write-LogMessage "Selected database: $($dbContext.DatabaseName), instance: $($dbContext.InstanceName), environment: $($dbContext.Environment), application: $($dbContext.Application)" -Level INFO

    $workObject = Get-DefaultWorkObjectsCommon -DatabaseName $dbContext.DatabaseName -DatabaseType PrimaryDb -InstanceName $dbContext.InstanceName -QuickMode
    if ($workObject -is [array]) {
        $workObject = $workObject[-1]
    }

    $rules = Get-Content -Path $ConfigFilePath -Raw | ConvertFrom-Json
    $selectedRules = @($rules | Where-Object { $_.ApplicationName.ToUpper() -eq $dbContext.Application.ToUpper() })
    if ($selectedRules.Count -eq 0) {
        throw "No table rules in config for application $($dbContext.Application)."
    }

    $keepYears = @(2025, 2026)

    $preReport = @()
    $resultReport = @()
    $postReport = @()

    foreach ($rule in $selectedRules) {
        $tableParts = Split-Db2QualifiedTableName -QualifiedTableName $rule.TableName
        $timestampColumn = $rule.TimestampColumn.Trim().ToUpper()
        $sourceTable = "$($tableParts.SchemaName).$($tableParts.BaseName)"

        Write-LogMessage "Processing table $($sourceTable) using timestamp column $($timestampColumn)" -Level INFO

        $exists = Test-Db2TableColumnExists -WorkObject $workObject -SchemaName $tableParts.SchemaName -TableName $tableParts.BaseName -ColumnName $timestampColumn
        if (-not $exists) {
            Write-LogMessage "Skipping table $($sourceTable). Table or timestamp column missing." -Level WARN
            continue
        }

        $beforeRows = Get-Db2YearCountsForTable -WorkObject $workObject -QualifiedTableName $sourceTable -TimestampColumn $timestampColumn
        foreach ($row in $beforeRows) {
            $preReport += [PSCustomObject]@{
                TableName = $sourceTable
                Year      = $row.Year
                RowCount  = $row.RowCount
                Phase     = "Before"
            }
        }

        $result = Invoke-Db2TableShrink -WorkObject $workObject -SchemaName $tableParts.SchemaName -BaseName $tableParts.BaseName -TimestampColumn $timestampColumn -KeepYears $keepYears -BatchSize $BatchSize -Method $Method -SkipApply:$SkipApply -KeepTmpTable:$KeepTmpTable
        $resultReport += $result

        if (-not $SkipApply) {
            $afterRows = Get-Db2YearCountsForTable -WorkObject $workObject -QualifiedTableName $sourceTable -TimestampColumn $timestampColumn
            foreach ($row in $afterRows) {
                $postReport += [PSCustomObject]@{
                    TableName = $sourceTable
                    Year      = $row.Year
                    RowCount  = $row.RowCount
                    Phase     = "After"
                }
            }
        }
    }

    if ($preReport.Count -gt 0) {
        Write-LogMessage "Year distribution before shrink:" -Level INFO
        Write-LogMessage ($preReport | Sort-Object TableName, Year | Format-Table -AutoSize | Out-String) -Level INFO
    }

    if ($resultReport.Count -gt 0) {
        Write-LogMessage "Shrink result report:" -Level INFO
        Write-LogMessage ($resultReport | Sort-Object TableName | Format-Table -AutoSize | Out-String) -Level INFO
    }

    if ($postReport.Count -gt 0) {
        Write-LogMessage "Year distribution after shrink:" -Level INFO
        Write-LogMessage ($postReport | Sort-Object TableName, Year | Format-Table -AutoSize | Out-String) -Level INFO
    }

    if ($SkipApply) {
        Write-LogMessage "SkipApply enabled. No table swap performed." -Level WARN
    } else {
        $failedVerifications = @($resultReport | Where-Object { $_.Applied -eq $true -and $_.VerificationOk -eq $false })
        if ($failedVerifications.Count -gt 0) {
            Write-LogMessage "Shrink completed with verification mismatches. Review the report." -Level WARN
        } else {
            Write-LogMessage "Shrink completed successfully for all processed tables." -Level INFO
        }
    }

    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error in shrink script: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    exit 1
}
