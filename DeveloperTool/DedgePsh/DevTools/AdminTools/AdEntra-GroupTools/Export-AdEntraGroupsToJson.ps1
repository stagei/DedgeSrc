#Requires -Version 7.0
<#
.SYNOPSIS
    Exports Active Directory and optionally Entra (Microsoft Graph) groups to JSON with hierarchy metadata.

.DESCRIPTION
    Builds a flat group catalog plus explicit containment edges (parent group contains nested group)
    and root identifiers so nested group structure can be reconstructed as a forest/DAG.
    Intended to run on a domain-joined server with RSAT ActiveDirectory module.

.EXAMPLE
    pwsh.exe -NoProfile -File .\Export-AdEntraGroupsToJson.ps1
.EXAMPLE
    pwsh.exe -NoProfile -File .\Export-AdEntraGroupsToJson.ps1 -Source Both -OutputPath D:\exports\groups.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [ValidateSet('AdOnly', 'EntraOnly', 'Both')]
    [string]$Source = 'AdOnly',

    [Parameter(Mandatory = $false)]
    [string]$SearchBase,

    [Parameter(Mandatory = $false)]
    [switch]$SkipServerCheck
)

$ErrorActionPreference = 'Stop'

Import-Module GlobalFunctions -Force
Import-Module Infrastructure -Force

Write-LogMessage 'JOB_STARTED Export-AdEntraGroupsToJson' -Level INFO

if (-not $SkipServerCheck -and -not (Test-IsServer)) {
    Write-LogMessage 'This script must run on a server (domain-joined with AD tools). Use -SkipServerCheck to override.' -Level ERROR
    exit 1
}

function New-CaseInsensitiveDictionary {
    return [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
}

function Convert-LdapWhenToUtcString {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value.ToUniversalTime().ToString('o') }
    try { return ([datetime]::Parse($Value.ToString(), [System.Globalization.CultureInfo]::InvariantCulture)).ToUniversalTime().ToString('o') }
    catch { return $Value.ToString() }
}

function Convert-AdsGroupTypeToCategoryAndScope {
    param([int]$GroupType)
    $isSecurity = ($GroupType -band 0x80000000) -ne 0
    $typeOnly = $GroupType -band 0x7FFFFFF
    $scope = switch ($typeOnly) {
        8 { 'Universal' }
        2 { 'Global' }
        4 { 'DomainLocal' }
        default { 'Unknown' }
    }
    $category = if ($isSecurity) { 'Security' } else { 'Distribution' }
    return [pscustomobject]@{ Category = $category; Scope = $scope }
}

function Get-ActiveDirectoryExportFromLdap {
    param([string]$SearchBase)

    Add-Type -AssemblyName System.DirectoryServices -ErrorAction Stop

    $rootDse = [ADSI]'LDAP://RootDSE'
    $defaultNc = [string]$rootDse.defaultNamingContext
    $ldapRoot = if ($SearchBase) {
        if ($SearchBase -match '^(LDAP://|ldap://)(.+)$') { $SearchBase } else { "LDAP://$SearchBase" }
    }
    else {
        "LDAP://$defaultNc"
    }

    Write-LogMessage "Reading AD groups via LDAP (root: $($ldapRoot))." -Level INFO

    $entry = New-Object System.DirectoryServices.DirectoryEntry($ldapRoot)
    $searcher = New-Object System.DirectoryServices.DirectorySearcher($entry)
    $searcher.Filter = '(objectCategory=group)'
    $searcher.PageSize = 1000
    $searcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
    [void]$searcher.PropertiesToLoad.Add('distinguishedName')
    [void]$searcher.PropertiesToLoad.Add('objectGUID')
    [void]$searcher.PropertiesToLoad.Add('sAMAccountName')
    [void]$searcher.PropertiesToLoad.Add('name')
    [void]$searcher.PropertiesToLoad.Add('groupType')
    [void]$searcher.PropertiesToLoad.Add('description')
    [void]$searcher.PropertiesToLoad.Add('whenCreated')
    [void]$searcher.PropertiesToLoad.Add('whenChanged')
    [void]$searcher.PropertiesToLoad.Add('member')
    [void]$searcher.PropertiesToLoad.Add('memberOf')
    [void]$searcher.PropertiesToLoad.Add('managedBy')
    [void]$searcher.PropertiesToLoad.Add('objectSid')

    $allGroups = [System.Collections.Generic.List[object]]::new()
    foreach ($sr in $searcher.FindAll()) {
        $p = $sr.Properties
        $guidBytes = $p['objectguid'][0]
        $objGuid = [guid]::new($guidBytes)
        $gt = 0
        if ($p['grouptype'].Count -gt 0) { $gt = [int]$p['grouptype'][0] }
        $cs = Convert-AdsGroupTypeToCategoryAndScope -GroupType $gt
        $sidStr = $null
        if ($p['objectsid'].Count -gt 0) {
            $rawSid = $p['objectsid'][0]
            try {
                $sidBytes = if ($rawSid -is [byte[]]) { $rawSid } else { [byte[]]@($rawSid) }
                if ($sidBytes.Length -ge 8) {
                    $sidStr = ([System.Security.Principal.SecurityIdentifier]::new($sidBytes, 0)).Value
                }
            }
            catch {
                $sidStr = $null
            }
        }
        $members = [System.Collections.Generic.List[string]]::new()
        if ($p['member']) {
            foreach ($x in @($p['member'])) { [void]$members.Add([string]$x) }
        }
        $memberOfs = [System.Collections.Generic.List[string]]::new()
        if ($p['memberof']) {
            foreach ($x in @($p['memberof'])) { [void]$memberOfs.Add([string]$x) }
        }
        $managedBy = if ($p['managedby'].Count -gt 0) { [string]$p['managedby'][0] } else { $null }
        $desc = if ($p['description'].Count -gt 0) { [string]$p['description'][0] } else { $null }
        $sam = if ($p['samaccountname'].Count -gt 0) { [string]$p['samaccountname'][0] } else { $null }
        $name = if ($p['name'].Count -gt 0) { [string]$p['name'][0] } else { $null }
        $dn = [string]$p['distinguishedname'][0]
        $whenCreated = if ($p['whencreated'].Count -gt 0) { $p['whencreated'][0] } else { $null }
        $whenChangedLdap = if ($p['whenchanged'].Count -gt 0) { $p['whenchanged'][0] } else { $null }

        $allGroups.Add([pscustomobject]@{
                DistinguishedName = $dn
                ObjectGUID        = $objGuid
                SamAccountName    = $sam
                Name              = $name
                GroupCategory     = $cs.Category
                GroupScope        = $cs.Scope
                Description       = $desc
                WhenCreated       = $whenCreated
                WhenChanged       = $whenChangedLdap
                ManagedBy         = $managedBy
                SID               = $sidStr
                Member            = $members
                memberOf          = $memberOfs
            })
    }

    return $allGroups
}

function Build-ActiveDirectoryExportBody {
    param(
        [object[]]$AllGroups,
        [System.Collections.Generic.List[string]]$Warnings
    )

    $dnToGuid = New-CaseInsensitiveDictionary
    foreach ($g in $AllGroups) {
        $guidStr = $g.ObjectGUID.Guid.ToString()
        $dnToGuid[$g.DistinguishedName] = $guidStr
    }

    $edges = [System.Collections.Generic.List[object]]::new()
    $flat = [System.Collections.Generic.List[object]]::new()

    foreach ($g in $AllGroups) {
        $guidStr = $g.ObjectGUID.Guid.ToString()
        $memberGroupGuids = [System.Collections.Generic.List[string]]::new()
        $memberOfGroupGuids = [System.Collections.Generic.List[string]]::new()

        $memberList = @()
        if ($g.Member) { $memberList = @($g.Member) }

        if ($memberList.Count -gt 0) {
            foreach ($m in $memberList) {
                if ($dnToGuid.ContainsKey($m)) {
                    $cg = $dnToGuid[$m]
                    [void]$memberGroupGuids.Add($cg)
                    $edges.Add([ordered]@{
                            parentObjectGuid = $guidStr
                            childObjectGuid  = $cg
                        })
                }
            }
        }
        else {
            try {
                if (Get-Command Get-ADGroupMember -ErrorAction SilentlyContinue) {
                    $nested = @(Get-ADGroupMember -Identity $g.DistinguishedName -ErrorAction Stop |
                            Where-Object { $_.objectClass -eq 'group' })
                    foreach ($ng in $nested) {
                        $ngObj = Get-ADGroup -Identity $ng.DistinguishedName -Properties ObjectGUID -ErrorAction SilentlyContinue
                        if ($ngObj) {
                            $cg = $ngObj.ObjectGUID.Guid.ToString()
                            if (-not $memberGroupGuids.Contains($cg)) {
                                [void]$memberGroupGuids.Add($cg)
                                $edges.Add([ordered]@{
                                        parentObjectGuid = $guidStr
                                        childObjectGuid  = $cg
                                    })
                            }
                        }
                    }
                    if ($nested.Count -gt 0) {
                        $Warnings.Add("Group $($g.SamAccountName): used Get-ADGroupMember fallback for nested groups (member attribute empty or truncated).")
                    }
                }
            }
            catch {
                Write-LogMessage "Could not expand members for $($g.SamAccountName): $($_.Exception.Message)" -Level WARN
            }
        }

        $moList = @()
        if ($g.memberOf) { $moList = @($g.memberOf) }
        foreach ($mo in $moList) {
            if ($dnToGuid.ContainsKey($mo)) {
                [void]$memberOfGroupGuids.Add($dnToGuid[$mo])
            }
        }

        $sidStr = if ($g.SID) {
            if ($g.SID -is [string]) { $g.SID } else { $g.SID.Value }
        }
        else { $null }

        $wc = $null
        $wh = $null
        if ($g.WhenCreated) { $wc = Convert-LdapWhenToUtcString -Value $g.WhenCreated }
        if ($g.WhenChanged) { $wh = Convert-LdapWhenToUtcString -Value $g.WhenChanged }

        $gc = if ($g.GroupCategory -is [string]) { $g.GroupCategory } else { $g.GroupCategory.ToString() }
        $gs = if ($g.GroupScope -is [string]) { $g.GroupScope } else { $g.GroupScope.ToString() }

        $flat.Add([ordered]@{
                objectGuid          = $guidStr
                samAccountName      = $g.SamAccountName
                name                = $g.Name
                distinguishedName   = $g.DistinguishedName
                sid                 = $sidStr
                groupCategory       = $gc
                groupScope          = $gs
                description         = $g.Description
                whenCreatedUtc      = $wc
                whenChangedUtc      = $wh
                managedBy           = $g.ManagedBy
                memberGroupGuids    = @($memberGroupGuids)
                memberOfGroupGuids  = @($memberOfGroupGuids)
            })
    }

    $childSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($e in $edges) {
        [void]$childSet.Add($e.childObjectGuid)
    }

    $roots = [System.Collections.Generic.List[string]]::new()
    foreach ($row in $flat) {
        if (-not $childSet.Contains($row.objectGuid)) {
            [void]$roots.Add($row.objectGuid)
        }
    }

    $domainDns = $env:USERDNSROOT
    if (-not $domainDns) { $domainDns = $env:USERDNSDOMAIN }
    if (Get-Command Get-ADDomain -ErrorAction SilentlyContinue) {
        try { $domainDns = (Get-ADDomain -ErrorAction SilentlyContinue).DNSRoot } catch { }
    }

    return [ordered]@{
        metadata = [ordered]@{
            exportedAtUtc        = (Get-Date).ToUniversalTime().ToString('o')
            computerName         = $env:COMPUTERNAME
            technology           = 'ActiveDirectory'
            domainDns            = $domainDns
            groupCount           = $flat.Count
            containmentEdgeCount = $edges.Count
            rootsCount           = $roots.Count
            warnings             = @($Warnings)
        }
        groups      = @($flat)
        containment = [ordered]@{
            roots = @($roots)
            edges = @($edges)
        }
    }
}

function Get-ActiveDirectoryExportFromModule {
    param([string]$SearchBase)

    if (-not (Get-Module -Name ActiveDirectory -ErrorAction SilentlyContinue)) {
        Import-Module ActiveDirectory -ErrorAction Stop
    }

    $getParams = @{
        Filter      = '*'
        Properties  = @(
            'SamAccountName', 'Name', 'DistinguishedName', 'ObjectGUID', 'SID',
            'GroupCategory', 'GroupScope', 'Description', 'WhenCreated', 'WhenChanged',
            'ManagedBy', 'Member', 'memberOf'
        )
        ErrorAction = 'Stop'
    }
    if ($SearchBase) {
        $getParams['SearchBase'] = $SearchBase
    }

    Write-LogMessage 'Reading all AD groups via ActiveDirectory module (this may take a while in large domains).' -Level INFO
    $allGroups = @(Get-ADGroup @getParams)
    $warnings = [System.Collections.Generic.List[string]]::new()
    return Build-ActiveDirectoryExportBody -AllGroups $allGroups -Warnings $warnings
}

function Get-ActiveDirectoryExport {
    param([string]$SearchBase)

    try {
        return Get-ActiveDirectoryExportFromModule -SearchBase $SearchBase
    }
    catch {
        Write-LogMessage "ActiveDirectory module path failed ($($_.Exception.Message)); using System.DirectoryServices LDAP." -Level WARN
        $warnings = [System.Collections.Generic.List[string]]::new()
        $ldapGroups = @(Get-ActiveDirectoryExportFromLdap -SearchBase $SearchBase)
        return Build-ActiveDirectoryExportBody -AllGroups $ldapGroups -Warnings $warnings
    }
}

function Get-EntraExport {
    $skipped = [ordered]@{ skipped = $true; reason = $null }

    try {
        if (-not (Get-Command Get-MgGroup -ErrorAction SilentlyContinue)) {
            Import-Module Microsoft.Graph.Groups -ErrorAction Stop
        }
        if (-not (Get-Command Get-MgContext -ErrorAction SilentlyContinue)) {
            Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
        }
    }
    catch {
        $skipped.reason = "Microsoft Graph modules not available: $($_.Exception.Message)"
        return $skipped
    }

    $ctx = Get-MgContext -ErrorAction SilentlyContinue
    if (-not $ctx) {
        $skipped.reason = 'Not connected to Microsoft Graph (run Connect-MgGraph with Group.Read.All).'
        return $skipped
    }

    Write-LogMessage 'Reading Entra groups via Microsoft Graph.' -Level INFO
    $all = @(Get-MgGroup -All -Property Id, DisplayName, Description, GroupTypes, SecurityEnabled, MailEnabled, CreatedDateTime, MailNickname)

    $idSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($x in $all) { [void]$idSet.Add($x.Id) }

    $edges = [System.Collections.Generic.List[object]]::new()
    $flat = [System.Collections.Generic.List[object]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()

    foreach ($g in $all) {
        $memberGroupIds = [System.Collections.Generic.List[string]]::new()
        try {
            $page = Get-MgGroupMember -GroupId $g.Id -All -ErrorAction Stop
            foreach ($m in $page) {
                $isGroup = $false
                if ($m.AdditionalProperties -and $m.AdditionalProperties['@odata.type']) {
                    $isGroup = $m.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.group'
                }
                elseif ($m.'@odata.type') {
                    $isGroup = $m.'@odata.type' -eq '#microsoft.graph.group'
                }
                if ($isGroup -and $idSet.Contains($m.Id)) {
                    [void]$memberGroupIds.Add($m.Id)
                    $edges.Add([ordered]@{
                            parentObjectId = $g.Id
                            childObjectId  = $m.Id
                        })
                }
            }
        }
        catch {
            $warnings.Add("Entra group $($g.DisplayName) ($($g.Id)): member read failed — $($_.Exception.Message)")
        }

        $flat.Add([ordered]@{
                id              = $g.Id
                displayName     = $g.DisplayName
                description     = $g.Description
                mailNickname    = $g.MailNickname
                groupTypes      = @($g.GroupTypes)
                securityEnabled = $g.SecurityEnabled
                mailEnabled     = $g.MailEnabled
                createdUtc      = if ($g.CreatedDateTime) { $g.CreatedDateTime.ToUniversalTime().ToString('o') } else { $null }
                memberGroupIds  = @($memberGroupIds)
            })
    }

    $memberOfMap = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($e in $edges) {
        if (-not $memberOfMap.ContainsKey($e.childObjectId)) {
            $memberOfMap[$e.childObjectId] = [System.Collections.Generic.List[string]]::new()
        }
        [void]$memberOfMap[$e.childObjectId].Add($e.parentObjectId)
    }
    foreach ($row in $flat) {
        if ($memberOfMap.ContainsKey($row.id)) {
            $row['memberOfGroupIds'] = @($memberOfMap[$row.id])
        }
        else {
            $row['memberOfGroupIds'] = @()
        }
    }

    $childSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($e in $edges) { [void]$childSet.Add($e.childObjectId) }

    $roots = [System.Collections.Generic.List[string]]::new()
    foreach ($g in $all) {
        if (-not $childSet.Contains($g.Id)) {
            [void]$roots.Add($g.Id)
        }
    }

    return [ordered]@{
        metadata = [ordered]@{
            exportedAtUtc          = (Get-Date).ToUniversalTime().ToString('o')
            computerName         = $env:COMPUTERNAME
            technology           = 'EntraMicrosoftGraph'
            tenantId             = $ctx.TenantId
            groupCount           = $flat.Count
            containmentEdgeCount = $edges.Count
            rootsCount           = $roots.Count
            warnings             = @($warnings)
        }
        groups      = @($flat)
        containment = [ordered]@{
            roots = @($roots)
            edges = @($edges)
        }
    }
}

$exportRoot = [ordered]@{
    metadata = [ordered]@{
        exportedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        computerName  = $env:COMPUTERNAME
        source        = $Source
        scriptVersion = '1.0'
    }
}

try {
    if ($Source -eq 'AdOnly' -or $Source -eq 'Both') {
        $exportRoot['activeDirectory'] = Get-ActiveDirectoryExport -SearchBase $SearchBase
        Write-LogMessage "AD export: $($exportRoot.activeDirectory.metadata.groupCount) groups, $($exportRoot.activeDirectory.metadata.containmentEdgeCount) containment edges." -Level INFO
    }

    if ($Source -eq 'EntraOnly' -or $Source -eq 'Both') {
        $ent = Get-EntraExport
        if ($ent.skipped) {
            Write-LogMessage "Entra export skipped: $($ent.reason)" -Level WARN
            $exportRoot['entra'] = $ent
        }
        else {
            $exportRoot['entra'] = $ent
            Write-LogMessage "Entra export: $($ent.metadata.groupCount) groups, $($ent.metadata.containmentEdgeCount) containment edges." -Level INFO
        }
    }

    if (-not $OutputPath) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $OutputPath = Join-Path (Get-ApplicationDataPath) "AdEntra-Groups-export-$($stamp).json"
    }

    $dir = Split-Path -Path $OutputPath -Parent
    if ($dir -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $json = $exportRoot | ConvertTo-Json -Depth 25
    $json | Set-Content -Path $OutputPath -Encoding utf8

    $scriptFolderCopy = Join-Path $PSScriptRoot (Split-Path -Path $OutputPath -Leaf)
    Copy-Item -Path $OutputPath -Destination $scriptFolderCopy -Force
    Write-LogMessage "JSON written to: $($OutputPath)" -Level INFO
    Write-LogMessage "JSON copy next to script: $($scriptFolderCopy)" -Level INFO
    Write-LogMessage 'JOB_COMPLETED Export-AdEntraGroupsToJson' -Level INFO
    exit 0
}
catch {
    Write-LogMessage "JOB_FAILED Export-AdEntraGroupsToJson: $($_.Exception.Message)" -Level ERROR -Exception $_
    exit 1
}
