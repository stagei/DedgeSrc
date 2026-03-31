return  #Not ready for deployment


# Author: Geir Helge Starholm, www.dEdge.no
#
# Deployment script for Scheduled Task Monitor tools
# Deploys monitoring scripts to target servers

# Set default values for parameters that need environment variables
if (-not $TargetServers) {
    $TargetServers = @($env:COMPUTERNAME)
}

if (-not $ServiceUser) {
    $ServiceUser = "$env:USERDOMAIN\$env:USERNAME"
}

Import-Module GlobalFunctions -Force
Import-Module ScheduledTask-Handler -Force
Import-Module Infrastructure -Force

<#
.SYNOPSIS
    Deploys scheduled task monitoring tools to servers.

.DESCRIPTION
    This script deploys the scheduled task monitoring tools to target servers:
    - Start-ScheduledTaskEventMonitor.ps1 - Real-time event monitoring
    - Invoke-TaskWithLogging.ps1 - Task wrapper for enhanced logging
    
.PARAMETER TargetServers
    Array of server names to deploy to. If not specified, deploys to current server.
    
.PARAMETER InstallAsService
    Create a scheduled task to run the event monitor as a service.
    
.PARAMETER ServiceUser
    User account for the monitoring service (default: current user).
    
.PARAMETER MonitoringInterval
    Polling interval in seconds for event monitoring (default: 30).
    
.PARAMETER EnableCurrentUserOnly
    Only monitor tasks for the service user account.

.EXAMPLE
    .\deploy.ps1 -InstallAsService
    
.EXAMPLE
    .\deploy.ps1 -TargetServers @("server1", "server2") -InstallAsService -EnableCurrentUserOnly
#>

param(
    [Parameter(Mandatory = $false)]
    [string[]]$TargetServers,
    
    [Parameter(Mandatory = $false)]
    [switch]$InstallAsService,
    
    [Parameter(Mandatory = $false)]
    [string]$ServiceUser,
    
    [Parameter(Mandatory = $false)]
    [int]$MonitoringInterval = 30,
    
    [Parameter(Mandatory = $false)]
    [switch]$EnableCurrentUserOnly,
    
    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

function Deploy-TaskMonitoringTools {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName,
        
        [Parameter(Mandatory = $false)]
        [switch]$InstallAsService,
        
        [Parameter(Mandatory = $false)]
        [string]$ServiceUser,
        
        [Parameter(Mandatory = $false)]
        [int]$MonitoringInterval,
        
        [Parameter(Mandatory = $false)]
        [switch]$EnableCurrentUserOnly,
        
        [Parameter(Mandatory = $false)]
        [switch]$DryRun
    )
    
    Write-LogMessage "Deploying scheduled task monitoring tools to: $ServerName" -Level INFO
    
    $sourceFolder = $PSScriptRoot
    $targetFolder = "\\$ServerName\C$\opt\DedgePshApps\ScheduledTaskMonitor"
    
    try {
        # Create target directory
        if (-not $DryRun) {
            if (-not (Test-Path $targetFolder)) {
                New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null
                Write-LogMessage "Created target directory: $targetFolder" -Level INFO
            }
        } else {
            Write-LogMessage "DRY RUN: Would create directory: $targetFolder" -Level INFO
        }
        
        # Copy monitoring scripts
        $filesToCopy = @(
            "Start-ScheduledTaskEventMonitor.ps1",
            "Invoke-TaskWithLogging.ps1"
        )
        
        foreach ($file in $filesToCopy) {
            $sourcePath = Join-Path $sourceFolder $file
            $targetPath = Join-Path $targetFolder $file
            
            if (Test-Path $sourcePath) {
                if (-not $DryRun) {
                    Copy-Item -Path $sourcePath -Destination $targetPath -Force
                    Write-LogMessage "Copied: $file" -Level INFO
                } else {
                    Write-LogMessage "DRY RUN: Would copy: $file" -Level INFO
                }
            } else {
                Write-LogMessage "Warning: Source file not found: $sourcePath" -Level WARN
            }
        }
        
        # Install as service if requested
        if ($InstallAsService) {
            Install-TaskMonitoringService -ServerName $ServerName -ServiceUser $ServiceUser -MonitoringInterval $MonitoringInterval -EnableCurrentUserOnly:$EnableCurrentUserOnly -DryRun:$DryRun
        }
        
        Write-LogMessage "Successfully deployed to: $ServerName" -Level INFO
    }
    catch {
        Write-LogMessage "Failed to deploy to server: $ServerName" -Level ERROR -Exception $_
        throw
    }
}

function Install-TaskMonitoringService {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName,
        
        [Parameter(Mandatory = $true)]
        [string]$ServiceUser,
        
        [Parameter(Mandatory = $false)]
        [int]$MonitoringInterval = 30,
        
        [Parameter(Mandatory = $false)]
        [switch]$EnableCurrentUserOnly,
        
        [Parameter(Mandatory = $false)]
        [switch]$DryRun
    )
    
    Write-LogMessage "Installing task monitoring service on: $ServerName" -Level INFO
    
    $taskName = "FK-TaskMonitoringService"
    $scriptPath = "$env:OptPath\DedgePshApps\ScheduledTaskMonitor\Start-ScheduledTaskEventMonitor.ps1"
    
    # Build arguments for the monitoring script
    $arguments = "-File `"$scriptPath`" -PollingIntervalSeconds $MonitoringInterval"
    if ($EnableCurrentUserOnly) {
        $arguments += " -MonitorCurrentUser"
    }
    
    if ($DryRun) {
        Write-LogMessage "DRY RUN: Would create scheduled task '$taskName' on $ServerName" -Level INFO
        Write-LogMessage "DRY RUN: Script: $scriptPath" -Level INFO
        Write-LogMessage "DRY RUN: Arguments: $arguments" -Level INFO
        Write-LogMessage "DRY RUN: User: $ServiceUser" -Level INFO
        return
    }
    
    try {
        # Create scheduled task on target server
        $session = $null
        if ($ServerName -ne $env:COMPUTERNAME) {
            $session = New-PSSession -ComputerName $ServerName
        }
        
        $scriptBlock = {
            param($TaskName, $ScriptPath, $Arguments, $ServiceUser)
            
            # Remove existing task if it exists
            $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
            if ($existingTask) {
                Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
                Write-Host "Removed existing task: $TaskName"
            }
            
            # Create new task
            $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $Arguments
            $trigger = New-ScheduledTaskTrigger -AtStartup
            $principal = New-ScheduledTaskPrincipal -UserId $ServiceUser -LogonType ServiceAccount -RunLevel Highest
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
            
            Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "FK Scheduled Task Monitoring Service"
            
            # Start the task
            Start-ScheduledTask -TaskName $TaskName
            
            Write-Host "Successfully created and started task: $TaskName"
        }
        
        if ($session) {
            Invoke-Command -Session $session -ScriptBlock $scriptBlock -ArgumentList $taskName, $scriptPath, $arguments, $ServiceUser
            Remove-PSSession $session
        } else {
            & $scriptBlock $taskName $scriptPath $arguments $ServiceUser
        }
        
        Write-LogMessage "Successfully installed monitoring service: $taskName" -Level INFO
    }
    catch {
        Write-LogMessage "Failed to install monitoring service on: $ServerName" -Level ERROR -Exception $_
        throw
    }
}

function Remove-TaskMonitoringService {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName,
        
        [Parameter(Mandatory = $false)]
        [switch]$DryRun
    )
    
    Write-LogMessage "Removing task monitoring service from: $ServerName" -Level INFO
    
    $taskName = "FK-TaskMonitoringService"
    
    if ($DryRun) {
        Write-LogMessage "DRY RUN: Would remove scheduled task '$taskName' from $ServerName" -Level INFO
        return
    }
    
    try {
        $session = $null
        if ($ServerName -ne $env:COMPUTERNAME) {
            $session = New-PSSession -ComputerName $ServerName
        }
        
        $scriptBlock = {
            param($TaskName)
            
            $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
            if ($existingTask) {
                Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
                Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
                Write-Host "Successfully removed task: $TaskName"
            } else {
                Write-Host "Task not found: $TaskName"
            }
        }
        
        if ($session) {
            Invoke-Command -Session $session -ScriptBlock $scriptBlock -ArgumentList $taskName
            Remove-PSSession $session
        } else {
            & $scriptBlock $taskName
        }
        
        Write-LogMessage "Successfully removed monitoring service: $taskName" -Level INFO
    }
    catch {
        Write-LogMessage "Failed to remove monitoring service from: $ServerName" -Level ERROR -Exception $_
        throw
    }
}

# Main execution
Write-LogMessage "Starting deployment of scheduled task monitoring tools" -Level INFO

if ($DryRun) {
    Write-LogMessage "DRY RUN MODE - No changes will be made" -Level WARN
}

foreach ($server in $TargetServers) {
    try {
        Deploy-TaskMonitoringTools -ServerName $server -InstallAsService:$InstallAsService -ServiceUser $ServiceUser -MonitoringInterval $MonitoringInterval -EnableCurrentUserOnly:$EnableCurrentUserOnly -DryRun:$DryRun
    }
    catch {
        Write-LogMessage "Deployment failed for server: $server" -Level ERROR -Exception $_
        continue
    }
}

Write-LogMessage "Deployment completed for $($TargetServers.Count) servers" -Level INFO
