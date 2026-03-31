<#
.SYNOPSIS
    Updates the Dedge tenant CSS in the DedgeAuth database.

.DESCRIPTION
    Updates the css_overrides column for the Dedge.no tenant with a
    comprehensive CSS theme that covers all DedgeAuth consumer apps:
    DedgeAuth, DocView, GenericLogHandler, ServerMonitorDashboard.

    The CSS defines all shared CSS variables (colors, shadows, borders, etc.)
    and common component overrides (header, buttons) using the FK Green color scheme.
    Apps load their own local CSS first, then this tenant CSS overrides common elements.

.PARAMETER PostgresHost
    PostgreSQL host. Default: t-no1fkxtst-db

.PARAMETER PostgresPort
    PostgreSQL port. Default: 8432

.PARAMETER PostgresUser
    PostgreSQL username. Default: postgres

.PARAMETER PostgresPassword
    PostgreSQL password. Default: postgres

.PARAMETER DatabaseName
    Database name. Default: DedgeAuth

.PARAMETER TenantDomain
    Tenant domain to update. Default: Dedge.no

.EXAMPLE
    .\DedgeAuth-Update-TenantCss.ps1
    Updates the Dedge.no tenant CSS using default connection.

.EXAMPLE
    .\DedgeAuth-Update-TenantCss.ps1 -TenantDomain "custom.no"
    Updates CSS for a different tenant.
#>

[CmdletBinding()]
param(
    [string]$PostgresHost = "t-no1fkxtst-db",
    [int]$PostgresPort = 8432,
    [string]$PostgresUser = "postgres",
    [string]$PostgresPassword = "postgres",
    [string]$DatabaseName = "DedgeAuth",
    [string]$TenantDomain = "Dedge.no"
)

$ErrorActionPreference = "Stop"
Import-Module GlobalFunctions -Force

Write-LogMessage "DedgeAuth-Update-TenantCss: Updating CSS for tenant '$($TenantDomain)'" -Level INFO

# ═══════════════════════════════════════════════════════════════════════════════
# COMPREHENSIVE TENANT CSS
# Covers all consumer apps: DedgeAuth, DocView, GenericLogHandler, ServerMonitorDashboard
# ═══════════════════════════════════════════════════════════════════════════════

$tenantCss = @'
/* ═══════════════════════════════════════════════════════════════════
   Dedge Tenant Theme
   Comprehensive CSS variables for all DedgeAuth consumer apps:
   DedgeAuth, DocView, GenericLogHandler, ServerMonitorDashboard.
   Loaded AFTER each app's local CSS to enforce consistent theming.
   ═══════════════════════════════════════════════════════════════════ */

/* ── Light Theme ─────────────────────────────────────────────────── */
:root {
    /* Brand Colors - FK Green */
    --primary-color: #008942;
    --primary-hover: #00b359;

    /* Backgrounds (shared across all apps) */
    --bg-primary: #f8fafc;
    --bg-secondary: #ffffff;
    --bg-tertiary: #f1f5f9;
    --bg-card: #ffffff;
    --bg-hover: #f1f5f9;
    --bg-input: #ffffff;

    /* Text */
    --text-primary: #0f172a;
    --text-secondary: #475569;
    --text-muted: #94a3b8;

    /* Borders */
    --border-color: #cbd5e1;
    --border-focus: #008942;
    --card-border: 1px solid #e2e8f0;

    /* Accent */
    --accent-color: #0369a1;
    --accent-hover: #0284c7;

    /* Status */
    --success-color: #059669;
    --warning-color: #d97706;
    --error-color: #dc2626;
    --info-color: #0284c7;
    --danger-color: #dc2626;
    --critical-color: #dc2626;

    /* Shadows */
    --shadow: 0 1px 3px rgba(0, 0, 0, 0.12), 0 1px 2px rgba(0, 0, 0, 0.08);
    --shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.05);
    --shadow-md: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
    --shadow-lg: 0 4px 12px rgba(0, 0, 0, 0.15), 0 2px 6px rgba(0, 0, 0, 0.1);

    /* Shape */
    --radius: 8px;
    --font-mono: 'JetBrains Mono', 'Fira Code', 'Consolas', monospace;

    /* ServerMonitor: gauge, panels */
    --gauge-bg: #e2e8f0;
    --panel-header-bg: linear-gradient(135deg, #f8fafc, #f1f5f9);

    /* Config/form editors: selection */
    --selection-bg: #0369a1;
    --selection-text: #ffffff;

    /* DocView: tree, code blocks */
    --tree-hover: #f0f0f5;
    --code-bg: #f6f8fa;
}

/* ── Dark Theme ──────────────────────────────────────────────────── */
[data-theme="dark"] {
    --primary-color: #00b359;
    --primary-hover: #00cc66;

    --bg-primary: #1f1f1f;
    --bg-secondary: #2a2a2a;
    --bg-tertiary: #333333;
    --bg-card: #000000;
    --bg-hover: #333333;
    --bg-input: #333333;

    --text-primary: #f8fafc;
    --text-secondary: #e4e4e7;
    --text-muted: #d4d4d8;

    --border-color: #444444;
    --border-focus: #60a5fa;
    --card-border: 1px solid #444444;

    --accent-color: #60a5fa;
    --accent-hover: #3b82f6;

    --success-color: #34d399;
    --warning-color: #fbbf24;
    --error-color: #f87171;
    --info-color: #38bdf8;
    --danger-color: #f87171;
    --critical-color: #f87171;

    --shadow: 0 1px 3px rgba(0, 0, 0, 0.4), 0 1px 2px rgba(0, 0, 0, 0.3);
    --shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.3);
    --shadow-md: 0 4px 6px -1px rgba(0, 0, 0, 0.4);
    --shadow-lg: 0 4px 12px rgba(0, 0, 0, 0.5), 0 2px 6px rgba(0, 0, 0, 0.4);

    --gauge-bg: #333333;
    --panel-header-bg: linear-gradient(135deg, #2a2a2a, #333333);

    --selection-bg: #60a5fa;
    --selection-text: #ffffff;

    --tree-hover: #2d2d30;
    --code-bg: #24292e;
}

/* ── Common Component Overrides ──────────────────────────────────── */

/* App header - FK Green gradient */
.app-header, header.header {
    background: linear-gradient(135deg, #008942, #006633) !important;
    color: white !important;
}

.app-header a, header.header a,
.app-header .nav-link, header.header .nav-link {
    color: rgba(255, 255, 255, 0.9) !important;
}

.app-header a:hover, header.header a:hover,
.app-header .nav-link:hover, header.header .nav-link:hover {
    color: #ffffff !important;
}

/* Tenant logo */
.tenant-logo {
    max-width: 200px;
    height: auto;
}

/* Primary buttons - FK Green */
.btn-primary, button.btn-primary {
    background-color: var(--primary-color);
    border-color: var(--primary-color);
}

.btn-primary:hover, button.btn-primary:hover {
    background-color: var(--primary-hover);
    border-color: var(--primary-hover);
}
'@

# ═══════════════════════════════════════════════════════════════════════════════
# FIND PSQL
# ═══════════════════════════════════════════════════════════════════════════════

$psqlPaths = @(
    "C:\Program Files\PostgreSQL\18\bin\psql.exe",
    "C:\Program Files\PostgreSQL\17\bin\psql.exe",
    "C:\Program Files\PostgreSQL\16\bin\psql.exe"
)
$psql = $psqlPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $psql) {
    Write-LogMessage "psql.exe not found. Install PostgreSQL or add to PATH." -Level ERROR
    exit 1
}
Write-LogMessage "Using psql: $($psql)" -Level DEBUG

# ═══════════════════════════════════════════════════════════════════════════════
# UPDATE TENANT CSS
# ═══════════════════════════════════════════════════════════════════════════════

$env:PGPASSWORD = $PostgresPassword

# Write CSS to temp file as UTF-8 (avoids encoding issues with psql -c)
$escapedCss = $tenantCss -replace "'", "''"
$sqlContent = "UPDATE tenants SET css_overrides = '$($escapedCss)' WHERE domain = '$($TenantDomain)';"
$tempSql = Join-Path $env:TEMP "DedgeAuth_update_tenant_css.sql"
[System.IO.File]::WriteAllText($tempSql, $sqlContent, [System.Text.Encoding]::UTF8)

try {
    $result = & $psql -h $PostgresHost -p $PostgresPort -U $PostgresUser -d $DatabaseName -f $tempSql 2>&1
    $resultStr = $result | Out-String

    if ($resultStr -match "UPDATE 1") {
        Write-LogMessage "Tenant CSS updated for '$($TenantDomain)'" -Level INFO
    }
    elseif ($resultStr -match "UPDATE 0") {
        Write-LogMessage "No tenant found with domain '$($TenantDomain)'" -Level WARN
    }
    else {
        Write-LogMessage "psql output: $($resultStr.Trim())" -Level WARN
    }
}
catch {
    Write-LogMessage "Failed to update tenant CSS: $($_.Exception.Message)" -Level ERROR
    exit 1
}
finally {
    Remove-Item $tempSql -Force -ErrorAction SilentlyContinue
    $env:PGPASSWORD = $null
}

Write-LogMessage "DedgeAuth-Update-TenantCss completed" -Level INFO
