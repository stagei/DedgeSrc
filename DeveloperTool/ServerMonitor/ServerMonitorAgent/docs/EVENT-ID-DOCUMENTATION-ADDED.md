# Event ID Documentation Links - Feature Added ✅

**Date:** 2025-11-26  
**Enhancement:** Added documentation URLs to all Event ID configurations for easier troubleshooting

---

## What Was Added

### 1. Configuration Enhancement ✅

**Added Property:** `DocumentationUrl` (optional string)

All 23 monitored Event IDs now include direct links to official Microsoft or EventID.net documentation.

### 2. Alert Enhancement ✅

Alerts now automatically include the documentation link in the `Details` field, making it easy to:
- Understand what the event means
- Find resolution steps
- Learn about the root cause

---

## Example Alert Output

### Before:
```
[2025-11-26 14:10:45] [CRITICAL] [EventLog] Event 4625 occurred 15 times
Details: Security - Failed login attempt: Occurred 15 times in the last 5 minutes (threshold: 10)
```

### After:
```
[2025-11-26 14:10:45] [CRITICAL] [EventLog] Event 4625 occurred 15 times
Details: Security - Failed login attempt: Occurred 15 times in the last 5 minutes (threshold: 10)
Documentation: https://learn.microsoft.com/en-us/windows/security/threat-protection/auditing/event-4625
```

---

## Complete Event ID Documentation Links

### Security Events

| Event ID | Description | Documentation |
|----------|-------------|---------------|
| **4625** | Failed login attempt | https://learn.microsoft.com/en-us/windows/security/threat-protection/auditing/event-4625 |
| **4740** | Account locked out | https://learn.microsoft.com/en-us/windows/security/threat-protection/auditing/event-4740 |

### Application Events

| Event ID | Description | Documentation |
|----------|-------------|---------------|
| **1000** | Application crash (WER) | https://learn.microsoft.com/en-us/windows/win32/wer/windows-error-reporting |
| **1001** | Application error/crash | https://learn.microsoft.com/en-us/windows/win32/wer/windows-error-reporting |

### System Events

| Event ID | Description | Documentation |
|----------|-------------|---------------|
| **6008** | Unexpected shutdown/dirty boot | https://eventid.net/display-eventid-6008-source-EventLog-eventno-12890-phase-1.htm |
| **41** | Kernel-Power (unexpected reboot) | https://learn.microsoft.com/en-us/windows/client-management/troubleshoot-event-id-41-restart |
| **1074** | System shutdown/restart initiated | https://eventid.net/display-eventid-1074-source-User32-eventno-13016-phase-1.htm |
| **1076** | Shutdown reason logged | https://eventid.net/display-eventid-1076-source-User32-eventno-13018-phase-1.htm |

### Task Scheduler Events

| Event ID | Description | Documentation |
|----------|-------------|---------------|
| **103** | Task failed to start | https://learn.microsoft.com/en-us/windows/win32/taskschd/task-scheduler-error-and-success-constants |
| **201** | Task completed with errors | https://learn.microsoft.com/en-us/windows/win32/taskschd/task-scheduler-error-and-success-constants |
| **411** | Task start failed | https://learn.microsoft.com/en-us/windows/win32/taskschd/task-scheduler-error-and-success-constants |

### DCOM Events

| Event ID | Description | Documentation |
|----------|-------------|---------------|
| **10010** | Server did not register with DCOM | https://learn.microsoft.com/en-us/troubleshoot/windows-client/application-management/event-10010-logged-application-log |

### Service Control Manager Events

| Event ID | Description | Documentation |
|----------|-------------|---------------|
| **7001** | Service dependency failure | https://eventid.net/display-eventid-7001-source-Service%20Control%20Manager-eventno-8605-phase-1.htm |
| **7022** | Service hung on starting | https://eventid.net/display-eventid-7022-source-Service%20Control%20Manager-eventno-8626-phase-1.htm |
| **7023** | Service terminated with error | https://eventid.net/display-eventid-7023-source-Service%20Control%20Manager-eventno-8627-phase-1.htm |
| **7024** | Service-specific error | https://eventid.net/display-eventid-7024-source-Service%20Control%20Manager-eventno-8628-phase-1.htm |
| **7026** | Driver failed to load | https://eventid.net/display-eventid-7026-source-Service%20Control%20Manager-eventno-8630-phase-1.htm |
| **7031** | Service crashed unexpectedly | https://eventid.net/display-eventid-7031-source-Service%20Control%20Manager-eventno-8635-phase-1.htm |
| **7034** | Service terminated unexpectedly | https://eventid.net/display-eventid-7034-source-Service%20Control%20Manager-eventno-8638-phase-1.htm |

### Disk Events

| Event ID | Description | Documentation |
|----------|-------------|---------------|
| **15** | Bad block detected | https://eventid.net/display-eventid-15-source-disk-eventno-323-phase-1.htm |
| **153** | IO error on disk | https://eventid.net/display-eventid-153-source-disk-eventno-461-phase-1.htm |

### Network Events

| Event ID | Description | Documentation |
|----------|-------------|---------------|
| **2019** | Duplicate name on network | https://eventid.net/display-eventid-2019-source-srv-eventno-6623-phase-1.htm |

### Security Center Events

| Event ID | Description | Documentation |
|----------|-------------|---------------|
| **1500** | Antivirus/Firewall/Updates disabled | https://learn.microsoft.com/en-us/windows/security/operating-system-security/system-security/windows-defender-security-center/wdsc-customize-contact-information |

---

## Configuration Example

```json
{
  "EventId": 4625,
  "Description": "Security - Failed login attempt",
  "Source": "Microsoft-Windows-Security-Auditing",
  "LogName": "Security",
  "Level": "Warning",
  "MaxOccurrences": 10,
  "TimeWindowMinutes": 5,
  "DocumentationUrl": "https://learn.microsoft.com/en-us/windows/security/threat-protection/auditing/event-4625"
}
```

---

## Benefits

### For Operations Teams:

1. **Faster Incident Response**
   - Click link directly from alert
   - No need to search for documentation
   - Understand event context immediately

2. **Better Root Cause Analysis**
   - Official Microsoft documentation
   - Common causes listed
   - Resolution steps provided

3. **Training & Knowledge Transfer**
   - New team members can learn on the fly
   - Links serve as documentation
   - Consistent information source

4. **Reduced MTTR (Mean Time To Resolution)**
   - Immediate access to troubleshooting steps
   - No context switching to search engines
   - Authoritative information source

---

## Alert Channels Showing Links

### 1. File Log Alert
```
[2025-11-26 15:30:00] [CRITICAL] [EventLog] Event 7031 occurred 1 times | Details: Services - Service crashed unexpectedly: Occurred 1 times in the last 60 minutes (threshold: 0)
Documentation: https://eventid.net/display-eventid-7031-source-Service%20Control%20Manager-eventno-8635-phase-1.htm
```

### 2. Email Alert (HTML)
```html
<tr><td><strong>Details:</strong></td>
    <td>Services - Service crashed unexpectedly: Occurred 1 times in the last 60 minutes (threshold: 0)
    <br>Documentation: <a href="https://eventid.net/...">https://eventid.net/...</a>
    </td>
</tr>
```

### 3. Windows Event Log
The documentation URL is included in the event message details.

---

## Documentation Sources

### Primary Sources:

1. **Microsoft Learn** (learn.microsoft.com)
   - Official Microsoft documentation
   - Security auditing events
   - Windows troubleshooting guides
   - Best practices

2. **EventID.net**
   - Community-driven event database
   - User experiences and solutions
   - Cross-referenced with Microsoft docs
   - Historical event information

---

## Adding New Event IDs

When adding a new event to monitor, include the `DocumentationUrl`:

```json
{
  "EventId": 1234,
  "Description": "Your event description",
  "Source": "Event Source",
  "LogName": "System",
  "Level": "Error",
  "MaxOccurrences": 0,
  "TimeWindowMinutes": 60,
  "DocumentationUrl": "https://learn.microsoft.com/en-us/path/to/event-1234"
}
```

**Finding Documentation:**
1. Search: `site:learn.microsoft.com event id {number}`
2. Or: `https://eventid.net/display-eventid-{number}-source-{source}`
3. Or: General search: `windows event id {number} {source}`

---

## Files Modified

1. ✅ `src/ServerMonitor.Core/Configuration/SurveillanceConfiguration.cs`
   - Added `DocumentationUrl` property to `EventToMonitor` class

2. ✅ `src/ServerMonitor.Core/Monitors/EventLogMonitor.cs`
   - Updated alert details to include documentation URL

3. ✅ `src/ServerMonitor/appsettings.json`
   - Added documentation URLs to all 23 event configurations

---

## Testing

After configuration reload (no restart needed!), check alerts:

```powershell
# View latest alerts
Get-Content "C:\opt\data\ServerMonitor\ServerMonitor_Alerts_$(Get-Date -Format 'yyyyMMdd').log" -Tail 20

# Look for "Documentation:" line in alert details
```

---

## Summary

✅ **23 Event IDs** documented  
✅ **Automatic link inclusion** in all alerts  
✅ **Zero code changes** to use (just configuration)  
✅ **Backward compatible** (optional field)  
✅ **Hot-reload enabled** (update config without restart)  

**Troubleshooting is now one click away!** 🔗

---

*Feature added: 2025-11-26*

