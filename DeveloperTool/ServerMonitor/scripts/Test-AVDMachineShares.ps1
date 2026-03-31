<#
.SYNOPSIS
    Validates network availability and COBNT share access for AVD workstations.

.DESCRIPTION
    This script checks machines p-no1avd-wrk001 through p-no1avd-wrk099 for:
    - Network availability (ping test)
    - COBNT share existence and accessibility
    - Share permissions for specified DEDGE domain group

.PARAMETER GroupNames
    The DEDGE domain groups to check for share permissions.
    Defaults to @("DEDGE\ACL_ERPUTV_Utvikling_Full", "DEDGE\ACL_Dedge_Servere_Utviklere")

.PARAMETER OutputPath
    Path to save the results file. Defaults to C:\opt\data\AVD-Share-Report.csv

.PARAMETER StartNumber
    Starting machine number. Defaults to 1.

.PARAMETER EndNumber
    Ending machine number. Defaults to 99.

.EXAMPLE
    .\Test-AVDMachineShares.ps1

.EXAMPLE
    .\Test-AVDMachineShares.ps1 -GroupNames @("DEDGE\CustomGroup1", "DEDGE\CustomGroup2")
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$GroupNames = @(
        "DEDGE\ACL_ERPUTV_Utvikling_Full",
        "DEDGE\ACL_Dedge_Servere_Utviklere"
    ),

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "C:\opt\data\AVD-Share-Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv",

    [Parameter(Mandatory = $false)]
    [int]$StartNumber = 1,

    [Parameter(Mandatory = $false)]
    [int]$EndNumber = 99
)

Import-Module GlobalFunctions -Force

Write-LogMessage "Starting AVD Machine Share Validation" -Level INFO
Write-LogMessage "Checking machines p-no1avd-wrk$($StartNumber.ToString('000')) through p-no1avd-wrk$($EndNumber.ToString('000'))" -Level INFO
Write-LogMessage "Checking for COBNT share with permissions for: $($GroupNames -join ', ')" -Level INFO

# Generate machine names
$machines = $StartNumber..$EndNumber | ForEach-Object {
    "p-no1avd-wrk$($_.ToString('000'))"
}

Write-LogMessage "Total machines to check: $($machines.Count)" -Level INFO

# Results collection
$results = [System.Collections.Generic.List[PSCustomObject]]::new()

# Progress counter
$totalMachines = $machines.Count
$current = 0

foreach ($machine in $machines) {
    $current++
    $percentComplete = [math]::Round(($current / $totalMachines) * 100, 0)
    Write-Progress -Activity "Checking AVD Machines" -Status "Processing $($machine) ($($current)/$($totalMachines))" -PercentComplete $percentComplete

    $result = [PSCustomObject]@{
        MachineName       = $machine
        NetworkAvailable  = $false
        ShareExists       = $false
        ShareAccessible   = $false
        GroupHasAccess    = $false
        SharePermissions  = ""
        ErrorMessage      = ""
    }

    try {
        # Test network connectivity with timeout
        $pingResult = Test-Connection -ComputerName $machine -Count 1 -Quiet -TimeoutSeconds 2 -ErrorAction SilentlyContinue
        $result.NetworkAvailable = $pingResult

        if (-not $pingResult) {
            $result.ErrorMessage = "Machine not reachable on network"
            Write-LogMessage "Machine $($machine): Not reachable" -Level WARN
        }
        else {
            Write-LogMessage "Machine $($machine): Online - checking COBNT share" -Level DEBUG

            # Check if COBNT share exists
            $sharePath = "\\$($machine)\COBNT"
            
            try {
                # Test if share path exists
                $shareExists = Test-Path -Path $sharePath -ErrorAction Stop
                $result.ShareExists = $shareExists
                $result.ShareAccessible = $shareExists

                if ($shareExists) {
                    Write-LogMessage "Machine $($machine): COBNT share exists" -Level DEBUG
                    
                    # Get share permissions using Get-SmbShareAccess if we can connect via WMI/CIM
                    try {
                        $shareAccess = Invoke-Command -ComputerName $machine -ScriptBlock {
                            param($shareName)
                            Get-SmbShareAccess -Name $shareName -ErrorAction Stop | 
                                Select-Object AccountName, AccessControlType, AccessRight
                        } -ArgumentList "COBNT" -ErrorAction Stop

                        if ($shareAccess) {
                            # Format permissions as string
                            $permStrings = $shareAccess | ForEach-Object {
                                "$($_.AccountName):$($_.AccessRight)"
                            }
                            $result.SharePermissions = $permStrings -join "; "

                            # Check if ALL specified groups have access
                            $allGroupsHaveAccess = $true
                            $missingGroups = @()
                            foreach ($groupName in $GroupNames) {
                                $groupAccess = $shareAccess | Where-Object { 
                                    $_.AccountName -like "*$($groupName.Split('\')[-1])*" -or 
                                    $_.AccountName -eq $groupName 
                                }
                                if (-not $groupAccess) {
                                    $allGroupsHaveAccess = $false
                                    $missingGroups += $groupName
                                }
                            }
                            
                            if ($allGroupsHaveAccess) {
                                $result.GroupHasAccess = $true
                                Write-LogMessage "Machine $($machine): All groups have access to COBNT share" -Level INFO
                            }
                            else {
                                Write-LogMessage "Machine $($machine): Missing access for: $($missingGroups -join ', ')" -Level WARN
                            }
                        }
                    }
                    catch {
                        # Fallback: Try to get NTFS permissions if share permissions fail
                        Write-LogMessage "Machine $($machine): Could not get share permissions via remoting, trying NTFS ACL" -Level DEBUG
                        
                        try {
                            $acl = Get-Acl -Path $sharePath -ErrorAction Stop
                            $aclStrings = $acl.Access | ForEach-Object {
                                "$($_.IdentityReference):$($_.FileSystemRights)"
                            }
                            $result.SharePermissions = "NTFS: " + ($aclStrings -join "; ")

                            # Check group access in NTFS for all groups
                            $allGroupsHaveAccess = $true
                            foreach ($groupName in $GroupNames) {
                                $groupNtfsAccess = $acl.Access | Where-Object {
                                    $_.IdentityReference -like "*$($groupName.Split('\')[-1])*" -or
                                    $_.IdentityReference -eq $groupName
                                }
                                if (-not $groupNtfsAccess) {
                                    $allGroupsHaveAccess = $false
                                }
                            }
                            
                            if ($allGroupsHaveAccess) {
                                $result.GroupHasAccess = $true
                            }
                        }
                        catch {
                            $result.SharePermissions = "Unable to retrieve permissions"
                            $result.ErrorMessage = "Share exists but cannot retrieve permissions: $($_.Exception.Message)"
                        }
                    }
                }
                else {
                    $result.ErrorMessage = "COBNT share does not exist"
                    Write-LogMessage "Machine $($machine): COBNT share does not exist" -Level WARN
                }
            }
            catch {
                $result.ShareExists = $false
                $result.ShareAccessible = $false
                $result.ErrorMessage = "Cannot access share path: $($_.Exception.Message)"
                Write-LogMessage "Machine $($machine): Cannot access share - $($_.Exception.Message)" -Level ERROR
            }
        }
    }
    catch {
        $result.ErrorMessage = "Unexpected error: $($_.Exception.Message)"
        Write-LogMessage "Machine $($machine): Unexpected error - $($_.Exception.Message)" -Level ERROR
    }

    $results.Add($result)
}

Write-Progress -Activity "Checking AVD Machines" -Completed

# Summary statistics
$onlineCount = ($results | Where-Object { $_.NetworkAvailable }).Count
$shareExistsCount = ($results | Where-Object { $_.ShareExists }).Count
$groupAccessCount = ($results | Where-Object { $_.GroupHasAccess }).Count

Write-LogMessage "========== SUMMARY ==========" -Level INFO
Write-LogMessage "Total machines checked: $($results.Count)" -Level INFO
Write-LogMessage "Machines online: $($onlineCount)" -Level INFO
Write-LogMessage "Machines with COBNT share: $($shareExistsCount)" -Level INFO
Write-LogMessage "Machines where all groups have access: $($groupAccessCount)" -Level INFO
Write-LogMessage "=============================" -Level INFO

# Output to console as table
Write-Host ""
Write-Host "===== AVD Machine Share Validation Results =====" -ForegroundColor Cyan
Write-Host ""

$results | Format-Table -Property MachineName, NetworkAvailable, ShareExists, ShareAccessible, GroupHasAccess -AutoSize

# Detailed view for machines with issues
$issuesMachines = $results | Where-Object { $_.NetworkAvailable -and (-not $_.ShareExists -or -not $_.GroupHasAccess) }
if ($issuesMachines.Count -gt 0) {
    Write-Host ""
    Write-Host "===== Machines Online but with Issues =====" -ForegroundColor Yellow
    $issuesMachines | Format-Table -Property MachineName, ShareExists, GroupHasAccess, ErrorMessage -AutoSize -Wrap
}

# Export to CSV
$outputDir = Split-Path -Path $OutputPath -Parent
if (-not (Test-Path -Path $outputDir)) {
    New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
}

$results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
Write-LogMessage "Results exported to: $($OutputPath)" -Level INFO

# Also create a summary file
$summaryPath = $OutputPath -replace '\.csv$', '_Summary.txt'
$summaryContent = @"
AVD Machine Share Validation Summary
=====================================
Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Groups Checked: $($GroupNames -join ', ')
Machine Range: p-no1avd-wrk$($StartNumber.ToString('000')) to p-no1avd-wrk$($EndNumber.ToString('000'))

Results:
--------
Total machines checked: $($results.Count)
Machines online: $onlineCount
Machines with COBNT share: $shareExistsCount
Machines where group has access: $groupAccessCount

Online machines without COBNT share:
$(($results | Where-Object { $_.NetworkAvailable -and -not $_.ShareExists } | ForEach-Object { "  - $($_.MachineName)" }) -join "`n")

Online machines where group lacks access:
$(($results | Where-Object { $_.NetworkAvailable -and $_.ShareExists -and -not $_.GroupHasAccess } | ForEach-Object { "  - $($_.MachineName)" }) -join "`n")
"@

$summaryContent | Out-File -FilePath $summaryPath -Encoding UTF8
Write-LogMessage "Summary exported to: $($summaryPath)" -Level INFO

Write-Host ""
Write-Host "Report files saved:" -ForegroundColor Green
Write-Host "  CSV: $($OutputPath)" -ForegroundColor Green
Write-Host "  Summary: $($summaryPath)" -ForegroundColor Green

# Return results object for pipeline usage
return $results
