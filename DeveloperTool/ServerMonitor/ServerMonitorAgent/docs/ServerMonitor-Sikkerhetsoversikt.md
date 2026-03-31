# ServerMonitor - Sikkerhetsoversikt

## Formål

ServerMonitor er et internt utviklet overvåkingsverktøy for Dedges servere. Systemet består av en Windows-tjeneste som samler inn helsedata, og en webapplikasjon for visualisering.

---

## Kildekode (Azure DevOps)

For kodegjennomgang, se følgende repositories:

| Repository | Innhold | URL |
|------------|---------|-----|
| **ServerMonitor** | C#-applikasjoner (Agent, Dashboard, TrayIcons) | https://dev.azure.com/Dedge/Dedge/_git/ServerMonitor |
| **DedgePsh** | PowerShell installasjonsscript | https://dev.azure.com/Dedge/Dedge/_git/DedgePsh |

### Relevante mapper i DedgePsh

| Sti | Innhold |
|-----|---------|
| `DevTools/InfrastructureTools/ServerMonitorAgent/` | Installasjonsscript for Agent og TrayIcon |
| `DevTools/InfrastructureTools/ServerMonitorDashboard/` | Installasjonsscript for Dashboard og Dashboard.Tray |

---

## Distribusjonsplasseringer (DedgeCommon)

Kompilerte applikasjoner og script distribueres via nettverksshare:

### Applikasjoner (.exe)

| Applikasjon | Nettverksshare |
|-------------|----------------|
| **ServerMonitor** | `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitor\` |
| **ServerMonitorTrayIcon** | `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitorTrayIcon\` |
| **ServerMonitorDashboard** | `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitorDashboard\` |
| **ServerMonitorDashboard.Tray** | `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\ServerMonitorDashboard.Tray\` |

### PowerShell-script

| Script | Nettverksshare |
|--------|----------------|
| **ServerMonitorAgent.ps1** | `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgePshApps\ServerMonitorAgent\` |
| **ServerMonitorDashboard.ps1** | `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgePshApps\ServerMonitorDashboard\` |

### Konfigurasjonsfiler

| Fil | Nettverksshare |
|-----|----------------|
| **appsettings.ServerMonitorAgent.json** | `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor\` |
| **NotificationRecipients.json** | `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor\` |

---

## Potensielle servere (Azure)

ServerMonitor Agent kan installeres på følgende Azure-servere (kilde: `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\ConfigFiles\ComputerInfo.json`):

### Produksjonsservere (PRD)

| Server | Miljø | Beskrivelse |
|--------|-------|-------------|
| p-no1batch-vm01 | PRD | Batch-server |
| p-no1docprd-db | PRD | CobDoc Database Server |
| p-no1fkmprd-app | PRD | Dedge Production Server |
| p-no1fkmprd-db | PRD | Dedge Production Database Server |
| p-no1fkmprd-mcl | PRD | Fk-Meny Server for håndterminaler |
| p-no1fkmprd-pos | PRD | Point Of Sale Server |
| p-no1fkmprd-soa | PRD | Dedge Production SOA Server |
| p-no1fkmprd-web | PRD | Dedge Production Web Server |
| p-no1fkmrap-db | PRD | Dedge Production Report Database Server |
| p-no1fkxprd-app | PRD | Fkx Production Server |
| p-no1fkxprd-db | PRD | Fkx Production database server |
| p-no1hstprd-db | PRD | HST Production Database Server |
| p-no1inlprd-app | PRD | Innlån Production Application Server |
| p-no1inlprd-db | PRD | Innlån Production Database Server |
| p-no1qvp-rep01 | PRD | QVP Replication Server |
| p-no1visprd-db | PRD | Visma Database Server |
| sfk-soa-web-01 | PRD | SOA Web Server |

### Testservere (TST/DEV/etc.)

| Server | Miljø | Beskrivelse |
|--------|-------|-------------|
| t-no1batch-vm01 | TST | Batch-server (test) |
| t-no1fkmdev-db | DEV | Dedge Development Database Server |
| t-no1fkmfsp-app | VFT, VFK, MIG, SIT, PER, FUT, KAT | Dedge Shared Server Forsprang |
| t-no1fkmfut-db | FUT | Dedge Forsprang Funksjonstest Database Server |
| t-no1fkmkat-db | KAT | Dedge Forsprang Kvalitets-test Database Server |
| t-no1fkmmig-db | MIG | Dedge Forsprang Migration Database Server |
| t-no1fkmper-db | PER | Dedge Performance Database Server |
| t-no1fkmsit-db | SIT | Dedge System Integration Test Database Server |
| t-no1fkmtst-app | TST | Dedge Test Server |
| t-no1fkmtst-db | TST | Dedge Test Database Server |
| t-no1fkmtst-pos | TST | Point Of Sale Server (test) |
| t-no1fkmtst-soa | TST | Dedge Test SOA Server |
| t-no1fkmtst-web | TST | Dedge Test Web Server |
| t-no1fkmvfk-db | VFK | Dedge Verification Database Server |
| t-no1fkmvft-db | VFT | Dedge Verification Test Database Server |
| dedge-server | TST | Fkx Test Server |
| t-no1fkxtst-db | TST | Fkx Test database server |
| t-no1inldev-db | DEV | Innlån Development Database Server |
| t-no1inltst-app | TST | Innlån Test Server |
| t-no1inltst-db | TST | Innlån Test Database Server |
| t-no1qvp-rep01 | TST | QVP Replication Server (test) |

**Totalt: 38 Azure-servere**

---

## Installasjonsstier

### Miljøvariabel

| Variabel | Nåværende verdi | Planlagt endring |
|----------|-----------------|------------------|
| `$env:OptPath` | `E:\opt` | Kan bli `F:\opt` på DB2-servere |

### Eksekverbare filer (.exe)

| Applikasjon | Installasjonssti | Beskrivelse |
|-------------|------------------|-------------|
| **ServerMonitor.exe** | `$env:OptPath\DedgeWinApps\ServerMonitor\` | Windows-tjeneste for overvåking |
| **ServerMonitorTrayIcon.exe** | `$env:OptPath\DedgeWinApps\ServerMonitorTrayIcon\` | Systemtray-applikasjon for agenten |
| **ServerMonitorDashboard.exe** | `$env:OptPath\DedgeWinApps\ServerMonitorDashboard\` | Web-dashboard (ASP.NET Core) |
| **ServerMonitorDashboard.Tray.exe** | `$env:OptPath\DedgeWinApps\ServerMonitorDashboard.Tray\` | Systemtray-applikasjon for dashboard |

**Konkret eksempel på full sti:**
- `E:\opt\DedgeWinApps\ServerMonitor\ServerMonitor.exe`
- `E:\opt\DedgeWinApps\ServerMonitorTrayIcon\ServerMonitorTrayIcon.exe`

---

## PowerShell Installasjonsscript

Installasjonsscriptene kjøres fra nettverksshare og kopierer applikasjonsfiler til lokal server.

| Script | Plassering (nettverksshare) | Lokal kopi |
|--------|----------------------------|------------|
| **ServerMonitorAgent.ps1** | `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgePshApps\ServerMonitorAgent\` | `$env:OptPath\DedgePshApps\ServerMonitorAgent\` |
| **ServerMonitorDashboard.ps1** | `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgePshApps\ServerMonitorDashboard\` | `$env:OptPath\DedgePshApps\ServerMonitorDashboard\` |

### Hva gjør scriptene?

**ServerMonitorAgent.ps1:**
1. Installerer `ServerMonitor` Windows-tjeneste (port 8999)
2. Installerer `ServerMonitorTrayIcon` systemtray-app
3. Oppretter planlagt oppgave for TrayIcon-oppstart
4. Konfigurerer brannmurregler
5. Oppretter snarveier på skrivebord og Start-meny

**ServerMonitorDashboard.ps1:**
1. Installerer `ServerMonitorDashboard` Windows-tjeneste (port 8998)
2. Installerer `ServerMonitorDashboard.Tray` systemtray-app
3. Oppretter planlagt oppgave for Dashboard.Tray-oppstart
4. Konfigurerer brannmurregler
5. Oppretter snarveier på skrivebord og Start-meny

---

## Planlagte oppgaver (Scheduled Tasks)

### Oppgave 1: ServerMonitorTrayIcon

| Egenskap | Verdi |
|----------|-------|
| **Navn** | `ServerMonitorTrayIcon` |
| **Trigger** | Ved brukerinnlogging (alle brukere) |
| **Kjører som** | Innlogget bruker med administratorrettigheter |
| **Formål** | Starter systemtray-appen når en bruker logger inn |
| **Interaktiv** | Ja - viser ikon i systemtray |

**Hvorfor nødvendig:** Gir brukeren visuell tilgang til ServerMonitor-status og hurtigmeny for å åpne dashboard, se logger, og starte oppdateringer.

### Oppgave 2: ServerMonitorDashboard.Tray

| Egenskap | Verdi |
|----------|-------|
| **Navn** | `ServerMonitorDashboard.Tray` |
| **Trigger** | Ved brukerinnlogging (alle brukere) |
| **Kjører som** | Innlogget bruker med administratorrettigheter |
| **Formål** | Starter dashboard systemtray-appen når en bruker logger inn |
| **Interaktiv** | Ja - viser ikon i systemtray |

**Hvorfor nødvendig:** Gir brukeren rask tilgang til web-dashboardet via høyreklikkmeny i systemtray.

---

## Windows-tjenester

| Tjeneste | Port | Oppstart | Formål |
|----------|------|----------|--------|
| **ServerMonitor** | 8999 | Automatisk (forsinket) | Samler inn serverhelsedata, genererer varsler |
| **ServerMonitorDashboard** | 8998 | Automatisk (forsinket) | Viser web-dashboard, autentiserer brukere via AD |

---

## Nettverkskommunikasjon

| Port | Protokoll | Retning | Formål |
|------|-----------|---------|--------|
| 8999 | HTTP | Inngående | REST API for ServerMonitor Agent |
| 8998 | HTTP | Inngående | Web Dashboard |

---

## Sikkerhetsfunksjoner

- **Windows-autentisering (Negotiate/Kerberos)** for dashboard-tilgang
- **AD-gruppebasert tilgangskontroll** (FullAccess / Standard / Blocked)
- **Kodesignering** av alle .exe og .dll filer med Dedges sertifikat
- **Tjenestekonto** kjører under domenekonto, ikke LocalSystem

---

## Kontakt

For spørsmål om ServerMonitor, kontakt:
- **Geir Helge Starholm** - geir.helge.starholm@Dedge.no

---

*Dokument opprettet: 2026-01-27*
*Relatert til: Sikkerhetsgjennomgang av ServerMonitor*
