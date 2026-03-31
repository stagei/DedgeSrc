#!/usr/bin/env pwsh
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Removes the legacy Windows Service installation of ServerMonitorDashboard.

.DESCRIPTION
    ServerMonitorDashboard was previously deployed as a Windows Service running on a
    dedicated port. It has since been migrated to an IIS virtual application.
    This script cleans up all remnants of the old service-mode deployment from
    computers that have not yet been migrated:

      - Windows Service "ServerMonitorDashboard" (stopped and deleted)
      - Registry Services key HKLM\...\Services\ServerMonitorDashboard
      - Registry Run/RunOnce autostart values referencing ServerMonitorDashboard
      - Scheduled tasks installed by the old service setup
      - Firewall rules created by the old service setup
      - Legacy install folders:
          $env:OptPath\IIS\ServerMonitorDashboard
          $env:OptPath\DedgePshApps\ServerMonitorDashboard

    After running this script, deploy the IIS version using:
        IIS-DeployApp.ps1 -SiteName ServerMonitorDashboard

.PARAMETER WhatIf
    Reports what would be removed without making any changes.

.PARAMETER SkipFolderRemoval
    Skip removal of legacy install folders. Useful if you want to preserve files
    for inspection before deletion.

.EXAMPLE
    .\Remove-ServerMonitorDashboardService.ps1 -WhatIf

.EXAMPLE
    .\Remove-ServerMonitorDashboardService.ps1

.EXAMPLE
    .\Remove-ServerMonitorDashboardService.ps1 -SkipFolderRemoval
#>
param(
    [switch]$WhatIf,
    [switch]$SkipFolderRemoval
)

$ErrorActionPreference = "Stop"

Import-Module GlobalFunctions -Force

Set-OverrideAppDataFolder -Path $(Join-Path $env:OptPath "data" "IIS-DeployApp")
Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_STARTED

$serviceName    = "ServerMonitorDashboard"
$servicesRoot   = "HKLM:\SYSTEM\CurrentControlSet\Services"
$serviceKey     = Join-Path $servicesRoot $serviceName
$legacyIisPath  = Join-Path $env:OptPath "IIS\$serviceName"
$legacyPshApp   = Join-Path $env:OptPath "DedgePshApps\$serviceName"

$report = [System.Collections.Generic.List[PSCustomObject]]::new()
function Add-Report {
    param([string]$Step, [string]$Status, [string]$Detail)
    $report.Add([PSCustomObject]@{ Step = $Step; Status = $Status; Detail = $Detail })
}

if ($WhatIf) {
    Write-LogMessage "=== WHATIF MODE — no changes will be made ===" -Level WARN
}

try {
    Write-LogMessage "Server: $($env:COMPUTERNAME)" -Level INFO

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 1: Stop and delete the Windows Service
    # ═══════════════════════════════════════════════════════════════════════════
    Write-LogMessage "--- Step 1: Windows Service ---" -Level INFO

    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($svc) {
        Write-LogMessage "  Found service '$($serviceName)' — Status: $($svc.Status)" -Level WARN
        Add-Report -Step "Step 1" -Status "FOUND" -Detail "Windows Service '$($serviceName)' exists (Status: $($svc.Status))"

        if (-not $WhatIf) {
            if ($svc.Status -ne 'Stopped') {
                Write-LogMessage "  Stopping service '$($serviceName)'..." -Level INFO
                Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 3
            }
            $scResult = & sc.exe delete $serviceName 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-LogMessage "  Service '$($serviceName)' deleted successfully." -Level INFO
                Add-Report -Step "Step 1" -Status "REMOVED" -Detail "Windows Service deleted"
            } else {
                Write-LogMessage "  sc.exe delete result: $($scResult)" -Level WARN
                Add-Report -Step "Step 1" -Status "WARN" -Detail "sc.exe delete returned: $($scResult)"
            }
        }
    } else {
        Write-LogMessage "  No Windows Service '$($serviceName)' found." -Level INFO
        Add-Report -Step "Step 1" -Status "CLEAN" -Detail "No Windows Service present"
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 2: Remove Services registry key
    # ═══════════════════════════════════════════════════════════════════════════
    Write-LogMessage "--- Step 2: Services registry key ---" -Level INFO

    if (Test-Path $serviceKey) {
        $svcReg  = Get-ItemProperty -Path $serviceKey -ErrorAction SilentlyContinue
        $imgPath = $svcReg.ImagePath
        Write-LogMessage "  Found registry key: $($serviceKey)" -Level WARN
        Write-LogMessage "    ImagePath : $($imgPath)" -Level WARN
        Write-LogMessage "    Start     : $($svcReg.Start)  (2=Auto, 3=Manual, 4=Disabled)" -Level WARN
        Write-LogMessage "    ObjectName: $($svcReg.ObjectName)" -Level WARN
        Add-Report -Step "Step 2" -Status "FOUND" -Detail "Service registry key present — ImagePath: $($imgPath) | Start: $($svcReg.Start)"

        if (-not $WhatIf) {
            Remove-Item -Path $serviceKey -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path $serviceKey) {
                Write-LogMessage "  WARNING: Registry key still present — may need reboot to fully remove." -Level WARN
                Add-Report -Step "Step 2" -Status "WARN" -Detail "Registry key still present after removal — reboot may be required"
            } else {
                Write-LogMessage "  Registry key removed." -Level INFO
                Add-Report -Step "Step 2" -Status "REMOVED" -Detail "Service registry key removed"
            }
        }
    } else {
        Write-LogMessage "  No registry key for '$($serviceName)' found." -Level INFO
        Add-Report -Step "Step 2" -Status "CLEAN" -Detail "No registry key present"
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 3: Remove Run/RunOnce autostart registry values
    # ═══════════════════════════════════════════════════════════════════════════
    Write-LogMessage "--- Step 3: Run/RunOnce autostart registry values ---" -Level INFO

    $runPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
    )

    $foundRun = 0
    foreach ($runPath in $runPaths) {
        if (-not (Test-Path $runPath)) { continue }
        $runValues = Get-ItemProperty -Path $runPath -ErrorAction SilentlyContinue
        if (-not $runValues) { continue }

        $runValues.PSObject.Properties | Where-Object {
            $_.Name -notlike 'PS*' -and $_.Value -match [regex]::Escape($serviceName)
        } | ForEach-Object {
            $valName = $_.Name
            $valData = $_.Value
            Write-LogMessage "  Found Run value '$($valName)' in $($runPath)" -Level WARN
            Write-LogMessage "    Data: $($valData)" -Level WARN
            Add-Report -Step "Step 3" -Status "FOUND" -Detail "Run value '$($valName)' = '$($valData)' in $($runPath)"
            $foundRun++

            if (-not $WhatIf) {
                Remove-ItemProperty -Path $runPath -Name $valName -ErrorAction SilentlyContinue
                Write-LogMessage "  Removed Run value '$($valName)' from $($runPath)" -Level INFO
                Add-Report -Step "Step 3" -Status "REMOVED" -Detail "Removed Run value '$($valName)'"
            }
        }
    }
    if ($foundRun -eq 0) {
        Write-LogMessage "  No autostart Run/RunOnce values found." -Level INFO
        Add-Report -Step "Step 3" -Status "CLEAN" -Detail "No Run/RunOnce autostart values"
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 4: Remove legacy scheduled tasks
    # ═══════════════════════════════════════════════════════════════════════════
    Write-LogMessage "--- Step 4: Scheduled tasks ---" -Level INFO

    $legacyTasks = @(
        "ServerMonitorDashboard",
        "Install-ServerMonitorDashboard",
        "DevTools\Install-ServerMonitorDashboard"
    )

    $foundTasks = 0
    foreach ($taskName in $legacyTasks) {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($task) {
            Write-LogMessage "  Found scheduled task: '$($taskName)'" -Level WARN
            Add-Report -Step "Step 4" -Status "FOUND" -Detail "Scheduled task '$($taskName)' exists"
            $foundTasks++

            if (-not $WhatIf) {
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
                Write-LogMessage "  Removed scheduled task: '$($taskName)'" -Level INFO
                Add-Report -Step "Step 4" -Status "REMOVED" -Detail "Scheduled task '$($taskName)' removed"
            }
        }
    }
    if ($foundTasks -eq 0) {
        Write-LogMessage "  No legacy scheduled tasks found." -Level INFO
        Add-Report -Step "Step 4" -Status "CLEAN" -Detail "No legacy scheduled tasks"
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 5: Remove legacy firewall rules
    # ═══════════════════════════════════════════════════════════════════════════
    Write-LogMessage "--- Step 5: Firewall rules ---" -Level INFO

    $legacyFwRules = @(
        "ServerMonitorDashboard_Api_Inbound",
        "ServerMonitorDashboard_Api_Outbound",
        "ServerMonitorDashboard Inbound",
        "ServerMonitorDashboard Outbound"
    )

    $foundFw = 0
    foreach ($ruleName in $legacyFwRules) {
        $rule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        if ($rule) {
            Write-LogMessage "  Found firewall rule: '$($ruleName)'" -Level WARN
            Add-Report -Step "Step 5" -Status "FOUND" -Detail "Legacy firewall rule '$($ruleName)'"
            $foundFw++

            if (-not $WhatIf) {
                Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
                Write-LogMessage "  Removed firewall rule: '$($ruleName)'" -Level INFO
                Add-Report -Step "Step 5" -Status "REMOVED" -Detail "Firewall rule '$($ruleName)' removed"
            }
        }
    }
    if ($foundFw -eq 0) {
        Write-LogMessage "  No legacy firewall rules found." -Level INFO
        Add-Report -Step "Step 5" -Status "CLEAN" -Detail "No legacy firewall rules"
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 6: Remove legacy install folders
    # ═══════════════════════════════════════════════════════════════════════════
    Write-LogMessage "--- Step 6: Legacy install folders ---" -Level INFO

    if ($SkipFolderRemoval) {
        Write-LogMessage "  SkipFolderRemoval specified — skipping folder removal." -Level WARN
        Add-Report -Step "Step 6" -Status "SKIPPED" -Detail "Folder removal skipped by -SkipFolderRemoval"
    } else {
        $legacyFolders = @($legacyIisPath, $legacyPshApp)
        $foundFolders = 0

        foreach ($folder in $legacyFolders) {
            if (-not (Test-Path $folder)) {
                Write-LogMessage "  Not present: $($folder)" -Level INFO
                Add-Report -Step "Step 6" -Status "CLEAN" -Detail "Legacy folder not present: $($folder)"
                continue
            }

            $itemCount = (Get-ChildItem -Path $folder -Recurse -ErrorAction SilentlyContinue).Count
            Write-LogMessage "  Found legacy folder ($($itemCount) items): $($folder)" -Level WARN
            Add-Report -Step "Step 6" -Status "FOUND" -Detail "Legacy folder exists ($($itemCount) items): $($folder)"
            $foundFolders++

            if (-not $WhatIf) {
                # Kill any processes that may lock files in this folder
                $lockingProcs = @("ServerMonitorDashboard", "ServerMonitorDashboard.Tray", "ServerMonitorTrayIcon")
                foreach ($procName in $lockingProcs) {
                    Get-Process -Name $procName -ErrorAction SilentlyContinue |
                        ForEach-Object {
                            Write-LogMessage "  Stopping locking process: $($_.Name) (PID $($_.Id))" -Level WARN
                            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
                        }
                }
                Start-Sleep -Seconds 2

                Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
                if (Test-Path $folder) {
                    # Robocopy purge as fallback for locked files
                    Write-LogMessage "  First pass incomplete — using robocopy purge..." -Level WARN
                    $emptyDir = Join-Path $env:TEMP "EmptyDir_$(Get-Random)"
                    New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
                    robocopy $emptyDir $folder /MIR /NFL /NDL /NJH /NJS 2>&1 | Out-Null
                    Remove-Item -Path $emptyDir -Force -ErrorAction SilentlyContinue
                    Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
                }

                if (Test-Path $folder) {
                    Write-LogMessage "  WARNING: $($folder) could not be fully removed — files may still be locked." -Level WARN
                    Add-Report -Step "Step 6" -Status "WARN" -Detail "Could not fully remove: $($folder)"
                } else {
                    Write-LogMessage "  Removed: $($folder)" -Level INFO
                    Add-Report -Step "Step 6" -Status "REMOVED" -Detail "Removed: $($folder)"
                }
            }
        }

        if ($foundFolders -eq 0) {
            Write-LogMessage "  No legacy install folders found." -Level INFO
        }
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # SUMMARY REPORT
    # ═══════════════════════════════════════════════════════════════════════════
    $found   = @($report | Where-Object { $_.Status -eq "FOUND"   })
    $removed = @($report | Where-Object { $_.Status -eq "REMOVED" })
    $warned  = @($report | Where-Object { $_.Status -eq "WARN"    })
    $clean   = @($report | Where-Object { $_.Status -eq "CLEAN"   })

    Write-LogMessage "" -Level INFO
    Write-LogMessage "=== Summary for $($env:COMPUTERNAME) ===" -Level INFO
    Write-LogMessage "  Items found   : $($found.Count + $removed.Count)" -Level INFO
    Write-LogMessage "  Items removed : $($removed.Count)" -Level INFO
    Write-LogMessage "  Warnings      : $($warned.Count)" -Level INFO
    Write-LogMessage "  Already clean : $($clean.Count)" -Level INFO

    if ($WhatIf) {
        Write-LogMessage "" -Level INFO
        Write-LogMessage "WhatIf report — items that WOULD be removed:" -Level WARN
        $found | ForEach-Object {
            Write-LogMessage "  [$($_.Step)] $($_.Detail)" -Level WARN
        }
        if ($found.Count -eq 0) {
            Write-LogMessage "  Nothing to remove — server already clean." -Level INFO
        }
    }

    if ($warned.Count -gt 0) {
        Write-LogMessage "" -Level INFO
        Write-LogMessage "Warnings:" -Level WARN
        $warned | ForEach-Object {
            Write-LogMessage "  [$($_.Step)] $($_.Detail)" -Level WARN
        }
    }

    Write-LogMessage "" -Level INFO
    if (-not $WhatIf) {
        Write-LogMessage "Legacy service removal complete." -Level INFO
        Write-LogMessage "Next step: deploy IIS version with:" -Level INFO
        Write-LogMessage "  IIS-DeployApp.ps1 -SiteName ServerMonitorDashboard" -Level INFO
    }

    Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_FAILED
    exit 1
}
finally {
    Reset-OverrideAppDataFolder
}
