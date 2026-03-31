<#
.SYNOPSIS
    Uninstalls all IIS apps, resets IIS, and redeploys everything from templates.

.DESCRIPTION
    Full IIS teardown and rebuild using deploy profile templates:

    1. Reads all .deploy.json templates to determine the complete app inventory
    2. Uninstalls all virtual applications (apps first, root site last)
    3. Resets IIS via iisreset
    4. Redeploys everything (root site first, then all apps)

    Each app is deployed non-interactively using its template -- no manual input needed.

    The script calls IIS-DeployApp.ps1 with -SiteName, which auto-loads the matching
    template from the templates folder.

.PARAMETER TemplatesPath
    Path to the templates folder. Defaults to $PSScriptRoot\templates.

.PARAMETER SkipUninstall
    Skip the uninstall phase (only redeploy).

.PARAMETER SkipIISReset
    Skip the iisreset step between uninstall and redeploy.

.PARAMETER SkipInstall
    Skip Phase 3 (redeploy) and tray MSI install; only run uninstall and/or IIS reset when used with other switches.

.PARAMETER DeployTray
    After redeploy, run Deploy-IIS-AutoDeploy-Tray.ps1 to deploy the tray scheduled task.

.NOTES
    When the current user is one of FKGEISTA, FKSVEERI, FKMISTA, FKCELERI (team-and-sms rule),
    the script sets DatabaseServer=t-no1fkxtst-db, StagingAppServer=dedge-server and
    env:FK_DATABASE_SERVER for downstream use; the tray MSI path uses StagingAppServer for the staging UNC.

.EXAMPLE
    .\IIS-RedeployAll.ps1
    Full teardown and rebuild of all templated IIS apps.

.EXAMPLE
    .\IIS-RedeployAll.ps1 -SkipUninstall
    Redeploy all apps without uninstalling first.
#>

param(
    [string]$TemplatesPath = "$PSScriptRoot\templates",
    [switch]$SkipUninstall,
    [switch]$SkipIISReset,
    [switch]$SkipInstall,
    [switch]$DeployTray
)

$ErrorActionPreference = "Stop"
Import-Module GlobalFunctions -Force
Import-Module SoftwareUtils -Force
Import-Module Infrastructure -Force
Import-Module IIS-Handler -Force
Set-OverrideAppDataFolder -Path $(Join-Path $env:OptPath "data" "IIS-DeployApp")
Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_STARTED

# IIS site creation and iisreset require elevation
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-LogMessage "This script must run as Administrator (IIS config and iisreset require elevation). Right-click Cursor/pwsh and 'Run as administrator'." -Level ERROR
    Reset-OverrideAppDataFolder
    exit 1
}

# When run by a team member (team-and-sms rule), use test app server and database server for staging/paths
$teamUsernames = @("FKGEISTA", "FKSVEERI", "FKMISTA", "FKCELERI")
$isTeamUser = $env:USERNAME -in $teamUsernames
if ($isTeamUser) {
    $script:DatabaseServer = "t-no1fkxtst-db"
    $script:StagingAppServer = "dedge-server"
    $env:FK_DATABASE_SERVER = $script:DatabaseServer
    Write-LogMessage "Team user $($env:USERNAME): using DatabaseServer=$($script:DatabaseServer), StagingAppServer=$($script:StagingAppServer)" -Level INFO
}
else {
    $script:DatabaseServer = $null
    $script:StagingAppServer = $env:COMPUTERNAME
}

$failCount = 0
$deployScript = Join-Path $PSScriptRoot "IIS-DeployApp.ps1"
$uninstallScript = Join-Path $PSScriptRoot "IIS-UninstallApp.ps1"

# Run a script in a child pwsh.exe process so exit 1 from the child does not terminate this script.
# Pipes child stdout to Out-Host so it appears on the console but does not pollute the return value.
function Invoke-ChildScript {
    param([string]$ScriptPath, [string[]]$ScriptArgs = @())
    & pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @ScriptArgs | Out-Host
    return $LASTEXITCODE
}

try {
# ═══════════════════════════════════════════════════════════════════════════════
# LOAD TEMPLATES
# ═══════════════════════════════════════════════════════════════════════════════
if (-not (Test-Path $TemplatesPath)) {
    Write-LogMessage "Templates folder not found: $($TemplatesPath)" -Level ERROR
    exit 1
}

$templateFiles = Get-ChildItem -Path $TemplatesPath -Filter "*.deploy.json" -File
if ($templateFiles.Count -eq 0) {
    Write-LogMessage "No .deploy.json templates found in $($TemplatesPath)" -Level ERROR
    exit 1
}

# Parse all templates and split into site (root) and apps
$siteProfiles = @()
$appProfiles = @()

foreach ($f in $templateFiles) {
    $json = Get-Content $f.FullName -Raw | ConvertFrom-Json
    $entry = [PSCustomObject]@{
        SiteName      = $json.SiteName
        IsRootSite    = ($json.IsRootSiteProfile -eq $true)
        File          = $f.FullName
        AppType       = $json.AppType
        InstallSource = $json.InstallSource
    }
    if ($entry.IsRootSite) {
        $siteProfiles += $entry
    }
    else {
        $appProfiles += $entry
    }
}

# Sort apps alphabetically for consistent ordering
$appProfiles = $appProfiles | Sort-Object SiteName

Write-LogMessage "Found $($siteProfiles.Count) site profile(s) and $($appProfiles.Count) app profile(s)" -Level INFO
Write-Host ""
Write-Host "  Site profiles:" -ForegroundColor Yellow
foreach ($s in $siteProfiles) {
    Write-Host "    [Site] $($s.SiteName) ($($s.AppType), $($s.InstallSource))" -ForegroundColor Cyan
}
Write-Host "  App profiles:" -ForegroundColor Yellow
foreach ($a in $appProfiles) {
    Write-Host "    [App]  $($a.SiteName) ($($a.AppType), $($a.InstallSource))" -ForegroundColor Green
}
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 1: UNINSTALL (apps first, then site)
# ═══════════════════════════════════════════════════════════════════════════════
if (-not $SkipUninstall) {
    Write-LogMessage "═══ PHASE 1: UNINSTALL ═══" -Level INFO

    # Uninstall apps first (reverse order for clean teardown)
    $reverseApps = @($appProfiles | Sort-Object SiteName -Descending)
    foreach ($app in $reverseApps) {
        Write-LogMessage "Uninstalling app: $($app.SiteName)" -Level INFO
        $exitCode = Invoke-ChildScript -ScriptPath $uninstallScript -ScriptArgs @('-SiteName', $app.SiteName, '-Force')
        if ($exitCode -eq 0) {
            Write-LogMessage "Uninstalled: $($app.SiteName)" -Level INFO
        }
        else {
            Write-LogMessage "Uninstall $($app.SiteName) exit $($exitCode) (may be already removed — non-fatal)" -Level WARN
        }
    }

    # Uninstall site(s) last
    # Root site profiles (IsRootSiteProfile=true) get a full teardown+recreate during Phase 3
    # deploy, so Phase 1 errors here are non-fatal. The site may also already be gone after
    # app uninstalls, or in a broken state ("application '/' does not exist") -- either way,
    # Phase 3 handles it cleanly.
    foreach ($site in $siteProfiles) {
        Write-LogMessage "Uninstalling site: $($site.SiteName)" -Level INFO
        $exitCode = Invoke-ChildScript -ScriptPath $uninstallScript -ScriptArgs @('-SiteName', $site.SiteName, '-Force')
        if ($exitCode -eq 0) {
            Write-LogMessage "Uninstalled: $($site.SiteName)" -Level INFO
        }
        else {
            Write-LogMessage "Uninstall site '$($site.SiteName)' exit $($exitCode) (non-fatal, Phase 3 handles teardown)" -Level WARN
        }
    }
}
else {
    Write-LogMessage "Skipping uninstall phase (SkipUninstall)" -Level INFO
}

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 2: RESET IIS
# ═══════════════════════════════════════════════════════════════════════════════
if (-not $SkipIISReset) {
    Write-LogMessage "═══ PHASE 2: IIS RESET ═══" -Level INFO
    try {
        Write-LogMessage "Running iisreset..." -Level INFO
        $resetOutput = & iisreset 2>&1 | Out-String
        Write-LogMessage "iisreset output: $($resetOutput.Trim())" -Level INFO
    }
    catch {
        Write-LogMessage "iisreset failed: $($_.Exception.Message)" -Level WARN
        $failCount++
    }

    # Wait for W3SVC to be ready
    Start-Sleep -Seconds 3
    Write-LogMessage "IIS reset complete" -Level INFO
}
else {
    Write-LogMessage "Skipping IIS reset (SkipIISReset)" -Level INFO
}
#read-host "Press Enter to continue..."
if (-not $SkipInstall) {
    # ═══════════════════════════════════════════════════════════════════════════════
    # PHASE 3: REDEPLOY (site first, then apps)
    # ═══════════════════════════════════════════════════════════════════════════════
    Write-LogMessage "═══ PHASE 3: REDEPLOY ═══" -Level INFO

    # Deploy site(s) first -- if the root site fails, abort app deployment
    $siteDeployFailed = $false
    foreach ($site in $siteProfiles) {
        Write-LogMessage "Deploying site: $($site.SiteName)" -Level INFO
        $exitCode = Invoke-ChildScript -ScriptPath $deployScript -ScriptArgs @('-SiteName', $site.SiteName)
        if ($exitCode -eq 0) {
            Write-LogMessage "Deployed: $($site.SiteName)" -Level INFO
        }
        else {
            Write-LogMessage "Failed to deploy $($site.SiteName) (exit $($exitCode))" -Level ERROR
            $failCount++
            $siteDeployFailed = $true
        }
    }

    if ($siteDeployFailed) {
        Write-LogMessage "ABORTING app deployment -- root site deployment failed. All apps depend on the parent site." -Level ERROR
        Write-LogMessage "Fix the root site issue first, then re-run this script." -Level ERROR
    }

    # Deploy apps (only if root site deployed successfully)
    if (-not $siteDeployFailed) {
        foreach ($app in $appProfiles) {
            Write-LogMessage "Deploying app: $($app.SiteName)" -Level INFO
            $exitCode = Invoke-ChildScript -ScriptPath $deployScript -ScriptArgs @('-SiteName', $app.SiteName)
            if ($exitCode -eq 0) {
                Write-LogMessage "Deployed: $($app.SiteName)" -Level INFO
            }
            else {
                Write-LogMessage "Failed to deploy $($app.SiteName) (exit $($exitCode))" -Level ERROR
                $failCount++
            }
        }
    }

    # Always install latest IIS Auto-Deploy Tray MSI silently after deploying all IIS apps
    Write-LogMessage "═══ Install IIS Auto-Deploy Tray (MSI) ═══" -Level INFO
    $stagingServer = if ($null -ne $StagingAppServer) { $StagingAppServer } else { $env:COMPUTERNAME }
    $stagingBase = "\\$($stagingServer)\DedgeCommon\Software\DedgeWinApps\IIS-AutoDeploy-Tray"
    $msiPath = Join-Path $stagingBase "IIS-AutoDeploy.Tray.Setup.msi"
    if (-not (Test-Path $msiPath)) {
        $msiPath = Join-Path "$env:OptPath\DedgeWinApps\IIS-AutoDeploy-Tray" "IIS-AutoDeploy.Tray.Setup.msi"
    }
    if (Test-Path $msiPath) {
        try {
            Write-LogMessage "Installing tray MSI: $($msiPath)" -Level INFO
            $msiProc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$msiPath`" /qn" -Wait -PassThru
            if ($msiProc.ExitCode -eq 0) {
                Write-LogMessage "IIS Auto-Deploy Tray MSI installed successfully" -Level INFO
            }
            else {
                Write-LogMessage "Tray MSI install exited with code $($msiProc.ExitCode)" -Level WARN
                $failCount++
            }
        }
        catch {
            Write-LogMessage "Tray MSI install failed: $($_.Exception.Message)" -Level WARN
            $failCount++
        }
    }
    else {
        Write-LogMessage "Tray MSI not found, skipping auto-deploy tray install" -Level WARN
    }

    # Optional: Deploy scheduled task for IIS Auto-Deploy Tray (runs at logon)
    if ($DeployTray) {
        Write-LogMessage "═══ Deploy IIS Auto-Deploy Tray Scheduled Task ═══" -Level INFO
        $trayDeployScript = "$env:OptPath\DedgeWinApps\IIS-AutoDeploy-Tray\Deploy-IIS-AutoDeploy-Tray.ps1"
        if (Test-Path $trayDeployScript) {
            try {
                & $trayDeployScript
                Write-LogMessage "IIS Auto-Deploy Tray scheduled task deployed" -Level INFO
            }
            catch {
                Write-LogMessage "Tray scheduled task deploy failed: $($_.Exception.Message)" -Level WARN
                $failCount++
            }
        }
        else {
            Write-LogMessage "Deploy-IIS-AutoDeploy-Tray.ps1 not found at $($trayDeployScript)" -Level WARN
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host ""
if ($failCount -gt 0) {
    Write-LogMessage "Redeploy completed with $($failCount) failure(s)" -Level ERROR
    Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_FAILED
}
elseif ($SkipInstall) {
    Write-LogMessage "Uninstall/IIS reset phase(s) completed. Redeploy skipped (SkipInstall)." -Level INFO
    Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_COMPLETED
}
else {
    $totalApps = $siteProfiles.Count + $appProfiles.Count
    Write-LogMessage "All $($totalApps) site(s)/app(s) redeployed successfully" -Level INFO
    Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_COMPLETED
}
}
finally {
    Reset-OverrideAppDataFolder
}
exit $failCount
