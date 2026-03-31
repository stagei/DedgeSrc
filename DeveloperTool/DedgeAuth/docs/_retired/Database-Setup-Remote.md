# Setting Up Database from App Server

This guide explains how to run the database setup script from `dedge-server` to configure the database on `t-no1fkxtst-db`.

## Prerequisites

1. **PostgreSQL Client Tools** must be installed on `dedge-server`
   - The script will detect PostgreSQL installation automatically
   - If not found, install via: `winget install -e --id PostgreSQL.PostgreSQL`

2. **Network Access** from `dedge-server` to `t-no1fkxtst-db`
   - Port 8432 must be open
   - PostgreSQL must allow remote connections (check `pg_hba.conf` on database server)

3. **Database Credentials**
   - Default: `postgres` / `postgres`
   - Update if your database uses different credentials

## Running from App Server

### Option 1: Run from Deployed Location

If the scripts are already deployed to the server:

```powershell
# Navigate to deployed location
cd C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\DedgeAuth\scripts

# Run setup (uses default: t-no1fkxtst-db)
.\Setup-Database.ps1 -ConfigureAppSettings

# Or with custom credentials
.\Setup-Database.ps1 `
    -PostgresHost "t-no1fkxtst-db" `
    -PostgresUser "youruser" `
    -PostgresPassword "yourpassword" `
    -ConfigureAppSettings
```

### Option 2: Run from Network Share

If accessing via network share:

```powershell
# Run directly from network share
& "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\DedgeAuth\scripts\Setup-Database.ps1" `
    -PostgresHost "t-no1fkxtst-db" `
    -ConfigureAppSettings
```

### Option 3: Copy Script to App Server Temporarily

```powershell
# Copy script to app server
Copy-Item "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\DedgeAuth\scripts\Setup-Database.ps1" `
    -Destination "C:\temp\Setup-Database.ps1"

# Run from app server
cd C:\temp
.\Setup-Database.ps1 -PostgresHost "t-no1fkxtst-db" -ConfigureAppSettings
```

## What the Script Does

1. **Detects PostgreSQL Client** (`psql.exe`) on the app server
2. **Tests Connection** to `t-no1fkxtst-db:8432`
3. **Creates Database** `DedgeAuth` if it doesn't exist
4. **Updates appsettings.json** (if `-ConfigureAppSettings` is used)
   - Updates connection string to point to `t-no1fkxtst-db`
   - Generates JWT secret if empty

## Important Notes

### appsettings.json Location

When using `-ConfigureAppSettings`, the script looks for `appsettings.json` at:
- `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\DedgeAuth\src\DedgeAuth.Api\appsettings.json`

However, in the deployed location, the file is at:
- `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\DedgeAuth\appsettings.json`

**Solution**: Either:
1. Manually update `appsettings.json` after running the script, OR
2. Run the script without `-ConfigureAppSettings` and manually update the connection string

### Manual appsettings.json Update

After running the database setup, update the deployed `appsettings.json`:

```json
{
  "ConnectionStrings": {
    "AuthDb": "Host=t-no1fkxtst-db;Database=DedgeAuth;Username=postgres;Password=postgres"
  }
}
```

## Troubleshooting

### PostgreSQL Client Not Found

```
PostgreSQL not found. Please install PostgreSQL first.
```

**Solution**: Install PostgreSQL client tools on `dedge-server`:
```powershell
winget install -e --id PostgreSQL.PostgreSQL
```

### Connection Failed

```
Failed to connect to PostgreSQL: ...
```

**Check**:
1. Can you ping `t-no1fkxtst-db`?
   ```powershell
   Test-NetConnection -ComputerName t-no1fkxtst-db -Port 8432
   ```

2. Is PostgreSQL running on `t-no1fkxtst-db`?
   ```powershell
   # On database server
   Get-Service -Name postgresql*
   ```

3. Is remote access enabled in `pg_hba.conf`?
   - File location: `C:\Program Files\PostgreSQL\<version>\data\pg_hba.conf`
   - Add line: `host    all    all    10.0.0.0/8    md5`
   - Restart PostgreSQL service

4. Is `postgresql.conf` configured to listen on network?
   - Set: `listen_addresses = '*'`
   - Restart PostgreSQL service

### Database Already Exists

```
Database 'DedgeAuth' already exists.
```

This is fine - the script will skip creation if the database already exists.

## Verification

After setup, verify the connection:

```powershell
# Test connection from app server
$env:PGPASSWORD = "postgres"
psql -h t-no1fkxtst-db -U postgres -d DedgeAuth -c "SELECT version();"
```

Or test from the application:
```powershell
# Check health endpoint (should connect to database)
Invoke-WebRequest -Uri "http://t-no1fkxtst.app:8100/health" -UseBasicParsing
```
