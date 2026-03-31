# Dashboard Service Account Fix

## Problem Summary

The `ServerMonitorDashboard` Windows Service was incorrectly configured to run as **LocalSystem**, which cannot access UNC/network paths. This broke access to centralized configuration files like `ComputerInfo.json`.

### What Went Wrong

1. **Dashboard install script uses LocalSystem** - The `ServerMonitorDashboard.ps1` install script was set to use `LocalSystem` account (lines 351-354):
   ```powershell
   # Use LocalSystem account - it can make HTTP calls to remote agents
   # Note: ComputerInfo.json is copied locally so no UNC access is needed
   $serviceAccount = "LocalSystem"
   ```

2. **Workaround that breaks centralization** - To "fix" the UNC access issue, another agent added logic to copy `ComputerInfo.json` locally during installation:
   ```powershell
   # Copy ComputerInfo.json locally (service runs as LocalSystem, can't access UNC)
   $remoteComputerInfoPath = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\ConfigFiles\ComputerInfo.json"
   $localComputerInfoPath = "$configDir\ComputerInfo.json"
   Copy-Item $remoteComputerInfoPath -Destination $localComputerInfoPath -Force
   ```

3. **This defeats the purpose of centralized config** - The whole point of having `ComputerInfo.json` on a network share is that it's a **single source of truth**. When you update the central file, all services should see the changes immediately. Copying locally means:
   - Changes to the central file are NOT reflected
   - Each server has a stale copy
   - Reinstallation is required to get updates

---

## The Correct Solution

### Use Domain Account (Like the Agent Does)

The `ServerMonitorAgent.ps1` install script correctly uses a **domain account** with credentials:

```powershell
# Get current user and create credentials
$currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$currentUser = $currentIdentity.Name

# Format as DEDGE\username
$serviceAccount = "$domain\$username"

# Get password using the function
$password = Get-SecureStringUserPasswordAsPlainText

# Create credential object
$securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($serviceAccount, $securePassword)

# Create service WITH credentials
New-Service -Name $ServiceName -Credential $credential ...
```

### Benefits of Domain Account

| Feature | LocalSystem | Domain Account |
|---------|-------------|----------------|
| UNC Path Access | ❌ No | ✅ Yes |
| HTTP to Remote Agents | ✅ Yes | ✅ Yes |
| Centralized Config | ❌ Requires local copy | ✅ Direct access |
| Config Updates | ❌ Stale until reinstall | ✅ Immediate |

---

## Changes Required (REVERT + FIX)

### REVERT: Remove the Local Copy Workaround

The following changes made on 2026-01-27 must be **reverted** because they defeat the purpose of centralized configuration:

**In `ServerMonitorDashboard.ps1`**, remove this section (lines ~303-340):
```powershell
# ❌ DELETE THIS SECTION - it copies config locally which defeats centralization
# Copy ComputerInfo.json locally (service runs as LocalSystem, can't access UNC)
$configDir = "$exeDir\Config"
if (-not (Test-Path $configDir)) {
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
}

$remoteComputerInfoPath = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\ConfigFiles\ComputerInfo.json"
$localComputerInfoPath = "$configDir\ComputerInfo.json"

if (Test-Path $remoteComputerInfoPath) {
    Copy-Item $remoteComputerInfoPath -Destination $localComputerInfoPath -Force
}

# Also remove the appsettings.json modification that sets local paths
$appSettings.Dashboard.ComputerInfoPath = $localComputerInfoPath  # ❌ DELETE
```

### 1. Revert `appsettings.json` to Use Network Path

**File**: `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor\appsettings.ServerMonitorDashboard.json`

Change `ComputerInfoPath` back to the UNC path:
```json
{
  "Dashboard": {
    "ComputerInfoPath": "\\dedge-server\\DedgeCommon\\ConfigFiles\\ComputerInfo.json",
    ...
  }
}
```

### 2. Update `ServerMonitorDashboard.ps1` Install Script

**File**: `C:\opt\src\DedgePsh\DevTools\InfrastructureTools\ServerMonitorDashboard\ServerMonitorDashboard.ps1`

#### Changes:

1. **Remove the local copy logic** (lines ~303-340):
   - Delete the section that copies `ComputerInfo.json` locally
   - Delete the section that modifies `appsettings.json` to use local paths

2. **Add domain credential retrieval** (before service creation):
   ```powershell
   # Get current user and create credentials (same as Agent)
   $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
   $currentUser = $currentIdentity.Name
   
   if ($currentUser.Contains('\')) {
       $userParts = $currentUser.Split('\')
       $domain = $userParts[0]
       $username = $userParts[1]
   }
   else {
       $domain = "DEDGE"
       $username = $currentUser
   }
   
   $serviceAccount = "$domain\$username"
   
   $password = Get-SecureStringUserPasswordAsPlainText
   $securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
   $credential = New-Object System.Management.Automation.PSCredential($serviceAccount, $securePassword)
   ```

3. **Use `New-Service` with credentials** instead of `sc.exe create`:
   ```powershell
   New-Service -Name $ServiceName `
       -BinaryPathName $absoluteExePath `
       -DisplayName $DisplayName `
       -Description $Description `
       -StartupType Automatic `
       -Credential $credential `
       -ErrorAction Stop
   ```

4. **Update the summary** to show the domain account instead of "LocalSystem"

### 3. Deploy Updated Install Script

After making changes:
```powershell
C:\opt\src\DedgePsh\DevTools\InfrastructureTools\ServerMonitorDashboard\_deploy.ps1
```

### 4. Reinstall Dashboard on Affected Servers

Run the updated install script on each server where the Dashboard is installed.

---

## Comparison: Agent vs Dashboard Install Scripts

| Aspect | ServerMonitorAgent.ps1 | ServerMonitorDashboard.ps1 (Current) | ServerMonitorDashboard.ps1 (Fixed) |
|--------|------------------------|--------------------------------------|-----------------------------------|
| Service Account | `DEDGE\username` | `LocalSystem` | `DEDGE\username` |
| Credential Source | `Get-SecureStringUserPasswordAsPlainText` | N/A | `Get-SecureStringUserPasswordAsPlainText` |
| Service Creation | `New-Service -Credential` | `sc.exe create` | `New-Service -Credential` |
| UNC Access | ✅ Yes | ❌ No | ✅ Yes |
| Local Config Copy | No | Yes (workaround) | No |

---

## Files to Modify

1. `C:\opt\src\DedgePsh\DevTools\InfrastructureTools\ServerMonitorDashboard\ServerMonitorDashboard.ps1`
2. `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\ServerMonitor\appsettings.ServerMonitorDashboard.json`

## Files to NOT Modify (Source of Truth)

- `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\ConfigFiles\ComputerInfo.json` - This is the centralized config and should remain on the network share

---

## Additional Issues Caused by LocalSystem

### Issue 2: User Access & Logs Shows "Error loading configuration"

**Symptom**: The "User Access & Logs" page shows "Error loading configuration" for all sections (FullAccess, Standard, Blocked).

**Root Cause**: The `/api/auth/config` endpoint requires "FullAccess" to view configuration:

```csharp
// From Program.cs line 296-305
app.MapGet("/api/auth/config", (HttpContext context) =>
{
    var user = context.User;
    var currentAuthEnabled = authSettings.AuthEnabled;
    var accessLevel = authSettings.IsUserBlocked(user) ? "blocked" : authSettings.GetAccessLevel(user);
    
    if (currentAuthEnabled && accessLevel != "full")
    {
        return Results.Json(new { error = "FullAccess required" }, statusCode: 403);
    }
    // ...
});
```

**Why it fails with LocalSystem**:
- Windows Authentication (Negotiate/Kerberos) requires the **service** to have a valid network identity
- LocalSystem has **no network identity** - it cannot validate Kerberos tickets properly
- Result: `context.User.Identity.IsAuthenticated` is `false` → accessLevel = "none" → 403 Forbidden

### Issue 3: Username Not Showing at Top of Dashboard

**Symptom**: The user info badge (showing `⭐ username`) doesn't appear in the header.

**Root Cause**: The `/api/auth/me` endpoint can't authenticate the user:

```csharp
// From Program.cs line 263-278
app.MapGet("/api/auth/me", (HttpContext context) =>
{
    var user = context.User;
    var identity = user.Identity;
    
    if (identity == null || !identity.IsAuthenticated)
    {
        return Results.Json(new 
        { 
            authenticated = false,  // <-- This is returned
            authEnabled = currentAuthEnabled,
            accessLevel = currentAuthEnabled ? "none" : "full"
        });
    }
    // ...
});
```

**Why it fails with LocalSystem**:
- The browser sends Windows credentials via Negotiate (NTLM/Kerberos)
- LocalSystem **cannot validate these credentials** because it has no domain identity
- `identity.IsAuthenticated` returns `false`
- The JavaScript then hides the user info element

**Can the browser access the local username?**
> **Answer**: No, the browser cannot directly access the Windows username for security reasons. The browser relies on the **server** to tell it who the user is via Windows Authentication. The authentication flow is:
> 1. Browser sends request with `Authorization: Negotiate <token>` header
> 2. Server (ASP.NET) validates the token using its own identity
> 3. Server returns the authenticated username via `/api/auth/me`
> 
> When the server runs as LocalSystem, step 2 fails because LocalSystem cannot validate domain credentials.

### Why Domain Account Fixes All Three Issues

| Issue | LocalSystem | Domain Account |
|-------|-------------|----------------|
| UNC Path Access | ❌ No | ✅ Yes |
| Windows Auth (Negotiate) | ❌ Cannot validate Kerberos/NTLM | ✅ Full support |
| User Identity | ❌ Always `IsAuthenticated = false` | ✅ Proper identity |
| Access Level Check | ❌ Always "none" → 403 errors | ✅ Correct level returned |
| Username Display | ❌ Hidden (not authenticated) | ✅ Shows `⭐ username` |

---

## Summary of All Issues

| # | Issue | Symptom | Root Cause |
|---|-------|---------|------------|
| 1 | UNC Path Access | Can't read `ComputerInfo.json` from network | LocalSystem has no network identity |
| 2 | User Access Page | "Error loading configuration" | Windows Auth fails → 403 Forbidden |
| 3 | Username Display | No username shown in header | `IsAuthenticated = false` |
| 4 | Orphaned Services | Multiple `ServerMonitor` services in stopped state | Previous installs not cleaned up |
| 5 | Quoted Display Name | Display name shows `"ServerMonitor Dashboard"` with quotes | `sc.exe` quoting issue |

**Single Fix**: Change Dashboard service to run as domain account (like Agent does)

---

## Issue 4 & 5: Service Cleanup and Quoting Problems

### Issue 4: Multiple Orphaned Services

**Symptom**: Windows Services shows multiple `ServerMonitor` entries, most in "Stopped" state.

**Root Cause**: Previous installations did not properly remove existing services before creating new ones.

### Issue 5: Quoted Display Name

**Symptom**: The Dashboard service display name shows with literal quotes: `"ServerMonitor Dashboard"` instead of `ServerMonitor Dashboard`.

**Root Cause**: Using `sc.exe create` with incorrect quoting:
```powershell
# ❌ WRONG - creates display name WITH literal quotes
sc.exe create $ServiceName binPath= "`"$absoluteExePath`"" DisplayName= "`"$DisplayName`"" start= delayed-auto

# ✅ CORRECT - use New-Service instead (handles quoting properly)
New-Service -Name $ServiceName -DisplayName $DisplayName -BinaryPathName $absoluteExePath
```

### Fix: Enhanced Service Cleanup in Install Scripts

Both install scripts must be updated to:

1. **Remove ALL orphaned services** before installation
2. **Use `New-Service`** instead of `sc.exe create` (handles quoting correctly)
3. **Force service deletion** even if it fails gracefully

```powershell
# Enhanced cleanup - remove ALL services matching pattern
function Remove-OrphanedServices {
    param([string]$ServiceNamePattern)
    
    $services = Get-Service -Name $ServiceNamePattern -ErrorAction SilentlyContinue
    foreach ($svc in $services) {
        Write-LogMessage "   Removing orphaned service: $($svc.Name)" -Level INFO
        try {
            Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
            
            # Kill any running process
            Get-Process -Name $svc.Name -ErrorAction SilentlyContinue | ForEach-Object {
                $_.Kill()
                $_.WaitForExit(3000)
            }
            
            # Remove using sc.exe (more reliable than Remove-Service)
            & sc.exe delete $svc.Name 2>&1 | Out-Null
            Write-LogMessage "   ✅ Removed: $($svc.Name)" -Level INFO
        }
        catch {
            Write-LogMessage "   ⚠️ Could not remove $($svc.Name): $($_.Exception.Message)" -Level WARN
        }
    }
}

# In ServerMonitorAgent.ps1 - clean up ALL ServerMonitor services
Remove-OrphanedServices -ServiceNamePattern "ServerMonitor*"

# In ServerMonitorDashboard.ps1 - clean up Dashboard services
Remove-OrphanedServices -ServiceNamePattern "ServerMonitorDashboard*"
```

### Files to Update

| File | Changes |
|------|---------|
| `ServerMonitorAgent.ps1` | Add cleanup for all `ServerMonitor*` services |
| `ServerMonitorDashboard.ps1` | Add cleanup for `ServerMonitorDashboard*` services, use domain account, remove local copy workaround |

---

## Date

- **Issue Identified**: 2026-01-28
- **Previous Workaround Applied**: 2026-01-27 (copying ComputerInfo.json locally - INCORRECT)
- **Fix Implemented**: 2026-01-28
  - `ServerMonitorDashboard.ps1` updated to use domain credentials
  - `ServerMonitorAgent.ps1` updated with enhanced service cleanup
  - Local config copy workaround removed
  - Orphaned service cleanup added to both scripts
- **Status**: Ready to deploy via `_deploy.ps1`
