<#
.SYNOPSIS
    Interactive wizard to register a new application in DedgeAuth and generate an IIS deployment profile.

.DESCRIPTION
    Point the script at a source project folder and it does the rest:

    1. Recursively scans for appsettings.json -- if multiple found, asks which to use
    2. Detects project type: .cs/.csproj files -> AspNetCore (WinApp), otherwise -> Static
    3. Auto-fills AppId, DLL name, API port, server name, and roles from the project files
    4. Presents a verification screen where every value can be confirmed or overridden
    5. Collects tenant routing and user permission preferences
    6. Executes: DB registration, .deploy.json generation, deploys config to app server

.PARAMETER SourcePath
    Path to the application source folder (e.g. "C:\opt\src\DocView").
    If omitted, the script prompts for it.

.EXAMPLE
    .\DedgeAuth-AddAppSupport.ps1 -SourcePath "C:\opt\src\DocView"

.EXAMPLE
    .\DedgeAuth-AddAppSupport.ps1
#>

param(
    [string]$SourcePath = "",
    [switch]$NonInteractive,
    [string]$AppId = "",
    [string]$DisplayName = "",
    [string]$Description = "",
    [string]$AppType = "",
    [int]$ApiPort = 0,
    [string]$DotNetDll = "",
    [string]$InstallSource = "",
    [string]$HealthEndpoint = "",
    [string[]]$Roles = @(),
    [switch]$AllTenants,
    [string]$PermissionMode = "skip",
    [string]$PermissionRole = "",
    [string]$BaseUrl = "",
    [switch]$SkipDeploy
)

$ErrorActionPreference = "Stop"

Import-Module PostgreSql-Handler -Force

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════
$script:dbHost     = "t-no1fkxtst-db"
$script:dbPort     = 8432
$script:dbName     = "DedgeAuth"
$script:dbUser     = "postgres"
$script:dbPassword = "postgres"

$script:appServerName   = "dedge-server"
$deployJsonDir          = "C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\templates"
$iisDeployScript        = "C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\_deploy.ps1"
$DedgeAuthIISDeploy        = "C:\opt\src\DedgePsh\DevTools\WebSites\DedgeAuth\DedgeAuth-IISConfig\_deploy.ps1"

# ═══════════════════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

function Invoke-Psql {
    param([string]$Query)
    $result = Invoke-PostgreSqlQuery -Host $script:dbHost -Port $script:dbPort -User $script:dbUser -Password $script:dbPassword -Database $script:dbName -Query $Query -Unattended
    if ($null -eq $result) {
        Write-Host "  SQL Error (check logs or run without -Unattended for details)" -ForegroundColor Red
        return $null
    }
    return $result
}

function Write-Header {
    param([string]$Text)
    Write-Host ""
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ("  " + ("=" * ($Text.Length + 2))) -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Step {
    param([string]$Number, [string]$Text)
    Write-Host ""
    Write-Host "  -- Step $($Number): $Text --" -ForegroundColor Yellow
    Write-Host ""
}

# Prompt with a pre-filled default. Returns the default if user just presses Enter.
function Read-WithDefault {
    param(
        [string]$Prompt,
        [string]$Default
    )
    if ($Default) {
        $value = Read-Host "$Prompt [$($Default)]"
        if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
        return $value
    } else {
        return (Read-Host $Prompt)
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# PREFLIGHT
# ═══════════════════════════════════════════════════════════════════════════════
$psqlPath = Get-PostgreSqlPsqlPath
if (-not $psqlPath) {
    Write-Host "  ERROR: PostgreSQL client (psql) not found. Install PostgreSQL client tools first." -ForegroundColor Red
    exit 1
}

$connTest = Invoke-Psql "SELECT 1;"
if ($null -eq $connTest) {
    Write-Host "  ERROR: Cannot connect to database at $($script:dbHost):$($script:dbPort)/$($script:dbName)" -ForegroundColor Red
    exit 1
}

Write-Header "DedgeAuth - Add App Support"

# ═══════════════════════════════════════════════════════════════════════════════
# EXISTING APPS
# ═══════════════════════════════════════════════════════════════════════════════
$existingAppsRaw = Invoke-Psql "SELECT app_id, display_name, is_active, base_url FROM apps ORDER BY app_id;"
if ($existingAppsRaw) {
    $existingApps = @()
    foreach ($line in ($existingAppsRaw -split "`n")) {
        $line = $line.Trim()
        if ($line -and $line -match '\|') {
            $parts = $line -split '\|', 4
            $existingApps += [PSCustomObject]@{
                AppId       = $parts[0].Trim()
                DisplayName = $parts[1].Trim()
                IsActive    = $parts[2].Trim()
                BaseUrl     = $parts[3].Trim()
            }
        }
    }
    if ($existingApps.Count -gt 0) {
        Write-Host "  Registered applications ($($existingApps.Count)):" -ForegroundColor White
        Write-Host ""
        foreach ($app in $existingApps) {
            $statusColor = if ($app.IsActive -eq 't') { "Green" } else { "DarkGray" }
            $statusLabel = if ($app.IsActive -eq 't') { "active" } else { "inactive" }
            Write-Host "    $($app.AppId)" -ForegroundColor $statusColor -NoNewline
            Write-Host "  $($app.DisplayName)" -ForegroundColor Gray -NoNewline
            Write-Host "  [$statusLabel]" -ForegroundColor $statusColor -NoNewline
            if ($app.BaseUrl) {
                Write-Host "  $($app.BaseUrl)" -ForegroundColor DarkGray
            } else {
                Write-Host ""
            }
        }
        Write-Host ""
    }
} else {
    Write-Host "  No applications registered yet." -ForegroundColor DarkGray
    Write-Host ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1: SOURCE PATH
# ═══════════════════════════════════════════════════════════════════════════════
Write-Step "1" "Source Project"

if ([string]::IsNullOrWhiteSpace($SourcePath)) {
    $SourcePath = Read-Host "  Path to application source folder (e.g. C:\opt\src\DocView)"
}
if (-not (Test-Path $SourcePath -PathType Container)) {
    Write-Host "  ERROR: Folder not found: $SourcePath" -ForegroundColor Red
    exit 1
}

$SourcePath = (Resolve-Path $SourcePath).Path
Write-Host "  Source: $SourcePath" -ForegroundColor White

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2: DETECT PROJECT TYPE
# ═══════════════════════════════════════════════════════════════════════════════
Write-Step "2" "Scanning Project"

# Detect .cs or .csproj -> AspNetCore + WinApp; otherwise -> Static
$hasCsFiles = $null -ne (Get-ChildItem -Path $SourcePath -Recurse -Include "*.cs", "*.csproj" -File -ErrorAction SilentlyContinue | Select-Object -First 1)

if ($hasCsFiles) {
    $appType       = "AspNetCore"
    $installSource = "WinApp"
    Write-Host "  Detected: .NET project (AspNetCore, WinApp)" -ForegroundColor Green
} else {
    $appType       = "Static"
    $installSource = "None"
    Write-Host "  Detected: Static site (no .cs/.csproj files found)" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 3: FIND AND SCAN APPSETTINGS.JSON
# ═══════════════════════════════════════════════════════════════════════════════

# Initialize all auto-detected fields
$appId          = Split-Path $SourcePath -Leaf   # default: folder name
$displayName    = ""
$description    = ""
$apiPort        = 0
$dotNetDll      = ""
$healthEndpoint = ""
$roles          = @()
$detectedServer = $script:appServerName
$enableDirBrowsing = ($appType -eq "Static")

# --- Find appsettings.json files recursively ---
$appSettingsFiles = @(Get-ChildItem -Path $SourcePath -Recurse -Filter "appsettings.json" -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\(bin|obj|node_modules)\\' })

$selectedAppSettings = $null

if ($appSettingsFiles.Count -eq 0) {
    Write-Host "  No appsettings.json found in $SourcePath" -ForegroundColor DarkGray
} elseif ($appSettingsFiles.Count -eq 1) {
    $selectedAppSettings = $appSettingsFiles[0]
    Write-Host "  Found: $($selectedAppSettings.FullName)" -ForegroundColor Green
} else {
    Write-Host "  Multiple appsettings.json found:" -ForegroundColor White
    $i = 1
    foreach ($f in $appSettingsFiles) {
        # Show path relative to source root
        $relPath = $f.FullName.Substring($SourcePath.Length).TrimStart('\')
        Write-Host "    [$i] $relPath" -ForegroundColor Gray
        $i++
    }
    $fileChoice = Read-Host "  Which to use? [1]"
    $fileNum = 0
    if ([int]::TryParse($fileChoice, [ref]$fileNum) -and $fileNum -ge 1 -and $fileNum -le $appSettingsFiles.Count) {
        $selectedAppSettings = $appSettingsFiles[$fileNum - 1]
    } else {
        $selectedAppSettings = $appSettingsFiles[0]
    }
    Write-Host "  Using: $($selectedAppSettings.FullName)" -ForegroundColor Green
}

# --- Scan selected appsettings.json ---
$appSettingsDir = $null
if ($selectedAppSettings) {
    $appSettingsDir = $selectedAppSettings.DirectoryName
    $json = Get-Content $selectedAppSettings.FullName -Raw | ConvertFrom-Json

    $fkSection = $json.DedgeAuth
    if ($fkSection) {
        Write-Host ""
        # AppId
        if ($fkSection.AppId) {
            $appId = $fkSection.AppId
            Write-Host "    DedgeAuth:AppId                = $appId" -ForegroundColor Green
        }

        # Server name from AuthServerUrl
        if ($fkSection.AuthServerUrl) {
            try {
                $uri = [System.Uri]$fkSection.AuthServerUrl
                $detectedServer = $uri.Host
                Write-Host "    DedgeAuth:AuthServerUrl        = $($fkSection.AuthServerUrl)  (server: $detectedServer)" -ForegroundColor Green
            } catch {
                Write-Host "    DedgeAuth:AuthServerUrl        = $($fkSection.AuthServerUrl)  (could not parse)" -ForegroundColor Yellow
            }
        }

        # Roles from GlobalLevelToAppRole
        if ($fkSection.GlobalLevelToAppRole -and $fkSection.GlobalLevelToAppRole.PSObject.Properties.Count -gt 0) {
            $roles = @($fkSection.GlobalLevelToAppRole.PSObject.Properties | ForEach-Object { $_.Value } | Select-Object -Unique)
            Write-Host "    DedgeAuth:GlobalLevelToAppRole = $($roles -join ', ')" -ForegroundColor Green
        }
    } else {
        Write-Host "    DedgeAuth section: not found in appsettings.json" -ForegroundColor DarkGray
    }
}

# --- .csproj -> DLL name (search in appsettings dir first, then source root) ---
if ($appType -eq "AspNetCore") {
    $searchDirs = @()
    if ($appSettingsDir) { $searchDirs += $appSettingsDir }
    if ($appSettingsDir -ne $SourcePath) { $searchDirs += $SourcePath }

    $csprojFile = $null
    foreach ($dir in $searchDirs) {
        $csprojFile = Get-ChildItem -Path $dir -Filter "*.csproj" -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($csprojFile) { break }
    }
    # Fallback: recursive search from source root
    if (-not $csprojFile) {
        $csprojFile = Get-ChildItem -Path $SourcePath -Recurse -Filter "*.csproj" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' } | Select-Object -First 1
    }

    if ($csprojFile) {
        $dotNetDll = $csprojFile.BaseName + ".dll"
        Write-Host "    .csproj                    = $($csprojFile.Name)  (DLL: $dotNetDll)" -ForegroundColor Green

        # Use csproj basename as AppId fallback if appsettings didn't have DedgeAuth:AppId
        if ($appId -eq (Split-Path $SourcePath -Leaf) -and $csprojFile.BaseName -ne $appId) {
            $appId = $csprojFile.BaseName
            Write-Host "    AppId (from .csproj)        = $appId" -ForegroundColor Yellow
        }
    } else {
        Write-Host "    .csproj                    = not found" -ForegroundColor DarkGray
    }

    # --- launchSettings.json -> API port ---
    $launchPaths = @()
    if ($appSettingsDir) { $launchPaths += Join-Path $appSettingsDir "Properties\launchSettings.json" }
    if ($appSettingsDir -ne $SourcePath) { $launchPaths += Join-Path $SourcePath "Properties\launchSettings.json" }

    foreach ($lsPath in $launchPaths) {
        if ((Test-Path $lsPath) -and $apiPort -le 0) {
            $launchJson = Get-Content $lsPath -Raw | ConvertFrom-Json
            if ($launchJson.profiles) {
                foreach ($prop in $launchJson.profiles.PSObject.Properties) {
                    $profileObj = $prop.Value
                    if ($profileObj.applicationUrl) {
                        # Regex: extract port number from URL like "http://localhost:8282"
                        # ://  = literal scheme separator
                        # [^:]+ = host (one or more non-colon chars)
                        # :     = literal colon before port
                        # (\d+) = capture group: one or more digits (the port)
                        if ($profileObj.applicationUrl -match '://[^:]+:(\d+)') {
                            $apiPort = [int]$matches[1]
                            Write-Host "    launchSettings ($($prop.Name))  = port $apiPort" -ForegroundColor Green
                            break
                        }
                    }
                }
            }
        }
    }
}

# Default displayName: split PascalCase -> "Doc View"
if ($appId) {
    # Regex: insert a space before each uppercase letter that follows a lowercase letter
    # (?<=[a-z]) = lookbehind for lowercase, (?=[A-Z]) = lookahead for uppercase
    $displayName = $appId -creplace '(?<=[a-z])(?=[A-Z])', ' '
}

Write-Host ""
Write-Host "  Scan complete." -ForegroundColor Cyan

# ═══════════════════════════════════════════════════════════════════════════════
# VERIFICATION -- confirm/override every field, fill in anything missing
# ═══════════════════════════════════════════════════════════════════════════════
Write-Header "Verify Configuration"

# --- Non-interactive: override auto-detected values with parameter values ---
if ($NonInteractive) {
    if ($AppId) { $appId = $AppId }
    if ($DisplayName) { $displayName = $DisplayName }
    if ($Description) { $description = $Description }
    if ($AppType) { $appType = $AppType }
    if ($ApiPort -gt 0) { $apiPort = $ApiPort }
    if ($DotNetDll) { $dotNetDll = $DotNetDll }
    if ($InstallSource) { $installSource = $InstallSource }
    if ($HealthEndpoint) { $healthEndpoint = $HealthEndpoint }
    if ($Roles.Count -gt 0) { $roles = $Roles }
    if ($BaseUrl) { $baseUrl = $BaseUrl }
}

if (-not $NonInteractive) {
    # --- App ID ---
    $appId = Read-WithDefault "  App ID" $appId
    while ([string]::IsNullOrWhiteSpace($appId) -or $appId -match '\s') {
        if ($appId -match '\s') { Write-Host "  App ID cannot contain spaces." -ForegroundColor Red }
        $appId = Read-Host "  App ID (required, no spaces)"
    }
}

# Check if already registered
$existing = Invoke-Psql "SELECT app_id FROM apps WHERE app_id = '$($appId)';"
if ($existing -and $existing.Trim() -eq $appId) {
    Write-Host "  WARNING: App '$($appId)' is already registered in DedgeAuth." -ForegroundColor Yellow
    if (-not $NonInteractive) {
        $continueChoice = Read-Host "  Continue anyway? [y/N]"
        if ($continueChoice -ne 'y' -and $continueChoice -ne 'Y') {
            Write-Host "  Aborted." -ForegroundColor Red
            exit 0
        }
    } else {
        Write-Host "  NonInteractive mode: continuing despite existing registration." -ForegroundColor Yellow
    }
}

if (-not $NonInteractive) {
    # --- Display Name ---
    if (-not $displayName) { $displayName = $appId }
    $displayName = Read-WithDefault "  Display Name" $displayName

    # --- Description ---
    $description = Read-WithDefault "  Description (optional)" $description

    # --- App Type ---
    Write-Host ""
    Write-Host "  App Type: [1] AspNetCore  [2] Static" -ForegroundColor White
    $currentTypeNum = if ($appType -eq "AspNetCore") { "1" } else { "2" }
    $typeChoice = Read-WithDefault "  Choose" $currentTypeNum
    $appType = if ($typeChoice -eq "2") { "Static" } else { "AspNetCore" }

    if ($appType -eq "AspNetCore") {
        # --- API Port ---
        while ($apiPort -le 0) {
            $apiPortInput = Read-Host "  API Port (required, e.g. 8100, 8282)"
            [int]::TryParse($apiPortInput, [ref]$apiPort) | Out-Null
        }
        $portInput = Read-WithDefault "  API Port" $apiPort.ToString()
        $apiPort = [int]$portInput

        # --- DotNet DLL ---
        if (-not $dotNetDll) { $dotNetDll = "$($appId).dll" }
        $dotNetDll = Read-WithDefault "  DotNet DLL" $dotNetDll

        # --- Install Source ---
        Write-Host ""
        Write-Host "  Install Source: [1] WinApp  [2] PshApp  [3] None" -ForegroundColor White
        $currentSrcNum = switch ($installSource) { "WinApp" { "1" } "PshApp" { "2" } "None" { "3" } default { "1" } }
        $srcChoice = Read-WithDefault "  Choose" $currentSrcNum
        $installSource = switch ($srcChoice) {
            "2" { "PshApp" }
            "3" { "None" }
            default { "WinApp" }
        }

        # --- Health Endpoint ---
        $healthEndpoint = Read-WithDefault "  Health Endpoint (empty to skip)" $healthEndpoint

        $enableDirBrowsing = $false
    } else {
        # Static site defaults
        $apiPort = 0
        $dotNetDll = ""
        $installSource = "None"
        $healthEndpoint = ""

        $dirBrowseInput = Read-WithDefault "  Enable directory browsing? [Y/n]" "Y"
        $enableDirBrowsing = ($dirBrowseInput -ne 'n' -and $dirBrowseInput -ne 'N')
    }

    # --- Roles ---
    if ($roles.Count -eq 0) {
        Write-Host ""
        Write-Host "  Which roles should this app support?" -ForegroundColor White
        Write-Host "    [1] Single role: 'User' (access or no access)" -ForegroundColor Gray
        Write-Host "    [2] Standard 4: ReadOnly, User, PowerUser, Admin" -ForegroundColor Gray
        Write-Host "    [3] Viewer-style: Viewer, Editor, Admin" -ForegroundColor Gray
        Write-Host "    [4] Custom (comma-separated)" -ForegroundColor Gray
        $roleChoice = Read-Host "  Choose [1]"
        $roles = switch ($roleChoice) {
            "2" { @("ReadOnly", "User", "PowerUser", "Admin") }
            "3" { @("Viewer", "Editor", "Admin") }
            "4" {
                $customInput = Read-Host "  Enter roles (comma-separated)"
                @($customInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
            }
            default { @("User") }
        }
    } else {
        $currentRolesStr = $roles -join ', '
        $rolesInput = Read-WithDefault "  Roles (comma-separated)" $currentRolesStr
        $roles = @($rolesInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    }
} else {
    # Non-interactive defaults
    if (-not $displayName) { $displayName = $appId }
    if (-not $dotNetDll -and $appType -eq "AspNetCore") { $dotNetDll = "$($appId).dll" }
    if (-not $installSource) { $installSource = if ($appType -eq "AspNetCore") { "WinApp" } else { "None" } }
    $enableDirBrowsing = ($appType -eq "Static")
}

if ($roles.Count -eq 0) {
    Write-Host "  No valid roles entered, defaulting to 'User'." -ForegroundColor Yellow
    $roles = @("User")
}

$rolesJsonArray = '[' + (($roles | ForEach-Object { "`"$_`"" }) -join ', ') + ']'

# ═══════════════════════════════════════════════════════════════════════════════
# TENANT ROUTING
# ═══════════════════════════════════════════════════════════════════════════════
Write-Step "T" "Tenant Routing"

$tenantRaw = Invoke-Psql "SELECT domain, display_name FROM tenants WHERE is_active = true ORDER BY domain;"
$tenants = @()
if ($tenantRaw) {
    foreach ($line in ($tenantRaw -split "`n")) {
        $line = $line.Trim()
        if ($line -and $line -match '\|') {
            $parts = $line -split '\|', 2
            $tenants += [PSCustomObject]@{
                Domain      = $parts[0].Trim()
                DisplayName = $parts[1].Trim()
            }
        }
    }
}

if (-not $baseUrl) { $baseUrl = "http://$($detectedServer)/$($appId)" }
$selectedTenants = @()

if ($NonInteractive) {
    if ($AllTenants -and $tenants.Count -gt 0) {
        $selectedTenants = @($tenants)
    }
    if ($selectedTenants.Count -gt 0) {
        Write-Host "  Will add routing to $($selectedTenants.Count) tenant(s) -> $baseUrl" -ForegroundColor Green
    }
} else {
    if ($tenants.Count -eq 0) {
        Write-Host "  No active tenants found in database." -ForegroundColor Yellow
    } elseif ($tenants.Count -eq 1) {
        Write-Host "  Found 1 tenant: $($tenants[0].DisplayName) ($($tenants[0].Domain))" -ForegroundColor White
        $addTenant = Read-Host "  Add $($appId) routing to this tenant? [Y/n]"
        if ($addTenant -ne 'n' -and $addTenant -ne 'N') {
            $selectedTenants = @($tenants[0])
        }
    } else {
        Write-Host "  Active tenants:" -ForegroundColor White
        $i = 1
        foreach ($t in $tenants) {
            Write-Host "    [$i] $($t.DisplayName) ($($t.Domain))" -ForegroundColor Gray
            $i++
        }
        Write-Host "    [A] All tenants" -ForegroundColor Gray
        $tenantChoice = Read-Host "  Choose [A]"
        if ($tenantChoice -eq 'A' -or $tenantChoice -eq 'a' -or [string]::IsNullOrWhiteSpace($tenantChoice)) {
            $selectedTenants = @($tenants)
        } else {
            $choiceNum = 0
            if ([int]::TryParse($tenantChoice, [ref]$choiceNum) -and $choiceNum -ge 1 -and $choiceNum -le $tenants.Count) {
                $selectedTenants = @($tenants[$choiceNum - 1])
            }
        }
    }

    if ($selectedTenants.Count -gt 0) {
        $baseUrl = Read-WithDefault "  App URL for routing" $baseUrl
        Write-Host "  Will add routing to $($selectedTenants.Count) tenant(s) -> $baseUrl" -ForegroundColor Green
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# USER PERMISSIONS
# ═══════════════════════════════════════════════════════════════════════════════
Write-Step "P" "User Permissions"

$selectedUsers = @()

if ($NonInteractive) {
    $permissionMode = $PermissionMode
    $permissionRole = if ($PermissionRole) { $PermissionRole } elseif ($roles.Count -gt 0) { $roles[0] } else { "User" }
    Write-Host "  Permission mode: $permissionMode (role: $permissionRole)" -ForegroundColor Green
} else {
    Write-Host "  Grant permissions now?" -ForegroundColor White
    Write-Host "    [1] Skip -- no permissions now" -ForegroundColor Gray
    Write-Host "    [2] Grant to ALL active users" -ForegroundColor Gray
    Write-Host "    [3] Grant to Admin-level users only" -ForegroundColor Gray
    Write-Host "    [4] Pick specific users from list" -ForegroundColor Gray
    $permChoice = Read-Host "  Choose [1]"

    $permissionMode = "skip"
    $permissionRole = $null

    switch ($permChoice) {
        "2" { $permissionMode = "all" }
        "3" { $permissionMode = "admins" }
        "4" {
            $permissionMode = "specific"
            $userRaw = Invoke-Psql "SELECT email, display_name, global_access_level FROM users WHERE is_active = true ORDER BY email;"
            $users = @()
            if ($userRaw) {
                foreach ($line in ($userRaw -split "`n")) {
                    $line = $line.Trim()
                    if ($line -and $line -match '\|') {
                        $parts = $line -split '\|', 3
                        $users += [PSCustomObject]@{
                            Email       = $parts[0].Trim()
                            DisplayName = $parts[1].Trim()
                            Level       = $parts[2].Trim()
                        }
                    }
                }
            }
            if ($users.Count -eq 0) {
                Write-Host "  No active users found. Skipping permissions." -ForegroundColor Yellow
                $permissionMode = "skip"
            } else {
                Write-Host ""
                $i = 1
                foreach ($u in $users) {
                    $levelName = switch ($u.Level) {
                        "0" { "ReadOnly" } "1" { "User" } "2" { "PowerUser" } "3" { "Admin" } default { $u.Level }
                    }
                    Write-Host "    [$i] $($u.Email) ($($u.DisplayName), $levelName)" -ForegroundColor Gray
                    $i++
                }
                $userChoices = Read-Host "  Enter user numbers (comma-separated, e.g. '1,3')"
                foreach ($uc in ($userChoices -split ',')) {
                    $ucNum = 0
                    if ([int]::TryParse($uc.Trim(), [ref]$ucNum) -and $ucNum -ge 1 -and $ucNum -le $users.Count) {
                        $selectedUsers += $users[$ucNum - 1]
                    }
                }
                if ($selectedUsers.Count -eq 0) {
                    Write-Host "  No valid users selected. Skipping permissions." -ForegroundColor Yellow
                    $permissionMode = "skip"
                }
            }
        }
    }

    # If granting permissions, ask which role to assign
    if ($permissionMode -ne "skip") {
        if ($roles.Count -eq 1) {
            $permissionRole = $roles[0]
            Write-Host "  Role: $permissionRole (only role available)" -ForegroundColor Green
        } else {
            Write-Host ""
            Write-Host "  Which role to assign?" -ForegroundColor White
            $i = 1
            foreach ($r in $roles) {
                Write-Host "    [$i] $r" -ForegroundColor Gray
                $i++
            }
            $roleIdx = Read-Host "  Choose [1]"
            $roleNum = 0
            if ([int]::TryParse($roleIdx, [ref]$roleNum) -and $roleNum -ge 1 -and $roleNum -le $roles.Count) {
                $permissionRole = $roles[$roleNum - 1]
            } else {
                $permissionRole = $roles[0]
            }
            Write-Host "  Role: $permissionRole" -ForegroundColor Green
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# FINAL SUMMARY + CONFIRM
# ═══════════════════════════════════════════════════════════════════════════════
Write-Header "Final Summary"

Write-Host "  App ID:          $appId" -ForegroundColor White
Write-Host "  Display Name:    $displayName" -ForegroundColor White
Write-Host "  Description:     $(if ($description) { $description } else { '(none)' })" -ForegroundColor White
Write-Host "  App Type:        $appType" -ForegroundColor White
Write-Host "  Roles:           $rolesJsonArray" -ForegroundColor White
if ($appType -eq "AspNetCore") {
    Write-Host "  API Port:        $apiPort" -ForegroundColor White
    Write-Host "  DotNet DLL:      $dotNetDll" -ForegroundColor White
}
Write-Host "  Install Source:  $installSource" -ForegroundColor White
if ($healthEndpoint) {
    Write-Host "  Health Check:    $healthEndpoint" -ForegroundColor White
}
if ($appType -eq "Static") {
    Write-Host "  Dir Browsing:    $enableDirBrowsing" -ForegroundColor White
}

Write-Host ""
Write-Host "  Database operations:" -ForegroundColor Yellow
Write-Host "    - Register app in 'apps' table" -ForegroundColor Gray
if ($selectedTenants.Count -gt 0) {
    foreach ($t in $selectedTenants) {
        Write-Host "    - Add routing to tenant '$($t.Domain)' -> $baseUrl" -ForegroundColor Gray
    }
}
switch ($permissionMode) {
    "all"      { Write-Host "    - Grant '$permissionRole' to ALL active users" -ForegroundColor Gray }
    "admins"   { Write-Host "    - Grant '$permissionRole' to Admin-level users" -ForegroundColor Gray }
    "specific" {
        foreach ($u in $selectedUsers) {
            Write-Host "    - Grant '$permissionRole' to $($u.Email)" -ForegroundColor Gray
        }
    }
    "skip"     { Write-Host "    - No permissions (skip)" -ForegroundColor DarkGray }
}

Write-Host ""
Write-Host "  IIS Deploy Profile:" -ForegroundColor Yellow
$deployJsonFile = Join-Path $deployJsonDir "$($appId)_$($installSource).deploy.json"
Write-Host "    - Generate: $deployJsonFile" -ForegroundColor Gray
Write-Host "    - Deploy IIS-DeployApp to app server" -ForegroundColor Gray
Write-Host "    - Deploy DedgeAuth-IISConfig to app server" -ForegroundColor Gray

Write-Host ""
if (-not $NonInteractive) {
    $confirm = Read-Host "  Proceed? [Y/n]"
    if ($confirm -eq 'n' -or $confirm -eq 'N') {
        Write-Host "  Aborted." -ForegroundColor Red
        exit 0
    }
} else {
    Write-Host "  NonInteractive mode: proceeding automatically." -ForegroundColor Cyan
}

# ═══════════════════════════════════════════════════════════════════════════════
# EXECUTE
# ═══════════════════════════════════════════════════════════════════════════════
Write-Header "Executing"

# --- A: Register app in database (via shared helper) ---
Write-Host "  [1/5] Registering app in database..." -ForegroundColor Cyan
$tenantDomains = @($selectedTenants | ForEach-Object { $_.Domain })
$specificEmails = @($selectedUsers | ForEach-Object { $_.Email })
$registerScript = Join-Path $PSScriptRoot "Register-DedgeAuthApp.ps1"
& $registerScript -DbHost $script:dbHost -DbPort $script:dbPort -DbName $script:dbName -DbUser $script:dbUser -DbPassword $script:dbPassword `
    -AppId $appId -DisplayName $displayName -Description $description -BaseUrl $baseUrl -Roles $roles `
    -TenantDomains $tenantDomains -PermissionMode $permissionMode -PermissionRole $permissionRole -SpecificUserEmails $specificEmails
Write-Host "    Done." -ForegroundColor Green

# --- B: Generate .deploy.json ---
Write-Host "  [2/3] Generating IIS deploy profile..." -ForegroundColor Cyan

$physicalPath = switch ($installSource) {
    "WinApp" { '$env:OptPath\DedgeWinApps\' + $appId }
    "PshApp" { '$env:OptPath\DedgePshApps\' + $appId }
    default  { '$env:OptPath\Webs\' + $appId }
}

$deployProfile = [ordered]@{
    SiteName                = $appId
    PhysicalPath            = $physicalPath
    AppType                 = $appType
    DotNetDll               = $dotNetDll
    AppPoolName             = $appId
    InstallSource           = $installSource
    InstallAppName          = $appId
    VirtualPath             = "/$($appId)"
    ParentSite              = "Default Web Site"
    HealthEndpoint          = $healthEndpoint
    EnableDirectoryBrowsing = $enableDirBrowsing
    IsRootSiteProfile       = $false
    ApiPort                 = $apiPort
    LastDeployed            = ""
    DeployedBy              = ""
    ComputerName            = ""
}

$jsonContent = $deployProfile | ConvertTo-Json -Depth 5
Set-Content -Path $deployJsonFile -Value $jsonContent -Encoding UTF8 -Force
Write-Host "    Created: $deployJsonFile" -ForegroundColor Green

# --- C: Deploy to app server ---
if ($SkipDeploy) {
    Write-Host "  [3/3] Deploying to app server: SKIPPED (-SkipDeploy)" -ForegroundColor DarkGray
} else {
    Write-Host "  [3/3] Deploying to app server..." -ForegroundColor Cyan

    Write-Host "    Running IIS-DeployApp _deploy.ps1..." -ForegroundColor Gray
    try {
        & $iisDeployScript
        Write-Host "    IIS-DeployApp deployed." -ForegroundColor Green
    } catch {
        Write-Host "    WARNING: IIS-DeployApp deploy failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    Write-Host "    Running DedgeAuth-IISConfig _deploy.ps1..." -ForegroundColor Gray
    try {
        & $DedgeAuthIISDeploy
        Write-Host "    DedgeAuth-IISConfig deployed." -ForegroundColor Green
    } catch {
        Write-Host "    WARNING: DedgeAuth-IISConfig deploy failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# DONE
# ═══════════════════════════════════════════════════════════════════════════════
Write-Header "Complete"

Write-Host "  App '$($appId)' has been registered in DedgeAuth." -ForegroundColor Green
Write-Host "  IIS deploy profile: $deployJsonFile" -ForegroundColor Green
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Yellow
Write-Host "    1. On the app server, run IIS-DeployApp.ps1 and select the '$($appId)' profile" -ForegroundColor Gray
Write-Host "    2. Verify the app is accessible at $baseUrl" -ForegroundColor Gray
Write-Host ""
