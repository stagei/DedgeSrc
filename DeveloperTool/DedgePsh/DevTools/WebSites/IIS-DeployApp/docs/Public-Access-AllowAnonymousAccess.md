# Public Access for IIS Virtual Applications

**Author:** Geir Helge Starholm, www.dEdge.no  
**Created:** 2026-03-16  
**Technology:** IIS / PowerShell

---

## Overview

The IIS-DeployApp system supports deploying virtual applications that are publicly accessible — no Windows login prompt, no credentials required. This is controlled by the `AllowAnonymousAccess` flag in the deploy template or as a script parameter.

When enabled, the deploy process:

1. **Enables Anonymous Authentication** on the virtual application path
2. **Sets anonymous identity to App Pool Identity** (not IUSR)
3. **Disables Windows Authentication** on the virtual application path
4. **Grants IUSR read access** to the physical folder (belt-and-suspenders)

---

## How to Use

### Deploy Template

Add `"AllowAnonymousAccess": true` to the deploy template JSON:

```json
{
  "SiteName": "GitHist",
  "PhysicalPath": "$env:OptPath\\Webs\\GitHist",
  "AppType": "Static",
  "InstallSource": "None",
  "VirtualPath": "/GitHist",
  "ParentSite": "Default Web Site",
  "AllowAnonymousAccess": true,
  "ApiPort": 0
}
```

### Script Parameter

Pass `-AllowAnonymousAccess:$true` directly:

```powershell
pwsh.exe -NoProfile -File ".\IIS-DeployApp.ps1" -SiteName GitHist -AllowAnonymousAccess:$true
```

The template value is only applied when the parameter is not explicitly passed on the command line. Explicit parameters always win.

---

## What Happens During Deploy (Step 6b)

The deploy process executes three `appcmd` commands targeting the virtual application path (e.g. `Default Web Site/GitHist`):

| Step | appcmd Command | Purpose |
|------|----------------|---------|
| 1 | `set config ... /section:.../anonymousAuthentication /enabled:true /commit:apphost` | Enable anonymous auth |
| 2 | `set config ... /section:.../anonymousAuthentication /userName: /commit:apphost` | Use app pool identity for anonymous requests |
| 3 | `set config ... /section:.../windowsAuthentication /enabled:false /commit:apphost` | Disable Windows auth (removes login prompt) |

After the authentication changes, NTFS permissions are granted:

| Identity | Permission | Scope |
|----------|------------|-------|
| `IIS AppPool\<AppPoolName>` | ReadAndExecute | Already set in Step 6 |
| `IUSR` | ReadAndExecute | Set in Step 6b as fallback |

---

## Why `/commit:apphost` Is Required

The `anonymousAuthentication` and `windowsAuthentication` configuration sections are **locked by default** in IIS at the `applicationHost.config` level (`overrideModeDefault="Deny"`).

Without `/commit:apphost`, appcmd attempts to write to the site-level `web.config`, which is blocked by the lock. The command fails silently — IIS returns an error about a locked section, but if output is suppressed, the failure goes unnoticed.

The `/commit:apphost` flag writes the configuration directly into `applicationHost.config` using a `<location path="Default Web Site/AppName">` block, which bypasses the lock.

### Resulting applicationHost.config Entry

After deploy, IIS stores:

```xml
<location path="Default Web Site/GitHist">
    <system.webServer>
        <security>
            <authentication>
                <anonymousAuthentication enabled="true" userName="" />
                <windowsAuthentication enabled="false" />
            </authentication>
        </security>
    </system.webServer>
</location>
```

---

## Default Behavior

| Setting | Default | Effect |
|---------|---------|--------|
| `AllowAnonymousAccess` omitted | `$false` | Inherits parent site auth (typically Windows Auth) |
| `AllowAnonymousAccess: true` | Public | Anonymous enabled, Windows Auth disabled |

All existing deploy templates that do not specify `AllowAnonymousAccess` are unaffected — they continue to use Windows Authentication as before.

---

## Troubleshooting

### 401 Unauthorized After Deploy

| Check | How |
|-------|-----|
| Anonymous Auth enabled? | IIS Manager → Sites → Default Web Site → AppName → Authentication |
| Windows Auth disabled? | Same location — should show "Disabled" |
| NTFS permissions? | `icacls "$env:OptPath\Webs\GitHist"` — look for `IIS AppPool\GitHist` and `IUSR` |
| App pool running? | `appcmd list apppool GitHist` — state should be "Started" |
| Physical path exists? | `Test-Path "$env:OptPath\Webs\GitHist"` |

### Manual Fix (if deploy didn't apply auth)

```powershell
$appcmd = "$env:SystemRoot\System32\inetsrv\appcmd.exe"

& $appcmd set config "Default Web Site/GitHist" `
    /section:system.webServer/security/authentication/anonymousAuthentication `
    /enabled:true /commit:apphost

& $appcmd set config "Default Web Site/GitHist" `
    /section:system.webServer/security/authentication/anonymousAuthentication `
    /userName: /commit:apphost

& $appcmd set config "Default Web Site/GitHist" `
    /section:system.webServer/security/authentication/windowsAuthentication `
    /enabled:false /commit:apphost
```

### Verify Configuration

```powershell
& $appcmd list config "Default Web Site/GitHist" /section:anonymousAuthentication
& $appcmd list config "Default Web Site/GitHist" /section:windowsAuthentication
```

---

## Affected Files

| File | Role |
|------|------|
| `_Modules/IIS-Handler/IIS-Handler.psm1` | `Deploy-IISSite` function, Step 6b implementation |
| `DevTools/WebSites/IIS-DeployApp/IIS-DeployApp.ps1` | Script parameter `AllowAnonymousAccess` |
| `DevTools/WebSites/IIS-DeployApp/templates/*.deploy.json` | Template field `AllowAnonymousAccess` |
