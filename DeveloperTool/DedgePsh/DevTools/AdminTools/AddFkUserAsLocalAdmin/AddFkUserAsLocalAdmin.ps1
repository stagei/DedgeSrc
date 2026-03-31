
try {
    $adminGroupNames = @("Administrators", "Administratorer")
    $localAdminGroup = $null

    # Find the correct local admin group name
    foreach ($groupName in $adminGroupNames) {
        try {
            $group = [ADSI]"WinNT://./$(${groupName}),group"
            if ($group.Name) {
                $localAdminGroup = $groupName
                break
            }
        }
        catch {
            # Continue to next group name
        }
    }

    if (-not $localAdminGroup) {
        Write-Host "Could not find administrators group with English or Norwegian name" -ForegroundColor Red
        return
    }

    # Get current user identity
    $currentUser = "$($env:USERDOMAIN)\$($env:USERNAME)"

    # Get the local admin group using ADSI
    $adminGroup = [ADSI]"WinNT://./$(${localAdminGroup}),group"

    # Check if the current user is already a local admin
    try {
        $members = $adminGroup.psbase.Invoke("Members")
        $currentUserIsAdmin = $false

        foreach ($member in $members) {
            $memberName = $member.GetType().InvokeMember("Name", 'GetProperty', $null, $member, $null)
            $memberClass = $member.GetType().InvokeMember("Class", 'GetProperty', $null, $member, $null)

            if ($memberClass -eq "User") {
                $fullMemberName = $member.GetType().InvokeMember("AdsPath", 'GetProperty', $null, $member, $null)
                if ($fullMemberName -match $env:USERNAME -or $memberName -eq $env:USERNAME) {
                    $currentUserIsAdmin = $true
                    break
                }
            }
        }

        if ($currentUserIsAdmin) {
            Write-Host "Current user $currentUser is already a local admin"
            return
        }
    }
    catch {
        Write-Host "Could not check current group membership, attempting to add user" -ForegroundColor Yellow
    }

    # Add user to the local admin group using ADSI
    try {
        $userPath = "WinNT://$($env:USERDOMAIN)/$($env:USERNAME),user"
        $adminGroup.psbase.Invoke("Add", $userPath)
        Write-Host "Successfully added $currentUser to the local admin group" -ForegroundColor Green
    }
    catch {
        # If domain user fails, try as local user
        try {
            $userPath = "WinNT://./$($env:USERNAME),user"
            $adminGroup.psbase.Invoke("Add", $userPath)
            Write-Host "Successfully added $env:USERNAME to the local admin group" -ForegroundColor Green
        }
        catch {
            throw "Failed to add user via both domain and local paths: $($_.Exception.Message)"
        }
    }
}
catch {
    Write-Host "Failed to add $($env:USERDOMAIN)\$($env:USERNAME) to the local admin group: $($_.Exception.Message)" -ForegroundColor Red
}

