<#
.SYNOPSIS
    Interactive tool to list all DedgeAuth-registered apps and delete a selected one.

.DESCRIPTION
    Connects to the DedgeAuth PostgreSQL database, lists all registered applications,
    and lets the user pick one to remove. Removal covers:
    1. App permissions (app_permissions table)
    2. Tenant routing references (app_routing_json in tenants table)
    3. The app record itself (apps table)
    4. Optionally deletes the matching IIS .deploy.json template

.PARAMETER NonInteractive
    Skip confirmation prompts. Requires -AppId.

.PARAMETER AppId
    Directly specify which app to remove (skips the selection menu).

.EXAMPLE
    .\DedgeAuth-RemoveAppSupport.ps1
    .\DedgeAuth-RemoveAppSupport.ps1 -AppId "DocView"
    .\DedgeAuth-RemoveAppSupport.ps1 -AppId "DocView" -NonInteractive
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$AppId = "",
    [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"

Import-Module PostgreSql-Handler -Force

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION (same as DedgeAuth-AddAppSupport)
# ═══════════════════════════════════════════════════════════════════════════════
$script:dbHost     = "t-no1fkxtst-db"
$script:dbPort     = 8432
$script:dbName     = "DedgeAuth"
$script:dbUser     = "postgres"
$script:dbPassword = "postgres"

$deployJsonDir = "C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\templates"

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

# ═══════════════════════════════════════════════════════════════════════════════
# PREFLIGHT
# ═══════════════════════════════════════════════════════════════════════════════
$psqlPath = Get-PostgreSqlPsqlPath
if (-not $psqlPath) {
    Write-Host "  ERROR: PostgreSQL client (psql) not found." -ForegroundColor Red
    exit 1
}

$connTest = Invoke-Psql "SELECT 1;"
if ($null -eq $connTest) {
    Write-Host "  ERROR: Cannot connect to $($script:dbHost):$($script:dbPort)/$($script:dbName)" -ForegroundColor Red
    exit 1
}

Write-Header "DedgeAuth - Remove App"

# ═══════════════════════════════════════════════════════════════════════════════
# LIST APPS
# ═══════════════════════════════════════════════════════════════════════════════
$existingAppsRaw = Invoke-Psql "SELECT app_id, display_name, is_active, base_url FROM apps ORDER BY app_id;"
$existingApps = @()
if ($existingAppsRaw) {
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
}

if ($existingApps.Count -eq 0) {
    Write-Host "  No applications registered. Nothing to remove." -ForegroundColor DarkGray
    exit 0
}

Write-Host "  Registered applications ($($existingApps.Count)):" -ForegroundColor White
Write-Host ""
$i = 1
foreach ($app in $existingApps) {
    $statusColor = if ($app.IsActive -eq 't') { "Green" } else { "DarkGray" }
    $statusLabel = if ($app.IsActive -eq 't') { "active" } else { "inactive" }
    Write-Host "    [$i] " -ForegroundColor Yellow -NoNewline
    Write-Host "$($app.AppId)" -ForegroundColor $statusColor -NoNewline
    Write-Host "  $($app.DisplayName)" -ForegroundColor Gray -NoNewline
    Write-Host "  [$statusLabel]" -ForegroundColor $statusColor -NoNewline
    if ($app.BaseUrl) {
        Write-Host "  $($app.BaseUrl)" -ForegroundColor DarkGray
    } else {
        Write-Host ""
    }
    $i++
}
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# SELECT APP
# ═══════════════════════════════════════════════════════════════════════════════
$selectedApp = $null

if ($AppId) {
    $selectedApp = $existingApps | Where-Object { $_.AppId -eq $AppId }
    if (-not $selectedApp) {
        Write-Host "  ERROR: App '$($AppId)' not found in database." -ForegroundColor Red
        exit 1
    }
} else {
    $choice = Read-Host "  Select app to remove [1-$($existingApps.Count)] or Q to quit"
    if ($choice -eq 'Q' -or $choice -eq 'q') {
        Write-Host "  Cancelled." -ForegroundColor DarkGray
        exit 0
    }
    $choiceNum = 0
    if (-not ([int]::TryParse($choice, [ref]$choiceNum)) -or $choiceNum -lt 1 -or $choiceNum -gt $existingApps.Count) {
        Write-Host "  Invalid selection." -ForegroundColor Red
        exit 1
    }
    $selectedApp = $existingApps[$choiceNum - 1]
}

$targetAppId = $selectedApp.AppId

# ═══════════════════════════════════════════════════════════════════════════════
# IMPACT ANALYSIS
# ═══════════════════════════════════════════════════════════════════════════════
Write-Header "Impact Analysis for '$($targetAppId)'"

# Count permissions
$permCountRaw = Invoke-Psql "SELECT COUNT(*) FROM app_permissions ap JOIN apps a ON ap.app_id = a.id WHERE a.app_id = '$($targetAppId)';"
$permCount = 0
if ($permCountRaw) {
    [int]::TryParse(($permCountRaw -split "`n" | Where-Object { $_.Trim() -match '^\d+$' } | Select-Object -First 1).Trim(), [ref]$permCount) | Out-Null
}

# Find tenants with routing
$tenantRoutingRaw = Invoke-Psql "SELECT domain FROM tenants WHERE app_routing_json::text LIKE '%$($targetAppId)%';"
$affectedTenants = @()
if ($tenantRoutingRaw) {
    foreach ($line in ($tenantRoutingRaw -split "`n")) {
        $line = $line.Trim()
        if ($line -and $line -ne '' -and $line -notmatch '^\-+$' -and $line -notmatch '^domain$' -and $line -notmatch '^\(' ) {
            $affectedTenants += $line
        }
    }
}

# Check for .deploy.json files
$deployFiles = @(Get-ChildItem -Path $deployJsonDir -Filter "$($targetAppId)_*.deploy.json" -File -ErrorAction SilentlyContinue)

Write-Host "  App:              $($selectedApp.AppId)  ($($selectedApp.DisplayName))" -ForegroundColor White
Write-Host "  Status:           $(if ($selectedApp.IsActive -eq 't') { 'active' } else { 'inactive' })" -ForegroundColor White
Write-Host "  Permissions:      $($permCount) user permission(s) will be removed" -ForegroundColor White
if ($affectedTenants.Count -gt 0) {
    Write-Host "  Tenant routing:   $($affectedTenants.Count) tenant(s): $($affectedTenants -join ', ')" -ForegroundColor White
} else {
    Write-Host "  Tenant routing:   none" -ForegroundColor DarkGray
}
if ($deployFiles.Count -gt 0) {
    foreach ($df in $deployFiles) {
        Write-Host "  Deploy template:  $($df.Name)" -ForegroundColor White
    }
} else {
    Write-Host "  Deploy template:  none found" -ForegroundColor DarkGray
}

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIRM
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "  This will permanently delete the app and all related data." -ForegroundColor Red

if (-not $NonInteractive) {
    $confirm = Read-Host "  Type the App ID to confirm deletion [$($targetAppId)]"
    if ($confirm -ne $targetAppId) {
        Write-Host "  Confirmation did not match. Aborted." -ForegroundColor Yellow
        exit 0
    }
} else {
    Write-Host "  NonInteractive mode: proceeding." -ForegroundColor Cyan
}

# ═══════════════════════════════════════════════════════════════════════════════
# EXECUTE REMOVAL
# ═══════════════════════════════════════════════════════════════════════════════
Write-Header "Removing '$($targetAppId)'"

# 1) Remove permissions
Write-Host "  [1/4] Removing app_permissions..." -ForegroundColor Cyan
$delPermSql = "DELETE FROM app_permissions WHERE app_id = (SELECT id FROM apps WHERE app_id = '$($targetAppId)');"
$r = Invoke-Psql $delPermSql
if ($null -ne $r) {
    Write-Host "    $($permCount) permission(s) removed." -ForegroundColor Green
} else {
    Write-Host "    WARNING: Could not remove permissions." -ForegroundColor Yellow
}

# 2) Remove tenant routing references
Write-Host "  [2/4] Removing tenant routing..." -ForegroundColor Cyan
if ($affectedTenants.Count -gt 0) {
    foreach ($domain in $affectedTenants) {
        $domainEscaped = $domain -replace "'", "''"
        $routeSql = "UPDATE tenants SET app_routing_json = (app_routing_json::jsonb - '$($targetAppId)')::text WHERE domain = '$($domainEscaped)';"
        $r = Invoke-Psql $routeSql
        if ($null -ne $r) {
            Write-Host "    Removed from tenant '$($domain)'." -ForegroundColor Green
        } else {
            Write-Host "    WARNING: Could not update tenant '$($domain)'." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "    No tenant routing to remove." -ForegroundColor DarkGray
}

# 3) Delete app record
Write-Host "  [3/4] Deleting app record..." -ForegroundColor Cyan
$delAppSql = "DELETE FROM apps WHERE app_id = '$($targetAppId)';"
$r = Invoke-Psql $delAppSql
if ($null -ne $r) {
    Write-Host "    App '$($targetAppId)' deleted from database." -ForegroundColor Green
} else {
    Write-Host "    WARNING: Could not delete app record." -ForegroundColor Yellow
}

# 4) Delete .deploy.json templates
Write-Host "  [4/4] Cleaning deploy templates..." -ForegroundColor Cyan
if ($deployFiles.Count -gt 0) {
    foreach ($df in $deployFiles) {
        if (-not $NonInteractive) {
            $delFile = Read-Host "    Delete $($df.Name)? [Y/n]"
            if ($delFile -eq 'n' -or $delFile -eq 'N') {
                Write-Host "      Kept: $($df.FullName)" -ForegroundColor DarkGray
                continue
            }
        }
        Remove-Item $df.FullName -Force
        Write-Host "      Deleted: $($df.Name)" -ForegroundColor Green
    }
} else {
    Write-Host "    No deploy templates to clean." -ForegroundColor DarkGray
}

# ═══════════════════════════════════════════════════════════════════════════════
# DONE
# ═══════════════════════════════════════════════════════════════════════════════
Write-Header "Complete"

Write-Host "  App '$($targetAppId)' has been removed from DedgeAuth." -ForegroundColor Green
Write-Host ""
Write-Host "  Note: The IIS site/app pool on the server is NOT removed automatically." -ForegroundColor Yellow
Write-Host "  To fully decommission, manually remove the IIS site on the app server." -ForegroundColor Yellow
Write-Host ""
