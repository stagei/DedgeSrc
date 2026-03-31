<#
.SYNOPSIS
    Copies the newest DB2 production backup file to the local restore folder.

.DESCRIPTION
    Searches the production backup share for the newest file matching the
    DB2 backup naming pattern and copies it to E:\Db2Restore.

    Run manually on the target restore server.
#>

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force


$sourceFolder = "\\p-no1fkmprd-db\Db2Backup"
$filter       = "FKMPRD.0.DB2.DBPART000.*.001"
$destination  = Find-ExistingFolder -Name "Db2Restore" -SkipRecreateFolders

Write-LogMessage "Searching for newest backup matching '$($filter)' in '$($sourceFolder)'" -Level INFO

$newestFile = Get-ChildItem -Path $sourceFolder -Filter $filter |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $newestFile) {
    Write-LogMessage "No backup file found matching filter '$($filter)'" -Level ERROR
    exit 1
}

Write-LogMessage "Found: $($newestFile.Name)  (LastWriteTime: $($newestFile.LastWriteTime))" -Level INFO

if (-not (Test-Path $destination)) {
    Write-LogMessage "Creating destination folder '$($destination)'" -Level INFO
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
}

$destPath = Join-Path $destination $newestFile.Name
Write-LogMessage "Copying to '$($destPath)' ..." -Level INFO

Copy-Item -Path $newestFile.FullName -Destination $destPath -Force

Write-LogMessage "Copy complete: $($destPath)" -Level INFO

Send-Sms -Receiver "+4797188358" -Message "Db2-ProductionBackupCopyOnly complete done on $($env:COMPUTERNAME). File $($newestFile.Name) copied to $($destPath)." 