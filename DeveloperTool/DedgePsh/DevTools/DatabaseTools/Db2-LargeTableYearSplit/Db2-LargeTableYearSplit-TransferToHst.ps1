param(
    [Parameter(Mandatory = $false)]
    [string]$SourceDatabaseName = "FKMPRD",
    [Parameter(Mandatory = $false)]
    [string]$TargetDatabaseName = "BASISHST",
    [Parameter(Mandatory = $false)]
    [string]$ConfigFilePath = "$(Join-Path $PSScriptRoot "ArchiveTables.json")",
    [Parameter(Mandatory = $false)]
    [switch]$SkipApply
)

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

try {
    Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED
    Test-Db2ServerAndAdmin

    if (-not (Test-Path -Path $ConfigFilePath -PathType Leaf)) {
        throw "Config file not found: $($ConfigFilePath)"
    }

    $sourceContext = Get-Db2DatabaseContext -RequestedDatabaseName $SourceDatabaseName
    Write-LogMessage "Source: DB=$($sourceContext.DatabaseName), ENV=$($sourceContext.Environment), INSTANCE=$($sourceContext.InstanceName), SERVER=$($sourceContext.ServerName)" -Level INFO

    $targetContext = Get-Db2DatabaseContext -RequestedDatabaseName $TargetDatabaseName
    Write-LogMessage "Target: DB=$($targetContext.DatabaseName), ENV=$($targetContext.Environment), INSTANCE=$($targetContext.InstanceName), SERVER=$($targetContext.ServerName)" -Level INFO

    if ($sourceContext.DatabaseName -eq $targetContext.DatabaseName) {
        throw "Source and target database are the same ($($sourceContext.DatabaseName)). Cannot transfer to self."
    }

    $sourceWorkObject = Get-DefaultWorkObjectsCommon -DatabaseName $sourceContext.DatabaseName -DatabaseType PrimaryDb -InstanceName $sourceContext.InstanceName -QuickMode
    if ($sourceWorkObject -is [array]) { $sourceWorkObject = $sourceWorkObject[-1] }
    $targetWorkObject = Get-DefaultWorkObjectsCommon -DatabaseName $targetContext.DatabaseName -DatabaseType PrimaryDb -InstanceName $targetContext.InstanceName -QuickMode
    if ($targetWorkObject -is [array]) { $targetWorkObject = $targetWorkObject[-1] }

    $archiveRules = Get-Content -Path $ConfigFilePath -Raw | ConvertFrom-Json
    $rulesForSourceApp = @($archiveRules | Where-Object { $_.ApplicationName.ToUpper() -eq $sourceContext.Application.ToUpper() })
    if ($rulesForSourceApp.Count -eq 0) {
        Write-LogMessage "No rules for application '$($sourceContext.Application)' — using all rules from config." -Level WARN
        $rulesForSourceApp = @($archiveRules)
    }

    $discoveredTables = @()
    foreach ($rule in $rulesForSourceApp) {
        $tableParts = Split-Db2QualifiedTableName -QualifiedTableName $rule.TableName
        $tmpTables = Get-Db2TmpTablesForBase -WorkObject $sourceWorkObject -SchemaName $tableParts.SchemaName -BaseName $tableParts.BaseName
        foreach ($tableName in $tmpTables) {
            $discoveredTables += [PSCustomObject]@{
                SchemaName = $tableParts.SchemaName
                BaseName   = $tableParts.BaseName
                TableName  = $tableName
            }
        }
    }
    $discoveredTables = @($discoveredTables | Sort-Object SchemaName, TableName -Unique)
    if ($discoveredTables.Count -eq 0) {
        Write-LogMessage "No *_TMP tables found from configured base tables. Nothing to transfer." -Level WARN
        Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
        return
    }

    Write-LogMessage "Discovered $($discoveredTables.Count) _TMP table(s) to transfer:" -Level INFO
    Write-LogMessage ($discoveredTables | ForEach-Object { "  $($_.SchemaName).$($_.TableName)" } | Out-String) -Level INFO

    $preSourceStats = @()
    foreach ($item in $discoveredTables) {
        $qualifiedTable = "$($item.SchemaName).$($item.TableName)"
        $preSourceStats += [PSCustomObject]@{
            Table      = $qualifiedTable
            SourceRows = (Get-Db2RowCount -WorkObject $sourceWorkObject -QualifiedTable $qualifiedTable)
        }
    }

    $appDataPath = Get-ApplicationDataPath
    $exportRoot = Join-Path $appDataPath "TmpTableTransfer_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    New-Item -Path $exportRoot -ItemType Directory -Force | Out-Null

    if ($SkipApply) {
        Write-LogMessage "SkipApply set: export/load execution skipped after discovery and validation." -Level WARN
        Write-LogMessage ($preSourceStats | Format-Table -AutoSize | Out-String) -Level INFO
        Write-LogMessage "Export folder prepared at: $($exportRoot)" -Level INFO
        Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
        return
    }

    $hasServerLink = $false
    $serverLinkName = $sourceContext.PrimaryCatalogName.ToUpper()
    try {
        $hasServerLink = Test-Db2ServerLinkExists -WorkObject $targetWorkObject -ServerLinkName $serverLinkName
    }
    catch {
        Write-LogMessage "Could not check server link: $($_.Exception.Message)" -Level WARN
    }

    if ($hasServerLink) {
        Write-LogMessage "Server link '$serverLinkName' found in $($targetContext.DatabaseName) — using nicknames to auto-create target tables." -Level INFO
        foreach ($item in $discoveredTables) {
            New-Db2NicknameAndTargetTable -TargetWorkObject $targetWorkObject -ServerLinkName $serverLinkName -RemoteSchema $item.SchemaName -TableName $item.TableName
        }
    }
    else {
        Write-LogMessage "No server link '$serverLinkName' in $($targetContext.DatabaseName) — target tables must already exist." -Level WARN
    }

    $postTargetStats = @()
    foreach ($item in $discoveredTables) {
        $srcTable = "$($item.SchemaName).$($item.TableName)"
        $ixfFile = Join-Path $exportRoot "$($item.SchemaName)_$($item.TableName).ixf"
        $exportMsgFile = Join-Path $exportRoot "$($item.SchemaName)_$($item.TableName)_export.msg"
        $loadMsgFile = Join-Path $exportRoot "$($item.SchemaName)_$($item.TableName)_load.msg"

        Write-LogMessage "Exporting $srcTable from $($sourceContext.DatabaseName)..." -Level INFO
        $exportCmd = @(
            "db2 export to `"$ixfFile`" of ixf messages `"$exportMsgFile`" select * from $srcTable"
        )
        $null = Invoke-Db2MultiStatement -WorkObject $sourceWorkObject -Db2Commands $exportCmd -IgnoreErrors
        if (-not (Test-Path $ixfFile)) {
            Write-LogMessage "EXPORT failed for $srcTable — IXF file not created. Skipping." -Level ERROR
            continue
        }
        $ixfSizeMb = [Math]::Round((Get-Item $ixfFile).Length / 1MB, 1)
        Write-LogMessage "  Exported $srcTable ($($ixfSizeMb) MB)" -Level INFO

        Write-LogMessage "Loading $srcTable into $($targetContext.DatabaseName)..." -Level INFO
        $loadCmd = @(
            "db2 load from `"$ixfFile`" of ixf messages `"$loadMsgFile`" insert into $srcTable nonrecoverable"
        )
        try {
            $null = Invoke-Db2MultiStatement -WorkObject $targetWorkObject -Db2Commands $loadCmd -IgnoreErrors
        }
        catch {
            Write-LogMessage "LOAD failed for $($srcTable): $($_.Exception.Message)" -Level ERROR
            continue
        }

        $targetRows = Get-Db2RowCount -WorkObject $targetWorkObject -QualifiedTable $srcTable
        $postTargetStats += [PSCustomObject]@{
            Table               = $srcTable
            TargetRowsAfterLoad = $targetRows
        }
        Write-LogMessage "  Loaded $srcTable — $targetRows rows in target" -Level INFO

        foreach ($f in @($ixfFile, $exportMsgFile, $loadMsgFile)) {
            if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
        }
    }

    Write-LogMessage "========== Transfer report ==========" -Level INFO
    Write-LogMessage "Source: $($sourceContext.DatabaseName) / $($sourceContext.InstanceName)" -Level INFO
    Write-LogMessage "Target: $($targetContext.DatabaseName) / $($targetContext.InstanceName)" -Level INFO
    Write-LogMessage "Export folder: $($exportRoot)" -Level INFO
    Write-LogMessage "Source row counts (before transfer):" -Level INFO
    Write-LogMessage ($preSourceStats | Format-Table -AutoSize | Out-String) -Level INFO
    Write-LogMessage "Target row counts (after load):" -Level INFO
    Write-LogMessage ($postTargetStats | Format-Table -AutoSize | Out-String) -Level INFO

    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error in transfer script: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    exit 1
}
