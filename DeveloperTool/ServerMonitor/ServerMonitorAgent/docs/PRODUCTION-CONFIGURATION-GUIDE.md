# Server Surveillance Tool - Production Configuration Guide

**Created:** 2025-11-26  
**Version:** 1.0  
**Configuration File:** `src/ServerMonitor/appsettings.Production.json`

---

## Overview

This guide documents the production-ready configuration for the Server Surveillance Tool, with sensible thresholds and intervals designed for real-world server monitoring.

### Configuration Philosophy

The production configuration balances:
- ✅ **Early detection** of genuine issues
- ✅ **Minimal false positives** (alert fatigue prevention)
- ✅ **Resource efficiency** (appropriate polling intervals)
- ✅ **Actionable alerts** (severity-based throttling)

---

## Key Differences: Test vs Production

| Setting | Test Config | Production Config | Reason |
|---------|-------------|-------------------|--------|
| **CPU Warning** | 1% | 80% | Test triggers immediately; Production for real issues |
| **CPU Sustained** | 5 seconds | 180 seconds (3 min) | Avoid transient spike alerts |
| **Memory Warning** | 1% | 85% | Test triggers immediately; Production for capacity planning |
| **Memory Sustained** | 5 seconds | 300 seconds (5 min) | Distinguish temporary vs persistent issues |
| **Disk Space Warning** | 1% | 85% | Realistic threshold for action |
| **Disk Space Polling** | 10 seconds | 600 seconds (10 min) | Disk space changes slowly |
| **CPU Polling** | 5 seconds | 30 seconds | Balance between responsiveness and overhead |
| **Memory Polling** | 10 seconds | 60 seconds | Memory changes gradually |
| **Network Polling** | 30 seconds | 120 seconds (2 min) | Network connectivity stable |
| **Event Log Polling** | 60 seconds | 120 seconds (2 min) | Events don't need instant detection |
| **Snapshots** | Every 15 min | Every 6 hours | Reduce storage, still capture trends |
| **SMS Alerts** | Enabled for Warning | **Disabled** (Critical only) | Reserve SMS for true emergencies |

---

## Production Configuration Sections

### 1. General Settings

```json
{
  "General": {
    "ServerName": "",
    "MonitoringEnabled": true,
    "DataRetentionHours": 720
  }
}
```

**Notes:**
- **ServerName:** Leave empty to auto-detect from `Environment.MachineName`
- **DataRetentionHours:** 30 days (720 hours) for trend analysis and compliance

---

### 2. Runtime Settings

```json
{
  "Runtime": {
    "AutoShutdownTime": null,
    "MaxRuntimeHours": null,
    "TestTimeoutSeconds": null
  }
}
```

**Production Values:**
- All set to `null` for **continuous operation**
- `TestTimeoutSeconds` only used during testing (omit or set `null`)

---

### 3. Processor Monitoring

```json
{
  "ProcessorMonitoring": {
    "Enabled": true,
    "PollingIntervalSeconds": 30,
    "Thresholds": {
      "WarningPercent": 80,
      "CriticalPercent": 95,
      "SustainedDurationSeconds": 180
    },
    "PerCoreMonitoring": true,
    "TrackTopProcesses": 5
  }
}
```

**Rationale:**
- **80% Warning:** Allows time for investigation before critical
- **95% Critical:** Server is at capacity, immediate action needed
- **180 seconds sustained:** Filters out brief spikes (compiles, backups)
- **30 second polling:** Responsive without excessive overhead
- **Per-core monitoring:** Identifies single-threaded bottlenecks

**Alert Scenarios:**
- ✅ Sustained high CPU from runaway process
- ✅ All cores consistently high (capacity issue)
- ❌ Brief compile spike (< 3 minutes)
- ❌ Single core at 100% momentarily

---

### 4. Memory Monitoring

```json
{
  "MemoryMonitoring": {
    "Enabled": true,
    "PollingIntervalSeconds": 60,
    "Thresholds": {
      "WarningPercent": 85,
      "CriticalPercent": 95,
      "SustainedDurationSeconds": 300
    },
    "TrackTopProcesses": 5
  }
}
```

**Rationale:**
- **85% Warning:** Plan for capacity upgrade
- **95% Critical:** Risk of paging/performance degradation
- **300 seconds sustained:** Memory leaks persist, cache growth is temporary
- **60 second polling:** Memory changes gradually

**Alert Scenarios:**
- ✅ Memory leak over 5+ minutes
- ✅ Persistent high usage from application
- ❌ SQL Server cache warming (temporary)
- ❌ Brief allocation spike

---

### 5. Virtual Memory Monitoring

```json
{
  "VirtualMemoryMonitoring": {
    "Enabled": true,
    "PollingIntervalSeconds": 60,
    "Thresholds": {
      "WarningPercent": 80,
      "CriticalPercent": 90,
      "SustainedDurationSeconds": 300,
      "ExcessivePagingRate": 1000
    }
  }
}
```

**Rationale:**
- **80% page file:** System under memory pressure
- **1000 pages/sec:** Excessive disk I/O from paging
- High paging = severe performance impact

---

### 6. Disk Space Monitoring

```json
{
  "DiskSpaceMonitoring": {
    "Enabled": true,
    "PollingIntervalSeconds": 600,
    "DisksToMonitor": [ "C:", "D:" ],
    "Thresholds": {
      "WarningPercent": 85,
      "CriticalPercent": 95,
      "MinimumFreeSpaceGB": 20
    }
  }
}
```

**Rationale:**
- **85% Warning:** Time to plan cleanup/expansion
- **95% Critical:** Immediate action required (logs, temp files)
- **20 GB minimum:** Ensure OS has working space
- **10 minute polling:** Disk space changes slowly

**Alert Scenarios:**
- ✅ Log files filling up over days
- ✅ Database growth exceeding capacity
- ❌ Brief temp file creation

---

### 7. Network Monitoring

```json
{
  "NetworkMonitoring": {
    "Enabled": true,
    "PollingIntervalSeconds": 120,
    "BaselineHosts": [
      {
        "Hostname": "google.com",
        "Description": "Internet connectivity check",
        "CheckPing": true,
        "CheckDns": true,
        "PortsToCheck": [ 443 ],
        "Thresholds": {
          "MaxPingMs": 100,
          "MaxPacketLossPercent": 5,
          "ConsecutiveFailuresBeforeAlert": 3
        }
      },
      {
        "Hostname": "DEDGE.fk.no",
        "Description": "Internal domain connectivity",
        "CheckPing": true,
        "CheckDns": true,
        "PortsToCheck": [],
        "Thresholds": {
          "MaxPingMs": 50,
          "MaxPacketLossPercent": 2,
          "ConsecutiveFailuresBeforeAlert": 3
        }
      }
    ]
  }
}
```

**Rationale:**
- **2 minute polling:** Balance between detection speed and overhead
- **3 consecutive failures:** Avoid alerts from brief hiccups
- **Internal < 50ms, External < 100ms:** Reasonable latency thresholds
- **HTTPS port check:** Verify internet access, not just DNS/ping

**Customization:**
- Add critical internal services (SQL Server, file servers)
- Add external SaaS dependencies
- Adjust ping thresholds based on WAN links

---

### 8. Windows Update Monitoring

```json
{
  "WindowsUpdateMonitoring": {
    "Enabled": true,
    "PollingIntervalSeconds": 3600,
    "Thresholds": {
      "MaxPendingSecurityUpdates": 0,
      "MaxPendingCriticalUpdates": 0,
      "MaxDaysSinceLastUpdate": 30
    },
    "Alerts": {
      "AlertOnPendingSecurityUpdates": true,
      "AlertOnFailedInstallations": true
    }
  }
}
```

**Rationale:**
- **Hourly polling:** Updates don't need real-time monitoring
- **Zero pending security/critical:** Enforce patching discipline
- **30 days since last update:** Ensure regular maintenance

---

### 9. Event Log Monitoring

**Key Events Monitored:**

| Event ID | Source | Description | Max Occurrences | Time Window |
|----------|--------|-------------|-----------------|-------------|
| 7001 | Service Control Manager | Service dependency failure | 3 | 60 min |
| 7022 | Service Control Manager | Service hung on starting | 1 | 30 min |
| 7023 | Service Control Manager | Service terminated with error | 3 | 60 min |
| 7031 | Service Control Manager | Service crashed unexpectedly | 2 | 60 min |
| 1000 | Application Error | Application crash | 5 | 60 min |
| 41 | Kernel-Power | Unexpected shutdown | 1 | 60 min |
| 6008 | EventLog | Unexpected system shutdown | 1 | 60 min |

**Rationale:**
- **2 minute polling:** Events are logged retroactively, no rush
- **Conservative occurrence thresholds:** Distinguish fluke from pattern
- **60 minute windows:** Detect chronic issues, not one-off glitches

**Customization:**
- Add application-specific error event IDs
- Adjust MaxOccurrences for noisy apps
- Add database/service-specific events

---

### 10. Scheduled Task Monitoring

```json
{
  "ScheduledTaskMonitoring": {
    "Enabled": true,
    "PollingIntervalSeconds": 600,
    "TasksToMonitor": [
      {
        "TaskPath": "\\Microsoft\\Windows\\Backup\\ConfigNotification",
        "Description": "Windows Backup Configuration",
        "AlertOnFailure": true,
        "AlertOnMissedRun": true,
        "MaxMinutesSinceLastRun": 10080,
        "AlertIfDisabled": true
      }
    ]
  }
}
```

**Rationale:**
- **10 minute polling:** Tasks run on schedules, not real-time
- **10080 minutes (7 days):** Weekly task example

**Customization:**
- Add business-critical scheduled tasks:
  - Backups
  - Data syncs
  - Report generation
  - Maintenance jobs
- Adjust `MaxMinutesSinceLastRun` per task schedule (daily = 1440, weekly = 10080)

---

### 11. Snapshot Exports

```json
{
  "ExportSettings": {
    "Enabled": true,
    "OutputDirectory": "C:\\opt\\data\\ServerSurveillance\\Snapshots",
    "FileNamePattern": "{ServerName}_{Timestamp:yyyyMMdd_HHmmss}.json",
    "ExportIntervals": {
      "ScheduleMinutes": [ 0, 360, 720, 1080 ],
      "OnAlertTrigger": true,
      "OnDemand": true
    },
    "Retention": {
      "MaxAgeHours": 720,
      "MaxFileCount": 1000,
      "CompressionEnabled": true
    }
  }
}
```

**Schedule:** 4 times per day (00:00, 06:00, 12:00, 18:00)

**Rationale:**
- **6-hour intervals:** Capture daily trends without excessive storage
- **OnAlertTrigger:** Document system state during incidents
- **30-day retention:** Sufficient for trend analysis and audits
- **Compression:** Reduce storage footprint

---

### 12. Alerting Channels

#### Email (Enabled by Default)

```json
{
  "Type": "Email",
  "Enabled": true,
  "MinSeverity": "Warning",
  "Settings": {
    "SmtpServer": "smtp.DEDGE.fk.no",
    "SmtpPort": 25,
    "From": "ServerMonitor@{ComputerName}.fk.DEDGE.no",
    "To": "serveradmins@Dedge.no",
    "EnableSsl": false
  }
}
```

**Configuration:**
- Use distribution list for `To` field
- Dynamic `From` address includes server name for easy identification
- Internal SMTP relay, no SSL needed

#### SMS (Disabled by Default - Enable for Critical Only)

```json
{
  "Type": "SMS",
  "Enabled": false,
  "MinSeverity": "Critical",
  "Settings": {
    "ApiUrl": "https://sms.pswin.com/SOAP/SMS.asmx",
    "Client": "FK",
    "Password": "",
    "Sender": "Dedge",
    "Receivers": "",
    "DefaultCountryCode": "+47"
  }
}
```

**Production Recommendations:**
- **Enable ONLY for Critical alerts** to avoid SMS fatigue
- **Add on-call phone numbers** to `Receivers` (comma-separated)
- **Fill in API credentials** from secure vault
- **Test thoroughly** before production deployment

#### WKMonitor (Enabled for Integration)

```json
{
  "Type": "WKMonitor",
  "Enabled": true,
  "MinSeverity": "Warning",
  "Settings": {
    "ProductionPath": "\\\\DEDGE.fk.no\\erpprog\\cobnt\\monitor\\",
    "TestPath": "\\\\DEDGE.fk.no\\erpprog\\cobtst\\monitor\\",
    "ProgramName": "ServerSurveillance",
    "ForceAll": false
  }
}
```

**Auto-detection:**
- Production servers → `ProductionPath`
- Test servers → `TestPath`

---

### 13. Throttling Configuration

```json
{
  "Throttling": {
    "Enabled": true,
    "MaxAlertsPerHour": 50,
    "WarningSuppressionMinutes": 60,
    "ErrorSuppressionMinutes": 15,
    "InformationalSuppressionMinutes": 120
  }
}
```

**Severity-Based Suppression:**

| Severity | Interval | Rationale |
|----------|----------|-----------|
| **Warning** | 60 minutes | Issues need attention but not urgent; hourly notification sufficient |
| **Error/Critical** | 15 minutes | Urgent issues; re-alert every 15 min until resolved |
| **Informational** | 120 minutes | Low priority; avoid noise |

**Example Flow:**

1. **CPU Warning detected at 10:00** → Alert sent to all channels
2. **Still high at 10:05** → Suppressed (within 60-min window)
3. **Still high at 11:00** → Alert sent again
4. **Escalates to Critical at 11:10** → Alert sent immediately (15-min interval for Critical)
5. **Still critical at 11:25** → Alert sent again
6. **Resolved at 11:30** → No more alerts

---

## Deployment Checklist

### Before Production Deployment

- [ ] **1. Review all thresholds** for your environment
- [ ] **2. Customize monitored scheduled tasks** with business-critical tasks
- [ ] **3. Add network hosts** for critical dependencies
- [ ] **4. Configure Email recipients** (use distribution list)
- [ ] **5. Test SMS configuration** (if enabling SMS)
- [ ] **6. Verify WKMonitor paths** are accessible
- [ ] **7. Create output directories:**
  - `C:\opt\data\ServerSurveillance\Snapshots`
  - `C:\opt\data\ServerSurveillance\Alerts`
- [ ] **8. Test in staging** environment first
- [ ] **9. Document custom event IDs** for your applications
- [ ] **10. Set up log rotation** for alert files

### Service Installation

```powershell
# Install as Windows Service
New-Service -Name "ServerMonitor" `
            -BinaryPathName "C:\opt\FkWinServices\ServerMonitor\ServerMonitor.exe" `
            -DisplayName "Server Surveillance Tool" `
            -Description "Monitors server health metrics and generates alerts" `
            -StartupType Automatic

# Start the service
Start-Service -Name "ServerMonitor"

# Verify status
Get-Service -Name "ServerMonitor"
```

### Post-Deployment Verification

1. **Check Event Log** for startup messages
2. **Verify snapshot files** being created
3. **Test alert delivery** with temporary low threshold
4. **Monitor first 24 hours** for false positives
5. **Adjust thresholds** as needed based on normal server behavior

---

## Environment-Specific Customization

### High-Load Servers (SQL, Web)

```json
{
  "ProcessorMonitoring": {
    "Thresholds": {
      "WarningPercent": 85,
      "CriticalPercent": 98,
      "SustainedDurationSeconds": 300
    }
  },
  "MemoryMonitoring": {
    "Thresholds": {
      "WarningPercent": 90,
      "CriticalPercent": 97
    }
  }
}
```

**Rationale:** These servers normally run hot; adjust thresholds higher

### Low-Utilization Servers (Domain Controllers, File Servers)

```json
{
  "ProcessorMonitoring": {
    "Thresholds": {
      "WarningPercent": 60,
      "CriticalPercent": 80
    }
  }
}
```

**Rationale:** These servers should be idle; lower thresholds catch anomalies

### Development/Test Servers

```json
{
  "Alerting": {
    "Channels": [
      {
        "Type": "Email",
        "Settings": {
          "To": "dev-team@company.com"
        }
      }
    ]
  }
}
```

**Rationale:** Route test server alerts to dev team, not operations

---

## Troubleshooting Production Issues

### Too Many Alerts (Alert Fatigue)

**Solutions:**
1. **Increase thresholds** for noisy metrics
2. **Increase sustained duration** to filter transient spikes
3. **Adjust throttling intervals** (e.g., Warning = 120 min instead of 60)
4. **Disable non-critical monitors** temporarily
5. **Review MaxOccurrences** for event log monitoring

### Missing Alerts (Under-alerting)

**Solutions:**
1. **Decrease thresholds** if issues go undetected
2. **Decrease sustained duration** for faster detection
3. **Verify alert channels** are enabled and configured
4. **Check service is running** (`Get-Service ServerMonitor`)
5. **Review logs** for errors in alert delivery

### Performance Impact

**Solutions:**
1. **Increase polling intervals** (especially for CPU/Memory)
2. **Disable Disk I/O monitoring** (can be expensive)
3. **Reduce snapshot frequency** (every 12 hours instead of 6)
4. **Disable per-core monitoring** for many-core servers

---

## Configuration Files

### Available Configurations

| File | Purpose | Use Case |
|------|---------|----------|
| `appsettings.json` | **Base configuration** | Development, testing |
| `appsettings.Production.json` | **Production-ready** | Production servers (documented here) |
| `appsettings.LowLimitsTest.json` | **Alert testing** | Verify alert channels work |

### Configuration Loading Order

1. `appsettings.json` (base)
2. `appsettings.{Environment}.json` (overrides)
3. Environment variables (final overrides)

**Example:**
```powershell
# Set environment
$env:ASPNETCORE_ENVIRONMENT = "Production"

# Service will load:
# 1. appsettings.json
# 2. appsettings.Production.json (merges/overrides)
```

---

## Best Practices

### 1. Start Conservative

- Begin with **higher thresholds** and **longer durations**
- Monitor for 1-2 weeks
- Adjust based on false positive/negative rates

### 2. Document Customizations

- Keep a change log of threshold adjustments
- Note reasons for deviations from defaults
- Share learnings across teams

### 3. Test Before Deploying

- Use `appsettings.LowLimitsTest.json` to verify alert delivery
- Test each channel (Email, SMS, WKMonitor)
- Verify on-call phone numbers receive SMS

### 4. Monitor the Monitor

- Ensure the service itself is monitored (e.g., via SCOM, Nagios)
- Set up alert if service stops unexpectedly
- Review alert logs periodically for patterns

### 5. Review Quarterly

- Reassess thresholds as server usage patterns change
- Add new critical tasks to scheduled task monitoring
- Remove outdated event IDs
- Update contact information

---

## Quick Reference

### Recommended Thresholds Summary

| Metric | Warning | Critical | Sustained | Polling |
|--------|---------|----------|-----------|---------|
| **CPU** | 80% | 95% | 3 min | 30 sec |
| **Memory** | 85% | 95% | 5 min | 60 sec |
| **Page File** | 80% | 90% | 5 min | 60 sec |
| **Disk Space** | 85% | 95% | N/A | 10 min |
| **Network** | 3 failures | N/A | N/A | 2 min |
| **Events** | Varies | Varies | N/A | 2 min |

### Alerting Strategy

- **Email:** All Warning+ alerts → serveradmins@company.com
- **SMS:** Critical only → On-call phone numbers
- **WKMonitor:** All Warning+ alerts → Monitoring system
- **EventLog:** All Warning+ alerts → Windows Application Log
- **File:** All Warning+ alerts → Persistent log file

---

**Document Version:** 1.0  
**Last Updated:** 2025-11-26  
**Configuration File:** `src/ServerMonitor/appsettings.Production.json`  
**Status:** ✅ Production-ready with sensible defaults

