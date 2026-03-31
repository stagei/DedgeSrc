#!/usr/bin/env pwsh
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Installs Server Health Monitor Check Tool as a Windows Service with auto-restart
.DESCRIPTION
    Creates and configures ServerMonitor as a Windows Service that:
    - Starts automatically on boot
    - Restarts automatically on failure
    - Restarts automatically when stopped (if AutoShutdownTime is configured)
.PARAMETER Operation
    Operation to perform:
    - FullReinstall (default): Full teardown and reinstall of service, runtimes, firewall, shortcuts
    - RemoveService: Kill processes, stop and remove the service, then exit
    - AddService: Install and start the service, then exit
    - Uninstall: Full removal of services, processes, firewall rules, URL ACL, scheduled task, shortcuts, app folders, and data folder
.PARAMETER ServiceName
    Name of the Windows Service (default: ServerMonitor)
.PARAMETER ExePath
    Path to the ServerMonitor.exe
.PARAMETER DisplayName
    Display name for the service
.PARAMETER Description
    Service description
.EXAMPLE
    .\ServerMonitorAgent.ps1
.EXAMPLE
    .\ServerMonitorAgent.ps1 -Operation RemoveService
.EXAMPLE
    .\ServerMonitorAgent.ps1 -Operation AddService
.EXAMPLE
    .\ServerMonitorAgent.ps1 -Operation Uninstall
.EXAMPLE
    .\ServerMonitorAgent.ps1 -ExePath "C:\CustomPath\ServerMonitor.exe"
#>

param(
    [ValidateSet("FullReinstall", "RemoveService", "AddService", "Uninstall")]
    [string]$Operation = "FullReinstall",
    [string]$ServiceName = "ServerMonitor",
    [string]$ExePath = "$env:OptPath\DedgeWinApps\ServerMonitor\ServerMonitor.exe",
    [string]$DisplayName = "ServerMonitor",
    [string]$Description = "Monitors server health, performance, and generates alerts for critical events. Also serves as a monitoring agent for other services using REST-Api."
)
Import-Module -Name GlobalFunctions -Force -ErrorAction Stop
Import-Module -Name SoftwareUtils -Force -ErrorAction Stop

try {
    $ErrorActionPreference = "Stop"
    Write-LogMessage "Server Health Monitor Check Tool - Service Installation" -Level INFO


    # Verify running as administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-LogMessage "❌ ERROR: This script must be run as Administrator!" -Level ERROR
        throw "This script must be run as Administrator!"
    }

    Write-LogMessage "Operation mode: $Operation" -Level INFO

    # ─────────────────────────────────────────────────────────────────────────────
    # OPERATION: RemoveService — kill processes, stop & remove service, then exit
    # ─────────────────────────────────────────────────────────────────────────────
    if ($Operation -eq "RemoveService") {
        Write-LogMessage "🛑 RemoveService — stopping and removing $ServiceName..." -Level INFO

        $agentServices = Get-Service -Name "ServerMonitor*" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike "ServerMonitorDashboard*" }

        if ($agentServices) {
            foreach ($svc in $agentServices) {
                Write-LogMessage "   Stopping service: $($svc.Name) (Status: $($svc.Status))" -Level INFO
                if ($svc.Status -eq 'Running') {
                    Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Milliseconds 500
                }
            }
        }

        foreach ($procName in @("ServerMonitorTrayIcon", "ServerMonitor")) {
            Get-Process -Name $procName -ErrorAction SilentlyContinue | ForEach-Object {
                Write-LogMessage "   Killing process: $($_.Name) PID $($_.Id)" -Level INFO
                try { $_.Kill(); $_.WaitForExit(5000) } catch { }
            }
        }

        if ($agentServices) {
            foreach ($svc in $agentServices) {
                $scResult = & sc.exe delete $svc.Name 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-LogMessage "   ✅ Removed service: $($svc.Name)" -Level INFO
                }
                else {
                    Write-LogMessage "   ⚠️ Could not remove $($svc.Name): $scResult" -Level WARN
                }
            }
        }
        else {
            Write-LogMessage "   No ServerMonitor services found to remove" -Level INFO
        }

        Write-LogMessage "✅ RemoveService completed" -Level INFO
        exit 0
    }

    # ─────────────────────────────────────────────────────────────────────────────
    # OPERATION: AddService — install and start the service, then exit
    # ─────────────────────────────────────────────────────────────────────────────
    if ($Operation -eq "AddService") {
        Write-LogMessage "➕ AddService — installing and starting $ServiceName..." -Level INFO

        Install-OurWinApp -AppName "ServerMonitor"

        Start-Sleep -Seconds 2
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($service.Status -eq 'Running') {
            Write-LogMessage "✅ Service $ServiceName started successfully" -Level INFO
        }
        else {
            Write-LogMessage "⚠️ Service status: $($service.Status)" -Level WARN
        }

        Write-LogMessage "✅ AddService completed" -Level INFO
        exit 0
    }

    # ─────────────────────────────────────────────────────────────────────────────
    # OPERATION: Uninstall — full removal of all ServerMonitor artifacts
    # ─────────────────────────────────────────────────────────────────────────────
    if ($Operation -eq "Uninstall") {
        Write-LogMessage "🗑️ Uninstall — removing all ServerMonitor artifacts..." -Level INFO

        $uninstallFolders = @(
            "$env:OptPath\DedgeWinApps\ServerMonitor",
            "$env:OptPath\DedgeWinApps\ServerMonitorTrayIcon",
            "$env:OptPath\data\ServerMonitor"
        )
        $normUninstallFolders = $uninstallFolders | ForEach-Object { $_.TrimEnd('\').ToLower() }

        function Test-UninstallFolderMatch {
            param([string]$Path)
            if ([string]::IsNullOrEmpty($Path)) { return $false }
            $p = $Path.ToLower()
            foreach ($f in $normUninstallFolders) { if ($p.StartsWith($f)) { return $true } }
            return $false
        }

        # ── Phase 1: Stop and remove services ─────────────────────────────────
        Write-LogMessage "   [1/8] Stopping and removing services..." -Level INFO
        $agentServices = Get-Service -Name "ServerMonitor*" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike "ServerMonitorDashboard*" }

        if ($agentServices) {
            foreach ($svc in $agentServices) {
                Write-LogMessage "         Stopping service: $($svc.Name) (Status: $($svc.Status))" -Level INFO
                if ($svc.Status -eq 'Running') {
                    Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Milliseconds 500
                }
                $scResult = & sc.exe delete $svc.Name 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-LogMessage "         ✅ Removed service: $($svc.Name)" -Level INFO
                }
                else {
                    Write-LogMessage "         ⚠️ Could not remove $($svc.Name): $scResult" -Level WARN
                }
            }
        }
        else {
            Write-LogMessage "         No ServerMonitor services found" -Level INFO
        }

        # ── Phase 2: Kill processes ────────────────────────────────────────────
        Write-LogMessage "   [2/8] Killing processes from install folders..." -Level INFO
        $killedPids = [System.Collections.Generic.HashSet[int]]::new()

        try {
            Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
                Where-Object { (Test-UninstallFolderMatch $_.CommandLine) -or (Test-UninstallFolderMatch $_.ExecutablePath) } |
                ForEach-Object {
                    if ($killedPids.Add($_.ProcessId)) {
                        Write-LogMessage "         WMI match: $($_.Name) PID $($_.ProcessId)" -Level INFO
                        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
                    }
                }
        }
        catch { Write-LogMessage "         ⚠️ WMI scan error: $($_.Exception.Message)" -Level WARN }

        foreach ($procName in @("ServerMonitorTrayIcon", "ServerMonitor")) {
            Get-Process -Name $procName -ErrorAction SilentlyContinue | ForEach-Object {
                if ($killedPids.Add($_.Id)) {
                    Write-LogMessage "         Name match: $($_.Name) PID $($_.Id)" -Level INFO
                    try { $_.Kill(); $_.WaitForExit(5000) } catch { }
                }
            }
        }

        foreach ($port in @(8999, 8997)) {
            try {
                $conns = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
                foreach ($conn in $conns) {
                    $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
                    if ($proc -and $killedPids.Add($proc.Id)) {
                        Write-LogMessage "         Port $port held by $($proc.Name) PID $($proc.Id) — killing" -Level INFO
                        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                    }
                }
            }
            catch { }
        }

        if ($killedPids.Count -gt 0) {
            Write-LogMessage "         ⏳ Waiting for $($killedPids.Count) process(es) to release handles..." -Level INFO
            Start-Sleep -Seconds 3
        }
        Write-LogMessage "         ✅ Process cleanup done ($($killedPids.Count) terminated)" -Level INFO

        # ── Phase 3: Remove firewall rules ─────────────────────────────────────
        Write-LogMessage "   [3/8] Removing firewall rules..." -Level INFO
        foreach ($ruleName in @(
            "$($ServiceName)_RestApi_Inbound",
            "$($ServiceName)_RestApi_Outbound",
            "ServerMonitorTrayIcon_Api_Inbound"
        )) {
            $rule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
            if ($rule) {
                Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
                Write-LogMessage "         ✅ Removed firewall rule: $ruleName" -Level INFO
            }
            else {
                Write-LogMessage "         Rule not found: $ruleName (OK)" -Level INFO
            }
        }

        # ── Phase 4: Remove URL ACL ────────────────────────────────────────────
        Write-LogMessage "   [4/8] Removing URL ACL for port 8997..." -Level INFO
        $netshResult = & netsh http delete urlacl url=http://+:8997/ 2>&1
        Write-LogMessage "         netsh: $netshResult" -Level INFO

        # ── Phase 5: Remove scheduled task and registry Run key ────────────────
        Write-LogMessage "   [5/8] Removing scheduled task and registry entries..." -Level INFO
        $taskName = "ServerMonitorTrayIcon"
        $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($existingTask) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
            Write-LogMessage "         ✅ Removed scheduled task: $taskName" -Level INFO
        }
        else {
            Write-LogMessage "         Scheduled task not found: $taskName (OK)" -Level INFO
        }
        $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        Remove-ItemProperty -Path $regPath -Name $taskName -ErrorAction SilentlyContinue

        # ── Phase 6: Remove shortcuts ──────────────────────────────────────────
        Write-LogMessage "   [6/8] Removing shortcuts..." -Level INFO
        $desktopPath = [Environment]::GetFolderPath('CommonDesktopDirectory')
        $desktopShortcut = Join-Path $desktopPath "Server Monitor Tray.lnk"
        if (Test-Path $desktopShortcut) {
            Remove-Item -Path $desktopShortcut -Force -ErrorAction SilentlyContinue
            Write-LogMessage "         ✅ Removed desktop shortcut" -Level INFO
        }

        $startMenuPath = [Environment]::GetFolderPath('CommonStartMenu')
        $startMenuFolder = Join-Path $startMenuPath "Programs\ServerMonitor"
        if (Test-Path $startMenuFolder) {
            Remove-Item -Path $startMenuFolder -Recurse -Force -ErrorAction SilentlyContinue
            Write-LogMessage "         ✅ Removed Start Menu folder" -Level INFO
        }

        # ── Phase 7: Final process verification before folder removal ──────────
        Write-LogMessage "   [7/8] Verifying no processes remain in target folders..." -Level INFO
        $stragglers = @()
        try {
            Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
                Where-Object { (Test-UninstallFolderMatch $_.CommandLine) -or (Test-UninstallFolderMatch $_.ExecutablePath) } |
                ForEach-Object { $stragglers += $_ }
        }
        catch { }

        if ($stragglers.Count -gt 0) {
            Write-LogMessage "         ⚠️ Found $($stragglers.Count) straggler process(es) — killing..." -Level WARN
            foreach ($s in $stragglers) {
                Write-LogMessage "         Killing: $($s.Name) PID $($s.ProcessId)" -Level WARN
                Stop-Process -Id $s.ProcessId -Force -ErrorAction SilentlyContinue
            }
            Start-Sleep -Seconds 3
        }
        else {
            Write-LogMessage "         ✅ No remaining processes in target folders" -Level INFO
        }

        # ── Phase 8: Remove folders ────────────────────────────────────────────
        Write-LogMessage "   [8/8] Removing application and data folders..." -Level INFO
        $savedConfirmPref = $ConfirmPreference
        $ConfirmPreference = 'None'

        foreach ($folder in $uninstallFolders) {
            if (-not (Test-Path $folder)) {
                Write-LogMessage "         Folder does not exist: $folder (OK)" -Level INFO
                continue
            }

            Write-LogMessage "         Removing: $folder" -Level INFO
            try {
                Remove-Item -Path $folder -Recurse -Force -ErrorAction Stop
                Write-LogMessage "         ✅ Removed: $folder" -Level INFO
                continue
            }
            catch {
                Write-LogMessage "         ⚠️ Initial remove failed: $($_.Exception.Message)" -Level WARN
            }

            Write-LogMessage "         🔑 Taking ownership and retrying..." -Level INFO
            & takeown.exe /F "$folder" /R /D Y 2>&1 | Out-Null
            & icacls.exe "$folder" /grant "Administrators:F" /T /C /Q 2>&1 | Out-Null

            try {
                Get-ChildItem -Path $folder -Recurse -Force -ErrorAction SilentlyContinue |
                    Sort-Object -Property FullName -Descending |
                    ForEach-Object {
                        try { Remove-Item -Path $_.FullName -Force -Recurse -ErrorAction SilentlyContinue }
                        catch { Write-LogMessage "         ⚠️ Skipped: $($_.FullName)" -Level WARN }
                    }
                if (Test-Path $folder) {
                    Remove-Item -Path $folder -Force -Recurse -Confirm:$false -ErrorAction SilentlyContinue
                }
            }
            catch { }

            if (Test-Path $folder) {
                Write-LogMessage "         ⚠️ Folder still present after cleanup: $folder" -Level WARN
            }
            else {
                Write-LogMessage "         ✅ Removed: $folder" -Level INFO
            }
        }

        $ConfirmPreference = $savedConfirmPref

        Write-LogMessage "✅ Uninstall completed — all ServerMonitor artifacts removed" -Level INFO
        exit 0
    }

    # ─────────────────────────────────────────────────────────────────────────────
    # CLEANUP: Remove deprecated scheduled tasks and DedgePshApps
    # The old Install-ServerMonitorService was deprecated in favor of ServerMonitorAgent
    # ─────────────────────────────────────────────────────────────────────────────
    $deprecatedTasks = @(
        "Install-ServerMonitorService",
        "DevTools\Install-ServerMonitorService"
    )
    foreach ($taskName in $deprecatedTasks) {
        try {
            $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            if ($task) {
                Write-LogMessage "🗑️ Removing deprecated scheduled task: $taskName" -Level INFO
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
                Write-LogMessage "   ✅ Removed deprecated task: $taskName" -Level INFO
            }
        } catch {
            # Task doesn't exist or can't be removed - that's OK
        }
    }
    
    # Remove deprecated FkPshApp folder
    $deprecatedPshApp = "$env:OptPath\DedgePshApps\Install-ServerMonitorService"
    if (Test-Path $deprecatedPshApp) {
        Write-LogMessage "🗑️ Removing deprecated FkPshApp: $deprecatedPshApp" -Level INFO
        Remove-Item -Path $deprecatedPshApp -Recurse -Force -ErrorAction SilentlyContinue
        Write-LogMessage "   ✅ Removed deprecated FkPshApp" -Level INFO
    }

    # ─────────────────────────────────────────────────────────────────────────────
    # .NET 10 Windows Desktop Runtime - Auto Download and Install
    # ─────────────────────────────────────────────────────────────────────────────
    Write-LogMessage "🔍 Checking for .NET 10 Windows Desktop Runtime..." -Level INFO
    
    $dotnetVersion = "10.0.1"
    $dotnetDownloadUrl = "https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/10.0.1/windowsdesktop-runtime-10.0.1-win-x64.exe"
    $dotnetInstallerPath = Join-Path $env:TEMP "windowsdesktop-runtime-$dotnetVersion-win-x64.exe"
    
    # Check if .NET 10 Desktop Runtime is already installed
    $dotnetInstalled = $false
    try {
        $installedRuntimes = & dotnet --list-runtimes 2>$null
        if ($installedRuntimes -match "Microsoft\.WindowsDesktop\.App 10\.") {
            $dotnetInstalled = $true
            Write-LogMessage "   ✅ .NET 10 Windows Desktop Runtime is already installed" -Level INFO
        }
    }
    catch {
        Write-LogMessage "   dotnet command not found, will install runtime" -Level INFO
    }
    
    if (-not $dotnetInstalled) {
        Write-LogMessage "📥 Downloading .NET 10 Windows Desktop Runtime ($dotnetVersion)..." -Level INFO
        Write-LogMessage "   URL: $dotnetDownloadUrl" -Level INFO
        Write-LogMessage "   Destination: $dotnetInstallerPath" -Level INFO
        
        try {
            # Download the installer
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($dotnetDownloadUrl, $dotnetInstallerPath)
            $webClient.Dispose()
            
            if (Test-Path $dotnetInstallerPath) {
                $installerSize = (Get-Item $dotnetInstallerPath).Length / 1MB
                Write-LogMessage "   ✅ Download complete ($([math]::Round($installerSize, 2)) MB)" -Level INFO
            }
            else {
                throw "Installer file not found after download"
            }
        }
        catch {
            Write-LogMessage "❌ Failed to download .NET 10 Runtime: $($_.Exception.Message)" -Level ERROR
            throw "Failed to download .NET 10 Runtime: $($_.Exception.Message)"
        }
        
        Write-LogMessage "🔧 Installing .NET 10 Windows Desktop Runtime silently..." -Level INFO
        try {
            # Run silent install with logging
            # Arguments: /install /quiet /norestart
            $installArgs = "/install /quiet /norestart"
            Write-LogMessage "   Running: $dotnetInstallerPath $installArgs" -Level INFO
            
            $processInfo = New-Object System.Diagnostics.ProcessStartInfo
            $processInfo.FileName = $dotnetInstallerPath
            $processInfo.Arguments = $installArgs
            $processInfo.RedirectStandardOutput = $true
            $processInfo.RedirectStandardError = $true
            $processInfo.UseShellExecute = $false
            $processInfo.CreateNoWindow = $true
            
            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $processInfo
            $process.Start() | Out-Null
            
            # Capture output
            $stdout = $process.StandardOutput.ReadToEnd()
            $stderr = $process.StandardError.ReadToEnd()
            $process.WaitForExit()
            
            $exitCode = $process.ExitCode
            
            if ($stdout) {
                Write-LogMessage "   Installer output: $stdout" -Level INFO
            }
            if ($stderr) {
                Write-LogMessage "   Installer stderr: $stderr" -Level WARN
            }
            
            # Exit codes: 0 = success, 3010 = success but reboot required, 1641 = reboot initiated
            if ($exitCode -eq 0) {
                Write-LogMessage "   ✅ .NET 10 Runtime installed successfully" -Level INFO
            }
            elseif ($exitCode -eq 3010) {
                Write-LogMessage "   ✅ .NET 10 Runtime installed successfully (reboot may be required)" -Level INFO
            }
            elseif ($exitCode -eq 1641) {
                Write-LogMessage "   ✅ .NET 10 Runtime installed, system reboot was initiated" -Level WARN
            }
            else {
                Write-LogMessage "   ⚠️  .NET 10 Runtime installer exited with code: $exitCode" -Level WARN
            }
        }
        catch {
            Write-LogMessage "❌ Failed to install .NET 10 Runtime: $($_.Exception.Message)" -Level ERROR
            throw "Failed to install .NET 10 Runtime: $($_.Exception.Message)"
        }
        finally {
            # Clean up installer file
            if (Test-Path $dotnetInstallerPath) {
                Remove-Item $dotnetInstallerPath -Force -ErrorAction SilentlyContinue
                Write-LogMessage "   Cleaned up installer file" -Level INFO
            }
        }
    }
    
    Write-LogMessage "" -Level INFO

    # ─────────────────────────────────────────────────────────────────────────────
    # .NET 10 ASP.NET Core Runtime - Auto Download and Install
    # (Required for ServerMonitor web API functionality)
    # ─────────────────────────────────────────────────────────────────────────────
    Write-LogMessage "🔍 Checking for .NET 10 ASP.NET Core Runtime..." -Level INFO
    
    $aspnetVersion = "10.0.1"
    $aspnetDownloadUrl = "https://builds.dotnet.microsoft.com/dotnet/aspnetcore/Runtime/10.0.1/aspnetcore-runtime-10.0.1-win-x64.exe"
    $aspnetInstallerPath = Join-Path $env:TEMP "aspnetcore-runtime-$aspnetVersion-win-x64.exe"
    
    # Check if ASP.NET Core 10 Runtime is already installed
    $aspnetInstalled = $false
    try {
        $installedRuntimes = & dotnet --list-runtimes 2>$null
        if ($installedRuntimes -match "Microsoft\.AspNetCore\.App 10\.") {
            $aspnetInstalled = $true
            Write-LogMessage "   ✅ .NET 10 ASP.NET Core Runtime is already installed" -Level INFO
        }
    }
    catch {
        Write-LogMessage "   dotnet command not found, will install ASP.NET Core runtime" -Level INFO
    }
    
    if (-not $aspnetInstalled) {
        Write-LogMessage "📥 Downloading .NET 10 ASP.NET Core Runtime ($aspnetVersion)..." -Level INFO
        Write-LogMessage "   URL: $aspnetDownloadUrl" -Level INFO
        Write-LogMessage "   Destination: $aspnetInstallerPath" -Level INFO
        
        try {
            # Download the installer
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($aspnetDownloadUrl, $aspnetInstallerPath)
            $webClient.Dispose()
            
            if (Test-Path $aspnetInstallerPath) {
                $installerSize = (Get-Item $aspnetInstallerPath).Length / 1MB
                Write-LogMessage "   ✅ Download complete ($([math]::Round($installerSize, 2)) MB)" -Level INFO
            }
            else {
                throw "ASP.NET Core installer file not found after download"
            }
        }
        catch {
            Write-LogMessage "❌ Failed to download .NET 10 ASP.NET Core Runtime: $($_.Exception.Message)" -Level ERROR
            throw "Failed to download .NET 10 ASP.NET Core Runtime: $($_.Exception.Message)"
        }
        
        Write-LogMessage "🔧 Installing .NET 10 ASP.NET Core Runtime silently..." -Level INFO
        try {
            $installArgs = "/install /quiet /norestart"
            Write-LogMessage "   Running: $aspnetInstallerPath $installArgs" -Level INFO
            
            $processInfo = New-Object System.Diagnostics.ProcessStartInfo
            $processInfo.FileName = $aspnetInstallerPath
            $processInfo.Arguments = $installArgs
            $processInfo.RedirectStandardOutput = $true
            $processInfo.RedirectStandardError = $true
            $processInfo.UseShellExecute = $false
            $processInfo.CreateNoWindow = $true
            
            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $processInfo
            $process.Start() | Out-Null
            
            $stdout = $process.StandardOutput.ReadToEnd()
            $stderr = $process.StandardError.ReadToEnd()
            $process.WaitForExit()
            
            $exitCode = $process.ExitCode
            
            if ($stdout) {
                Write-LogMessage "   Output: $stdout" -Level INFO
            }
            if ($stderr) {
                Write-LogMessage "   StdErr: $stderr" -Level WARN
            }
            
            if ($exitCode -eq 0) {
                Write-LogMessage "   ✅ .NET 10 ASP.NET Core Runtime installed successfully" -Level INFO
            }
            elseif ($exitCode -eq 3010) {
                Write-LogMessage "   ✅ .NET 10 ASP.NET Core Runtime installed (reboot may be required)" -Level INFO
            }
            elseif ($exitCode -eq 1641) {
                Write-LogMessage "   ✅ .NET 10 ASP.NET Core Runtime installed, system reboot was initiated" -Level WARN
            }
            else {
                Write-LogMessage "   ⚠️  .NET 10 ASP.NET Core Runtime installer exited with code: $exitCode" -Level WARN
            }
        }
        catch {
            Write-LogMessage "❌ Failed to install .NET 10 ASP.NET Core Runtime: $($_.Exception.Message)" -Level ERROR
            throw "Failed to install .NET 10 ASP.NET Core Runtime: $($_.Exception.Message)"
        }
        finally {
            # Clean up installer file
            if (Test-Path $aspnetInstallerPath) {
                Remove-Item $aspnetInstallerPath -Force -ErrorAction SilentlyContinue
                Write-LogMessage "   Cleaned up ASP.NET Core installer file" -Level INFO
            }
        }
    }
    
    Write-LogMessage "" -Level INFO

    # ─────────────────────────────────────────────────────────────────────────────
    # KILL ALL PROCESSES HOLDING FILES IN INSTALL FOLDERS
    # Four-pass strategy to catch every process - including those that only load
    # a DLL from the folder (e.g. FontAwesome.Sharp.dll in TrayIcon folder).
    #
    # Pass 1 - Services:      stop & delete any service whose binary lives here
    # Pass 2 - Command lines: kill processes launched from these paths
    # Pass 3 - Loaded modules: kill processes with any DLL from these paths open
    # Pass 4 - Known names:   final sweep by process name (TrayIcon first!)
    # Pass 5 - Ports:         free TCP ports 8997/8999 held by any leftover
    # ─────────────────────────────────────────────────────────────────────────────
    Write-LogMessage "🛑 Terminating all processes with dependencies on install folders..." -Level INFO

    $installFolders = @(
        "$env:OptPath\DedgeWinApps\ServerMonitor",
        "$env:OptPath\DedgeWinApps\ServerMonitorTrayIcon"
    )
    # Normalise once for fast prefix matching
    $normFolders = $installFolders | ForEach-Object { $_.TrimEnd('\').ToLower() }

    function Test-FolderMatch {
        param([string]$Path)
        if ([string]::IsNullOrEmpty($Path)) { return $false }
        $p = $Path.ToLower()
        foreach ($f in $normFolders) { if ($p.StartsWith($f)) { return $true } }
        return $false
    }

    $killedPids = [System.Collections.Generic.HashSet[int]]::new()

    # ── Pass 1: Windows Services ──────────────────────────────────────────────
    Write-LogMessage "   [1/5] Stopping services running from install folders..." -Level INFO
    try {
        Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
            Where-Object { Test-FolderMatch $_.PathName } |
            ForEach-Object {
                Write-LogMessage "         Service: $($_.Name) | $($_.PathName)" -Level INFO
                Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 300
                $scOut = & sc.exe delete $_.Name 2>&1
                Write-LogMessage "         Deleted service '$($_.Name)': $scOut" -Level INFO
            }
    }
    catch { Write-LogMessage "         ⚠️  Service scan error: $($_.Exception.Message)" -Level WARN }

    # ── Pass 2: Process command lines / executable paths ──────────────────────
    Write-LogMessage "   [2/5] Killing processes launched from install folders..." -Level INFO
    try {
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { (Test-FolderMatch $_.CommandLine) -or (Test-FolderMatch $_.ExecutablePath) } |
            ForEach-Object {
                if ($killedPids.Add($_.ProcessId)) {
                    Write-LogMessage "         CmdLine match: $($_.Name) PID $($_.ProcessId)" -Level INFO
                    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
                }
            }
    }
    catch { Write-LogMessage "         ⚠️  Command-line scan error: $($_.Exception.Message)" -Level WARN }

    # ── Pass 3: Loaded DLL / module paths ─────────────────────────────────────
    Write-LogMessage "   [3/5] Killing processes with DLLs loaded from install folders..." -Level INFO
    foreach ($proc in [System.Diagnostics.Process]::GetProcesses()) {
        try {
            $hasMatch = $false
            foreach ($mod in $proc.Modules) {
                if (Test-FolderMatch $mod.FileName) { $hasMatch = $true; break }
            }
            if ($hasMatch -and $killedPids.Add($proc.Id)) {
                Write-LogMessage "         Module match: $($proc.Name) PID $($proc.Id)" -Level INFO
                $proc.Kill()
                $proc.WaitForExit(3000)
            }
        }
        catch { }  # Access-denied for protected system processes is expected
    }

    # ── Pass 4: Known process names (TrayIcon first – it can restart Agent) ───
    Write-LogMessage "   [4/5] Final sweep by known process names..." -Level INFO
    foreach ($procName in @("ServerMonitorTrayIcon", "ServerMonitor")) {
        Get-Process -Name $procName -ErrorAction SilentlyContinue | ForEach-Object {
            if ($killedPids.Add($_.Id)) {
                Write-LogMessage "         Name match: $($_.Name) PID $($_.Id)" -Level INFO
                try { $_.Kill(); $_.WaitForExit(5000) }
                catch { Write-LogMessage "         ⚠️  Could not kill PID $($_.Id): $($_.Exception.Message)" -Level WARN }
            }
        }
    }

    # ── Pass 5: Free API ports 8999 and 8997 ─────────────────────────────────
    Write-LogMessage "   [5/5] Freeing API ports 8999 / 8997..." -Level INFO
    foreach ($port in @(8999, 8997)) {
        try {
            $conns = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
            if ($conns) {
                foreach ($conn in $conns) {
                    $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
                    if ($proc -and $killedPids.Add($proc.Id)) {
                        Write-LogMessage "         Port $port held by $($proc.Name) PID $($proc.Id) — killing" -Level INFO
                        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                        Start-Sleep -Milliseconds 500
                    }
                }
            }
            else {
                Write-LogMessage "         Port $port is free" -Level INFO
            }
        }
        catch { Write-LogMessage "         ⚠️  Could not check port $($port): $($_.Exception.Message)" -Level WARN }
    }

    if ($killedPids.Count -gt 0) {
        Write-LogMessage "   ⏳ Waiting for $($killedPids.Count) process(es) to fully release file handles..." -Level INFO
        Start-Sleep -Seconds 3
    }
    Write-LogMessage "   ✅ Process cleanup complete ($($killedPids.Count) terminated)" -Level INFO
    Write-LogMessage "" -Level INFO

    # Grant batch logon rights to the user (required for Task Scheduler)
    Write-LogMessage "Granting 'Log on as batch job' right..." -Level INFO
    Grant-BatchLogonRight

    # Grant service logon rights to the user (required for Windows Services)
    Write-LogMessage "Granting 'Log on as a service' right..." -Level INFO
    Grant-ServiceLogonRight


    # # Resolve environment variable in path if present
    # if ($ExePath -match '\$env:(\w+)') {
    #     $envVarName = $matches[1]
    #     $envVarValue = [Environment]::GetEnvironmentVariable($envVarName)
    #     if ($envVarValue) {
    #         $ExePath = $ExePath -replace "`$env:$envVarName", $envVarValue
    #         Write-LogMessage "📋 Resolved environment variable: `$env:$envVarName = $envVarValue" -Level INFO
    #     }
    #     else {
    #         Write-LogMessage "⚠️  WARNING: Environment variable `$env:$envVarName is not set!" -Level WARN
    #         Write-Host "   Using path as-is: $ExePath" -ForegroundColor Yellow
    #     }
    # }

    # Convert to absolute path
    if (-not [System.IO.Path]::IsPathRooted($ExePath)) {
        $ExePath = [System.IO.Path]::GetFullPath($ExePath)
    }

    Write-LogMessage "📋 Executable path: $ExePath" -Level INFO

    # ─────────────────────────────────────────────────────────────────────────────
    # CLEANUP: Remove ALL orphaned ServerMonitor* services (not Dashboard ones)
    # This fixes issues from previous installations that left orphaned services
    # ─────────────────────────────────────────────────────────────────────────────
    Write-LogMessage "🗑️  Cleaning up ALL orphaned ServerMonitor services..." -Level INFO
    
    # Get all services starting with "ServerMonitor" but NOT "ServerMonitorDashboard"
    $agentServices = Get-Service -Name "ServerMonitor*" -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -notlike "ServerMonitorDashboard*" }
    
    if ($agentServices) {
        foreach ($svc in $agentServices) {
            Write-LogMessage "   Found service: $($svc.Name) (Status: $($svc.Status))" -Level INFO
            try {
                # Stop the service if running
                if ($svc.Status -eq 'Running') {
                    Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Milliseconds 500
                }
                
                # Kill any remaining process with matching name
                Get-Process -Name $svc.Name -ErrorAction SilentlyContinue | ForEach-Object {
                    try { $_.Kill(); $_.WaitForExit(3000) } catch { }
                }
                
                # Remove the service using sc.exe (more reliable than Remove-Service)
                $scResult = & sc.exe delete $svc.Name 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-LogMessage "   ✅ Removed service: $($svc.Name)" -Level INFO
                }
                else {
                    Write-LogMessage "   ⚠️  Could not remove $($svc.Name): $scResult" -Level WARN
                }
            }
            catch {
                Write-LogMessage "   ⚠️  Error cleaning up $($svc.Name): $($_.Exception.Message)" -Level WARN
            }
        }
        Start-Sleep -Seconds 2
    }
    else {
        Write-LogMessage "   No orphaned ServerMonitor services found" -Level INFO
    }

    # ─────────────────────────────────────────────────────────────────────────────
    # REMOVE OLD INSTALLATION FOLDERS (ensures clean deployment)
    # ─────────────────────────────────────────────────────────────────────────────
    Write-LogMessage "🗑️  Removing old installation folders for clean deployment..." -Level INFO
    
    $foldersToRemove = @(
        "$env:OptPath\DedgeWinApps\ServerMonitor",
        "$env:OptPath\DedgeWinApps\ServerMonitorTrayIcon"
    )
    
    $savedConfirmPref = $ConfirmPreference
    $ConfirmPreference = 'None'

    foreach ($folder in $foldersToRemove) {
        if (-not (Test-Path $folder)) {
            Write-LogMessage "   Folder does not exist: $folder (OK)" -Level INFO
            continue
        }

        Write-LogMessage "   Removing: $folder" -Level INFO

        # Attempt 1 – straightforward recursive remove
        try {
            Remove-Item -Path $folder -Recurse -Force -ErrorAction Stop
            Write-LogMessage "   ✅ Removed: $folder" -Level INFO
            continue
        }
        catch {
            Write-LogMessage "   ⚠️  Initial remove failed: $($_.Exception.Message)" -Level WARN
        }

        # Attempt 2 – scan for any remaining processes holding files in this folder,
        #             then retry after taking ownership of locked files
        Write-LogMessage "   🔍 Scanning for processes locking files in $folder..." -Level INFO
        $normFolder = $folder.TrimEnd('\').ToLower()

        # Check running process modules for remaining locks
        foreach ($proc in [System.Diagnostics.Process]::GetProcesses()) {
            try {
                foreach ($mod in $proc.Modules) {
                    if ($mod.FileName.ToLower().StartsWith($normFolder)) {
                        Write-LogMessage "   Killing locking process: $($proc.Name) PID $($proc.Id) ($($mod.FileName))" -Level WARN
                        $proc.Kill()
                        $proc.WaitForExit(3000)
                        break
                    }
                }
            }
            catch { }
        }

        # Also kill by WMI command line as a catch-all
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -and $_.CommandLine.ToLower().StartsWith($normFolder) } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

        Start-Sleep -Seconds 2

        # Take ownership of entire tree so ACL restrictions can't block deletion
        Write-LogMessage "   🔑 Taking ownership of $folder..." -Level INFO
        & takeown.exe /F "$folder" /R /D Y 2>&1 | Out-Null
        & icacls.exe "$folder" /grant "Administrators:F" /T /C /Q 2>&1 | Out-Null

        # Remove file by file (avoids recursion confirmation quirk on some PS builds)
        try {
            Get-ChildItem -Path $folder -Recurse -Force -ErrorAction SilentlyContinue |
                Sort-Object -Property FullName -Descending |
                ForEach-Object {
                    try { Remove-Item -Path $_.FullName -Force -Recurse -ErrorAction SilentlyContinue }
                    catch { Write-LogMessage "   ⚠️  Skipped: $($_.FullName) — $($_.Exception.Message)" -Level WARN }
                }
            if (Test-Path $folder) {
                Remove-Item -Path $folder -Force -Recurse -Confirm:$false -ErrorAction SilentlyContinue
            }
        }
        catch { }

        if (Test-Path $folder) {
            Write-LogMessage "   ⚠️  Folder still present after cleanup: $folder" -Level WARN
        }
        else {
            Write-LogMessage "   ✅ Removed: $folder" -Level INFO
        }
    }

    $ConfirmPreference = $savedConfirmPref
    
    Write-LogMessage "" -Level INFO

    # Deploy/update the application files.
    # Install-OurWinApp handles: stop service, kill process, robocopy, sc.exe create,
    # failure restart policy, service account selection, and Start-Service.
    Install-OurWinApp -AppName "ServerMonitor"

    # Install ServerMonitorTrayIcon with pretty display name (creates Desktop and Start Menu shortcuts automatically)
    Install-OurWinApp -AppName "ServerMonitorTrayIcon" -DisplayName "Server Monitor Tray App"

    # Path to the installed executable
    $trayIconPath = "$env:OptPath\DedgeWinApps\ServerMonitorTrayIcon\ServerMonitorTrayIcon.exe"

    # ─────────────────────────────────────────────────────────────────────────────
    # Configure ServerMonitorTrayIcon Startup via Scheduled Task (All Users)
    # This replaces the old Registry Run key which only worked for the installing user
    # ─────────────────────────────────────────────────────────────────────────────
    Write-LogMessage "📋 Configuring Scheduled Task for ServerMonitorTrayIcon..." -Level INFO
    
    $taskName = "ServerMonitorTrayIcon"
    $trayIconIconPath = "$env:OptPath\DedgeWinApps\ServerMonitorTrayIcon\dedge.ico"
    
    try {
        # Remove old Registry Run key if present (cleanup from previous installs)
        $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        Remove-ItemProperty -Path $regPath -Name $taskName -ErrorAction SilentlyContinue
        
        # Remove existing scheduled task
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        
        # Create Scheduled Task for startup at user logon (works for ALL users)
        # Use schtasks.exe for better compatibility across PowerShell versions
        # /SC ONLOGON - Trigger when any user logs on
        # /RL HIGHEST - Run with elevated (admin) privileges without UAC prompt
        # /IT - Interactive mode (runs in user session, tray icon visible)
        # /DELAY 0000:10 - 10 second delay to allow desktop to fully load
        $schtasksArgs = @(
            '/Create'
            '/TN', $taskName
            '/TR', "`"$trayIconPath`""
            '/SC', 'ONLOGON'
            '/RL', 'HIGHEST'
            '/IT'
            '/DELAY', '0000:10'
            '/F'
        )
        $result = & schtasks.exe @schtasksArgs 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-LogMessage "   ✅ Scheduled Task created (runs at logon with admin privileges)" -Level INFO
        }
        else {
            Write-LogMessage "   ⚠️ schtasks.exe returned: $result" -Level WARN
        }
        
        # Run the scheduled task to start the tray app in the user's interactive session
        # This ensures the tray icon appears even when install runs from a service
        Write-LogMessage "   🚀 Starting Tray Icon via scheduled task..." -Level INFO
        $runResult = & schtasks.exe /Run /TN $taskName 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-LogMessage "   ✅ Tray Icon started in user session" -Level INFO
        }
        else {
            # If scheduled task fails (no user logged in), that's OK
            Write-LogMessage "   ⚠️ Scheduled task run failed (no interactive session?): $runResult" -Level WARN
            Write-LogMessage "   ℹ️ Tray will start at next user logon" -Level INFO
        }
    }
    catch {
        Write-LogMessage "   ❌ Failed to create Scheduled Task: $($_.Exception.Message)" -Level ERROR
    }
    
    # ─────────────────────────────────────────────────────────────────────────────
    # Create Desktop and Start Menu Shortcuts with Icon
    # ─────────────────────────────────────────────────────────────────────────────
    Write-LogMessage "🔗 Creating shortcuts for Server Monitor Tray..." -Level INFO
    
    try {
        $shell = New-Object -ComObject WScript.Shell
        
        # Desktop shortcut (All Users)
        $desktopPath = [Environment]::GetFolderPath('CommonDesktopDirectory')
        $desktopShortcut = Join-Path $desktopPath "Server Monitor Tray.lnk"
        $shortcut = $shell.CreateShortcut($desktopShortcut)
        $shortcut.TargetPath = $trayIconPath
        $shortcut.WorkingDirectory = Split-Path $trayIconPath
        $shortcut.Description = "Server Monitor Tray Application"
        if (Test-Path $trayIconIconPath) { $shortcut.IconLocation = "$($trayIconIconPath),0" }
        $shortcut.Save()
        # Set "Run as Administrator" flag
        $bytes = [System.IO.File]::ReadAllBytes($desktopShortcut)
        $bytes[0x15] = $bytes[0x15] -bor 0x20
        [System.IO.File]::WriteAllBytes($desktopShortcut, $bytes)
        Write-LogMessage "   ✅ Desktop shortcut created with icon" -Level INFO
        
        # Start Menu shortcut (All Users - in ServerMonitor folder)
        $startMenuPath = [Environment]::GetFolderPath('CommonStartMenu')
        $programsPath = Join-Path $startMenuPath "Programs\ServerMonitor"
        if (-not (Test-Path $programsPath)) { New-Item -Path $programsPath -ItemType Directory -Force | Out-Null }
        $startMenuShortcut = Join-Path $programsPath "Server Monitor Tray.lnk"
        $shortcut = $shell.CreateShortcut($startMenuShortcut)
        $shortcut.TargetPath = $trayIconPath
        $shortcut.WorkingDirectory = Split-Path $trayIconPath
        $shortcut.Description = "Server Monitor Tray Application"
        if (Test-Path $trayIconIconPath) { $shortcut.IconLocation = "$($trayIconIconPath),0" }
        $shortcut.Save()
        # Set "Run as Administrator" flag
        $bytes = [System.IO.File]::ReadAllBytes($startMenuShortcut)
        $bytes[0x15] = $bytes[0x15] -bor 0x20
        [System.IO.File]::WriteAllBytes($startMenuShortcut, $bytes)
        Write-LogMessage "   ✅ Start Menu shortcut created with icon" -Level INFO
        
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
    }
    catch {
        Write-LogMessage "   ⚠️ Could not create shortcuts: $($_.Exception.Message)" -Level WARN
    }

    # Verify the exe and required config files exist post-deployment
    Write-LogMessage "🧪 Verifying deployment..." -Level INFO
    $resolvedExePath = "$env:OptPath\DedgeWinApps\$ServiceName\$ServiceName.exe"
    if (Test-Path $resolvedExePath) {
        $ExePath = $resolvedExePath
        Write-LogMessage "   ✅ Executable found: $ExePath" -Level INFO
    }
    else {
        Write-LogMessage "   ❌ Executable not found: $resolvedExePath" -Level ERROR
        throw "Executable not found after deployment: $resolvedExePath"
    }
    $exeDir = Split-Path -Parent $ExePath
    $appsettingsPath = Join-Path $exeDir "appsettings.json"
    if (-not (Test-Path $appsettingsPath)) {
        Write-LogMessage "   ❌ appsettings.json not found in $exeDir" -Level ERROR
        throw "Cannot proceed without appsettings.json"
    }
    foreach ($file in @("NLog.config", "ScheduledTaskExitCodes.json")) {
        if (Test-Path (Join-Path $exeDir $file)) {
            Write-LogMessage "   ✅ $file found" -Level INFO
        }
        else {
            Write-LogMessage "   ⚠️  $file not found (may be optional)" -Level WARN
        }
    }

    # Configure firewall rules for REST API port 8999 (Agent API)
    Write-LogMessage "🔥 Configuring firewall rules for REST API port 8999 (Agent)..." -Level INFO
    $firewallRuleName = "$($ServiceName)_RestApi"
    $restApiPort = 8999

    try {
        # Remove existing rules if they exist (to ensure clean state)
        $existingInbound = Get-NetFirewallRule -DisplayName "$($firewallRuleName)_Inbound" -ErrorAction SilentlyContinue
        if ($existingInbound) {
            Remove-NetFirewallRule -DisplayName "$($firewallRuleName)_Inbound" -ErrorAction SilentlyContinue
            Write-LogMessage "   Removed existing inbound rule" -Level INFO
        }

        $existingOutbound = Get-NetFirewallRule -DisplayName "$($firewallRuleName)_Outbound" -ErrorAction SilentlyContinue
        if ($existingOutbound) {
            Remove-NetFirewallRule -DisplayName "$($firewallRuleName)_Outbound" -ErrorAction SilentlyContinue
            Write-LogMessage "   Removed existing outbound rule" -Level INFO
        }

        # Create inbound rule for port 8999
        New-NetFirewallRule -DisplayName "$($firewallRuleName)_Inbound" `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort $restApiPort `
            -Action Allow `
            -Profile Domain, Private `
            -Description "Allow inbound traffic for $ServiceName REST API on port $restApiPort" `
            -ErrorAction Stop | Out-Null
        Write-LogMessage "   ✅ Inbound firewall rule created for port $restApiPort" -Level INFO

        # Create outbound rule for port 8999
        New-NetFirewallRule -DisplayName "$($firewallRuleName)_Outbound" `
            -Direction Outbound `
            -Protocol TCP `
            -LocalPort $restApiPort `
            -Action Allow `
            -Profile Domain, Private `
            -Description "Allow outbound traffic for $ServiceName REST API on port $restApiPort" `
            -ErrorAction Stop | Out-Null
        Write-LogMessage "   ✅ Outbound firewall rule created for port $restApiPort" -Level INFO

        Write-LogMessage "✅ Firewall configured for REST API port $($restApiPort)" -Level INFO
    }
    catch {
        Write-LogMessage "⚠️  Warning: Could not configure firewall rules: $($_.Exception.Message)" -Level WARN
        Write-LogMessage "   💡 You may need to manually open port $restApiPort in Windows Firewall" -Level WARN
    }

    # Configure firewall rules for Tray API port 8997
    Write-LogMessage "🔥 Configuring firewall rules for Tray API port 8997..." -Level INFO
    $trayFirewallRuleName = "ServerMonitorTrayIcon_Api"
    $trayApiPort = 8997

    try {
        # Remove existing rules if they exist
        $existingTrayInbound = Get-NetFirewallRule -DisplayName "$($trayFirewallRuleName)_Inbound" -ErrorAction SilentlyContinue
        if ($existingTrayInbound) {
            Remove-NetFirewallRule -DisplayName "$($trayFirewallRuleName)_Inbound" -ErrorAction SilentlyContinue
            Write-LogMessage "   Removed existing tray inbound rule" -Level INFO
        }

        # Create inbound rule for port 8997
        New-NetFirewallRule -DisplayName "$($trayFirewallRuleName)_Inbound" `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort $trayApiPort `
            -Action Allow `
            -Profile Domain, Private `
            -Description "Allow inbound traffic for ServerMonitorTrayIcon API on port $trayApiPort" `
            -ErrorAction Stop | Out-Null
        Write-LogMessage "   ✅ Inbound firewall rule created for port $trayApiPort" -Level INFO

        Write-LogMessage "✅ Firewall configured for Tray API port $($trayApiPort)`n" -Level INFO
    }
    catch {
        Write-LogMessage "⚠️  Warning: Could not configure tray firewall rules: $($_.Exception.Message)" -Level WARN
        Write-LogMessage "   💡 You may need to manually open port $trayApiPort in Windows Firewall" -Level WARN
    }

    # Configure URL ACL for HttpListener on port 8997 (allows non-admin to listen)
    Write-LogMessage "🔧 Configuring URL ACL for Tray API port 8997..." -Level INFO
    try {
        # Remove existing reservation
        & netsh http delete urlacl url=http://+:8997/ 2>&1 | Out-Null
        
        # Get current user for reservation
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        
        # Add URL ACL reservation
        $result = & netsh http add urlacl url=http://+:8997/ user="$currentUser" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-LogMessage "   ✅ URL ACL configured for http://+:8997/ (user: $currentUser)" -Level INFO
        }
        else {
            Write-LogMessage "   ⚠️  URL ACL configuration: $result" -Level WARN
        }
    }
    catch {
        Write-LogMessage "   ⚠️  Could not configure URL ACL: $($_.Exception.Message)" -Level WARN
    }

    # Verify service status post-install (Install-OurWinApp already started the service)
    Start-Sleep -Seconds 2
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service.Status -eq 'Running') {
        Write-LogMessage "✅ Service started successfully!`n" -Level INFO
    }
    else {
        Write-LogMessage "⚠️  Service status: $($service.Status)" -Level WARN
        Write-LogMessage "💡 The service was created but did not start. Check logs for details." -Level WARN
    }

    # Display service configuration
    $serviceSummary = @"
═══════════════════════════════════════════════════════
  Service Configuration Summary
═══════════════════════════════════════════════════════

Service Name:     $ServiceName
Display Name:     $DisplayName
Status:           $($service.Status)
Start Type:       Automatic (Delayed)
Executable:       $ExePath
Auto-Restart:     Yes (on failure, after 1 minute)

📋 Service Management Commands:
  Start:   Start-Service -Name $ServiceName
  Stop:    Stop-Service -Name $ServiceName
  Restart: Restart-Service -Name $ServiceName
  Status:  Get-Service -Name $ServiceName
  Remove:  Remove-Service -Name $ServiceName

💡 Configuration Tips:
  • Edit appsettings.json to configure monitoring
  • Set AutoShutdownTime for daily restart (e.g., '02:00')
  • Check logs in: C:\opt\data\ServerMonitor\
  • REST API available at: http://$(hostname):8999/swagger

✅ Installation complete!

═══════════════════════════════════════════════════════
"@

    Write-LogMessage $serviceSummary -Level INFO
    
    # ─────────────────────────────────────────────────────────────────────────────
    # VALIDATION: Verify installed executables - Signatures and Versions
    # ─────────────────────────────────────────────────────────────────────────────
    Write-LogMessage "" -Level INFO
    Write-LogMessage "═══════════════════════════════════════════════════════" -Level INFO
    Write-LogMessage "  📋 Installed Application Validation" -Level INFO
    Write-LogMessage "═══════════════════════════════════════════════════════" -Level INFO
    
    $installedApps = @(
        @{ Name = "ServerMonitor";          Path = "$env:OptPath\DedgeWinApps\ServerMonitor\ServerMonitor.exe" }
        @{ Name = "ServerMonitorTrayIcon";  Path = "$env:OptPath\DedgeWinApps\ServerMonitorTrayIcon\ServerMonitorTrayIcon.exe" }
    )
    
    $validationResults = @()
    
    foreach ($app in $installedApps) {
        Write-LogMessage "" -Level INFO
        Write-LogMessage "  🔍 $($app.Name)" -Level INFO
        Write-LogMessage "     Path: $($app.Path)" -Level INFO
        
        if (-not (Test-Path $app.Path)) {
            Write-LogMessage "     ❌ FILE NOT FOUND" -Level ERROR
            $validationResults += @{
                App = $app.Name
                Exists = $false
                Version = "N/A"
                Signed = $false
                SignedBy = "N/A"
            }
            continue
        }
        
        # Get file version
        try {
            $fileInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($app.Path)
            $fileVersion = $fileInfo.FileVersion
            $productVersion = $fileInfo.ProductVersion
            
            if ([string]::IsNullOrWhiteSpace($fileVersion)) {
                $fileVersion = "Unknown"
            }
            
            Write-LogMessage "     📦 File Version: $fileVersion" -Level INFO
            if ($productVersion -and $productVersion -ne $fileVersion) {
                Write-LogMessage "     📦 Product Version: $productVersion" -Level INFO
            }
        }
        catch {
            $fileVersion = "Error: $($_.Exception.Message)"
            Write-LogMessage "     ⚠️  Could not read version: $($_.Exception.Message)" -Level WARN
        }
        
        # Check digital signature
        try {
            $signature = Get-AuthenticodeSignature -FilePath $app.Path -ErrorAction Stop
            
            if ($signature.Status -eq 'Valid') {
                $signedBy = $signature.SignerCertificate.Subject
                # Extract CN (Common Name) from subject
                if ($signedBy -match 'CN=([^,]+)') {
                    $signedBy = $matches[1]
                }
                Write-LogMessage "     ✅ Signature: VALID" -Level INFO
                Write-LogMessage "     🔐 Signed by: $signedBy" -Level INFO
                
                $validationResults += @{
                    App = $app.Name
                    Exists = $true
                    Version = $fileVersion
                    Signed = $true
                    SignedBy = $signedBy
                }
            }
            elseif ($signature.Status -eq 'NotSigned') {
                Write-LogMessage "     ⚠️  Signature: NOT SIGNED" -Level WARN
                $validationResults += @{
                    App = $app.Name
                    Exists = $true
                    Version = $fileVersion
                    Signed = $false
                    SignedBy = "N/A"
                }
            }
            else {
                Write-LogMessage "     ❌ Signature: $($signature.Status)" -Level ERROR
                if ($signature.StatusMessage) {
                    Write-LogMessage "        $($signature.StatusMessage)" -Level WARN
                }
                $validationResults += @{
                    App = $app.Name
                    Exists = $true
                    Version = $fileVersion
                    Signed = $false
                    SignedBy = "Status: $($signature.Status)"
                }
            }
        }
        catch {
            Write-LogMessage "     ❌ Could not check signature: $($_.Exception.Message)" -Level ERROR
            $validationResults += @{
                App = $app.Name
                Exists = $true
                Version = $fileVersion
                Signed = $false
                SignedBy = "Error checking"
            }
        }
        
        # Show file timestamp
        try {
            $fileItem = Get-Item $app.Path
            Write-LogMessage "     📅 Modified: $($fileItem.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Level INFO
            Write-LogMessage "     📁 Size: $([math]::Round($fileItem.Length / 1KB, 1)) KB" -Level INFO
        }
        catch {
            # Ignore timestamp errors
        }
    }
    
    # Summary table
    Write-LogMessage "" -Level INFO
    Write-LogMessage "═══════════════════════════════════════════════════════" -Level INFO
    Write-LogMessage "  📊 Validation Summary" -Level INFO
    Write-LogMessage "═══════════════════════════════════════════════════════" -Level INFO
    Write-LogMessage "" -Level INFO
    Write-LogMessage "  Application                  Version          Signed" -Level INFO
    Write-LogMessage "  ────────────────────────────────────────────────────" -Level INFO
    
    $allValid = $true
    foreach ($result in $validationResults) {
        $appName = $result.App.PadRight(28)
        $version = $result.Version.PadRight(16)
        if ($result.Signed) {
            $signedStatus = "✅ Yes"
        }
        else {
            $signedStatus = "❌ No"
            $allValid = $false
        }
        Write-LogMessage "  $appName $version $signedStatus" -Level INFO
    }
    
    Write-LogMessage "" -Level INFO
    if ($allValid) {
        Write-LogMessage "  ✅ All executables are properly signed and versioned" -Level INFO
    }
    else {
        Write-LogMessage "  ⚠️  WARNING: Some executables are NOT signed!" -Level WARN
        Write-LogMessage "     This may indicate a deployment issue or tampered files." -Level WARN
        Write-LogMessage "     Re-run Build-And-Publish.ps1 to ensure proper signing." -Level WARN
    }
    Write-LogMessage "═══════════════════════════════════════════════════════" -Level INFO
}
catch {
    Write-LogMessage "❌ Failed to install service: $($_.Exception.Message)" -Level ERROR
    exit 1
}