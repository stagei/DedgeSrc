# Configuring DedgeAuth as IIS Default Web Site

Manual step-by-step guide to configure DedgeAuth as the Default Web Site in IIS.

## Overview

| Item | Value |
|------|-------|
| **Server** | `dedge-server` |
| **Install path** | `%OptPath%\DedgeWinApps\DedgeAuth` |
| **Application pool** | `DedgeAuth` (No Managed Code, Integrated) |
| **Port** | `80` |
| **Hosting model** | In-process (AspNetCoreModuleV2) |

## Prerequisites

- Administrator access to `dedge-server`
- IIS installed (`Server Manager > Add Roles > Web Server (IIS)`)
- .NET 10.0 ASP.NET Core Hosting Bundle installed
  - Download: https://dotnet.microsoft.com/download/dotnet/10.0
  - Run `iisreset /restart` after installing the bundle
- DedgeAuth application files present at the install path

### Verify .NET 10.0 Runtime

```powershell
dotnet --list-runtimes | Select-String "AspNetCore"
```

Expected output should include `Microsoft.AspNetCore.App 10.x.x`.

---

## Step 1: Create the Application Pool

1. Open **IIS Manager** (`Win+R` > `inetmgr`)
2. Expand the server node in the left panel
3. Right-click **Application Pools** > **Add Application Pool...**
4. Configure:

   | Setting | Value |
   |---------|-------|
   | **Name** | `DedgeAuth` |
   | **.NET CLR Version** | **No Managed Code** |
   | **Managed Pipeline Mode** | **Integrated** |

5. Click **OK**

### Configure Advanced Settings

1. Select the `DedgeAuth` application pool
2. Click **Advanced Settings...** in the right-hand Actions pane
3. Set the following:

   | Setting | Value | Why |
   |---------|-------|-----|
   | **Start Mode** | `AlwaysRunning` | Prevents cold-start delays |
   | **Idle Time-out (minutes)** | `0` | Disables idle shutdown |
   | **Identity** | `ApplicationPoolIdentity` | Default; runs as `IIS AppPool\DedgeAuth` |

4. Click **OK**

---

## Step 2: Set Folder Permissions

The IIS application pool identity (`IIS AppPool\DedgeAuth`) needs read/execute access to the install folder. Without this, the site will fail to start with a 500 or 503 error.

### Using IIS Manager (GUI)

1. Open **File Explorer** on the server
2. Navigate to the install path (e.g. `E:\opt\DedgeWinApps\DedgeAuth`)
3. Right-click the `DedgeAuth` folder > **Properties** > **Security** tab
4. Click **Edit...** > **Add...**
5. In the object name field, type: `IIS AppPool\DedgeAuth`
   - **Important:** This is a virtual account created by IIS, not a normal user. Type it exactly as shown.
6. Click **Check Names** -- it should resolve and become underlined
7. Click **OK**
8. Select the `IIS AppPool\DedgeAuth` entry and grant:

   | Permission | Allow |
   |------------|-------|
   | **Read & execute** | Yes |
   | **List folder contents** | Yes |
   | **Read** | Yes |

9. Click **OK** twice to apply

### Using PowerShell

```powershell
$installPath = Join-Path $env:OptPath "DedgeWinApps\DedgeAuth"
$acl = Get-Acl $installPath
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "IIS AppPool\DedgeAuth",
    "ReadAndExecute",
    "ContainerInherit,ObjectInherit",
    "None",
    "Allow"
)
$acl.AddAccessRule($rule)
Set-Acl -Path $installPath -AclObject $acl
```

### Using icacls

```cmd
icacls "%OptPath%\DedgeWinApps\DedgeAuth" /grant "IIS AppPool\DedgeAuth:(OI)(CI)RX" /T
```

### Logs folder -- write permission

The application writes stdout logs to a `logs` subfolder. Grant the app pool identity write access to that folder:

```powershell
$logsPath = Join-Path $env:OptPath "DedgeWinApps\DedgeAuth\logs"
if (-not (Test-Path $logsPath)) { New-Item -ItemType Directory -Path $logsPath -Force }
$acl = Get-Acl $logsPath
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "IIS AppPool\DedgeAuth",
    "Modify",
    "ContainerInherit,ObjectInherit",
    "None",
    "Allow"
)
$acl.AddAccessRule($rule)
Set-Acl -Path $logsPath -AclObject $acl
```

Or with icacls:

```cmd
mkdir "%OptPath%\DedgeWinApps\DedgeAuth\logs" 2>nul
icacls "%OptPath%\DedgeWinApps\DedgeAuth\logs" /grant "IIS AppPool\DedgeAuth:(OI)(CI)M" /T
```

---

## Step 3: Configure the Default Web Site

1. In IIS Manager, expand **Sites**
2. Select **Default Web Site**
3. Click **Basic Settings...** in the Actions pane
4. Configure:

   | Setting | Value |
   |---------|-------|
   | **Physical path** | `E:\opt\DedgeWinApps\DedgeAuth` (or `%OptPath%\DedgeWinApps\DedgeAuth`) |
   | **Application pool** | Click **Select...** > choose `DedgeAuth` |

5. Click **OK**

---

## Step 4: Configure Bindings

1. Select **Default Web Site**
2. Click **Bindings...** in the Actions pane
3. Remove any existing HTTP bindings you don't need (e.g. port 80)
4. Click **Add...**
5. Configure:

   | Setting | Value |
   |---------|-------|
   | **Type** | `http` |
   | **IP address** | `All Unassigned` |
   | **Port** | `80` |
   | **Host name** | *(leave empty)* |

6. Click **OK** > **Close**

---

## Step 5: Verify web.config

The `web.config` file should already exist in the install folder (created during publish). If missing, create it:

**Path:** `%OptPath%\DedgeWinApps\DedgeAuth\web.config`

```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <location path="." inheritInChildApplications="false">
    <system.webServer>
      <handlers>
        <add name="aspNetCore" path="*" verb="*" modules="AspNetCoreModuleV2" resourceType="Unspecified" />
      </handlers>
      <aspNetCore processPath="dotnet"
                  arguments=".\DedgeAuth.Api.dll"
                  stdoutLogEnabled="true"
                  stdoutLogFile=".\logs\stdout"
                  hostingModel="inprocess" />
    </system.webServer>
  </location>
</configuration>
```

> **Tip:** Set `stdoutLogEnabled="true"` during initial setup to capture startup errors. Change to `"false"` once everything works to avoid disk usage.

---

## Step 6: Configure Firewall

Port 80 (HTTP) is typically already open. Verify:

```powershell
# Check if port 80 is allowed through the firewall
Get-NetFirewallRule -DisplayName "*HTTP*" | Where-Object { $_.Enabled -eq 'True' }

# If not, add it:
New-NetFirewallRule -DisplayName "DedgeAuth HTTP" -Direction Inbound -LocalPort 80 -Protocol TCP -Action Allow
```

---

## Step 7: Start and Verify

### Start the Site

1. In IIS Manager, right-click **Default Web Site** > **Manage Website** > **Start**
2. Verify the `DedgeAuth` application pool shows **Started**

Or via command line:

```powershell
Start-WebAppPool -Name "DedgeAuth"
Start-Website -Name "Default Web Site"
```

Or using appcmd:

```cmd
%SystemRoot%\System32\inetsrv\appcmd.exe start apppool "DedgeAuth"
%SystemRoot%\System32\inetsrv\appcmd.exe start site "Default Web Site"
```

### Verify

```powershell
# Check application pool is running
Get-WebAppPoolState -Name "DedgeAuth"

# Check site is running
Get-Website -Name "Default Web Site" | Select-Object Name, State

# Test health endpoint
Invoke-WebRequest -Uri "http://localhost/health" -UseBasicParsing

# Test login page
Start-Process "http://localhost/login.html"
```

---

## Troubleshooting

### 503 Service Unavailable

The application pool has stopped. Check:

```powershell
# Check event log for crash details
Get-EventLog -LogName Application -Source "IIS*" -Newest 10 | Format-List

# Check stdout logs
Get-ChildItem "$($env:OptPath)\DedgeWinApps\DedgeAuth\logs\stdout*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Get-Content -Tail 50
```

Common causes:
- Missing .NET 10.0 Hosting Bundle -- install and run `iisreset /restart`
- Incorrect folder permissions -- see Step 2
- Missing `web.config`

### 502.5 Process Failure

The ASP.NET Core process crashed during startup:

1. Enable stdout logging in `web.config` (`stdoutLogEnabled="true"`)
2. Restart the site and check `logs\stdout_*.log`
3. Common cause: database connection failure -- verify `appsettings.json`

### 500.19 Configuration Error

Invalid `web.config` or missing AspNetCoreModuleV2:

```powershell
# Check if the module is registered
Get-WebGlobalModule | Where-Object Name -eq "AspNetCoreModuleV2"
```

If missing, reinstall the Hosting Bundle and run `iisreset /restart`.

### Permission Denied / 401

The app pool identity cannot read the application files:

```powershell
# Verify current permissions
icacls "$($env:OptPath)\DedgeWinApps\DedgeAuth"

# Should show IIS AppPool\DedgeAuth with (RX) access
```

See Step 2 to fix permissions.

### Port Conflict

```powershell
# Check what is using port 80
netstat -ano | findstr :80
```

---

## Quick Reference

```powershell
# Restart the application (after a new publish)
Restart-WebAppPool -Name "DedgeAuth"

# View live stdout logs
Get-Content "$($env:OptPath)\DedgeWinApps\DedgeAuth\logs\stdout*" -Tail 30 -Wait

# Recycle app pool (graceful restart)
Restart-WebAppPool -Name "DedgeAuth"

# Full IIS restart
iisreset /restart
```
