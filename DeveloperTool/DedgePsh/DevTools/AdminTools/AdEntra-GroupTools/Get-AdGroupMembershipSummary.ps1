#Requires -Version 7.0
<#
.SYNOPSIS
    Summarizes direct members of an Active Directory group (users vs nested groups).

.EXAMPLE
    pwsh.exe -NoProfile -File .\Get-AdGroupMembershipSummary.ps1 -GroupIdentity 'CN=MyGroup,OU=Groups,DC=corp,DC=local'
.EXAMPLE
    pwsh.exe -NoProfile -File .\Get-AdGroupMembershipSummary.ps1 -GroupIdentity 'Domain Users'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GroupIdentity,

    [Parameter(Mandatory = $false)]
    [switch]$SkipServerCheck
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

if (-not $SkipServerCheck) {
    Import-Module Infrastructure -Force
    if (-not (Test-IsServer)) {
        Write-LogMessage 'Run this script on a domain-joined server, or pass -SkipServerCheck.' -Level ERROR
        exit 1
    }
}

Import-Module ActiveDirectory -ErrorAction Stop

Write-LogMessage "JOB_STARTED Get-AdGroupMembershipSummary GroupIdentity=$($GroupIdentity)" -Level INFO

try {
    $g = Get-ADGroup -Identity $GroupIdentity -Properties DistinguishedName, SamAccountName, Name -ErrorAction Stop
    $members = @(Get-ADGroupMember -Identity $g.DistinguishedName -ErrorAction Stop)
    $users = @($members | Where-Object { $_.objectClass -eq 'user' })
    $groups = @($members | Where-Object { $_.objectClass -eq 'group' })
    $other = @($members | Where-Object { $_.objectClass -notin 'user', 'group' })

    Write-LogMessage "Group: $($g.Name) ($($g.SamAccountName))" -Level INFO
    Write-LogMessage "Direct members — users: $($users.Count), nested groups: $($groups.Count), other: $($other.Count); total: $($members.Count)" -Level INFO

    foreach ($ng in $groups | Select-Object -First 50) {
        Write-LogMessage "  Nested group: $($ng.Name)" -Level INFO
    }
    if ($groups.Count -gt 50) {
        Write-LogMessage "  ... ($($groups.Count - 50) more nested groups not listed)" -Level INFO
    }

    Write-LogMessage 'JOB_COMPLETED Get-AdGroupMembershipSummary' -Level INFO
    exit 0
}
catch {
    Write-LogMessage "JOB_FAILED Get-AdGroupMembershipSummary: $($_.Exception.Message)" -Level ERROR -Exception $_
    exit 1
}
