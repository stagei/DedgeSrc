# ServerMonitor Scheduled Task Audit

## Overview

This document audits all code in the ServerMonitor project that creates Windows Scheduled Tasks, verifies if each is needed, and explains why.

---

## Summary

| Location | Task Name | Status | Needed? | Purpose |
|----------|-----------|--------|---------|---------|
| `ServerMonitorAgent.ps1` | `ServerMonitorTrayIcon` | ✅ ACTIVE | ✅ YES | Starts tray app at user logon |
| `ServerMonitorDashboard.ps1` | `ServerMonitorDashboard.Tray` | ✅ ACTIVE | ✅ YES | Starts dashboard tray at user logon |
| `ServerMonitorAgent\_install.ps1` | `DevTools\ServerMonitorAgent` | ✅ ACTIVE | ⚠️ REVIEW | Runs install script daily at 00:01 |
| `ServerMonitorDashboard\_install.ps1` | `DevTools\ServerMonitorDashboard` | ✅ ACTIVE | ⚠️ REVIEW | Runs install script daily at 00:01 |
| ~~`TrayApp-Startup-Functions.ps1`~~ | N/A | 🗑️ DELETED | N/A | Was unused - deleted 2026-01-27 |
| `Installation-Routine-Design.md` | N/A | 📄 DOCS ONLY | N/A | Documentation examples only |

---

## Detailed Analysis

### 1. ServerMonitorAgent.ps1 - TrayIcon Startup Task

**File**: `C:\opt\src\DedgePsh\DevTools\InfrastructureTools\ServerMonitorAgent\ServerMonitorAgent.ps1`

**Task Name**: `ServerMonitorTrayIcon`

**Code**:
```powershell
$schtasksArgs = @(
    '/Create'
    '/TN', $taskName                    # ServerMonitorTrayIcon
    '/TR', "`"$trayIconPath`""          # Path to exe
    '/SC', 'ONLOGON'                    # Trigger: any user logs on
    '/RL', 'HIGHEST'                    # Run level: admin privileges
    '/IT'                               # Interactive (visible tray icon)
    '/DELAY', '0000:10'                 # 10 second delay after logon
    '/F'                                # Force overwrite
)
$result = & schtasks.exe @schtasksArgs 2>&1
```

**Purpose**: Starts `ServerMonitorTrayIcon.exe` when any user logs on to the server.

**Why It's Needed**:
| Reason | Explanation |
|--------|-------------|
| **Auto-start for ALL users** | Registry Run key only works for the installing user |
| **Admin privileges** | `/RL HIGHEST` runs with elevated privileges (no UAC) |
| **Interactive session** | `/IT` ensures tray icon appears in notification area |
| **Startup delay** | `/DELAY 0000:10` allows desktop to fully load |
| **Trigger file monitoring** | TrayIcon watches for `ReinstallServerMonitor.txt` to auto-update |

**Verdict**: ✅ **NEEDED** - Essential for tray app functionality

---

### 2. ServerMonitorDashboard.ps1 - Dashboard Tray Startup Task

**File**: `C:\opt\src\DedgePsh\DevTools\InfrastructureTools\ServerMonitorDashboard\ServerMonitorDashboard.ps1`

**Task Name**: `ServerMonitorDashboard.Tray`

**Code**:
```powershell
$schtasksArgs = @(
    '/Create'
    '/TN', $dashboardTrayTaskName       # ServerMonitorDashboard.Tray
    '/TR', "`"$dashboardTrayPath`""     # Path to exe
    '/SC', 'ONLOGON'                    # Trigger: any user logs on
    '/RL', 'HIGHEST'                    # Run level: admin privileges
    '/IT'                               # Interactive (visible tray icon)
    '/DELAY', '0000:10'                 # 10 second delay after logon
    '/F'                                # Force overwrite
)
$result = & schtasks.exe @schtasksArgs 2>&1
```

**Purpose**: Starts `ServerMonitorDashboard.Tray.exe` when any user logs on.

**Why It's Needed**:
| Reason | Explanation |
|--------|-------------|
| **Auto-start for ALL users** | Same as above - Registry Run is user-specific |
| **Admin privileges** | Needed for dashboard control functionality |
| **Interactive session** | Tray icon must be visible to user |
| **Trigger file monitoring** | Watches for `ReinstallServerMonitorDashboard.txt` |
| **Quick dashboard access** | Provides right-click menu to open dashboard |

**Verdict**: ✅ **NEEDED** - Essential for dashboard tray functionality

---

### 3. _install.ps1 Files - Daily Install Script Execution

**Files**: 
- `C:\opt\src\DedgePsh\DevTools\InfrastructureTools\ServerMonitorAgent\_install.ps1`
- `C:\opt\src\DedgePsh\DevTools\InfrastructureTools\ServerMonitorDashboard\_install.ps1`

**Task Names**: `DevTools\ServerMonitorAgent` and `DevTools\ServerMonitorDashboard`

**Code** (identical in both files):
```powershell
Import-Module ScheduledTask-Handler -Force
Import-Module Infrastructure -Force

if (Test-IsServer) {
    New-ScheduledTask -SourceFolder $PSScriptRoot -TaskFolder "DevTools" -RecreateTask $true -RunFrequency "Daily" -StartHour 0 -StartMinute 01 -RunAsUser $false
}
```

**Purpose**: Creates a scheduled task that runs the install script **daily at 00:01**.

**What It Does**:
1. `New-ScheduledTask` from `ScheduledTask-Handler` module
2. Creates task in `Task Scheduler > DevTools` folder
3. Runs `ServerMonitorAgent.ps1` or `ServerMonitorDashboard.ps1` daily at midnight + 1 minute
4. Only runs on servers (`Test-IsServer`)

**Why It Might Be Needed**:
| Reason | Explanation |
|--------|-------------|
| **Daily auto-update check** | Ensures servers pull latest version daily |
| **Self-healing** | Reinstalls if something breaks |
| **Catch missed updates** | If trigger file missed, daily run catches up |

**Why It Might NOT Be Needed**:
| Reason | Explanation |
|--------|-------------|
| **Service already monitors trigger files** | `ReinstallTriggerService` in both services now |
| **Tray apps monitor trigger files** | FileSystemWatcher for real-time updates |
| **Redundant** | Two other mechanisms already handle updates |
| **Runs at inconvenient time** | 00:01 might conflict with batch jobs |

**Verdict**: ⚠️ **REVIEW NEEDED** - Potentially redundant with `ReinstallTriggerService`

**Recommendation**: 
- **Option A**: Keep for defense-in-depth (belt and suspenders)
- **Option B**: Remove if trigger file mechanism is proven reliable
- **Option C**: Change to weekly instead of daily

---

### 4. TrayApp-Startup-Functions.ps1 - Helper Module

**File**: `ServerMonitorAgent\Install\TrayApp-Startup-Functions.ps1`

**Code** (excerpt):
```powershell
function Register-TrayAppStartupTask {
    # Uses Register-ScheduledTask cmdlet (not schtasks.exe)
    $action = New-ScheduledTaskAction -Execute $ExePath -WorkingDirectory $workingDir
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -GroupId "BUILTIN\Users" -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet ...
    
    Register-ScheduledTask -TaskName $TaskName -Action $action ...
}
```

**Status**: ❌ **NOT USED**

**Why It Exists**: Was created as a helper module for scheduled task creation, but the install scripts use `schtasks.exe` directly instead.

**Evidence It's Unused**:
1. No `Import-Module TrayApp-Startup-Functions` in any install script
2. Install scripts call `schtasks.exe` directly (see items 1 and 2 above)
3. Uses `Register-ScheduledTask` cmdlet which had compatibility issues

**Verdict**: ❌ **NOT NEEDED** - Can be deleted or kept for future reference

---

### 5. Installation-Routine-Design.md - Documentation Only

**File**: `ServerMonitorAgent\docs\Installation-Routine-Design.md`

**Status**: 📄 **DOCUMENTATION ONLY**

Contains example PowerShell code for scheduled task creation, but this is documentation and design reference, not active code.

**Verdict**: N/A - Not executable code

---

## Verification Commands

### List All ServerMonitor Scheduled Tasks

```powershell
Get-ScheduledTask | Where-Object { 
    $_.TaskName -match 'ServerMonitor' -or 
    $_.TaskPath -match 'DevTools' 
} | Format-Table TaskName, TaskPath, State
```

### Expected Output

```
TaskName                       TaskPath              State
--------                       --------              -----
ServerMonitorTrayIcon          \                     Ready
ServerMonitorDashboard.Tray    \                     Ready
ServerMonitorAgent             \DevTools\            Ready
ServerMonitorDashboard         \DevTools\            Ready
```

### Check Task Details

```powershell
# Check TrayIcon task
Get-ScheduledTaskInfo -TaskName "ServerMonitorTrayIcon"

# Check Dashboard.Tray task
Get-ScheduledTaskInfo -TaskName "ServerMonitorDashboard.Tray"

# Check DevTools tasks
Get-ScheduledTask -TaskPath "\DevTools\" | Get-ScheduledTaskInfo
```

---

## Recommendations

### Keep (Essential)

| Task | Reason |
|------|--------|
| `ServerMonitorTrayIcon` | Required for tray app to start at login |
| `ServerMonitorDashboard.Tray` | Required for dashboard tray to start at login |

### Review (Potentially Redundant)

| Task | Current | Recommendation |
|------|---------|----------------|
| `DevTools\ServerMonitorAgent` | Runs daily at 00:01 | Consider removing - `ReinstallTriggerService` handles updates |
| `DevTools\ServerMonitorDashboard` | Runs daily at 00:01 | Consider removing - `ReinstallTriggerService` handles updates |

### Deleted (Was Unused)

| File | Reason | Status |
|------|--------|--------|
| `TrayApp-Startup-Functions.ps1` | Not imported anywhere, uses incompatible cmdlets | 🗑️ Deleted 2026-01-27 |

---

## Current Update Mechanisms

The ServerMonitor project now has **three** update mechanisms:

| Mechanism | When Active | How It Works |
|-----------|-------------|--------------|
| **1. ReinstallTriggerService** (in services) | Always (services running) | Polls trigger file every 10s, launches install |
| **2. FileSystemWatcher** (in tray apps) | When user logged in | Real-time detection, shows notification, launches install |
| **3. Daily Scheduled Task** (_install.ps1) | Daily at 00:01 | Runs full install script regardless of trigger file |

**Analysis**: Mechanisms 1 and 2 are event-driven (trigger file appears → update runs). Mechanism 3 is time-based (runs every day regardless).

**Redundancy**: If mechanisms 1 and 2 are working correctly, mechanism 3 is redundant except for:
- Catching missed updates (if trigger file was deleted before detection)
- Self-healing (if service crashed before processing trigger)
- Defense-in-depth

---

## Conclusion

| Category | Count | Action |
|----------|-------|--------|
| ✅ Essential | 2 | Keep - TrayIcon and Dashboard.Tray startup tasks |
| ⚠️ Review | 2 | Evaluate - Daily install tasks may be redundant |
| 🗑️ Deleted | 1 | Done - TrayApp-Startup-Functions.ps1 removed |

---

*Document created: 2026-01-27*
*Author: Automated audit*
