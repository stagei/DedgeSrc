#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Downloads one or more blobs from an Azure Blob Storage container.

.DESCRIPTION
    Forwarding shell for Invoke-AzureContainerDownload in the AzureFunctions module.
    See that function for full documentation.

    BlobList accepts a comma-separated string when called via pwsh.exe -File,
    or a string array when called directly from PowerShell.

.PARAMETER StorageAccountName
    Azure Storage account name (default: pbackup14532)

.PARAMETER StorageAccountKey
    Azure Storage account key. AzureStorage.json overrides this if present.

.PARAMETER ContainerName
    Container name (default: server hostname in lowercase).

.PARAMETER BlobList
    Comma-separated blob paths, or a string array when called from PowerShell.

.PARAMETER DestinationFolder
    Local folder where downloaded files are saved. Defaults to current directory.

.PARAMETER KeepBlobPath
    Recreates the blob folder structure under DestinationFolder instead of flattening.

.EXAMPLE
    .\Azure-ContainerDownload.ps1 -BlobList '2026/02/26/testupload.tst' -DestinationFolder 'C:\downloads'

.EXAMPLE
    .\Azure-ContainerDownload.ps1 -BlobList '2026/02/26/a.csv,2026/02/26/b.csv' -ContainerName 'mycontainer'

.EXAMPLE
    .\Azure-ContainerDownload.ps1 -BlobList '2026/02/26/report.pdf' -KeepBlobPath -DestinationFolder 'D:\archive'
#>
param(
    [string]$StorageAccountName = "pbackup14532",
    [string]$StorageAccountKey  = "cFlkO82oWLXedSrgWFbCV38MWtfcd6D3Auxs98uLQuswOjeC6RU4kASA5LXpDjA+OgbKTKNxLmKmSrEDveKtrw==",
    [string]$ContainerName      = "",
    [string]$BlobList           = "",
    [string]$DestinationFolder  = "",
    [switch]$KeepBlobPath
)

Import-Module GlobalFunctions  -Force
Import-Module AzureFunctions   -Force

Set-OverrideAppDataFolder -Path (Join-Path $env:OptPath "data\AzureStorageUpload")
Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_STARTED

try {
    [string[]]$blobArray = $BlobList -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }

    Invoke-AzureContainerDownload `
        -StorageAccountName $StorageAccountName `
        -StorageAccountKey  $StorageAccountKey `
        -ContainerName      $ContainerName `
        -BlobList           $blobArray `
        -DestinationFolder  $DestinationFolder `
        -KeepBlobPath:$KeepBlobPath `
        -ConfigFolder       $PSScriptRoot

    Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "$($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_FAILED
    exit 1
}
finally {
    Reset-OverrideAppDataFolder
}
