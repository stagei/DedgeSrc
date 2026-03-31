<#
.SYNOPSIS
    Sets up the PostgreSQL database for DedgeAuth.

.DESCRIPTION
    This script:
    - Detects PostgreSQL installation
    - Creates the DedgeAuth database if it doesn't exist
    - Optionally configures appsettings.json with connection string and JWT secret

.PARAMETER PostgresHost
    PostgreSQL host. Default: t-no1fkxtst-db

.PARAMETER PostgresPort
    PostgreSQL port. Default: 8432

.PARAMETER PostgresUser
    PostgreSQL username. Default: postgres

.PARAMETER PostgresPassword
    PostgreSQL password. Default: postgres

.PARAMETER DatabaseName
    Database name to create. Default: DedgeAuth

.PARAMETER ConfigureAppSettings
    If specified, updates src/DedgeAuth.Api/appsettings.json with connection string and generates JWT secret if empty.

.EXAMPLE
    .\DatabaseSetup.ps1
    Creates the DedgeAuth database using defaults.

.EXAMPLE
    .\DatabaseSetup.ps1 -PostgresPort 5433 -ConfigureAppSettings
    Creates database on port 5433 and updates appsettings.json.
#>

[CmdletBinding()]
[System.Diagnostics.CodeAnalysis.SuppressMessage('Security', 'PSAvoidUsingPlainTextForPassword', Justification = 'Passed to PostgreSql-Handler and psql; plain string required.')]
param(
    [string]$PostgresHost = "t-no1fkxtst-db",
    [int]$PostgresPort = 8432,
    [string]$PostgresUser = "postgres",
    [string]$PostgresPassword = "postgres",
    [string]$DatabaseName = "DedgeAuth",
    [switch]$ConfigureAppSettings
)

$ErrorActionPreference = "Stop"

Import-Module GlobalFunctions -Force -ErrorAction Stop
Import-Module PostgreSql-Handler -Force -ErrorAction Stop

$projectRoot = Split-Path $PSScriptRoot -Parent

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  DedgeAuth – Database Setup" -ForegroundColor Cyan
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
    Invoke-PostgreSqlEnsureLocalReady -Host $PostgresHost -Port $PostgresPort -User $PostgresUser -Password $PostgresPassword -PsqlExe $psqlExe -PgHbaComment "DedgeAuth-DatabaseSetup"
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
# CONFIGURE APPSETTINGS (optional) — DedgeAuth-specific: AuthDb + JWT secret
# ═══════════════════════════════════════════════════════════════════════════════
if ($ConfigureAppSettings) {
    Write-Host ""
    Write-LogMessage "Configuring appsettings.json..." -Level INFO

    $appSettingsPath = Join-Path $projectRoot "src\DedgeAuth.Api\appsettings.json"
    if (-not (Test-Path $appSettingsPath)) {
        $deployedPath = Join-Path (Split-Path $PSScriptRoot -Parent) "appsettings.json"
        if (Test-Path $deployedPath) {
            $appSettingsPath = $deployedPath
            Write-LogMessage "Using deployed appsettings.json at: $($appSettingsPath)" -Level INFO
        }
    }

    if (-not (Test-Path $appSettingsPath)) {
        Write-LogMessage "appsettings.json not found at: $($appSettingsPath)" -Level WARN
        $connStr = Get-PostgreSqlConnectionString -Host $PostgresHost -Port $PostgresPort -Database $DatabaseName -User $PostgresUser -Password $PostgresPassword
        Write-LogMessage "Please update appsettings.json manually with connection string: $($connStr)" -Level WARN
    }
    else {
        $appSettings = Get-Content $appSettingsPath -Raw | ConvertFrom-Json
        $connectionString = Get-PostgreSqlConnectionString -Host $PostgresHost -Port $PostgresPort -Database $DatabaseName -User $PostgresUser -Password $PostgresPassword
        $appSettings.ConnectionStrings.AuthDb = $connectionString
        Write-LogMessage "Updated connection string." -Level INFO

        if ([string]::IsNullOrEmpty($appSettings.AuthConfiguration.JwtSecret)) {
            $jwtSecret = [Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(64))
            $appSettings.AuthConfiguration.JwtSecret = $jwtSecret
            Write-LogMessage "Generated new JWT secret." -Level INFO
        }
        else {
            Write-LogMessage "JWT secret already configured." -Level INFO
        }

        $appSettings | ConvertTo-Json -Depth 10 | Set-Content $appSettingsPath -Encoding UTF8
        Write-LogMessage "appsettings.json updated." -Level INFO
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
Write-Host "  Next step: Run Build-And-Publish.ps1 to build and start DedgeAuth" -ForegroundColor Yellow
Write-Host "    .\Build-And-Publish.ps1" -ForegroundColor Gray
Write-Host ""

} # end try
finally {
    $env:PGPASSWORD = $null
}
