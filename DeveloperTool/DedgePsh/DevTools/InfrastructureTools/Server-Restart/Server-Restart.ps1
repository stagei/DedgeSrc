#!/usr/bin/env pwsh
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Restarts the server with a planned reason and automated notifications

.DESCRIPTION
    Performs a controlled server restart with logging, user notification,
    and configurable delay. Logs the restart reason and time to system event log
    and application logs for audit purposes.

    Designed for automated execution via scheduled tasks with no user interaction required.
    By default, forces restart, notifies users, and sends SMS.

.PARAMETER Reason
    The reason for the server restart. Defaults to "Planned server reboot".
    This will be logged in the event log and application logs.

.PARAMETER DelaySeconds
    Number of seconds to wait before restarting. Defaults to 30 seconds.
    Provides time for services to complete current operations and for users to save work.

.PARAMETER Force
    Forces restart even if users are logged in or applications are running.
    Defaults to true for automated execution. Set to false for interactive mode.

.PARAMETER NotifyUsers
    When true (default), sends notification to logged-in users before restart.
    Shows a warning message with countdown timer via Windows messaging.

.PARAMETER SendSms
    When true (default), sends SMS notification to the current user about the restart.
    Uses the team member SMS numbers from GlobalFunctions configuration.

.PARAMETER NoDelay
    When true, skips the delay countdown and restarts immediately.
    Defaults to false. Set to true for emergency restarts.

.PARAMETER WhatIf
    Shows what would happen without actually restarting the server.

.EXAMPLE
    .\Server-Restart.ps1
    Restarts the server with default settings (forced, with notifications and SMS).

.EXAMPLE
    .\Server-Restart.ps1 -Reason "Monthly security updates" -DelaySeconds 60
    Restarts after 60 seconds with specified reason.

.EXAMPLE
    .\Server-Restart.ps1 -Force:$false
    Interactive mode: prompts for confirmation if users are logged in.

.EXAMPLE
    .\Server-Restart.ps1 -NoDelay:$true -Reason "Emergency patch"
    Immediate forced restart for emergency situations.

.NOTES
    Requires Administrator privileges to restart the server.
    Designed for use in scheduled tasks with automated execution.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$Reason = "Planned server reboot",

    [Parameter(Mandatory = $false)]
    [int]$DelaySeconds = 30,

    [Parameter(Mandatory = $false)]
    [bool]$Force = $true,

    [Parameter(Mandatory = $false)]
    [bool]$NotifyUsers = $true,

    [Parameter(Mandatory = $false)]
    [bool]$SendSms = $true,

    [Parameter(Mandatory = $false)]
    [bool]$NoDelay = $false
)

Import-Module GlobalFunctions -Force

try {
    $ErrorActionPreference = "Stop"

    Write-LogMessage "═══════════════════════════════════════════════════════" -Level INFO
    Write-LogMessage "  Server Restart Script" -Level INFO
    Write-LogMessage "═══════════════════════════════════════════════════════" -Level INFO


    # Verify running as administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-LogMessage "❌ ERROR: This script must be run as Administrator!" -Level ERROR
        throw "This script must be run as Administrator!"
    }

    # Get server information
    $serverName = $env:COMPUTERNAME
    $currentUser = $env:USERNAME
    $restartTime = (Get-Date).AddSeconds($DelaySeconds)

    Write-LogMessage "Server: $($serverName)" -Level INFO
    Write-LogMessage "User: $($currentUser)" -Level INFO
    Write-LogMessage "Reason: $($Reason)" -Level INFO
    Write-LogMessage "Mode: $(if ($Force) { 'Forced (automated)' } else { 'Interactive' })" -Level INFO
    Write-LogMessage "Notify Users: $($NotifyUsers)" -Level INFO
    Write-LogMessage "Send SMS: $($SendSms)" -Level INFO

    if ($NoDelay) {
        Write-LogMessage "Restart: Immediate (no delay)" -Level WARN
    }
    else {
        Write-LogMessage "Restart scheduled: $($restartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Level INFO
        Write-LogMessage "Delay: $($DelaySeconds) seconds" -Level INFO
    }

    # Check for logged-in users
    $loggedInUsers = @()
    try {
        $quser = & quser 2>&1
        if ($LASTEXITCODE -eq 0 -and $quser) {
            $loggedInUsers = $quser | Select-Object -Skip 1 | ForEach-Object {
                $line = $_ -replace '\s{2,}', ','
                $fields = $line -split ','
                if ($fields.Count -ge 1) { $fields[0].Trim() }
            } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        }
    }
    catch {
        Write-LogMessage "⚠️  Could not query logged-in users: $($_.Exception.Message)" -Level WARN
    }

    if ($loggedInUsers.Count -gt 0) {
        Write-LogMessage "⚠️  WARNING: $($loggedInUsers.Count) user(s) currently logged in:" -Level WARN
        foreach ($user in $loggedInUsers) {
            Write-LogMessage "   - $($user)" -Level WARN
        }


        if (-not $Force) {
            Write-LogMessage "💡 Use -Force to restart anyway" -Level WARN
            $confirmation = Read-Host "Continue with restart? (y/n)"
            if ($confirmation -ne 'y') {
                Write-LogMessage "❌ Restart cancelled by user" -Level WARN
                exit 0
            }
        }
    }
    else {
        Write-LogMessage "✅ No users currently logged in" -Level INFO
    }

    # # Remove existing WKAKT file for WKSTYR
    # if ($serverName.ToUpper().Contains( "P-NO1FKMPRD-DB")) {
    #     $wkaktPath = "\\p-no1fkmprd-app\WKAKT"
    #     if (Test-Path $wkaktPath) {
    #         $wkaktFile = $wkaktPath + "\WKSTYR.AKT"
    #         if (Test-Path $wkaktFile) {
    #             Remove-Item -Path $wkaktFile -Force
    #             Write-LogMessage "✅ WKSTYR file removed" -Level INFO
    #         }
    #         else {
    #             Write-LogMessage "❌ WKSTYR file not found" -Level WARN
    #         }
    #         $DelaySeconds += 120 # Add 2 minutes to the delay
    #     }
    # }

    # Send SMS notification if requested
    if ($SendSms) {
        Write-LogMessage "📱 Sending SMS notification..." -Level INFO
        try {
            # Send SMS to all team members
            $smsRecipients = @(
                "+4797188358",
                "+4795762742"
                # "+4799348397",  # FKMISTA
                # "+4745269945"   # FKCELERI
            )

            $smsMessage = "Server restart: $($serverName) will restart in $($DelaySeconds)s. Reason: $($Reason)"
            $smsSentCount = 0

            foreach ($number in $smsRecipients) {
                try {
                    Send-Sms -Receiver $number -Message $smsMessage
                    $smsSentCount++
                    Write-LogMessage "   ✅ SMS sent to $($number)" -Level INFO
                }
                catch {
                    Write-LogMessage "   ⚠️  Failed to send SMS to $($number): $($_.Exception.Message)" -Level WARN
                }
            }

            Write-LogMessage "✅ SMS notifications sent to $($smsSentCount) of $($smsRecipients.Count) recipients" -Level INFO
        }
        catch {
            Write-LogMessage "⚠️  Could not send SMS: $($_.Exception.Message)" -Level WARN
        }

    }
    # Log to Windows Event Log
    Write-LogMessage "📋 Logging restart to Windows Event Log..." -Level INFO
    try {
        $eventSource = "ServerRestart"
        if (-not [System.Diagnostics.EventLog]::SourceExists($eventSource)) {
            New-EventLog -LogName Application -Source $eventSource -ErrorAction Stop
            Write-LogMessage "   Created event log source: $($eventSource)" -Level INFO
        }

        $eventMessage = @"
Server Restart Initiated
========================
Server: $serverName
User: $currentUser
Reason: $Reason
Scheduled Time: $($restartTime.ToString('yyyy-MM-dd HH:mm:ss'))
Delay: $DelaySeconds seconds
Mode: $(if ($Force) { 'Forced (automated)' } else { 'Interactive' })
Notify Users: $NotifyUsers
Send SMS: $SendSms
"@

        Write-EventLog -LogName Application -Source $eventSource -EventId 1000 -EntryType Information -Message $eventMessage -ErrorAction Stop
        Write-LogMessage "✅ Event logged successfully" -Level INFO
    }
    catch {
        Write-LogMessage "⚠️  Could not log to Event Log: $($_.Exception.Message)" -Level WARN
    }




    # Notify logged-in users
    if ($NotifyUsers -and $loggedInUsers.Count -gt 0) {
        Write-LogMessage "🔔 Notifying logged-in users..." -Level INFO
        try {
            $userMessage = "SYSTEM RESTART SCHEDULED`n`nServer: $serverName`nReason: $Reason`nRestart in: $DelaySeconds seconds`n`nPlease save your work immediately!"

            # Use msg.exe to send message to all sessions
            $sessions = & query session 2>&1 | Select-Object -Skip 1
            foreach ($session in $sessions) {
                if ($session -match '\s+(\d+)\s+') {
                    $sessionId = $Matches[1]
                    & msg.exe $sessionId /TIME:60 $userMessage 2>&1 | Out-Null
                }
            }
            Write-LogMessage "✅ User notifications sent" -Level INFO
        }
        catch {
            Write-LogMessage "⚠️  Could not notify users: $($_.Exception.Message)" -Level WARN
        }

    }

    # Countdown delay (unless NoDelay)
    if (-not $NoDelay -and $DelaySeconds -gt 0) {
        Write-LogMessage "⏳ Countdown to restart:" -Level INFO

        $remainingSeconds = $DelaySeconds
        while ($remainingSeconds -gt 0) {
            if ($remainingSeconds -le 10 -or $remainingSeconds % 10 -eq 0) {
                Write-LogMessage "   $($remainingSeconds) seconds remaining..." -Level WARN
            }
            Start-Sleep -Seconds 1
            $remainingSeconds--
        }

    }

    # Final confirmation
    if ($WhatIfPreference) {
        Write-LogMessage "🔍 WhatIf: Would restart server now with reason: $($Reason)" -Level INFO
        Write-LogMessage "   Command: Restart-Computer -Force:$($Force) -ComputerName $($serverName)" -Level INFO
        exit 0
    }

    # Perform the restart
    Write-LogMessage "🔄 Initiating server restart..." -Level WARN
    Write-LogMessage "   Server: $($serverName)" -Level WARN
    Write-LogMessage "   Reason: $($Reason)" -Level WARN


    $restartParams = @{
        ComputerName = $serverName
        Force        = $Force
        ErrorAction  = 'Stop'
    }

    if ($PSCmdlet.ShouldProcess($serverName, "Restart server with reason: $Reason")) {
        Restart-Computer @restartParams
        Write-LogMessage "✅ Restart command issued successfully" -Level INFO
        Write-LogMessage "   The server will restart momentarily..." -Level INFO
    }

}
catch {
    Write-LogMessage "❌ Failed to restart server: $($_.Exception.Message)" -Level ERROR
    Write-LogMessage "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    exit 1
}

