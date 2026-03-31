<#
.SYNOPSIS
    Creates the COBNT share on AVD workstations with specified permissions.

.DESCRIPTION
    This script remotely creates a COBNT share on machines p-no1avd-wrk001 through p-no1avd-wrk099.
    The share is created with Full access for:
    - DEDGE\ACL_ERPUTV_Utvikling_Full
    - DEDGE\ACL_Dedge_Servere_Utviklere

.PARAMETER StartNumber
    Starting machine number. Defaults to 1.

.PARAMETER EndNumber
    Ending machine number. Defaults to 99.

.PARAMETER LocalPath
    The local folder path to share. Defaults to C:\COBNT

.PARAMETER AccessGroups
    Array of DEDGE domain groups to grant Full access.
    Defaults to @("DEDGE\ACL_ERPUTV_Utvikling_Full", "DEDGE\ACL_Dedge_Servere_Utviklere")

.PARAMETER WhatIf
    Shows what would happen without making changes.

.EXAMPLE
    .\New-COBNTShare.ps1
    Creates share on all machines 001-099

.EXAMPLE
    .\New-COBNTShare.ps1 -StartNumber 1 -EndNumber 10
    Creates share on machines 001-010 only

.EXAMPLE
    .\New-COBNTShare.ps1 -WhatIf
    Shows what would happen without making changes
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [int]$StartNumber = 1,

    [Parameter(Mandatory = $false)]
    [int]$EndNumber = 99,

    [Parameter(Mandatory = $false)]
    [string]$LocalPath = "C:\COBNT",

    [Parameter(Mandatory = $false)]
    [string[]]$AccessGroups = @(
        "DEDGE\ACL_ERPUTV_Utvikling_Full",
        "DEDGE\ACL_Dedge_Servere_Utviklere"
    )
)

$shareName = "COBNT"
$accessGroups = $AccessGroups

# Generate machine names
$machines = $StartNumber..$EndNumber | ForEach-Object {
    "p-no1avd-wrk$($_.ToString('000'))"
}

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  COBNT Share Creation Script" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Machines: p-no1avd-wrk$($StartNumber.ToString('000')) through p-no1avd-wrk$($EndNumber.ToString('000'))" -ForegroundColor White
Write-Host "Share Name: $($shareName)" -ForegroundColor White
Write-Host "Local Path: $($LocalPath)" -ForegroundColor White
Write-Host "Access Groups:" -ForegroundColor White
$accessGroups | ForEach-Object { Write-Host "  - $_" -ForegroundColor White }
Write-Host ""

# Results collection
$results = [System.Collections.Generic.List[PSCustomObject]]::new()

$totalMachines = $machines.Count
$current = 0

foreach ($machine in $machines) {
    $current++
    $percentComplete = [math]::Round(($current / $totalMachines) * 100, 0)
    Write-Progress -Activity "Creating COBNT Shares" -Status "Processing $($machine) ($($current)/$($totalMachines))" -PercentComplete $percentComplete

    $result = [PSCustomObject]@{
        MachineName    = $machine
        Online         = $false
        FolderCreated  = $false
        ShareCreated   = $false
        PermissionsSet = $false
        Status         = ""
        ErrorMessage   = ""
    }

    # Test connectivity first
    $pingResult = Test-Connection -ComputerName $machine -Count 1 -Quiet -TimeoutSeconds 2 -ErrorAction SilentlyContinue
    
    if (-not $pingResult) {
        $result.Status = "Offline"
        $result.ErrorMessage = "Machine not reachable"
        Write-Host "[$($machine)] " -NoNewline -ForegroundColor Yellow
        Write-Host "OFFLINE - Skipping" -ForegroundColor Red
        $results.Add($result)
        continue
    }

    $result.Online = $true

    if ($PSCmdlet.ShouldProcess($machine, "Create COBNT share")) {
        try {
            $remoteResult = Invoke-Command -ComputerName $machine -ScriptBlock {
                param($shareName, $localPath, $accessGroups)
                
                $output = @{
                    FolderCreated  = $false
                    ShareCreated   = $false
                    PermissionsSet = $false
                    Status         = ""
                    Error          = ""
                }

                try {
                    # Step 1: Create the folder if it doesn't exist
                    if (-not (Test-Path -Path $localPath)) {
                        New-Item -Path $localPath -ItemType Directory -Force | Out-Null
                        $output.FolderCreated = $true
                        $output.Status = "Folder created"
                    }
                    else {
                        $output.FolderCreated = $true
                        $output.Status = "Folder already exists"
                    }

                    # Step 2: Check if share already exists
                    $existingShare = Get-SmbShare -Name $shareName -ErrorAction SilentlyContinue
                    
                    if ($existingShare) {
                        # Share exists - remove it first to recreate with correct permissions
                        Remove-SmbShare -Name $shareName -Force -ErrorAction Stop
                        $output.Status += "; Existing share removed"
                    }

                    # Step 3: Create the share with no access initially
                    New-SmbShare -Name $shareName -Path $localPath -FullAccess "Administrators" -ErrorAction Stop | Out-Null
                    $output.ShareCreated = $true
                    $output.Status += "; Share created"

                    # Step 4: Grant access to specified groups
                    foreach ($group in $accessGroups) {
                        try {
                            Grant-SmbShareAccess -Name $shareName -AccountName $group -AccessRight Full -Force -ErrorAction Stop | Out-Null
                        }
                        catch {
                            $output.Error += "Failed to grant access to $($group): $($_.Exception.Message); "
                        }
                    }
                    $output.PermissionsSet = $true
                    $output.Status += "; Permissions set"

                    # Step 5: Set NTFS permissions on the folder as well
                    $acl = Get-Acl -Path $localPath
                    foreach ($group in $accessGroups) {
                        try {
                            $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                                $group,
                                "FullControl",
                                "ContainerInherit,ObjectInherit",
                                "None",
                                "Allow"
                            )
                            $acl.AddAccessRule($accessRule)
                        }
                        catch {
                            $output.Error += "Failed to set NTFS for $($group): $($_.Exception.Message); "
                        }
                    }
                    Set-Acl -Path $localPath -AclObject $acl -ErrorAction Stop
                    $output.Status += "; NTFS permissions set"
                }
                catch {
                    $output.Error = $_.Exception.Message
                }

                return $output
            } -ArgumentList $shareName, $LocalPath, $accessGroups -ErrorAction Stop

            $result.FolderCreated = $remoteResult.FolderCreated
            $result.ShareCreated = $remoteResult.ShareCreated
            $result.PermissionsSet = $remoteResult.PermissionsSet
            $result.Status = $remoteResult.Status
            $result.ErrorMessage = $remoteResult.Error

            if ($result.ShareCreated -and $result.PermissionsSet) {
                Write-Host "[$($machine)] " -NoNewline -ForegroundColor Green
                Write-Host "SUCCESS - $($result.Status)" -ForegroundColor Green
            }
            else {
                Write-Host "[$($machine)] " -NoNewline -ForegroundColor Yellow
                Write-Host "PARTIAL - $($result.Status) | Error: $($result.ErrorMessage)" -ForegroundColor Yellow
            }
        }
        catch {
            $result.ErrorMessage = $_.Exception.Message
            $result.Status = "Failed"
            Write-Host "[$($machine)] " -NoNewline -ForegroundColor Red
            Write-Host "FAILED - $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    else {
        $result.Status = "WhatIf - No changes made"
        Write-Host "[$($machine)] " -NoNewline -ForegroundColor Cyan
        Write-Host "WHATIF - Would create share" -ForegroundColor Cyan
    }

    $results.Add($result)
}

Write-Progress -Activity "Creating COBNT Shares" -Completed

# Summary
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  SUMMARY" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

$onlineCount = ($results | Where-Object { $_.Online }).Count
$successCount = ($results | Where-Object { $_.ShareCreated -and $_.PermissionsSet }).Count
$failedCount = ($results | Where-Object { $_.Online -and (-not $_.ShareCreated -or -not $_.PermissionsSet) }).Count
$offlineCount = ($results | Where-Object { -not $_.Online }).Count

Write-Host "Total machines: $($results.Count)" -ForegroundColor White
Write-Host "Online: $($onlineCount)" -ForegroundColor White
Write-Host "Successful: $($successCount)" -ForegroundColor Green
Write-Host "Failed: $($failedCount)" -ForegroundColor $(if ($failedCount -gt 0) { "Red" } else { "White" })
Write-Host "Offline: $($offlineCount)" -ForegroundColor $(if ($offlineCount -gt 0) { "Yellow" } else { "White" })
Write-Host ""

# Output table
$results | Format-Table -Property MachineName, Online, FolderCreated, ShareCreated, PermissionsSet, Status -AutoSize

# Export to CSV
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$outputPath = "C:\opt\data\COBNT-Share-Creation_$($timestamp).csv"

# Ensure output directory exists
$outputDir = Split-Path -Path $outputPath -Parent
if (-not (Test-Path -Path $outputDir)) {
    New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
}

$results | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
Write-Host "Results exported to: $($outputPath)" -ForegroundColor Green

# Return results
return $results
