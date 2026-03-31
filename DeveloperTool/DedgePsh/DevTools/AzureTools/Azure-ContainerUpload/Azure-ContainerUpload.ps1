#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Uploads one or more files to Azure Blob Storage.

.DESCRIPTION
    Forwarding shell for Invoke-AzureContainerUpload in the AzureFunctions module.
    See that function for full documentation.

    UploadFileList accepts a comma-separated string when called via pwsh.exe -File,
    or a string array when called directly from PowerShell.

.PARAMETER StorageAccountName
    Azure Storage account name (default: pbackup14532)

.PARAMETER StorageAccountKey
    Azure Storage account key. AzureStorage.json overrides this if present.

.PARAMETER ContainerName
    Container name (default: server hostname in lowercase). Auto-created if missing.

.PARAMETER UploadFileList
    Comma-separated file paths, or a string array when called from PowerShell.

.EXAMPLE
    .\Azure-ContainerUpload.ps1 -UploadFileList "C:\reports\report.pdf"

.EXAMPLE
    .\Azure-ContainerUpload.ps1 -UploadFileList "C:\data\a.csv,C:\data\b.csv" -ContainerName "mycontainer"

.EXAMPLE
    $files = Get-ChildItem "D:\exports" -Filter "*.zip" | Select-Object -ExpandProperty FullName
    .\Azure-ContainerUpload.ps1 -UploadFileList ($files -join ",")
#>
param(
    [string]$StorageAccountName = "pbackup14532",
    [string]$StorageAccountKey  = "cFlkO82oWLXedSrgWFbCV38MWtfcd6D3Auxs98uLQuswOjeC6RU4kASA5LXpDjA+OgbKTKNxLmKmSrEDveKtrw==",
    [string]$ContainerName      = "",
    [string]$UploadFileList     = ""
)

Import-Module GlobalFunctions  -Force
Import-Module AzureFunctions   -Force

Set-OverrideAppDataFolder -Path (Join-Path $env:OptPath "data\AzureStorageUpload")
Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_STARTED

try {
    [string[]]$fileArray = $UploadFileList -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }

    Invoke-AzureContainerUpload `
        -StorageAccountName $StorageAccountName `
        -StorageAccountKey  $StorageAccountKey `
        -ContainerName      $ContainerName `
        -UploadFileList     $fileArray `
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
