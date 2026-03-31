# DedgeCommon Offline Files

Makes critical configuration files on `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\` available offline using Windows Offline Files (Client-Side Caching / CSC). When `dedge-server` is unreachable, Windows transparently serves cached copies so scripts continue to work.

## Pinned Folders

| UNC Path | Contents | Files |
|----------|----------|------:|
| `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles` | `DatabasesV2.json`, `GlobalSettings.json`, `Applications.json`, `Environments.json`, `ServerMonitorConfig.json`, Resources, etc. | ~53 |
| `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\Db2\ClientConfig` | DB2 client configuration files (catalogs, SSL, Kerberos) | ~131 |
| `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor` | Server monitor configuration | ~9 |

All three paths are under the same `DedgeCommon` SMB share on `dedge-server`.

## Architecture

```
Server (dedge-server)                    Client (workstation or server)
+---------------------------------+          +----------------------------------+
| DedgeCommon share                  |          | CscService (Offline Files)       |
| CachingMode = Manual            |  <---->  | Pins folders for offline access   |
| F:\DedgeCommon\Configfiles\        |   SMB    | Cache: C:\Windows\CSC            |
| F:\DedgeCommon\Software\Config\... |          |                                  |
+---------------------------------+          +----------------------------------+

Server ONLINE  --> Files served from server, cache updated in background
Server OFFLINE --> Files served transparently from local CSC cache
```

## Scripts

| Script | Purpose | Runs on |
|--------|---------|---------|
| `Enable-DedgeCommonOfflineCache-Server.ps1` | Verifies the `DedgeCommon` share has `CachingMode = Manual`. Sets it if not. | `dedge-server` (via autocur) |
| `Enable-DedgeCommonOfflineCache-Client.ps1` | Enables `CscService`, pins the three folders for offline access, forces initial sync. | Each workstation and server that needs offline access |
| `_deploy.ps1` | Deploys scripts to all `*-app` and `*-db` servers via `Deploy-Handler`. | Developer machine |

## How to Run

### 1. Deploy

```powershell
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\InfrastructureTools\DedgeCommon-OfflineFiles\_deploy.ps1"
```

### 2. Server-side (once, via autocur)

Verify the share allows offline caching:

```powershell
. "C:\opt\src\DedgePsh\DevTools\CodingTools\Cursor-ServerOrchestrator\_helpers\_CursorAgent.ps1"

Invoke-ServerCommand -ServerName 'dedge-server' `
    -Command '%OptPath%\DedgePshApps\DedgeCommon-OfflineFiles\Enable-DedgeCommonOfflineCache-Server.ps1' `
    -Project 'DedgeCommon-offline'
```

### 3. Client-side (each machine, once)

**On a workstation (Windows 11):**

```powershell
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\InfrastructureTools\DedgeCommon-OfflineFiles\Enable-DedgeCommonOfflineCache-Client.ps1"
```

Requires elevation (Run as Administrator). On Windows 11, this typically completes in a single run.

**On a server (Windows Server 2025 Datacenter) via autocur:**

```powershell
. "C:\opt\src\DedgePsh\DevTools\CodingTools\Cursor-ServerOrchestrator\_helpers\_CursorAgent.ps1"

Invoke-ServerCommand -ServerName '<server>' `
    -Command '%OptPath%\DedgePshApps\DedgeCommon-OfflineFiles\Enable-DedgeCommonOfflineCache-Client.ps1' `
    -Project 'DedgeCommon-offline'
```

On servers where `CscService` was disabled (typical for Server 2025), the script exits with **code 2** and a message that a reboot is required. After rebooting the server, run the same command again to complete the pinning.

**Custom folder list (optional):**

```powershell
pwsh.exe -NoProfile -File "Enable-DedgeCommonOfflineCache-Client.ps1" `
    -UncPaths @("C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles", "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\SomeOtherFolder")
```

## Server Reboot Flow (Windows Server 2025)

On Windows Server 2025 Datacenter, `CscService` is disabled by default and the CSC driver (`csc.sys`) has three issues that prevent it from loading:

1. **CSC driver `Start` value**: Set to `4` (Disabled) -- must be changed to `1` (System)
2. **CSC minifilter `Instances` key**: Missing entirely -- must be created with `Altitude=180100`
3. **CSC cache database**: Never initialized -- `FormatDatabase=1` in the `Parameters` key triggers initialization on boot

The client script handles all three automatically on first run, then requires a single reboot.

```
First run:
  CscService Disabled -> Set StartupType Automatic -> Start fails
  -> Fix CSC driver: Start=1, create Instances\CSC Instance (Altitude=180100),
     create Parameters\FormatDatabase=1
  -> Save marker file -> Exit code 2 ("reboot required")

  >>> Reboot the server (one time) <<<

Second run:
  CSC driver loaded at boot -> FormatDatabase initializes cache -> CscService Running
  -> Pin all 3 folders -> Sync -> Verify -> Done
  -> Remove marker file -> Exit code 0
```

The marker file is saved at `$env:LOCALAPPDATA\DedgeCommon-OfflineFiles-PendingPin.json` on the target machine.

### Why fltmc / sc start don't work

On a fresh Windows Server 2025 installation where Offline Files was never enabled:
- `fltmc load csc` fails with `0x80070057 (The parameter is incorrect)` -- the CSC filter was never registered with the Filter Manager
- `sc start csc` fails with error 87 -- the driver can't initialize without the `Instances` registry key and cache database
- Simply setting `CscService` to Automatic and rebooting is insufficient -- the kernel driver also needs its own `Start` value changed and filter registration created
- These are boot-time kernel operations that cannot be applied without a reboot

## How to Verify

### Method 1: Explorer Context Menu

1. Open `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\` in Windows Explorer
2. Right-click the `Configfiles` folder
3. **"Always available offline"** should have a checkmark next to it
4. Pinned folders show a green sync overlay icon on the folder

### Method 2: Sync Center (GUI)

1. Open **Control Panel > Sync Center**
2. Click **Manage offline files** (left sidebar)
3. Click **View your offline files**
4. Browse the cached folder tree to confirm `Configfiles`, `Db2\ClientConfig`, and `ServerMonitor` appear

Alternatively, run from a command prompt:

```
control /name Microsoft.SyncCenter
```

### Method 3: PowerShell Service Check

```powershell
# Check CscService is running
Get-Service CscService | Select-Object Status, StartType, DisplayName

# Expected output:
#  Status StartType DisplayName
#  ------ --------- -----------
# Running Automatic Offline Files
```

### Method 4: PowerShell CSC Cache Directory

```powershell
# Verify the CSC cache directory exists
Test-Path "$env:SystemRoot\CSC"

# List cached namespaces (if accessible)
Get-ChildItem "$env:SystemRoot\CSC\v2.0.6\namespace" -ErrorAction SilentlyContinue
```

### Method 5: Functional Test (Ultimate Proof)

Read a config file while the server is reachable, then simulate offline and confirm the same path still works:

```powershell
# While server is online -- read and note content
$online = Get-Content "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\GlobalSettings.json" -Raw
Write-Host "File length: $($online.Length) chars"

# Disconnect network or block server (e.g. firewall rule) and try the same path
# Windows CSC transparently serves the cached copy
```

### Method 6: Server-Side Share Verification

Confirm the share allows client-side caching:

```powershell
# On dedge-server (or via autocur)
Get-SmbShare -Name "DedgeCommon" | Select-Object Name, Path, CachingMode

# Expected: CachingMode = Manual
```

## Infrastructure Change: Add-SmbSharedFolder

The `Add-SmbSharedFolder` function in `_Modules\Infrastructure\Infrastructure.psm1` was updated to include an explicit `-CachingMode` parameter (defaults to `Manual`). This ensures the offline caching setting is preserved if the `DedgeCommon` share is ever recreated.

## Limitations

- Offline Files caches files **read-only** when the server is offline. Writes are queued and synced when the server comes back. This is not an issue since `Configfiles` are read-only for clients.
- The cache is **per-user per-machine**. Each developer or service account must run the client script once.
- **Windows Server Core** does not support Offline Files. The script detects this and exits with an error.
- On **Windows Server 2025 Datacenter**, a single reboot is required on first setup. The script automatically configures the CSC driver registry (Start value, filter registration, FormatDatabase) before requesting the reboot.
- Background sync runs approximately every 6 hours when the server is online. Files are also refreshed on each open.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `CscService not found` | Server Core edition or Offline Files feature removed | Not supported on Server Core. Use Desktop Experience. |
| Exit code 2, "reboot required" | CSC driver not loaded (first-time enablement on Server). Script auto-fixes driver Start, filter registration, and FormatDatabase. | Reboot the machine, then re-run the script. |
| `Shell.Application could not open` path | UNC path unreachable or permissions issue | Verify the server is online and the share is accessible. |
| Files not available after server goes down | CscService stopped or files not yet synced | Check `Get-Service CscService`. Re-run the client script. |
| `Always available offline` not in context menu | CscService not running | Run `Start-Service CscService` (elevated) or re-run the client script. |
| Pin succeeded but files not cached | Initial sync still in progress | Wait a few minutes, or check Sync Center for sync status. |
| `fltmc load csc` fails with 0x80070057 | CSC filter not registered with Filter Manager | Run the client script -- it creates the Instances key automatically. Reboot required. |
| `sc start csc` fails with error 87 | CSC driver was never initialized | Run the client script -- it sets FormatDatabase=1. Reboot required. |

## Current Status (2026-03-26)

| Machine | Type | Status |
|---------|------|--------|
| `dedge-server` | Server (share host) | `CachingMode = Manual` -- confirmed, no changes needed |
| Developer workstation (FKGEISTA) | Windows 11 | All 3 folders pinned and synced (193 files total) |
| `t-no1inltst-db` | Windows Server 2025 | All 3 folders pinned and synced (193 files total) |
