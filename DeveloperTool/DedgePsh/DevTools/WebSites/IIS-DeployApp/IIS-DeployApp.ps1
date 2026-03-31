<#
.SYNOPSIS
    Generic IIS virtual application deployment using appcmd.exe with full teardown + recreate.

.DESCRIPTION
    Deploys any application as a virtual app under an existing IIS site (Default Web Site).
    All apps are virtual applications -- no standalone sites. This ensures deploying one app
    never breaks another (no port conflicts, no binding removals).

    Supports two app types:
    - AspNetCore : .NET app hosted in-process via AspNetCoreModuleV2 (AlwaysRunning, no idle timeout)
    - Static     : HTML/CSS/JS files served directly by IIS (default idle timeout, directory browsing optional)

    Supports three install sources:
    - WinApp  : Calls Install-OurWinApp (deploys to $env:OptPath\DedgeWinApps\$InstallAppName)
    - PshApp  : Calls Install-OurPshApp (deploys to $env:OptPath\DedgePshApps\$InstallAppName)
    - None    : Skips install -- uses PhysicalPath as-is (for pre-existing content like AutoDoc)

    Supports deployment profiles (JSON) for repeatable deployments. When -SiteName is passed,
    the matching template is automatically determined from the templates folder (by JSON SiteName).
    Run with no parameters to see available profiles and pick one interactively.

    A special "DefaultWebSite" profile bootstraps the root site with a redirect index.html.
    No other profile can deploy to the root path (/).

    Steps: Teardown -> Install files -> Create app pool -> Create virtual app -> web.config -> Permissions -> Start -> Verify

.PARAMETER SiteName
    IIS app name (becomes the virtual path). Default: DedgeAuth

.PARAMETER PhysicalPath
    Local path to the application files. Auto-resolved from InstallSource if not provided.

.PARAMETER AppType
    Application type: AspNetCore or Static. Default: AspNetCore

.PARAMETER DotNetDll
    For AspNetCore apps: the DLL to run (e.g. MyApp.Api.dll). Auto-detected if not provided.

.PARAMETER AppPoolName
    IIS app pool name. Defaults to SiteName.

.PARAMETER InstallSource
    How to deploy app files before IIS setup: WinApp, PshApp, or None. Default: WinApp

.PARAMETER InstallAppName
    App name passed to Install-OurWinApp or Install-OurPshApp. Defaults to SiteName.

.PARAMETER VirtualPath
    Virtual path under ParentSite. Defaults to /$SiteName. Root (/) is reserved for DefaultWebSite profile.

.PARAMETER ParentSite
    Parent IIS site. Default: Default Web Site

.PARAMETER HealthEndpoint
    Health check endpoint path for AspNetCore apps (e.g. /health). Empty to skip. Default: /health

.PARAMETER EnableDirectoryBrowsing
    For Static apps: enable directory browsing.

.PARAMETER AllowAnonymousAccess
    When $true, enables Anonymous Authentication and disables Windows Authentication
    on the virtual app so it is publicly accessible. Default: $false.

.EXAMPLE
    .\IIS-DeployApp.ps1
    Shows profile picker, then deploys the selected profile.

.EXAMPLE
    .\IIS-DeployApp.ps1 -SiteName "DedgeAuth"
    Deploys DedgeAuth as virtual app at http://server/DedgeAuth/

.EXAMPLE
    .\IIS-DeployApp.ps1 -SiteName "AutoDoc" -AppType Static -InstallSource None -PhysicalPath "$env:OptPath\Webs\AutoDoc" -EnableDirectoryBrowsing
    Deploys AutoDoc as virtual app at http://server/AutoDoc/
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$SiteName = "",

    [Parameter(Mandatory = $false)]
    [string]$PhysicalPath = $null,

    [Parameter(Mandatory = $false)]
    [ValidateSet("AspNetCore", "Static", "Undetermined")]
    [string]$AppType = "Undetermined",

    [Parameter(Mandatory = $false)]
    [string]$DotNetDll = $null,

    [Parameter(Mandatory = $false)]
    [string]$AppPoolName = $null,

    [Parameter(Mandatory = $false)]
    [ValidateSet("WinApp", "PshApp", "None", "Undetermined")]
    [string]$InstallSource = "Undetermined",

    [Parameter(Mandatory = $false)]
    [string]$InstallAppName = $null,

    [Parameter(Mandatory = $false)]
    [string]$VirtualPath = $null,

    [Parameter(Mandatory = $false)]
    [string]$ParentSite = $null,

    [Parameter(Mandatory = $false)]
    [string]$HealthEndpoint = $null,

    [Parameter(Mandatory = $false)]
    [bool]$EnableDirectoryBrowsing = $true,

    [Parameter(Mandatory = $false)]
    [int]$ApiPort = 0,

    # Optional array of additional ports that need firewall rules.
    # Each entry: @{ Port = [int]; Description = [string]; Direction = [string] }
    # Direction: "Inbound", "Outbound", or "Both" (default: "Both").
    [Parameter(Mandatory = $false)]
    [array]$AdditionalPorts = @(),

    # Optional array of additional WinApp names to install alongside the main app.
    # Each entry is a string app name passed to Install-OurWinApp (e.g. "GenericLogHandler-Agent").
    [Parameter(Mandatory = $false)]
    [string[]]$AdditionalWinApps = @(),

    # Path to Register-DedgeAuthApp.ps1 when template has DedgeAuth block. Default derived from repo layout when not set.
    [Parameter(Mandatory = $false)]
    [string]$DedgeAuthRegisterScriptPath = $null,

    # Optional path to a permissions JSON template (absolute, or relative to the deploy template directory).
    # When provided, permissions in that file are applied to PhysicalPath during Step 6.
    # Overrides the value from the deploy template's PermissionsTemplatePath field.
    [Parameter(Mandatory = $false)]
    [string]$PermissionsTemplatePath = $null,

    [Parameter(Mandatory = $false)]
    [bool]$AllowAnonymousAccess = $false
)

$ErrorActionPreference = "Stop"
Import-Module GlobalFunctions -Force
Import-Module SoftwareUtils -Force
Import-Module Infrastructure -Force
Import-Module IIS-Handler -Force
Set-OverrideAppDataFolder -Path $(Join-Path $env:OptPath "data" "IIS-DeployApp")
Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_STARTED
$deployResult = $null
try {
    # Only forward parameters the user explicitly provided, so Deploy-IISSite
    # can detect unset values and let profile data fill them in.
    $splatParams = @{}
    foreach ($key in $PSBoundParameters.Keys) {
        $splatParams[$key] = $PSBoundParameters[$key]
    }
    # TemplatesPath: when -SiteName is passed, Deploy-IISSite auto-selects the template
    # from this folder by matching the JSON "SiteName" field in *.deploy.json files.
    $splatParams['TemplatesPath'] = "$PSScriptRoot\templates"

    # Wire DedgeAuthRegisterScriptPath: use caller-provided value or resolve via $env:OptPath
    if ($PSBoundParameters.ContainsKey('DedgeAuthRegisterScriptPath') -and $DedgeAuthRegisterScriptPath) {
        $splatParams['DedgeAuthRegisterScriptPath'] = $DedgeAuthRegisterScriptPath
    } else {
        $defaultRegisterScript = Join-Path $env:OptPath "DedgePshApps\DedgeAuth-AddAppSupport\Register-DedgeAuthApp.ps1"
        if (Test-Path $defaultRegisterScript) {
            $splatParams['DedgeAuthRegisterScriptPath'] = $defaultRegisterScript
            Write-LogMessage "DedgeAuthRegisterScriptPath auto-resolved: $($defaultRegisterScript)" -Level DEBUG
        } else {
            Write-LogMessage "Register-DedgeAuthApp.ps1 not found at '$($defaultRegisterScript)' — DedgeAuth registration will be skipped if templates have DedgeAuth block" -Level WARN
        }
    }

    $deployResult = Deploy-IISSite @splatParams

    Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "$($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_FAILED

    # Run diagnostics if we know which site failed
    $diagSite = if ($deployResult) { $deployResult.SiteName }   elseif ($SiteName) { $SiteName }   else { $null }
    $diagParent = if ($deployResult) { $deployResult.ParentSite } elseif ($ParentSite) { $ParentSite } else { "Default Web Site" }
    if ($diagSite) {
        Write-LogMessage "Running diagnostics for '$($diagSite)'..." -Level INFO
        Test-IISSite -SiteName $diagSite -ParentSite $diagParent
    }
    exit 1
}
finally {
    Reset-OverrideAppDataFolder
}