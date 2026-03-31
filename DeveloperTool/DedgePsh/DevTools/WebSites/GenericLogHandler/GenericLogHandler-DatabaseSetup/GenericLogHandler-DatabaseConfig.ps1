<#
.SYNOPSIS
    Connection and database configuration for GenericLogHandler PostgreSQL operations.

.DESCRIPTION
    Returns a hashtable of connection parameters used by GenericLogHandler-Backup-Database.ps1 and
    GenericLogHandler-Restore-Database.ps1. Copy this file to other PostgreSQL-backed projects and
    change defaults (DatabaseName, host, port, credentials) for reuse.

.OUTPUTS
    Hashtable with: PostgresHost, PostgresPort, PostgresUser, PostgresPassword, DatabaseName
#>
[System.Diagnostics.CodeAnalysis.SuppressMessage('Security', 'PSAvoidUsingPlainTextForPassword', Justification = 'Config for psql/pg_dump; plain string required.')]
[CmdletBinding()]
param(
    [string]$PostgresHost = "t-no1fkxtst-db",
    [int]$PostgresPort = 8432,
    [string]$PostgresUser = "postgres",
    [string]$PostgresPassword = "postgres",
    [string]$DatabaseName = "GenericLogHandler"
)

return @{
    PostgresHost     = $PostgresHost
    PostgresPort     = $PostgresPort
    PostgresUser     = $PostgresUser
    PostgresPassword = $PostgresPassword
    DatabaseName     = $DatabaseName
}
