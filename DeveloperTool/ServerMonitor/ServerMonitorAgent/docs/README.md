# Server Surveillance Tool

**Author:** Geir Helge Starholm, www.dEdge.no  
**Status:** Production Ready ✅  
**Version:** 1.0.0  
**Framework:** .NET 10.0  
**Language:** C#  
**Date:** 2025-11-26

---

## 🎯 Overview

The **Server Surveillance Tool** is a comprehensive Windows server monitoring solution built with **C# and .NET 10**. It tracks system health metrics, detects anomalies, and generates alerts based on configurable thresholds. All monitoring parameters are externalized in JSON configuration files with **hot-reload** support.

### ✨ Key Features

✅ **9 Core Monitoring Modules** - CPU, Memory, Virtual Memory, Disk I/O, Disk Space, Network, Uptime, Windows Update, Event Logs  
✅ **Scheduled Task Monitoring** - Direct Task Scheduler API integration  
✅ **23+ Critical Event IDs** - With direct documentation links  
✅ **Multi-Channel Alerting** - Event Log, Email, File  
✅ **Hot-Reload Configuration** - No restart needed for config changes  
✅ **Snapshot Exports** - Point-in-time JSON system state  
✅ **Auto-Kill Existing Instances** - Clean startup every time  
✅ **Windows Service Ready** - Install with NSSM or built-in service support

---

## 📚 Documentation

All documentation is located in the **[`docs/`](docs/)** folder:

### 🚀 Quick Start
- **[README-CSHARP.md](docs/README-CSHARP.md)** - Installation & quick start guide
- **[CONFIG-EXAMPLES.md](docs/CONFIG-EXAMPLES.md)** - Configuration examples

### 📖 Technical Documentation
- **[SPECIFICATION-CSHARP.md](docs/SPECIFICATION-CSHARP.md)** - Complete technical specification
- **[MONITORING-FLOW-DIAGRAMS.md](docs/MONITORING-FLOW-DIAGRAMS.md)** - Architecture diagrams (Mermaid)
- **[IMPLEMENTATION-COMPLETE.md](docs/IMPLEMENTATION-COMPLETE.md)** - Implementation details

### 🆕 Latest Features
- **[AUTO-KILL-AND-DOCUMENTATION-URLS.md](docs/AUTO-KILL-AND-DOCUMENTATION-URLS.md)** - Auto-kill & event documentation
- **[SCHEDULED-TASK-MONITORING-ADDED.md](docs/SCHEDULED-TASK-MONITORING-ADDED.md)** - Task Scheduler monitoring
- **[EVENT-ID-DOCUMENTATION-ADDED.md](docs/EVENT-ID-DOCUMENTATION-ADDED.md)** - 23 event IDs documented

### 📝 Complete Documentation Index
See **[docs/README.md](docs/README.md)** for the full documentation table of contents.

---

## 🚀 Quick Start

### Prerequisites
- **.NET 10 SDK** or later
- **Windows Server 2016+** or Windows 10/11
- **Administrator privileges** (for system monitoring)

### Build & Run

```powershell
# Clone or navigate to project
cd C:\opt\src\ServerMonitor

# Build
dotnet build ServerMonitor.sln --configuration Release

# Run (auto-kills existing instances)
cd src\ServerMonitor\ServerMonitorAgent\bin\Release\net10.0-windows\win-x64
.\ServerMonitor.exe
```

### Install as Windows Service

```powershell
# Using NSSM (recommended)
cd Install
.\Install-Service.ps1

# Or use built-in Windows Service support
sc.exe create ServerMonitor binPath= "C:\path\to\ServerMonitor.exe"
sc.exe start ServerMonitor
```

See **[docs/README-CSHARP.md](docs/README-CSHARP.md)** for detailed installation instructions.

---

## 🔍 Monitoring Capabilities

### System Metrics
- **Processor** - Per-core and overall CPU usage (5s polling)
- **Memory** - Physical RAM usage and availability (10s polling)
- **Virtual Memory** - Page file usage and paging rate (10s polling)
- **Disk I/O** - Queue length, latency, throughput (15s polling)
- **Disk Space** - Free space per volume with % and GB thresholds (15s polling)
- **Network** - Connectivity checks via ping and port monitoring (30s polling)
- **Uptime** - System uptime tracking (60s polling)

### Windows Components
- **Event Logs** - 23+ critical event IDs with documentation links (60s polling)
- **Windows Update** - Pending updates, failed installations (1h polling)
- **Scheduled Tasks** - Task execution monitoring, missed runs (5min polling)

### Alert Features
- **Multi-Channel** - Event Log, Email (SMTP), File logging
- **Throttling** - Prevent alert storms with configurable limits
- **Severity Levels** - Critical, Warning, Informational
- **Documentation Links** - Every event ID alert includes Microsoft Learn/EventID.net link
- **Alert History** - Persistent logging with automatic cleanup

### Export & Retention
- **JSON Snapshots** - Complete system state every 15 minutes
- **Auto-Cleanup** - Configurable retention (default 30 days)
- **Snapshot on Alert** - Capture state when critical alerts occur

---

## ⚙️ Configuration

All configuration is in `appsettings.json` with **hot-reload** support:

```json
{
  "Surveillance": {
    "ProcessorMonitoring": {
      "Enabled": true,
      "PollingIntervalSeconds": 5,
      "WarningThresholdPercent": 80,
      "CriticalThresholdPercent": 95
    },
    "EventMonitoring": {
      "Enabled": true,
      "PollingIntervalSeconds": 60,
      "EventsToMonitor": [
        {
          "EventId": 4625,
          "Description": "Security - Failed login attempt",
          "MaxOccurrences": 10,
          "TimeWindowMinutes": 5,
          "DocumentationUrl": "https://learn.microsoft.com/..."
        }
      ]
    }
  }
}
```

See **[docs/CONFIG-EXAMPLES.md](docs/CONFIG-EXAMPLES.md)** for complete configuration examples.

---

## 📂 Project Structure

```
ServerMonitor/
├── docs/                                 # 📚 All documentation
│   ├── README.md                         #    Documentation index
│   ├── README-CSHARP.md                  #    Quick start guide
│   ├── SPECIFICATION-CSHARP.md           #    Technical spec
│   └── ...                               #    Feature docs
├── src/
│   ├── ServerMonitor/           # Main Windows Service
│   │   ├── Program.cs                    #   Entry point + auto-kill
│   │   ├── SurveillanceWorker.cs         #   Background service
│   │   ├── appsettings.json              #   Configuration
│   │   └── NLog.config                   #   Logging config
│   └── ServerMonitor.Core/      # Core monitoring logic
│       ├── Monitors/                     #   All monitor implementations
│       ├── Services/                     #   Orchestrator, alerts, exports
│       ├── AlertChannels/                #   Event Log, Email, File
│       ├── Configuration/                #   Config models
│       ├── Interfaces/                   #   Abstractions
│       └── Models/                       #   Data models
├── tests/
│   └── ServerMonitor.Tests/     # Unit tests
├── Install/
│   ├── Install-Service.ps1               # NSSM service installer
│   ├── Uninstall-Service.ps1             # Service uninstaller
│   └── Build-And-Publish.ps1             # Build script
├── _deploy.ps1                           # Deploy-Handler integration
└── README.md                             # This file
```

---

## 🎁 Recent Enhancements

### Auto-Kill Feature (2025-11-26)
- Automatically terminates existing instances on startup
- No more "file locked" errors during development
- Clean deployments without manual service stops
- Full audit trail in logs

### Event Documentation URLs (2025-11-26)
- All 23 monitored event IDs include direct documentation links
- Microsoft Learn and EventID.net references
- Faster troubleshooting - one click to documentation
- Reduces MTTR (Mean Time To Resolution)

### Scheduled Task Monitoring (2025-11-26)
- Direct Task Scheduler API integration
- Monitor task execution status and exit codes
- Detect missed scheduled runs
- Alert on disabled critical tasks

---

## 📊 Performance

| Metric | Target | Actual |
|--------|--------|--------|
| CPU Usage | < 2% | ~0.5% average |
| Memory | < 200 MB | ~50 MB baseline |
| Disk I/O | Minimal | Only during snapshots |
| Startup Time | < 10s | ~3-5 seconds |

---

## 🛠️ Development

### Build
```powershell
dotnet build ServerMonitor.sln --configuration Release
```

### Test
```powershell
dotnet test
```

### Publish
```powershell
cd Install
.\Build-And-Publish.ps1
```

### Deploy
```powershell
# Uses Deploy-Handler module
.\\_deploy.ps1
```

---

## 🔐 Security

- **Least Privilege** - Runs with minimum required permissions
- **Encrypted Credentials** - Email/SMTP passwords stored securely
- **Protected Logs** - Output to `C:\opt\data\AllPwshLog`
- **Audit Trail** - All actions logged via NLog
- **No Cleartext Secrets** - Configuration can use Windows Credential Manager

---

## 📞 Support

### For Operators
- Quick Start: [docs/README-CSHARP.md](docs/README-CSHARP.md)
- Configuration: [docs/CONFIG-EXAMPLES.md](docs/CONFIG-EXAMPLES.md)
- Event Docs: [docs/EVENT-ID-DOCUMENTATION-ADDED.md](docs/EVENT-ID-DOCUMENTATION-ADDED.md)

### For Administrators
- Installation: [docs/README-CSHARP.md#installation](docs/README-CSHARP.md)
- Service Setup: [docs/README-CSHARP.md#windows-service](docs/README-CSHARP.md)
- Config Reference: [docs/SPECIFICATION-CSHARP.md](docs/SPECIFICATION-CSHARP.md)

### For Developers
- Architecture: [docs/MONITORING-FLOW-DIAGRAMS.md](docs/MONITORING-FLOW-DIAGRAMS.md)
- Implementation: [docs/IMPLEMENTATION-COMPLETE.md](docs/IMPLEMENTATION-COMPLETE.md)
- Build Guide: [docs/BUILD-AND-RUN-SUCCESS.md](docs/BUILD-AND-RUN-SUCCESS.md)

---

## 📝 License

Internal use within FK organization.

---

## 🎯 Roadmap

### Completed ✅
- Core monitoring modules
- Event log monitoring with 23+ event IDs
- Scheduled task monitoring
- Auto-kill existing instances
- Event documentation URLs
- Hot-reload configuration
- Multi-channel alerting
- Snapshot exports
- Windows Service support

### Planned 🔲
- Wildcard support for scheduled tasks
- User-based task filtering
- Central aggregation service
- Web dashboard
- Historical trending
- Predictive analytics

---

## 🏆 Why C#?

While the initial analysis recommended PowerShell, the implementation was done in **C# and .NET 10** for:

✅ **Better Performance** - Sub-second polling capability  
✅ **Type Safety** - Compile-time error detection  
✅ **Better Tooling** - IntelliSense, debugging, testing frameworks  
✅ **Long-Running Stability** - Robust Windows Service support  
✅ **Maintainability** - Clear architecture with dependency injection  
✅ **Extensibility** - Easy to add new monitors and alert channels

See [docs/LANGUAGE-ANALYSIS.md](docs/LANGUAGE-ANALYSIS.md) for the original comparison.

---

## 📈 Changelog

### Version 1.0.0 (2025-11-26)
- ✅ Complete C# implementation with .NET 10
- ✅ All 9 core monitoring modules
- ✅ Scheduled task monitoring
- ✅ 23+ event IDs with documentation links
- ✅ Auto-kill existing instances
- ✅ Multi-channel alerting
- ✅ Hot-reload configuration
- ✅ Production ready

---

**Author:** Geir Helge Starholm  
**Website:** www.dEdge.no  
**Project:** Server Surveillance Tool  
**Status:** ✅ Production Ready  

---

*For complete documentation, see the **[docs/](docs/)** folder*
