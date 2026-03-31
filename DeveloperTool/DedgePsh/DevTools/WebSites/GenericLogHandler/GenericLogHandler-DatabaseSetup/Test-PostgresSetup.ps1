<#
.SYNOPSIS
    Validates PostgreSQL installation, configuration, and connectivity for GenericLogHandler.
.DESCRIPTION
    Checks PostgreSQL installation, data directory, port configuration,
    service status, firewall rules, connectivity, and GenericLogHandler database existence.
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
Write-Host "  GenericLogHandler – PostgreSQL Diagnostic Report" -ForegroundColor Cyan
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  |  $($env:COMPUTERNAME)" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

$result = Test-PostgreSqlSetup -Port $Port -Password "postgres" -DatabaseName "GenericLogHandler"

if (-not $result.Passed) {
    foreach ($issue in $result.Issues) {
        Write-Host "  - $issue" -ForegroundColor Red
    }
    exit 1
}
exit 0
