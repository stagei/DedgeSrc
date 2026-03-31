param (
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [Parameter(Mandatory = $false)]
    [string[]]$AdditionalAdmins = @($("$env:USERDOMAIN\$env:USERNAME"), "$env:USERDOMAIN\ACL_ERPUTV_Utvikling_Full", "$env:USERDOMAIN\ACL_Dedge_Servere_Utviklere"),
    [Parameter(Mandatory = $false)]
    [string]$ShareName = "opt",
    [Parameter(Mandatory = $false)]
    [string]$EveryonePermission = "Read"
)
Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)"
if ($PSVersionTable.PSVersion.Major -ne 5) {
    Write-Host "PowerShell major version must be 5" -ForegroundColor Red
    exit 1
}
if ($ShareName -eq "") {
    throw "ShareName is empty"
}
# Convert the scriptblock to string and save to temp file
# Function to convert permission string to access right

try {
    # Check if the path exists
    $DrivePath = $Path
    if (-not (Test-Path -Path $DrivePath -PathType Container)) {
        throw "The specified path does not exist: $DrivePath"
    }

    # # Check if SMB feature is installed
    # $smbFeature = Get-WindowsFeature -Name FS-SMB1 -ErrorAction SilentlyContinue
    # if ($smbFeature -and $smbFeature.Installed) {
    #     Write-Host "SMB1 is installed. This is insecure and should be removed."
    #     Write-Host "Removing SMB1..."
    #     Remove-WindowsFeature -Name FS-SMB1
    # }

    # Ensure SMB3 is enabled (it's enabled by default in modern Windows)
    # Check if we can import the SMB module
    Import-Module SmbShare -ErrorAction SilentlyContinue
    if (-not (Get-Command New-SmbShare -ErrorAction SilentlyContinue)) {
        Write-Host "SMB PowerShell module not available. Installing required features..."
        # Install File Services features which include SMB support
        Install-WindowsFeature -Name FS-FileServer -IncludeManagementTools
        Import-Module SmbShare
    }

    # Configure SMB to use secure versions only
    Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force
    Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force
    # Set minimum SMB version to 3.0

    $existingShare = Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue
    if ($existingShare) {
        Write-Warning "Share '$ShareName' already exists. Removing existing share..."
        Remove-SmbShare -Name $ShareName -Force
    }

    # Create the share
    Write-Host "Creating share '$ShareName' for path '$DrivePath'..."
    New-SmbShare -Name $ShareName -Path $DrivePath -Description $Description -FullAccess "Administrators" | Out-Null

    # Remove inheritance and preserve inherited permissions
    $acl = Get-Acl -Path $DrivePath
    $acl.SetAccessRuleProtection($true, $true)
    Set-Acl -Path $DrivePath -AclObject $acl

    # Convert AdditionalAdmins to array of PSObjects and add default users
    $userPermissions = @()

    # Add default users
    $userPermissions += [PSCustomObject]@{
        User        = "Administrators"
        Permissions = "Full"
    }
    if ($EveryonePermission) {
        $userPermissions += [PSCustomObject]@{
            User        = "Everyone"
            Permissions = $EveryonePermission
        }
    }

    # Add additional admins
    foreach ($admin in $AdditionalAdmins) {
        $userPermissions += [PSCustomObject]@{
            User        = $admin
            Permissions = "Full"
        }
    }
    # Add permissions for each domain user
    foreach ($singleUserPermission in $userPermissions) {
        Write-Host "Adding $($singleUserPermission.Permissions) permissions for user: $($singleUserPermission.User)"

        # Add SMB share permission
        Grant-SmbShareAccess -Name $ShareName -AccountName $singleUserPermission.User -AccessRight $singleUserPermission.Permissions -Force | Out-Null

        # Add NTFS permission
        $acl = Get-Acl -Path $DrivePath
        $rights = switch ($singleUserPermission.Permissions) {
            "Read" { "ReadAndExecute" }
            "Change" { "Modify" }
            "Full" { "FullControl" }
            default { "ReadAndExecute" }
        }
        $inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
        $propagationFlags = [System.Security.AccessControl.PropagationFlags]::None
        $type = [System.Security.AccessControl.AccessControlType]::Allow

        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($singleUserPermission.User, $rights, $inheritanceFlags, $propagationFlags, $type)
        $acl.AddAccessRule($accessRule)
        Set-Acl -Path $DrivePath -AclObject $acl
    }

    Write-Host "`nShare created successfully!" -ForegroundColor Green
    Write-Host "Share Name: \\$($env:COMPUTERNAME)\$ShareName"

}
catch {
    Write-Error "Failed to create share: $_"
}

