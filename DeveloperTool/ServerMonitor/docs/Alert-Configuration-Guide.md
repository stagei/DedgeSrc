# Alert Configuration Guide

This guide explains how to configure alert thresholds and accumulation behavior in ServerMonitor.

## Overview

Every alert in ServerMonitor can be configured with two key parameters:

| Parameter | Description |
|-----------|-------------|
| `MaxOccurrences` | Number of times a condition must be detected before an alert is triggered |
| `TimeWindowMinutes` | The sliding time window for counting occurrences AND the cooldown after alerting |

These parameters work together to control:
- **When** an alert is triggered
- **How often** alerts can repeat
- **How much** accumulation is needed before alerting

---

## Quick Reference

| MaxOccurrences | TimeWindowMinutes | Behavior | Use Case |
|----------------|-------------------|----------|----------|
| 0 | 0 | Alert on **every** occurrence | Critical events that must never be missed |
| 0 | 60 | Alert **immediately**, then 1-hour cooldown | Important but don't spam |
| 0 | 1440 | Alert **immediately**, then 24-hour cooldown | Daily notifications |
| 5 | 10 | Need **5+ occurrences** in 10 minutes | Sustained conditions |
| 100 | 60 | Need **100+ occurrences** in 60 minutes | High-frequency events |

---

## Understanding the Parameters

### MaxOccurrences

**What it means:** How many times must the condition be detected before generating an alert?

| Value | Meaning |
|-------|---------|
| 0 | Alert on the **first** occurrence (immediate) |
| 1 | Alert after **2** occurrences |
| 5 | Alert after **6** occurrences |
| 100 | Alert after **101** occurrences |

**Note:** The alert triggers when the count **exceeds** MaxOccurrences (i.e., count > MaxOccurrences).

### TimeWindowMinutes

**What it means:** The sliding time window that serves two purposes:

1. **Counting window**: Only occurrences within the last N minutes are counted
2. **Cooldown period**: After an alert is sent, the accumulator resets

| Value | Meaning |
|-------|---------|
| 0 | No time restriction (legacy mode - every occurrence alerts) |
| 1 | 1-minute window |
| 60 | 1-hour window |
| 1440 | 24-hour window (1 day) |

---

## Configuration Examples

### Example 1: Critical One-Time Events

**Scenario:** Server unexpectedly rebooted - I need to know immediately, every time.

```json
{
  "EventId": 6008,
  "Description": "System - Unexpected shutdown",
  "MaxOccurrences": 0,
  "TimeWindowMinutes": 0
}
```

**Behavior:**
- Alert generated for **every single occurrence**
- No deduplication, no cooldown
- Use sparingly to avoid alert fatigue

---

### Example 2: Important Event with Cooldown

**Scenario:** Account locked out - alert me immediately, but not more than once per hour.

```json
{
  "EventId": 4740,
  "Description": "Security - Account locked out",
  "MaxOccurrences": 0,
  "TimeWindowMinutes": 60
}
```

**Behavior:**
- First lockout → Alert sent immediately
- Next 60 minutes → No alerts (cooldown active)
- After 60 minutes → Next lockout triggers alert again

**Timeline:**
```
09:00 - Account locked → ALERT SENT
09:15 - Another lockout → No alert (cooldown)
09:30 - Another lockout → No alert (cooldown)
10:05 - Another lockout → ALERT SENT (cooldown expired)
```

---

### Example 3: Daily Notification

**Scenario:** Security updates pending - alert me once per day max.

```json
{
  "SecurityUpdateAlertSeverity": "Warning",
  "MaxOccurrences": 0,
  "TimeWindowMinutes": 1440
}
```

**Behavior:**
- First detection → Alert sent
- For the next 24 hours → No more alerts for this condition
- Next day → Can alert again

---

### Example 4: Sustained CPU High

**Scenario:** Only alert if CPU is high for multiple consecutive checks (not just a brief spike).

```json
{
  "ProcessorMonitoring": {
    "WarningThresholdPercent": 90,
    "Alerts": {
      "HighCpuSeverity": "Warning",
      "MaxOccurrences": 5,
      "TimeWindowMinutes": 10
    }
  }
}
```

**Behavior:**
- CPU must be >90% for **6 or more** poll cycles within 10 minutes
- If CPU drops below threshold, the count resets (old entries age out)
- After alert, count resets to zero

**Timeline:**
```
09:00 - CPU 95% → Count: 1 → No alert
09:01 - CPU 92% → Count: 2 → No alert
09:02 - CPU 88% → Count: 2 (no new occurrence)
09:03 - CPU 91% → Count: 3 → No alert
09:04 - CPU 93% → Count: 4 → No alert
09:05 - CPU 94% → Count: 5 → No alert
09:06 - CPU 95% → Count: 6 → ALERT SENT → Count reset to 0
09:07 - CPU 95% → Count: 1 → No alert (starting fresh)
```

---

### Example 5: High-Frequency Event Log Events

**Scenario:** Task Scheduler Event 201 fires hundreds of times - only alert if it's excessive.

```json
{
  "EventId": 201,
  "Description": "Task Scheduler - Task completed with errors",
  "MaxOccurrences": 100,
  "TimeWindowMinutes": 60
}
```

**Behavior:**
- Need **101+ occurrences** within 60 minutes to trigger alert
- After alert, accumulator clears
- Need 101 more new occurrences for another alert

**Timeline:**
```
09:00-09:30 - 80 events → Count: 80 → No alert
09:30-09:45 - 25 events → Count: 105 → ALERT SENT → Count reset
09:45-10:00 - 50 events → Count: 50 → No alert
08:30 events age out (older than 60 min from current time)
```

---

### Example 6: Disk Space Warning

**Scenario:** Alert when disk is low, but don't spam me every minute.

```json
{
  "DiskSpaceMonitoring": {
    "Thresholds": {
      "WarningPercent": 85,
      "CriticalPercent": 95
    },
    "Alerts": {
      "WarningAlertSeverity": "Warning",
      "CriticalAlertSeverity": "Critical",
      "MaxOccurrences": 0,
      "TimeWindowMinutes": 120
    }
  }
}
```

**Behavior:**
- First time disk exceeds 85% → Warning alert
- For next 2 hours → No more warnings (cooldown)
- If disk exceeds 95% → Critical alert (separate tracking)
- After 2 hours → Can warn again if still above threshold

---

### Example 7: Failed Login Attempts (Brute Force Detection)

**Scenario:** Alert if there are many failed logins in a short period (possible attack).

```json
{
  "EventId": 4625,
  "Description": "Security - Failed login attempt",
  "MaxOccurrences": 10,
  "TimeWindowMinutes": 5
}
```

**Behavior:**
- Need **11+ failed logins** within 5 minutes to trigger alert
- Designed to catch brute force attacks, not occasional typos
- After alert, count resets

---

### Example 8: Network Connectivity

**Scenario:** Only alert if connectivity is lost for multiple consecutive checks.

```json
{
  "NetworkMonitoring": {
    "Alerts": {
      "ConnectivityLostSeverity": "Critical",
      "MaxOccurrences": 3,
      "TimeWindowMinutes": 5
    }
  }
}
```

**Behavior:**
- Need **4 consecutive failures** within 5 minutes
- Single packet loss or brief outage won't trigger alert
- Sustained outage will trigger alert

---

## Common Patterns

### Pattern 1: "Alert Immediately, Don't Repeat"

```json
{
  "MaxOccurrences": 0,
  "TimeWindowMinutes": 60
}
```
Use for: Important events where you need to know ASAP, but one notification is enough.

### Pattern 2: "Alert Every Time"

```json
{
  "MaxOccurrences": 0,
  "TimeWindowMinutes": 0
}
```
Use for: Critical events that must never be missed, even if it means duplicates.

### Pattern 3: "Sustained Condition Required"

```json
{
  "MaxOccurrences": 5,
  "TimeWindowMinutes": 15
}
```
Use for: Threshold-based alerts (CPU, memory) where brief spikes are acceptable.

### Pattern 4: "High-Frequency Threshold"

```json
{
  "MaxOccurrences": 100,
  "TimeWindowMinutes": 60
}
```
Use for: Events that occur frequently, where volume indicates a problem.

### Pattern 5: "Once Per Day"

```json
{
  "MaxOccurrences": 0,
  "TimeWindowMinutes": 1440
}
```
Use for: Informational alerts that you only need to see once per day.

---

## How Accumulation Works

### The Sliding Window

The `TimeWindowMinutes` creates a sliding window that automatically removes old occurrences:

```
TimeWindowMinutes: 60

Timeline:
├─────────────────────────────────────────────────────────────┤
                    ◄────── Last 60 minutes ──────►
                    
08:00    08:30    09:00    09:30    10:00 (now)
  │        │        │        │        │
  X        X        X        X        X    ← Events
  │        │        │                 │
  └────────┴────────┘                 │
     Aged out                    Still counted
     (not counted)
```

### After Alert Clears

When an alert is triggered and distributed:

1. **Accumulator clears** → Count goes to 0
2. **LastProcessedTimestamp stays** → Only genuinely new events are counted
3. **Fresh accumulation begins** → Must reach threshold again for another alert

```
Before Alert:  [t1, t2, t3, t4, t5, t6] → Count: 6 → ALERT!
After Alert:   [] → Count: 0
Next Poll:     [t7] → Count: 1 (only new events added)
```

---

## Troubleshooting

### "I'm getting too many alerts"

**Problem:** Alert fatigue from frequent notifications.

**Solutions:**
1. Increase `MaxOccurrences` to require more events before alerting
2. Increase `TimeWindowMinutes` to extend the cooldown period
3. Check if condition is legitimately occurring frequently (fix root cause)

### "I'm not getting any alerts"

**Problem:** Alerts aren't triggering when expected.

**Solutions:**
1. Check `MaxOccurrences` - if set too high, threshold may never be reached
2. Check `TimeWindowMinutes` - if too short, events may age out before accumulating
3. Verify the condition is actually being detected (check logs)

### "I want to know about every event"

**Solution:** Set `MaxOccurrences: 0` and `TimeWindowMinutes: 0`

**Warning:** This can cause alert flooding if the condition occurs frequently.

### "Alerts stopped after the first one"

**Cause:** This is expected behavior with a cooldown period.

**If you want more frequent alerts:** Reduce `TimeWindowMinutes`

---

## Default Values

If not specified, alerts use these defaults:

```json
{
  "MaxOccurrences": 0,
  "TimeWindowMinutes": 5
}
```

This means: Alert immediately on first occurrence, with a 5-minute cooldown.

---

## Configuration Locations

Alert settings can be found in `appsettings.json` in these sections:

| Section | Alerts Configured |
|---------|-------------------|
| `EventMonitoring.EventsToMonitor[]` | Windows Event Log events |
| `ProcessorMonitoring.Alerts` | CPU threshold alerts |
| `MemoryMonitoring.Alerts` | Memory threshold alerts |
| `VirtualMemoryMonitoring.Alerts` | Virtual memory alerts |
| `DiskSpaceMonitoring.Alerts` | Disk space alerts |
| `DiskUsageMonitoring.Alerts` | Disk I/O alerts |
| `NetworkMonitoring.Alerts` | Network connectivity alerts |
| `ScheduledTaskMonitoring.Alerts` | Scheduled task alerts |
| `WindowsUpdateMonitoring.Alerts` | Windows Update alerts |
| `UptimeMonitoring.Alerts` | Uptime/reboot alerts |
| `Db2DiagMonitoring.Alerts` | DB2 diagnostic alerts |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-22 | Initial documentation |
