# DedgeAuth Server Setup Steps for dedge-server

This document provides step-by-step instructions to configure DedgeAuth on the `dedge-server` server after publishing.

## Prerequisites

- Application files published to `C:\opt\DedgeWinApps\DedgeAuth` (or network share)
- Administrator access to `dedge-server`
- IIS installed and configured
- ASP.NET Core Hosting Bundle installed (for .NET 10.0)
- PostgreSQL database accessible from the server

## Step 1: Verify Published Files

1. **Check deployment location:**
   ```powershell
   Test-Path "C:\opt\DedgeWinApps\DedgeAuth\DedgeAuth.Api.dll"
   ```

2. **Verify required files exist:**
   - `DedgeAuth.Api.dll` (main application)
   - `appsettings.json` (configuration)
   - `web.config` (IIS configuration)
   - `wwwroot/` folder (static files)
   - `scripts/` folder (database setup scripts)
   - `docs/` folder (documentation)

## Step 2: Configure Database Connection

1. **Edit appsettings.json:**
   ```powershell
   notepad "C:\opt\DedgeWinApps\DedgeAuth\appsettings.json"
   ```

2. **Verify connection string:**
   ```json
   "ConnectionStrings": {
     "AuthDb": "Host=t-no1fkxtst-db;Database=DedgeAuth;Username=postgres;Password=YOUR_PASSWORD"
   }
   ```

3. **Update AuthConfiguration if needed:**
   - `JwtSecret`: Should be a secure random string (not placeholder)
   - `JwtIssuer`: e.g., `"https://t-no1fkxtst.app.DEDGE.fk.no"`
   - `JwtAudience`: e.g., `"https://portal.Dedge.no"`
   - `BaseUrl`: e.g., `"https://t-no1fkxtst.app.DEDGE.fk.no:8100"`

## Step 3: Run Database Setup Script

1. **Navigate to scripts folder:**
   ```powershell
   cd "C:\opt\DedgeWinApps\DedgeAuth\scripts"
   ```

2. **Run database setup:**
   ```powershell
   .\Setup-Database.ps1 -PostgresHost "t-no1fkxtst-db" -PostgresPassword "YOUR_PASSWORD"
   ```

   This will:
   - Create the database if it doesn't exist
   - Run migrations
   - Seed initial data (admin user, tenants, apps)

3. **Verify database connection:**
   ```powershell
   .\Setup-Database.ps1 -PostgresHost "t-no1fkxtst-db" -TestConnectionOnly
   ```

## Step 4: Configure IIS

### Option A: Use PowerShell Script (Recommended)

1. **Run the configuration script:**
   ```powershell
   cd "C:\opt\DedgeWinApps\DedgeAuth\scripts"
   .\Configure-IIS-DefaultWebsite.ps1 `
       -PhysicalPath "C:\opt\DedgeWinApps\DedgeAuth" `
       -Port 8100
   ```

### Option B: Manual IIS Configuration

1. **Open IIS Manager:**
   - Press `Win + R`, type `inetmgr`, press Enter

2. **Create Application Pool:**
   - Expand server node → Right-click **Application Pools** → **Add Application Pool**
   - Name: `DedgeAuth`
   - .NET CLR Version: **No Managed Code**
   - Managed Pipeline Mode: **Integrated**
   - Click **OK**

3. **Configure Application Pool:**
   - Select **DedgeAuth** pool → **Advanced Settings**
   - Set **Start Mode**: `AlwaysRunning`
   - Set **Idle Timeout**: `00:00:00` (disabled)
   - Click **OK**

4. **Configure Default Web Site:**
   - Expand **Sites** → Select **Default Web Site**
   - Click **Basic Settings**
   - Physical path: `C:\opt\DedgeWinApps\DedgeAuth`
   - Application pool: `DedgeAuth`
   - Click **OK**

5. **Configure Bindings:**
   - Select **Default Web Site** → Click **Bindings**
   - Remove any existing bindings on port 8100 (if present)
   - Click **Add**
   - Type: `http`
   - IP address: `All Unassigned`
   - Port: `8100`
   - Host name: (leave empty)
   - Click **OK**

6. **Verify web.config:**
   - Check that `C:\opt\DedgeWinApps\DedgeAuth\web.config` exists
   - If not, the script should have created it automatically
   - Content should reference `DedgeAuth.Api.dll`

7. **Start Services:**
   - Right-click **DedgeAuth** application pool → **Start**
   - Right-click **Default Web Site** → **Start**

## Step 5: Configure Firewall

1. **Allow port 8100:**
   ```powershell
   New-NetFirewallRule -DisplayName "DedgeAuth HTTP" -Direction Inbound -LocalPort 8100 -Protocol TCP -Action Allow
   ```

2. **Verify firewall rule:**
   ```powershell
   Get-NetFirewallRule -DisplayName "DedgeAuth HTTP"
   ```

## Step 6: Verify Application

1. **Test health endpoint:**
   ```powershell
   Invoke-WebRequest -Uri "http://localhost:8100/health" -UseBasicParsing
   ```
   Expected response: `{"Status":"Healthy","Timestamp":"..."}`

2. **Test login page:**
   - Open browser: `http://t-no1fkxtst.app:8100/login.html`
   - Verify page loads correctly

3. **Check application pool status:**
   ```powershell
   Get-WebAppPoolState -Name "DedgeAuth"
   ```
   Should show: `Started`

4. **Check website status:**
   ```powershell
   Get-Website -Name "Default Web Site" | Select-Object Name, State
   ```
   Should show: `Started`

## Step 7: Check Logs (if issues occur)

1. **IIS stdout logs:**
   ```powershell
   Get-Content "C:\opt\DedgeWinApps\DedgeAuth\logs\stdout*.log" -Tail 50
   ```

2. **Windows Event Viewer:**
   - Open Event Viewer
   - Navigate to: **Windows Logs** → **Application**
   - Look for errors related to DedgeAuth or ASP.NET Core

3. **Application logs:**
   - Check `appsettings.json` for logging configuration
   - Logs may be written to configured locations

## Troubleshooting

### Application Pool Won't Start

- **Check Event Viewer** for detailed error messages
- **Verify ASP.NET Core Hosting Bundle** is installed:
  ```powershell
  Get-ItemProperty "HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedhost" -ErrorAction SilentlyContinue
  ```
- **Verify .NET 10.0 runtime** is installed:
  ```powershell
  dotnet --list-runtimes
  ```
- **Check permissions:** Application pool identity needs read/execute permissions on `C:\opt\DedgeWinApps\DedgeAuth`

### 502.5 Process Failure

- **Verify web.config** exists and is correct
- **Check DedgeAuth.Api.dll** exists in deployment folder
- **Verify .NET 10.0 runtime** is installed
- **Check stdout logs** in `.\logs\stdout` folder
- **Verify database connection** string is correct

### Database Connection Errors

- **Test database connectivity:**
  ```powershell
  Test-NetConnection -ComputerName "t-no1fkxtst-db" -Port 8432
  ```
- **Verify connection string** in `appsettings.json`
- **Check PostgreSQL** is running and accessible
- **Verify firewall rules** allow database connections

### Port Already in Use

- **Check what's using port 8100:**
  ```powershell
   netstat -ano | findstr :8100
   ```
- **Stop conflicting service** or change port in `Program.cs` and redeploy

### CORS Issues

- **Verify CORS configuration** in `appsettings.json`:
  ```json
  "Cors": {
    "AllowedOrigins": ["https://portal.Dedge.no"]
  }
  ```
- **For development**, CORS allows localhost automatically

## Post-Deployment Checklist

- [ ] Application files deployed successfully
- [ ] Database connection configured and tested
- [ ] Database migrations run successfully
- [ ] IIS application pool created and started
- [ ] IIS website configured and started
- [ ] Firewall rule added for port 8100
- [ ] Health endpoint responds correctly
- [ ] Login page loads correctly
- [ ] Application pool shows "Started" status
- [ ] No errors in Event Viewer
- [ ] Database seeding completed (if applicable)

## Next Steps

After successful deployment:

1. **Configure SSL/TLS** if required (HTTPS)
2. **Set up monitoring** and alerting
3. **Configure backup** for database
4. **Set up log rotation** for application logs
5. **Configure as Windows Service** (optional) for automatic startup
6. **Update DNS** if needed for external access
7. **Run security tests** using provided test scripts

## Quick Reference Commands

```powershell
# Check application pool status
Get-WebAppPoolState -Name "DedgeAuth"

# Restart application pool
Restart-WebAppPool -Name "DedgeAuth"

# Check website status
Get-Website -Name "Default Web Site"

# Restart website
Restart-Website -Name "Default Web Site"

# View recent stdout logs
Get-Content "C:\opt\DedgeWinApps\DedgeAuth\logs\stdout*.log" -Tail 50

# Test health endpoint
Invoke-WebRequest -Uri "http://localhost:8100/health" -UseBasicParsing

# Test database connection
cd "C:\opt\DedgeWinApps\DedgeAuth\scripts"
.\Setup-Database.ps1 -PostgresHost "t-no1fkxtst-db" -TestConnectionOnly
```
