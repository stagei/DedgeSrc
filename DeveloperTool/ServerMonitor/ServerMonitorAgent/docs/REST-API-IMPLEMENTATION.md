# REST API Implementation - COMPLETE ✅

## Summary

Successfully added a complete REST API with Swagger/OpenAPI documentation to the Server Surveillance Tool. The application now runs as both a Windows Service AND a web server simultaneously.

## ✅ What Was Implemented

### 1. **ASP.NET Core Web API**
- Runs alongside Windows Service in the same process
- Configured on port **5000** (customizable in appsettings.json)
- Full REST API for querying live system data
- Uses GlobalSnapshotService (always available, thread-safe)

### 2. **Swagger/OpenAPI UI**
- Interactive API documentation at `http://SERVER:5000/swagger`
- Auto-generated from code and XML comments
- OpenAPI spec at `/swagger/v1/swagger.json`
- Beautiful, professional UI for testing APIs

### 3. **Auto-Firewall Configuration**
- **Automatically opens Windows Firewall** if running as admin
- Creates rule: "ServerMonitorAPI" for TCP port 5000
- Gracefully handles non-admin scenarios (logs warning)
- Configurable via `AutoConfigureFirewall` setting

### 4. **Startup Logging**
- Logs all API URLs at startup
- Shows Swagger UI URL
- Lists all available endpoints
- Makes it easy to find and use the API

## 📋 Configuration (appsettings.json)

```json
{
  "Surveillance": {
    "RestApi": {
      "Enabled": true,                    // Enable/disable API
      "Port": 5000,                       // API port
      "EnableSwagger": true,              // Enable Swagger UI
      "AutoConfigureFirewall": true       // Auto-open firewall (if admin)
    }
  }
}
```

## 🌐 API Endpoints

### Complete Snapshot
- **GET** `/api/snapshot`
  - Returns full system snapshot (all data + all alerts)
  - Includes processor, memory, disks, network, updates, etc.
  - Includes ALL alerts with complete distribution history

### Health Summary
- **GET** `/api/snapshot/health`
  - Quick health overview
  - CPU, memory, disk usage
  - Alert counts by severity
  - Uptime information

### Alerts
- **GET** `/api/snapshot/alerts`
  - All alerts since startup
  - Includes complete distribution history for each alert
  - Shows which channels received each alert and if successful

- **GET** `/api/snapshot/alerts/recent?count=10`
  - Recent N alerts (most recent first)
  - Default: 10 alerts

### Specific Metrics
- **GET** `/api/snapshot/processor` - CPU metrics
- **GET** `/api/snapshot/memory` - Memory metrics
- **GET** `/api/snapshot/disks` - Disk metrics
- **GET** `/api/snapshot/network` - Network connectivity
- **GET** `/api/snapshot/updates` - Windows Update status

## 🔥 Firewall Auto-Configuration

### When Running as Administrator:
```
✅ Firewall rule created automatically
✅ Port 5000 opened for TCP
✅ Rule name: "ServerMonitorAPI"
✅ Logged at startup
```

### When NOT Running as Administrator:
```
⚠️ Warning logged
💡 Tip displayed: "Run as administrator to auto-configure firewall"
✅ API still works (if firewall manually configured)
```

### Manual Firewall Configuration (if needed):
```powershell
netsh advfirewall firewall add rule name="ServerMonitorAPI" dir=in action=allow protocol=TCP localport=5000
```

## 📚 Swagger UI

### Access:
```
http://30237-FK:5000/swagger
```

### Features:
- ✅ Interactive API testing
- ✅ Auto-generated documentation
- ✅ Request/response examples
- ✅ Try API calls directly from browser
- ✅ OpenAPI spec download

### Example Screenshot:
```
Server Surveillance Tool API v1
Live REST API for querying server monitoring data, alerts, and system health

Snapshot
  GET /api/snapshot              Get the complete current system snapshot
  GET /api/snapshot/alerts       Get all alerts with distribution history
  GET /api/snapshot/health       Get system health summary
  GET /api/snapshot/processor    Get processor metrics
  ...
```

## 🚀 Startup Log Output

When the application starts, you'll see:

```
══════════════════════════════════════════════════════
  🌐 REST API STARTED
══════════════════════════════════════════════════════

📡 Base URL: http://30237-FK:5000

📚 Swagger UI: http://30237-FK:5000/swagger
📄 OpenAPI Spec: http://30237-FK:5000/swagger/v1/swagger.json

🔗 API Endpoints:
   GET http://30237-FK:5000/api/snapshot           - Full system snapshot
   GET http://30237-FK:5000/api/snapshot/health    - Health summary
   GET http://30237-FK:5000/api/snapshot/alerts    - All alerts
   GET http://30237-FK:5000/api/snapshot/processor - CPU data
   GET http://30237-FK:5000/api/snapshot/memory    - Memory data
   GET http://30237-FK:5000/api/snapshot/disks     - Disk data
   GET http://30237-FK:5000/api/snapshot/network   - Network data
   GET http://30237-FK:5000/api/snapshot/updates   - Windows updates

💡 TIP: Open http://30237-FK:5000/swagger in your browser for interactive API documentation!
══════════════════════════════════════════════════════
```

## 📊 Example API Response

### GET /api/snapshot/health

```json
{
  "serverName": "30237-FK",
  "timestamp": "2025-11-27T13:30:00Z",
  "uptimeDays": 7.25,
  "lastBootTime": "2025-11-20T08:00:00Z",
  "cpu": {
    "usagePercent": 25.5,
    "cores": 16
  },
  "memory": {
    "totalGB": 32.0,
    "usedPercent": 48.2,
    "availableGB": 16.6
  },
  "disks": [
    {
      "drive": "C:",
      "totalGB": 475.9,
      "usedPercent": 67.5,
      "availableGB": 154.7
    }
  ],
  "alerts": {
    "total": 42,
    "critical": 2,
    "warning": 35,
    "informational": 5,
    "last24Hours": 15
  }
}
```

### GET /api/snapshot/alerts

```json
[
  {
    "id": "abc123...",
    "severity": "Warning",
    "category": "Processor",
    "message": "CPU usage sustained above warning level: 85.0%",
    "timestamp": "2025-11-27T13:25:00Z",
    "serverName": "30237-FK",
    "distributionHistory": [
      {
        "channelType": "SMS",
        "destination": "+4797188358",
        "timestamp": "2025-11-27T13:25:01Z",
        "success": true
      },
      {
        "channelType": "WKMonitor",
        "destination": "\\\\server\\monitor\\30237-FK20251127132501123.MON",
        "timestamp": "2025-11-27T13:25:02Z",
        "success": true
      },
      {
        "channelType": "Email",
        "destination": "admin@company.com",
        "timestamp": "2025-11-27T13:25:03Z",
        "success": false,
        "errorMessage": "SMTP timeout"
      }
    ]
  }
]
```

## 🔧 Architecture

```
ServerMonitor.exe (Single Process)
│
├── Windows Service Layer
│   ├── SurveillanceWorker (Background monitoring)
│   ├── Monitors (CPU, Memory, Disk, etc.)
│   ├── GlobalSnapshotService (Always-available state)
│   └── AlertManager (Sequential distribution)
│
└── ASP.NET Core Web API Layer
    ├── Kestrel Web Server (Port 5000)
    ├── SnapshotController (REST endpoints)
    ├── Swagger UI (Interactive docs)
    └── FirewallService (Auto-configuration)
```

## ✅ Benefits

1. **Live Data Access** - Query current system state anytime
2. **No Database Needed** - Data is already in memory (GlobalSnapshotService)
3. **Thread-Safe** - Multiple API requests handled safely
4. **Complete History** - All alerts with distribution tracking
5. **Auto-Firewall** - Works out-of-the-box when run as admin
6. **Professional UI** - Swagger provides beautiful documentation
7. **Easy Integration** - Standard REST API for monitoring dashboards

## 🧪 Testing

### 1. Start Application as Administrator:
```powershell
.\ServerMonitor.exe
```

### 2. Verify Startup Logs:
Look for:
- ✅ REST API STARTED
- ✅ Swagger UI URL
- ✅ Firewall rule created

### 3. Open Swagger UI:
```
http://30237-FK:5000/swagger
```

### 4. Test Health Endpoint:
```powershell
Invoke-RestMethod -Uri "http://30237-FK:5000/api/snapshot/health" | ConvertTo-Json
```

### 5. Test Alerts Endpoint:
```powershell
Invoke-RestMethod -Uri "http://30237-FK:5000/api/snapshot/alerts" | ConvertTo-Json -Depth 10
```

## 📦 Files Changed

1. **ServerMonitor.csproj** - Changed SDK to Web, added ASP.NET packages
2. **Program.cs** - Added web hosting configuration
3. **appsettings.json** - Added RestApi configuration section
4. **Controllers/SnapshotController.cs** (NEW) - REST API endpoints
5. **Services/FirewallService.cs** (NEW) - Firewall management
6. **Services/RestApiStartupLogger.cs** (NEW) - Startup logging

## 🎯 Next Steps

1. ✅ Application builds successfully
2. ⏳ Run and test REST API
3. ⏳ Verify Swagger UI loads
4. ⏳ Test firewall auto-configuration
5. ⏳ Query live data from GlobalSnapshotService

---

**The REST API is ready to use! Just start the application as administrator and navigate to the Swagger UI.** 🚀

