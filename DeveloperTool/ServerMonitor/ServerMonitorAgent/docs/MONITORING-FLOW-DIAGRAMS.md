# Server Surveillance Tool - Monitoring Flow Diagrams

**Purpose:** Visual representation of monitoring flow and alert processing  
**Example:** Virtual Memory threshold breach scenario  
**Date:** 2025-11-26

---

## Table of Contents
1. [Overall System Architecture](#overall-system-architecture)
2. [Virtual Memory Monitoring Flow](#virtual-memory-monitoring-flow)
3. [Alert Processing Flow](#alert-processing-flow)
4. [Complete Breach-to-Notification Flow](#complete-breach-to-notification-flow)
5. [Configuration Hot-Reload Flow](#configuration-hot-reload-flow)
6. [Snapshot Export Flow](#snapshot-export-flow)

---

## Overall System Architecture

```mermaid
graph TB
    Start[Service Starts] --> DI[Dependency Injection Setup]
    DI --> Config[Load Configuration]
    Config --> Orchestrator[SurveillanceOrchestrator]
    
    Orchestrator --> Timer1[Processor Monitor Timer<br/>5 sec]
    Orchestrator --> Timer2[Memory Monitor Timer<br/>10 sec]
    Orchestrator --> Timer3[Virtual Memory Timer<br/>10 sec]
    Orchestrator --> Timer4[Disk Monitor Timer<br/>15 sec]
    Orchestrator --> Timer5[Network Monitor Timer<br/>30 sec]
    Orchestrator --> Timer6[Other Monitors...]
    
    Orchestrator --> ExportTimer[Snapshot Export Timer<br/>15 min]
    Orchestrator --> CleanupTimer[Cleanup Timer<br/>24 hours]
    
    Timer1 --> MonitorCycle[Monitor Collection Cycle]
    Timer2 --> MonitorCycle
    Timer3 --> MonitorCycle
    Timer4 --> MonitorCycle
    Timer5 --> MonitorCycle
    Timer6 --> MonitorCycle
    
    MonitorCycle --> AlertMgr[Alert Manager]
    MonitorCycle --> SnapshotCheck{Snapshot on Alert?}
    
    SnapshotCheck -->|Yes| Export[Export Snapshot]
    
    AlertMgr --> EventLog[Event Log Channel]
    AlertMgr --> FileLog[File Log Channel]
    AlertMgr --> Email[Email Channel]
    
    ExportTimer --> Export
    Export --> Compress{Compression<br/>Enabled?}
    Compress -->|Yes| GZip[GZip Compress]
    Compress -->|No| SaveJSON[Save JSON]
    GZip --> SaveJSON
    
    CleanupTimer --> Cleanup[Cleanup Old Snapshots]
    
    style Start fill:#90EE90
    style AlertMgr fill:#FFB6C1
    style Export fill:#87CEEB
```

---

## Virtual Memory Monitoring Flow

### Detailed Monitor Collection Cycle

```mermaid
sequenceDiagram
    participant Timer as Monitor Timer
    participant Orch as Orchestrator
    participant VMon as VirtualMemoryMonitor
    participant PC as PerformanceCounter
    participant CI as ComputerInfo
    participant Alert as Alert Object
    participant Result as MonitorResult
    
    Note over Timer: Every 10 seconds
    Timer->>Orch: Timer tick
    Orch->>VMon: CollectAsync()
    
    activate VMon
    VMon->>VMon: Check IsEnabled
    
    alt Monitor Disabled
        VMon-->>Orch: Success=true, ErrorMessage="Disabled"
    else Monitor Enabled
        VMon->>VMon: Start Stopwatch
        VMon->>PC: Get Pages/sec counter
        VMon->>CI: Get Total Virtual Memory
        VMon->>CI: Get Available Virtual Memory
        
        VMon->>VMon: Calculate UsedPercent
        Note right of VMon: (Total - Available) / Total * 100
        
        VMon->>VMon: Check if > WarningPercent
        
        alt Above Warning Threshold
            VMon->>VMon: Increment SecondsAboveThreshold<br/>+= PollingInterval (10 sec)
        else Below Warning Threshold
            VMon->>VMon: Keep existing counter
        end
        
        VMon->>VMon: Check Daily Reset
        alt 24 hours passed
            VMon->>VMon: Reset SecondsAboveThreshold = 0
            VMon->>VMon: Reset LastResetTime = Now
        end
        
        VMon->>VMon: Evaluate Alert Conditions
        
        alt UsedPercent >= CriticalPercent (90%)
            VMon->>Alert: Create Alert(Critical)
            Note right of Alert: "Virtual memory usage critical: 92%"
            VMon->>Result: Add alert to result
        end
        
        alt UsedPercent >= WarningPercent AND<br/>SecondsAboveThreshold >= SustainedDuration
            VMon->>Alert: Create Alert(Warning)
            Note right of Alert: "Sustained above warning: 85% for 300 sec"
            VMon->>Result: Add alert to result
        end
        
        alt PagingRate > ExcessivePagingRate (1000)
            VMon->>Alert: Create Alert(Warning)
            Note right of Alert: "Excessive paging: 1500 pages/sec"
            VMon->>Result: Add alert to result
        end
        
        VMon->>VMon: Build VirtualMemoryData object
        VMon->>VMon: Stop Stopwatch
        
        VMon->>Result: Create MonitorResult<br/>Success=true<br/>Data=VirtualMemoryData<br/>Alerts=List<Alert>
        
        VMon-->>Orch: Return MonitorResult
    end
    deactivate VMon
    
    Orch->>Orch: Process Alerts
```

---

## Alert Processing Flow

### From Monitor to Alert Channels

```mermaid
flowchart TD
    Start[Monitor Returns Result] --> HasAlerts{Has Alerts?}
    
    HasAlerts -->|No| End[End]
    HasAlerts -->|Yes| LogInfo[Log: Monitor generated X alerts]
    
    LogInfo --> AlertMgr[Alert Manager ProcessAlertsAsync]
    
    AlertMgr --> CheckEnabled{Alerting<br/>Enabled?}
    CheckEnabled -->|No| LogDisabled[Log: Alerting disabled]
    CheckEnabled -->|Yes| LoopAlerts[For Each Alert]
    
    LoopAlerts --> Throttled{Is Throttled?<br/>Check rate limit}
    
    Throttled -->|Yes| LogThrottle[Log: Alert throttled]
    Throttled -->|No| Duplicate{Is Duplicate?<br/>Check suppression window}
    
    Duplicate -->|Yes| LogDupe[Log: Duplicate suppressed]
    Duplicate -->|No| GetChannels[Get Enabled Channels]
    
    GetChannels --> FilterSeverity[Filter by MinSeverity]
    
    FilterSeverity --> SendParallel[Send to All Channels<br/>In Parallel]
    
    SendParallel --> EventLogChan{Event Log<br/>Channel?}
    SendParallel --> FileChan{File<br/>Channel?}
    SendParallel --> EmailChan{Email<br/>Channel?}
    
    EventLogChan -->|Enabled &<br/>Severity >= Min| WriteEventLog[Write to Application Log<br/>Source: ServerMonitor]
    FileChan -->|Enabled &<br/>Severity >= Min| WriteFile[Append to Alert Log File<br/>Thread-safe with SemaphoreSlim]
    EmailChan -->|Enabled &<br/>Severity >= Min| SendEmail[Send HTML Email via SMTP]
    
    WriteEventLog --> Track[Track Alert]
    WriteFile --> Track
    SendEmail --> Track
    
    Track --> UpdateTimestamps[Add to Timestamp Queue]
    Track --> UpdateRecentAlerts[Add to Recent Alerts Dict]
    
    UpdateTimestamps --> CheckExport{Export Snapshot<br/>on Alert?}
    
    CheckExport -->|Yes| TriggerExport[Trigger Snapshot Export]
    CheckExport -->|No| End
    TriggerExport --> End
    
    LogDisabled --> End
    LogThrottle --> End
    LogDupe --> End
    
    style Start fill:#90EE90
    style AlertMgr fill:#FFB6C1
    style WriteEventLog fill:#87CEEB
    style WriteFile fill:#87CEEB
    style SendEmail fill:#87CEEB
    style TriggerExport fill:#FFD700
```

---

## Complete Breach-to-Notification Flow

### Virtual Memory Critical Threshold Breach Example

```mermaid
sequenceDiagram
    autonumber
    participant System as Windows System
    participant Timer as Monitor Timer (10s)
    participant VMon as VirtualMemoryMonitor
    participant Data as VirtualMemoryData
    participant Alert as Alert (Critical)
    participant AMgr as AlertManager
    participant EventLog as EventLog Channel
    participant File as File Channel
    participant Email as Email Channel
    participant Export as SnapshotExporter
    
    Note over System: Virtual Memory reaches 92%
    
    Timer->>VMon: Timer fires (10 sec interval)
    activate VMon
    
    VMon->>System: Query Performance Counters
    System-->>VMon: Pages/sec = 1200
    
    VMon->>System: Get Total Virtual Memory (WMI)
    System-->>VMon: 48 GB
    
    VMon->>System: Get Available Virtual Memory (WMI)
    System-->>VMon: 3.84 GB
    
    VMon->>VMon: Calculate: (48 - 3.84) / 48 * 100 = 92%
    
    VMon->>VMon: Check: 92% >= CriticalPercent (90%)?
    Note right of VMon: YES - Critical threshold breached!
    
    VMon->>Alert: new Alert()<br/>Severity = Critical<br/>Category = "VirtualMemory"<br/>Message = "Virtual memory usage critical: 92%"
    
    VMon->>VMon: Check: PagingRate (1200) > 1000?
    Note right of VMon: YES - Excessive paging!
    
    VMon->>Alert: new Alert()<br/>Severity = Warning<br/>Message = "Excessive paging: 1200 pages/sec"
    
    VMon->>Data: Create VirtualMemoryData<br/>TotalGB = 48<br/>AvailableGB = 3.84<br/>UsedPercent = 92<br/>PagingRatePerSec = 1200
    
    VMon->>VMon: Create MonitorResult<br/>Success = true<br/>Alerts = [Critical, Warning]<br/>Data = VirtualMemoryData
    
    VMon-->>Timer: Return MonitorResult
    deactivate VMon
    
    Timer->>AMgr: ProcessAlertsAsync(2 alerts)
    activate AMgr
    
    Note over AMgr: Processing Alert 1 (Critical)
    
    AMgr->>AMgr: Check throttling (50/hour limit)
    AMgr->>AMgr: Current hour: 12 alerts
    Note right of AMgr: OK - Not throttled
    
    AMgr->>AMgr: Check duplicate suppression (15 min)
    AMgr->>AMgr: Last same alert: 20 min ago
    Note right of AMgr: OK - Not duplicate
    
    AMgr->>AMgr: Get channels where:<br/>Enabled = true AND<br/>MinSeverity <= Critical
    
    par Send to All Channels
        AMgr->>EventLog: SendAlertAsync(Critical Alert)
        activate EventLog
        EventLog->>EventLog: Map to EventLogEntryType.Error
        EventLog->>System: WriteEntry("Application" log)<br/>Source: ServerMonitor<br/>EventID: 1002
        System-->>EventLog: Success
        EventLog-->>AMgr: Done
        deactivate EventLog
        
        AMgr->>File: SendAlertAsync(Critical Alert)
        activate File
        File->>File: Generate log path:<br/>C:\opt\data\AllPwshLog\<br/>ServerSurveillance_Alerts_20251126.log
        File->>File: Format entry:<br/>[2025-11-26 14:30:00] [CRITICAL] [VirtualMemory]<br/>Virtual memory usage critical: 92%
        File->>File: Acquire SemaphoreSlim lock
        File->>System: Append to file
        System-->>File: Success
        File->>File: Release lock
        File-->>AMgr: Done
        deactivate File
        
        AMgr->>Email: SendAlertAsync(Critical Alert)
        activate Email
        Note over Email: Email channel enabled for Critical
        Email->>Email: Build HTML email<br/>Subject: [Critical] VirtualMemory: Virtual memory usage critical: 92%<br/>Body: Formatted table with details
        Email->>Email: Connect to SMTP server
        Email->>System: Send email to admin@company.com
        System-->>Email: Success
        Email-->>AMgr: Done
        deactivate Email
    end
    
    AMgr->>AMgr: Track alert in recent alerts dict
    AMgr->>AMgr: Add timestamp to queue
    
    Note over AMgr: Processing Alert 2 (Warning) - Same flow...
    
    AMgr-->>Timer: All alerts processed
    deactivate AMgr
    
    Timer->>Timer: Check: ExportSettings.ExportIntervals.OnAlertTrigger?
    Note right of Timer: YES - Export on alert enabled
    
    Timer->>Export: ExportCurrentSnapshotAsync()
    activate Export
    
    Export->>Export: Collect data from all monitors
    Export->>Export: Build SystemSnapshot object
    Export->>Export: Serialize to JSON
    Export->>Export: Generate filename:<br/>SERVER01_20251126_143000.json
    Export->>System: Write to:<br/>C:\opt\data\ServerSurveillance\Snapshots\
    
    Export->>Export: CompressionEnabled = true
    Export->>Export: GZip compress file
    Export->>System: Delete original .json<br/>Keep .json.gz (70% smaller)
    
    System-->>Export: Success
    Export-->>Timer: Snapshot exported
    deactivate Export
    
    Note over System,Export: End of cycle - System continues monitoring
```

---

## Configuration Hot-Reload Flow

```mermaid
flowchart TD
    Start[Admin Edits appsettings.json] --> Save[Save File]
    
    Save --> Detected[.NET FileSystemWatcher<br/>Detects Change]
    
    Detected --> IOM[IOptionsMonitor<br/>Triggers OnChange Event]
    
    IOM --> ConfigMgr[ConfigurationManager<br/>OnConfigurationChanged]
    
    ConfigMgr --> Validate[Validate New Configuration]
    
    Validate --> Valid{Is Valid?}
    
    Valid -->|No| LogError[Log Validation Errors]
    Valid -->|Yes| LogInfo[Log: Configuration change detected]
    
    LogError --> Reject[Reject New Configuration]
    Reject --> KeepOld[Keep Using Old Config]
    
    LogInfo --> Update[Update _configuration Field]
    
    Update --> FireEvent[Fire ConfigurationChanged Event]
    
    FireEvent --> Monitors[Monitors Use New Config]
    FireEvent --> Channels[Alert Channels Use New Config]
    
    Monitors --> EventLogChan[EventLog Channel Updates<br/>MinSeverity, IsEnabled]
    Monitors --> FileChan[File Channel Updates<br/>LogPath, MinSeverity]
    Monitors --> EmailChan[Email Channel Updates<br/>SMTP Settings, Recipients]
    
    EventLogChan --> NextCycle[Next Monitor Cycle<br/>Uses New Settings]
    FileChan --> NextCycle
    EmailChan --> NextCycle
    
    NextCycle --> NoRestart[No Service Restart Required!]
    
    KeepOld --> End[Continue with Old Config]
    NoRestart --> End
    
    style Start fill:#90EE90
    style Valid fill:#FFD700
    style NoRestart fill:#87CEEB
```

---

## Snapshot Export Flow

```mermaid
flowchart TB
    Start{Export Trigger} --> Scheduled[Scheduled Timer<br/>Every 15 minutes]
    Start --> OnAlert[Alert Triggered]
    Start --> OnDemand[On-Demand Request]
    
    Scheduled --> Collect[Collect Current Snapshot]
    OnAlert --> Collect
    OnDemand --> Collect
    
    Collect --> Parallel[Query All Enabled Monitors<br/>In Parallel]
    
    Parallel --> PMon[Processor Monitor]
    Parallel --> MMon[Memory Monitor]
    Parallel --> VMon[Virtual Memory Monitor]
    Parallel --> DMon[Disk Monitor]
    Parallel --> NMon[Network Monitor]
    Parallel --> UMon[Uptime Monitor]
    Parallel --> WMon[Windows Update Monitor]
    Parallel --> EMon[Event Log Monitor]
    Parallel --> TMon[Scheduled Task Monitor]
    
    PMon --> Await[Await All Results]
    MMon --> Await
    VMon --> Await
    DMon --> Await
    NMon --> Await
    UMon --> Await
    WMon --> Await
    EMon --> Await
    TMon --> Await
    
    Await --> Build[Build SystemSnapshot]
    
    Build --> Metadata[Add Metadata:<br/>ServerName<br/>Timestamp<br/>SnapshotId (GUID)<br/>ToolVersion<br/>CollectionDurationMs]
    
    Metadata --> AddData[Add Monitor Data:<br/>Processor<br/>Memory<br/>VirtualMemory<br/>Disks<br/>Network<br/>Uptime<br/>WindowsUpdates<br/>Events<br/>ScheduledTasks<br/>Alerts]
    
    AddData --> Serialize[Serialize to JSON<br/>Pretty-printed<br/>CamelCase<br/>Null values omitted]
    
    Serialize --> Filename[Generate Filename<br/>Pattern: ServerName_Timestamp.json<br/>Example: SERVER01_20251126_143000.json]
    
    Filename --> CheckDir{Output Directory<br/>Exists?}
    
    CheckDir -->|No| CreateDir[Create Directory]
    CheckDir -->|Yes| WritePath[Write to Path]
    CreateDir --> WritePath
    
    WritePath --> Write[Write JSON to File]
    
    Write --> Compress{Compression<br/>Enabled?}
    
    Compress -->|No| Done[Log: Snapshot Exported]
    
    Compress -->|Yes| GZip[GZip Compress]
    
    GZip --> Size[Original: 250 KB<br/>Compressed: 75 KB<br/>70% reduction]
    
    Size --> DeleteOrig[Delete Original JSON]
    
    DeleteOrig --> Rename[Keep .json.gz]
    
    Rename --> Done
    
    Done --> End[End]
    
    style Start fill:#90EE90
    style Build fill:#FFB6C1
    style Serialize fill:#87CEEB
    style GZip fill:#FFD700
```

---

## Real-World Example Timeline

### What Actually Happens: Virtual Memory Breach at 14:30:00

```mermaid
gantt
    title Virtual Memory Breach Detection and Response Timeline
    dateFormat HH:mm:ss
    axisFormat %H:%M:%S
    
    section Monitoring
    Virtual Memory at 85%           :14:29:50, 10s
    Virtual Memory at 92%           :14:30:00, 10s
    Threshold breached detected     :14:30:00, 1s
    
    section Data Collection
    Query Performance Counters      :14:30:00, 100ms
    Query WMI (Total Memory)        :14:30:00, 80ms
    Query WMI (Available Memory)    :14:30:00, 80ms
    Calculate percentages           :14:30:00, 10ms
    
    section Alert Creation
    Create Critical Alert           :14:30:00, 5ms
    Create Warning Alert (Paging)   :14:30:00, 5ms
    Build MonitorResult             :14:30:00, 10ms
    
    section Alert Processing
    AlertManager receives alerts    :14:30:00, 5ms
    Check throttling limits         :14:30:00, 2ms
    Check duplicate suppression     :14:30:00, 3ms
    
    section Alert Delivery
    Write to Event Log              :14:30:00, 50ms
    Write to Alert File             :14:30:00, 30ms
    Send Email                      :14:30:00, 500ms
    
    section Snapshot Export
    Trigger snapshot export         :14:30:01, 10ms
    Collect all monitor data        :14:30:01, 2500ms
    Serialize to JSON               :14:30:03, 300ms
    GZip compress                   :14:30:04, 400ms
    Write to disk                   :14:30:04, 100ms
    
    section Logging
    Log alert generation            :14:30:00, 5ms
    Log alert delivery              :14:30:01, 5ms
    Log snapshot export             :14:30:05, 5ms
```

**Total Time:**
- Detection to Alert Delivery: ~600ms
- Detection to Snapshot Export Complete: ~5 seconds

---

## Configuration Reference for Virtual Memory

From `appsettings.json`:

```json
{
  "VirtualMemoryMonitoring": {
    "Enabled": true,
    "PollingIntervalSeconds": 10,
    "Thresholds": {
      "WarningPercent": 80,
      "CriticalPercent": 90,
      "SustainedDurationSeconds": 300,
      "ExcessivePagingRate": 1000
    }
  }
}
```

**Alert Triggers:**
1. **Critical Alert**: UsedPercent >= 90% (immediate)
2. **Warning Alert (Sustained)**: UsedPercent >= 80% for 300+ seconds
3. **Warning Alert (Paging)**: PagingRate > 1000 pages/sec

---

## Summary

This document demonstrates:
- ✅ How monitors collect data and evaluate thresholds
- ✅ How alerts are created and processed
- ✅ How alerts are distributed to multiple channels in parallel
- ✅ How snapshot exports are triggered and compressed
- ✅ How configuration hot-reload works without service restart
- ✅ Real-world timing of the entire detection-to-notification pipeline

**Total latency from threshold breach to administrator notification: ~600 milliseconds** ⚡

---

*Last Updated: 2025-11-26*

