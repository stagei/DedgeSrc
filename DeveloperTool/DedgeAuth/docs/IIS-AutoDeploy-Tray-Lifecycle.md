# IIS-AutoDeploy.Tray — Lifecycle & Architecture

## Overview

The IIS-AutoDeploy.Tray is a Windows Forms system tray application that monitors published app binaries and deploy templates for changes, then automatically triggers `IIS-DeployApp.ps1` to redeploy affected IIS sites. It also self-updates when a newer MSI is available.

---

## End-to-End Flow

```mermaid
flowchart TD
    subgraph DEV["Developer Machine"]
        BAP["Build-And-Publish.ps1"]
        BAP -->|"1. Version bump"| VER["Version 1.0.X → 1.0.X+1<br/>(shared: DedgeAuth.Api + Tray)"]
        VER -->|"2. dotnet publish"| PUB_API["Publish DedgeAuth.Api<br/>→ staging share"]
        VER -->|"3. dotnet publish + WiX build"| PUB_TRAY["Publish Tray App<br/>Build MSI installer"]
        PUB_TRAY -->|"4. Copy MSI only"| STAGING_TRAY["\\\\server\\DedgeCommon\\Software\\<br/>DedgeWinApps\\IIS-AutoDeploy-Tray\\<br/>IIS-AutoDeploy.Tray.Setup.msi"]
        PUB_API -->|"4. Copy binaries"| STAGING_API["\\\\server\\DedgeCommon\\Software\\<br/>DedgeWinApps\\DedgeAuth\\<br/>(DLLs, EXE, wwwroot)"]
    end

    subgraph SERVER["App Server (dedge-server)"]
        REDEPLOY["IIS-RedeployAll.ps1"]
        DEPLOY_SITE["IIS-DeployApp.ps1<br/>-SiteName DedgeAuth"]
        INSTALL_WINAPP["Install-OurWinApp<br/>'IIS-AutoDeploy-Tray'"]
        MSIEXEC["msiexec /i MSI /qn"]
        DEPLOY_TRAY_PS["Deploy-IIS-AutoDeploy-Tray.ps1"]
        SCHED_TASK["Scheduled Task:<br/>IIS-AutoDeploy-Tray"]
        RUN_KEY["Registry Run Key:<br/>HKCU\\...\\Run"]
        TRAY_EXE["IIS-AutoDeploy.Tray.exe<br/>(system tray)"]
    end

    STAGING_TRAY --> REDEPLOY
    STAGING_API --> REDEPLOY

    REDEPLOY -->|"Step 1: Deploy all IIS sites"| DEPLOY_SITE
    DEPLOY_SITE -->|"AdditionalWinApps in template"| INSTALL_WINAPP
    INSTALL_WINAPP -->|"Copies MSI to local<br/>OptPath\\DedgeWinApps\\IIS-AutoDeploy-Tray"| LOCAL_MSI["Local MSI copy"]
    REDEPLOY -->|"Step 2: Install/update tray"| MSIEXEC
    MSIEXEC -->|"Installs exe, creates shortcuts"| TRAY_EXE
    MSIEXEC -->|"Writes auto-start entry"| RUN_KEY
    REDEPLOY -->|"Step 3 (if -DeployTray)"| DEPLOY_TRAY_PS
    DEPLOY_TRAY_PS -->|"Creates logon task"| SCHED_TASK

    RUN_KEY -->|"At user logon"| TRAY_EXE
    SCHED_TASK -->|"At logon +10s delay<br/>(via Launcher script)"| TRAY_EXE
```

---

## Installation: What the MSI Does

```mermaid
flowchart LR
    MSI["IIS-AutoDeploy.Tray.Setup.msi"]

    MSI --> CLOSE["CloseApplication<br/>Stop running tray exe"]
    MSI --> FILES["Install files to<br/>[%OptPath]\\DedgeWinApps\\IIS-AutoDeploy-Tray\\"]
    MSI --> RUNKEY["Registry Run Key<br/>HKCU\\SOFTWARE\\Microsoft\\<br/>Windows\\CurrentVersion\\Run<br/>'IIS Auto-Deploy Tray' = exe path"]
    MSI --> STARTMENU["Start Menu shortcut<br/>Dedge folder"]
    MSI --> DESKTOP["Desktop shortcut"]
    MSI --> LAUNCH["LaunchTrayApp<br/>Start exe immediately<br/>after install"]
```

| Component | Details |
|---|---|
| **Install location** | `%OptPath%\DedgeWinApps\IIS-AutoDeploy-Tray\` |
| **Files** | `IIS-AutoDeploy.Tray.exe`, `appsettings.json`, `dedge.ico`, launcher/deploy scripts, DLLs |
| **Auto-start** | `HKCU\...\Run` registry key (starts at every user logon) |
| **Shortcuts** | Start Menu (Dedge folder) + Desktop |
| **Pre-install** | Kills running `IIS-AutoDeploy.Tray.exe` via WiX `CloseApplication` |
| **Post-install** | Launches the exe immediately |

---

## Two Startup Paths

```mermaid
flowchart TD
    LOGON["User Logon"]

    LOGON --> PATH_A["Path A: Registry Run Key<br/>(installed by MSI)"]
    LOGON --> PATH_B["Path B: Scheduled Task<br/>(created by Deploy-IIS-AutoDeploy-Tray.ps1)"]

    PATH_A -->|"Direct exe launch"| TRAY["IIS-AutoDeploy.Tray.exe"]
    PATH_B -->|"ONLOGON trigger, 10s delay"| LAUNCHER["IIS-AutoDeploy-Tray-Launcher.ps1"]
    LAUNCHER -->|"Starts exe in loop<br/>(restarts on crash after 5s)"| TRAY

    TRAY --> MUTEX{"Mutex check:<br/>IIS-AutoDeploy-Tray<br/>_SingleInstance"}
    MUTEX -->|"Already running"| EXIT["Exit (second instance blocked)"]
    MUTEX -->|"First instance"| RUN["Run tray app"]
```

| Path | Created by | Behavior |
|---|---|---|
| **Registry Run key** | MSI installer | Direct exe launch at logon |
| **Scheduled Task** | `Deploy-IIS-AutoDeploy-Tray.ps1` | 10s delay, uses launcher script that auto-restarts on crash |
| **Mutex** | Tray app itself | Only one instance runs regardless of how many startup paths trigger |

---

## Surveillance & Auto-Deploy

```mermaid
flowchart TD
    TRAY["Tray App Running"]

    TRAY -->|"Every PollIntervalSeconds<br/>(default: 30s)"| POLL["Poll two locations"]

    POLL --> WATCH_APPS["Watch: DedgeWinApps staging share<br/>\\\\server\\DedgeCommon\\Software\\DedgeWinApps\\*"]
    POLL --> WATCH_TEMPLATES["Watch: Deploy templates<br/>OptPath\\DedgePshApps\\IIS-DeployApp\\templates\\*.deploy.json"]

    WATCH_APPS -->|"For each subfolder:<br/>check max LastWriteTime + total size"| STABLE_CHECK{"Stable for<br/>StabilitySeconds?<br/>(default: 240s)"}
    WATCH_TEMPLATES -->|"Compare LastWriteTime<br/>with templates-state.json"| TEMPLATE_CHANGE{"Template<br/>changed?"}

    STABLE_CHECK -->|"Not stable yet"| WAIT["Wait for next poll"]
    STABLE_CHECK -->|"Stable (4 min unchanged)"| MAP_SITE["Map folder → SiteName<br/>(via deploy template InstallAppName)"]

    TEMPLATE_CHANGE -->|"No change"| WAIT
    TEMPLATE_CHANGE -->|"Changed"| MAP_SITE

    MAP_SITE --> DEPLOY["Run IIS-DeployApp.ps1<br/>-SiteName <site>"]
    DEPLOY --> SELF_UPDATE["SelfReinstallFromMsi()<br/>(after all deploys complete)"]

    SELF_UPDATE --> VERSION_CHECK{"Running version<br/>= MSI version?"}
    VERSION_CHECK -->|"Same"| SKIP["Skip reinstall"]
    VERSION_CHECK -->|"Different"| MSIEXEC["msiexec /i MSI /qn<br/>(detached process)"]
    MSIEXEC -->|"MSI kills running tray"| RESTART["New version starts<br/>(via MSI post-install action)"]
```

### Key details

| Setting | Default | Purpose |
|---|---|---|
| `PollIntervalSeconds` | 30 | How often to scan for changes |
| `StabilitySeconds` | 240 (4 min) | How long files must be unchanged before triggering deploy |
| `FilePattern` | `DedgeAuth*.dll` | Which files to monitor for changes |

---

## Self-Update Mechanism

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant Staging as Staging Share
    participant Tray as Tray App (running)
    participant MSI as msiexec.exe

    Dev->>Staging: Build-And-Publish.ps1<br/>copies new MSI (v1.0.135)
    Note over Staging: \\server\DedgeCommon\Software\<br/>DedgeWinApps\IIS-AutoDeploy-Tray\<br/>IIS-AutoDeploy.Tray.Setup.msi

    Staging-->>Tray: Tray detects DedgeAuth DLL change<br/>in DedgeWinApps staging
    Tray->>Tray: RunDeploysSequentially()<br/>deploys changed IIS sites

    Tray->>Tray: SelfReinstallFromMsi()<br/>Compare running v1.0.134 vs MSI v1.0.135
    Note over Tray: Version mismatch detected

    Tray->>MSI: Process.Start("msiexec /i MSI /qn")<br/>(detached, fire-and-forget)
    MSI->>Tray: CloseApplication kills tray exe
    MSI->>MSI: Install new files (v1.0.135)
    MSI->>Tray: LaunchTrayApp starts new exe
    Note over Tray: Now running v1.0.135
```

### Three triggers for self-update

| Trigger | Method | When |
|---|---|---|
| **After deploys** | `SelfReinstallFromMsi()` | Automatically at end of every deploy batch |
| **Manual menu click** | `LaunchSelfUpdate()` | User clicks "Update Available" in tray menu |
| **Menu refresh** | `RefreshUpdateMenuState()` | Every ~5 minutes, updates the menu label to show version diff |

---

## Does IIS-DeployApp Update the Tray?

```mermaid
flowchart LR
    subgraph "IIS-DeployApp.ps1 -SiteName DedgeAuth"
        DEPLOY["Deploy-IISSite"]
        DEPLOY -->|"AdditionalWinApps<br/>from DedgeAuth_WinApp.deploy.json"| INSTALL["Install-OurWinApp<br/>'IIS-AutoDeploy-Tray'"]
        INSTALL -->|"Copies files from staging<br/>to local OptPath"| COPY["Copies MSI to local disk<br/>(does NOT run it)"]
    end

    subgraph "IIS-RedeployAll.ps1"
        RA["Full redeploy all sites"]
        RA --> RA_MSI["msiexec /i MSI /qn<br/>(runs the MSI!)"]
        RA --> RA_TASK["Deploy-IIS-AutoDeploy-Tray.ps1<br/>(if -DeployTray)"]
    end
```

| Script | Updates tray? | How |
|---|---|---|
| `IIS-DeployApp.ps1 -SiteName DedgeAuth` | **Partially** — copies MSI to local disk only | Via `AdditionalWinApps` in the DedgeAuth deploy template; runs `Install-OurWinApp` which copies files but does NOT run the MSI |
| `IIS-RedeployAll.ps1` | **Yes** — runs the MSI silently | Explicitly calls `msiexec /i <msi> /qn` after deploying all sites |
| Tray app itself | **Yes** — self-updates | `SelfReinstallFromMsi()` runs after every deploy batch if MSI version is newer |

**Bottom line**: `IIS-DeployApp.ps1` only stages the MSI locally. The tray app updates itself via its own `SelfReinstallFromMsi()` or when `IIS-RedeployAll.ps1` explicitly runs the MSI.

---

## Process Hierarchy

```mermaid
flowchart TD
    subgraph "User Session (logon)"
        EXPLORER["explorer.exe"]
        EXPLORER -->|"Registry Run key<br/>or Scheduled Task"| TRAY["IIS-AutoDeploy.Tray.exe<br/>(elevated via app.manifest)"]

        TRAY -->|"On detected changes"| PWSH["pwsh.exe -File<br/>IIS-DeployApp.ps1 -SiteName X"]
        TRAY -->|"After deploys"| MSIEXEC["msiexec.exe /i MSI /qn<br/>(self-update)"]
        TRAY -->|"On failure"| SMS["Send-Sms notification"]

        MSIEXEC -->|"CloseApplication"| KILL["Kills IIS-AutoDeploy.Tray.exe"]
        MSIEXEC -->|"LaunchTrayApp"| TRAY_NEW["New IIS-AutoDeploy.Tray.exe<br/>(updated version)"]
    end
```

---

## File Locations

| Item | Path |
|---|---|
| **Source code** | `C:\opt\src\DedgeAuth\src\IIS-AutoDeploy.Tray\` |
| **WiX installer project** | `C:\opt\src\DedgeAuth\src\IIS-AutoDeploy.Tray.Installer\` |
| **Staging (MSI published here)** | `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\IIS-AutoDeploy-Tray\` |
| **Local install (from MSI)** | `%OptPath%\DedgeWinApps\IIS-AutoDeploy-Tray\` |
| **Settings** | `%OptPath%\DedgeWinApps\IIS-AutoDeploy-Tray\appsettings.json` |
| **Deploy script** | `%OptPath%\DedgePshApps\IIS-DeployApp\IIS-DeployApp.ps1` |
| **Deploy templates** | `%OptPath%\DedgePshApps\IIS-DeployApp\templates\*.deploy.json` |
