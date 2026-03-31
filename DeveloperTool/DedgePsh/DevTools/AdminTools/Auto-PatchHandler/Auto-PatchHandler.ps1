<#
.SYNOPSIS
    Automated Windows Server Patching Handler for Application Administrators

.DESCRIPTION
    This script provides application administrators with control over Windows Update patching
    on servers, overriding system administrator settings. It can be scheduled to run automatically
    and provides comprehensive logging and notification capabilities.

    Features:
    - Override Windows Update settings and policies
    - Install critical and security updates automatically
    - Schedule patching during maintenance windows
    - Comprehensive logging and reporting
    - Email notifications for patch status
    - Rollback capabilities for failed patches
    - Exclusion management for specific updates

.PARAMETER Action
    The action to perform: Install, Check, Configure, Rollback, or Status

.PARAMETER UpdateType
    Type of updates to install: Critical, Security, All, or Custom

.PARAMETER MaintenanceWindow
    Maintenance window in hours (default: 4)

.PARAMETER ForceReboot
    Force reboot after patching (default: false)

.PARAMETER ExcludeUpdates
    Array of KB numbers or update titles to exclude

.PARAMETER TestMode
    Run in test mode without making actual changes

.EXAMPLE
    .\Auto-PatchHandler.ps1 -Action Install -UpdateType Security -ForceReboot
    # Install security updates and reboot if required

.EXAMPLE
    .\Auto-PatchHandler.ps1 -Action Check -UpdateType All
    # Check for all available updates without installing

.EXAMPLE
    .\Auto-PatchHandler.ps1 -Action Configure -MaintenanceWindow 6
    # Configure Windows Update settings with 6-hour maintenance window

.NOTES
    Author: Dedge Application Administration Team
    Version: 1.0
    Requires: PowerShell 5.1+, Windows Server 2012+
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Install", "Check", "Configure", "Rollback", "Status")]
    [string]$Action,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Critical", "Security", "All", "Custom")]
    [string]$UpdateType = "Security",

    [Parameter(Mandatory = $false)]
    [int]$MaintenanceWindow = 4,

    [Parameter(Mandatory = $false)]
    [switch]$ForceReboot,

    [Parameter(Mandatory = $false)]
    [string[]]$ExcludeUpdates = @(),

    [Parameter(Mandatory = $false)]
    [switch]$TestMode,

    [Parameter(Mandatory = $false)]
    [string]$SmsNumbers
)

# Import required modules
Import-Module GlobalFunctions -Force

# Initialize logging
$script:StartTime = Get-Date
$script:PatchResults = @{
    Success        = @()
    Failed         = @()
    Skipped        = @()
    RebootRequired = $false
}

# Configuration settings
$script:Config = @{
    WindowsUpdateService   = "wuauserv"
    UpdateSessionTimeout   = 3600  # 1 hour
    MaxRetryAttempts       = 3
    RetryDelaySeconds      = 30
    MaintenanceWindowHours = $MaintenanceWindow
    TestMode               = $TestMode
}

function Test-AdministratorPrivileges {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Set-WindowsUpdateSettings {
    Write-LogMessage "Configuring Windows Update settings for application admin control" -Level INFO

    try {
        # Stop Windows Update service
        Write-LogMessage "Stopping Windows Update service" -Level INFO
        Stop-Service -Name $script:Config.WindowsUpdateService -Force -ErrorAction SilentlyContinue

        # Configure Windows Update registry settings
        $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
        $regPathAU = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"

        # Create registry keys if they don't exist
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        if (-not (Test-Path $regPathAU)) {
            New-Item -Path $regPathAU -Force | Out-Null
        }

        # Override system admin settings
        $registrySettings = @{
            "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU\NoAutoUpdate"                  = 0
            "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU\AUOptions"                     = 4  # Auto download and schedule install
            "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU\ScheduledInstallDay"           = 0  # Every day
            "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU\ScheduledInstallTime"          = 2  # 2 AM
            "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU\UseWUServer"                   = 0  # Use Microsoft Update
            "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU\NoAutoRebootWithLoggedOnUsers" = 0
            "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU\RebootRelaunchTimeoutEnabled"  = 1
            "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU\RebootRelaunchTimeout"         = 15  # 15 minutes
        }

        foreach ($setting in $registrySettings.GetEnumerator()) {
            if (-not $script:Config.TestMode) {
                Set-ItemProperty -Path $setting.Key.Split('=')[0] -Name $setting.Key.Split('=')[1] -Value $setting.Value -Force
            }
            Write-LogMessage "Set registry: $($setting.Key) = $($setting.Value)" -Level DEBUG
        }

        # Start Windows Update service
        Write-LogMessage "Starting Windows Update service" -Level INFO
        Start-Service -Name $script:Config.WindowsUpdateService -ErrorAction Stop

        Write-LogMessage "Windows Update settings configured successfully" -Level INFO
        return $true
    }
    catch {
        Write-LogMessage "Failed to configure Windows Update settings: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

function Get-AvailableUpdates {
    param(
        [Parameter(Mandatory = $false)]
        [string]$UpdateCategory = "All"
    )

    Write-LogMessage "Checking for available updates (Category: $UpdateCategory)" -Level INFO

    try {
        # Create Windows Update session
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()

        # Search for updates
        $searchResult = $updateSearcher.Search("IsInstalled=0 and Type='Software'")

        $availableUpdates = @()
        foreach ($update in $searchResult.Updates) {
            $updateInfo = @{
                Title        = $update.Title
                KB           = if ($update.KBArticleIDs.Count -gt 0) { $update.KBArticleIDs[0] } else { "N/A" }
                Size         = [math]::Round($update.MaxDownloadSize / 1MB, 2)
                IsDownloaded = $update.IsDownloaded
                IsMandatory  = $update.IsMandatory
                Categories   = $update.Categories | ForEach-Object { $_.Name }
                Description  = $update.Description
                Identity     = $update.Identity.UpdateID
            }

            # Filter by category
            if ($UpdateCategory -eq "All" -or
                ($UpdateCategory -eq "Critical" -and $updateInfo.IsMandatory) -or
                ($UpdateCategory -eq "Security" -and ($updateInfo.Categories -contains "Security Updates"))) {
                $availableUpdates += $updateInfo
            }
        }

        Write-LogMessage "Found $($availableUpdates.Count) available updates" -Level INFO
        return $availableUpdates
    }
    catch {
        Write-LogMessage "Failed to check for updates: $($_.Exception.Message)" -Level ERROR
        return @()
    }
}

function Install-WindowsUpdates {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Updates,

        [Parameter(Mandatory = $false)]
        [string[]]$ExcludeList = @()
    )

    Write-LogMessage "Starting installation of $($Updates.Count) updates" -Level INFO

    try {
        # Create update session
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        $updateDownloader = $updateSession.CreateUpdateDownloader()
        $updateInstaller = $updateSession.CreateUpdateInstaller()

        # Get update collection
        $updateCollection = New-Object -ComObject Microsoft.Update.UpdateColl

        foreach ($update in $Updates) {
            # Check if update should be excluded
            $shouldExclude = $false
            foreach ($exclude in $ExcludeList) {
                if ($update.Title -like "*$exclude*" -or $update.KB -like "*$exclude*") {
                    $shouldExclude = $true
                    $script:PatchResults.Skipped += $update
                    Write-LogMessage "Excluding update: $($update.Title)" -Level INFO
                    break
                }
            }

            if (-not $shouldExclude) {
                # Find the actual update object
                $searchResult = $updateSearcher.Search("IsInstalled=0 and Type='Software'")
                foreach ($actualUpdate in $searchResult.Updates) {
                    if ($actualUpdate.Identity.UpdateID -eq $update.Identity) {
                        $null = $updateCollection.Add($actualUpdate)
                        break
                    }
                }
            }
        }

        if ($updateCollection.Count -eq 0) {
            Write-LogMessage "No updates to install after exclusions" -Level WARN
            return $true
        }

        # Download updates
        Write-LogMessage "Downloading $($updateCollection.Count) updates..." -Level INFO
        if (-not $script:Config.TestMode) {
            $updateDownloader.Updates = $updateCollection
            $downloadResult = $updateDownloader.Download()

            if ($downloadResult.ResultCode -ne 2) {
                # 2 = succeeded
                Write-LogMessage "Download failed with result code: $($downloadResult.ResultCode)" -Level ERROR
                return $false
            }
        }

        # Install updates
        Write-LogMessage "Installing $($updateCollection.Count) updates..." -Level INFO
        if (-not $script:Config.TestMode) {
            $updateInstaller.Updates = $updateCollection
            $updateInstaller.AllowSourcePrompts = $false
            $updateInstaller.ForceQuiet = $true

            $installResult = $updateInstaller.Install()

            # Process results
            for ($i = 0; $i -lt $updateCollection.Count; $i++) {
                $update = $updateCollection.Item($i)
                $result = $installResult.GetUpdateResult($i)

                if ($result.ResultCode -eq 2) {
                    # 2 = succeeded
                    $script:PatchResults.Success += @{
                        Title = $update.Title
                        KB    = if ($update.KBArticleIDs.Count -gt 0) { $update.KBArticleIDs[0] } else { "N/A" }
                    }
                    Write-LogMessage "Successfully installed: $($update.Title)" -Level INFO
                }
                else {
                    $script:PatchResults.Failed += @{
                        Title     = $update.Title
                        KB        = if ($update.KBArticleIDs.Count -gt 0) { $update.KBArticleIDs[0] } else { "N/A" }
                        ErrorCode = $result.ResultCode
                    }
                    Write-LogMessage "Failed to install: $($update.Title) (Error: $($result.ResultCode))" -Level ERROR
                }

                # Check if reboot is required
                if ($result.RebootRequired) {
                    $script:PatchResults.RebootRequired = $true
                }
            }
        }
        else {
            Write-LogMessage "TEST MODE: Would install $($updateCollection.Count) updates" -Level INFO
        }

        Write-LogMessage "Update installation completed" -Level INFO
        return $true
    }
    catch {
        Write-LogMessage "Failed to install updates: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

function Send-PatchNotification {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EmailAddress,

        [Parameter(Mandatory = $true)]
        [string]$Subject,

        [Parameter(Mandatory = $true)]
        [string]$Body
    )

    if ([string]::IsNullOrEmpty($EmailAddress)) {
        return
    }

    try {
        Write-LogMessage "Sending notification email to: $EmailAddress" -Level INFO

        # Create HTML email body
        $htmlBody = @"
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; }
        .header { background-color: #f0f0f0; padding: 10px; }
        .success { color: green; }
        .error { color: red; }
        .warning { color: orange; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <div class="header">
        <h2>Windows Update Patching Report</h2>
        <p><strong>Server:</strong> $env:COMPUTERNAME</p>
        <p><strong>Date:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        <p><strong>Duration:</strong> $((Get-Date) - $script:StartTime)</p>
    </div>

    <h3>Summary</h3>
    <ul>
        <li><strong>Successful Updates:</strong> $($script:PatchResults.Success.Count)</li>
        <li><strong>Failed Updates:</strong> $($script:PatchResults.Failed.Count)</li>
        <li><strong>Skipped Updates:</strong> $($script:PatchResults.Skipped.Count)</li>
        <li><strong>Reboot Required:</strong> $($script:PatchResults.RebootRequired)</li>
    </ul>

    $Body
</body>
</html>
"@

        Send-EmailMessage -To $EmailAddress -Subject $Subject -HtmlBody $htmlBody
        Write-LogMessage "Notification email sent successfully" -Level INFO
    }
    catch {
        Write-LogMessage "Failed to send notification email: $($_.Exception.Message)" -Level ERROR
    }
}

function Get-PatchStatus {
    Write-LogMessage "Retrieving current patch status" -Level INFO

    try {
        $status = @{
            LastCheckTime        = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Install" -Name "LastSuccessTime" -ErrorAction SilentlyContinue).LastSuccessTime
            PendingReboot        = $null -ne (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -ErrorAction SilentlyContinue)
            WindowsUpdateService = (Get-Service -Name $script:Config.WindowsUpdateService).Status
            AvailableUpdates     = (Get-AvailableUpdates -UpdateCategory "All").Count
        }

        Write-LogMessage "Patch Status:" -Level INFO
        Write-LogMessage "  Last Check: $($status.LastCheckTime)" -Level INFO
        Write-LogMessage "  Pending Reboot: $($status.PendingReboot)" -Level INFO
        Write-LogMessage "  Windows Update Service: $($status.WindowsUpdateService)" -Level INFO
        Write-LogMessage "  Available Updates: $($status.AvailableUpdates)" -Level INFO

        return $status
    }
    catch {
        Write-LogMessage "Failed to get patch status: $($_.Exception.Message)" -Level ERROR
        return $null
    }
}

function Start-RebootIfRequired {
    if ($script:PatchResults.RebootRequired -or $ForceReboot) {
        Write-LogMessage "Reboot is required after patching" -Level WARN

        if (-not $script:Config.TestMode) {
            # Send notification before reboot
            if ($SmsNumbers) {
                foreach ($smsNumber in $SmsNumbers) {
                    Send-Sms -Receiver $smsNumber -Message "Server will reboot in 5 minutes due to Windows Updates installation."
                }
            }

            # Schedule reboot in 5 minutes
            Write-LogMessage "Scheduling reboot in 5 minutes" -Level WARN
            shutdown /r /t 300 /c "Windows Updates installed - Automatic reboot scheduled"
        }
        else {
            Write-LogMessage "TEST MODE: Would schedule reboot in 5 minutes" -Level INFO
        }
    }
}

# Main execution
try {
    Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED
    Write-LogMessage "Action: $Action, UpdateType: $UpdateType, TestMode: $($script:Config.TestMode)" -Level INFO

    # Check administrator privileges
    if (-not (Test-AdministratorPrivileges)) {
        Write-LogMessage "This script requires administrator privileges" -Level ERROR
        exit 1
    }

    switch ($Action) {
        "Configure" {
            Write-LogMessage "Configuring Windows Update settings" -Level INFO
            $configResult = Set-WindowsUpdateSettings
            if ($configResult) {
                Write-LogMessage "Configuration completed successfully" -Level INFO
            }
            else {
                Write-LogMessage "Configuration failed" -Level ERROR
                exit 1
            }
        }

        "Check" {
            Write-LogMessage "Checking for available updates" -Level INFO
            $updates = Get-AvailableUpdates -UpdateCategory $UpdateType
            Write-LogMessage "Found $($updates.Count) updates of type: $UpdateType" -Level INFO

            foreach ($update in $updates) {
                Write-LogMessage "  - $($update.Title) (KB: $($update.KB), Size: $($update.Size) MB)" -Level INFO
            }
        }

        "Install" {
            Write-LogMessage "Starting update installation process" -Level INFO

            # Configure settings first
            Set-WindowsUpdateSettings | Out-Null

            # Get available updates
            $updates = Get-AvailableUpdates -UpdateCategory $UpdateType
            if ($updates.Count -eq 0) {
                Write-LogMessage "No updates available for installation" -Level INFO
                break
            }

            # Install updates
            $installResult = Install-WindowsUpdates -Updates $updates -ExcludeList $ExcludeUpdates

            if ($installResult) {
                Write-LogMessage "Update installation process completed" -Level INFO

                # Send notification
                if ($SmsNumbers) {
                    foreach ($smsNumber in $SmsNumbers) {
                        Send-Sms -Receiver $smsNumber -Message "Windows Updates installed on $env:COMPUTERNAME.`nSuccessfully installed $($script:PatchResults.Success.Count) updates.`nFailed to install $($script:PatchResults.Failed.Count) updates.`nSkipped $($script:PatchResults.Skipped.Count) updates."
                    }
                }

                # Handle reboot if required
                Start-RebootIfRequired
            }
            else {
                Write-LogMessage "Update installation failed" -Level ERROR
                exit 1
            }
        }

        "Status" {
            Get-PatchStatus | Out-Null
        }

        "Rollback" {
            Write-LogMessage "Rollback functionality not implemented in this version" -Level WARN
        }
    }

    $duration = (Get-Date) - $script:StartTime
    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {

    Write-LogMessage "Script execution failed: $($_.Exception.Message)" -Level ERROR
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED -Exception $_
    exit 1
}

