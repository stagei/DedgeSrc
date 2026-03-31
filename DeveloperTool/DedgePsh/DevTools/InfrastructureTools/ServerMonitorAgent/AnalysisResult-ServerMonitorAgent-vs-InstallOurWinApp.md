# Evaluation: ServerMonitorAgent.ps1 vs Install-OurWinApp

**Date:** 2026-02-20

---

## 1. Is ServerMonitorAgent.ps1 still needed?

**Yes — it remains necessary.** `Install-OurWinApp` now handles the generic service lifecycle
(stop → copy → register → start). But `ServerMonitorAgent.ps1` does things that are specific
to the ServerMonitor application and cannot be generalized:

| Responsibility | Install-OurWinApp | ServerMonitorAgent.ps1 |
|---|:---:|:---:|
| Stop service + kill process before copy | ✅ | ✅ |
| Robocopy from staging | ✅ | ❌ (uses Install-OurWinApp internally) |
| sc.exe create + failure restart policy | ✅ | ✅ |
| .NET 10 Desktop + ASP.NET Core runtime install | ❌ | ✅ |
| Kill TrayIcon first (avoids agent restart) | ❌ | ✅ |
| Firewall rules (port 8999 inbound+outbound) | ❌ | ✅ |
| Firewall rules (port 8997 tray API) | ❌ | ✅ |
| URL ACL (`netsh http add urlacl` port 8997) | ❌ | ✅ |
| Port conflict detection before start | ❌ | ✅ |
| Delayed auto-start via registry | ❌ | ✅ |
| Deprecation cleanup of old tasks/folders | ❌ | ✅ |

**Conclusion:** `ServerMonitorAgent.ps1` should stay. The overlap (stop/kill/register) is now
handled more robustly by `Install-OurWinApp`, so `ServerMonitorAgent.ps1` could delegate that
step to `Install-OurWinApp` eventually — but its app-specific steps are irreplaceable.

---

## 2. Can Install-OurWinApp auto-detect the port a C# app uses?

**Partially — but not reliably enough for automatic use.**

Possible detection approaches and their limitations:

| Method | Feasibility | Risk |
|---|:---:|---|
| Parse `appsettings.json` → `Urls` or `Kestrel.Endpoints` | Medium | Not all apps use this key; some use env vars or code |
| Parse `launchSettings.json` → `applicationUrl` | Low | Dev-only file, not deployed to staging |
| Query `Get-NetTCPConnection` after start | Low | Race condition; port may not be bound yet |
| Read `ASPNETCORE_URLS` env var from service config | Medium | Requires reading registry service env block |

**Verdict: Do not auto-detect in `Install-OurWinApp`.** The detection is app-specific and
fragile across different project configurations. Embedding it in the generic installer adds
complexity without a reliable contract.

---

## 3. Recommended pattern: Firewall via _install.ps1

**Best approach.** `Infrastructure.psm1` contains no firewall helper functions
(confirmed: `New-NetFirewallRule`, `Add-NetFirewallRule` — no wrappers exist).
Use raw `New-NetFirewallRule` directly in a per-app `_install.ps1`.

**Separation of concerns:**
- `Install-OurWinApp` → generic: stop, copy, sc.exe register, start
- `_install.ps1` → app-specific: firewall rules, URL ACLs, runtime installs, port config

**Example _install.ps1 pattern for a service with a known port:**

```powershell
param([string]$AppPath, [string]$AppName)

$port = 8999
$ruleName = "${AppName}_RestApi"

# Remove stale rules
Get-NetFirewallRule -DisplayName "${ruleName}_Inbound" -ErrorAction SilentlyContinue |
    Remove-NetFirewallRule -ErrorAction SilentlyContinue
Get-NetFirewallRule -DisplayName "${ruleName}_Outbound" -ErrorAction SilentlyContinue |
    Remove-NetFirewallRule -ErrorAction SilentlyContinue

New-NetFirewallRule -DisplayName "${ruleName}_Inbound" -Direction Inbound `
    -Protocol TCP -LocalPort $port -Action Allow -Profile Domain,Private | Out-Null
New-NetFirewallRule -DisplayName "${ruleName}_Outbound" -Direction Outbound `
    -Protocol TCP -LocalPort $port -Action Allow -Profile Domain,Private | Out-Null

Write-LogMessage "$($AppName): Firewall rules set for port $($port)" -Level INFO
```

> **Note:** `Install-OurWinApp` currently skips `_install.ps1` when it detects a Windows
> service (sets `$serviceInstalled = $true`). If firewall config is needed post-service-start,
> `_install.ps1` execution must be enabled even for service apps, or the firewall logic must
> live in `ServerMonitorAgent.ps1` (which is fine for ServerMonitor's case).

---

## Summary

| Question | Answer |
|---|---|
| Still need `ServerMonitorAgent.ps1`? | **Yes** — app-specific steps can't be generalized |
| Auto-detect port in `Install-OurWinApp`? | **No** — too fragile; no reliable contract |
| Firewall via `_install.ps1`? | **Yes** — cleanest separation of concerns |
