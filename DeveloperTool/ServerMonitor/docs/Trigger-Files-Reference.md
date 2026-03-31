# ServerMonitor Trigger Files Reference

This document describes the global trigger files used to control ServerMonitor agents across all servers.

## Overview

ServerMonitor uses trigger files stored in a central network location to coordinate actions across multiple servers. These files are monitored by the Agent and/or Tray Icon applications to trigger specific behaviors.

**Trigger File Location:**
```
C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor\
```

---

## Trigger Files Summary

| File | Dashboard Can Set | Agent Monitors | Tray Monitors | Purpose |
|------|:-----------------:|:--------------:|:-------------:|---------|
| `StopServerMonitor.txt` | ✓ | ✓ | ✗ | Stop ALL agents globally |
| `StopServerMonitor_{Server}.txt` | ✓ | ✓ | ✗ | Stop specific server's agent |
| `StartServerMonitor.txt` | ✓ | ✗ | ✓ | Start ALL agents globally |
| `StartServerMonitor_{Server}.txt` | ✓ | ✗ | ✓ | Start specific server's agent |
| `DisableServerMonitor.txt` | ✓ | ✓ | ✓ | Prevent ALL agents from starting |
| `ReinstallServerMonitor.txt` | ✓ | ✗ | ✓ | Trigger version update |

---

## Detailed File Descriptions

### StopServerMonitor.txt (Global Stop)

**Purpose:** Gracefully stops ALL running ServerMonitor agents.

**Monitored By:** Agent (`StopFileMonitorService`)

**Behavior:**
- Agent checks for this file every 5 seconds
- When detected, agent initiates graceful shutdown
- File is **NOT deleted** after processing (stays for other agents to process)
- All agents will stop when they detect this file

**File Contents:**
```
# ServerMonitor Stop Trigger File
# Target: ALL
TargetServer=*
Reason=<reason text>
Created=<UTC timestamp>
Source=Dashboard
```

**Dashboard API:**
```http
POST /api/stop
Content-Type: application/json

{
  "serverName": "*",
  "reason": "Maintenance window"
}
```

---

### StopServerMonitor_{Server}.txt (Server-Specific Stop)

**Purpose:** Gracefully stops a specific server's agent only.

**Monitored By:** Agent (`StopFileMonitorService`)

**Behavior:**
- Agent checks for its own machine-specific file every 5 seconds
- Only the targeted server's agent will stop
- File is **deleted** after processing by the target agent
- Takes priority over global stop file

**Example Filename:** `StopServerMonitor_p-no1fkmprd-app.txt`

**Dashboard API:**
```http
POST /api/stop
Content-Type: application/json

{
  "serverName": "p-no1fkmprd-app",
  "reason": "Server maintenance"
}
```

---

### StartServerMonitor.txt (Global Start)

**Purpose:** Starts the ServerMonitor agent on ALL servers where it's not running.

**Monitored By:** Tray Icon (`TrayIconApplicationContext`)

**Behavior:**
- Tray Icon checks for this file periodically
- If agent is not running, Tray will start it
- File is **NOT deleted** (stays for other trays to process)
- Only affects servers where agent is currently stopped

**File Contents:**
```
# ServerMonitor Start Trigger File
# Target: ALL
TargetServer=*
Created=<UTC timestamp>
Source=Dashboard
```

**Dashboard API:**
```http
POST /api/start
Content-Type: application/json

{
  "serverName": "*"
}
```

---

### StartServerMonitor_{Server}.txt (Server-Specific Start)

**Purpose:** Starts the agent on a specific server only.

**Monitored By:** Tray Icon (`TrayIconApplicationContext`)

**Behavior:**
- Only the targeted server's Tray Icon processes this file
- File is **deleted** after processing by the target
- Agent will be started if not already running

**Example Filename:** `StartServerMonitor_dedge-server.txt`

**Dashboard API:**
```http
POST /api/start
Content-Type: application/json

{
  "serverName": "dedge-server"
}
```

---

### DisableServerMonitor.txt (Global Disable)

**Purpose:** Prevents ALL agents from starting. This is a "kill switch" that blocks agent startup.

**Monitored By:** 
- Agent (`Program.cs` - at startup)
- Tray Icon (`TrayIconApplicationContext` - before starting agent)
- Tray API (`TrayApiServer` - on start/restart requests)

**Behavior:**
- Agent checks for this file at startup and **refuses to start** if present
- Tray Icon will not start the agent while this file exists
- Tray API `/api/agent/start` and `/api/agent/restart` return error if file exists
- File persists until manually removed
- Running agents are NOT stopped (only prevents new starts)

**File Contents:**
```
# ServerMonitor Disable File
# This file prevents all ServerMonitor agents from starting
# Delete this file to re-enable agents

Reason=<reason text>
Created=<UTC timestamp>
Source=Dashboard
```

**Dashboard API:**
```http
# Create disable file
POST /api/disable
Content-Type: application/json

{
  "reason": "System maintenance - do not start agents"
}

# Remove disable file
DELETE /api/disable
```

**Use Cases:**
- Scheduled maintenance windows
- Emergency stop of all monitoring
- Debugging agent issues without auto-restart

---

### ReinstallServerMonitor.txt (Version Update Trigger)

**Purpose:** Triggers agents to update to a new version.

**Monitored By:** Tray Icon (`TrayIconApplicationContext` via FileSystemWatcher)

**Behavior:**
- Tray Icon watches for changes to this file
- When detected, Tray downloads and installs the new version
- Agent is restarted with the new version
- File contains the target version number

**File Contents:**
```
Version=1.0.121
```

**Dashboard API:**
```http
POST /api/reinstall
Content-Type: application/json

{
  "serverName": "*",
  "version": "1.0.121"
}
```

---

## Dashboard Control Panel

The Dashboard provides a Control Panel UI with buttons to manage trigger files:

### Quick Actions
| Button | Action | Creates File |
|--------|--------|--------------|
| Stop All Agents | Stop all running agents | `StopServerMonitor.txt` |
| Start All Agents | Start all stopped agents | `StartServerMonitor.txt` |
| Update All Agents | Trigger version update | `ReinstallServerMonitor.txt` |

### Global Enable/Disable Toggle
- **Disable**: Creates `DisableServerMonitor.txt`
- **Enable**: Deletes `DisableServerMonitor.txt`

### Quick Links
- **Config Folder**: Copies config folder path to clipboard
- **Create Stop File**: Creates stop trigger (global or server-specific)

---

## API Endpoints Summary

### Trigger File Management

| Action | Method | Endpoint | Body |
|--------|--------|----------|------|
| Create Stop | POST | `/api/stop` | `{"serverName": "*", "reason": "..."}` |
| Delete Stop | DELETE | `/api/stop` | - |
| Create Start | POST | `/api/start` | `{"serverName": "*"}` |
| Delete Start | DELETE | `/api/start` | - |
| Create Disable | POST | `/api/disable` | `{"reason": "..."}` |
| Delete Disable | DELETE | `/api/disable` | - |
| Create Reinstall | POST | `/api/reinstall` | `{"serverName": "*"}` |
| Delete Reinstall | DELETE | `/api/reinstall` | - |
| Check Status | GET | `/api/trigger-status` | - |

### Direct Agent Control (via Tray API)

These endpoints communicate directly with the agent's Tray Icon API (port 8997):

| Action | Method | Endpoint | Notes |
|--------|--------|----------|-------|
| Start Agent | POST | `/api/trayapi/{server}/start` | Blocked if disabled |
| Stop Agent | POST | `/api/trayapi/{server}/stop` | Immediate stop |
| Restart Agent | POST | `/api/trayapi/{server}/restart` | Blocked if disabled |
| Get Status | GET | `/api/trayapi/{server}/status` | Returns running state |

---

## Monitoring Intervals

| Component | Check Interval | What It Monitors |
|-----------|----------------|------------------|
| Agent StopFileMonitor | 5 seconds | Stop files |
| Tray Icon Status Check | Configurable | Start files, disable file |
| Tray FileSystemWatcher | Real-time | Reinstall trigger |

---

## File Priority

When multiple trigger files exist:

1. **Machine-specific files** take priority over global files
2. **Disable file** blocks start operations even if start trigger exists
3. **Stop files** are processed before start files

---

## Troubleshooting

### Agent won't start
1. Check for `DisableServerMonitor.txt` - delete if present
2. Check Dashboard Control Panel for "Agents Disabled" indicator
3. Verify Tray Icon is running on target server

### Agent keeps restarting
1. Windows Service recovery settings may be set to auto-restart
2. Check for `StartServerMonitor.txt` triggering restarts
3. Verify no scheduled tasks are restarting the agent

### Stop command not working
1. Verify agent is actually running (check Tray Icon status)
2. Check network connectivity to config folder
3. Try direct API: `POST /api/trayapi/{server}/stop`

### Trigger file not being processed
1. Check file permissions on config folder
2. Verify server can access `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\...`
3. Check agent/tray logs for errors

---

## Version History

| Version | Changes |
|---------|---------|
| 1.0.121 | Added DisableServerMonitor.txt enforcement in Agent and Tray |
| 1.0.120 | Added Quick Links section to Dashboard Control Panel |
| 1.0.119 | Initial trigger file system implementation |
