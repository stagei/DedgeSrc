# Server Surveillance Tool - Technical Specification

**Author:** Geir Helge Starholm, www.dEdge.no  
**Version:** 1.0  
**Date:** 2025-11-26

---

## 1. Overview

The Server Surveillance Tool is a comprehensive system monitoring solution designed to continuously track server health metrics, detect anomalies, and generate alerts based on configurable thresholds. The tool captures point-in-time snapshots and maintains historical data for analysis.

---

## 2. Core Requirements

### 2.1 Configuration Management
- All thresholds, limits, and monitoring parameters must be externalized to JSON configuration files
- Configuration should be hot-reloadable without service restart
- Support for environment-specific configurations (dev/test/prod)
- Validation of configuration on load with detailed error reporting

### 2.2 Data Collection Architecture
- Polling interval configurable per metric category
- Independent collection threads/jobs for each monitoring category
- Graceful degradation if individual collectors fail
- Minimal performance impact on monitored system (< 2% CPU, < 100MB RAM)

### 2.3 Data Export & Persistence
- Snapshot exports to JSON files at configurable intervals
- Retention policy for historical snapshots
- Optional real-time streaming to central monitoring system
- Data compression for long-term storage

### 2.4 Alerting System
- Multi-channel alerting (Event Log, Email, File, Custom webhook)
- Alert throttling to prevent notification storms
- Severity levels: Critical, Warning, Informational
- Alert acknowledgment and suppression support

---

## 3. Monitoring Categories

### 3.1 Event Log Monitoring

**Description:** Track specific Windows Event Log entries that indicate system issues.

**Metrics Collected:**
- Event ID
- Event Source
- Event Level (Error, Warning, Critical)
- Event Message
- Timestamp
- Event Count (within monitoring window)

**Configuration Parameters:**
```json
{
  "eventMonitoring": {
    "enabled": true,
    "pollingIntervalSeconds": 60,
    "eventsToMonitor": [
      {
        "eventId": 1001,
        "description": "Application crash event",
        "source": "Application Error",
        "logName": "Application",
        "level": "Error",
        "maxOccurrences": 5,
        "timeWindowMinutes": 15
      },
      {
        "eventId": 4625,
        "description": "Failed login attempt",
        "source": "Microsoft-Windows-Security-Auditing",
        "logName": "Security",
        "level": "Warning",
        "maxOccurrences": 10,
        "timeWindowMinutes": 5
      }
    ]
  }
}
```

**Alert Conditions:**
- Event occurrence exceeds `maxOccurrences` within `timeWindowMinutes`
- Critical events trigger immediate alerts regardless of count

---

### 3.2 Processor Usage Monitoring

**Description:** Monitor CPU utilization per core and overall system processor usage.

**Metrics Collected:**
- Overall CPU utilization percentage
- Per-core CPU utilization percentage
- Peak CPU usage (1min, 5min, 15min averages)
- Duration above threshold (in seconds)
- Top CPU-consuming processes

**Configuration Parameters:**
```json
{
  "processorMonitoring": {
    "enabled": true,
    "pollingIntervalSeconds": 5,
    "thresholds": {
      "warningPercent": 80,
      "criticalPercent": 95,
      "sustainedDurationSeconds": 300
    },
    "perCoreMonitoring": true,
    "trackTopProcesses": 5
  }
}
```

**Alert Conditions:**
- CPU usage exceeds `warningPercent` for longer than `sustainedDurationSeconds`
- CPU usage exceeds `criticalPercent` at any point
- Any single core at 100% for more than `sustainedDurationSeconds`

**Tracking Requirements:**
- Maintain running counter of total seconds any processor was above threshold
- Track which specific cores are consistently overutilized
- Reset counters daily at midnight or on service restart

---

### 3.3 Memory Usage Monitoring

**Description:** Monitor physical RAM utilization.

**Metrics Collected:**
- Total physical memory (GB)
- Available physical memory (GB)
- Used memory percentage
- Duration above threshold (in seconds)
- Memory pressure indicators
- Top memory-consuming processes

**Configuration Parameters:**
```json
{
  "memoryMonitoring": {
    "enabled": true,
    "pollingIntervalSeconds": 10,
    "thresholds": {
      "warningPercent": 85,
      "criticalPercent": 95,
      "sustainedDurationSeconds": 300
    },
    "trackTopProcesses": 5
  }
}
```

**Alert Conditions:**
- Memory usage exceeds `warningPercent` for longer than `sustainedDurationSeconds`
- Memory usage exceeds `criticalPercent` at any point
- Available memory drops below 500MB

---

### 3.4 Virtual Memory (Page File) Monitoring

**Description:** Monitor page file usage and paging activity.

**Metrics Collected:**
- Total virtual memory (GB)
- Available virtual memory (GB)
- Used virtual memory percentage
- Duration above threshold (in seconds)
- Pages per second (paging rate)

**Configuration Parameters:**
```json
{
  "virtualMemoryMonitoring": {
    "enabled": true,
    "pollingIntervalSeconds": 10,
    "thresholds": {
      "warningPercent": 80,
      "criticalPercent": 90,
      "sustainedDurationSeconds": 300,
      "excessivePagingRate": 1000
    }
  }
}
```

**Alert Conditions:**
- Virtual memory usage exceeds `warningPercent` for longer than `sustainedDurationSeconds`
- Virtual memory usage exceeds `criticalPercent`
- Paging rate exceeds `excessivePagingRate` pages/sec

---

### 3.5 Disk Usage (I/O) Monitoring

**Description:** Monitor disk I/O performance and queue lengths.

**Metrics Collected:**
- Disk read/write bytes per second (per disk)
- Disk queue length
- Average disk response time (ms)
- Duration above threshold (in seconds)
- IOPS (Input/Output Operations Per Second)

**Configuration Parameters:**
```json
{
  "diskUsageMonitoring": {
    "enabled": true,
    "pollingIntervalSeconds": 15,
    "disksToMonitor": ["C:", "D:", "E:"],
    "thresholds": {
      "maxQueueLength": 10,
      "maxResponseTimeMs": 50,
      "sustainedDurationSeconds": 180
    }
  }
}
```

**Alert Conditions:**
- Disk queue length exceeds `maxQueueLength` for longer than `sustainedDurationSeconds`
- Average response time exceeds `maxResponseTimeMs` consistently

---

### 3.6 Disk Space Monitoring

**Description:** Monitor available disk space on all volumes.

**Metrics Collected:**
- Total disk space (GB)
- Available disk space (GB)
- Used space percentage
- Free space (GB)
- Volume label and file system type

**Configuration Parameters:**
```json
{
  "diskSpaceMonitoring": {
    "enabled": true,
    "pollingIntervalSeconds": 300,
    "disksToMonitor": ["C:", "D:", "E:"],
    "thresholds": {
      "warningPercent": 85,
      "criticalPercent": 95,
      "minimumFreeSpaceGB": 10
    }
  }
}
```

**Alert Conditions:**
- Used space exceeds `warningPercent`
- Used space exceeds `criticalPercent`
- Free space drops below `minimumFreeSpaceGB`

---

### 3.7 Network Connectivity Monitoring

**Description:** Monitor network connectivity to critical baseline hosts.

**Metrics Collected:**
- Ping response time (ms)
- Packet loss percentage
- DNS resolution time
- TCP port connectivity status
- Consecutive failure count

**Configuration Parameters:**
```json
{
  "networkMonitoring": {
    "enabled": true,
    "pollingIntervalSeconds": 30,
    "baselineHosts": [
      {
        "hostname": "p-no1fkmprd-db",
        "ipAddress": "10.0.1.100",
        "description": "Production Database Server",
        "checkPing": true,
        "checkDns": true,
        "portsToCheck": [1433, 445],
        "thresholds": {
          "maxPingMs": 50,
          "maxPacketLossPercent": 5,
          "consecutiveFailuresBeforeAlert": 3
        }
      },
      {
        "hostname": "8.8.8.8",
        "description": "Internet Gateway (Google DNS)",
        "checkPing": true,
        "checkDns": false,
        "thresholds": {
          "maxPingMs": 100,
          "consecutiveFailuresBeforeAlert": 5
        }
      }
    ]
  }
}
```

**Alert Conditions:**
- Ping fails `consecutiveFailuresBeforeAlert` times in a row
- Ping response time exceeds `maxPingMs` consistently
- Packet loss exceeds `maxPacketLossPercent`
- TCP port connectivity fails

---

### 3.8 Windows Uptime Monitoring

**Description:** Track system uptime and boot events.

**Metrics Collected:**
- Last boot time
- Current uptime (days, hours, minutes)
- Unexpected reboot detection
- Clean vs. dirty shutdown detection

**Configuration Parameters:**
```json
{
  "uptimeMonitoring": {
    "enabled": true,
    "pollingIntervalSeconds": 60,
    "alerts": {
      "unexpectedRebootAlert": true,
      "minimumUptimeDaysWarning": 90,
      "maximumUptimeDaysWarning": 365
    }
  }
}
```

**Alert Conditions:**
- Unexpected system reboot detected (Event ID 6008)
- Uptime exceeds `maximumUptimeDaysWarning` (needs patching reboot)
- Dirty shutdown detected

---

### 3.9 Windows Update Monitoring

**Description:** Track pending Windows updates and installation status.

**Metrics Collected:**
- Count of pending updates
- Count of critical/security updates pending
- Last update installation date
- Update categories (Security, Critical, Optional, Driver)
- Failed update installations

**Configuration Parameters:**
```json
{
  "windowsUpdateMonitoring": {
    "enabled": true,
    "pollingIntervalSeconds": 3600,
    "thresholds": {
      "maxPendingSecurityUpdates": 0,
      "maxPendingCriticalUpdates": 0,
      "maxDaysSinceLastUpdate": 30
    },
    "alerts": {
      "alertOnPendingSecurityUpdates": true,
      "alertOnFailedInstallations": true
    }
  }
}
```

**Alert Conditions:**
- Pending security or critical updates exceed thresholds
- No updates installed within `maxDaysSinceLastUpdate` days
- Update installation failures detected

---

### 3.10 Additional Monitoring Categories (Extended)

#### 3.10.1 Windows Services Monitoring

**Description:** Monitor critical Windows services status.

**Configuration Parameters:**
```json
{
  "servicesMonitoring": {
    "enabled": true,
    "pollingIntervalSeconds": 60,
    "criticalServices": [
      {
        "serviceName": "W3SVC",
        "displayName": "World Wide Web Publishing Service",
        "expectedStatus": "Running",
        "restartOnFailure": false
      },
      {
        "serviceName": "MSSQLSERVER",
        "displayName": "SQL Server (MSSQLSERVER)",
        "expectedStatus": "Running",
        "restartOnFailure": false
      }
    ]
  }
}
```

#### 3.10.2 Process Monitoring

**Description:** Monitor presence or absence of specific processes.

**Configuration Parameters:**
```json
{
  "processMonitoring": {
    "enabled": true,
    "pollingIntervalSeconds": 30,
    "requiredProcesses": [
      {
        "processName": "myapp.exe",
        "description": "Critical Business Application",
        "alertIfNotRunning": true,
        "maxInstances": 1,
        "minInstances": 1
      }
    ],
    "forbiddenProcesses": [
      {
        "processName": "malware.exe",
        "description": "Known malicious process",
        "alertIfRunning": true,
        "killOnDetection": false
      }
    ]
  }
}
```

#### 3.10.3 Certificate Expiration Monitoring

**Description:** Monitor SSL/TLS certificate expiration dates.

**Configuration Parameters:**
```json
{
  "certificateMonitoring": {
    "enabled": true,
    "pollingIntervalSeconds": 86400,
    "certificateLocations": [
      {
        "storeName": "My",
        "storeLocation": "LocalMachine",
        "thumbprint": "ABC123...",
        "description": "Web Server SSL Certificate"
      }
    ],
    "thresholds": {
      "warningDaysBeforeExpiration": 30,
      "criticalDaysBeforeExpiration": 7
    }
  }
}
```

#### 3.10.4 Failed Login Attempts Monitoring

**Description:** Track failed authentication attempts.

**Configuration Parameters:**
```json
{
  "failedLoginMonitoring": {
    "enabled": true,
    "pollingIntervalSeconds": 60,
    "thresholds": {
      "maxFailedLoginsPerUser": 5,
      "maxFailedLoginsTotal": 20,
      "timeWindowMinutes": 15
    },
    "alerts": {
      "alertOnBruteForcePattern": true,
      "alertOnLockedAccounts": true
    }
  }
}
```

#### 3.10.5 Scheduled Tasks Monitoring

**Description:** Verify scheduled tasks are running successfully.

**Configuration Parameters:**
```json
{
  "scheduledTasksMonitoring": {
    "enabled": true,
    "pollingIntervalSeconds": 300,
    "tasksToMonitor": [
      {
        "taskName": "\\Microsoft\\Windows\\Backup\\ConfigNotification",
        "description": "System Backup Task",
        "alertOnFailure": true,
        "alertOnMissedRun": true
      }
    ]
  }
}
```

#### 3.10.6 Security Monitoring

**Description:** Monitor Windows Defender and firewall status.

**Configuration Parameters:**
```json
{
  "securityMonitoring": {
    "enabled": true,
    "pollingIntervalSeconds": 300,
    "checks": {
      "defenderStatus": true,
      "defenderSignatureAge": true,
      "firewallStatus": true,
      "antivirusEnabled": true
    },
    "thresholds": {
      "maxSignatureAgeDays": 7
    }
  }
}
```

#### 3.10.7 Application Pool Monitoring (IIS)

**Description:** Monitor IIS application pool health.

**Configuration Parameters:**
```json
{
  "iisMonitoring": {
    "enabled": false,
    "pollingIntervalSeconds": 60,
    "applicationPools": [
      {
        "name": "DefaultAppPool",
        "expectedState": "Started",
        "restartOnFailure": false
      }
    ]
  }
}
```

#### 3.10.8 Database Connectivity Monitoring

**Description:** Monitor database connection health.

**Configuration Parameters:**
```json
{
  "databaseMonitoring": {
    "enabled": true,
    "pollingIntervalSeconds": 120,
    "databases": [
      {
        "name": "ProductionDB",
        "connectionString": "Server=localhost;Database=master;Integrated Security=true;",
        "queryTimeout": 5,
        "testQuery": "SELECT 1",
        "alertOnConnectionFailure": true
      }
    ]
  }
}
```

#### 3.10.9 Temperature Monitoring

**Description:** Monitor system temperature sensors (if available via WMI).

**Configuration Parameters:**
```json
{
  "temperatureMonitoring": {
    "enabled": false,
    "pollingIntervalSeconds": 60,
    "thresholds": {
      "cpuWarningCelsius": 70,
      "cpuCriticalCelsius": 85
    }
  }
}
```

#### 3.10.10 User Session Monitoring

**Description:** Track active user sessions.

**Configuration Parameters:**
```json
{
  "userSessionMonitoring": {
    "enabled": true,
    "pollingIntervalSeconds": 300,
    "thresholds": {
      "maxConcurrentSessions": 10,
      "maxDisconnectedSessions": 5
    }
  }
}
```

---

## 4. Data Export & Snapshot Format

### 4.1 Snapshot Structure

```json
{
  "metadata": {
    "serverName": "P-NO1FKMPRD-DB",
    "timestamp": "2025-11-26T14:30:00Z",
    "snapshotId": "550e8400-e29b-41d4-a716-446655440000",
    "collectionDurationMs": 1234,
    "toolVersion": "1.0.0"
  },
  "processor": {
    "overallUsagePercent": 45.2,
    "perCoreUsage": [42.1, 48.3, 45.0, 45.5],
    "averages": {
      "oneMinute": 43.5,
      "fiveMinute": 41.2,
      "fifteenMinute": 39.8
    },
    "timeAboveThresholdSeconds": 1250,
    "topProcesses": [
      {"name": "sqlservr.exe", "pid": 1234, "cpuPercent": 15.2},
      {"name": "pwsh.exe", "pid": 5678, "cpuPercent": 8.1}
    ]
  },
  "memory": {
    "totalGB": 32.0,
    "availableGB": 8.5,
    "usedPercent": 73.4,
    "timeAboveThresholdSeconds": 0,
    "topProcesses": [
      {"name": "sqlservr.exe", "pid": 1234, "memoryMB": 4096}
    ]
  },
  "virtualMemory": {
    "totalGB": 48.0,
    "availableGB": 20.0,
    "usedPercent": 58.3,
    "timeAboveThresholdSeconds": 0,
    "pagingRatePerSec": 25
  },
  "disks": {
    "usage": [
      {
        "drive": "C:",
        "queueLength": 2.3,
        "avgResponseTimeMs": 15,
        "timeAboveThresholdSeconds": 0,
        "iops": 150
      }
    ],
    "space": [
      {
        "drive": "C:",
        "totalGB": 500,
        "availableGB": 125,
        "usedPercent": 75.0,
        "fileSystem": "NTFS"
      }
    ]
  },
  "network": [
    {
      "hostname": "p-no1fkmprd-db",
      "pingMs": 2,
      "packetLossPercent": 0,
      "dnsResolutionMs": 5,
      "portStatus": {
        "1433": "Open",
        "445": "Open"
      },
      "consecutiveFailures": 0
    }
  ],
  "uptime": {
    "lastBootTime": "2025-11-01T08:00:00Z",
    "currentUptimeDays": 25.27,
    "unexpectedReboot": false
  },
  "windowsUpdates": {
    "pendingCount": 3,
    "securityUpdates": 0,
    "criticalUpdates": 0,
    "lastInstallDate": "2025-11-20T03:00:00Z",
    "failedUpdates": 0
  },
  "events": [
    {
      "eventId": 1001,
      "source": "Application Error",
      "level": "Error",
      "count": 2,
      "lastOccurrence": "2025-11-26T12:15:00Z",
      "message": "Application crash detected"
    }
  ],
  "services": [
    {
      "serviceName": "W3SVC",
      "status": "Running",
      "startType": "Automatic"
    }
  ],
  "alerts": [
    {
      "severity": "Warning",
      "category": "DiskSpace",
      "message": "Disk C: usage at 85%",
      "timestamp": "2025-11-26T14:25:00Z"
    }
  ]
}
```

### 4.2 Export Configuration

```json
{
  "exportSettings": {
    "enabled": true,
    "outputDirectory": "C:\\opt\\data\\ServerSurveillance\\Snapshots",
    "fileNamePattern": "{ServerName}_{Timestamp:yyyyMMdd_HHmmss}.json",
    "exportIntervals": {
      "scheduleMinutes": [0, 15, 30, 45],
      "onAlertTrigger": true,
      "onDemand": true
    },
    "retention": {
      "maxAgeHours": 720,
      "maxFileCount": 1000,
      "compressionEnabled": true
    }
  }
}
```

---

## 5. Alerting System

### 5.1 Alert Configuration

```json
{
  "alerting": {
    "enabled": true,
    "channels": [
      {
        "type": "EventLog",
        "enabled": true,
        "logName": "Application",
        "source": "ServerMonitor",
        "minSeverity": "Warning"
      },
      {
        "type": "Email",
        "enabled": false,
        "smtpServer": "smtp.company.com",
        "from": "monitoring@company.com",
        "to": ["admin@company.com"],
        "minSeverity": "Critical"
      },
      {
        "type": "File",
        "enabled": true,
        "logPath": "C:\\opt\\data\\AllPwshLog\\ServerSurveillance_{Date}.log",
        "minSeverity": "Informational"
      },
      {
        "type": "Webhook",
        "enabled": false,
        "url": "https://monitoring.company.com/api/alerts",
        "authToken": "Bearer xyz...",
        "minSeverity": "Warning"
      }
    ],
    "throttling": {
      "enabled": true,
      "maxAlertsPerHour": 50,
      "duplicateSuppressionMinutes": 15
    },
    "customAlerts": [
      {
        "name": "HighCpuAndMemory",
        "condition": "processor.overallUsagePercent > 90 AND memory.usedPercent > 90",
        "severity": "Critical",
        "message": "System under severe resource pressure"
      }
    ]
  }
}
```

---

## 6. Architecture Considerations

### 6.1 Deployment Models

1. **Standalone Service**
   - Runs as Windows Service on each monitored server
   - Self-contained with local configuration
   - Exports snapshots to network share

2. **Agent-Based with Central Collector**
   - Lightweight agents on monitored servers
   - Central aggregation service
   - Centralized configuration management

3. **Scheduled Task Model**
   - Runs as scheduled PowerShell script
   - Suitable for less critical monitoring
   - Lower resource overhead

### 6.2 Performance Requirements

- CPU Usage: < 2% average, < 5% peak
- Memory: < 100 MB baseline, < 200 MB with full history
- Disk I/O: Minimal (only during snapshot exports)
- Network: < 1 KB/s for network checks

### 6.3 Error Handling

- Graceful degradation if individual collectors fail
- Automatic retry with exponential backoff
- Comprehensive error logging
- Self-healing capabilities (restart collectors)

### 6.4 Security Considerations

- Run with minimum required privileges
- Encrypt sensitive configuration data (credentials)
- Secure storage of snapshots
- Audit trail of configuration changes

---

## 7. Implementation Phases

### Phase 1: Core Framework
- Configuration loading and validation
- Basic data collection framework
- Snapshot export functionality
- File-based alerting

### Phase 2: Essential Monitoring
- Processor, Memory, Disk monitoring
- Network connectivity checks
- Windows uptime tracking
- Event log monitoring

### Phase 3: Advanced Monitoring
- Windows Update tracking
- Service monitoring
- Process monitoring
- Database connectivity

### Phase 4: Extended Features
- Multiple alert channels
- Alert throttling and suppression
- Custom alert conditions
- Performance optimizations

### Phase 5: Enterprise Features
- Central aggregation
- Dashboard/reporting
- Historical trending
- Predictive analytics

---

## 8. File Structure

```
ServerMonitor/
├── ServerMonitor.ps1 (or .exe)
├── Config/
│   ├── default-config.json
│   ├── production-config.json
│   └── README.md
├── Modules/
│   ├── ConfigurationManager.psm1
│   ├── ProcessorMonitor.psm1
│   ├── MemoryMonitor.psm1
│   ├── DiskMonitor.psm1
│   ├── NetworkMonitor.psm1
│   ├── EventLogMonitor.psm1
│   ├── UpdateMonitor.psm1
│   ├── SnapshotExporter.psm1
│   └── AlertManager.psm1
├── Data/
│   ├── Snapshots/
│   └── History/
├── Logs/
├── Tests/
│   └── Test-SurveillanceTool.ps1
├── Install/
│   ├── Install-Service.ps1
│   └── Uninstall-Service.ps1
├── _deploy.ps1
└── README.md
```

---

## 9. Testing Requirements

- Unit tests for each monitoring module
- Integration tests for end-to-end scenarios
- Performance tests under load
- Failover and recovery tests
- Configuration validation tests

---

## 10. Documentation Requirements

- Installation guide
- Configuration reference
- Troubleshooting guide
- API reference (if applicable)
- Architecture documentation

---

*End of Specification*

