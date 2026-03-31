param(
    [Parameter(Mandatory = $false)]
    [string]$DatabaseName = "",
    [Parameter(Mandatory = $false)]
    [string]$ConfigFilePath = "$(Join-Path $PSScriptRoot "ArchiveTables.json")",
    [Parameter(Mandatory = $false)]
    [switch]$SkipApply,
    [Parameter(Mandatory = $false)]
    [ValidateSet("ExportLoad", "InsertSelect", "Legacy", "RenameAndReload")]
    [string]$Method = "ExportLoad",
    [Parameter(Mandatory = $false)]
    [int]$BatchSize = 10000,
    [Parameter(Mandatory = $false)]
    [int]$DeleteBatchSize = 50000,
    [Parameter(Mandatory = $false)]
    [bool]$RestoreFromPrd = $true,
    [Parameter(Mandatory = $false)]
    [bool]$ReuseLocalBackup = $false
)

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

#region PRD Backup Cache (reuse downloaded backup images across runs)

function Get-SplitPrdBackupCacheRoot {
    $rootDrive = if (Test-Path -Path 'F:\' -PathType Container) { 'F:' } else { 'E:' }
    return Join-Path $rootDrive 'Db2SplitPrdBackupCache'
}

function Save-BackupImagesToCache {
    param(
        [Parameter(Mandatory)]
        [string]$RestoreFolder
    )
    $cacheRoot = Get-SplitPrdBackupCacheRoot
    try {
        if (-not (Test-Path $cacheRoot -PathType Container)) {
            New-Item -Path $cacheRoot -ItemType Directory -Force | Out-Null
        }
        $backupFiles = @(Get-ChildItem -Path $RestoreFolder -Filter "*.0*" -File -ErrorAction SilentlyContinue)
        if ($backupFiles.Count -eq 0) {
            Write-LogMessage "BackupCache: No backup images in $($RestoreFolder) to cache" -Level WARN
            return
        }
        Get-ChildItem -Path $cacheRoot -Filter "*.0*" -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        $totalSize = 0
        foreach ($f in $backupFiles) {
            Copy-Item -Path $f.FullName -Destination (Join-Path $cacheRoot $f.Name) -Force
            $totalSize += $f.Length
        }
        $sizeGB = [math]::Round($totalSize / 1GB, 1)
        Write-LogMessage "BackupCache: Cached $($backupFiles.Count) file(s) ($($sizeGB) GB) to $($cacheRoot)" -Level INFO
    }
    catch {
        Write-LogMessage "BackupCache: Failed to cache backup images (non-fatal): $($_.Exception.Message)" -Level WARN
    }
}

function Initialize-RestoreFolderFromCache {
    param(
        [Parameter(Mandatory)]
        [string]$RestoreFolder
    )
    $cacheRoot = Get-SplitPrdBackupCacheRoot
    if (-not (Test-Path $cacheRoot -PathType Container)) { return $false }
    $cachedPrimary = @(Get-ChildItem -Path $cacheRoot -Filter "*.001" -File -ErrorAction SilentlyContinue)
    if ($cachedPrimary.Count -eq 0) { return $false }

    $allCached = @(Get-ChildItem -Path $cacheRoot -Filter "*.0*" -File -ErrorAction SilentlyContinue)
    $totalSize = ($allCached | Measure-Object -Property Length -Sum).Sum
    $sizeMB = [math]::Round($totalSize / 1MB, 0)
    Write-LogMessage "BackupCache: Seeding $($RestoreFolder) from cache ($($allCached.Count) file(s), $($sizeMB) MB)..." -Level INFO
    foreach ($f in $allCached) {
        Copy-Item -Path $f.FullName -Destination (Join-Path $RestoreFolder $f.Name) -Force
    }
    Write-LogMessage "BackupCache: Seed complete." -Level INFO
    return $true
}

#endregion

try {
    Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED

    Test-Db2ServerAndAdmin

    if ($RestoreFromPrd) {
        $restoreFolder = Find-ExistingFolder -Name "DB2Restore" -SkipRecreateFolders
        Write-LogMessage "RestoreFromPrd: Restore folder = $($restoreFolder)" -Level INFO

        $useLocalBackup = $false
        if ($ReuseLocalBackup) {
            $localImages = @(Get-ChildItem -Path $restoreFolder -Filter "*.001" -File -ErrorAction SilentlyContinue)
            if ($localImages.Count -gt 0) {
                $totalGB = [math]::Round(($localImages | Measure-Object -Property Length -Sum).Sum / 1GB, 1)
                Write-LogMessage "RestoreFromPrd: Db2Restore already has $($localImages.Count) backup image(s) ($($totalGB) GB). Reusing local files." -Level INFO
                $useLocalBackup = $true
            }
            else {
                $useLocalBackup = Initialize-RestoreFolderFromCache -RestoreFolder $restoreFolder
                if ($useLocalBackup) {
                    Write-LogMessage "RestoreFromPrd: Seeded Db2Restore from backup cache." -Level INFO
                }
            }

            if ($useLocalBackup) {
                $restoreScript = Join-Path $env:OptPath "DedgePshApps\Db2-CreateInitialDatabases\Db2-CreateInitialDatabasesStdAllNoBackupCopy.ps1"
                Write-LogMessage "RestoreFromPrd: Using local backup (no PRD download). Script: $($restoreScript)" -Level INFO
            }
            else {
                $restoreScript = Join-Path $env:OptPath "DedgePshApps\Db2-CreateInitialDatabases\Db2-CreateInitialDatabasesStdAll.ps1"
                Write-LogMessage "RestoreFromPrd: No local or cached backup found. Downloading from PRD. Script: $($restoreScript)" -Level WARN
            }
        }
        else {
            $restoreScript = Join-Path $env:OptPath "DedgePshApps\Db2-CreateInitialDatabases\Db2-CreateInitialDatabasesStdAll.ps1"
            Write-LogMessage "RestoreFromPrd: Fresh download from PRD. Script: $($restoreScript)" -Level INFO
        }

        if (-not (Test-Path $restoreScript)) {
            throw "RestoreFromPrd requested but script not found: $($restoreScript)"
        }
        & $restoreScript
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            throw "RestoreFromPrd: Restore script exited with code $($LASTEXITCODE)"
        }
        Write-LogMessage "RestoreFromPrd: Database restore completed." -Level INFO

        Save-BackupImagesToCache -RestoreFolder $restoreFolder
    }

    if (-not (Test-Path -Path $ConfigFilePath -PathType Leaf)) {
        throw "Config file not found: $($ConfigFilePath)"
    }

    $dbContext = Get-Db2DatabaseContext -RequestedDatabaseName $DatabaseName -LocalServerOnly
    Write-LogMessage "Selected database: $($dbContext.DatabaseName), instance: $($dbContext.InstanceName), application: $($dbContext.Application)" -Level INFO

    $workObject = Get-DefaultWorkObjectsCommon -DatabaseName $dbContext.DatabaseName -DatabaseType PrimaryDb -InstanceName $dbContext.InstanceName -QuickMode
    if ($workObject -is [array]) {
        $workObject = $workObject[-1]
    }

    $archiveRules = Get-Content -Path $ConfigFilePath -Raw | ConvertFrom-Json
    $selectedRules = @($archiveRules | Where-Object { $_.ApplicationName.ToUpper() -eq $dbContext.Application.ToUpper() })
    if ($selectedRules.Count -eq 0) {
        throw "No archive rules in config for application $($dbContext.Application)."
    }

    $currentYear = (Get-Date).Year
    $cutoffYear = $currentYear - 1
    Write-LogMessage "Retention policy: keep year >= $($cutoffYear). Move year < $($cutoffYear)." -Level INFO

    $preReport = @()
    $moveReport = @()

    foreach ($rule in $selectedRules) {
        $tableParts = Split-Db2QualifiedTableName -QualifiedTableName $rule.TableName
        $timestampColumn = $rule.TimestampColumn.Trim().ToUpper()
        $sourceTable = "$($tableParts.SchemaName).$($tableParts.BaseName)"

        $tableMethod = if ($rule.PSObject.Properties['Method']) { $rule.Method } else { $Method }
        $tableDeleteBatchSize = if ($rule.PSObject.Properties['DeleteBatchSize'] -and [int]$rule.DeleteBatchSize -gt 0) { [int]$rule.DeleteBatchSize } else { $DeleteBatchSize }

        Write-LogMessage "Processing table $($sourceTable) on timestamp column $($timestampColumn) (method: $tableMethod)" -Level INFO

        $exists = Test-Db2TableColumnExists -WorkObject $workObject -SchemaName $tableParts.SchemaName -TableName $tableParts.BaseName -ColumnName $timestampColumn
        if (-not $exists) {
            Write-LogMessage "Skipping table $($sourceTable). Table or timestamp column missing." -Level WARN
            continue
        }

        if ($SkipApply) {
            Write-LogMessage "SkipApply fast validation: table and timestamp column verified for $($sourceTable). Archival scan/move skipped." -Level INFO
            $moveReport += [PSCustomObject]@{
                TableName    = $sourceTable
                TargetTable  = ""
                Year         = 0
                RowsDetected = 0
                RowsMoved    = 0
                Applied      = $false
            }
            continue
        }

        if ($tableMethod -eq "RenameAndReload") {
            try {
                $yearCountsBefore = Get-Db2YearCountsForTable -WorkObject $workObject -QualifiedTableName $sourceTable -TimestampColumn $timestampColumn
                foreach ($row in $yearCountsBefore) {
                    $preReport += [PSCustomObject]@{
                        TableName = $sourceTable
                        Year      = $row.Year
                        RowCount  = $row.RowCount
                        Phase     = "Before"
                    }
                }

                $rrResult = Invoke-Db2RenameAndReload -WorkObject $workObject -SourceTable $sourceTable -TimestampColumn $timestampColumn -CutoffYear $cutoffYear
                $moveReport += [PSCustomObject]@{
                    TableName    = $sourceTable
                    TargetTable  = $rrResult.TmpTable
                    Year         = 0
                    RowsDetected = $rrResult.TotalRows
                    RowsMoved    = $rrResult.KeptRows
                    Applied      = ($rrResult.Status -eq "Completed")
                }
            }
            catch {
                Write-LogMessage "RenameAndReload failed for $($sourceTable): $($_.Exception.Message)" -Level ERROR
                throw
            }
            continue
        }

        try {
            $yearCountsBefore = Get-Db2YearCountsForTable -WorkObject $workObject -QualifiedTableName $sourceTable -TimestampColumn $timestampColumn
            foreach ($row in $yearCountsBefore) {
                $preReport += [PSCustomObject]@{
                    TableName = $sourceTable
                    Year      = $row.Year
                    RowCount  = $row.RowCount
                    Phase     = "Before"
                }
            }

            $yearsToArchive = @($yearCountsBefore | Where-Object { $_.Year -lt $cutoffYear } | Select-Object -ExpandProperty Year)
            if ($yearsToArchive.Count -eq 0) {
                Write-LogMessage "No years to archive for table $($sourceTable)." -Level INFO
                continue
            }

            foreach ($archiveYear in $yearsToArchive) {
                $targetTable = New-Db2YearTable -WorkObject $workObject -SchemaName $tableParts.SchemaName -BaseName $tableParts.BaseName -ArchiveYear $archiveYear
                Write-LogMessage "Target table ready: $($targetTable)" -Level INFO

                if ($SkipApply) {
                    $sourceCountSql = "SELECT CHAR(COUNT(1)) FROM $sourceTable WHERE YEAR($timestampColumn) = $archiveYear"
                    $sourceRows = [int64](Get-Db2ScalarValue -WorkObject $workObject -SqlQuery $sourceCountSql)
                    $moveReport += [PSCustomObject]@{
                        TableName    = $sourceTable
                        TargetTable  = $targetTable
                        Year         = $archiveYear
                        RowsDetected = $sourceRows
                        RowsMoved    = 0
                        Applied      = $false
                    }
                    continue
                }

                $moveResult = Move-Db2YearData -WorkObject $workObject -SourceTable $sourceTable -TargetTable $targetTable -TimestampColumn $timestampColumn -ArchiveYear $archiveYear -Method $tableMethod -BatchSize $BatchSize -DeleteBatchSize $tableDeleteBatchSize
                $moveReport += [PSCustomObject]@{
                    TableName    = $sourceTable
                    TargetTable  = $targetTable
                    Year         = $archiveYear
                    RowsDetected = $moveResult.SourceRows
                    RowsMoved    = $moveResult.Inserted
                    Applied      = $true
                }
            }
        }
        catch {
            Write-LogMessage "Skipping table $($sourceTable) due to processing error: $($_.Exception.Message)" -Level WARN
            continue
        }
    }

    $postReport = @()
    if (-not $SkipApply) {
        foreach ($rule in $selectedRules) {
            $tableParts = Split-Db2QualifiedTableName -QualifiedTableName $rule.TableName
            $timestampColumn = $rule.TimestampColumn.Trim().ToUpper()
            $sourceTable = "$($tableParts.SchemaName).$($tableParts.BaseName)"

            $exists = Test-Db2TableColumnExists -WorkObject $workObject -SchemaName $tableParts.SchemaName -TableName $tableParts.BaseName -ColumnName $timestampColumn
            if (-not $exists) {
                continue
            }

            try {
                $yearCountsAfter = Get-Db2YearCountsForTable -WorkObject $workObject -QualifiedTableName $sourceTable -TimestampColumn $timestampColumn
                foreach ($row in $yearCountsAfter) {
                    $postReport += [PSCustomObject]@{
                        TableName = $sourceTable
                        Year      = $row.Year
                        RowCount  = $row.RowCount
                        Phase     = "After"
                    }
                }
            }
            catch {
                Write-LogMessage "Skipping post-report for table $($sourceTable) due to error: $($_.Exception.Message)" -Level WARN
                continue
            }
        }
    }

    if ($preReport.Count -gt 0) {
        Write-LogMessage "Year distribution before archive:" -Level INFO
        Write-LogMessage ($preReport | Sort-Object TableName, Year | Format-Table -AutoSize | Out-String) -Level INFO
    }

    if ($moveReport.Count -gt 0) {
        Write-LogMessage "Archive move report:" -Level INFO
        Write-LogMessage ($moveReport | Sort-Object TableName, Year | Format-Table -AutoSize | Out-String) -Level INFO
    }

    if ($postReport.Count -gt 0) {
        Write-LogMessage "Year distribution after archive:" -Level INFO
        Write-LogMessage ($postReport | Sort-Object TableName, Year | Format-Table -AutoSize | Out-String) -Level INFO
    }

    $oldRowsLeft = @($postReport | Where-Object { $_.Year -lt $cutoffYear })
    if ($SkipApply) {
        Write-LogMessage "SkipApply is enabled. No data was moved." -Level WARN
    }
    elseif ($oldRowsLeft.Count -gt 0) {
        Write-LogMessage "Archive completed, but old rows still exist in source tables. Review report." -Level WARN
    }
    else {
        Write-LogMessage "Archive completed. Source tables retain only current and last year rows." -Level INFO
    }

    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error in archive script: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    exit 1
}
