<#
.SYNOPSIS
    Registers or upserts an application in the DedgeAuth database (apps, tenant routing, permissions).

.DESCRIPTION
    Reusable helper for DedgeAuth app registration. Called by DedgeAuth-AddAppSupport.ps1 (interactive wizard)
    and by IIS-Handler during template-driven deploy. Performs:
    1. INSERT/UPDATE app in apps table (ON CONFLICT DO UPDATE)
    2. Tenant routing updates (app_routing_json) for specified tenant domains
    3. User permission grants (skip, all, admins, or specific users)

    Password: use -DbPassword or env var DedgeAuth_DbPassword. Never store in templates.

.PARAMETER DbHost
    PostgreSQL host for DedgeAuth database.

.PARAMETER DbPort
    PostgreSQL port.

.PARAMETER DbName
    Database name (default DedgeAuth).

.PARAMETER DbUser
    PostgreSQL user.

.PARAMETER DbPassword
    PostgreSQL password. If not provided, uses $env:DedgeAuth_DbPassword.

.PARAMETER AppId
    Application ID (unique key in apps table).

.PARAMETER DisplayName
    Human-readable display name.

.PARAMETER Description
    Optional description.

.PARAMETER BaseUrl
    Base URL for the application (e.g. http://server/DocView).

.PARAMETER Roles
    Array of role names (stored as JSON in available_roles_json).

.PARAMETER TenantDomains
    Array of tenant domain names to add app routing for. Each gets app_routing_json updated.

.PARAMETER PermissionMode
    skip, all, admins, or specific.

.PARAMETER PermissionRole
    Role to grant when PermissionMode is not skip.

.PARAMETER SpecificUserEmails
    When PermissionMode is specific, list of user emails to grant.

.PARAMETER Unattended
    If set, SQL errors are not written to host; script throws on failure.

.EXAMPLE
    .\Register-DedgeAuthApp.ps1 -DbHost "t-no1fkxtst-db" -DbPort 8432 -DbName "DedgeAuth" -DbUser "postgres" -AppId "DocView" -DisplayName "Doc View" -BaseUrl "http://localhost/DocView" -Roles @("User") -TenantDomains @("acme.com") -PermissionMode skip -Unattended
#>
[System.Diagnostics.CodeAnalysis.SuppressMessage('Security', 'PSAvoidUsingPlainTextForPassword', Justification = 'PostgreSql-Handler and env DedgeAuth_DbPassword')]
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DbHost,
    [Parameter(Mandatory = $true)]
    [int]$DbPort,
    [Parameter(Mandatory = $false)]
    [string]$DbName = "DedgeAuth",
    [Parameter(Mandatory = $true)]
    [string]$DbUser,
    [Parameter(Mandatory = $false)]
    [string]$DbPassword = $env:DedgeAuth_DbPassword,
    [Parameter(Mandatory = $true)]
    [string]$AppId,
    [Parameter(Mandatory = $false)]
    [string]$DisplayName = "",
    [Parameter(Mandatory = $false)]
    [string]$Description = "",
    [Parameter(Mandatory = $false)]
    [string]$BaseUrl = "",
    [Parameter(Mandatory = $false)]
    [string[]]$Roles = @("User"),
    [Parameter(Mandatory = $false)]
    [string[]]$TenantDomains = @(),
    [Parameter(Mandatory = $false)]
    [ValidateSet("skip", "all", "admins", "specific")]
    [string]$PermissionMode = "skip",
    [Parameter(Mandatory = $false)]
    [string]$PermissionRole = "User",
    [Parameter(Mandatory = $false)]
    [string[]]$SpecificUserEmails = @(),
    # When provided, sets global_access_level=3 and upserts the highest role for these emails.
    # Supplements PermissionMode (e.g. pass AdminEmails from appsettings.json to enforce admin access).
    [Parameter(Mandatory = $false)]
    [string[]]$AdminEmails = @(),
    [Parameter(Mandatory = $false)]
    [string]$GroupsJson = "",
    [Parameter(Mandatory = $false)]
    [switch]$Unattended
)

$ErrorActionPreference = "Stop"
Import-Module PostgreSql-Handler -Force

if ([string]::IsNullOrWhiteSpace($DbPassword)) {
    if (-not $Unattended) {
        Write-Host "  DedgeAuth DB password not set. Use -DbPassword or set env DedgeAuth_DbPassword." -ForegroundColor Red
    }
    throw "DedgeAuth DB password is required ( -DbPassword or env:DedgeAuth_DbPassword )."
}

if ([string]::IsNullOrWhiteSpace($DisplayName)) {
    $DisplayName = $AppId
}

$rolesJsonArray = '[' + (($Roles | ForEach-Object { "`"$_`"" }) -join ', ') + ']'
$escapedDisplayName = $DisplayName -replace "'", "''"
$descSql = if ($Description) { "'$($Description -replace "'", "''")'" } else { "NULL" }
$baseUrlEscaped = $BaseUrl -replace "'", "''"

# 1) Upsert app
$appSql = @"
INSERT INTO apps (id, app_id, display_name, description, base_url, available_roles_json, is_active, created_at)
VALUES (gen_random_uuid(), '$($AppId)', '$($escapedDisplayName)', $descSql, '$($baseUrlEscaped)', '$($rolesJsonArray)', true, NOW())
ON CONFLICT (app_id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  description = EXCLUDED.description,
  base_url = EXCLUDED.base_url,
  available_roles_json = EXCLUDED.available_roles_json,
  is_active = true;
"@
$result = Invoke-PostgreSqlQuery -Host $DbHost -Port $DbPort -User $DbUser -Password $DbPassword -Database $DbName -Query $appSql -Unattended:$Unattended
if ($null -eq $result -and -not $Unattended) {
    Write-Host "  SQL Error (app upsert)" -ForegroundColor Red
}
if ($null -eq $result) {
    throw "DedgeAuth app registration failed (apps table)."
}

# 2) Tenant routing
foreach ($domain in $TenantDomains) {
    if ([string]::IsNullOrWhiteSpace($domain)) { continue }
    $domainEscaped = $domain -replace "'", "''"
    $routeSql = "UPDATE tenants SET app_routing_json = jsonb_set(COALESCE(app_routing_json::jsonb, '{}'), '{$($AppId)}', to_jsonb('$($baseUrlEscaped)'::text))::text WHERE domain = '$($domainEscaped)';"
    $r = Invoke-PostgreSqlQuery -Host $DbHost -Port $DbPort -User $DbUser -Password $DbPassword -Database $DbName -Query $routeSql -Unattended:$Unattended
    if ($null -eq $r -and -not $Unattended) {
        Write-Host "  SQL Error (tenant routing for $domain)" -ForegroundColor Red
    }
    if ($null -eq $r) {
        throw "DedgeAuth tenant routing failed for domain: $($domain)."
    }
}

# 3) User permissions
if ($PermissionMode -ne "skip") {
    $whereClause = switch ($PermissionMode) {
        "all"      { "u.is_active = true" }
        "admins"   { "u.is_active = true AND u.global_access_level = 3" }
        "specific" {
            if ($SpecificUserEmails.Count -eq 0) {
                throw "PermissionMode is 'specific' but SpecificUserEmails is empty."
            }
            $emails = ($SpecificUserEmails | ForEach-Object { "'$($_ -replace "'", "''")'" }) -join ', '
            "u.email IN ($($emails))"
        }
        default { "u.is_active = true" }
    }
    $permSql = "INSERT INTO app_permissions (id, user_id, app_id, role, granted_at, granted_by) SELECT gen_random_uuid(), u.id, a.id, '$($PermissionRole -replace "'", "''")', NOW(), 'Register-DedgeAuthApp' FROM users u, apps a WHERE $whereClause AND a.app_id = '$($AppId)' ON CONFLICT DO NOTHING;"
    $p = Invoke-PostgreSqlQuery -Host $DbHost -Port $DbPort -User $DbUser -Password $DbPassword -Database $DbName -Query $permSql -Unattended:$Unattended
    if ($null -eq $p -and -not $Unattended) {
        Write-Host "  SQL Error (permissions)" -ForegroundColor Red
    }
    if ($null -eq $p) {
        throw "DedgeAuth permission grant failed."
    }
}

# 4) Sync AdminEmails: ensure global_access_level=3 and highest role on this app
if ($AdminEmails.Count -gt 0) {
    $highestRole = if ($Roles.Count -gt 0) { $Roles[-1] } else { "Admin" }
    $highestRoleEscaped = $highestRole -replace "'", "''"
    foreach ($email in $AdminEmails) {
        if ([string]::IsNullOrWhiteSpace($email)) { continue }
        $emailEscaped = $email -replace "'", "''"

        $levelSql = "UPDATE users SET global_access_level = 3 WHERE LOWER(email) = LOWER('$($emailEscaped)');"
        Invoke-PostgreSqlQuery -Host $DbHost -Port $DbPort -User $DbUser -Password $DbPassword `
            -Database $DbName -Query $levelSql -Unattended:$Unattended | Out-Null

        $adminPermSql = @"
INSERT INTO app_permissions (id, user_id, app_id, role, granted_at, granted_by)
SELECT gen_random_uuid(), u.id, a.id, '$($highestRoleEscaped)', NOW(), 'Register-DedgeAuthApp-AdminSync'
FROM users u, apps a
WHERE LOWER(u.email) = LOWER('$($emailEscaped)') AND a.app_id = '$($AppId)'
ON CONFLICT (user_id, app_id) DO UPDATE SET role = EXCLUDED.role, granted_at = EXCLUDED.granted_at, granted_by = EXCLUDED.granted_by;
"@
        Invoke-PostgreSqlQuery -Host $DbHost -Port $DbPort -User $DbUser -Password $DbPassword `
            -Database $DbName -Query $adminPermSql -Unattended:$Unattended | Out-Null

        if (-not $Unattended) {
            Write-Host "  Admin email synced: $($email) -> $($AppId)/$($highestRole), global_access_level=3" -ForegroundColor Green
        }
    }
}

# 5) Group placement (auto-create hierarchy + link app to leaf groups)
if (-not [string]::IsNullOrWhiteSpace($GroupsJson)) {
    try {
        $groupsMap = $GroupsJson | ConvertFrom-Json
        foreach ($domain in $groupsMap.PSObject.Properties.Name) {
            $slugPaths = @($groupsMap.$domain)
            foreach ($slugPath in $slugPaths) {
                $segments = $slugPath -split '/'
                $parentIdExpr = "NULL"
                foreach ($segment in $segments) {
                    $segEsc = $segment -replace "'", "''"
                    $domEsc = $domain -replace "'", "''"
                    $groupSql = @"
INSERT INTO app_groups (id, tenant_id, name, slug, parent_id, sort_order, created_at)
SELECT gen_random_uuid(), t.id, '$($segEsc)', '$($segEsc)',
       $($parentIdExpr), 0, NOW()
FROM tenants t WHERE t.domain = '$($domEsc)'
ON CONFLICT (tenant_id, slug) DO NOTHING;
"@
                    Invoke-PostgreSqlQuery -Host $DbHost -Port $DbPort -User $DbUser -Password $DbPassword `
                        -Database $DbName -Query $groupSql -Unattended:$Unattended | Out-Null

                    $parentIdExpr = "(SELECT id FROM app_groups ag JOIN tenants t ON ag.tenant_id = t.id WHERE ag.slug = '$($segEsc)' AND t.domain = '$($domEsc)')"
                }

                $leafSlug = ($segments[-1]) -replace "'", "''"
                $linkSql = @"
INSERT INTO app_group_items (id, app_group_id, app_id, sort_order)
SELECT gen_random_uuid(), g.id, a.id, 0
FROM app_groups g
JOIN tenants t ON g.tenant_id = t.id
CROSS JOIN apps a
WHERE g.slug = '$($leafSlug)'
  AND t.domain = '$($domEsc)'
  AND a.app_id = '$($AppId)'
ON CONFLICT (app_group_id, app_id) DO NOTHING;
"@
                Invoke-PostgreSqlQuery -Host $DbHost -Port $DbPort -User $DbUser -Password $DbPassword `
                    -Database $DbName -Query $linkSql -Unattended:$Unattended | Out-Null
            }
            if (-not $Unattended) {
                Write-Host "  App '$($AppId)' placed in groups for tenant '$($domain)': $($slugPaths -join ', ')" -ForegroundColor Green
            }
        }
    } catch {
        if (-not $Unattended) {
            Write-Host "  Group placement failed: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}
