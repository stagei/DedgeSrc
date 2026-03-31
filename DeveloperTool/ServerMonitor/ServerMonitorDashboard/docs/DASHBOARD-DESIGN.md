# ServerMonitor Dashboard - Design Document

## Overview

A centralized web dashboard for monitoring all ServerMonitor agents across the infrastructure. Provides real-time visibility into server health, resource usage, and DB2 diagnostics with the ability to manage agent installations remotely.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           FRONTEND (HTML + JS)                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │ Server List │  │   Metrics   │  │   Charts    │  │   DB2 Diagnostics   │ │
│  │  Dropdown   │  │   Cards     │  │   Gauges    │  │   Panel (if data)   │ │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘ │
│         │                │                │                     │           │
│         └────────────────┴────────────────┴─────────────────────┘           │
│                                    │                                        │
│                            Fetch API (JSON)                                 │
└────────────────────────────────────┼────────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                      BACKEND API (C# .NET 10)                               │
│                                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────────┐  │
│  │ /api/servers    │  │ /api/snapshot   │  │ /api/reinstall              │  │
│  │ List + Status   │  │ Live or Cached  │  │ Create trigger file         │  │
│  └────────┬────────┘  └────────┬────────┘  └──────────────┬──────────────┘  │
│           │                    │                          │                 │
│           ▼                    ▼                          ▼                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                     Background Services                                 ││
│  │  • ServerStatusPoller - Polls /api/IsAlive for each server              ││
│  │  • VersionDetector - Reads ServerMonitor.exe version from UNC           ││
│  │  • ComputerInfoLoader - Loads server list from ComputerInfo.json        ││
│  └─────────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          EXTERNAL RESOURCES                                 │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\ComputerInfo.json                ││
│  │ → Server list (filter: type contains "Server")                          ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ ServerMonitor Agents (per server)                                       ││
│  │ → http://{server}:8999/api/IsAlive     (health check)                   ││
│  │ → http://{server}:8999/api/snapshot    (live data)                      ││
│  │ → http://{server}:8999/api/CachedSnapshot (cached data)                 ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ Trigger Files (for reinstall)                                           ││
│  │ → C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor\             ││
│  │   ReinstallServerMonitor.txt (contains Version=x.y.z)                   ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ Version Detection                                                       ││
│  │ → C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitor\          ││
│  │   ServerMonitor.exe → FileVersionInfo.GetVersionInfo()                  ││
│  └─────────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Project Structure

```
ServerMonitorDashboard/
├── docs/
│   └── DASHBOARD-DESIGN.md          # This document
├── src/
│   └── ServerMonitorDashboard/
│       ├── ServerMonitorDashboard.csproj
│       ├── Program.cs
│       ├── appsettings.json
│       │
│       ├── Controllers/
│       │   ├── ServersController.cs      # /api/servers endpoints
│       │   ├── SnapshotController.cs     # /api/snapshot/{server}
│       │   └── ReinstallController.cs    # /api/reinstall/{server}
│       │
│       ├── Services/
│       │   ├── ServerStatusService.cs    # Background status polling
│       │   ├── ComputerInfoService.cs    # Load/cache ComputerInfo.json
│       │   ├── VersionService.cs         # Detect ServerMonitor version
│       │   └── SnapshotProxyService.cs   # Fetch live/cached snapshots
│       │
│       ├── Models/
│       │   ├── ServerInfo.cs             # Server details + status
│       │   ├── ComputerInfo.cs           # ComputerInfo.json model
│       │   └── DashboardConfig.cs        # Configuration model
│       │
│       └── wwwroot/
│           ├── index.html                # Main dashboard page
│           ├── css/
│           │   └── dashboard.css         # Custom styles
│           └── js/
│               ├── dashboard.js          # Main application logic
│               ├── charts.js             # Chart/gauge rendering
│               └── db2-panel.js          # DB2 diagnostics panel
│
└── ServerMonitorDashboard.sln
```

---

## Backend API Endpoints

### 1. Server List & Status

```http
GET /api/servers
```

**Response:**
```json
{
  "servers": [
    {
      "name": "P-NO1FKMPRD-DB",
      "displayName": "Production DB Server",
      "type": "Server",
      "ipAddress": "10.33.100.50",
      "isAlive": true,
      "lastChecked": "2026-01-13T12:00:00Z",
      "agentVersion": "1.0.3",
      "responseTimeMs": 45
    },
    {
      "name": "P-NO1FKMPRD-APP",
      "displayName": "Production App Server",
      "type": "Server",
      "isAlive": false,
      "lastChecked": "2026-01-13T12:00:00Z",
      "agentVersion": null,
      "responseTimeMs": null,
      "error": "Connection timeout"
    }
  ],
  "lastRefreshed": "2026-01-13T12:00:00Z",
  "currentAgentVersion": "1.0.3"
}
```

### 2. Get Snapshot (Live or Cached)

```http
GET /api/snapshot/{serverName}?useCached=false
```

**Parameters:**
- `serverName`: Target server name
- `useCached`: `true` = use `/api/CachedSnapshot`, `false` = use `/api/snapshot`

**Response:** Full SystemSnapshot JSON from the target server

### 3. Create Reinstall Trigger

```http
POST /api/reinstall/{serverName}
```

**Request Body:**
```json
{
  "version": "1.0.3"  // Optional - auto-detects if not provided
}
```

**Response:**
```json
{
  "success": true,
  "triggerFilePath": "\\dedge-server\\DedgeCommon\\Software\\Config\\ServerMonitor\\ReinstallServerMonitor.txt",
  "version": "1.0.3",
  "message": "Reinstall trigger created for version 1.0.3"
}
```

### 4. Get Current Agent Version

```http
GET /api/version
```

**Response:**
```json
{
  "version": "1.0.3",
  "exePath": "\\dedge-server\\DedgeCommon\\Software\\DedgeWinApps\\ServerMonitor\\ServerMonitor.exe"
}
```

---

## Background Services

### ServerStatusService

Periodically polls all servers to check if their agents are alive.

```csharp
public class ServerStatusService : BackgroundService
{
    private readonly Dictionary<string, ServerStatus> _serverStatus = new();
    private readonly TimeSpan _pollInterval = TimeSpan.FromSeconds(30);
    
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            var servers = await _computerInfoService.GetServersAsync();
            
            await Parallel.ForEachAsync(servers, async (server, ct) =>
            {
                var isAlive = await CheckIsAliveAsync(server.Name);
                UpdateServerStatus(server.Name, isAlive);
            });
            
            await Task.Delay(_pollInterval, stoppingToken);
        }
    }
    
    private async Task<bool> CheckIsAliveAsync(string serverName)
    {
        try
        {
            using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
            var response = await client.GetAsync($"http://{serverName}:8999/api/IsAlive");
            return response.IsSuccessStatusCode;
        }
        catch
        {
            return false;
        }
    }
}
```

### ComputerInfoService

Loads and caches the server list from ComputerInfo.json.

```csharp
public class ComputerInfoService
{
    private readonly string _computerInfoPath = 
        @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\ComputerInfo.json";
    
    public async Task<List<ComputerInfo>> GetServersAsync()
    {
        var json = await File.ReadAllTextAsync(_computerInfoPath);
        var allComputers = JsonSerializer.Deserialize<List<ComputerInfo>>(json);
        
        // Filter to only servers
        return allComputers
            .Where(c => c.Type?.Contains("Server", StringComparison.OrdinalIgnoreCase) == true)
            .ToList();
    }
}
```

### VersionService

Detects the current ServerMonitor agent version from the deployment path.

```csharp
public class VersionService
{
    private readonly string _serverMonitorExePath = 
        @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitor\ServerMonitor.exe";
    
    public string GetCurrentVersion()
    {
        if (File.Exists(_serverMonitorExePath))
        {
            var versionInfo = FileVersionInfo.GetVersionInfo(_serverMonitorExePath);
            return versionInfo.FileVersion ?? "Unknown";
        }
        return "Unknown";
    }
}
```

---

## Frontend Design

### Main Layout

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  ╔══════════════════════════════════════════════════════════════════════╗   │
│  ║  🖥️ ServerMonitor Dashboard                             [Live ◉]    ║   │
│  ╚══════════════════════════════════════════════════════════════════════╝   │
│                                                                              │
│  ┌────────────────────────────────────────────────┐  ┌────────────────────┐  │
│  │ Server: [▼ P-NO1FKMPRD-DB         🟢]          │  │ ☑ Use Cached Data  │  │
│  │                                                 │  │ ⟳ Refresh (30s)   │  │
│  │  🟢 12 Online  🔴 2 Offline                     │  │ [🔄 Reinstall]     │  │
│  └────────────────────────────────────────────────┘  └────────────────────┘  │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                        SYSTEM OVERVIEW                                  │ │
│  │  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐  ┌──────────┐  │ │
│  │  │ 🔲 CPU        │  │ 🔲 Memory     │  │ 🔲 Disk C:    │  │ ⏱ Uptime │  │ │
│  │  │   ████░░ 67%  │  │   █████░ 85%  │  │   ███░░░ 45%  │  │  45 days │  │ │
│  │  │               │  │  12/16 GB     │  │  220/500 GB   │  │          │  │ │
│  │  └───────────────┘  └───────────────┘  └───────────────┘  └──────────┘  │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                         ALERTS (3)                                      │ │
│  │  ┌───────────────────────────────────────────────────────────────────┐  │ │
│  │  │ 🔴 Critical │ Processor │ CPU at 95% for 5 minutes    │ 10:45:30 │  │ │
│  │  │ 🟡 Warning  │ Memory    │ Memory usage above 85%      │ 10:42:15 │  │ │
│  │  │ 🔵 Info     │ Uptime    │ Server uptime > 90 days     │ 09:00:00 │  │ │
│  │  └───────────────────────────────────────────────────────────────────┘  │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │              🗄️ DB2 DIAGNOSTICS  (Only shown if data present)          │ │
│  │  ┌──────────────────────────────────────────────────────────────────┐   │ │
│  │  │  Instance: DB2HFED    Entries: 47    Last: 2026-01-13 10:30:00  │   │ │
│  │  │                                                                  │   │ │
│  │  │  Severity Distribution:                                          │   │ │
│  │  │  ■■■■■■■■░░░░░░░░░░░░  Critical: 8                               │   │ │
│  │  │  ■■■■■■■■■■■■░░░░░░░░  Error: 15                                 │   │ │
│  │  │  ■■■■■■■■■■■■■■■■■■■■  Warning: 24                               │   │ │
│  │  │                                                                  │   │ │
│  │  │  [📋 View Full Log]  [📊 Message Distribution]                   │   │ │
│  │  └──────────────────────────────────────────────────────────────────┘   │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                     TOP PROCESSES (CPU)                                 │ │
│  │  ┌───────────────────────────────────────────────────────────────────┐  │ │
│  │  │ db2sysc.exe      │ █████████████████░░░  45.2% │ [View Details]  │  │ │
│  │  │ sqlservr.exe     │ █████████░░░░░░░░░░░  23.1% │ [View Details]  │  │ │
│  │  │ w3wp.exe         │ ████░░░░░░░░░░░░░░░░   8.5% │ [View Details]  │  │ │
│  │  │ ServerMonitor    │ █░░░░░░░░░░░░░░░░░░░   2.1% │ [View Details]  │  │ │
│  │  └───────────────────────────────────────────────────────────────────┘  │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Server Dropdown with Status Icons

```html
<select id="serverSelect" class="server-dropdown">
  <option value="P-NO1FKMPRD-DB" data-status="online">
    🟢 P-NO1FKMPRD-DB (Production DB)
  </option>
  <option value="P-NO1FKMPRD-APP" data-status="online">
    🟢 P-NO1FKMPRD-APP (Production App)
  </option>
  <option value="T-NO1FKXTST-DB" data-status="offline">
    🔴 T-NO1FKXTST-DB (Test DB) - OFFLINE
  </option>
</select>
```

### Visual Components

#### Gauge/Meter (CSS + JS)

```html
<div class="metric-gauge">
  <svg viewBox="0 0 100 50">
    <path class="gauge-bg" d="M 10 50 A 40 40 0 0 1 90 50" />
    <path class="gauge-fill" d="M 10 50 A 40 40 0 0 1 90 50" 
          style="stroke-dashoffset: calc(126 - 126 * 0.67)" />
  </svg>
  <div class="gauge-value">67%</div>
  <div class="gauge-label">CPU</div>
</div>
```

#### Progress Bar

```html
<div class="metric-bar">
  <div class="bar-label">Memory: 12.5 / 16 GB</div>
  <div class="bar-track">
    <div class="bar-fill warning" style="width: 78%"></div>
  </div>
</div>
```

#### Severity Badge

```html
<span class="severity-badge critical">Critical</span>
<span class="severity-badge warning">Warning</span>
<span class="severity-badge info">Informational</span>
```

### JavaScript API Integration

```javascript
// dashboard.js

class DashboardApp {
  constructor() {
    this.servers = [];
    this.selectedServer = null;
    this.useCached = false;
    this.refreshInterval = 30000;
  }

  async init() {
    await this.loadServers();
    this.setupEventListeners();
    this.startAutoRefresh();
  }

  async loadServers() {
    const response = await fetch('/api/servers');
    const data = await response.json();
    this.servers = data.servers;
    this.renderServerDropdown();
  }

  async loadSnapshot(serverName) {
    const useCached = document.getElementById('useCached').checked;
    const response = await fetch(
      `/api/snapshot/${serverName}?useCached=${useCached}`
    );
    const snapshot = await response.json();
    this.renderDashboard(snapshot);
  }

  renderDashboard(snapshot) {
    this.renderSystemMetrics(snapshot);
    this.renderAlerts(snapshot.alerts);
    this.renderTopProcesses(snapshot.processor?.topProcesses);
    
    // Only render DB2 panel if data exists
    if (snapshot.db2Diagnostics?.instances?.length > 0) {
      this.showDb2Panel(snapshot.db2Diagnostics);
    } else {
      this.hideDb2Panel();
    }
  }

  async triggerReinstall(serverName) {
    if (!confirm(`Trigger reinstall for ${serverName}?`)) return;
    
    const response = await fetch(`/api/reinstall/${serverName}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    });
    
    const result = await response.json();
    if (result.success) {
      this.showNotification(`Reinstall triggered: v${result.version}`);
    }
  }
}

// Initialize on page load
document.addEventListener('DOMContentLoaded', () => {
  const app = new DashboardApp();
  app.init();
});
```

### DB2 Diagnostics Panel

Only rendered when `snapshot.db2Diagnostics` contains data:

```javascript
// db2-panel.js

function renderDb2Panel(db2Data) {
  const panel = document.getElementById('db2Panel');
  
  if (!db2Data || !db2Data.instances || db2Data.instances.length === 0) {
    panel.style.display = 'none';
    return;
  }
  
  panel.style.display = 'block';
  
  // Aggregate severity counts across all instances
  const severityCounts = { Critical: 0, Error: 0, Warning: 0, Event: 0 };
  
  for (const instance of db2Data.instances) {
    for (const entry of instance.entries || []) {
      const level = entry.level || 'Event';
      severityCounts[level] = (severityCounts[level] || 0) + 1;
    }
  }
  
  // Render severity distribution chart
  renderSeverityChart(severityCounts);
  
  // Render recent entries table
  renderDb2EntriesTable(db2Data.instances);
}
```

---

## Configuration

### appsettings.json

```json
{
  "Dashboard": {
    "ComputerInfoPath": "\\dedge-server\\DedgeCommon\\Configfiles\\ComputerInfo.json",
    "ServerMonitorExePath": "\\dedge-server\\DedgeCommon\\Software\\DedgeWinApps\\ServerMonitor\\ServerMonitor.exe",
    "ReinstallTriggerPath": "\\dedge-server\\DedgeCommon\\Software\\Config\\ServerMonitor\\ReinstallServerMonitor.txt",
    "ServerMonitorPort": 8999,
    "StatusPollIntervalSeconds": 30,
    "SnapshotTimeoutSeconds": 10
  },
  "Logging": {
    "LogLevel": {
      "Default": "Information"
    }
  }
}
```

---

## Reinstall Trigger Flow

```
1. User clicks [🔄 Reinstall] button for offline server
   ↓
2. Dashboard API auto-detects current agent version
   → Reads FileVersionInfo from ServerMonitor.exe
   ↓
3. Dashboard API creates trigger file:
   → C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor\ReinstallServerMonitor.txt
   → Contents: "Version=1.0.3"
   ↓
4. Tray apps on target servers detect trigger file
   → FileSystemWatcher or polling picks up file
   ↓
5. Tray apps compare installed version with trigger version
   → If different: Run Install-ServerMonitorService
   ↓
6. Agent reinstalled, service restarted
   ↓
7. Dashboard background service detects /api/IsAlive returns true
   ↓
8. Server dropdown updates: 🔴 → 🟢
```

---

## Technology Stack

| Layer | Technology |
|-------|------------|
| **Frontend** | HTML5, CSS3, Vanilla JavaScript |
| **Charts** | Chart.js or custom SVG gauges |
| **Backend** | ASP.NET Core 10 (Minimal API or Controllers) |
| **Background Services** | IHostedService / BackgroundService |
| **HTTP Client** | HttpClientFactory with resilience |
| **Static Files** | UseStaticFiles middleware |

---

## Implementation Phases

### Phase 1: Core Infrastructure
- [ ] Create project structure
- [ ] Implement ComputerInfoService (load server list)
- [ ] Implement ServerStatusService (background polling)
- [ ] Implement /api/servers endpoint
- [ ] Basic frontend with server dropdown

### Phase 2: Snapshot Viewing
- [ ] Implement SnapshotProxyService
- [ ] Add /api/snapshot/{server} endpoint
- [ ] Frontend: System metrics cards (CPU, Memory, Disk)
- [ ] Frontend: Alerts table
- [ ] Frontend: Top processes list

### Phase 3: Visual Enhancements
- [ ] Add gauges/meters for metrics
- [ ] Add severity-colored progress bars
- [ ] Responsive design
- [ ] Auto-refresh with countdown

### Phase 4: DB2 Diagnostics
- [ ] Conditional DB2 panel rendering
- [ ] Severity distribution chart
- [ ] DB2 entries table with filtering
- [ ] Message code distribution

### Phase 5: Remote Management
- [ ] Implement VersionService
- [ ] Implement /api/reinstall endpoint
- [ ] Reinstall button with confirmation
- [ ] Status notifications

---

## Security Considerations

1. **Network Access**: Dashboard should only be accessible from internal network
2. **File Access**: UNC paths require appropriate Windows authentication
3. **No Authentication Initially**: Consider adding if exposed more broadly
4. **Input Validation**: Validate server names against ComputerInfo.json list

---

---

## Auto-Refresh Functionality

### Configuration

- **Minimum Interval**: 10 seconds (enforced)
- **Default Interval**: 30 seconds
- **Visual Indicator**: Spinning refresh icon when active

### UI Components

```html
<div class="refresh-controls">
  <label class="toggle">
    <input type="checkbox" id="autoRefresh" checked>
    <span class="slider"></span>
    Auto-Refresh
  </label>
  <select id="refreshInterval">
    <option value="10">10 seconds</option>
    <option value="30" selected>30 seconds</option>
    <option value="60">1 minute</option>
    <option value="300">5 minutes</option>
  </select>
  <span id="refreshSpinner" class="spinner hidden">⟳</span>
  <span id="countdown">30s</span>
</div>
```

### JavaScript Implementation

```javascript
class AutoRefresh {
  constructor(minInterval = 10000) {
    this.minInterval = minInterval;
    this.interval = 30000;
    this.timer = null;
    this.countdown = null;
  }

  start(callback) {
    this.stop();
    this.showSpinner();
    callback();
    this.hideSpinner();
    
    this.timer = setInterval(() => {
      this.showSpinner();
      callback();
      this.hideSpinner();
    }, Math.max(this.interval, this.minInterval));
    
    this.startCountdown();
  }

  setInterval(seconds) {
    this.interval = Math.max(seconds * 1000, this.minInterval);
  }

  showSpinner() {
    document.getElementById('refreshSpinner').classList.remove('hidden');
    document.getElementById('refreshSpinner').classList.add('spinning');
  }

  hideSpinner() {
    document.getElementById('refreshSpinner').classList.remove('spinning');
  }
}
```

---

## Dark/Light Mode

### Theme Toggle

```html
<button id="themeToggle" class="theme-btn" title="Toggle Dark/Light Mode">
  <span class="theme-icon">🌙</span>
</button>
```

### CSS Variables (Theme Support)

```css
/* Light Mode (default) */
:root {
  --bg-primary: #f5f7fa;
  --bg-secondary: #ffffff;
  --bg-card: #ffffff;
  --text-primary: #1a1a2e;
  --text-secondary: #4a4a6a;
  --border-color: #e0e0e0;
  --accent-color: #3b82f6;
  --success-color: #10b981;
  --warning-color: #f59e0b;
  --error-color: #ef4444;
  --gauge-bg: #e5e7eb;
  --shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
}

/* Dark Mode */
[data-theme="dark"] {
  --bg-primary: #0f0f1a;
  --bg-secondary: #1a1a2e;
  --bg-card: #252540;
  --text-primary: #e5e5e5;
  --text-secondary: #a0a0b0;
  --border-color: #3a3a5a;
  --accent-color: #60a5fa;
  --success-color: #34d399;
  --warning-color: #fbbf24;
  --error-color: #f87171;
  --gauge-bg: #3a3a5a;
  --shadow: 0 2px 8px rgba(0, 0, 0, 0.4);
}

body {
  background-color: var(--bg-primary);
  color: var(--text-primary);
  transition: background-color 0.3s, color 0.3s;
}

.card {
  background-color: var(--bg-card);
  border: 1px solid var(--border-color);
  box-shadow: var(--shadow);
}
```

### JavaScript Theme Handler

```javascript
class ThemeManager {
  constructor() {
    this.theme = localStorage.getItem('theme') || 
                 (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
    this.apply();
  }

  toggle() {
    this.theme = this.theme === 'dark' ? 'light' : 'dark';
    this.apply();
    localStorage.setItem('theme', this.theme);
  }

  apply() {
    document.documentElement.setAttribute('data-theme', this.theme);
    const icon = document.querySelector('.theme-icon');
    if (icon) icon.textContent = this.theme === 'dark' ? '☀️' : '🌙';
  }
}
```

---

## Automated API Tests

### Test Runner Script

Located at: `ServerMonitorDashboard/tests/run-api-tests.ps1`

```powershell
# Automated API endpoint tests
# Outputs results to screen and JSON file

$baseUrl = "http://localhost:5100"
$results = @()

function Test-Endpoint {
    param($Name, $Method, $Url, $Body)
    
    $result = @{
        Name = $Name
        Url = $Url
        Method = $Method
        Timestamp = Get-Date -Format "o"
        Success = $false
        StatusCode = $null
        ResponseTimeMs = $null
        Response = $null
        Error = $null
    }
    
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        $params = @{
            Uri = $Url
            Method = $Method
            ContentType = "application/json"
        }
        if ($Body) { $params.Body = ($Body | ConvertTo-Json) }
        
        $response = Invoke-RestMethod @params
        $stopwatch.Stop()
        
        $result.Success = $true
        $result.StatusCode = 200
        $result.ResponseTimeMs = $stopwatch.ElapsedMilliseconds
        $result.Response = $response
        
        Write-Host "✅ $Name - ${$stopwatch.ElapsedMilliseconds}ms" -ForegroundColor Green
    }
    catch {
        $stopwatch.Stop()
        $result.Error = $_.Exception.Message
        $result.ResponseTimeMs = $stopwatch.ElapsedMilliseconds
        Write-Host "❌ $($Name): $($_.Exception.Message)" -ForegroundColor Red
    }
    
    return $result
}

# Run tests
$results += Test-Endpoint "GET /api/servers" "GET" "$baseUrl/api/servers"
$results += Test-Endpoint "GET /api/version" "GET" "$baseUrl/api/version"
$results += Test-Endpoint "GET /api/IsAlive" "GET" "$baseUrl/api/IsAlive"

# Save results
$outputPath = "$PSScriptRoot\test-results.json"
$results | ConvertTo-Json -Depth 10 | Set-Content $outputPath
Write-Host "`nResults saved to: $outputPath"
```

---

## Future Enhancements

- **Multi-select**: View multiple servers simultaneously
- **Historical Charts**: Trend data over time (requires data persistence)
- **Email Alerts**: Send notifications when servers go offline
- **Scheduled Reports**: Daily/weekly PDF summaries
- **Custom Thresholds**: Configure alert thresholds per server
