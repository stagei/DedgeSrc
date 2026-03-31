<#
.SYNOPSIS
    Installs PostgreSQL 18 server (DB host) or client tools only (app host) via SoftwareUtils\Install-WindowsApps.

.DESCRIPTION
    - DbServer: PostgreSQL.18 (full server, port 8432 per SoftwareUtils switch)
    - AppServer: PostgreSQL.18.Client (psql, pg_dump, pg_restore for app server tooling)

    Requires PostgreSQL installer media under Get-WindowsAppsPath (Software share layout).
    Run elevated on the target server (IIS / orchestrator).

.PARAMETER Role
    DbServer or AppServer
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('AppServer', 'DbServer')]
    [string]$Role
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force
Import-Module SoftwareUtils -Force
Import-Module Infrastructure -Force

Write-LogMessage "Install-Pg18-ForPrd.ps1 Role=$($Role)" -Level JOB_STARTED

try {
    if ($Role -eq 'DbServer') {
        Write-LogMessage "Installing PostgreSQL.18 (server)..." -Level INFO
        Install-WindowsApps -AppName 'PostgreSQL.18' -Force
    }
    else {
        Write-LogMessage "Installing PostgreSQL.18.Client..." -Level INFO
        Install-WindowsApps -AppName 'PostgreSQL.18.Client' -Force
    }
    Write-LogMessage "Install-Pg18-ForPrd.ps1 completed" -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Install-Pg18-ForPrd failed: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage "Install-Pg18-ForPrd.ps1" -Level JOB_FAILED
    exit 1
}
