# Install Client Applications (Quick Guide)

Please run the following commands:

```powershell
Import-Module SoftwareUtils -Force
Install-OurWinApp -AppName "DedgeRemoteConnect"
Install-OurWinApp -AppName "ServerMonitorDashboard.Tray"
Install-WindowsApps -AppName "DbExplorer"
```

## What each command does

- `Install-OurWinApp -AppName "DedgeRemoteConnect"`
  - Installs the DedgeRemoteConnect Windows desktop application from the central software share.
  - DedgeRemoteConnect is a system tray app for managing Remote Desktop (RDP) connections to all FK servers. It reads a central server list, groups connections by environment, handles secure credential storage (Windows DPAPI), and supports multi-monitor and clipboard settings.
  - Result: Shortcut on Desktop and Start Menu. The app starts in the system tray and gives one-click RDP access to all registered servers.

- `Install-OurWinApp -AppName "ServerMonitorDashboard.Tray"`
  - Installs the ServerMonitorDashboard tray icon application from the central software share.
  - This is a Windows Forms system tray app that connects to the ServerMonitor Dashboard web service. It shows live alert status in the notification area, lets you open the dashboard in the browser, and allows authorized users to send commands to the server monitor.
  - Result: A tray icon appears in the system notification area showing the current alert state of all monitored servers.

- `Install-OurWinApp -AppName "DbExplorer"`
  - Installs DbExplorer, a modern WPF-based DB2 database editor for Windows.
  - DbExplorer provides a DBeaver-like experience for IBM DB2: SQL editor with syntax highlighting and auto-formatting, database browser with schema/table navigation, query history, multi-format export (CSV, TSV, JSON, SQL), dark/light theme, and multiple simultaneous connections via tabs. Uses Net.IBM.Data.Db2 — no separate DB2 client required.
  - Result: DbExplorer.exe is installed and ready to connect to any DB2 database.

## Expected overall result

After running all three installs:

- You can connect to any FK server via RDP directly from the system tray (DedgeRemoteConnect).
- You get live server health status and dashboard access from the system tray (ServerMonitorDashboard.Tray).
- You have a full-featured DB2 query and schema editor available locally (DbExplorer).
