# Configuration Examples and Suggestions

## Common Event IDs to Monitor

### Security Events

| Event ID | Description | Recommended Threshold |
|----------|-------------|----------------------|
| **4625** | Failed login attempt | 10 per 5 minutes |
| **4740** | Account locked out | 0 (immediate alert) |
| **4728** | User added to privileged group | 0 (immediate alert) |
| **4732** | User added to local administrators | 0 (immediate alert) |
| **4719** | System audit policy changed | 0 (immediate alert) |
| **4964** | Special groups assigned to new logon | 1 per day |

### System Events

| Event ID | Description | Recommended Threshold |
|----------|-------------|----------------------|
| **6008** | Unexpected shutdown | 0 (immediate alert) |
| **41** | Kernel-Power (dirty shutdown) | 0 (immediate alert) |
| **1074** | System shutdown initiated | 5 per day |
| **1076** | Shutdown reason logged | 5 per day |
| **1001** | Windows Error Reporting | 3 per 15 minutes |

### Service Events

| Event ID | Description | Recommended Threshold |
|----------|-------------|----------------------|
| **7001** | Service dependency failure | 0 (immediate alert) |
| **7022** | Service hung on starting | 0 (immediate alert) |
| **7023** | Service terminated with error | 0 (immediate alert) |
| **7024** | Service-specific error | 0 (immediate alert) |
| **7026** | Driver failed to load | 0 (immediate alert) |
| **7031** | Service crashed | 0 (immediate alert) |
| **7034** | Service terminated unexpectedly | 0 (immediate alert) |

### Task Scheduler Events

| Event ID | Description | Recommended Threshold |
|----------|-------------|----------------------|
| **103** | Task failed to start | 0 (immediate alert) |
| **201** | Task completed with errors | 0 (immediate alert) |
| **411** | Task start failed | 0 (immediate alert) |

### Disk Events

| Event ID | Description | Recommended Threshold |
|----------|-------------|----------------------|
| **15** | Bad block detected | 0 (immediate alert) |
| **153** | I/O error on disk | 3 per hour |
| **7** | Disk error | 5 per day |

### DCOM/RPC Events

| Event ID | Description | Recommended Threshold |
|----------|-------------|----------------------|
| **10010** | DCOM server did not register | 10 per hour |
| **10016** | DCOM permission error | 20 per hour |

---

## Network Monitoring Examples

### Internal Database Server
```json
{
  "Hostname": "p-no1fkmprd-db",
  "Description": "Production Database Server",
  "CheckPing": true,
  "CheckDns": true,
  "PortsToCheck": [1433, 445],
  "Thresholds": {
    "MaxPingMs": 10,
    "MaxPacketLossPercent": 0,
    "ConsecutiveFailuresBeforeAlert": 2
  }
}
```

### External Gateway
```json
{
  "Hostname": "8.8.8.8",
  "Description": "Internet Connectivity (Google DNS)",
  "CheckPing": true,
  "CheckDns": false,
  "PortsToCheck": [],
  "Thresholds": {
    "MaxPingMs": 100,
    "MaxPacketLossPercent": 5,
    "ConsecutiveFailuresBeforeAlert": 5
  }
}
```

### Web Server
```json
{
  "Hostname": "web.company.com",
  "Description": "Public Web Server",
  "CheckPing": true,
  "CheckDns": true,
  "PortsToCheck": [80, 443],
  "Thresholds": {
    "MaxPingMs": 50,
    "MaxPacketLossPercent": 2,
    "ConsecutiveFailuresBeforeAlert": 3
  }
}
```

---

## Scheduled Task Monitoring Examples

### Windows Backup Task
```json
{
  "TaskPath": "\\Microsoft\\Windows\\Backup\\Windows Backup Monitor",
  "Description": "Windows Server Backup",
  "AlertOnFailure": true,
  "AlertOnMissedRun": true,
  "MaxMinutesSinceLastRun": 1440,
  "AlertIfDisabled": true
}
```

### Database Backup Task
```json
{
  "TaskPath": "\\CustomTasks\\DatabaseBackup",
  "Description": "SQL Server Backup",
  "AlertOnFailure": true,
  "AlertOnMissedRun": true,
  "MaxMinutesSinceLastRun": 1440,
  "AlertIfDisabled": true
}
```

### Maintenance Task (Weekly)
```json
{
  "TaskPath": "\\CustomTasks\\WeeklyMaintenance",
  "Description": "Weekly System Maintenance",
  "AlertOnFailure": true,
  "AlertOnMissedRun": true,
  "MaxMinutesSinceLastRun": 10080,
  "AlertIfDisabled": false
}
```

---

## Environment-Specific Configuration

### Development Environment
Lower thresholds, more verbose logging:
```json
{
  "ProcessorMonitoring": {
    "Thresholds": {
      "WarningPercent": 90,
      "CriticalPercent": 98
    }
  },
  "DiskSpaceMonitoring": {
    "Thresholds": {
      "WarningPercent": 90,
      "CriticalPercent": 98
    }
  }
}
```

### Production Environment
Tighter thresholds, immediate alerting:
```json
{
  "ProcessorMonitoring": {
    "Thresholds": {
      "WarningPercent": 70,
      "CriticalPercent": 90,
      "SustainedDurationSeconds": 180
    }
  },
  "Alerting": {
    "Channels": [
      {
        "Type": "Email",
        "Enabled": true,
        "MinSeverity": "Warning"
      }
    ]
  }
}
```

---

## Complete Configuration Template

See `appsettings.json` for the complete configuration template with all available options.

### Quick Customization Checklist

- [ ] Set `General.ServerName` to actual server name
- [ ] Adjust `ProcessorMonitoring.Thresholds` for your workload
- [ ] Configure `NetworkMonitoring.BaselineHosts` for your environment
- [ ] Add `ScheduledTaskMonitoring.TasksToMonitor` for critical tasks
- [ ] Review `EventMonitoring.EventsToMonitor` and enable relevant events
- [ ] Configure email settings in `Alerting.Channels` if needed
- [ ] Adjust `ExportSettings.OutputDirectory` path if needed
- [ ] Set `Retention.MaxAgeHours` based on disk space

---

## Tips

1. **Start Conservative**: Begin with higher thresholds and adjust down based on actual patterns
2. **Test Event IDs**: Use Event Viewer to verify event IDs exist on your systems
3. **Monitor Throttling**: If you hit alert limits, tune thresholds or increase `MaxAlertsPerHour`
4. **Baseline Network Hosts**: Monitor at least one internal and one external host
5. **Critical Tasks Only**: Only monitor scheduled tasks that are truly critical
6. **Use Descriptions**: Good descriptions make alerts much more actionable

