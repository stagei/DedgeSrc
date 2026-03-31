#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Publishes Generic Log Handler apps (using .pubxml PublishProfiles) and optionally starts them locally.

.DESCRIPTION
    Follows the FK standard Build-And-Publish pattern:
    - All app versions follow the REST API (WebApi) version: WebApi is primary, version is incremented there and synced to all projects.
    - Stops running Generic Log Handler processes so publish can succeed.
    - Publishes each component using its .pubxml publish profile:
        WebApi:        WebApp-FileSystem.pubxml  -> \\server\DedgeCommon\Software\DedgeWinApps\GenericLogHandler-WebApi
        ImportService: WinApp-FileSystem.pubxml  -> \\server\DedgeCommon\Software\DedgeWinApps\GenericLogHandler-ImportService
        AlertAgent:    WinApp-FileSystem.pubxml  -> \\server\DedgeCommon\Software\DedgeWinApps\GenericLogHandler-AlertAgent
    - Each component publishes to its own isolated folder (multi-project naming convention).
    - Optionally starts the apps from the local install path and opens the web page.

    After publishing, run IIS-DeployApp.ps1 on the target server to deploy:
      C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\IIS-DeployApp.ps1
      Template: templates\GenericLogHandler_WinApp.deploy.json

    Full deployment docs: C:\opt\src\DedgeAuth\docs\integration\publish-and-deploy-guide.md

.PARAMETER VersionPart
    Which version part to increment: Major, Minor, or Patch (default: Patch).

.PARAMETER ApiBaseUrl
    Base URL of the Web API. Default: http://localhost:8110

.PARAMETER SkipVersionBump
    Do not increment version; only sync existing WebApi version to other projects and build.

.PARAMETER SkipBuild
    Do not rebuild. Only stop, start apps, and open web page (use when binaries are already built).

.PARAMETER SkipStart
    Do not start Import Service or Web API; only publish (and optionally bump version). Do not open browser.

.EXAMPLE
    .\Build-And-Publish.ps1
    Bump patch version, publish all components to network share.

.EXAMPLE
    .\Build-And-Publish.ps1 -VersionPart Minor
    Bump minor version, sync all projects, publish.

.EXAMPLE
    .\Build-And-Publish.ps1 -SkipStart:$false
    Publish and start apps locally from the local install path.
#>

[CmdletBinding()]
param(
    [ValidateSet("Major", "Minor", "Patch")]
    [string]$VersionPart = "Patch",

    [string]$ApiBaseUrl = "http://localhost:8110",

    [Parameter(Mandatory = $false)]
    [switch]$SkipVersionBump,

    [Parameter(Mandatory = $false)]
    [switch]$SkipBuild,

    [bool]$SkipStart = $true
)

try {
    Import-Module -Name GlobalFunctions -Force -ErrorAction Stop
}
catch {
    Write-Host "[WARN] GlobalFunctions not available; using fallback logging." -ForegroundColor Yellow
    function Write-LogMessage { param([string]$Message, [string]$Level = "INFO") Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message" }
}

$ErrorActionPreference = "Stop"
$startTime = Get-Date
$projectRoot = $PSScriptRoot
$webApiPath = Join-Path $projectRoot "src\GenericLogHandler.WebApi"
$importServicePath = Join-Path $projectRoot "src\GenericLogHandler.ImportService"
$healthUrl = "$ApiBaseUrl/health"

# Publish destination base paths (multi-project naming: <Solution>-<Component>)
# Network share: where dotnet publish writes via .pubxml profiles
# Local install:  where IIS-DeployApp copies apps to on the target server
$publishShareBase = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps"
$localInstallBase = Join-Path $env:OptPath "DedgeWinApps"

# Apps to publish: ProjectPath, pubxml profile name, folder name on DedgeCommon share
# Naming convention: WebApp-FileSystem.pubxml for IIS web apps, WinApp-FileSystem.pubxml for services
$publishProjects = @(
    @{
        Name          = "GenericLogHandler.ImportService"
        ProjectPath   = Join-Path $projectRoot "src\GenericLogHandler.ImportService\GenericLogHandler.ImportService.csproj"
        PublishFolder  = "GenericLogHandler-ImportService"
        ExeName       = "GenericLogHandler.ImportService.exe"
        DllName       = "GenericLogHandler.ImportService.dll"
        ProfileName   = "WinApp-FileSystem"
    },
    @{
        Name          = "GenericLogHandler.WebApi"
        ProjectPath   = Join-Path $projectRoot "src\GenericLogHandler.WebApi\GenericLogHandler.WebApi.csproj"
        PublishFolder  = "GenericLogHandler-WebApi"
        ExeName       = "GenericLogHandler.WebApi.exe"
        DllName       = "GenericLogHandler.WebApi.dll"
        ProfileName   = "WebApp-FileSystem"
    },
    @{
        Name          = "GenericLogHandler.AlertAgent"
        ProjectPath   = Join-Path $projectRoot "src\GenericLogHandler.AlertAgent\GenericLogHandler.AlertAgent.csproj"
        PublishFolder  = "GenericLogHandler-AlertAgent"
        ExeName       = "GenericLogHandler.AlertAgent.exe"
        DllName       = "GenericLogHandler.AlertAgent.dll"
        ProfileName   = "WinApp-FileSystem"
    }
)

# Resolve directory that contains the published app (local install path, share path, or bin\Release\*\publish)
function Get-PublishOutputDir {
    param([string]$LocalDir, [string]$ShareDir, [string]$ProjectDir, [string]$ExeName, [string]$DllName)
    # 1. Local install path (where IIS-DeployApp copies to)
    if ($LocalDir -and (Test-Path (Join-Path $LocalDir $ExeName))) { return $LocalDir }
    if ($LocalDir -and (Test-Path (Join-Path $LocalDir $DllName))) { return $LocalDir }
    # 2. Network share (where dotnet publish writes via .pubxml)
    if ($ShareDir -and (Test-Path (Join-Path $ShareDir $ExeName))) { return $ShareDir }
    if ($ShareDir -and (Test-Path (Join-Path $ShareDir $DllName))) { return $ShareDir }
    # 3. Fallback: bin\Release\*\publish under project
    $binPublish = Get-ChildItem -Path (Join-Path $ProjectDir "bin\Release") -Filter "publish" -Recurse -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($binPublish -and (Test-Path (Join-Path $binPublish.FullName $ExeName))) { return $binPublish.FullName }
    if ($binPublish -and (Test-Path (Join-Path $binPublish.FullName $DllName))) { return $binPublish.FullName }
    return $null
}

# ═══════════════════════════════════════════════════════════════════════════════
# STOP ALL APPS (run at start so build can succeed)
# ═══════════════════════════════════════════════════════════════════════════════
function Stop-LogHandlerProcesses {
    Write-LogMessage "Killing all Generic Log Handler apps..." -Level INFO
    $stopped = 0
    $pidsStopped = @()

    # 1. By actual exe process name (GenericLogHandler.WebApi, GenericLogHandler.ImportService, GenericLogHandler.AlertAgent)
    foreach ($name in @("GenericLogHandler.WebApi", "GenericLogHandler.ImportService", "GenericLogHandler.AlertAgent")) {
        Get-Process -Name $name -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Id -notin $pidsStopped) {
                Write-Host "    Stopping $name (PID $($_.Id))..." -ForegroundColor Gray
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
                $pidsStopped += $_.Id
                $stopped++
            }
        }
    }

    # 2. Process listening on Web API port (e.g. dotnet run WebApi)
    try {
        Get-NetTCPConnection -LocalPort 8110 -State Listen -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.OwningProcess -and $_.OwningProcess -notin $pidsStopped) {
                Write-Host "    Stopping process on port 8110 (PID $($_.OwningProcess))..." -ForegroundColor Gray
                Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue
                $pidsStopped += $_.OwningProcess
                $stopped++
            }
        }
    }
    catch { }

    # 3. dotnet processes running GenericLogHandler projects (dotnet run ImportService, AlertAgent, etc.)
    try {
        Get-CimInstance Win32_Process -Filter "Name = 'dotnet.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
            $cmd = $_.CommandLine ?? ""
            if ($cmd -match "GenericLogHandler") {
                $procId = $_.ProcessId
                if ($procId -notin $pidsStopped) {
                    Write-Host "    Stopping dotnet GenericLogHandler (PID $procId)..." -ForegroundColor Gray
                    Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
                    $pidsStopped += $procId
                    $stopped++
                }
            }
        }
    }
    catch { }

    # 4. Any process with GenericLogHandler in path (fallback)
    try {
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
            $_.ExecutablePath -and $_.ExecutablePath -match "GenericLogHandler"
        } | ForEach-Object {
            $procId = $_.ProcessId
            if ($procId -notin $pidsStopped) {
                Write-Host "    Stopping GenericLogHandler process (PID $procId)..." -ForegroundColor Gray
                Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
                $pidsStopped += $procId
                $stopped++
            }
        }
    }
    catch { }

    if ($stopped -gt 0) {
        Start-Sleep -Seconds 2
        Write-LogMessage "Killed $stopped Generic Log Handler process(es)." -Level INFO
    }
    else {
        Write-LogMessage "No running Generic Log Handler apps found." -Level INFO
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# VERSION MANAGEMENT (REST API = WebApi is primary; all apps follow its version)
# ═══════════════════════════════════════════════════════════════════════════════
function Get-ProjectVersion {
    param([string]$CsprojPath)
    if (-not (Test-Path $CsprojPath)) { return $null }
    $content = Get-Content $CsprojPath -Raw
    if ($content -match '<VersionPrefix>(\d+\.\d+\.\d+)</VersionPrefix>') { return $matches[1] }
    if ($content -match '<Version>(\d+\.\d+\.\d+)</Version>') { return $matches[1] }
    if ($content -match '<AssemblyVersion>(\d+)\.(\d+)\.(\d+)\.(\d+)</AssemblyVersion>') {
        return "$($matches[1]).$($matches[2]).$($matches[3])"
    }
    return $null
}

function Set-ProjectVersion {
    param([string]$CsprojPath, [string]$NewVersion)
    $content = Get-Content $CsprojPath -Raw
    $fourPart = "$NewVersion.0"
    if ($content -match '<VersionPrefix>\d+\.\d+\.\d+</VersionPrefix>') {
        $content = $content -replace '<VersionPrefix>\d+\.\d+\.\d+</VersionPrefix>', "<VersionPrefix>$NewVersion</VersionPrefix>"
    }
    if ($content -match '<AssemblyVersion>\d+\.\d+\.\d+\.\d+</AssemblyVersion>') {
        $content = $content -replace '<AssemblyVersion>\d+\.\d+\.\d+\.\d+</AssemblyVersion>', "<AssemblyVersion>$fourPart</AssemblyVersion>"
    }
    if ($content -match '<FileVersion>\d+\.\d+\.\d+\.\d+</FileVersion>') {
        $content = $content -replace '<FileVersion>\d+\.\d+\.\d+\.\d+</FileVersion>', "<FileVersion>$fourPart</FileVersion>"
    }
    if ($content -match '<Version>\d+\.\d+\.\d+</Version>') {
        $content = $content -replace '<Version>\d+\.\d+\.\d+</Version>', "<Version>$NewVersion</Version>"
    }
    Set-Content -Path $CsprojPath -Value $content -NoNewline
}

function Get-IncrementedVersion {
    param([string]$CurrentVersion, [string]$Part = "Patch")
    $versionParts = $CurrentVersion.Split('.')
    $major = [int]$versionParts[0]
    $minor = [int]$versionParts[1]
    $patch = [int]$versionParts[2]
    switch ($Part) {
        "Major" { $major++; $minor = 0; $patch = 0 }
        "Minor" { $minor++; $patch = 0 }
        "Patch" { $patch++ }
    }
    return "$major.$minor.$patch"
}

# Projects: WebApi is primary (REST API version); all others follow
$versionedProjects = @(
    @{ Name = "GenericLogHandler.Core"; Path = Join-Path $projectRoot "src\GenericLogHandler.Core\GenericLogHandler.Core.csproj"; IsPrimary = $false },
    @{ Name = "GenericLogHandler.Data"; Path = Join-Path $projectRoot "src\GenericLogHandler.Data\GenericLogHandler.Data.csproj"; IsPrimary = $false },
    @{ Name = "GenericLogHandler.ImportService"; Path = Join-Path $projectRoot "src\GenericLogHandler.ImportService\GenericLogHandler.ImportService.csproj"; IsPrimary = $false },
    @{ Name = "GenericLogHandler.AlertAgent"; Path = Join-Path $projectRoot "src\GenericLogHandler.AlertAgent\GenericLogHandler.AlertAgent.csproj"; IsPrimary = $false },
    @{ Name = "GenericLogHandler.WebApi"; Path = Join-Path $projectRoot "src\GenericLogHandler.WebApi\GenericLogHandler.WebApi.csproj"; IsPrimary = $true }
)

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Generic Log Handler – Build & Publish" -ForegroundColor Cyan
Write-Host "  Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

Stop-LogHandlerProcesses

# ─── Version (REST API = WebApi primary) ───────────────────────────────────────
$newVersion = $null
$primaryProject = $versionedProjects | Where-Object { $_.IsPrimary } | Select-Object -First 1
$currentPrimaryVersion = Get-ProjectVersion -CsprojPath $primaryProject.Path

if ($null -eq $currentPrimaryVersion) {
    Write-LogMessage "No version found in WebApi csproj; using 1.0.0" -Level WARN
    $currentPrimaryVersion = "1.0.0"
}

if (-not $SkipVersionBump) {
    $newVersion = Get-IncrementedVersion -CurrentVersion $currentPrimaryVersion -Part $VersionPart
    Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
    Write-Host "  Version (REST API = WebApi): $currentPrimaryVersion → $newVersion ($VersionPart)" -ForegroundColor Yellow
    Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
    Write-Host ""
}
else {
    $newVersion = $currentPrimaryVersion
    Write-Host "  Version (no bump): $newVersion" -ForegroundColor Gray
    Write-Host ""
}

foreach ($proj in $versionedProjects) {
    if (-not (Test-Path $proj.Path)) { continue }
    $cur = Get-ProjectVersion -CsprojPath $proj.Path
    if ($null -eq $cur) { continue }
    Set-ProjectVersion -CsprojPath $proj.Path -NewVersion $newVersion
    $label = if ($proj.IsPrimary) { " (REST API primary)" } else { "" }
    Write-Host "  $($proj.Name): $newVersion$label" -ForegroundColor $(if ($proj.IsPrimary) { "Green" } else { "Gray" })
}
Write-Host ""

# ─── Publish (using .pubxml publish profiles) ─────────────────────────
if (-not $SkipBuild) {
    Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
    Write-Host "  Publishing apps (to $($publishShareBase))" -ForegroundColor Yellow
    Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
    Write-Host ""
    
    foreach ($proj in $publishProjects) {
        if (-not (Test-Path $proj.ProjectPath)) {
            Write-Host "  Skipping $($proj.Name): project not found." -ForegroundColor Yellow
            continue
        }
        Write-Host "  Publishing $($proj.Name) (profile: $($proj.ProfileName)) ..." -ForegroundColor Gray
        
        # Use the .pubxml publish profile (Properties\PublishProfiles\<name>.pubxml)
        $publishArgs = @(
            "publish",
            $proj.ProjectPath,
            "/p:PublishProfile=$($proj.ProfileName)",
            "-v", "minimal"
        )
        & dotnet @publishArgs
        if ($LASTEXITCODE -ne 0) {
            Write-LogMessage "Publish failed: $($proj.Name)." -Level ERROR
            exit 1
        }
    }
    Write-Host ""
    Write-Host "  Publish succeeded." -ForegroundColor Green
    Write-Host ""

    # Copy import-config.json and appsettings.json to each component's publish folder
    $importConfigSrc = Join-Path $projectRoot "import-config.json"
    $appsettingsSrc = Join-Path $projectRoot "appsettings.json"
    
    foreach ($proj in $publishProjects) {
        $appShareDir = Join-Path $publishShareBase $proj.PublishFolder
        if (Test-Path $appShareDir) {
            if (Test-Path $appsettingsSrc) {
                Copy-Item -Path $appsettingsSrc -Destination $appShareDir -Force
            }
            if (Test-Path $importConfigSrc) {
                Copy-Item -Path $importConfigSrc -Destination $appShareDir -Force
            }
            Write-Host "  Copied configs to $($proj.PublishFolder)" -ForegroundColor Gray
        }
    }

    # ─── Sign Published Executables ──────────────────────────────────────────
    Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Magenta
    Write-Host "  Signing Published Files (EXE)" -ForegroundColor Magenta
    Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Magenta
    Write-Host ""

    $filesToSign = @(
        "$publishShareBase\GenericLogHandler-WebApi\GenericLogHandler.WebApi.exe",
        "$publishShareBase\GenericLogHandler-ImportService\GenericLogHandler.ImportService.exe",
        "$publishShareBase\GenericLogHandler-AlertAgent\GenericLogHandler.AlertAgent.exe"
    )
    $DedgeSignPath = "dedge-server.DEDGE.fk.no\DedgeCommon\Software\DedgePshApps\DedgeSign\DedgeSign.ps1"

    foreach ($fileToSign in $filesToSign) {
        if (Test-Path $fileToSign) {
            $sig = Get-AuthenticodeSignature -FilePath $fileToSign -ErrorAction SilentlyContinue
            if ($sig.Status -eq 'Valid') {
                Write-Host "  Already signed: $(Split-Path -Leaf $fileToSign)" -ForegroundColor Green
                continue
            }
            Write-Host "  Signing: $(Split-Path -Leaf $fileToSign)..." -ForegroundColor Yellow
            try {
                & pwsh.exe -ExecutionPolicy Bypass -File $DedgeSignPath -Path $fileToSign -Action Add -NoConfirm 2>&1 | Out-Null
                $sigAfter = Get-AuthenticodeSignature -FilePath $fileToSign -ErrorAction SilentlyContinue
                if ($sigAfter.Status -eq 'Valid') {
                    Write-Host "  Signed successfully: $(Split-Path -Leaf $fileToSign)" -ForegroundColor Green
                } else {
                    Write-Host "  Signing may have failed: $(Split-Path -Leaf $fileToSign) (Status: $($sigAfter.Status))" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "  Could not sign: $(Split-Path -Leaf $fileToSign) - $($_.Exception.Message)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  File not found: $fileToSign" -ForegroundColor Yellow
        }
    }
    Write-Host ""

    # ─── Verify Published Versions ───────────────────────────────────────────
    Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
    Write-Host "  Verifying Published Versions" -ForegroundColor Cyan
    Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
    Write-Host ""

    foreach ($proj in $publishProjects) {
        $exePath = Join-Path $publishShareBase "$($proj.PublishFolder)\$($proj.ExeName)"
        if (Test-Path $exePath) {
            $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exePath)
            $sig = Get-AuthenticodeSignature $exePath -ErrorAction SilentlyContinue
            $sigStatus = if ($sig.Status -eq 'Valid') { "Signed" } else { "$($sig.Status)" }
            Write-Host "  $($proj.Name): v$($vi.FileVersion) $sigStatus" -ForegroundColor $(if ($sig.Status -eq 'Valid') { 'Green' } else { 'Yellow' })
        } else {
            Write-Host "  $($proj.Name): NOT FOUND at $exePath" -ForegroundColor Red
        }
    }
    Write-Host ""
}

# ─── Start Import Service, Alert Agent, and Web API from publish output ─
if (-not $SkipStart) {
    Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
    Write-Host "  Starting Import Service, Alert Agent, and Web API" -ForegroundColor Yellow
    Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Yellow
    Write-Host ""

    # Helper to start an app from local install path or share
    function Start-PublishedApp {
        param([string]$AppName, [string]$PublishFolder, [string]$ExeName, [string]$DllName)
        $localDir = Join-Path $localInstallBase $PublishFolder
        $shareDir = Join-Path $publishShareBase $PublishFolder
        $projectDir = Join-Path $projectRoot "src\$AppName"
        $appDir = Get-PublishOutputDir -LocalDir $localDir -ShareDir $shareDir -ProjectDir $projectDir -ExeName $ExeName -DllName $DllName
        if ($appDir) {
            $exePath = Join-Path $appDir $ExeName
            if (Test-Path $exePath) {
                Write-Host "  Starting $AppName from $appDir ..." -ForegroundColor Gray
                Start-Process -FilePath $exePath -WorkingDirectory $appDir -WindowStyle Normal
                return $true
            }
        }
        Write-Host "  $AppName exe not found (checked local and share)" -ForegroundColor Yellow
        return $false
    }

    # Start Import Service
    Start-PublishedApp -AppName "GenericLogHandler.ImportService" -PublishFolder "GenericLogHandler-ImportService" -ExeName "GenericLogHandler.ImportService.exe" -DllName "GenericLogHandler.ImportService.dll" | Out-Null
    Start-Sleep -Seconds 1

    # Start Alert Agent
    Start-PublishedApp -AppName "GenericLogHandler.AlertAgent" -PublishFolder "GenericLogHandler-AlertAgent" -ExeName "GenericLogHandler.AlertAgent.exe" -DllName "GenericLogHandler.AlertAgent.dll" | Out-Null
    Start-Sleep -Seconds 1

    # Start Web API
    Start-PublishedApp -AppName "GenericLogHandler.WebApi" -PublishFolder "GenericLogHandler-WebApi" -ExeName "GenericLogHandler.WebApi.exe" -DllName "GenericLogHandler.WebApi.dll" | Out-Null

    # Run health-check wait and browser launch in a background job so the script can finish
    $waitAndOpenJob = Start-Job -ScriptBlock {
        param($healthUrl, $apiBaseUrl)
        $deadline = (Get-Date).AddSeconds(60)
        $ready = $false
        while ((Get-Date) -lt $deadline) {
            try {
                $r = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
                if ($r.StatusCode -eq 200) { $ready = $true; break }
            }
            catch { }
            Start-Sleep -Seconds 2
        }
        if ($ready) {
            Start-Process $apiBaseUrl
        }
    } -ArgumentList $healthUrl, $ApiBaseUrl

    Write-Host ""
    Write-Host "  Health check and browser launch running in background (job id: $($waitAndOpenJob.Id))." -ForegroundColor Gray
    Write-Host "  Browser will open when API is ready at $ApiBaseUrl" -ForegroundColor Gray
    Write-Host ""
}

# ─── Summary ──────────────────────────────────────────────────────────────────
$totalDuration = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Done" -ForegroundColor Cyan
Write-Host "  Version: $newVersion | Duration: $($totalDuration)s | Finished: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
