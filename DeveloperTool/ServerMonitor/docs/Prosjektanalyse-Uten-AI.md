# ServerMonitor: Prosjektanalyse – Implementering uten AI

## 📋 Sammendrag

Dette dokumentet analyserer hva som hadde vært nødvendig for å implementere ServerMonitor-systemet i en verden uten AI-assistert utvikling. Vi går gjennom omfanget av systemet, tekniske komponenter, designarbeid, og presenterer til slutt en realistisk prosjektplan.

---

## 🏗️ Systemarkitektur

ServerMonitor-løsningen består av **fire hovedapplikasjoner** som sammen utgjør et komplett overvåkingssystem for Windows-servere:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        ServerMonitor Økosystem                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────────────────┐       ┌─────────────────────────────────┐        │
│   │  ServerMonitorAgent │       │     ServerMonitorDashboard      │        │
│   │     (Windows-tjeneste)     │         (Web-applikasjon)         │        │
│   │                     │       │                                 │        │
│   │  • 10 monitorer     │◄─────►│  • Server-oversikt              │        │
│   │  • REST API         │       │  • Sanntidsmetrikker            │        │
│   │  • Varsling         │       │  • Agent-kontroll               │        │
│   │  • Snapshot-eksport │       │  • Konfigurasjonseditorer       │        │
│   └─────────────────────┘       └─────────────────────────────────┘        │
│             ▲                                    ▲                          │
│             │                                    │                          │
│   ┌─────────────────────┐       ┌─────────────────────────────────┐        │
│   │ ServerMonitorTrayIcon│      │  ServerMonitorDashboard.Tray   │        │
│   │   (System tray app)  │      │     (Dashboard i system tray)   │        │
│   │                     │       │                                 │        │
│   │  • Servicekontroll  │       │  • Hurtigtilgang               │        │
│   │  • Automatisk       │       │  • Varsler                     │        │
│   │    oppdatering      │       │                                 │        │
│   │  • Varsler          │       │                                 │        │
│   └─────────────────────┘       └─────────────────────────────────┘        │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 📊 Kodestatistikk

| Filtype | Antall filer | Antall linjer | Beskrivelse |
|---------|--------------|---------------|-------------|
| **C# (.cs)** | 127 | ~24.200 | Backend-logikk, monitorer, tjenester |
| **JavaScript (.js)** | 11 | ~13.800 | Frontend dashboard-interaktivitet |
| **CSS** | 9 | ~9.900 | Styling, dark/light mode, responsivt design |
| **HTML** | 11 | ~3.200 | Dashboard-sider, editorer |
| **PowerShell (.ps1)** | 34 | ~5.200 | Deploy, installasjon, testing |
| **JSON (config)** | 30 | ~4.600 | Konfigurasjon, appsettings |
| **TOTALT** | **222** | **~61.000** | - |

---

## 🔍 Detaljert Komponentanalyse

### 1. ServerMonitorAgent (Windows-tjeneste)

**Hovedformål:** Overvåker serverressurser og sender varsler.

#### Monitorer (10 stk):
| Monitor | Kompleksitet | Beskrivelse |
|---------|-------------|-------------|
| ProcessorMonitor | Høy | CPU-bruk, per-kjerne, top prosesser |
| MemoryMonitor | Medium | RAM-bruk med prosess-tracking |
| VirtualMemoryMonitor | Medium | Pagefile og paging-rate |
| DiskMonitor | Medium | Disk I/O, køtid, responstid |
| DiskSpaceMonitor | Lav | Diskplass per volum |
| NetworkMonitor | Høy | Ping, DNS, TCP-porter |
| UptimeMonitor | Lav | Oppetid, reboot-deteksjon |
| WindowsUpdateMonitor | Medium | Ventende oppdateringer |
| EventLogMonitor | Høy | Real-time EventLog-overvåking |
| ScheduledTaskMonitor | Medium | Scheduled tasks status |
| Db2DiagMonitor | Svært høy | IBM DB2 loggparsing |

#### Varslingskanaler (5 stk):
- SMS (PSWin API)
- E-post (SMTP)
- Windows Event Log
- Fil-basert logging
- WKMonitor (legacy-integrasjon)

#### Tjenester:
- AlertManager med throttling og deduplisering
- SnapshotExporter (JSON + HTML)
- ConfigurationManager med hot-reload
- NotificationRecipientService med tidsplaner
- PerformanceScalingService for ressurssvake servere
- CommonConfigSyncService for sentralisert konfig

### 2. ServerMonitorTrayIcon (Windows Forms)

**Hovedformål:** System tray-applikasjon for lokal servicekontroll.

#### Funksjonalitet:
- **Visuell statusindikator:** Grønn/rød ikon basert på tjenestestatus
- **Servicekontroll:** Start/stopp/restart fra kontekstmeny
- **Automatisk oppdatering:** FileSystemWatcher + polling for trigger-filer
- **Varsler:** Balloon-notifikasjoner for alarmer
- **REST API-klient:** Henter data fra agent
- **Lokal REST API-server:** Port 8997 for fjernkontroll fra Dashboard
- **Versjonssammenligning:** Automatisk reinstallasjon ved ny versjon

#### Avanserte features:
- FontAwesome.Sharp for ikoner
- Win32 API-integrasjon (DestroyIcon)
- Asynkron exception-håndtering
- Trigger-fil signatursporing

### 3. ServerMonitorDashboard (ASP.NET Core Web App)

**Hovedformål:** Sentralt web-dashboard for alle servere.

#### Frontend (SPA-lignende):
- **Hovedvisning:** Sanntidsmetrikker med gauges
- **Serverliste:** Status for alle servere
- **Paneler:** Windows Updates, DB2, Prosesser, Scheduled Tasks, Alerts
- **Control Panel:** Global agent-kontroll
- **Tools Panel:** Konfigurasjonseditorer
- **Dark/Light mode:** Fullstendig temastøtte

#### Backend Services:
- ServerStatusService (background service)
- ComputerInfoService (serverliste)
- SnapshotProxyService (proxy til agenter)
- ConfigEditorService (redigering av sentral konfig)
- ReinstallService (trigger-fil håndtering)
- TrayApiService (kommunikasjon med tray-apper)
- VersionService

#### Editorer:
- Alert Settings Editor (form-basert)
- Notification Settings Editor
- Alert Routing Overview
- Script Runner (admin-verktøy)

### 4. ServerMonitorDashboard.Tray

**Hovedformål:** System tray wrapper for Dashboard-tilgang.

---

## 🛠️ Teknisk Dybde

### Konfigurasjonssystem

Appsettings.json inneholder ~700 linjer med:
- Kestrel-konfigurasjon
- NLog med 5 targets og arkivering
- Eksport-innstillinger med retention
- 5 varslingskanaler med detaljerte settings
- Throttling med per-severity suppression
- 10 monitor-konfigurasjoner med egne thresholds
- 25+ Windows Event-overvåkingsregler
- Performance scaling for lavkapasitets-servere

### Deployment-system

```
Build-And-Publish.ps1
├── Stopper eksisterende prosesser
├── Rydder målmapper
├── Inkrementerer versjon i alle .csproj
├── Kompilerer 4 prosjekter
├── Signerer eksekverbare filer
├── Oppretter trigger-fil for auto-oppdatering
└── Starter Dashboard
```

### Auto-oppdateringssystem

1. **Trigger-filer:**
   - `ReinstallServerMonitor.txt` - Global oppdatering
   - `ReinstallServerMonitor_<SERVERNAME>.txt` - Maskinspesifikk
   - `StartServerMonitor.txt` / `StopServerMonitorTray.txt`
   - `DisableServerMonitor.txt` - Disable-flagg

2. **Versjonshåndtering:**
   - Leser versjon fra trigger-fil
   - Sammenligner med installert versjon
   - Normaliserer versjonsformat (1.0.62 vs 1.0.62.0)
   - Hopper over hvis allerede oppdatert

3. **Installasjonsprosess:**
   - Lukker tray-app
   - Kjører ServerMonitorAgent
   - Starter tjeneste og tray-app på nytt

---

## ⏱️ Tradisjonell Utviklingstid (Uten AI)

### Estimeringsforutsetninger

- **Utviklererfaring:** Senior-nivå med 5+ års .NET-erfaring
- **Domenekunskap:** Moderat kjennskap til Windows-server-administrasjon
- **Arbeidstimer per uke:** 40 timer
- **Inkluderer:** Design, utvikling, testing, dokumentasjon, debugging, research
- **Buffer:** 20% for uforutsette problemer

### Fase 0: Research og Domeneforståelse

Før man i det hele tatt kan begynne å kode, kreves omfattende research:

| Aktivitet | Estimat | Beskrivelse |
|-----------|---------|-------------|
| Windows Event Log research | 5 dager | Identifisere hvilke av tusenvis av Windows-events som er kritiske å overvåke. Krever gjennomgang av Microsoft-dokumentasjon, best practices, og erfaring fra produksjonsmiljøer |
| Windows Performance Counters | 3 dager | Forstå WMI, Performance Counters API, hvilke metrikker som er relevante for CPU, minne, disk |
| SMS Gateway-integrasjon | 2 dager | Forstå PSWin API, autentisering, meldingsformat, feilhåndtering |
| Windows Service-utvikling | 2 dager | Lifecycle, installasjoner, rettigheter, debugging av services |
| IBM DB2 loggformat-forståelse | 8 dager | **Svært komplekst:** Forstå db2diag.log format, message types, severity levels, instance-struktur. Krever tilgang til DB2-dokumentasjon og reelle loggfiler for testing |
| DB2 Message Map-bygging | 5 dager | Kategorisere hundrevis av DB2-meldingstyper, bestemme severity, bygge Db2DiagMessageMap.json |
| Scheduled Task API | 2 dager | Task Scheduler COM API, exit codes, status-tolkninger |
| Windows Update API | 2 dager | WUA (Windows Update Agent) API, pending updates, install history |
| **Subtotal** | **29 dager (6 uker)** | - |

> ⚠️ **Kritisk:** Uten denne research-fasen vil utvikleren bruke enda mer tid på prøving og feiling under implementering.

### Fase 1: Arkitektur og Design

| Aktivitet | Estimat |
|-----------|---------|
| Kravanalyse og spesifikasjon | 3 dager |
| Systemarkitektur-design | 4 dager |
| API-design (REST endpoints) | 2 dager |
| Database/konfig-struktur | 2 dager |
| UI/UX-design for dashboard | 4 dager |
| **Subtotal** | **15 dager (3 uker)** |

### Fase 2: ServerMonitorAgent

| Komponent | Estimat |
|-----------|---------|
| Prosjektoppsett, DI, konfig | 2 dager |
| ProcessorMonitor | 3 dager |
| MemoryMonitor + VirtualMemoryMonitor | 3 dager |
| DiskMonitor + DiskSpaceMonitor | 3 dager |
| NetworkMonitor (ping, DNS, TCP) | 4 dager |
| UptimeMonitor | 1 dag |
| WindowsUpdateMonitor | 3 dager |
| EventLogMonitor (real-time watcher) | 5 dager |
| ScheduledTaskMonitor | 3 dager |
| Db2DiagMonitor (kompleks parsing) | 8 dager |
| AlertManager med throttling | 5 dager |
| SMS-kanal (PSWin API) | 2 dager |
| E-post-kanal (SMTP) | 2 dager |
| EventLog + File-kanaler | 2 dager |
| WKMonitor-integrasjon | 2 dager |
| SnapshotExporter (JSON) | 3 dager |
| SnapshotHtmlExporter | 4 dager |
| REST API (Controllers) | 3 dager |
| ConfigurationManager + hot-reload | 4 dager |
| Windows Service wrapper | 2 dager |
| NotificationRecipientService | 3 dager |
| PerformanceScalingService | 2 dager |
| Testing og debugging | 10 dager |
| **Subtotal** | **75 dager (15 uker)** |

### Fase 3: ServerMonitorTrayIcon

| Komponent | Estimat |
|-----------|---------|
| Windows Forms prosjektoppsett | 1 dag |
| NotifyIcon med kontekstmeny | 2 dager |
| ServiceManager (start/stopp) | 2 dager |
| FontAwesome-ikon integrasjon | 1 dag |
| API-klient (HTTP) | 2 dager |
| FileSystemWatcher for trigger-filer | 3 dager |
| Automatisk oppdateringslogikk | 4 dager |
| Versjonshåndtering og sammenligning | 2 dager |
| Alert-varsler (balloon) | 2 dager |
| REST API-server (port 8997) | 3 dager |
| Testing og edge cases | 5 dager |
| **Subtotal** | **27 dager (5.5 uker)** |

### Fase 4: ServerMonitorDashboard

| Komponent | Estimat |
|-----------|---------|
| ASP.NET Core prosjektoppsett | 1 dag |
| Backend Services (7 stk) | 10 dager |
| Controllers (7 stk) | 5 dager |
| HTML struktur (hovedside + 4 undersider) | 5 dager |
| CSS (light/dark mode, responsivt) | 10 dager |
| JavaScript - hovedlogikk | 8 dager |
| JavaScript - config-editor | 5 dager |
| JavaScript - notification-settings | 5 dager |
| JavaScript - alert-settings | 4 dager |
| JavaScript - script-runner | 3 dager |
| Real-time polling og oppdatering | 3 dager |
| Control Panel modal | 3 dager |
| Testing på tvers av nettlesere | 4 dager |
| **Subtotal** | **66 dager (13 uker)** |

### Fase 5: Dashboard.Tray

| Komponent | Estimat |
|-----------|---------|
| Windows Forms wrapper | 2 dager |
| WebView eller prosess-launch | 1 dag |
| Testing | 1 dag |
| **Subtotal** | **4 dager (1 uke)** |

### Fase 6: DevOps og Deployment

| Aktivitet | Estimat |
|-----------|---------|
| Build-And-Publish.ps1 | 3 dager |
| ServerMonitorAgent | 3 dager |
| Install-ServerMonitorDashboard.ps1 | 2 dager |
| Code signing-integrasjon | 2 dager |
| Trigger-fil system | 2 dager |
| Testskripter | 3 dager |
| Deployment til test-miljø | 2 dager |
| Deployment til produksjon | 3 dager |
| **Subtotal** | **20 dager (4 uker)** |

### Fase 7: Dokumentasjon

| Aktivitet | Estimat |
|-----------|---------|
| README og oppsettguide | 2 dager |
| API-dokumentasjon | 2 dager |
| Konfigurasjonsguide | 2 dager |
| Feilsøkingsguide | 2 dager |
| Arkitekturdokumentasjon | 2 dager |
| **Subtotal** | **10 dager (2 uker)** |

### Fase 8: Prosjektledelse (løpende)

| Aktivitet | Estimat | Beskrivelse |
|-----------|---------|-------------|
| Daglige stand-ups | 25 dager | 15 min/dag × 250 arbeidsdager |
| Sprint-planlegging | 12 dager | 2-ukers sprints, 4t per sprint |
| Retrospektiver | 6 dager | 2t per sprint |
| Stakeholder-møter | 10 dager | Ukentlige statusmøter |
| Dokumentering av beslutninger | 5 dager | Løpende |
| **Subtotal** | **58 dager (~12 uker)** | Fordelt over hele prosjektet |

### Fase 9: Kvalitetssikring og Testing

| Aktivitet | Estimat | Beskrivelse |
|-----------|---------|-------------|
| Enhetstester (unit tests) | 15 dager | For alle monitorer og services |
| Integrasjonstesting | 10 dager | Agent + Dashboard + TrayIcon samspill |
| Ytelsestesting | 5 dager | Minnebruk, CPU under last |
| Sikkerhetstesting | 3 dager | API-sikkerhet, rettigheter |
| Testing på ulike Windows-versjoner | 5 dager | Server 2016, 2019, 2022 |
| Testing i prod-lignende miljø | 8 dager | Reelle servere med DB2, Scheduled Tasks |
| Akseptansetesting med brukere | 5 dager | Godkjenning av funksjonalitet |
| Bug-fixing fra testing | 15 dager | Erfaringsbasert ~20% av testtid |
| **Subtotal** | **66 dager (~13 uker)** | - |

---

### 🔬 Db2DiagMonitor: Spesiell Kompleksitetsanalyse

Db2DiagMonitor fortjener spesiell oppmerksomhet fordi den er **den mest komplekse monitoren**:

| Utfordring | Beskrivelse | Ekstra tid |
|------------|-------------|------------|
| **Loggformat-forståelse** | IBM DB2 bruker et proprietært loggformat med multi-linje entries, timestamps i ulike formater, og nested data | 5 dager |
| **Multi-instance support** | Må finne alle DB2-instanser på serveren dynamisk via Registry og miljøvariabler | 3 dager |
| **Inkrementell parsing** | Må huske siste prosesserte linje på tvers av restarts via environment variables | 3 dager |
| **Message Map** | Bygge Db2DiagMessageMap.json med 100+ meldingstyper og korrekt severity | 5 dager |
| **Encoding-håndtering** | Windows-1252 encoding, spesialtegn i meldinger | 2 dager |
| **Memory management** | Store loggfiler (300MB+) krever streaming og max entries-håndtering | 3 dager |
| **Testing med reelle logger** | Krever tilgang til DB2-servere med produksjonslogger | 5 dager |
| **Edge cases** | Korrupte filer, loggrotasjon, låste filer, nettverksfeil | 4 dager |
| **TOTAL ekstra tid for Db2DiagMonitor** | - | **30 dager** |

> 📝 **Merk:** I tabellen over vises 8 dager for Db2DiagMonitor. Med research-fasen (13 dager) og denne ekstra kompleksiteten (30 dager) = **~51 dager totalt** for DB2-støtte.

---

### Totalsum (Revidert med alle aspekter)

| Fase | Dager | Uker |
|------|-------|------|
| **Fase 0:** Research og Domeneforståelse | 29 | 6 |
| **Fase 1:** Arkitektur og Design | 15 | 3 |
| **Fase 2:** ServerMonitorAgent | 75 | 15 |
| **Fase 3:** ServerMonitorTrayIcon | 27 | 5.5 |
| **Fase 4:** ServerMonitorDashboard | 66 | 13 |
| **Fase 5:** Dashboard.Tray | 4 | 1 |
| **Fase 6:** DevOps og Deployment | 20 | 4 |
| **Fase 7:** Dokumentasjon | 10 | 2 |
| **Fase 8:** Prosjektledelse (løpende) | 58 | 12 |
| **Fase 9:** Kvalitetssikring og Testing | 66 | 13 |
| **Db2DiagMonitor ekstra kompleksitet** | 30 | 6 |
| **TOTAL** | **400 dager** | **~80 uker** |

**Med 20% buffer for uforutsette problemer:** ~480 dager ≈ **96 uker (~2 år)**

> ⚠️ **Opprinnelig estimat (uten research, PM, grundig testing):** 217 dager
> 
> **Realistisk estimat (komplett prosjekt):** 400-480 dager

---

## 💰 Kostnadsvurdering (Revidert)

### Ressursbehov

> ⚠️ **Viktig forutsetning:** De fleste tekniske ressurser vil måtte leies inn som **eksterne konsulenter** til ~1.500 kr/time, da det er vanskelig å finne og ansette spesialistkompetanse på Windows-overvåking, .NET-utvikling og DB2-integrasjon for et enkeltprosjekt. Kun prosjektleder antas å være intern ansatt.

#### Konsulentressurser (1.500 kr/time, 7,5 timer/dag)

| Rolle | Andel | Dager | Timer | Timepris | Kostnad |
|-------|-------|-------|-------|----------|---------|
| Senior .NET-utvikler | 100% | 400 | 3.000 | 1.500 kr | **4.500.000 NOK** |
| DevOps/Infrastruktur | 25% | 100 | 750 | 1.500 kr | **1.125.000 NOK** |
| UI/UX Designer | 30% | 60 | 450 | 1.500 kr | **675.000 NOK** |
| QA/Testressurs | 50% | 132 | 990 | 1.500 kr | **1.485.000 NOK** |
| **Subtotal konsulenter** | - | - | **5.190** | - | **7.785.000 NOK** |

#### Intern ressurs (ansatt)

| Rolle | Andel | Måneder | Årskostnad | Kostnad |
|-------|-------|---------|------------|---------|
| Prosjektleder | 25% | 20 | 1.200.000 NOK | **500.000 NOK** |

#### Total personalkostnad

| | |
|---|---|
| Konsulenter | 7.785.000 NOK |
| Interne ansatte | 500.000 NOK |
| **TOTAL personalkostnader** | **~8.285.000 NOK** |

### Indirekte kostnader

| Kostnad | Beløp |
|---------|-------|
| Utviklerverktøy og lisenser (Visual Studio, JetBrains, etc.) | 50.000 NOK |
| Testmiljø (servere, nettverk, lagring) | 100.000 NOK |
| IBM DB2-lisenser for testing | 150.000 NOK |
| Code signing-sertifikat | 10.000 NOK |
| Dokumentasjonsverktøy | 10.000 NOK |
| Konsulentadministrasjon og onboarding | 100.000 NOK |
| Uforutsette kostnader (15%) | 1.300.000 NOK |
| **TOTAL indirekte** | **~1.720.000 NOK** |

### Totalt prosjektbudsjett

| | |
|---|---|
| Konsulenter | 7.785.000 NOK |
| Interne ansatte (prosjektleder) | 500.000 NOK |
| Indirekte kostnader | 1.720.000 NOK |
| **TOTALT** | **~10.000.000 NOK** |

> 💡 **Sammenligning:** 
> - Naivt estimat (uten research, PM, testing): ~2 MNOK
> - Realistisk med interne ansatte: ~4.5 MNOK
> - **Realistisk med konsulenter: ~10 MNOK**

### Hvorfor konsulenter?

| Utfordring | Forklaring |
|------------|------------|
| **Spesialistkompetanse** | Windows-overvåking, WMI, Performance Counters, Windows Service-utvikling krever nisje-ekspertise |
| **IBM DB2** | Svært få har erfaring med DB2-loggparsing og diagnostikk |
| **Prosjektvarighet** | 20 måneder er for kort til å ansette og for lang til å la være |
| **Rekrutteringstid** | Å finne og ansette en senior .NET-utvikler tar 3-6 måneder |
| **Risiko** | Konsulenter reduserer risiko ved å kunne byttes ut hvis de ikke leverer |

---

## 📅 Detaljert Prosjektplan

### Gantt-diagram (Realistisk ~20 måneder)

```
Måned:  1    2    3    4    5    6    7    8    9    10   11   12   13   14   15   16   17   18   19   20
        ├────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┤
Fase 0: ████████                                                                             Research
Fase 1:      ████                                                                            Design
Fase 2:          ████████████████████████████                                                Agent
Fase 3:                                      ████████                                        TrayIcon
Fase 4:                              ████████████████████████████                            Dashboard
Fase 5:                                                      ████                            Dash.Tray
Fase 6:                                                  ████████████                        DevOps
Fase 7:                                                              ████████                Dokument.
Fase 8: ──────────────────────────────────────────────────────────────────────────────────── PM (løpende)
Fase 9:              ────────────────────────────────────────────────────────────████████████ Testing
DB2:         ████████████████████████                                                        DB2 spesial
```

### Milepæler

| Milepæl | Måned | Leveranser |
|---------|-------|------------|
| M0: Research Complete | 2 | Domeneforståelse, API-kunnskap, event-liste |
| M1: Design Complete | 3 | Arkitekturdok, API-spesifikasjon, UI-mockups |
| M2: Agent MVP | 7 | Agent med 5 monitorer, fil-varsling |
| M3: Agent + DB2 Complete | 10 | Alle 10 monitorer, inkl. Db2DiagMonitor |
| M4: TrayIcon Complete | 12 | Full tray-funksjonalitet med auto-oppdatering |
| M5: Dashboard MVP | 13 | Grunnleggende dashboard, serverliste |
| M6: Dashboard Complete | 16 | Alle editorer, control panel, script runner |
| M7: System Integration Test | 17 | Alle komponenter fungerer sammen |
| M8: Deployment Ready | 18 | Full deploy-pipeline, auto-oppdatering fungerer |
| M9: Beta-testing | 19 | Pilot-installasjon på utvalgte servere |
| M10: Production Release | 20 | Dokumentasjon komplett, aksepttest godkjent |

---

## 🚧 Risikoer og Utfordringer

### Tekniske risikoer

| Risiko | Sannsynlighet | Konsekvens | Tiltak |
|--------|--------------|------------|--------|
| Windows API-endringer | Medium | Høy | Grundig testing på flere Windows-versjoner |
| DB2 logg-format endringer | Høy | Medium | Konfigurerbar parsing-logikk |
| Performance-problemer | Medium | Høy | Tidlig ytelsestesting, performance scaling |
| Nettverksfeil (UNC-paths) | Høy | Medium | Fallback-mekanismer, retry-logikk |

### Prosjektrisikoer

| Risiko | Sannsynlighet | Konsekvens | Tiltak |
|--------|--------------|------------|--------|
| Scope creep | Høy | Høy | Streng endringskontroll |
| Ressursmangel | Medium | Høy | Cross-training, dokumentasjon |
| Integrasjonsproblemer | Medium | Medium | Tidlig integrasjonstesting |

---

## 🎯 Konklusjon

### Uten AI ville dette prosjektet kreve:

- **1 senior utvikler (konsulent) på fulltid i ~20 måneder**
- **Støtteressurser (konsulenter):** DevOps, Designer, QA
- **Intern prosjektleder** på 25% i hele perioden
- **Total kostnad med konsulenter: ~10 millioner NOK**
- **61.000+ linjer kode skrevet manuelt**
- **127 C#-filer med avansert logikk**
- **Omfattende research:** 6 uker bare på domeneforståelse
- **50+ dager** på DB2-monitor alene
- **66 dager** grundig kvalitetssikring og testing
- **Løpende prosjektledelse** gjennom hele prosjektet

### Nøkkelutfordringer uten AI:

1. **Research-tid:** Hundrevis av timer på Microsoft-dokumentasjon, Windows Event IDs, IBM DB2-loggformat, Performance Counters APIer.

2. **Event-identifisering:** Finne hvilke av tusenvis av Windows-events som faktisk er viktige å overvåke. Krever erfaring og eksperimentering.

3. **DB2-kompleksitet:** Forstå IBM DB2s proprietære loggformat, bygge message map med 100+ meldingstyper, håndtere edge cases.

4. **Boilerplate-kode:** Manuell skriving av CRUD-operasjoner, API-endepunkter, modellklasser, DTOs.

5. **CSS/JavaScript:** Tusenvis av linjer med styling, dark/light mode, responsivt design, interaktive elementer.

6. **Feilhåndtering:** Identifisering av edge cases: async exceptions, race conditions, memory leaks, network failures på UNC-paths.

7. **Testing:** Enhetstester, integrasjonstester, ytelsestester på ulike Windows-versjoner, testing med reelle DB2-servere.

8. **Prosjektledelse:** Møter, planlegging, stakeholder-kommunikasjon, dokumentering av beslutninger.

### Med AI-assistanse:

Utviklingstiden kan reduseres med **70-85%**, da AI kan:
- **Generere boilerplate-kode** i sekunder istedenfor timer
- **Identifisere Windows Event IDs** basert på beskrivelse av hva man vil overvåke
- **Foreslå DB2-loggformat parsing** basert på eksempler
- **Skrive CSS/JavaScript** for komplekse UI-komponenter
- **Identifisere potensielle feil** før de oppstår (race conditions, memory issues)
- **Generere enhetstester** automatisk
- **Forklare dokumentasjon** og APIer uten manuell lesing
- **Hjelpe med regex, parsing, kompleks logikk** umiddelbart

### Sammenligning

| Aspekt | Uten AI (konsulenter) | Med AI |
|--------|----------------------|--------|
| **Utviklingstid** | ~20 måneder | ~3-4 måneder |
| **Kostnad** | **~10 MNOK** | ~1-1.5 MNOK |
| **Konsulent-timer** | 5.190 timer | ~500-750 timer |
| **Research-tid** | 6 uker | ~1 uke |
| **Testing-skriving** | 15 dager | ~2-3 dager |
| **CSS/JS for Dashboard** | 10 uker | ~1-2 uker |
| **DB2-monitor** | 50+ dager | ~5-7 dager |

### ROI-analyse

| Scenario | Kostnad | Besparelse |
|----------|---------|------------|
| Tradisjonell utvikling (konsulenter) | 10.000.000 NOK | Baseline |
| AI-assistert utvikling | 1.500.000 NOK | **8.500.000 NOK (85%)** |

> 🎯 **Konklusjon:** AI-assistert utvikling gir en besparelse på ~8.5 MNOK og reduserer prosjekttiden fra 20 måneder til 3-4 måneder.

---

## 📎 Appendiks: Hva er inkludert i estimatene

### ✅ Nå inkludert (etter revisjon):

- [x] **Research-fase:** 29 dager for domeneforståelse
- [x] **Windows Event research:** Finne hvilke av tusenvis av events som er viktige
- [x] **DB2Diag spesial-kompleksitet:** 30 ekstra dager for denne monitoren
- [x] **Prosjektledelse:** 58 dager for møter, planlegging, status
- [x] **Grundig testing:** 66 dager for unit, integrasjon, akseptanse
- [x] **Alle 10 monitorer** med individuell estimering
- [x] **Frontend-utvikling:** CSS, JavaScript, responsivt design
- [x] **DevOps:** Build-scripts, deploy-pipelines, code signing
- [x] **Auto-oppdatering:** Trigger-fil system, versjonshåndtering

### ⚠️ Potensielle tilleggsfaktorer (ikke inkludert):

- [ ] Opplæring av supportpersonell
- [ ] Brukeropplæring og onboarding
- [ ] Vedlikehold etter produksjon (år 2+)
- [ ] Endringshåndtering i organisasjonen
- [ ] Sikkerhetsgodkjenning/penetrasjonstesting
- [ ] Compliance-dokumentasjon (hvis påkrevd)

---

*Dokument opprettet: Januar 2026*
*Sist oppdatert: 22. januar 2026 (revidert med testing, PM, research)*
