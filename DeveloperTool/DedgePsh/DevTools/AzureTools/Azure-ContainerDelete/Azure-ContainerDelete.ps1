#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Deletes one or more blobs from an Azure Blob Storage container.

.DESCRIPTION
    Forwarding shell for Remove-AzureContainerBlob in the AzureFunctions module.
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
    Comma-separated blob paths to delete (e.g. '2026/02/26/report.pdf,2026/02/26/other.pdf').

.PARAMETER WhatIf
    Lists what would be deleted without actually removing anything.

.EXAMPLE
    .\Azure-ContainerDelete.ps1 -BlobList '2026/02/26/testupload.tst' -ContainerName '30237-fk'

.EXAMPLE
    .\Azure-ContainerDelete.ps1 -BlobList '2026/02/26/a.txt,2026/02/26/b.txt' -WhatIf

.EXAMPLE
    .\Azure-ContainerDelete.ps1 -BlobList '2026/02/26/a.txt,2026/02/26/b.txt' -ContainerName 'mycontainer'
#>
param(
    [string]$StorageAccountName = "pbackup14532",
    [string]$StorageAccountKey  = "cFlkO82oWLXedSrgWFbCV38MWtfcd6D3Auxs98uLQuswOjeC6RU4kASA5LXpDjA+OgbKTKNxLmKmSrEDveKtrw==",
    [string]$ContainerName      = "",
    [string]$BlobList           = "",
    [switch]$WhatIf
)

Import-Module GlobalFunctions  -Force
Import-Module AzureFunctions   -Force

Set-OverrideAppDataFolder -Path (Join-Path $env:OptPath "data\AzureStorageUpload")
Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_STARTED

try {
    [string[]]$blobArray = $BlobList -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }

    Remove-AzureContainerBlob `
        -StorageAccountName $StorageAccountName `
        -StorageAccountKey  $StorageAccountKey `
        -ContainerName      $ContainerName `
        -BlobList           $blobArray `
        -WhatIf:$WhatIf `
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
