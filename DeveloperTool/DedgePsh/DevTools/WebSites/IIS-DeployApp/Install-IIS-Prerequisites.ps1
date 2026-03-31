<#
.SYNOPSIS
    Installs IIS and all prerequisites required to run IIS-DeployApp.ps1.

.DESCRIPTION
    Automatically detects what is already installed and only installs what is missing.
    No parameters or prompts required — fully unattended.

    Installs:
      1. IIS Windows Features (via DISM Get-WindowsOptionalFeature)
      2. ASP.NET Core Hosting Bundle   (provides AspNetCoreModuleV2 for AspNetCore app pools)
      3. URL Rewrite Module            (required for some proxy scenarios)

    Run once on a fresh Windows Server before IIS-DeployApp.ps1.
    Must be executed as Administrator.
#>

Import-Module GlobalFunctions -Force

try {
    Write-LogMessage "Install-IIS-Prerequisites started" -Level JOB_STARTED

    # ── Admin check ──────────────────────────────────────────────────────────
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-LogMessage "Script must run as Administrator" -Level ERROR
        exit 1
    }

    $dism      = "$env:SystemRoot\System32\Dism.exe"
    $rebootNeeded = $false

    # ── Helper: enable a single Windows optional feature if not already enabled ──
    function Enable-IISFeature {
        param([string]$FeatureName)
        $state = (Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction SilentlyContinue).State
        if ($state -eq "Enabled") {
            Write-LogMessage "  [OK]   $($FeatureName)" -Level INFO
            return
        }
        Write-LogMessage "  [INST] $($FeatureName) (state: $($state))" -Level INFO
        $result = & $dism /Online /Enable-Feature /FeatureName:$FeatureName /All /NoRestart 2>&1
        if ($LASTEXITCODE -eq 3010) {
            Write-LogMessage "  [REBOOT REQUIRED] $($FeatureName)" -Level WARN
            $script:rebootNeeded = $true
        }
        elseif ($LASTEXITCODE -ne 0) {
            Write-LogMessage "  [WARN] $($FeatureName) exit $($LASTEXITCODE): $($result)" -Level WARN
        }
    }

    # ── Step 1: IIS Windows Features ─────────────────────────────────────────
    Write-LogMessage "Step 1: IIS Windows Features" -Level INFO

    $iisFeatures = @(
        "IIS-WebServerRole",            # Core IIS role
        "IIS-WebServer",                # Web Server
        "IIS-CommonHttpFeatures",       # Parent: Default doc, static content
        "IIS-DefaultDocument",          # Default document
        "IIS-StaticContent",            # Serve HTML/CSS/JS (Static app type in IIS-DeployApp)
        "IIS-HttpRedirect",             # Redirect (DefaultWebSite → /DedgeAuth/)
        "IIS-ApplicationDevelopment",   # Parent for CGI/ISAPI
        "IIS-CGI",                      # Required by .NET Hosting Bundle installer
        "IIS-ISAPIExtensions",          # ISAPI extensions
        "IIS-ISAPIFilter",              # ISAPI filters
        "IIS-HttpLogging",              # HTTP request logging
        "IIS-HttpCompressionStatic",    # Static content compression
        "IIS-RequestFiltering",         # Request filtering (security baseline)
        "IIS-ManagementConsole",        # IIS Manager UI
        "IIS-ManagementService",        # Remote IIS management
        "NetFx4Extended-ASPNET45"       # .NET 4.x ASPNET registration
    )

    foreach ($feature in $iisFeatures) {
        Enable-IISFeature -FeatureName $feature
    }

    # ── Step 2: ASP.NET Core Hosting Bundle ───────────────────────────────────
    # Provides AspNetCoreModuleV2 (ANCM) — mandatory for AspNetCore app pools.
    # Must be installed AFTER IIS features are enabled.
    # Uses SoftwareUtils Install-WingetPackage (HostingBundle.10/9/8); paths from Get-WingetAppsPath.
    # ANCM installs to "C:\Program Files\IIS\Asp.Net Core Module\V2\aspnetcorev2.dll" (not inetsrv).
    Write-LogMessage "Step 2: ASP.NET Core Hosting Bundle (AspNetCoreModuleV2)" -Level INFO

    $ancmPaths = @(
        "$env:ProgramFiles\IIS\Asp.Net Core Module\V2\aspnetcorev2.dll",
        "${env:ProgramFiles(x86)}\IIS\Asp.Net Core Module\V2\aspnetcorev2.dll",
        "$($env:SystemRoot)\System32\inetsrv\aspnetcorev2.dll"
    )
    $ancmDll = $ancmPaths | Where-Object { Test-Path $_ -PathType Leaf } | Select-Object -First 1

    if ($ancmDll) {
        Write-LogMessage "  [OK]   AspNetCoreModuleV2 already installed at $($ancmDll)" -Level INFO
    }
    else {
        Write-LogMessage "  [INST] AspNetCoreModuleV2 not found — installing Hosting Bundle via Install-WingetPackage..." -Level INFO
        Import-Module SoftwareUtils -Force -ErrorAction SilentlyContinue
        $hostingBundleApps = @("Microsoft.DotNet.HostingBundle.10", "Microsoft.DotNet.HostingBundle.9", "Microsoft.DotNet.HostingBundle.8")
        $downloaded = @(Get-DownloadedWingetPackages)
        $installed = $false
        foreach ($appName in $hostingBundleApps) {
            if ($downloaded -notcontains $appName) {
                continue
            }
            $null = Install-WingetPackage -AppName $appName -Force
            $ancmDll = $ancmPaths | Where-Object { Test-Path $_ -PathType Leaf } | Select-Object -First 1
            if ($ancmDll) {
                Write-LogMessage "  [OK]   Hosting Bundle installed from $($appName) — ANCM at $($ancmDll)" -Level INFO
                $installed = $true
                break
            }
        }
        if (-not $installed) {
            Write-LogMessage "  [WARN] Hosting Bundle not installed. Ensure one of $($hostingBundleApps -join ', ') exists under Get-WingetAppsPath." -Level WARN
            Write-LogMessage "  Download from https://dotnet.microsoft.com/download/dotnet and place under WingetApps." -Level WARN
        }
    }

    # ── Step 3: URL Rewrite Module ────────────────────────────────────────────
    # Resolve installer via Get-WingetAppsPath/Get-DownloadedWingetPackages or Get-SoftwarePath (WindowsApps).
    Write-LogMessage "Step 3: URL Rewrite Module" -Level INFO

    $rewriteKey = "HKLM:\SOFTWARE\Microsoft\IIS Extensions\URL Rewrite"
    if (Test-Path $rewriteKey) {
        Write-LogMessage "  [OK]   URL Rewrite Module already installed" -Level INFO
    }
    else {
        Write-LogMessage "  [INST] URL Rewrite not found — installing..." -Level INFO
        Import-Module SoftwareUtils -Force -ErrorAction SilentlyContinue
        $rewriteMsi = $null
        $wingetPath = Get-WingetAppsPath
        $downloaded = @(Get-DownloadedWingetPackages)
        $rewriteFolders = $downloaded | Where-Object { $_ -match "Rewrite|URL" }
        foreach ($folder in $rewriteFolders) {
            $dir = Join-Path $wingetPath $folder
            $msi = Get-ChildItem -Path $dir -Filter "rewrite*.msi" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($msi) {
                $rewriteMsi = $msi.FullName
                break
            }
        }
        if (-not $rewriteMsi) {
            $softwarePath = Get-SoftwarePath
            $rewriteMsi = Join-Path $softwarePath "WindowsApps\iis-url-rewrite\rewrite_amd64_en-US.msi"
        }

        if ($rewriteMsi -and (Test-Path $rewriteMsi)) {
            Write-LogMessage "  Installing from: $($rewriteMsi)" -Level INFO
            $proc = Start-Process -FilePath "msiexec.exe" `
                -ArgumentList "/i `"$rewriteMsi`" /quiet /norestart" `
                -Wait -PassThru
            if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
                Write-LogMessage "  [OK]   URL Rewrite Module installed (exit: $($proc.ExitCode))" -Level INFO
            }
            else {
                Write-LogMessage "  [WARN] URL Rewrite exit code: $($proc.ExitCode)" -Level WARN
            }
        }
        else {
            Write-LogMessage "  [WARN] URL Rewrite installer not found (WingetApps or WindowsApps\iis-url-rewrite). Use Get-SoftwarePath / Get-WingetAppsPath." -Level WARN
        }
    }

    # ── Step 4: Verify ────────────────────────────────────────────────────────
    Write-LogMessage "Step 4: Verification" -Level INFO

    $appcmd = "$env:SystemRoot\System32\inetsrv\appcmd.exe"
    if (Test-Path $appcmd) {
        Write-LogMessage "  [OK]   appcmd.exe found" -Level INFO
    }
    else {
        Write-LogMessage "  [FAIL] appcmd.exe not found — IIS did not install correctly" -Level ERROR
    }

    $ancmDll = $ancmPaths | Where-Object { Test-Path $_ -PathType Leaf } | Select-Object -First 1
    if ($ancmDll) {
        Write-LogMessage "  [OK]   aspnetcorev2.dll found at $($ancmDll)" -Level INFO
    }
    else {
        Write-LogMessage "  [WARN] aspnetcorev2.dll not found in any known location — install .NET Hosting Bundle manually" -Level WARN
    }

    # ── Step 5: WingetApps software (presence only) ─────────────────────────────
    # Uses Get-DownloadedWingetPackages from SoftwareUtils (reads Get-WingetAppsPath).
    Write-LogMessage "Step 5: WingetApps software (presence check)" -Level INFO
    $downloaded = @(Get-DownloadedWingetPackages)
    $desiredWinget = @(
        "Microsoft.DotNet.SDK.8", "Microsoft.DotNet.SDK.9", "Microsoft.DotNet.SDK.10",
        "Microsoft.DotNet.AspNetCore.8", "Microsoft.DotNet.AspNetCore.9", "Microsoft.DotNet.AspNetCore.10",
        "Microsoft.DotNet.Framework.DeveloperPack_4",
        "Microsoft.DotNet.HostingBundle.8", "Microsoft.DotNet.HostingBundle.9", "Microsoft.DotNet.HostingBundle.10",
        "Microsoft.DotNet.Runtime.8", "Microsoft.DotNet.Runtime.9", "Microsoft.DotNet.Runtime.10"
    )
    foreach ($folder in $desiredWinget) {
        if ($downloaded -contains $folder) {
            Write-LogMessage "  [OK]   $($folder)" -Level INFO
        }
        else {
            Write-LogMessage "  [MISS] $($folder)" -Level WARN
        }
    }

    if ($rebootNeeded) {
        Write-LogMessage "A reboot is required to complete the installation. Please restart and run IIS-DeployApp.ps1 after reboot." -Level WARN
    }
    elseif (Test-Path $ancmDll) {
        Write-LogMessage "All prerequisites installed. Ready to run IIS-DeployApp.ps1." -Level INFO
    }
    else {
        Write-LogMessage "Prerequisites run complete. Install x64 Hosting Bundle and URL Rewrite as needed (see warnings above), then run IIS-DeployApp.ps1." -Level WARN
    }

    Write-LogMessage "Install-IIS-Prerequisites" -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Install-IIS-Prerequisites failed: $($_.Exception.Message)" -Level ERROR
    Write-LogMessage "Install-IIS-Prerequisites" -Level JOB_FAILED -Exception $_
    exit 1
}
