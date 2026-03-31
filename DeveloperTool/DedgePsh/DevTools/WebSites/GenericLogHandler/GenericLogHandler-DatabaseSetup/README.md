# GenericLogHandler-DatabaseSetup

Sets up the PostgreSQL database for the GenericLogHandler application. Creates the database if it doesn't exist and optionally configures `appsettings.json`.

## What It Does

1. **Detects** PostgreSQL installation on the server
2. **Creates** the `GenericLogHandler` database if it doesn't exist
3. **Optionally** updates `appsettings.json` with the connection string

## Scripts

| Script | Description |
|--------|-------------|
| `GenericLogHandler-DatabaseSetup.ps1` | Main setup — installs PostgreSQL if needed, configures port/firewall, creates DB |
| `GenericLogHandler-DatabaseConfig.ps1` | Connection config (host, port, user, database) for backup/restore |
| `GenericLogHandler-Backup-Database.ps1` | Backs up the database using pg_dump (see Backup and Restore below) |
| `GenericLogHandler-Restore-Database.ps1` | Restores from a backup file (see Backup and Restore below) |
| `Test-PostgresSetup.ps1` | General — diagnostic: installation, service, config, ports, firewall, connectivity |
| `Repair-PostgresInstall.ps1` | General — repair: reinitializes data directory and service after a failed install |

## Parameters (Main Setup)

| Parameter | Default | Description |
|-----------|---------|-------------|
| `PostgresHost` | `t-no1fkxtst-db` | PostgreSQL server hostname |
| `PostgresPort` | `8432` | PostgreSQL port |
| `PostgresUser` | `postgres` | PostgreSQL username |
| `PostgresPassword` | `postgres` | PostgreSQL password |
| `DatabaseName` | `GenericLogHandler` | Database name to create |
| `ConfigureAppSettings` | Off | If set, updates `appsettings.json` with connection string |

## Usage

Run on the database server:

```powershell
.\GenericLogHandler-DatabaseSetup.ps1
```

Create the database and configure appsettings:

```powershell
.\GenericLogHandler-DatabaseSetup.ps1 -PostgresPassword "YourPassword" -ConfigureAppSettings
```

Use a different host or port:

```powershell
.\GenericLogHandler-DatabaseSetup.ps1 -PostgresHost "my-db-server" -PostgresPort 5433
```

Run diagnostics:

```powershell
.\Test-PostgresSetup.ps1
```

## Backup and Restore

Backup and restore use **GenericLogHandler-DatabaseConfig.ps1** for connection settings and the shared **PostgreSql-Handler** module. Default backup output: `.\Backups\<DatabaseName>_<yyyyMMdd-HHmmss>.backup`.

```powershell
.\GenericLogHandler-Backup-Database.ps1
.\GenericLogHandler-Backup-Database.ps1 -OutputPath C:\temp\GenericLogHandler.backup -Format Plain
.\GenericLogHandler-Restore-Database.ps1 -Latest -CreateDatabaseIfNotExists
.\GenericLogHandler-Restore-Database.ps1 -InputPath .\Backups\GenericLogHandler_20250101-120000.backup -Clean
```

| Parameter (Restore) | Description |
|--------------------|-------------|
| `-InputPath` | Path to backup file (.backup or .sql) |
| `-Latest` | Use latest backup in .\Backups\ |
| `-CreateDatabaseIfNotExists` | Create the database before restore if missing |
| `-Clean` | (Custom format) Drop existing objects before restore |

## Deployment

This script is distributed to the database server automatically via `_deploy.ps1`.

## Source Project

Maintained from `C:\opt\src\GenericLogHandler`. See the GenericLogHandler project for the full application source.
