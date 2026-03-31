#!/usr/bin/env pwsh
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Removes ALL legacy ServerMonitorDashboard installation artifacts from the server
    and repairs the correct IIS-DeployApp virtual-app deployment.

.DESCRIPTION
    The deprecated ServerMonitorDashboard.ps1 (IIS mode) created:
      - Standalone IIS SITE "ServerMonitorDashboard" on port 8998
            (conflicts with virtual app; causes HTTP 500.35)
      - App pool "ServerMonitorDashboard" shared with the virtual app
      - Physical files at $env:OptPath\IIS\ServerMonitorDashboard
      - PshApp at $env:OptPath\DedgePshApps\ServerMonitorDashboard
      - Windows Service "ServerMonitorDashboard" (Service mode)
      - Scheduled tasks: ServerMonitorDashboard, Install-ServerMonitorDashboard
      - Firewall rules: ServerMonitorDashboard_Api_Inbound/Outbound
      - Registry HKLM\Run and current HKCU\Run entries (service-mode autostart)

    IIS-DeployApp (Deploy-IISSite) creates the correct deployment:
      - Virtual app "Default Web Site/ServerMonitorDashboard"
      - App pool "ServerMonitorDashboard" (dedicated)
      - Physical files at $env:OptPath\DedgeWinApps\ServerMonitorDashboard
      - Firewall rules for ports 8998, 8999, 8997

    When both coexist, IIS throws HTTP 500.35 (InProcess shared app pool).

    This script removes all legacy artifacts, repairs the correct virtual-app
    deployment, then runs Test-IISSite for final verification.

.PARAMETER WhatIf
    Diagnostic mode: checks everything, makes no changes, and prints a clear
    summary report to the console explaining why ServerMonitorDashboard is broken.
    Step 0 (forensic investigation) always runs in both modes — it searches the
    Windows Event Log, registry Services/Run keys, scheduled tasks, and recently
    modified installer scripts to determine HOW the legacy install was triggered.

.EXAMPLE
    .\Fix-ServerMonitorDashboard.ps1 -WhatIf

.EXAMPLE
    .\Fix-ServerMonitorDashboard.ps1
#>
param(
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

Import-Module GlobalFunctions -Force
Import-Module IIS-Handler -Force

Set-OverrideAppDataFolder -Path $(Join-Path $env:OptPath "data" "IIS-DeployApp")
Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_STARTED

$appcmd = "$($env:SystemRoot)\System32\inetsrv\appcmd.exe"
$siteName        = "ServerMonitorDashboard"
$appPoolName     = "ServerMonitorDashboard"
$parentSite      = "Default Web Site"
$virtualAppId    = "$parentSite/$siteName"
$correctPath     = Join-Path $env:OptPath "DedgeWinApps\$siteName"
$legacyIisPath   = Join-Path $env:OptPath "IIS\$siteName"
$legacyPshApp    = Join-Path $env:OptPath "DedgePshApps\$siteName"
$logsDir         = Join-Path $correctPath "logs"

# Diagnostic findings collected when -WhatIf is used
$findings = [System.Collections.Generic.List[PSCustomObject]]::new()
function Add-Finding {
    param([string]$Step, [string]$Status, [string]$Detail)
    $findings.Add([PSCustomObject]@{ Step = $Step; Status = $Status; Detail = $Detail })
}

if ($WhatIf) {
    Write-LogMessage "=== WHATIF MODE — no changes will be made ===" -Level WARN
}

try {
    Write-LogMessage "=== Removing legacy ServerMonitorDashboard installation ===" -Level INFO
    Write-LogMessage "  Server:       $($env:COMPUTERNAME)" -Level INFO
    Write-LogMessage "  Correct path: $correctPath" -Level INFO
    Write-LogMessage "  Legacy paths: $legacyIisPath | $legacyPshApp" -Level INFO

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 0: Forensic investigation — find AND fix HOW the legacy install was triggered
    #   Always runs. In -WhatIf mode: read-only reporting only.
    #   In normal mode: auto-fixes the root cause where possible.
    #   Searches (and fixes):
    #     - [0a] Windows Event Log for service-install events (7045 / 4697)  [report only]
    #     - [0b] Registry Services key — stops + force-removes key + disables launcher svc
    #     - [0c] Run/RunOnce values referencing IIS/SMD — removes the registry values
    #     - [0d] Scheduled tasks referencing \IIS\ or SMD installer — disables + unregisters
    #     - [0e] Recently modified installer scripts in known SMD locations   [report only]
    #     - [0f] File system scan: *.ps1/psm1/bat/cs under $OptPath for \IIS\ string [report only]
    # ═══════════════════════════════════════════════════════════════════════════
    Write-LogMessage "--- Step 0: Forensic investigation (reinstall origin) ---" -Level INFO

    $forensicClues = [System.Collections.Generic.List[string]]::new()

    # ── 0a: Event Log — service installation events (last 4 hours) ─────────────
    Write-LogMessage "  [0a] Checking Event Log for service install events (last 4 hours)..." -Level INFO
    $since = (Get-Date).AddHours(-4)

    # Event ID 7045 = new service installed (System log)
    $svcInstallEvents = Get-WinEvent -FilterHashtable @{
        LogName   = 'System'
        Id        = 7045
        StartTime = $since
    } -ErrorAction SilentlyContinue

    foreach ($evt in $svcInstallEvents) {
        $msg      = $evt.Message
        $msgClean = $msg -replace "`r`n", ' ' -replace "`n", ' '
        Write-LogMessage "  [EventLog 7045] $($evt.TimeCreated) — $msg" -Level WARN
        $forensicClues.Add("EventLog 7045 at $($evt.TimeCreated): $msgClean")
        Add-Finding -Step "Step 0a" -Status "ISSUE" -Detail "Service install event at $($evt.TimeCreated): $msgClean"
    }
    if (-not $svcInstallEvents) {
        Write-LogMessage "  [0a] No service install events (7045) in last 4 hours" -Level INFO
        Add-Finding -Step "Step 0a" -Status "OK" -Detail "No service install events (7045) in last 4 hours"
    }

    # Event ID 4697 = service installed (Security log) — may need SeAuditPrivilege
    $secEvents = Get-WinEvent -FilterHashtable @{
        LogName   = 'Security'
        Id        = 4697
        StartTime = $since
    } -ErrorAction SilentlyContinue

    foreach ($evt in $secEvents) {
        $msg = $evt.Message
        if ($msg -match 'ServerMonitor|IIS\\') {
            $msgClean = $msg -replace "`r`n", ' ' -replace "`n", ' '
            Write-LogMessage "  [EventLog 4697] $($evt.TimeCreated) — $msg" -Level WARN
            $forensicClues.Add("EventLog 4697 at $($evt.TimeCreated): $msgClean")
            Add-Finding -Step "Step 0a" -Status "ISSUE" -Detail "Security service install event at $($evt.TimeCreated): $msgClean"
        }
    }

    # Application log — look for SMD or IIS mentions in last 4 hours
    $appEvents = Get-WinEvent -FilterHashtable @{
        LogName   = 'Application'
        StartTime = $since
    } -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match 'ServerMonitor|\\IIS\\' } |
        Select-Object -First 10

    foreach ($evt in $appEvents) {
        $rawMsg  = $evt.Message -replace "`r`n", ' ' -replace "`n", ' '
        $snippet = $rawMsg.Substring(0, [Math]::Min(200, $rawMsg.Length))
        Write-LogMessage "  [AppLog $($evt.Id)] $($evt.TimeCreated) $($evt.ProviderName): $snippet" -Level WARN
        $forensicClues.Add("AppLog $($evt.Id) at $($evt.TimeCreated) from $($evt.ProviderName): $snippet")
        Add-Finding -Step "Step 0a" -Status "ISSUE" -Detail "App event mentioning SMD/IIS at $($evt.TimeCreated) ($($evt.ProviderName)): $snippet"
    }

    # ── 0b: Registry Services — find ImagePath entries with \IIS\ or SMD paths ──
    Write-LogMessage "  [0b] Scanning HKLM Services for IIS/SMD ImagePath entries..." -Level INFO
    $servicesRoot = "HKLM:\SYSTEM\CurrentControlSet\Services"
    $smdServiceKey = Join-Path $servicesRoot $siteName
    if (Test-Path $smdServiceKey) {
        $svcReg  = Get-ItemProperty -Path $smdServiceKey -ErrorAction SilentlyContinue
        $imgPath = $svcReg.ImagePath
        Write-LogMessage "  [0b] Service registry key EXISTS: $smdServiceKey" -Level WARN
        Write-LogMessage "       ImagePath : $imgPath" -Level WARN
        Write-LogMessage "       Start     : $($svcReg.Start)  (2=Auto,3=Manual,4=Disabled)" -Level WARN
        Write-LogMessage "       ObjectName: $($svcReg.ObjectName)" -Level WARN
        $forensicClues.Add("Service registry key exists: ImagePath=$imgPath Start=$($svcReg.Start)")
        Add-Finding -Step "Step 0b" -Status "ISSUE" -Detail "Service registry key present — ImagePath: $imgPath | Start: $($svcReg.Start) | ObjectName: $($svcReg.ObjectName)"

        # Check if the ImagePath script/exe contains \IIS\ hints
        if ($imgPath -match '\\IIS\\') {
            Write-LogMessage "       *** ImagePath references \IIS\ path — legacy IIS-mode installer ***" -Level WARN
            $forensicClues.Add("ImagePath references \\IIS\\ path — this is the legacy IIS-mode install")
            Add-Finding -Step "Step 0b" -Status "ISSUE" -Detail "ImagePath contains \\IIS\\ path — confirms legacy IIS-mode service was reinstalled"
        }

        # If ImagePath is a script, read it and grep for \IIS\
        $scriptPath = ($imgPath -replace '^.*pwsh[^"]*"([^"]+)".*$','$1' -replace "^.*-File\s+'?([^\s']+)'?.*$",'$1').Trim()
        if ($scriptPath -ne $imgPath -and (Test-Path $scriptPath)) {
            Write-LogMessage "       Reading referenced script: $scriptPath" -Level INFO
            $scriptContent = Get-Content $scriptPath -Raw -ErrorAction SilentlyContinue
            if ($scriptContent -match '\\IIS\\') {
                Write-LogMessage "       *** Script $scriptPath contains \\IIS\\ path ***" -Level WARN
                $forensicClues.Add("Script $scriptPath contains \\IIS\\ references")
                Add-Finding -Step "Step 0b" -Status "ISSUE" -Detail "Service script '$scriptPath' references \\IIS\\ paths — confirms legacy installer"
            }
        }

        # FIX: stop service + force-remove the registry key so it cannot auto-restart on reboot
        if (-not $WhatIf) {
            Write-LogMessage "  [0b] FIX: Stopping service and force-removing registry key '$smdServiceKey'..." -Level WARN
            $svcObj = Get-Service -Name $siteName -ErrorAction SilentlyContinue
            if ($svcObj -and $svcObj.Status -ne 'Stopped') {
                Stop-Service -Name $siteName -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
            }
            # sc.exe delete marks for deletion; force-remove the registry key immediately
            & sc.exe delete $siteName 2>&1 | Out-Null
            if (Test-Path $smdServiceKey) {
                Remove-Item -Path $smdServiceKey -Recurse -Force -ErrorAction SilentlyContinue
                if (Test-Path $smdServiceKey) {
                    Write-LogMessage "  [0b] WARNING: Registry key still present after removal attempt — may need reboot" -Level WARN
                }
                else {
                    Write-LogMessage "  [0b] Service registry key removed" -Level INFO
                }
            }
        }
    }
    else {
        Write-LogMessage "  [0b] No service registry key for '$siteName' (OK)" -Level INFO
        Add-Finding -Step "Step 0b" -Status "OK" -Detail "No service registry key for '$siteName'"
    }

    # Scan ALL services for ImagePath containing \IIS\ (may reveal a launcher)
    $allServiceKeys = Get-ChildItem $servicesRoot -ErrorAction SilentlyContinue
    foreach ($key in $allServiceKeys) {
        try {
            $props = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
            $img   = $props.ImagePath
            if ($img -match '\\IIS\\' -or $img -match 'ServerMonitorDashboard') {
                if ($key.PSChildName -ne $siteName) {
                    Write-LogMessage "  [0b] Service '$($key.PSChildName)' has IIS/SMD ImagePath: $img" -Level WARN
                    $forensicClues.Add("Other service '$($key.PSChildName)' references IIS/SMD: $img")
                    Add-Finding -Step "Step 0b" -Status "ISSUE" -Detail "Unrelated service '$($key.PSChildName)' references IIS or SMD in ImagePath: $img"
                    # FIX: stop and disable this launcher service so it cannot re-trigger the install
                    if (-not $WhatIf) {
                        Write-LogMessage "  [0b] FIX: Disabling launcher service '$($key.PSChildName)'..." -Level WARN
                        $lSvc = Get-Service -Name $key.PSChildName -ErrorAction SilentlyContinue
                        if ($lSvc -and $lSvc.Status -ne 'Stopped') {
                            Stop-Service -Name $key.PSChildName -Force -ErrorAction SilentlyContinue
                        }
                        Set-Service -Name $key.PSChildName -StartupType Disabled -ErrorAction SilentlyContinue
                        Write-LogMessage "  [0b] Service '$($key.PSChildName)' stopped and disabled (StartupType=Disabled)" -Level INFO
                    }
                }
            }
        } catch { }
    }

    # ── 0c: Run / RunOnce keys — read scripts and grep for \IIS\ ───────────────
    Write-LogMessage "  [0c] Scanning Run/RunOnce registry values for \IIS\ references..." -Level INFO
    $runPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
    )
    $foundRunIssues = $false
    foreach ($regPath in $runPaths) {
        if (-not (Test-Path $regPath)) { continue }
        $props = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        foreach ($name in ($props.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' -and $_.Name -notlike 'PS*' })) {
            $val        = $name.Value
            $entryName  = $name.Name
            $needsFix   = $false

            if ($val -match '\\IIS\\' -or $val -match 'ServerMonitorDashboard') {
                Write-LogMessage "  [0c] Run key match — $regPath '$entryName' = $val" -Level WARN
                $forensicClues.Add("Run key: $regPath '$entryName' = $val")
                Add-Finding -Step "Step 0c" -Status "ISSUE" -Detail "Run key '$entryName' at $regPath references IIS/SMD: $val"
                $foundRunIssues = $true
                $needsFix = $true
            }

            # If value references a script, read it too
            $scriptRef = ($val -replace '^.*-File\s+"?([^"]+\.ps1)"?.*$','$1').Trim()
            if ($scriptRef -ne $val -and (Test-Path $scriptRef -ErrorAction SilentlyContinue)) {
                $sc = Get-Content $scriptRef -Raw -ErrorAction SilentlyContinue
                if ($sc -match '\\IIS\\' -or $sc -match 'ServerMonitorDashboard') {
                    Write-LogMessage "  [0c] Script '$scriptRef' (from Run key '$entryName') contains IIS/SMD reference" -Level WARN
                    $forensicClues.Add("Script '$scriptRef' from Run key contains \\IIS\\ or SMD references")
                    Add-Finding -Step "Step 0c" -Status "ISSUE" -Detail "Script '$scriptRef' referenced from Run key '$entryName' contains \\IIS\\ or ServerMonitorDashboard paths"
                    $foundRunIssues = $true
                    $needsFix = $true
                }
            }

            # FIX: remove the offending Run/RunOnce value
            if ($needsFix -and -not $WhatIf) {
                Write-LogMessage "  [0c] FIX: Removing Run key '$entryName' from $regPath" -Level WARN
                Remove-ItemProperty -Path $regPath -Name $entryName -ErrorAction SilentlyContinue
                $verify = Get-ItemProperty -Path $regPath -Name $entryName -ErrorAction SilentlyContinue
                if ($null -eq $verify) {
                    Write-LogMessage "  [0c] Run key '$entryName' removed" -Level INFO
                }
                else {
                    Write-LogMessage "  [0c] WARNING: Could not remove Run key '$entryName'" -Level WARN
                }
            }
        }
    }
    if (-not $foundRunIssues) {
        Write-LogMessage "  [0c] No Run/RunOnce entries reference IIS or SMD paths (OK)" -Level INFO
        Add-Finding -Step "Step 0c" -Status "OK" -Detail "No Run/RunOnce entries reference IIS or SMD paths"
    }

    # ── 0d: Scheduled tasks — find any that reference \IIS\ or SMD installer ───
    Write-LogMessage "  [0d] Scanning scheduled tasks for \IIS\ or installer references..." -Level INFO
    $foundTaskIssues = $false
    try {
        $allTasks = Get-ScheduledTask -ErrorAction SilentlyContinue
        foreach ($task in $allTasks) {
            $actions   = $task.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }
            $actionStr = $actions -join ' '
            if ($actionStr -match '\\IIS\\' -or $actionStr -match 'ServerMonitorDashboard' -or $actionStr -match 'Install-ServerMonitor') {
                $taskInfo  = Get-ScheduledTaskInfo -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue
                $lastRun   = $taskInfo.LastRunTime
                $taskState = $task.State   # Ready, Disabled, Running
                Write-LogMessage "  [0d] Task '$($task.TaskPath)$($task.TaskName)' references IIS/SMD" -Level WARN
                Write-LogMessage "       State   : $taskState" -Level WARN
                Write-LogMessage "       LastRun : $lastRun" -Level WARN
                Write-LogMessage "       Actions : $actionStr" -Level WARN
                $forensicClues.Add("ScheduledTask '$($task.TaskPath)$($task.TaskName)' State=$taskState LastRun=$lastRun Actions=$actionStr")
                Add-Finding -Step "Step 0d" -Status "ISSUE" -Detail "Scheduled task '$($task.TaskPath)$($task.TaskName)' references IIS/SMD (State: $taskState, LastRun: $lastRun): $actionStr"
                $foundTaskIssues = $true

                # FIX: disable and unregister the task so it cannot re-trigger the install
                if (-not $WhatIf) {
                    Write-LogMessage "  [0d] FIX: Disabling and unregistering task '$($task.TaskName)'..." -Level WARN
                    # Disable first to stop any running instance
                    Disable-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue | Out-Null
                    Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false -ErrorAction SilentlyContinue
                    $stillExists = Get-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue
                    if ($null -eq $stillExists) {
                        Write-LogMessage "  [0d] Task '$($task.TaskName)' removed" -Level INFO
                    }
                    else {
                        Write-LogMessage "  [0d] WARNING: Task '$($task.TaskName)' still exists after removal attempt — disabled at minimum" -Level WARN
                    }
                }
            }
        }
    } catch { }
    if (-not $foundTaskIssues) {
        Write-LogMessage "  [0d] No scheduled tasks reference IIS or SMD installer paths (OK)" -Level INFO
        Add-Finding -Step "Step 0d" -Status "OK" -Detail "No scheduled tasks reference IIS or SMD installer paths"
    }

    # ── 0e: Recently modified files in SMD installer locations ─────────────────
    Write-LogMessage "  [0e] Checking for recently modified installer scripts (last 4 hours)..." -Level INFO
    $installerLocations = @(
        $legacyPshApp,
        $legacyIisPath,
        (Join-Path $env:OptPath "DedgePshApps\Inst-Psh"),
        (Join-Path $env:OptPath "DedgePshApps\IIS-DeployApp")
    )
    $foundRecentFiles = $false
    foreach ($loc in $installerLocations) {
        if (-not (Test-Path $loc)) { continue }
        $recentFiles = Get-ChildItem -Path $loc -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt $since -and -not $_.PSIsContainer }
        foreach ($f in $recentFiles) {
            Write-LogMessage "  [0e] Recently modified: $($f.FullName) at $($f.LastWriteTime)" -Level WARN
            $forensicClues.Add("Recently modified file: $($f.FullName) at $($f.LastWriteTime)")
            Add-Finding -Step "Step 0e" -Status "ISSUE" -Detail "File modified in last 4 hours: $($f.FullName) at $($f.LastWriteTime)"
            $foundRecentFiles = $true

            # Grep for \IIS\ inside it
            $content = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
            if ($content -match '\\IIS\\') {
                Write-LogMessage "       *** Contains \\IIS\\ path references ***" -Level WARN
                $forensicClues.Add("File $($f.FullName) contains \\IIS\\ references")
                Add-Finding -Step "Step 0e" -Status "ISSUE" -Detail "Recently modified file '$($f.FullName)' contains \\IIS\\ path references — likely the reinstall trigger"
            }
        }
    }
    if (-not $foundRecentFiles) {
        Write-LogMessage "  [0e] No installer scripts modified in last 4 hours (OK)" -Level INFO
        Add-Finding -Step "Step 0e" -Status "OK" -Detail "No installer scripts modified in last 4 hours"
    }

    # ── 0f: File system scan — search *.ps1, *.psm1, *.bat, *.cs for \IIS\ ────
    #   Covers all script/code files on the server that could act as reinstall triggers.
    #   Searches $env:OptPath recursively (covers DedgePshApps, IIS, DedgeWinApps, etc.)
    #   and C:\opt if it differs from $env:OptPath.
    Write-LogMessage "  [0f] Scanning local script/code files for \IIS\ references..." -Level INFO
    $scanRoots = [System.Collections.Generic.List[string]]::new()
    if ($env:OptPath -and (Test-Path $env:OptPath)) {
        $scanRoots.Add($env:OptPath)
    }
    $cOpt = 'C:\opt'
    if ((Test-Path $cOpt) -and ($cOpt -ne $env:OptPath)) {
        $scanRoots.Add($cOpt)
    }

    $fileExtensions = @('*.ps1', '*.psm1', '*.bat', '*.cs')
    $iisFileMatches = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($root in $scanRoots) {
        Write-LogMessage "  [0f] Scanning: $root" -Level INFO
        foreach ($ext in $fileExtensions) {
            $files = Get-ChildItem -Path $root -Filter $ext -Recurse -ErrorAction SilentlyContinue -File
            foreach ($f in $files) {
                try {
                    # Read line by line so we can report exact line numbers
                    $lineNum = 0
                    foreach ($line in [System.IO.File]::ReadLines($f.FullName)) {
                        $lineNum++
                        if ($line -match '\\IIS\\') {
                            $iisFileMatches.Add([PSCustomObject]@{
                                File    = $f.FullName
                                Line    = $lineNum
                                Content = $line.Trim()
                                Modified = $f.LastWriteTime
                            })
                        }
                    }
                } catch { }
            }
        }
    }

    if ($iisFileMatches.Count -eq 0) {
        Write-LogMessage "  [0f] No script/code files reference \IIS\ paths (OK)" -Level INFO
        Add-Finding -Step "Step 0f" -Status "OK" -Detail "No *.ps1/psm1/bat/cs files on this server reference \IIS\ paths"
    }
    else {
        # Group by file and report
        $byFile = $iisFileMatches | Group-Object File
        Write-LogMessage "  [0f] Found \IIS\ references in $($byFile.Count) file(s), $($iisFileMatches.Count) line(s) total:" -Level WARN
        foreach ($grp in $byFile) {
            $fileModified = $grp.Group[0].Modified
            Write-LogMessage "  [0f] $($grp.Name)  (modified: $fileModified, $($grp.Count) match(es))" -Level WARN
            foreach ($m in $grp.Group) {
                Write-LogMessage "       L$($m.Line): $($m.Content)" -Level WARN
            }
            $lineList  = ($grp.Group | ForEach-Object { "L$($_.Line): $($_.Content)" }) -join ' | '
            $isSuspect = $fileModified -gt $since
            $status    = if ($isSuspect) { 'ISSUE' } else { 'INFO' }
            $tag       = if ($isSuspect) { ' [RECENTLY MODIFIED — suspect]' } else { '' }
            $forensicClues.Add("File with \IIS\ reference$tag : $($grp.Name) (modified $fileModified)")
            Add-Finding -Step "Step 0f" -Status $status -Detail "\IIS\ found in '$($grp.Name)'$tag — $($grp.Count) match(es): $lineList"
        }
    }

    # ── 0g: Print forensic summary ─────────────────────────────────────────────
    if ($forensicClues.Count -gt 0) {
        Write-LogMessage "--- Forensic summary: $($forensicClues.Count) clue(s) found ---" -Level WARN
        $i = 1
        foreach ($clue in $forensicClues) {
            Write-LogMessage "  [$i] $clue" -Level WARN
            $i++
        }
    }
    else {
        Write-LogMessage "--- Forensic summary: No reinstall triggers found in the last 4 hours ---" -Level INFO
        Write-LogMessage "    Consider checking: Windows Update, SCCM/Intune deployments, or manual RDP login activity" -Level INFO
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 1: Remove standalone IIS SITE "ServerMonitorDashboard"
    #         The virtual app under "Default Web Site" is NOT touched.
    # ═══════════════════════════════════════════════════════════════════════════
    Write-LogMessage "--- Step 1: Remove standalone IIS site ---" -Level INFO

    $siteCheck = & $appcmd list site /name:"$siteName" 2>&1 | Out-String
    if ($siteCheck -match 'SITE "') {
        Write-LogMessage "Found standalone site '$siteName' -- $(if ($WhatIf) {'WOULD remove'} else {'removing'})" -Level WARN
        Add-Finding -Step "Step 1" -Status "ISSUE" -Detail "Standalone IIS site '$siteName' exists — conflicts with virtual app (causes HTTP 500.35)"
        if (-not $WhatIf) {
            & $appcmd stop site /site.name:"$siteName" 2>&1 | Out-Null
            $siteApps = & $appcmd list app /site.name:"$siteName" 2>&1 | Out-String
            foreach ($line in ($siteApps -split "`n")) {
                if ($line.Trim() -match '^APP "([^"]+)"') {
                    $appId = $matches[1]
                    Write-LogMessage "  Removing app: $appId" -Level INFO
                    & $appcmd delete app /app.name:"$appId" 2>&1 | Out-Null
                }
            }
            $delSite = & $appcmd delete site /site.name:"$siteName" 2>&1 | Out-String
            if ($delSite -match "deleted") {
                Write-LogMessage "Standalone site '$siteName' deleted" -Level INFO
            }
            else {
                Write-LogMessage "Site delete result: $($delSite.Trim())" -Level WARN
            }
        }
    }
    else {
        Write-LogMessage "No standalone site '$siteName' found (OK)" -Level INFO
        Add-Finding -Step "Step 1" -Status "OK" -Detail "No standalone IIS site '$siteName'"
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 2: Remove Windows Service "ServerMonitorDashboard" (Service mode)
    # ═══════════════════════════════════════════════════════════════════════════
    Write-LogMessage "--- Step 2: Remove Windows Service ---" -Level INFO

    $svc = Get-Service -Name $siteName -ErrorAction SilentlyContinue
    if ($svc) {
        Write-LogMessage "Found Windows Service '$siteName' (Status: $($svc.Status)) -- $(if ($WhatIf) {'WOULD remove'} else {'removing'})" -Level WARN
        Add-Finding -Step "Step 2" -Status "ISSUE" -Detail "Windows Service '$siteName' exists (Status: $($svc.Status)) — legacy service-mode install; conflicts with IIS virtual app"
        if (-not $WhatIf) {
            if ($svc.Status -ne 'Stopped') {
                Stop-Service -Name $siteName -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
            }
            $scResult = & sc.exe delete $siteName 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-LogMessage "Windows Service '$siteName' deleted" -Level INFO
            }
            else {
                Write-LogMessage "Service delete result: $scResult" -Level WARN
            }
        }
    }
    else {
        Write-LogMessage "No Windows Service '$siteName' found (OK)" -Level INFO
        Add-Finding -Step "Step 2" -Status "OK" -Detail "No legacy Windows Service '$siteName'"
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 3: Remove deprecated scheduled tasks
    # ═══════════════════════════════════════════════════════════════════════════
    Write-LogMessage "--- Step 3: Remove deprecated scheduled tasks ---" -Level INFO

    $deprecatedTasks = @(
        "ServerMonitorDashboard",
        "Install-ServerMonitorDashboard",
        "DevTools\Install-ServerMonitorDashboard"
    )
    $removedTasks = 0
    foreach ($taskName in $deprecatedTasks) {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($task) {
            Write-LogMessage "  $(if ($WhatIf) {'WOULD remove'} else {'Removing'}) scheduled task: $taskName" -Level WARN
            Add-Finding -Step "Step 3" -Status "ISSUE" -Detail "Deprecated scheduled task exists: '$taskName'"
            if (-not $WhatIf) {
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
                Write-LogMessage "  Removed scheduled task: $taskName" -Level INFO
            }
            $removedTasks++
        }
    }
    if ($removedTasks -eq 0) {
        Write-LogMessage "No deprecated scheduled tasks found (OK)" -Level INFO
        Add-Finding -Step "Step 3" -Status "OK" -Detail "No deprecated scheduled tasks"
    }
    else {
        Write-LogMessage "$(if ($WhatIf) {'Found'} else {'Removed'}) $removedTasks deprecated scheduled task(s)" -Level INFO
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 4: Remove legacy firewall rules (created by old ServerMonitorDashboard.ps1)
    #         IIS-DeployApp creates its own rules with correct naming.
    # ═══════════════════════════════════════════════════════════════════════════
    Write-LogMessage "--- Step 4: Remove legacy firewall rules ---" -Level INFO

    $legacyFwRules = @(
        "ServerMonitorDashboard_Api_Inbound",
        "ServerMonitorDashboard_Api_Outbound"
    )
    $removedFw = 0
    foreach ($ruleName in $legacyFwRules) {
        $rule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        if ($rule) {
            Write-LogMessage "  $(if ($WhatIf) {'WOULD remove'} else {'Removing'}) firewall rule: $ruleName" -Level WARN
            Add-Finding -Step "Step 4" -Status "ISSUE" -Detail "Legacy firewall rule exists: '$ruleName'"
            if (-not $WhatIf) {
                Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
                Write-LogMessage "  Removed firewall rule: $ruleName" -Level INFO
            }
            $removedFw++
        }
    }
    if ($removedFw -eq 0) {
        Write-LogMessage "No legacy firewall rules found (OK)" -Level INFO
        Add-Finding -Step "Step 4" -Status "OK" -Detail "No legacy firewall rules"
    }
    else {
        Write-LogMessage "$(if ($WhatIf) {'Found'} else {'Removed'}) $removedFw legacy firewall rule(s)" -Level INFO
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 5: Kill locking processes, then permanently remove legacy folders
    #   - $env:OptPath\IIS\ServerMonitorDashboard  (IIS mode install target)
    #   - $env:OptPath\DedgePshApps\ServerMonitorDashboard  (installed PshApp copy)
    #   Process kill runs BEFORE deletion so locked DLLs are released first.
    # ═══════════════════════════════════════════════════════════════════════════
    Write-LogMessage "--- Step 5: Remove legacy folders ---" -Level INFO

    # Process names that may lock files in these folders
    $processesToKill = @(
        "ServerMonitorDashboard",
        "ServerMonitorDashboard.Tray",
        "ServerMonitorTrayIcon"
    )

    Write-LogMessage "  Checking for processes that may lock legacy files..." -Level INFO
    foreach ($procName in $processesToKill) {
        $procs = Get-Process -Name $procName -ErrorAction SilentlyContinue
        foreach ($proc in $procs) {
            Write-LogMessage "  $(if ($WhatIf) {'WOULD kill'} else {'Killing'}) $($proc.Name) PID $($proc.Id)" -Level WARN
            Add-Finding -Step "Step 5" -Status "ISSUE" -Detail "Locking process running: $($proc.Name) (PID $($proc.Id))"
            if (-not $WhatIf) {
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            }
        }
    }
    if (-not $WhatIf) {
        if ($processesToKill | ForEach-Object { Get-Process -Name $_ -ErrorAction SilentlyContinue } | Select-Object -First 1) {
            Start-Sleep -Seconds 3
        }
    }

    $legacyFolders = @($legacyIisPath, $legacyPshApp)
    foreach ($folder in $legacyFolders) {
        if (-not (Test-Path $folder)) {
            Write-LogMessage "  Not found (already clean): $folder" -Level INFO
            Add-Finding -Step "Step 5" -Status "OK" -Detail "Legacy folder not present: $folder"
            continue
        }

        Write-LogMessage "  $(if ($WhatIf) {'WOULD remove'} else {'Removing'}): $folder" -Level WARN
        $itemCount = (Get-ChildItem -Path $folder -Recurse -ErrorAction SilentlyContinue).Count
        Add-Finding -Step "Step 5" -Status "ISSUE" -Detail "Legacy folder exists ($itemCount items): $folder"

        if (-not $WhatIf) {
            Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path $folder) {
                Write-LogMessage "  First pass incomplete — using robocopy purge to force removal..." -Level WARN
                $emptyDir = Join-Path $env:TEMP "EmptyDirForRobocopy_$(Get-Random)"
                New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
                robocopy $emptyDir $folder /MIR /NFL /NDL /NJH /NJS 2>&1 | Out-Null
                Remove-Item -Path $emptyDir -Force -ErrorAction SilentlyContinue
                Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path $folder) {
                Write-LogMessage "  WARNING: $folder could not be fully removed — files may still be locked" -Level WARN
                Get-ChildItem -Path $folder -Recurse -ErrorAction SilentlyContinue |
                    ForEach-Object { Write-LogMessage "    Remaining: $($_.FullName)" -Level WARN }
            }
            else {
                Write-LogMessage "  Removed: $folder" -Level INFO
            }
        }
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 6: Repair the correct virtual-app deployment
    #   - Ensure app pool is running and exclusive to the virtual app
    #   - Create logs directory if missing (required for stdout logging)
    #   - Fix permissions for IIS AppPool\ServerMonitorDashboard
    # ═══════════════════════════════════════════════════════════════════════════
    Write-LogMessage "--- Step 6: Repair virtual-app deployment ---" -Level INFO

    $vappCheck = & $appcmd list app /app.name:"$virtualAppId" 2>&1 | Out-String
    if ($vappCheck -notmatch 'APP "') {
        Write-LogMessage "Virtual app '$virtualAppId' not found -- run: .\IIS-DeployApp.ps1 -SiteName $siteName" -Level ERROR
        Add-Finding -Step "Step 6" -Status "ISSUE" -Detail "Virtual app '$virtualAppId' is MISSING — need to run IIS-DeployApp.ps1 -SiteName $siteName"
    }
    else {
        Write-LogMessage "Virtual app '$virtualAppId' exists" -Level INFO
        Add-Finding -Step "Step 6" -Status "OK" -Detail "Virtual app '$virtualAppId' is present"

        # Verify pool exclusivity (no other apps should reference it now)
        $allApps = & $appcmd list app 2>&1 | Out-String
        $poolUsers = @($allApps -split "`n" | Where-Object { $_ -match "applicationPool:$appPoolName" })
        if ($poolUsers.Count -gt 1) {
            Write-LogMessage "App pool '$appPoolName' still shared by $($poolUsers.Count) apps -- check manually" -Level WARN
            $poolUsers | ForEach-Object { Write-LogMessage "  $_" -Level WARN }
            Add-Finding -Step "Step 6" -Status "ISSUE" -Detail "App pool '$appPoolName' is shared by $($poolUsers.Count) apps (should be exclusive): $($poolUsers -join ' | ')"
        }
        else {
            Write-LogMessage "App pool '$appPoolName' is exclusive to '$virtualAppId' (correct)" -Level INFO
            Add-Finding -Step "Step 6" -Status "OK" -Detail "App pool '$appPoolName' is exclusive to virtual app"
        }

        # Check app pool state
        $poolCheck = & $appcmd list apppool /apppool.name:"$appPoolName" 2>&1 | Out-String
        if ($poolCheck -match 'APPPOOL "') {
            $poolState = if ($poolCheck -match 'state:(\w+)') { $matches[1] } else { 'Unknown' }
            Write-LogMessage "App pool '$appPoolName' state: $poolState" -Level INFO
            if ($poolState -notin @('Started', 'Unknown')) {
                Add-Finding -Step "Step 6" -Status "ISSUE" -Detail "App pool '$appPoolName' is in state '$poolState' — not running"
            }
            if (-not $WhatIf) {
                Write-LogMessage "Recycling app pool to clear stale crash state..." -Level INFO
                & $appcmd stop apppool "$appPoolName" 2>&1 | Out-Null
                Start-Sleep -Seconds 3
                & $appcmd start apppool "$appPoolName" 2>&1 | Out-Null
                Write-LogMessage "App pool '$appPoolName' recycled" -Level INFO
            }
        }

        # Check logs directory
        if (-not (Test-Path $logsDir)) {
            Write-LogMessage "$(if ($WhatIf) {'WOULD create'} else {'Creating'}) logs directory: $logsDir" -Level WARN
            Add-Finding -Step "Step 6" -Status "ISSUE" -Detail "Logs directory missing: $logsDir — app cannot write stdout logs"
            if (-not $WhatIf) {
                New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
                Write-LogMessage "Created logs directory: $logsDir" -Level INFO
            }
        }
        else {
            Write-LogMessage "Logs directory already exists: $logsDir" -Level INFO
        }

        # Check/fix permissions: grant IIS AppPool\ServerMonitorDashboard RX on app folder, Modify on logs
        if (Test-Path $correctPath) {
            $identity = "IIS AppPool\$appPoolName"
            Write-LogMessage "$(if ($WhatIf) {'Checking'} else {'Setting'}) permissions for '$identity' on $correctPath" -Level INFO

            # Check current ACL
            $acl = Get-Acl $correctPath
            $hasRx = $acl.Access | Where-Object {
                $_.IdentityReference -like "*$appPoolName*" -and
                ($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::ReadAndExecute)
            }
            if (-not $hasRx) {
                Add-Finding -Step "Step 6" -Status "ISSUE" -Detail "Missing ReadAndExecute permission for '$identity' on $correctPath"
            }
            else {
                Add-Finding -Step "Step 6" -Status "OK" -Detail "ReadAndExecute permission present for '$identity' on app folder"
            }

            if (Test-Path $logsDir) {
                $aclLogs = Get-Acl $logsDir
                $hasMod = $aclLogs.Access | Where-Object {
                    $_.IdentityReference -like "*$appPoolName*" -and
                    ($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::Modify)
                }
                if (-not $hasMod) {
                    Add-Finding -Step "Step 6" -Status "ISSUE" -Detail "Missing Modify permission for '$identity' on $logsDir — app cannot write logs"
                }
                else {
                    Add-Finding -Step "Step 6" -Status "OK" -Detail "Modify permission present for '$identity' on logs folder"
                }
            }

            if (-not $WhatIf) {
                try {
                    $acl2 = Get-Acl $correctPath
                    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                        $identity, "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow"
                    )
                    $acl2.AddAccessRule($rule)
                    Set-Acl -Path $correctPath -AclObject $acl2
                    Write-LogMessage "  Granted ReadAndExecute to $identity on $correctPath" -Level INFO
                    if (Test-Path $logsDir) {
                        $aclLogs2 = Get-Acl $logsDir
                        $ruleLogs = New-Object System.Security.AccessControl.FileSystemAccessRule(
                            $identity, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow"
                        )
                        $aclLogs2.AddAccessRule($ruleLogs)
                        Set-Acl -Path $logsDir -AclObject $aclLogs2
                        Write-LogMessage "  Granted Modify to $identity on $logsDir" -Level INFO
                    }
                }
                catch {
                    Write-LogMessage "  Could not set permissions: $($_.Exception.Message)" -Level WARN
                    Write-LogMessage "  Manual fix: icacls `"$correctPath`" /grant `"IIS AppPool\$appPoolName`":(OI)(CI)RX /T" -Level WARN
                }
            }
        }
        else {
            Write-LogMessage "Correct install path not found: $correctPath" -Level WARN
            Write-LogMessage "Run: .\IIS-DeployApp.ps1 -SiteName $siteName" -Level WARN
            Add-Finding -Step "Step 6" -Status "ISSUE" -Detail "Correct install path MISSING: $correctPath — run IIS-DeployApp.ps1"
        }
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 7: Final IIS state snapshot
    # ═══════════════════════════════════════════════════════════════════════════
    Write-LogMessage "--- Step 7: Final IIS state ---" -Level INFO

    foreach ($line in (& $appcmd list site 2>&1 | Out-String) -split "`n") {
        if ($line.Trim() -match '^SITE "') { Write-LogMessage "  $($line.Trim())" -Level INFO }
    }
    foreach ($line in (& $appcmd list app 2>&1 | Out-String) -split "`n") {
        if ($line.Trim() -match '^APP "') { Write-LogMessage "  $($line.Trim())" -Level INFO }
    }
    foreach ($line in (& $appcmd list apppool 2>&1 | Out-String) -split "`n") {
        if ($line.Trim() -match '^APPPOOL "') { Write-LogMessage "  $($line.Trim())" -Level INFO }
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 8: Remove HKLM startup registry entries
    #   The old ServerMonitorDashboard.ps1 (service mode) may have added Run/RunOnce
    #   entries under HKLM so the exe started automatically with the server.
    #   This is a server — service-mode autoruns live in HKLM, not user profiles.
    #   HKCU for the current RDP session is also checked as a precaution.
    # ═══════════════════════════════════════════════════════════════════════════
    Write-LogMessage "--- Step 8: Remove startup registry entries (HKLM + current HKCU) ---" -Level INFO

    $startupNames = @(
        "ServerMonitorDashboard",
        "Server Monitor Dashboard"
    )

    $registryRunPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
    )

    $removedRegEntries = 0
    foreach ($regPath in $registryRunPaths) {
        if (-not (Test-Path $regPath)) { continue }
        foreach ($entryName in $startupNames) {
            $value = Get-ItemProperty -Path $regPath -Name $entryName -ErrorAction SilentlyContinue
            if ($null -ne $value) {
                Write-LogMessage "  $(if ($WhatIf) {'WOULD remove'} else {'Removing'}) startup entry '$entryName' from $regPath" -Level WARN
                Add-Finding -Step "Step 8" -Status "ISSUE" -Detail "Legacy startup registry entry '$entryName' at $regPath = $($value.$entryName)"
                if (-not $WhatIf) {
                    Remove-ItemProperty -Path $regPath -Name $entryName -ErrorAction SilentlyContinue
                    Write-LogMessage "  Removed startup entry '$entryName' from $regPath" -Level INFO
                }
                $removedRegEntries++
            }
        }
    }

    if ($removedRegEntries -eq 0) {
        Write-LogMessage "No startup registry entries found (OK)" -Level INFO
        Add-Finding -Step "Step 8" -Status "OK" -Detail "No legacy startup registry entries"
    }
    else {
        Write-LogMessage "$(if ($WhatIf) {'Found'} else {'Removed'}) $removedRegEntries startup registry entry/entries" -Level INFO
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 9: Redeploy ServerMonitorDashboard via IIS-DeployApp
    #   Ensures a clean virtual-app install after all legacy artifacts are gone.
    # ═══════════════════════════════════════════════════════════════════════════
    Write-LogMessage "--- Step 9: Redeploy via IIS-DeployApp ---" -Level INFO

    if ($WhatIf) {
        Write-LogMessage "  WHATIF: Skipping redeploy (Step 9 is skipped in diagnostic mode)" -Level WARN
        Add-Finding -Step "Step 9" -Status "SKIPPED" -Detail "Redeploy via IIS-DeployApp.ps1 skipped in -WhatIf mode"
    }
    else {
        $iisDeployScript = Join-Path $PSScriptRoot "IIS-DeployApp.ps1"
        if (Test-Path $iisDeployScript) {
            Write-LogMessage "  Running IIS-DeployApp.ps1 -SiteName $siteName ..." -Level INFO
            try {
                & $iisDeployScript -SiteName $siteName
                Write-LogMessage "  IIS-DeployApp completed" -Level INFO
            }
            catch {
                Write-LogMessage "  IIS-DeployApp failed: $($_.Exception.Message)" -Level ERROR
            }
        }
        else {
            Write-LogMessage "  IIS-DeployApp.ps1 not found at $iisDeployScript -- skipping redeploy" -Level WARN
        }
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 10: Health check
    # ═══════════════════════════════════════════════════════════════════════════
    Write-LogMessage "--- Step 10: Health check ---" -Level INFO

    if (-not $WhatIf) { Start-Sleep -Seconds 5 }
    $healthUrl = "http://localhost/ServerMonitorDashboard/api/IsAlive"
    try {
        $response = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        Write-LogMessage "[OK] $healthUrl -> HTTP $($response.StatusCode)" -Level INFO
        Add-Finding -Step "Step 10" -Status "OK" -Detail "Health check PASS: $healthUrl -> HTTP $($response.StatusCode)"
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode) {
            Write-LogMessage "[FAIL] $healthUrl -> HTTP $statusCode" -Level ERROR
            Add-Finding -Step "Step 10" -Status "ISSUE" -Detail "Health check FAIL: $healthUrl -> HTTP $statusCode"
        }
        else {
            Write-LogMessage "[FAIL] $healthUrl -> $($_.Exception.Message)" -Level ERROR
            Add-Finding -Step "Step 10" -Status "ISSUE" -Detail "Health check FAIL: $healthUrl -> $($_.Exception.Message)"
        }
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # DIAGNOSTIC REPORT (printed when -WhatIf)
    # ═══════════════════════════════════════════════════════════════════════════
    if ($WhatIf) {
        $issues  = @($findings | Where-Object { $_.Status -eq 'ISSUE' })
        $oks     = @($findings | Where-Object { $_.Status -eq 'OK' })
        $skipped = @($findings | Where-Object { $_.Status -eq 'SKIPPED' })

        $separator = '═' * 72
        Write-Host ""
        Write-Host $separator -ForegroundColor Cyan
        Write-Host "  DIAGNOSTIC REPORT — ServerMonitorDashboard" -ForegroundColor Cyan
        Write-Host "  Server : $($env:COMPUTERNAME)" -ForegroundColor Cyan
        Write-Host "  Time   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
        Write-Host $separator -ForegroundColor Cyan

        # Forensic clues (Step 0) — always shown first in report
        $forensicIssues = @($findings | Where-Object { $_.Step -like 'Step 0*' -and $_.Status -eq 'ISSUE' })
        if ($forensicIssues.Count -gt 0) {
            Write-Host ""
            Write-Host "  FORENSIC INVESTIGATION — HOW it was reinstalled ($($forensicIssues.Count) clue(s)):" -ForegroundColor Magenta
            Write-Host ""
            $i = 1
            foreach ($f in $forensicIssues) {
                Write-Host "  [F$i] $($f.Step)" -ForegroundColor DarkMagenta -NoNewline
                Write-Host "  $($f.Detail)" -ForegroundColor White
                $i++
            }
        }
        else {
            Write-Host ""
            Write-Host "  FORENSIC: No reinstall trigger found in the last 4 hours." -ForegroundColor DarkMagenta
            Write-Host "            Check SCCM/Intune deployments, Windows Update, or manual RDP activity." -ForegroundColor DarkGray
        }

        $nonForensicIssues = @($issues | Where-Object { $_.Step -notlike 'Step 0*' })
        if ($nonForensicIssues.Count -eq 0 -and $forensicIssues.Count -eq 0) {
            Write-Host ""
            Write-Host "  ALL CHECKS PASSED — no legacy artifacts or misconfiguration found." -ForegroundColor Green
            Write-Host "  If the site is still broken, check the application event log and IIS" -ForegroundColor Green
            Write-Host "  stdout log at: $logsDir" -ForegroundColor Green
        }
        elseif ($nonForensicIssues.Count -gt 0) {
            Write-Host ""
            Write-Host "  ISSUES FOUND ($($nonForensicIssues.Count)) — these are WHY the site is broken:" -ForegroundColor Red
            Write-Host ""
            $i = 1
            foreach ($f in $nonForensicIssues) {
                Write-Host "  [$i] $($f.Step)" -ForegroundColor Yellow -NoNewline
                Write-Host "  $($f.Detail)" -ForegroundColor White
                $i++
            }
        }

        $nonForensicOks = @($oks | Where-Object { $_.Step -notlike 'Step 0*' })
        if ($nonForensicOks.Count -gt 0) {
            Write-Host ""
            Write-Host "  CLEAN ($($nonForensicOks.Count)):" -ForegroundColor Green
            foreach ($f in $nonForensicOks) {
                Write-Host "   OK  $($f.Step)  $($f.Detail)" -ForegroundColor DarkGreen
            }
        }

        if ($skipped.Count -gt 0) {
            Write-Host ""
            Write-Host "  SKIPPED ($($skipped.Count)):" -ForegroundColor DarkGray
            foreach ($f in $skipped) {
                Write-Host "  --  $($f.Step)  $($f.Detail)" -ForegroundColor DarkGray
            }
        }

        Write-Host ""
        if ($issues.Count -gt 0) {
            Write-Host "  ACTION: Run without -WhatIf to fix all issues above." -ForegroundColor Cyan
        }
        else {
            Write-Host "  No action needed from this script." -ForegroundColor Cyan
        }
        Write-Host $separator -ForegroundColor Cyan
        Write-Host ""
    }

    Write-LogMessage "=== Fix-ServerMonitorDashboard $(if ($WhatIf) {'(WhatIf) scan'} else {'fix'}) complete ===" -Level INFO
    Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "$($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_FAILED
    exit 1
}
finally {
    Reset-OverrideAppDataFolder
}
