#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Lists blobs in an Azure Storage container.

.DESCRIPTION
    Forwarding shell for Get-AzureContainerListContent in the AzureFunctions module.
    See that function for full documentation.

.PARAMETER StorageAccountName
    Azure Storage account name (default: pbackup14532)

.PARAMETER StorageAccountKey
    Azure Storage account key. AzureStorage.json overrides this if present.

.PARAMETER ContainerName
    Container name (default: server hostname in lowercase).

.PARAMETER Filter
    Optional blob name prefix filter (e.g. "2026/02" for a specific month).

.PARAMETER DaysBack
    Only show blobs modified within the last N days. 0 = all (default).

.EXAMPLE
    .\Azure-ContainerListContent.ps1

.EXAMPLE
    .\Azure-ContainerListContent.ps1 -ContainerName "mycontainer" -DaysBack 7

.EXAMPLE
    .\Azure-ContainerListContent.ps1 -ContainerName "mycontainer" -Filter "2026/02"
#>
param(
    [string]$StorageAccountName = "pbackup14532",
    [string]$StorageAccountKey  = "cFlkO82oWLXedSrgWFbCV38MWtfcd6D3Auxs98uLQuswOjeC6RU4kASA5LXpDjA+OgbKTKNxLmKmSrEDveKtrw==",
    [string]$ContainerName      = "",
    [string]$Filter             = "",
    [int]$DaysBack              = 0
)

Import-Module GlobalFunctions  -Force
Import-Module AzureFunctions   -Force

Set-OverrideAppDataFolder -Path (Join-Path $env:OptPath "data\AzureStorageUpload")
Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_STARTED

try {
    Get-AzureContainerListContent @PSBoundParameters -ConfigFolder $PSScriptRoot
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
