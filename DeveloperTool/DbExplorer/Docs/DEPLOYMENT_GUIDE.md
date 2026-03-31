# DbExplorer Deployment Guide

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Building the Application](#building-the-application)
3. [Self-Contained Deployment](#self-contained-deployment)
4. [Configuration](#configuration)
5. [Installation](#installation)
6. [Troubleshooting](#troubleshooting)
7. [Offline Deployment](#offline-deployment)

---

## Prerequisites

### Development Machine

- **Windows 11** (recommended) or Windows 10
- **.NET 10 SDK**: Install from [https://dotnet.microsoft.com/download](https://dotnet.microsoft.com/download)
- **Visual Studio 2022** (17.8+) or VS Code (optional, for development)
- **Git** (for source control)

### Target Machine (End User)

- **Windows 11** or Windows 10 (version 1809 or later)
- **.NET 10 Runtime** (included in self-contained deployment)
- **Network access** to DB2 database server (no DB2 client installation needed)

---

## Building the Application

### Debug Build

For development and testing:

```bash
dotnet build
```

### Release Build

For production deployment:

```bash
dotnet build -c Release
```

### Verify Build

Check for successful build:

```bash
cd bin/Release/net10.0-windows
dir DbExplorer.exe
```

---

## Self-Contained Deployment

Create a self-contained deployment package that includes the .NET runtime:

### Standard Deployment

```bash
dotnet publish -c Release -r win-x64 --self-contained true -f net10.0-windows
```

### Single File Deployment (Recommended)

```bash
dotnet publish -c Release -r win-x64 --self-contained true -f net10.0-windows ^
  /p:PublishSingleFile=true ^
  /p:IncludeNativeLibrariesForSelfExtract=true ^
  /p:PublishReadyToRun=true
```

**Output Location**: `bin/Release/net10.0-windows/win-x64/publish/`

### Deployment Package Contents

After publishing, the `publish` folder should contain:

```
publish/
├── DbExplorer.exe       # Main executable
├── appsettings.json           # Configuration
├── nlog.config                # Logging configuration
├── Resources/
│   └── DB2SQL.xshd           # SQL syntax highlighting
├── *.dll                      # Dependencies (if not single-file)
└── logs/                      # Created on first run
```

---

## Configuration

### appsettings.json

Configure before deployment:

```json
{
  "Application": {
    "Framework": "net10.0-windows"
  },
  "Editor": {
    "DefaultTheme": "Dark",
    "FontFamily": "Consolas",
    "FontSize": 14,
    "TabSize": 4,
    "WordWrap": false
  },
  "Database": {
    "DefaultCommandTimeout": 30,
    "PoolSize": 20,
    "AutoCommit": true
  },
  "Logging": {
    "UseNLog": true,
    "ConfigFile": "nlog.config",
    "MinLevel": "Info",
    "LogDirectory": "logs",
    "RetentionDays": 30
  }
}
```

### nlog.config

Default configuration (already included):

```xml
<?xml version="1.0" encoding="utf-8" ?>
<nlog xmlns="http://www.nlog-project.org/schemas/NLog.xsd"
      xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <targets>
    <target xsi:type="File" name="file" 
            fileName="logs/db2editor-${shortdate}.log"
            layout="${longdate}|${level:uppercase=true}|${logger}|${message}${exception:format=ToString}"
            archiveFileName="logs/archives/db2editor-{#}.log"
            archiveEvery="Day"
            archiveNumbering="Rolling"
            maxArchiveFiles="30" />
  </targets>
  <rules>
    <logger name="*" minlevel="Info" writeTo="file" />
  </rules>
</nlog>
```

---

## Installation

### Method 1: Simple Copy (Recommended for Small Teams)

1. Copy the entire `publish` folder to target machine
2. Rename folder to `DbExplorer`
3. Place in desired location (e.g., `C:\Program Files\DbExplorer\`)
4. Create desktop shortcut to `DbExplorer.exe`
5. Run the application

### Method 2: Create MSI Installer (For Large Deployments)

Use WiX Toolset or Advanced Installer to create an MSI package:

1. Include all files from `publish` folder
2. Set installation directory: `C:\Program Files\DbExplorer\`
3. Create Start Menu entry
4. Create Desktop shortcut (optional)
5. Register file associations (optional, for `.sql` files)

### Method 3: XCOPY Deployment

```bash
# On deployment machine
xcopy /E /I /Y "\\build-server\DbExplorer\publish" "C:\opt\DbExplorer"
```

---

## Configuration

### First Run Setup

When the application runs for the first time:

1. **Logs Directory**: Created automatically in application folder
2. **User Settings**: Stored in `%APPDATA%\DbExplorer\`
3. **Query History**: Stored in `%APPDATA%\DbExplorer\query-history.json`

### Connecting to DB2

1. Launch DbExplorer
2. Click "New Connection" or press `Ctrl+N`
3. Enter connection details:
   - **Host**: DB2 server hostname or IP
   - **Port**: Default is 50000
   - **Database**: Database name
   - **Username**: DB2 username
   - **Password**: DB2 password
4. Click "Test Connection" to verify
5. Click "Connect"

### Connection String Format

The application uses this format internally:

```
Server=hostname:port;Database=DBNAME;UID=username;PWD=password;
```

---

## Troubleshooting

### Application Won't Start

**Symptom**: Double-clicking exe does nothing or shows error

**Solutions**:
1. Check Windows Event Viewer for .NET errors
2. Ensure all files from `publish` folder are present
3. Verify `appsettings.json` and `nlog.config` exist
4. Check antivirus hasn't quarantined files
5. Run as Administrator (if permissions issue)

### Connection Failed

**Symptom**: "Failed to connect to database"

**Solutions**:
1. Verify DB2 server is accessible:
   ```bash
   ping db2-server-hostname
   telnet db2-server-hostname 50000
   ```
2. Check credentials are correct
3. Verify DB2 server allows remote connections
4. Check firewall rules on both machines
5. Review logs in `logs/db2editor-[date].log`

### Slow Performance

**Symptom**: Queries take long time to execute

**Solutions**:
1. Increase `DefaultCommandTimeout` in `appsettings.json`
2. Check network latency to DB2 server
3. Review query execution plans
4. Check DB2 server performance
5. Enable DEBUG logging to identify bottlenecks

### Missing Syntax Highlighting

**Symptom**: SQL appears in plain text, no colors

**Solutions**:
1. Verify `Resources/DB2SQL.xshd` file exists
2. Check file is in same directory as exe or in `Resources` subfolder
3. Review logs for file loading errors
4. Restart application

### Logs Not Created

**Symptom**: No log files in `logs` directory

**Solutions**:
1. Check write permissions on application directory
2. Verify `nlog.config` exists and is valid XML
3. Check internal NLog log: `logs/nlog-internal.log`
4. Run application as Administrator temporarily to test

### Theme Not Changing

**Symptom**: Pressing Ctrl+D doesn't change theme

**Solutions**:
1. Wait a moment (theme change can take 1-2 seconds)
2. Check `appsettings.json` for valid `DefaultTheme` value
3. Restart application
4. Check logs for theme service errors

---

## Offline Deployment

For air-gapped or offline environments:

### Preparation

1. Build self-contained deployment on development machine
2. Copy entire `publish` folder to USB drive or network share
3. Include this deployment guide

### Installation Steps

1. Copy `publish` folder to target machine
2. No internet connection required
3. No .NET installation required (already included)
4. No DB2 client installation required (using Net.IBM.Data.Db2)

### Network Requirements

- **Database Connection**: Target machine must be able to reach DB2 server
- **Port**: Default DB2 port 50000 (or custom port)
- **Protocol**: TCP/IP

### Testing Connectivity

From command prompt on target machine:

```bash
# Test connectivity
telnet db2-server-hostname 50000

# If telnet not available
Test-NetConnection -ComputerName db2-server-hostname -Port 50000
```

---

## File Locations

### Application Files

- **Installation**: `C:\Program Files\DbExplorer\` (or custom location)
- **Executable**: `DbExplorer.exe`
- **Configuration**: `appsettings.json`, `nlog.config`

### User Data

- **Settings**: `%APPDATA%\DbExplorer\appsettings.json`
- **Query History**: `%APPDATA%\DbExplorer\query-history.json`

### Logs

- **Current Logs**: `logs\db2editor-YYYY-MM-DD.log`
- **Archived Logs**: `logs\archives\db2editor-*.log` (30-day retention)
- **Internal Logs**: `logs\nlog-internal.log`

---

## Security Considerations

### Password Storage

- Passwords are **NOT** stored in configuration
- Passwords are **NOT** logged (masked in logs)
- Each connection requires password entry
- Consider using Windows Credential Manager for password management

### Network Security

- All connections use native DB2 protocol
- No intermediate proxy or service
- Direct TCP/IP connection to DB2 server
- Ensure DB2 server has proper firewall rules

### Logging Security

- Logs contain SQL queries (may include sensitive data)
- Logs automatically mask passwords with pattern `PWD=***`
- Review log retention policy (default 30 days)
- Secure log directory with appropriate permissions

---

## Support

### Getting Help

1. **Check Logs**: Review `logs\db2editor-[date].log`
2. **Enable DEBUG Logging**: Change `MinLevel` to `Debug` in `appsettings.json`
3. **Event Viewer**: Check Windows Event Viewer for .NET errors
4. **Internal Logs**: Check `logs\nlog-internal.log` for NLog errors

### Common Log Locations

```powershell
# View today's log
Get-Content "logs\db2editor-$(Get-Date -Format yyyy-MM-dd).log" -Tail 50

# View all errors
Select-String -Path "logs\*.log" -Pattern "ERROR"
```

---

## Version Information

- **Application Version**: 1.0.0
- **.NET Version**: 10.0 (net10.0-windows)
- **DB2 Package**: Net.IBM.Data.Db2 9.0.0.400
- **Target Platform**: win-x64 (Windows 11/10 64-bit)

---

## Changelog

### Version 1.0.0 (Initial Release)

- Full DB2 connectivity without external client
- Multiple connection tabs
- SQL syntax highlighting and formatting
- Query history with search
- Export to CSV, TSV, JSON, SQL
- Dark/Light/System theme support
- Comprehensive logging with NLog
- Settings dialog for configuration
- Keyboard shortcuts for productivity
- Database browser with schema/table enumeration

---

**Last Updated**: 2025-11-12

