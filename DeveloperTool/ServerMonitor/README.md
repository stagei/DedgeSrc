# ServerMonitor Repository

This repository contains two .NET solutions for comprehensive Windows server health monitoring and management.

---

## ServerMonitor

A robust Windows server health monitoring service that runs as a Windows Service or console application.

### Features
- **Comprehensive Monitoring**: Tracks CPU usage, memory (physical & virtual), disk space, network connectivity, system uptime, Windows Updates, Windows Event Logs, Scheduled Tasks, and IBM DB2 diagnostic logs
- **Multi-Channel Alerting**: Sends alerts via SMS, Email, Windows Event Log, file-based logging, and WKMonitor integration
- **Alert Throttling**: Intelligent deduplication and rate-limiting to prevent alert storms
- **REST API**: Built-in HTTP API with Swagger UI for live querying of monitoring data
- **Snapshot Export**: Exports system state snapshots in JSON and HTML formats
- **Hot Reload**: Configuration changes are detected and applied without restart
- **Centralized Config**: Supports syncing configuration from a shared UNC path

### Monitors Included
| Monitor | Description |
|---------|-------------|
| ProcessorMonitor | CPU usage with threshold alerts and top process tracking |
| MemoryMonitor | Physical RAM usage monitoring |
| VirtualMemoryMonitor | Page file usage and paging rate monitoring |
| DiskMonitor | Disk space usage and I/O performance monitoring |
| NetworkMonitor | Host availability via ping, DNS, and TCP port checks |
| UptimeMonitor | System uptime tracking and reboot detection |
| WindowsUpdateMonitor | Pending security/critical updates detection |
| EventLogMonitor | Windows Event Log monitoring for critical events |
| ScheduledTaskMonitor | Scheduled task failure and status monitoring |
| Db2DiagMonitor | IBM DB2 diagnostic log parsing (for database servers) |

### Configuration
Configuration is managed via `appsettings.json` with per-monitor thresholds, polling intervals, and alert channel settings.

---

## ServerMonitorTrayIcon

A Windows Forms system tray application for managing the ServerMonitor service.

### Features
- **Visual Status Indicator**: Green checkmark when service is running, red X when stopped
- **Service Control**: Start, stop, and restart the ServerMonitor service from the system tray
- **Quick Access**: Open Swagger UI, HTML reports, and JSON snapshots with one click
- **Installation**: One-click installation of the latest ServerMonitor version
- **Single Instance**: Enforces single instance to prevent duplicate tray icons

### Context Menu
- Open Swagger UI (double-click shortcut)
- Open Last HTML Report
- Open Last JSON Snapshot
- Start/Stop/Restart Service
- Install Latest Version
- Exit

---

## Getting Started

### Prerequisites
- Windows Server or Windows 10/11
- .NET 10.0 Runtime
- PowerShell 7+ (for installation scripts)

### Installation
1. Build both solutions using `dotnet build`
2. Run `ServerMonitorAgent` to install ServerMonitor as a Windows Service
3. Optionally deploy ServerMonitorTrayIcon to user startup for convenient management

### Logs & Data
- Default log directory: `C:\opt\data\ServerMonitor\`
- Log files: `ServerMonitor_{date}.log` and `ServerMonitor_Alerts_{date}.log`
- Snapshots: JSON and HTML files in configured output directories

---

## Build and Test

```powershell
# Build both solutions
dotnet build ServerMonitor\ServerMonitor.sln --configuration Release
dotnet build ServerMonitorTrayIcon\ServerMonitorTrayIcon.sln --configuration Release

# Run ServerMonitor with test timeout
.\ServerMonitor\Test-ServerMonitor-With-Timeout.ps1
```

---

## License
Internal use only.
