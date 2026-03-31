# Installer klientapplikasjoner (hurtigguide)

Vennligst kjør følgende kommandoer:

```powershell
Import-Module SoftwareUtils -Force
Install-OurWinApp -AppName "DedgeRemoteConnect"
Install-OurWinApp -AppName "ServerMonitorDashboard.Tray"
Install-WindowsApps -AppName "DbExplorer"
```

## Hva hvert kommando gjør

- `Install-OurWinApp -AppName "DedgeRemoteConnect"`
  - Installerer Windows-applikasjonen DedgeRemoteConnect fra den sentrale programvaredelen.
  - DedgeRemoteConnect er en system tray-app for å administrere Remote Desktop (RDP)-tilkoblinger til alle FK-servere. Den leser en sentral serverliste, grupperer tilkoblinger etter miljø, håndterer sikker lagring av innloggingsdetaljer (Windows DPAPI) og støtter flermonitor- og utklippstavleinnstillinger.
  - Resultat: Snarvei på skrivebordet og i Start-menyen. Appen starter i systemstatusfeltet og gir ett-klikk RDP-tilgang til alle registrerte servere.

- `Install-OurWinApp -AppName "ServerMonitorDashboard.Tray"`
  - Installerer tray-ikonapplikasjonen ServerMonitorDashboard fra den sentrale programvaredelen.
  - Dette er en Windows Forms system tray-app som kobler seg til ServerMonitor Dashboard-webtjenesten. Den viser live varselstatus i systemstatusfeltet, lar deg åpne dashboardet i nettleseren, og gir autoriserte brukere mulighet til å sende kommandoer til serverovervåkeren.
  - Resultat: Et tray-ikon vises i systemstatusfeltet med gjeldende varselstatus for alle overvåkede servere.

- `Install-OurWinApp -AppName "DbExplorer"`
  - Installerer DbExplorer, en moderne WPF-basert DB2-databaseeditor for Windows.
  - DbExplorer gir en DBeaver-lignende opplevelse for IBM DB2: SQL-editor med syntaksuthevning og autoformatering, databasenettleser med skjema- og tabellnavigasjon, spørringshistorikk, eksport i flere formater (CSV, TSV, JSON, SQL), mørk/lys tema og flere samtidige tilkoblinger via faner. Bruker Net.IBM.Data.Db2 — ingen separat DB2-klient er nødvendig.
  - Resultat: DbExplorer.exe er installert og klar til å koble til enhver DB2-database.

## Forventet samlet resultat

Etter at alle tre installasjoner er kjørt:

- Du kan koble til enhver FK-server via RDP direkte fra systemstatusfeltet (DedgeRemoteConnect).
- Du får live serverhelsestatus og dashboardtilgang fra systemstatusfeltet (ServerMonitorDashboard.Tray).
- Du har en fullverdig DB2-spørrings- og skjemaeditor tilgjengelig lokalt (DbExplorer).
