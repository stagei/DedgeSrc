#Requires -Version 7.0
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Applies machine policy to disable Microsoft Edge sidebar (Hubs) features.

.DESCRIPTION
    Sets HKLM policy values HubsSidebarEnabled and StandaloneHubsSidebarEnabled to 0.
    Restart Edge for changes to take effect.
#>

[CmdletBinding()]
param()

Import-Module GlobalFunctions -Force

$edgePolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'

if (-not (Test-Path -Path $edgePolicyPath)) {
    New-Item -Path $edgePolicyPath -Force | Out-Null
    Write-LogMessage "Created registry path: $($edgePolicyPath)" -Level INFO
}

New-ItemProperty -Path $edgePolicyPath -Name 'HubsSidebarEnabled' -Value 0 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $edgePolicyPath -Name 'StandaloneHubsSidebarEnabled' -Value 0 -PropertyType DWord -Force | Out-Null

Write-LogMessage 'Edge sidebar policies set (HubsSidebarEnabled=0, StandaloneHubsSidebarEnabled=0). Restart Edge to apply.' -Level INFO
