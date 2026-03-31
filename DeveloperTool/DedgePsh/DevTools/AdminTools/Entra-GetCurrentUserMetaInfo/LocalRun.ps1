$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
# $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())

# Get groups and privileges
$groups = $currentUser.Groups | ForEach-Object {
    try {
        $_.Translate([System.Security.Principal.NTAccount]).Value
    }
    catch {
        $_.Value # Fallback to SID if translation fails
    }
}
$privileges = [System.Security.Principal.WindowsIdentity]::GetCurrent().Claims |
Where-Object { $_.Type -like '*right*' } |
Select-Object -ExpandProperty Value

$currentUserInfo = [PSCustomObject]@{
    UserName   = $currentUser.Name
    UserDomain = $currentUser.User
    Groups     = $groups
    Privileges = $privileges
    IsAdmin    = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
Write-Host "Current User"
$currentUser | Format-Table -AutoSize
Write-Host "Current User Group Info"
$currentUserInfo | Format-Table -AutoSize

Write-Host "Related Group Metadata"
$groupTable = @()
foreach ($group in $groups) {
    $groupTable += [PSCustomObject]@{
        Name   = $group
        Type   = if ($group -match "^S-\d-\d+-\d+-\d+") { "SID" } else { "Group" }
        Domain = if ($group -match "\\") { $group.Split('\')[0] } else { "Local" }
    }
}
$groupTable | Format-Table -AutoSize

$privTable = @()
foreach ($privilege in $privileges) {
    $privTable += [PSCustomObject]@{
        Name     = $privilege
        Category = switch -Wildcard ($privilege) {
            "*SeBackup*" { "Backup" }
            "*SeDebug*" { "Debug" }
            "*SeSystem*" { "System" }
            "*SeNetwork*" { "Network" }
            default { "Other" }
        }
    }
}

Write-Host "Related Privilege Metadata"
$privTable | Format-Table -AutoSize

Write-Host "Current User Privileges"
$currentUser.Privileges | Format-Table -AutoSize

$commonLogPath = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Commonlogging\Server\ServiceUsersMetadata"

Write-Host "Common Log Path: $commonLogPath"

# Create combined object with user and group info
$combinedInfo = [PSCustomObject]@{
    ComputerName = $env:COMPUTERNAME
    UserInfo     = $currentUserInfo
    Groups       = $groupTable
    Privileges   = $privTable
    Timestamp    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
}

# Create filename with timestamp
$fileName = "ServiceUserMetadata_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
$outputPath = Join-Path $commonLogPath $fileName

# Export to JSON file
$combinedInfo | ConvertTo-Json -Depth 10 | Out-File $outputPath
Write-Host "Exported service user metadata to $outputPath"

