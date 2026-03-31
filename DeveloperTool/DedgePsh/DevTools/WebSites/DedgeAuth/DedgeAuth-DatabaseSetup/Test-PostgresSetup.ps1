<#
.SYNOPSIS
    Validates PostgreSQL installation, configuration, and connectivity.
.DESCRIPTION
    Checks PostgreSQL installation, data directory, port configuration,
    service status, firewall rules, and connectivity.
.PARAMETER Port
    Expected PostgreSQL port. Default: 8432
#>
[CmdletBinding()]
param(
    [int]$Port = 8432
)

Import-Module GlobalFunctions -Force
Import-Module PostgreSql-Handler -Force

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  PostgreSQL Diagnostic Report - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "  Computer: $($env:COMPUTERNAME)" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

$result = Test-PostgreSqlSetup -Port $Port -Password "postgres"

if (-not $result.Passed) {
    foreach ($issue in $result.Issues) {
        Write-Host "  - $issue" -ForegroundColor Red
    }
    exit 1
}
exit 0
