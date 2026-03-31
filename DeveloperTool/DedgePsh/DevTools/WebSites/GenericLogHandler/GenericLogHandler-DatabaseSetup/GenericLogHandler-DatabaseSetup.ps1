<#
.SYNOPSIS
    Sets up the PostgreSQL database for GenericLogHandler.

.DESCRIPTION
    This script:
    - Detects PostgreSQL installation (or installs if missing)
    - Creates the GenericLogHandler database only if it doesn't exist; safe to run when
      PostgreSQL is already installed and other databases (e.g. DedgeAuth) already exist
    - Optionally configures appsettings.json with connection string

.PARAMETER PostgresHost
    PostgreSQL host. Default: t-no1fkxtst-db

.PARAMETER PostgresPort
    PostgreSQL port. Default: 8432

.PARAMETER PostgresUser
    PostgreSQL username. Default: postgres

.PARAMETER PostgresPassword
    PostgreSQL password. Default: postgres

.PARAMETER DatabaseName
    Database name to create. Default: GenericLogHandler

.PARAMETER ConfigureAppSettings
    If specified, updates appsettings.json with the Postgres connection string.

.EXAMPLE
    .\GenericLogHandler-DatabaseSetup.ps1
    Creates the GenericLogHandler database using defaults.

.EXAMPLE
    .\GenericLogHandler-DatabaseSetup.ps1 -PostgresPort 5433 -ConfigureAppSettings
    Creates database on port 5433 and updates appsettings.json.
#>

[CmdletBinding()]
[System.Diagnostics.CodeAnalysis.SuppressMessage('Security', 'PSAvoidUsingPlainTextForPassword', Justification = 'Passed to PostgreSql-Handler and psql; plain string required.')]
param(
    [string]$PostgresHost = "t-no1fkxtst-db",
    [int]$PostgresPort = 8432,
    [string]$PostgresUser = "postgres",
    [string]$PostgresPassword = "postgres",
    [string]$DatabaseName = "GenericLogHandler",
    [switch]$ConfigureAppSettings
)

$ErrorActionPreference = "Stop"

Import-Module GlobalFunctions -Force -ErrorAction Stop
Import-Module PostgreSql-Handler -Force -ErrorAction Stop

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  GenericLogHandler – Database Setup" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# DETECT / INSTALL POSTGRESQL
# ═══════════════════════════════════════════════════════════════════════════════
Write-LogMessage "Detecting PostgreSQL installation..." -Level INFO

$psqlPath = Get-PostgreSqlPsqlPath -InstallIfMissing
if (-not $psqlPath) {
    Write-LogMessage "PostgreSQL not found and could not be installed." -Level ERROR
    exit 1
}

$psqlExe = Join-Path $psqlPath "psql.exe"
$env:PGPASSWORD = $PostgresPassword

try {

# ═══════════════════════════════════════════════════════════════════════════════
# LOCAL CONFIG (if host is local: port, listen_addresses, pg_hba, firewall, restart)
# ═══════════════════════════════════════════════════════════════════════════════
try {
    Invoke-PostgreSqlEnsureLocalReady -Host $PostgresHost -Port $PostgresPort -User $PostgresUser -Password $PostgresPassword -PsqlExe $psqlExe -PgHbaComment "GenericLogHandler-DatabaseSetup"
}
catch {
    Write-LogMessage "Local PostgreSQL setup failed: $($_.Exception.Message)" -Level ERROR
    exit 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# TEST CONNECTION (final verification on desired port, with retry for service restart)
# ═══════════════════════════════════════════════════════════════════════════════
Write-LogMessage "Testing connection to PostgreSQL ($($PostgresHost):$($PostgresPort))..." -Level INFO

$connected = $false
$maxRetries = 5
for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
    $connected = Test-PostgreSqlConnection -Host $PostgresHost -Port $PostgresPort -User $PostgresUser -Password $PostgresPassword -PsqlExe $psqlExe
    if ($connected) { break }
    if ($attempt -lt $maxRetries) {
        Write-LogMessage "Connection attempt $($attempt)/$($maxRetries) failed, retrying in 3 seconds..." -Level WARN
        Start-Sleep -Seconds 3
    }
}
if (-not $connected) {
    Write-LogMessage "Failed to connect to PostgreSQL after $($maxRetries) attempts." -Level ERROR
    exit 1
}
Write-LogMessage "Connection successful on $($PostgresHost):$($PostgresPort)." -Level INFO

# ═══════════════════════════════════════════════════════════════════════════════
# CREATE DATABASE
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-LogMessage "Checking database '$($DatabaseName)'..." -Level INFO

try {
    New-PostgreSqlDatabaseIfNotExists -Host $PostgresHost -Port $PostgresPort -User $PostgresUser -Password $PostgresPassword -DatabaseName $DatabaseName -PsqlExe $psqlExe
}
catch {
    Write-LogMessage "Database operation failed: $($_.Exception.Message)" -Level ERROR
    exit 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURE APPSETTINGS (optional)
# ═══════════════════════════════════════════════════════════════════════════════
if ($ConfigureAppSettings) {
    Write-Host ""
    Write-LogMessage "Configuring appsettings.json..." -Level INFO

    $appSettingsCandidates = @(
        "C:\opt\src\GenericLogHandler\appsettings.json",
        "C:\opt\src\GenericLogHandler\src\GenericLogHandler.WebApi\appsettings.json"
    )
    $deployedPath = Join-Path (Split-Path $PSScriptRoot -Parent) "appsettings.json"
    $appSettingsCandidates += $deployedPath

    $appSettingsPath = $null
    foreach ($candidate in $appSettingsCandidates) {
        if (Test-Path $candidate) {
            $appSettingsPath = $candidate
            Write-LogMessage "Found appsettings.json at: $($appSettingsPath)" -Level INFO
            break
        }
    }

    if (-not $appSettingsPath) {
        Write-LogMessage "appsettings.json not found in any known location." -Level WARN
        foreach ($c in $appSettingsCandidates) {
            Write-LogMessage "  $($c)" -Level WARN
        }
        $connStr = Get-PostgreSqlConnectionString -Host $PostgresHost -Port $PostgresPort -Database $DatabaseName -User $PostgresUser -Password $PostgresPassword
        Write-LogMessage "Please update appsettings.json manually with connection string: $($connStr)" -Level WARN
    }
    else {
        $appSettings = Get-Content $appSettingsPath -Raw | ConvertFrom-Json
        $connectionString = Get-PostgreSqlConnectionString -Host $PostgresHost -Port $PostgresPort -Database $DatabaseName -User $PostgresUser -Password $PostgresPassword

        if (-not $appSettings.ConnectionStrings) {
            $appSettings | Add-Member -NotePropertyName "ConnectionStrings" -NotePropertyValue ([PSCustomObject]@{}) -Force
        }
        $appSettings.ConnectionStrings.Postgres = $connectionString
        $appSettings.ConnectionStrings.DefaultConnection = $connectionString
        Write-LogMessage "Updated ConnectionStrings.Postgres and DefaultConnection." -Level INFO

        $appSettings | ConvertTo-Json -Depth 10 | Set-Content $appSettingsPath -Encoding UTF8
        Write-LogMessage "appsettings.json updated: $($appSettingsPath)" -Level INFO
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Database Setup Complete" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  PostgreSQL: $($PostgresHost):$($PostgresPort)" -ForegroundColor Gray
Write-Host "  Database:   $DatabaseName" -ForegroundColor Gray
Write-Host ""
Write-Host "  Next step: Run Build-And-Publish.ps1 to build and start GenericLogHandler" -ForegroundColor Yellow
Write-Host "    cd C:\opt\src\GenericLogHandler && .\Build-And-Publish.ps1" -ForegroundColor Gray
Write-Host ""

} # end try
finally {
    $env:PGPASSWORD = $null
}
