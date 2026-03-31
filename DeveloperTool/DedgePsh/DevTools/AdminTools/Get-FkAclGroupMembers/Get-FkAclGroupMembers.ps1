<#
.SYNOPSIS
    Lists members of development-related AD groups in DEDGE domain

.DESCRIPTION
    This script retrieves and displays members of the following groups:
    - ACL_ERPUTV_Utvikling_Full
    - ACL_Dedge_Servere_Utviklere

.NOTES
    Author: Geir Helge Starholm, www.dEdge.no
    Date: 2025-11-19
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$Domain = "DEDGE",
    [Parameter(Mandatory = $false)]
    [string[]]$Groups = @(
        "ACL_ERPUTV_Utvikling_Full",
        "ACL_Dedge_Servere_Utviklere",
        "ACL_Dedge_Utviklere",
        "ACL_Dedge_Utviklere_Modernisering"
    )
)
Import-Module GlobalFunctions -Force

function Install-ActiveDirectoryModule {
    try {
        Import-Module -Name ActiveDirectory -ErrorAction Stop
    }
    catch {
        Write-LogMessage "Failed to import ActiveDirectory module. Attempting to install..." -Level WARN
    
        if (Test-IsServer) {
            try {
                Install-WindowsFeature -Name RSAT-AD-PowerShell -IncludeAllSubFeature
                Import-Module -Name ActiveDirectory -Force
                Write-LogMessage "Active Directory module installed and imported successfully" -Level INFO
            }
            catch {
                Write-LogMessage "Failed to install Active Directory module on server" -Level ERROR
                throw $_
            }
        }
        else {
            try {
                Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
                Import-Module -Name ActiveDirectory -Force
                Write-LogMessage "Active Directory module installed and imported successfully" -Level INFO
            }
            catch {
                Write-LogMessage "Failed to install Active Directory module on client" -Level ERROR
                throw $_
            }
        }
    }
}

Install-ActiveDirectoryModule

$appdatafolder = Get-ApplicationDataPath
Write-LogMessage "Starting AD group member listing for DEDGE domain" -Level INFO
$workObjects = [PSCustomObject[]]@()
foreach ($groupName in $groups) {
    $groupObject = [PSCustomObject]@{
        GroupName = $groupName
        Members   = @()
    }
    Write-LogMessage "================================================" -Level INFO
    Write-LogMessage "Group: $($groupName)" -Level INFO
    Write-LogMessage "================================================" -Level INFO
    
    try {
        # Get group members using ActiveDirectory module
        $members = Get-ADGroupMember -Identity $groupName -Server $domain | ForEach-Object {
            $member = $_
            $email = $null
            if ($member.objectClass -eq 'user') {
                $adUser = Get-ADUser -Identity $member.SamAccountName -Server $domain -Properties EmailAddress -ErrorAction SilentlyContinue
                $email = $adUser.EmailAddress
            }
            [PSCustomObject]@{
                Name           = $member.Name
                EmailAddress   = $email
                SamAccountName = $member.SamAccountName
                objectClass    = $member.objectClass
            }
        } | Sort-Object Name
        
        if ($members) {
            Write-LogMessage "Found $($members.Count) member(s) in group $($groupName)" -Level INFO
            $members | Format-Table -AutoSize | Out-String | Write-Host
        }
        else {
            Write-LogMessage "No members found in group $($groupName)" -Level WARN
        }
    }
    catch {
        Write-LogMessage "Failed to get members for group $($groupName)" -Level ERROR -Exception $_
    }

    $groupObject.Members = $members
    $workObjects += $groupObject
    
}

Write-LogMessage "AD group member listing completed" -Level INFO

foreach ($workObject in $workObjects) {
    # Export primary database object to html file
    $outputFileName = "$(Join-Path $appdatafolder "Get-AclGroupMembers-Report-$($workObject.GroupName).html")"
    $result = Export-ArrayToHtmlFile -Content $workObject.Members -Title "Group Members Report for $($workObject.GroupName)" -AutoOpen:$false -OutputPath $outputFileName -NoTitleAutoFormat -AddToDevToolsWebPath $true -DevToolsWebDirectory "UserInfo"
    Write-Host "Exported results to HTML file: " $result -ForegroundColor Green
}