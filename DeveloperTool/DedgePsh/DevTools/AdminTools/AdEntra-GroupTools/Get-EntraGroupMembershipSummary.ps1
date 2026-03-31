#Requires -Version 7.0
<#
.SYNOPSIS
    Summarizes direct members of a Microsoft Entra group (Graph).

.DESCRIPTION
    Requires Microsoft Graph PowerShell modules and an authenticated session (Connect-MgGraph).

.EXAMPLE
    Connect-MgGraph -Scopes Group.Read.All
    pwsh.exe -NoProfile -File .\Get-EntraGroupMembershipSummary.ps1 -GroupId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GroupId
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

Write-LogMessage "JOB_STARTED Get-EntraGroupMembershipSummary GroupId=$($GroupId)" -Level INFO

try {
    Import-Module Microsoft.Graph.Groups -ErrorAction Stop
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

    $ctx = Get-MgContext -ErrorAction SilentlyContinue
    if (-not $ctx) {
        Write-LogMessage 'Not connected to Microsoft Graph. Run Connect-MgGraph -Scopes Group.Read.All' -Level ERROR
        exit 1
    }

    $g = Get-MgGroup -GroupId $GroupId -ErrorAction Stop
    $page = @(Get-MgGroupMember -GroupId $GroupId -All -ErrorAction Stop)

    $users = 0
    $groups = 0
    $apps = 0
    $other = 0
    foreach ($m in $page) {
        $t = $null
        if ($m.AdditionalProperties -and $m.AdditionalProperties['@odata.type']) {
            $t = $m.AdditionalProperties['@odata.type']
        }
        elseif ($m.'@odata.type') { $t = $m.'@odata.type' }
        switch -Regex ($t) {
            'graph\.user$' { $users++ }
            'graph\.group$' { $groups++ }
            'graph\.application|graph\.servicePrincipal' { $apps++ }
            default { $other++ }
        }
    }

    Write-LogMessage "Entra group: $($g.DisplayName) ($($g.Id))" -Level INFO
    Write-LogMessage "Direct members — users: $($users), groups: $($groups), apps/servicePrincipals: $($apps), other: $($other); total: $($page.Count)" -Level INFO
    Write-LogMessage 'JOB_COMPLETED Get-EntraGroupMembershipSummary' -Level INFO
    exit 0
}
catch {
    Write-LogMessage "JOB_FAILED Get-EntraGroupMembershipSummary: $($_.Exception.Message)" -Level ERROR -Exception $_
    exit 1
}
