<#
.SYNOPSIS
    Sets NTFS ACL on the Cursor-ServerOrchestrator data folder so that only
    members of DEDGE\ACL_Dedge_Utviklere_Modernisering can write command files.

.DESCRIPTION
    Creates the data folder if it does not exist, then applies the following ACL:
    - SYSTEM: FullControl (required for scheduled task)
    - BUILTIN\Administrators: FullControl
    - DEDGE\ACL_Dedge_Utviklere_Modernisering: Modify (read, write, delete)
    - Inheritance from parent is disabled; only explicit rules apply.

    This script is called by _install.ps1 and runs on the target server.
#>

Import-Module GlobalFunctions -Force

$dataPath = Join-Path $env:OptPath "data" "Cursor-ServerOrchestrator"

if (-not (Test-Path $dataPath)) {
    New-Item -ItemType Directory -Path $dataPath -Force | Out-Null
    Write-LogMessage "Created data folder: $($dataPath)" -Level INFO
}

$historyPath = Join-Path $dataPath "history"
if (-not (Test-Path $historyPath)) {
    New-Item -ItemType Directory -Path $historyPath -Force | Out-Null
}

try {
    $acl = New-Object System.Security.AccessControl.DirectorySecurity

    $acl.SetAccessRuleProtection($true, $false)

    # SID S-1-5-18 = NT AUTHORITY\SYSTEM (locale-independent)
    $systemSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")
    $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $systemSid,
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
        [System.Security.AccessControl.PropagationFlags]::None,
        [System.Security.AccessControl.AccessControlType]::Allow
    )
    $acl.AddAccessRule($systemRule)

    # SID S-1-5-32-544 = BUILTIN\Administrators (locale-independent)
    $adminSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
    $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $adminSid,
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
        [System.Security.AccessControl.PropagationFlags]::None,
        [System.Security.AccessControl.AccessControlType]::Allow
    )
    $acl.AddAccessRule($adminRule)

    try {
        $devGroupIdentity = New-Object System.Security.Principal.NTAccount("DEDGE", "ACL_Dedge_Utviklere_Modernisering")
        $devGroupIdentity.Translate([System.Security.Principal.SecurityIdentifier]) | Out-Null
        $devGroupRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $devGroupIdentity,
            [System.Security.AccessControl.FileSystemRights]::Modify,
            ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        $acl.AddAccessRule($devGroupRule)
    }
    catch {
        Write-LogMessage "Could not resolve DEDGE\ACL_Dedge_Utviklere_Modernisering - skipping dev group ACL (expected on non-domain machines)" -Level WARN
    }

    Set-Acl -Path $dataPath -AclObject $acl
    Write-LogMessage "ACL applied to $($dataPath): SYSTEM=Full, Administrators=Full, ACL_Dedge_Utviklere_Modernisering=Modify" -Level INFO

    Set-Acl -Path $historyPath -AclObject $acl
    Write-LogMessage "ACL applied to $($historyPath)" -Level INFO
}
catch {
    Write-LogMessage "Failed to set ACL on $($dataPath): $($_.Exception.Message)" -Level ERROR
    throw
}
