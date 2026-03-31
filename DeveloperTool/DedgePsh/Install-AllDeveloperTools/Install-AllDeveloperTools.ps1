Import-Module GlobalFunctions -Force
Import-Module SoftwareUtils -Force

$ErrorActionPreference = "Stop"

try {
    Set-OverrideAppDataFolder -Path (Get-ApplicationDataPath)
    Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_STARTED

    # ── Phase 1: Install all apps (copy from staging, run _install.ps1 if present) ──
    $apps = @(
        "Azure-DevOpsCloneRepositories"
        "Setup-CursorUserSettings"
        "Setup-AllMcpServers"
        "DedgePosLogSearch"
        "Enable-KerberosForBrowser"
        "Azure-NugetVersionPush"
        "Config-CursorAndVsCode"
        "DedgeSign"
        "Push-AllRepos"
        "CompareAllFilesInTwoFolders"
        "VSCode System-Installer"
        "Cursor System-Installer"
        "Ollama.Ollama"
    )

    $failed = @()
    $installedPshApps = @()
    foreach ($app in $apps) {
        try {
            Write-LogMessage "Installing $($app)..." -Level INFO
            Install-OurPshApp -AppName $app
            Write-LogMessage "Installed $($app)" -Level INFO
            $installedPshApps += $app
        }
        catch {
            Write-LogMessage "Failed to install $($app): $($_.Exception.Message)" -Level ERROR -Exception $_
            $failed += $app
        }
    }

    foreach ($app in $installedPshApps) {
        try {
            $localInstallScript = Join-Path "$($env:OptPath)\DedgePshApps\$($app)" "_install.ps1"
            if (Test-Path $localInstallScript -PathType Leaf) {
                Write-LogMessage "Skipping start for $($app) because local _install.ps1 exists: $($localInstallScript)" -Level INFO
                continue
            }

            Write-LogMessage "Starting app $($app) with Start-OurPshApp..." -Level INFO
            Start-OurPshApp $app
            Write-LogMessage "Started app $($app)" -Level INFO
        }
        catch {
            Write-LogMessage "Failed to start $($app): $($_.Exception.Message)" -Level ERROR -Exception $_
            $failed += "$($app) (start)"
        }
    }

    try {
        Install-OurWinApp -AppName "DedgeRemoteConnect"
        Write-LogMessage "Installed DedgeRemoteConnect" -Level INFO
    }
    catch {
        Write-LogMessage "Failed to install DedgeRemoteConnect: $($_.Exception.Message)" -Level ERROR -Exception $_
        $failed += "DedgeRemoteConnect"
    }
    try {
        Install-WindowsApps -AppName "DbExplorer"
        Write-LogMessage "Installed DbExplorer" -Level INFO
    }
    catch {
        Write-LogMessage "Failed to install DbExplorer: $($_.Exception.Message)" -Level ERROR -Exception $_
        $failed += "DbExplorer"
    }

    # ── Phase 2: Run setup scripts that have no _install.ps1 ──
    # MCP servers are handled by Setup-AllMcpServers (started via Start-OurPshApp in Phase 1).
    # Remaining setups: Cursor user settings and Kerberos.
    $setupScripts = @(
        @{ App = "Setup-CursorUserSettings"; Script = "Set-CursorUserSettings.ps1" }
        @{ App = "Enable-KerberosForBrowser"; Script = "Enable-KerberosForBrowser.ps1" }
    )

    $failedSetup = @()
    foreach ($entry in $setupScripts) {
        $appName = $entry.App
        $scriptName = $entry.Script
        $scriptPath = Join-Path "$($env:OptPath)\DedgePshApps\$($appName)" $scriptName

        if ($appName -in $failed) {
            Write-LogMessage "Skipping setup for $($appName) (install failed)" -Level WARN
            $failedSetup += $appName
            continue
        }

        if (-not (Test-Path $scriptPath -PathType Leaf)) {
            Write-LogMessage "Setup script not found: $($scriptPath)" -Level WARN
            $failedSetup += $appName
            continue
        }

        try {
            Write-LogMessage "Running setup: $($appName)\$($scriptName)..." -Level INFO
            & pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath
            if ($LASTEXITCODE -ne 0) {
                throw "Exit code $($LASTEXITCODE)"
            }
            Write-LogMessage "Setup completed: $($appName)" -Level INFO
        }
        catch {
            Write-LogMessage "Setup failed for $($appName): $($_.Exception.Message)" -Level ERROR -Exception $_
            $failedSetup += $appName
        }
    }

    # ── Summary ──
    $totalFailed = $failed.Count + $failedSetup.Count
    if ($totalFailed -gt 0) {
        if ($failed.Count -gt 0) {
            Write-LogMessage "Failed installs ($($failed.Count)): $($failed -join ', ')" -Level ERROR
        }
        if ($failedSetup.Count -gt 0) {
            Write-LogMessage "Failed setups ($($failedSetup.Count)): $($failedSetup -join ', ')" -Level ERROR
        }
        Write-LogMessage "$($MyInvocation.MyCommand.Name) - completed with $($totalFailed) failure(s)" -Level JOB_FAILED
        throw "Some installs or setups failed"
    }

    Write-LogMessage "$($MyInvocation.MyCommand.Name) - all $($apps.Count) apps installed, $($setupScripts.Count) setups executed" -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_FAILED
    exit 1
}
