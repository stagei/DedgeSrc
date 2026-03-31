# Service Installation & Configuration Guide

## Quick Answer to Your Questions

### ✅ YES - Config Reload Works Automatically!

**.NET's `IOptionsMonitor<T>` provides automatic config hot-reload:**
1. **At startup** - Always loads latest config
2. **On file change** - Detects within seconds when you edit appsettings.json
3. **No interval needed** - File watching is automatic and instant
4. **All services already use it** - Every monitor, channel, orchestrator uses `IOptionsMonitor<T>`

**Example:**
```
12:00 - Service running with CPU threshold = 80%
12:05 - You edit appsettings.json, change CPU threshold to 90%
12:05 - (within 2-5 seconds) IOptionsMonitor detects change
12:05 - Log: "Configuration changed - settings reloaded"
12:06 - Next monitor cycle uses NEW threshold (90%)
```

### ✅ Daily Memory Clear Strategy

**With daily restarts:**
- GlobalSnapshot alerts cleared daily
- Memory usage resets
- Fresh config loaded
- Historical alerts preserved in JSON export files
- **No memory limit concerns**

---

## 🚀 Service Installation

### Prerequisites
- ✅ Application built in Release mode
- ✅ PowerShell with Administrator privileges
- ✅ appsettings.json configured

### Install Service

```powershell
# Run as Administrator
.\Install-ServerSurveillanceService.ps1
```

**What This Does:**
1. ✅ Stops and removes any existing service
2. ✅ Creates new Windows Service
3. ✅ Configures auto-restart on failure (1-minute delay)
4. ✅ Sets delayed auto-start (starts after boot)
5. ✅ Starts the service
6. ✅ Displays configuration summary

### Custom Installation Path

```powershell
.\Install-ServerSurveillanceService.ps1 -ExePath "C:\YourPath\ServerMonitor.exe"
```

---

## ⚙️ Configuration for Daily Restart

### appsettings.json

```json
{
  "Surveillance": {
    "Logging": {
      "LogDirectory": "C:\\opt\\data\\AllPwshLog",  // Path to log files
      "AppName": "ServerSurveillance"               // Log file prefix
    },
    "Runtime": {
      "AutoShutdownTime": "02:00",           // Restart daily at 2 AM
      "ConfigReloadIntervalMinutes": 5       // Monitor config changes every 5 min
    },
    "RestApi": {
      "Enabled": true,
      "Port": 5000,
      "EnableSwagger": true,
      "AutoConfigureFirewall": true
    }
  }
}
```

### How Daily Restart Works

```
Timeline:
├─ 02:00 - AutoShutdownTime triggers
├─ 02:00 - Application exits gracefully
├─ 02:01 - Windows Service auto-restart (1-min recovery)
├─ 02:01 - New process starts
├─ 02:01 - GlobalSnapshot initialized (memory cleared)
├─ 02:01 - Fresh config loaded from appsettings.json
├─ 02:01 - Monitoring resumes
└─ 02:02 - REST API available again
```

**Benefits:**
- ✅ Memory cleared daily (no accumulation)
- ✅ Config refreshed from file
- ✅ Any memory leaks cleared
- ✅ Logs rotated (NLog handles this)
- ✅ Minimal downtime (~1-2 minutes)

---

## 🔄 Config Hot-Reload (No Restart Needed)

### How It Works

**.NET Configuration System:**
```json
// In CreateDefaultBuilder() - automatically enabled:
"reloadOnChange": true  // Watches appsettings.json for changes
```

**All services use `IOptionsMonitor<T>`:**
```csharp
// Example from MemoryMonitor.cs
public MemoryMonitor(IOptionsMonitor<SurveillanceConfiguration> config)
{
    _config = config;
    // config.CurrentValue always reads latest
}

public async Task CollectAsync()
{
    // This ALWAYS gets current config (hot-reloaded)
    var settings = _config.CurrentValue.MemoryMonitoring;
}
```

### What Can Be Changed Without Restart?

✅ **Monitoring Thresholds** (CPU, Memory, Disk, etc.)
✅ **Alert Channel Settings** (SMS, Email, WKMonitor)
✅ **Polling Intervals**
✅ **Alert Throttling Settings**
✅ **Export Settings**
✅ **Log Directory** (new log files go to new path immediately)
✅ **REST API Port** (requires restart to rebind port)

### Example Workflow

```powershell
# 1. Service is running
Get-Service ServerMonitor
# Status: Running

# 2. Edit config (change CPU warning from 80% to 90%)
notepad C:\...\appsettings.json

# 3. Save file

# 4. Within 2-5 seconds, check logs:
# "Configuration changed - settings reloaded automatically"

# 5. New threshold active immediately (no restart!)
```

### ConfigReloadService

The new `ConfigReloadService`:
- Monitors for config changes
- Logs when changes detected
- Provides visibility into hot-reload
- Configurable check interval (`ConfigReloadIntervalMinutes`)

**Log output example:**
```
2025-11-27 13:05:00 | INFO | ConfigReloadService | 🔄 Configuration changed - settings reloaded automatically
2025-11-27 13:05:00 | DEBUG | ConfigReloadService | New config: MonitoringEnabled=True, ExportEnabled=True
```

---

## 📊 Service Management

### Common Commands

```powershell
# Check service status
Get-Service ServerMonitor

# Start service
Start-Service ServerMonitor

# Stop service (will auto-restart if configured)
Stop-Service ServerMonitor

# Restart service (manual)
Restart-Service ServerMonitor

# View service details
Get-Service ServerMonitor | Format-List *

# Remove service
sc.exe delete ServerMonitor
```

### Check Service Configuration

```powershell
# View auto-restart settings
sc.exe qfailure ServerMonitor

# Output:
# RESET_PERIOD: 86400 seconds (24 hours)
# FAILURE_ACTIONS:
#   Restart after 60000 milliseconds (1 minute)
```

### View Service Logs

```powershell
# Read LogDirectory from config
$config = Get-Content "appsettings.json" | ConvertFrom-Json
$logDir = $config.Surveillance.Logging.LogDirectory
$appName = $config.Surveillance.Logging.AppName

# Today's log
Get-Content "$logDir\${appName}_$(Get-Date -Format 'yyyy-MM-dd').log" -Tail 50

# Follow log live
Get-Content "$logDir\${appName}_$(Get-Date -Format 'yyyy-MM-dd').log" -Tail 20 -Wait

# Or use default path
Get-Content "C:\opt\data\ServerMonitor\ServerMonitor_$(Get-Date -Format 'yyyy-MM-dd').log" -Tail 50
```

---

## 🔥 Firewall Configuration

### Automatic (If Running as Admin)

```
Service starts → Checks if admin → Creates firewall rule for port 5000
```

**Firewall rule created:**
- Name: `ServerMonitorAPI`
- Direction: Inbound
- Protocol: TCP
- Port: 5000
- Action: Allow
- Profiles: All (Domain, Private, Public)

### Manual (If Not Admin)

```powershell
# Run as Administrator
netsh advfirewall firewall add rule name="ServerMonitorAPI" dir=in action=allow protocol=TCP localport=5000 profile=any
```

### Verify Firewall Rule

```powershell
netsh advfirewall firewall show rule name="ServerMonitorAPI"
```

---

## 🌐 REST API Access

### URLs (After Service Starts)

- **Swagger UI**: `http://SERVERNAME:5000/swagger`
- **Health Check**: `http://SERVERNAME:5000/api/snapshot/health`
- **All Alerts**: `http://SERVERNAME:5000/api/snapshot/alerts`
- **Full Snapshot**: `http://SERVERNAME:5000/api/snapshot`

### Test from PowerShell

```powershell
# Health check
Invoke-RestMethod -Uri "http://localhost:5000/api/snapshot/health" | ConvertTo-Json

# Recent alerts
Invoke-RestMethod -Uri "http://localhost:5000/api/snapshot/alerts/recent?count=5" | ConvertTo-Json -Depth 10

# Full snapshot
Invoke-RestMethod -Uri "http://localhost:5000/api/snapshot" | ConvertTo-Json -Depth 10
```

### Test from Web Browser

```
Open: http://30237-FK:5000/swagger

Then click "Try it out" on any endpoint to test interactively!
```

---

## 📋 Configuration Reference

### Complete appsettings.json Example

```json
{
  "Surveillance": {
    "Logging": {
      "LogDirectory": "C:\\opt\\data\\AllPwshLog",  // Custom log directory
      "AppName": "ServerSurveillance"               // Log file name prefix
    },
    "Runtime": {
      "AutoShutdownTime": "02:00",             // Daily restart at 2 AM
      "ConfigReloadIntervalMinutes": 5,        // Config change monitoring
      "TestTimeoutSeconds": null               // No timeout in production
    },
    "RestApi": {
      "Enabled": true,                         // Enable REST API
      "Port": 5000,                            // API port
      "EnableSwagger": true,                   // Enable Swagger UI
      "AutoConfigureFirewall": true            // Auto-create firewall rule
    },
    "Alerting": {
      "Throttling": {
        "WarningSuppressionMinutes": 60,       // Warnings: once per hour
        "ErrorSuppressionMinutes": 15,         // Errors: once per 15 min
        "InformationalSuppressionMinutes": 120 // Info: once per 2 hours
      }
    }
  }
}
```

---

## 🎯 Production Deployment Checklist

### 1. Build Application
```powershell
dotnet build C:\opt\src\ServerMonitor\ServerMonitorAgent\ServerMonitor.sln --configuration Release
```

### 2. Configure appsettings.json
- ✅ Set `AutoShutdownTime` for daily restart
- ✅ Configure alert channels (SMS, Email, WKMonitor)
- ✅ Set monitoring thresholds
- ✅ Enable REST API if needed

### 3. Install Service (as Admin)
```powershell
.\Install-ServerSurveillanceService.ps1
```

### 4. Verify Service Running
```powershell
Get-Service ServerMonitor
# Status should be: Running
```

### 5. Check Logs
```powershell
# Check default log location (or your configured LogDirectory)
Get-Content "C:\opt\data\ServerMonitor\ServerMonitor_$(Get-Date -Format 'yyyy-MM-dd').log" -Tail 30
```

Look for:
- ✅ "Starting Server Surveillance Tool"
- ✅ "Log Directory: C:\opt\data\AllPwshLog" (or your custom path)
- ✅ "REST API STARTED"
- ✅ "Swagger UI: http://..."
- ✅ "Started monitoring cycle for..."

### 6. Test REST API
```
Open browser: http://SERVERNAME:5000/swagger
```

### 7. Test Config Hot-Reload
```powershell
# Edit config
notepad C:\...\appsettings.json

# Save changes

# Check logs for:
# "Configuration changed - settings reloaded"
```

---

## 🔧 Troubleshooting

### Service Won't Start

```powershell
# Check service status
Get-Service ServerMonitor | Format-List *

# Check Windows Event Log
Get-EventLog -LogName Application -Source ServerMonitor -Newest 10

# Check application logs
Get-Content "C:\opt\data\ServerMonitor\ServerMonitor_*.log" -Tail 100
```

### Firewall Not Working

```powershell
# Check if rule exists
netsh advfirewall firewall show rule name="ServerMonitorAPI"

# Manually add if needed (as admin)
netsh advfirewall firewall add rule name="ServerMonitorAPI" dir=in action=allow protocol=TCP localport=5000
```

### Config Changes Not Picked Up

```powershell
# Verify appsettings.json syntax (must be valid JSON)
Get-Content appsettings.json | ConvertFrom-Json

# Check logs for config reload messages
Get-Content "C:\opt\data\ServerMonitor\ServerMonitor_*.log" | Select-String "Configuration changed"

# Force restart to reload
Restart-Service ServerMonitor
```

### REST API Not Accessible

```powershell
# Check if port is listening
netstat -ano | Select-String ":5000"

# Test locally first
Invoke-RestMethod -Uri "http://localhost:5000/api/snapshot/health"

# Check firewall
Test-NetConnection -ComputerName localhost -Port 5000
```

---

## 💡 Best Practices

### 1. **Configure Log Directory**
```json
"Logging": {
  "LogDirectory": "C:\\opt\\data\\AllPwshLog",  // Or network share
  "AppName": "ServerSurveillance"
}
```

### 2. **Daily Restart for Memory Management**
```json
"AutoShutdownTime": "02:00"  // Low-traffic time
```

### 3. **Enable Config Hot-Reload**
```json
"ConfigReloadIntervalMinutes": 5  // Monitors for changes
```

### 4. **Use REST API for Monitoring**
- Integrate with monitoring dashboards
- Query `/api/snapshot/health` for current status
- Alert history available via `/api/snapshot/alerts`

### 5. **Log Retention**
- Application logs: `{LogDirectory}\{AppName}_{date}.log` (30 days auto-archive)
- JSON exports go to: `C:\opt\data\ServerSurveillance\Snapshots\`
- Pipe these into your log system/database
- Historical analysis from exports, not from GlobalSnapshot

### 6. **Service Recovery**
- Auto-restart configured for 3 failures
- Each failure restarts after 1 minute
- Service will auto-restart after `AutoShutdownTime` shutdown

---

## 📚 Summary

| Feature | Implementation | Benefit |
|---------|----------------|---------|
| **Service Install** | Install-ServerSurveillanceService.ps1 | One-command setup |
| **Auto-Restart** | Service recovery configured | High availability |
| **Daily Restart** | AutoShutdownTime config | Memory cleared daily |
| **Config Reload** | IOptionsMonitor (automatic) | No restart for config changes |
| **REST API** | ASP.NET Core + Swagger | Query live data anytime |
| **Firewall** | Auto-configured if admin | Works out-of-the-box |
| **Memory Strategy** | Daily restart + JSON exports | No accumulation issues |

---

**The service is production-ready with automatic config reload, daily memory clearing, and REST API access!** 🎉

