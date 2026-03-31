<#
.SYNOPSIS
    Repairs a broken PostgreSQL installation where binaries exist but no data directory or service.
.DESCRIPTION
    After a failed unattended install, this script:
    1. Initializes the database cluster using initdb
    2. Configures postgresql.conf (port, listen_addresses)
    3. Configures pg_hba.conf for network access
    4. Registers and starts the Windows service
    5. Opens the firewall port
.PARAMETER DataDir
    Data directory path. Default: E:\pg (falls back to C:\Program Files\PostgreSQL\18\data)
.PARAMETER Port
    PostgreSQL port. Default: 8432
.PARAMETER SuperPassword
    Database superuser (postgres) password. Default: postgres
#>
[CmdletBinding()]
param(
    [string]$DataDir = "E:\pg",
    [int]$Port = 8432,
    [string]$SuperPassword = "postgres"
)

$ErrorActionPreference = "Stop"

Import-Module GlobalFunctions -Force
Import-Module PostgreSql-Handler -Force

Write-Host ""
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host "  GenericLogHandler – PostgreSQL Repair Script" -ForegroundColor Cyan
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host ""

Repair-PostgreSqlInstall -DataDir $DataDir -Port $Port -SuperPassword $SuperPassword

Write-Host ""
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host "  Repair Complete" -ForegroundColor Green
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host ""
