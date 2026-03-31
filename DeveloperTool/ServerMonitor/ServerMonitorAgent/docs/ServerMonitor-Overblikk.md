# ServerMonitor - Systemoversikt

## Arkitektur

```mermaid
graph TB
    subgraph "ServerMonitor Applikasjon"
        SM[ServerMonitor.exe]
        SM --> GM[GlobalSnapshotService]
        SM --> SO[SurveillanceOrchestrator]
        SM --> AM[AlertManager]
        SM --> SE[SnapshotExporter]
    end
    
    subgraph "Monitorer"
        PM[ProcessorMonitor]
        MM[MemoryMonitor]
        VM[VirtualMemoryMonitor]
        DM[DiskMonitor]
        NM[NetworkMonitor]
        UM[UptimeMonitor]
        WUM[WindowsUpdateMonitor]
        ELM[EventLogMonitor]
        STM[ScheduledTaskMonitor]
    end
    
    subgraph "Alert Kanaler"
        SMS[SMS AlertChannel]
        EMAIL[Email AlertChannel]
        FILE[File AlertChannel]
        EVENT[EventLog AlertChannel]
        WK[WKMonitor AlertChannel]
    end
    
    subgraph "Eksport"
        JSON[JSON Snapshots]
        HTML[HTML Snapshots]
        REST[REST API]
    end
    
    SO --> PM
    SO --> MM
    SO --> VM
    SO --> DM
    SO --> NM
    SO --> UM
    SO --> WUM
    SO --> ELM
    SO --> STM
    
    PM --> GM
    MM --> GM
    VM --> GM
    DM --> GM
    
    GM --> AM
    AM --> SMS
    AM --> EMAIL
    AM --> FILE
    AM --> EVENT
    AM --> WK
    
    GM --> SE
    SE --> JSON
    SE --> HTML
    GM --> REST
```

## Overvåkingsflyt

```mermaid
sequenceDiagram
    participant SO as SurveillanceOrchestrator
    participant PM as ProcessorMonitor
    participant GM as GlobalSnapshotService
    participant AM as AlertManager
    participant SMS as SMS Channel
    
    loop Hver PollingInterval
        SO->>PM: CollectAsync()
        PM->>PM: Samle CPU målinger
        PM->>PM: Beregn gjennomsnitt over SustainedDurationSeconds
        PM->>PM: Sjekk om nok målinger (60 for 300s)
        alt Nok målinger OG gjennomsnitt > terskel
            PM->>GM: Oppdater data + Alerts
            GM->>AM: Prosesser alerts
            AM->>SMS: Send alert
        else Ikke nok målinger
            PM->>PM: Logg "Skipping alert check"
            PM->>GM: Oppdater data (uten alerts)
        end
    end
```

## Måling og Gjennomsnittsberegning

```mermaid
graph LR
    subgraph "Målingssamling"
        M1[Måling 1<br/>t=0s]
        M2[Måling 2<br/>t=5s]
        M3[Måling 3<br/>t=10s]
        M4[...]
        M60[Måling 60<br/>t=295s]
    end
    
    subgraph "Gjennomsnittsberegning"
        AVG[Beregn gjennomsnitt<br/>over alle målinger]
    end
    
    subgraph "Alert Sjekk"
        CHECK{Nok målinger?<br/>60 for 300s}
        THRESHOLD{Gjennomsnitt ><br/>terskel?}
        ALERT[Send Alert]
        SKIP[Skip Alert]
    end
    
    M1 --> AVG
    M2 --> AVG
    M3 --> AVG
    M4 --> AVG
    M60 --> AVG
    
    AVG --> CHECK
    CHECK -->|Ja, 60 målinger| THRESHOLD
    CHECK -->|Nei, < 60 målinger| SKIP
    THRESHOLD -->|Ja| ALERT
    THRESHOLD -->|Nei| SKIP
```

## Dataflyt

```mermaid
flowchart TD
    START[ServerMonitor Starter] --> INIT[Initialiser Monitorer]
    INIT --> LOOP[Polling Loop]
    
    LOOP --> COLLECT[Samle Data]
    COLLECT --> STORE[Lagre Målinger]
    STORE --> CALC[Beregn Gjennomsnitt]
    
    CALC --> CHECK{Har nok<br/>målinger?}
    CHECK -->|Nei| WAIT[Vent neste<br/>polling]
    CHECK -->|Ja| COMPARE{Sammenlign med<br/>terskel}
    
    COMPARE -->|Over terskel| ALERT[Generer Alert]
    COMPARE -->|Under terskel| WAIT
    
    ALERT --> DIST[Distribuer til<br/>Alert Kanaler]
    DIST --> SMS[SMS]
    DIST --> EMAIL[Email]
    DIST --> FILE[Fil]
    
    STORE --> EXPORT[Eksporter Snapshot]
    EXPORT --> JSON[JSON Fil]
    EXPORT --> HTML[HTML Fil]
    EXPORT --> REST[REST API]
    
    WAIT --> LOOP
```

## Komponenter

```mermaid
mindmap
  root((ServerMonitor))
    Monitorer
      Processor
        CPU bruk
        Per-core
        Gjennomsnitt over tid
      Memory
        Fysisk minne
        Tilgjengelig minne
      Disk
        Diskplass
        I/O ytelse
      Network
        Ping
        DNS
        Porter
      Windows Update
        Ventende oppdateringer
        Kritiske oppdateringer
    Alert System
      SMS
        Format: [Severity@Server]
        PSWin API
      Email
        SMTP
        HTML format
      Fil
        Alert log
      EventLog
        Windows Event Viewer
    Eksport
      JSON Snapshots
        Målingshistorikk
        Systemtilstand
      HTML Snapshots
        Interaktiv visning
        JavaScript arrays
      REST API
        Live data
        Swagger UI
    Konfigurasjon
      appsettings.json
      SustainedDurationSeconds
      PollingIntervalSeconds
      Terskler
```

## Alert Distribusjon

```mermaid
graph TD
    ALERT[Alert Generert] --> FILTER[Filter på Severity]
    FILTER --> THROTTLE[Throttling Sjekk]
    THROTTLE -->|Ikke throttlet| CHANNELS[Alert Kanaler]
    THROTTLE -->|Throttlet| SKIP[Skip Alert]
    
    CHANNELS --> SMS1[SMS Channel]
    CHANNELS --> EMAIL1[Email Channel]
    CHANNELS --> FILE1[File Channel]
    CHANNELS --> EVENT1[EventLog Channel]
    CHANNELS --> WK1[WKMonitor Channel]
    
    SMS1 --> SMS2["Format: [Severity@Server]<br/>Processor: CPU usage..."]
    EMAIL1 --> EMAIL2[HTML Email]
    FILE1 --> FILE2[Alert Log Fil]
    EVENT1 --> EVENT2[Windows Event Log]
    WK1 --> WK2[WKMonitor API]
```

## Målingshistorikk

```mermaid
graph LR
    subgraph "Tidsserie Målinger"
        T0["Måling t=0s<br/>CPU: 45%"]
        T5["Måling t=5s<br/>CPU: 48%"]
        T10["Måling t=10s<br/>CPU: 52%"]
        T15[...]
        T300["Måling t=300s<br/>CPU: 55%"]
    end
    
    subgraph "Gjennomsnittsberegning"
        AVG["Gjennomsnitt:<br/>50%"]
    end
    
    subgraph "Eksport"
        JSON["JSON:<br/>cpuUsageHistory array"]
        HTML["HTML:<br/>JavaScript array"]
        REST["REST API:<br/>processor.cpuUsageHistory"]
    end
    
    T0 --> AVG
    T5 --> AVG
    T10 --> AVG
    T15 --> AVG
    T300 --> AVG
    
    AVG --> JSON
    AVG --> HTML
    AVG --> REST
```

## Terskel Sjekk Logikk

```mermaid
stateDiagram-v2
    [*] --> SamleMåling: Hver PollingInterval
    
    SamleMåling --> LagreMåling: Legg til i historikk
    LagreMåling --> RensGamle: Fjern målinger > SustainedDurationSeconds
    
    RensGamle --> SjekkAntall: Har nok målinger?
    
    SjekkAntall --> IkkeNok: < requiredMeasurements
    SjekkAntall --> NokMålinger: >= requiredMeasurements
    
    IkkeNok --> LoggSkip: Logg "Skipping alert check"
    LoggSkip --> [*]
    
    NokMålinger --> BeregnGjennomsnitt: Beregn gjennomsnitt
    BeregnGjennomsnitt --> SjekkTerskel: Sammenlign med terskel
    
    SjekkTerskel --> UnderTerskel: Gjennomsnitt < terskel
    SjekkTerskel --> OverTerskel: Gjennomsnitt >= terskel
    
    UnderTerskel --> [*]
    OverTerskel --> GenererAlert: Opprett Alert
    GenererAlert --> [*]
```

## Eksempel: CPU Alert Scenario

```mermaid
gantt
    title CPU Overvåking - 5 Minutter (300 sekunder)
    dateFormat X
    axisFormat %Ss
    
    section Målinger
    Måling 1 (t=0s)    :0, 5
    Måling 2 (t=5s)    :5, 5
    Måling 3 (t=10s)   :10, 5
    Måling 4-59        :15, 280
    Måling 60 (t=295s) :295, 5
    
    section Gjennomsnitt
    Beregn gjennomsnitt :300, 1
    
    section Alert Sjekk
    Sjekk terskel       :301, 1
    Send alert (hvis over) :302, 1
```

## System Oversikt

```mermaid
graph TB
    subgraph "Input"
        WIN[Windows System]
        PERF[Performance Counters]
        WMI[WMI Queries]
        TASK[Task Scheduler]
        EVENTLOG[Event Logs]
    end
    
    subgraph "ServerMonitor"
        MON[Monitorer]
        PROC[Prosesserer]
        STORE[Lagrer]
    end
    
    subgraph "Output"
        ALERTS[Alerts]
        SNAPS[Snapshots]
        API[REST API]
    end
    
    WIN --> MON
    PERF --> MON
    WMI --> MON
    TASK --> MON
    EVENTLOG --> MON
    
    MON --> PROC
    PROC --> STORE
    STORE --> ALERTS
    STORE --> SNAPS
    STORE --> API
```


