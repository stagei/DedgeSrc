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
    .\ServerMonitorAgent.ps1 -ExePath "C:\CustomPath\ServerMonitor.exe"
#>

param(
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
    # KILL SERVERMONITOR AGENT PROCESSES (only agent-related, not dashboard)
    # IMPORTANT: Kill TrayIcon FIRST because it might restart the Agent!
    # ServerMonitorTrayIcon = the agent tray app (kill first!)
    # ServerMonitor = the agent service/process
    # ─────────────────────────────────────────────────────────────────────────────
    Write-LogMessage "🛑 Killing ServerMonitor Agent processes..." -Level INFO
    
    # Kill TrayIcon FIRST (it can restart Agent)
    $processesToKill = @("ServerMonitorTrayIcon", "ServerMonitor")
    foreach ($procName in $processesToKill) {
        $procs = Get-Process -Name $procName -ErrorAction SilentlyContinue
        if ($procs) {
            Write-LogMessage "   Killing $procName ($($procs.Count) process(es))..." -Level INFO
            foreach ($proc in $procs) {
                try {
                    $proc.Kill()
                    $proc.WaitForExit(5000)
                    Write-LogMessage "     ✅ Killed PID $($proc.Id)" -Level INFO
                }
                catch {
                    Write-LogMessage "     ⚠️  Could not kill $procName PID $($proc.Id): $($_.Exception.Message)" -Level WARN
                }
            }
        }
    }
    
    # ─────────────────────────────────────────────────────────────────────────────
    # KILL ANY PROCESS USING PORT 8999 (Agent API port)
    # This ensures the port is free for the new service instance
    # ─────────────────────────────────────────────────────────────────────────────
    Write-LogMessage "🔌 Checking for processes using port 8999..." -Level INFO
    try {
        $portConnections = Get-NetTCPConnection -LocalPort 8999 -State Listen -ErrorAction SilentlyContinue
        if ($portConnections) {
            foreach ($conn in $portConnections) {
                $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
                if ($proc) {
                    Write-LogMessage "   Killing $($proc.Name) (PID: $($proc.Id)) listening on port 8999" -Level INFO
                    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Milliseconds 500
                }
            }
        }
        else {
            Write-LogMessage "   Port 8999 is free" -Level INFO
        }
    }
    catch {
        Write-LogMessage "   Could not check port 8999: $($_.Exception.Message)" -Level WARN
    }
    
    # Double-check: Kill any remaining Agent processes by name (excluding Dashboard)
    $remainingProcs = Get-Process -Name "ServerMonitor" -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -notlike "*Dashboard*" }
    if ($remainingProcs) {
        Write-LogMessage "   ⚠️  Found remaining Agent processes, force killing..." -Level WARN
        $remainingProcs | ForEach-Object {
            Write-LogMessage "     Killing $($_.Name) PID $($_.Id)" -Level INFO
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
    }
    
    Start-Sleep -Seconds 2
    Write-LogMessage "   ✅ Process cleanup complete" -Level INFO
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
    # Kill running process if exists
    # ─────────────────────────────────────────────────────────────────────────────
    Write-LogMessage "🛑 Checking for running $ServiceName process..." -Level INFO
    $runningProcs = Get-Process -Name $ServiceName -ErrorAction SilentlyContinue
    if ($runningProcs) {
        Write-LogMessage "   Process $ServiceName is running, killing..." -Level INFO
        $runningProcs | ForEach-Object {
            try {
                $_.Kill()
                $_.WaitForExit(5000)
            }
            catch {
                Write-LogMessage "   ⚠️  Could not kill process $($_.Id): $($_.Exception.Message)" -Level WARN
            }
        }
        Write-LogMessage "   Process killed" -Level INFO
        Start-Sleep -Seconds 2
    }
    else {
        Write-LogMessage "   Process $ServiceName is not running" -Level INFO
    }

    # Verify exe exists (informational only)
    if (Test-Path $ExePath) {
        Write-LogMessage "✅ Executable found: $ExePath" -Level INFO
        try {
            $fileInfo = Get-Item $ExePath -ErrorAction Stop
            Write-LogMessage "   Size: $([math]::Round($fileInfo.Length / 1MB, 2)) MB" -Level INFO
            Write-LogMessage "   Modified: $($fileInfo.LastWriteTime)" -Level INFO
        }
        catch {
            Write-LogMessage "   ⚠️  Could not read file properties: $($_.Exception.Message)" -Level WARN
        }
    }
    else {
        Write-LogMessage "   Executable not found yet (will be deployed by Install-OurWinApp)" -Level INFO
    }

    Write-LogMessage "" -Level INFO

    # ─────────────────────────────────────────────────────────────────────────────
    # REMOVE OLD INSTALLATION FOLDERS (ensures clean deployment)
    # ─────────────────────────────────────────────────────────────────────────────
    Write-LogMessage "🗑️  Removing old installation folders for clean deployment..." -Level INFO
    
    $foldersToRemove = @(
        "$env:OptPath\DedgeWinApps\ServerMonitor",
        "$env:OptPath\DedgeWinApps\ServerMonitorTrayIcon"
    )
    
    foreach ($folder in $foldersToRemove) {
        if (Test-Path $folder) {
            try {
                Write-LogMessage "   Removing: $folder" -Level INFO
                Remove-Item -Path $folder -Recurse -Force -ErrorAction Stop
                Write-LogMessage "   ✅ Removed: $folder" -Level INFO
            }
            catch {
                Write-LogMessage "   ⚠️  Could not remove $($folder): $($_.Exception.Message)" -Level WARN
                # Try to remove individual files
                try {
                    Get-ChildItem -Path $folder -Recurse -Force | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
                    Remove-Item -Path $folder -Force -ErrorAction SilentlyContinue
                }
                catch {
                    Write-LogMessage "   ⚠️  Some files may remain in $folder" -Level WARN
                }
            }
        }
        else {
            Write-LogMessage "   Folder does not exist: $folder (OK)" -Level INFO
        }
    }
    
    Write-LogMessage "" -Level INFO

    # Deploy/update the application files
    Install-OurWinApp -AppName "ServerMonitor"
    
    # After deployment, try to remove service again if it still exists
    $serviceStillExists = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($serviceStillExists) {
        Write-LogMessage "🗑️  Service still exists after deployment, removing..." -Level INFO
        try {
            # Make sure it's stopped
            Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
            
            # Kill any remaining process
            Get-Process -Name $ServiceName -ErrorAction SilentlyContinue | ForEach-Object {
                try { $_.Kill(); $_.WaitForExit(3000) } catch { }
            }
            Start-Sleep -Seconds 1
            
            # Try sc.exe delete
            $scResult = & sc.exe delete $ServiceName 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-LogMessage "   ✅ Service removed" -Level INFO
            }
            else {
                Write-LogMessage "   ⚠️  Could not remove service: $scResult" -Level WARN
                Write-LogMessage "   💡 The service will be recreated with updated settings" -Level INFO
            }
            Start-Sleep -Seconds 2
        }
        catch {
            Write-LogMessage "   ⚠️  Error during service removal: $($_.Exception.Message)" -Level WARN
        }
    }     

    # ─────────────────────────────────────────────────────────────────────────────
    # TRAY ICON: Disable scheduled task first to prevent auto-restart during install
    # ─────────────────────────────────────────────────────────────────────────────
    $trayIconProcessName = "ServerMonitorTrayIcon"
    $taskName = "ServerMonitorTrayIcon"
    
    Write-LogMessage "⏸️  Disabling ServerMonitorTrayIcon scheduled task to prevent restart..." -Level INFO
    try {
        $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($existingTask -and $existingTask.State -ne 'Disabled') {
            Disable-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue | Out-Null
            Write-LogMessage "   ✅ Scheduled task disabled" -Level INFO
        }
    }
    catch {
        Write-LogMessage "   ⚠️  Could not disable task: $($_.Exception.Message)" -Level WARN
    }

    # Remove old Registry Run key if present (cleanup from previous installs)
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    Remove-ItemProperty -Path $regPath -Name $taskName -ErrorAction SilentlyContinue

    # ─────────────────────────────────────────────────────────────────────────────
    # TRAY ICON: Kill ALL running instances (by name and by exe path)
    # ─────────────────────────────────────────────────────────────────────────────
    Write-LogMessage "🛑 Killing all ServerMonitorTrayIcon processes..." -Level INFO
    
    $trayProcs = Get-Process -Name $trayIconProcessName -ErrorAction SilentlyContinue
    if ($trayProcs) {
        Write-LogMessage "   Found $($trayProcs.Count) running instance(s)" -Level INFO
        foreach ($proc in $trayProcs) {
            try {
                Write-LogMessage "   Killing PID $($proc.Id)..." -Level INFO
                $proc.Kill()
                $proc.WaitForExit(10000)
                Write-LogMessage "   ✅ PID $($proc.Id) terminated" -Level INFO
            }
            catch {
                Write-LogMessage "   ⚠️  Could not kill PID $($proc.Id): $($_.Exception.Message)" -Level WARN
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            }
        }
    }
    else {
        Write-LogMessage "   No running instances found" -Level INFO
    }

    # Verify all instances are dead (retry with taskkill as fallback)
    Start-Sleep -Seconds 1
    $remaining = Get-Process -Name $trayIconProcessName -ErrorAction SilentlyContinue
    if ($remaining) {
        Write-LogMessage "   ⚠️  $($remaining.Count) instance(s) still running, using taskkill /F..." -Level WARN
        & taskkill.exe /F /IM "$($trayIconProcessName).exe" 2>&1 | Out-Null
        Start-Sleep -Seconds 2
        
        $stillRunning = Get-Process -Name $trayIconProcessName -ErrorAction SilentlyContinue
        if ($stillRunning) {
            Write-LogMessage "   ❌ Could not kill all instances - install may have file lock issues" -Level ERROR
        }
        else {
            Write-LogMessage "   ✅ All instances terminated via taskkill" -Level INFO
        }
    }
    
    Write-LogMessage "   ✅ Process cleanup complete" -Level INFO
    Write-LogMessage "" -Level INFO

    # ─────────────────────────────────────────────────────────────────────────────
    # TRAY ICON: Deploy application files
    # ─────────────────────────────────────────────────────────────────────────────
    Install-OurWinApp -AppName "ServerMonitorTrayIcon" -DisplayName "Server Monitor Tray App"

    $trayIconPath = "$env:OptPath\DedgeWinApps\ServerMonitorTrayIcon\ServerMonitorTrayIcon.exe"
    $trayIconIconPath = "$env:OptPath\DedgeWinApps\ServerMonitorTrayIcon\dedge.ico"

    # ─────────────────────────────────────────────────────────────────────────────
    # TRAY ICON: Remove ALL old shortcuts before creating new ones
    # Covers All Users, Current User, and OneDrive desktop locations
    # ─────────────────────────────────────────────────────────────────────────────
    Write-LogMessage "🗑️  Removing old ServerMonitorTrayIcon shortcuts..." -Level INFO
    
    $shortcutName = "Server Monitor Tray.lnk"
    $altShortcutName = "Server Monitor Tray App.lnk"
    
    $shortcutLocations = @(
        # All Users locations
        (Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) $shortcutName)
        (Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) $altShortcutName)
        (Join-Path ([Environment]::GetFolderPath('CommonStartMenu')) "Programs\ServerMonitor\$shortcutName")
        (Join-Path ([Environment]::GetFolderPath('CommonStartMenu')) "Programs\ServerMonitor\$altShortcutName")
        # Current User locations
        (Join-Path ([Environment]::GetFolderPath('Desktop')) $shortcutName)
        (Join-Path ([Environment]::GetFolderPath('Desktop')) $altShortcutName)
        (Join-Path ([Environment]::GetFolderPath('StartMenu')) "Programs\ServerMonitor\$shortcutName")
        (Join-Path ([Environment]::GetFolderPath('StartMenu')) "Programs\ServerMonitor\$altShortcutName")
        (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\ServerMonitor\$shortcutName")
        (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\ServerMonitor\$altShortcutName")
        (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\ServerMonitorTrayIcon\$altShortcutName")
    )
    
    # Also check OneDrive desktop (Norwegian "Skrivebord" and English "Desktop")
    $oneDrivePaths = @($env:OneDrive, $env:OneDriveCommercial, $env:OneDriveConsumer) | Where-Object { $_ }
    foreach ($od in $oneDrivePaths) {
        $shortcutLocations += (Join-Path $od "Skrivebord\$shortcutName")
        $shortcutLocations += (Join-Path $od "Skrivebord\$altShortcutName")
        $shortcutLocations += (Join-Path $od "Desktop\$shortcutName")
        $shortcutLocations += (Join-Path $od "Desktop\$altShortcutName")
    }
    
    foreach ($lnkPath in $shortcutLocations) {
        if (Test-Path $lnkPath) {
            Remove-Item -Path $lnkPath -Force -ErrorAction SilentlyContinue
            Write-LogMessage "   Removed: $lnkPath" -Level INFO
        }
    }

    # ─────────────────────────────────────────────────────────────────────────────
    # TRAY ICON: Create fresh shortcuts with correct icon
    # ─────────────────────────────────────────────────────────────────────────────
    Write-LogMessage "🔗 Creating shortcuts for Server Monitor Tray..." -Level INFO
    
    # Resolve the icon: prefer dedge.ico, fall back to exe itself
    if (Test-Path $trayIconIconPath) {
        $resolvedIconLocation = "$($trayIconIconPath),0"
        Write-LogMessage "   Icon source: $trayIconIconPath" -Level INFO
    }
    else {
        $resolvedIconLocation = "$($trayIconPath),0"
        Write-LogMessage "   ⚠️  dedge.ico not found, using exe icon: $trayIconPath" -Level WARN
    }
    
    try {
        $shell = New-Object -ComObject WScript.Shell
        
        # Desktop shortcut (All Users)
        $desktopPath = [Environment]::GetFolderPath('CommonDesktopDirectory')
        $desktopShortcut = Join-Path $desktopPath $shortcutName
        $shortcut = $shell.CreateShortcut($desktopShortcut)
        $shortcut.TargetPath = $trayIconPath
        $shortcut.WorkingDirectory = Split-Path $trayIconPath
        $shortcut.Description = "Server Monitor Tray Application"
        $shortcut.IconLocation = $resolvedIconLocation
        $shortcut.Save()
        # Set "Run as Administrator" flag (byte 0x15 bit 0x20)
        $bytes = [System.IO.File]::ReadAllBytes($desktopShortcut)
        $bytes[0x15] = $bytes[0x15] -bor 0x20
        [System.IO.File]::WriteAllBytes($desktopShortcut, $bytes)
        Write-LogMessage "   ✅ Desktop shortcut: $desktopShortcut" -Level INFO
        
        # Start Menu shortcut (All Users - in ServerMonitor folder)
        $startMenuPath = [Environment]::GetFolderPath('CommonStartMenu')
        $programsPath = Join-Path $startMenuPath "Programs\ServerMonitor"
        if (-not (Test-Path $programsPath)) { New-Item -Path $programsPath -ItemType Directory -Force | Out-Null }
        $startMenuShortcut = Join-Path $programsPath $shortcutName
        $shortcut = $shell.CreateShortcut($startMenuShortcut)
        $shortcut.TargetPath = $trayIconPath
        $shortcut.WorkingDirectory = Split-Path $trayIconPath
        $shortcut.Description = "Server Monitor Tray Application"
        $shortcut.IconLocation = $resolvedIconLocation
        $shortcut.Save()
        # Set "Run as Administrator" flag
        $bytes = [System.IO.File]::ReadAllBytes($startMenuShortcut)
        $bytes[0x15] = $bytes[0x15] -bor 0x20
        [System.IO.File]::WriteAllBytes($startMenuShortcut, $bytes)
        Write-LogMessage "   ✅ Start Menu shortcut: $startMenuShortcut" -Level INFO
        
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
    }
    catch {
        Write-LogMessage "   ❌ Could not create shortcuts: $($_.Exception.Message)" -Level ERROR
    }
    
    # Verify shortcuts have the correct icon
    Write-LogMessage "🔍 Verifying shortcut icons..." -Level INFO
    try {
        $verifyShell = New-Object -ComObject WScript.Shell
        foreach ($lnk in @($desktopShortcut, $startMenuShortcut)) {
            if (Test-Path $lnk) {
                $sc = $verifyShell.CreateShortcut($lnk)
                if ($sc.IconLocation -and $sc.IconLocation -ne ',0' -and $sc.IconLocation -ne '') {
                    Write-LogMessage "   ✅ $([System.IO.Path]::GetFileName($lnk)): Icon=$($sc.IconLocation)" -Level INFO
                }
                else {
                    Write-LogMessage "   ⚠️  $([System.IO.Path]::GetFileName($lnk)): Icon not set, reapplying..." -Level WARN
                    $sc.IconLocation = $resolvedIconLocation
                    $sc.Save()
                    Write-LogMessage "   ✅ Icon reapplied: $resolvedIconLocation" -Level INFO
                }
            }
        }
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($verifyShell) | Out-Null
    }
    catch {
        Write-LogMessage "   ⚠️  Icon verification failed: $($_.Exception.Message)" -Level WARN
    }

    # ─────────────────────────────────────────────────────────────────────────────
    # TRAY ICON: Configure auto-start on login (HKLM Run key + Scheduled Task)
    # HKLM Run key is primary (reliable, starts for all users).
    # Scheduled Task is secondary (elevated, delayed start).
    # ─────────────────────────────────────────────────────────────────────────────
    Write-LogMessage "📋 Configuring auto-start for ServerMonitorTrayIcon..." -Level INFO
    
    # Primary: HKLM Run key (starts for all users on login)
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" `
            -Name "Server Monitor Tray" -Value $trayIconPath -Type String -ErrorAction Stop
        Write-LogMessage "   ✅ HKLM Run key set: Server Monitor Tray" -Level INFO
    }
    catch {
        Write-LogMessage "   ⚠️  Could not set HKLM Run key: $($_.Exception.Message)" -Level WARN
    }

    # Clean up old HKCU Run key if present (superseded by HKLM)
    Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" `
        -Name $taskName -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" `
        -Name "Server Monitor Tray" -ErrorAction SilentlyContinue

    # Secondary: Scheduled Task (runs elevated with delay)
    try {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        
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
    }
    catch {
        Write-LogMessage "   ❌ Failed to create Scheduled Task: $($_.Exception.Message)" -Level ERROR
    }
    
    # Start the tray icon application
    Write-LogMessage "🚀 Starting ServerMonitorTrayIcon..." -Level INFO
    Start-Process -FilePath $trayIconPath
    Write-LogMessage "✅ ServerMonitorTrayIcon started" -Level INFO

    # Test run the executable to verify it works
    Write-LogMessage "🧪 Testing executable before service creation..." -Level INFO
    $exeDir = Split-Path -Parent $ExePath
    Write-LogMessage "   Working Directory: $exeDir" -Level INFO

    # Check if appsettings.json exists in the same directory
    $appsettingsPath = Join-Path $exeDir "appsettings.json"
    if (-not (Test-Path $appsettingsPath)) {
        Write-LogMessage "   ❌ ERROR: appsettings.json not found in $exeDir" -Level ERROR
        Write-LogMessage "   💡 The application REQUIRES appsettings.json to start" -Level WARN
        Write-LogMessage "   💡 Check that the file was deployed with the executable" -Level WARN
        Write-LogMessage "" -Level INFO
        Write-LogMessage "   Files in directory:" -Level INFO
        Get-ChildItem $exeDir -File | Select-Object Name | Format-Table -AutoSize
        Write-LogMessage "   ❌ Cannot proceed without appsettings.json" -Level ERROR
        throw "Cannot proceed without appsettings.json"
    }
    else {
        Write-LogMessage "   ✅ appsettings.json found" -Level INFO
    }

    # Check for other required files
    $requiredFiles = @("NLog.config", "ScheduledTaskExitCodes.json")
    foreach ($file in $requiredFiles) {
        $filePath = Join-Path $exeDir $file
        if (Test-Path $filePath) {
            Write-LogMessage "   ✅ $file found" -Level INFO
        }
        else {
            Write-LogMessage "   ⚠️  $file not found (may be optional)" -Level WARN
        }
    }

    # Update ExePath after deployment (Install-OurWinApp may have copied to standard location)
    # Re-resolve the path in case it changed
    $resolvedExePath = "$env:OptPath\DedgeWinApps\$ServiceName\$ServiceName.exe"
    if (Test-Path $resolvedExePath) {
        $ExePath = $resolvedExePath
        $exeDir = Split-Path -Parent $ExePath
        Write-LogMessage "   Updated executable path: $ExePath" -Level INFO
    }

    # Create the service with working directory (always done manually)
    $serviceCreationMsg = @"
 📦 Creating Windows Service...
    Service Name: $ServiceName
    Executable: $ExePath
    Working Directory: $exeDir
"@
    Write-LogMessage $serviceCreationMsg -Level INFO

    # Get current user and create credentials
    $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $currentUser = $currentIdentity.Name
    
    # Ensure domain is DEDGE
    if ($currentUser.Contains('\')) {
        $userParts = $currentUser.Split('\')
        $domain = $userParts[0]
        $username = $userParts[1]
    }
    else {
        # If no domain, assume it's the username and add DEDGE domain
        $domain = "DEDGE"
        $username = $currentUser
    }
    
    # Format as DEDGE\username
    $serviceAccount = "$domain\$username"
    Write-LogMessage "   Service Account: $serviceAccount" -Level INFO
    
    # Get password using the function
    Write-LogMessage "   Retrieving password..." -Level INFO
    try {
        $password = Get-SecureStringUserPasswordAsPlainText
        if ([string]::IsNullOrWhiteSpace($password)) {
            throw "Password retrieval returned empty value"
        }
        Write-LogMessage "   ✅ Password retrieved" -Level INFO
    }
    catch {
        Write-LogMessage "❌ Failed to retrieve password: $($_.Exception.Message)" -Level ERROR
        throw "Failed to retrieve password: $($_.Exception.Message)"
    }
    
    # Create credential object
    $securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($serviceAccount, $securePassword)
    
    # Use absolute path
    $absoluteExePath = [System.IO.Path]::GetFullPath($ExePath)

    # Check if service already exists (couldn't be removed earlier)
    $existingServiceCheck = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    
    if ($existingServiceCheck) {
        # Service still exists - update its configuration instead of creating new
        Write-LogMessage "   ⚠️  Service already exists, updating configuration..." -Level WARN
        try {
            # Update the service binary path and credentials using sc.exe
            $escapedPath = $absoluteExePath -replace '"', '\"'
            & sc.exe config $ServiceName binPath= "`"$escapedPath`"" 2>&1 | Out-Null
            & sc.exe config $ServiceName start= delayed-auto 2>&1 | Out-Null
            Write-LogMessage "   ✅ Service configuration updated" -Level INFO
        }
        catch {
            Write-LogMessage "   ⚠️  Could not update service config: $($_.Exception.Message)" -Level WARN
        }
    }
    else {
        # Create service using New-Service with credentials
        Write-LogMessage "   Creating service with credentials..." -Level INFO
        try {
            $null = New-Service -Name $ServiceName `
                -BinaryPathName $absoluteExePath `
                -DisplayName $DisplayName `
                -Description $Description `
                -StartupType Automatic `
                -Credential $credential `
                -ErrorAction Stop
            
            Write-LogMessage "✅ Service created with account: $serviceAccount" -Level INFO
        }
        catch {
            Write-LogMessage "❌ Failed to create service: $($_.Exception.Message)" -Level ERROR
            Write-LogMessage "   Error details: $_" -Level ERROR
            throw "Failed to create service: $($_.Exception.Message)"
        }
    }

    # Set working directory for the service (important for finding config files)
    Write-LogMessage "📁 Setting service working directory..." -Level INFO
    # Note: Windows services don't directly support setting a working directory via PowerShell cmdlets
    # The application uses AppContext.BaseDirectory which resolves to the executable's directory
    Write-LogMessage "✅ Working directory will be: $exeDir (exe location)`n" -Level INFO

    # Service description is already set via New-Service, but we can verify it
    Write-LogMessage "📝 Verifying service description..." -Level INFO
    $service = Get-Service -Name $ServiceName -ErrorAction Stop
    Write-LogMessage "   Service created: $($service.DisplayName)" -Level INFO

    # Configure service to restart on failure
    # Note: Using sc.exe for failure actions as it's the most reliable method and doesn't involve password escaping
    Write-LogMessage "🔄 Configuring auto-restart on failure..." -Level INFO
    try {
        # Configure failure actions: Restart service after 60 seconds (60000 ms) for first, second, and third failures
        # Reset counter after 86400 seconds (24 hours)
        $failureResult = & sc.exe failure $ServiceName reset= 86400 actions= restart/60000/restart/60000/restart/60000 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-LogMessage "✅ Auto-restart configured: Restart after 1 minute on failure" -Level INFO
        }
        else {
            Write-LogMessage "❌ Failed to configure auto-restart: $failureResult" -Level ERROR
            throw "sc.exe failure command failed with exit code $LASTEXITCODE"
        }
    }
    catch {
        Write-LogMessage "❌ Failed to configure auto-restart: $($_.Exception.Message)" -Level ERROR
        Write-LogMessage "   The service will not automatically restart on failure" -Level WARN
    }

    # Configure service recovery flag using registry
    Write-LogMessage "⚙️  Configuring service recovery options..." -Level INFO
    try {
        $serviceRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
        if (Test-Path $serviceRegPath) {
            # Set FailureFlag to 1 (enable failure actions)
            Set-ItemProperty -Path $serviceRegPath -Name "FailureFlag" -Value 1 -Type DWord -ErrorAction Stop
            Write-LogMessage "✅ Failure flag configured" -Level INFO
        }
        else {
            throw "Service registry path not found: $serviceRegPath"
        }
    }
    catch {
        Write-LogMessage "⚠️  Warning: Could not set failure flag: $($_.Exception.Message)" -Level WARN
    }

    # Set delayed auto start using registry
    Write-LogMessage "⏰ Setting delayed auto-start..." -Level INFO
    try {
        $serviceRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
        if (Test-Path $serviceRegPath) {
            # Set DelayedAutoStart to 1 (enable delayed auto-start)
            Set-ItemProperty -Path $serviceRegPath -Name "DelayedAutoStart" -Value 1 -Type DWord -ErrorAction Stop
            Write-LogMessage "✅ Service will start automatically after system boot (delayed)`n" -Level INFO
        }
        else {
            throw "Service registry path not found: $serviceRegPath"
        }
    }
    catch {
        Write-LogMessage "⚠️  Warning: Could not set delayed auto-start: $($_.Exception.Message)" -Level WARN
        Write-LogMessage "   Service will start automatically (not delayed)`n" -Level WARN
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

    # ─────────────────────────────────────────────────────────────────────────────
    # FINAL CLEANUP: Kill ALL Agent processes before starting service
    # This is the last chance to ensure nothing is blocking port 8999
    # ─────────────────────────────────────────────────────────────────────────────
    Write-LogMessage "🔌 Final cleanup before starting service..." -Level INFO
    
    # Kill all Agent processes one more time (excluding Dashboard)
    Get-Process -Name "ServerMonitor" -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -notlike "*Dashboard*" } |
        ForEach-Object {
            Write-LogMessage "   Killing $($_.Name) PID $($_.Id)" -Level WARN
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
    
    # Ensure port 8999 is free
    $maxPortWait = 10
    $portWaitCount = 0
    while ($portWaitCount -lt $maxPortWait) {
        $portInUse = Get-NetTCPConnection -LocalPort 8999 -State Listen -ErrorAction SilentlyContinue
        if (-not $portInUse) {
            Write-LogMessage "   ✅ Port 8999 is free" -Level INFO
            break
        }
        
        # Kill the process using the port
        foreach ($conn in $portInUse) {
            $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
            if ($proc) {
                Write-LogMessage "   Killing $($proc.Name) (PID: $($proc.Id)) using port 8999..." -Level WARN
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            }
        }
        
        $portWaitCount++
        Start-Sleep -Seconds 1
    }
    
    if ($portWaitCount -ge $maxPortWait) {
        Write-LogMessage "   ⚠️  Port 8999 may still be in use - service may fail to start" -Level WARN
    }
    
    # Wait for sockets to fully release
    Start-Sleep -Seconds 2

    # ─────────────────────────────────────────────────────────────────────────────
    # Start the service (with retry mechanism)
    # ─────────────────────────────────────────────────────────────────────────────
    Write-LogMessage "🚀 Starting $ServiceName service..." -Level INFO
    $maxRetries = 3
    $retryCount = 0
    $serviceStarted = $false
    
    while ($retryCount -lt $maxRetries -and -not $serviceStarted) {
        try {
            Start-Service -Name $ServiceName -ErrorAction Stop
            $serviceStarted = $true
            Write-LogMessage "✅ $ServiceName service started" -Level INFO
        }
        catch {
            $retryCount++
            if ($retryCount -lt $maxRetries) {
                Write-LogMessage "   ⚠️  Start attempt $retryCount failed, retrying in 3 seconds..." -Level WARN
                Start-Sleep -Seconds 3
                
                # Kill any process that may have grabbed the port
                $portInUse = Get-NetTCPConnection -LocalPort 8999 -State Listen -ErrorAction SilentlyContinue
                if ($portInUse) {
                    foreach ($conn in $portInUse) {
                        $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
                        if ($proc) {
                            Write-LogMessage "   Killing $($proc.Name) (PID: $($proc.Id)) blocking port 8999" -Level WARN
                            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                        }
                    }
                    Start-Sleep -Seconds 2
                }
            }
            else {
                Write-LogMessage "❌ Failed to start service after $maxRetries attempts: $($_.Exception.Message)" -Level ERROR
                Write-LogMessage "`n🔍 Diagnosing issue..." -Level WARN
            
                # Check if executable exists
                if (-not (Test-Path $ExePath)) {
                    Write-LogMessage "   ❌ Executable not found: $ExePath" -Level ERROR
                    Write-LogMessage "   💡 Check that the path is correct and the file exists" -Level WARN
                }
                else {
                    Write-LogMessage "   ✅ Executable exists: $ExePath" -Level INFO
                }
            
                # Check service configuration
                $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
                if ($service) {
                    Write-LogMessage "   Service Name: $($service.Name)" -Level INFO
                    Write-LogMessage "   Service Status: $($service.Status)" -Level INFO
                    Write-LogMessage "   Service StartType: $($service.StartType)" -Level INFO
                }
            
                # Check event log for errors
                Write-LogMessage "`n📋 Checking Windows Event Log for errors..." -Level INFO
                $events = Get-EventLog -LogName Application -Source "ServerMonitor" -Newest 5 -ErrorAction SilentlyContinue
                if ($events) {
                    Write-LogMessage "   Recent ServerMonitor events:" -Level INFO
                    $events | ForEach-Object {
                        Write-LogMessage "   [$($_.TimeGenerated)] $($_.EntryType): $($_.Message)" -Level $(if ($_.EntryType -eq 'Error') { "ERROR" } else { "WARN" })
                    }
                }
                else {
                    Write-LogMessage "   No ServerMonitor events found in Application log" -Level INFO
                }
            
                # Check System event log for service errors
                $serviceEvents = Get-EventLog -LogName System -Source "Service Control Manager" -Newest 5 -ErrorAction SilentlyContinue | 
                Where-Object { $_.Message -like "*ServerMonitor*" }
                if ($serviceEvents) {
                    Write-LogMessage "`n   Service Control Manager events:" -Level INFO
                    $serviceEvents | ForEach-Object {
                        Write-LogMessage "   [$($_.TimeGenerated)] $($_.EntryType): $($_.Message)" -Level $(if ($_.EntryType -eq 'Error') { "ERROR" } else { "WARN" })
                    }
                }
            
                # Try to get more details using PowerShell
                Write-LogMessage "`n📋 Service configuration details:" -Level INFO
                try {
                    $serviceDetails = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop
                    Write-LogMessage "   Name: $($serviceDetails.Name)" -Level INFO
                    Write-LogMessage "   DisplayName: $($serviceDetails.DisplayName)" -Level INFO
                    Write-LogMessage "   PathName: $($serviceDetails.PathName)" -Level INFO
                    Write-LogMessage "   StartMode: $($serviceDetails.StartMode)" -Level INFO
                    Write-LogMessage "   State: $($serviceDetails.State)" -Level INFO
                    Write-LogMessage "   StartName: $($serviceDetails.StartName)" -Level INFO
                }
                catch {
                    Write-LogMessage "   Could not retrieve service details: $($_.Exception.Message)" -Level WARN
                }
            
                $troubleshootingTips = @"
💡 Troubleshooting tips:
   1. Check if the executable path is correct: $ExePath
   2. Verify the executable has proper permissions
   3. Ensure appsettings.json exists in: $(Split-Path -Parent $ExePath)
   4. Check application logs in: C:\opt\data\ServerMonitor\
   5. Try running manually: cd "$(Split-Path -Parent $ExePath)" ; .\ServerMonitor.exe
   6. Check Windows Event Viewer > Windows Logs > Application
   7. Verify .NET 10 runtime is available (if not self-contained)
"@
                Write-LogMessage $troubleshootingTips -Level WARN
            }
        }
    }

    # Verify service status and display summary
    Start-Sleep -Seconds 2
    $service = Get-Service -Name $ServiceName
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