# Windows Authentication Troubleshooting Guide

## Overview

The ServerMonitor Dashboard uses **Windows Negotiate Authentication** (Kerberos/NTLM) to authenticate users. This document covers common authentication issues and their solutions.

---

## Critical Configuration

### FallbackPolicy (REQUIRED!)

The server MUST have `FallbackPolicy` configured to trigger the browser's auth challenge:

```csharp
builder.Services.AddAuthorization(options =>
{
    options.FallbackPolicy = options.DefaultPolicy;  // Forces auth challenge!
});
```

**Without this**, the server accepts anonymous requests and the browser never sends credentials!

This was discovered by comparing with the working DedgeICC project.

---

## Common Symptoms

- Dashboard shows "Not Authenticated" or "Not Logged In"
- Auth badge shows red lock icon
- `/api/auth/me` returns `authenticated: false`
- `/api/auth/debug` shows empty `claims` array and empty `rawUsername`

---

## Root Causes

### 1. Browser Not in Intranet Zone

**Problem**: Modern browsers (Edge, Chrome) don't automatically send Windows credentials to servers they don't recognize as "intranet" sites.

**Symptoms**:
- Works on some machines but not others
- Same user works from one browser but not another

**Solution** (run on client machine):

```powershell
# Add server to Local Intranet Zone
$serverName = "dedge-server"
New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\Domains\$serverName" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\Domains\$serverName" -Name "http" -Value 1 -Type DWord

Write-Host "Added $serverName to Local Intranet Zone. Restart browser."
```

Then **restart the browser completely**.

---

### 2. Client Computer Not Domain-Joined

**Problem**: If the client computer is not joined to the domain, Windows/Kerberos authentication **cannot work automatically**.

**Why**:
- No Kerberos TGT (Ticket-Granting Ticket) from domain controller
- Browser cannot silently pass Windows credentials

**Symptoms**:
- `setspn` commands fail with "Could not find account"
- AD queries fail with "domain does not exist or could not be contacted"
- Authentication works from domain-joined machines but not from this machine

**Solutions**:

1. **Access from a domain-joined machine** - Authentication will work automatically

2. **Use local dashboard** - If running in developer mode on your machine:
   ```
   http://localhost:8998/
   ```
   This runs as your user account and bypasses network auth issues.

3. **Disable authentication for testing** - Edit `appsettings.json`:
   ```json
   {
     "Authentication": {
       "Enabled": false
     }
   }
   ```

---

### 3. Missing Kerberos SPN (Service Principal Name)

**Problem**: For Kerberos authentication to work, the service account must have HTTP SPNs registered.

**Symptoms**:
- Authentication falls back to NTLM (slower, less secure)
- May fail in some cross-domain scenarios

**Check SPNs** (run on domain controller or domain-joined machine):

```powershell
# Check SPNs for computer account
setspn -L dedge-server

# Check SPNs for service account (if running as domain user)
setspn -L DEDGE\ServiceAccountName
```

**Register SPNs** (requires Domain Admin, run on domain controller):

```powershell
# First, find what account the service runs as
$svc = Get-WmiObject -Class Win32_Service -ComputerName dedge-server -Filter "Name='ServerMonitorDashboard'"
Write-Host "Service runs as: $($svc.StartName)"

# For computer account (LocalSystem/NetworkService):
setspn -S HTTP/dedge-server dedge-server
setspn -S HTTP/dedge-server.DEDGE.fk.no dedge-server

# For domain user account:
setspn -S HTTP/dedge-server DEDGE\ServiceAccountName
setspn -S HTTP/dedge-server.DEDGE.fk.no DEDGE\ServiceAccountName

# Verify
setspn -L dedge-server
```

---

### 4. Service Account Configuration

**Problem**: The Dashboard service must run under an appropriate account for authentication to work.

**Options**:

| Account Type | Pros | Cons |
|--------------|------|------|
| LocalSystem | Simple setup | Cannot access network shares |
| NetworkService | Can access network as computer account | Limited |
| Domain User | Full network access, UNC paths work | Requires password management |

**Recommended**: Run as domain user account (e.g., `DEDGE\FKGEISTA`) for full UNC path access.

**Check service account**:

```powershell
Get-WmiObject -Class Win32_Service -Filter "Name='ServerMonitorDashboard'" | 
    Select-Object Name, StartName, State
```

---

## Diagnostic Endpoints

### `/api/auth/me`
Returns current authentication status:

```json
{
  "authenticated": true,
  "authEnabled": true,
  "accessLevel": "full",
  "username": "DEDGE\\FKGEISTA",
  "authenticationType": "Negotiate",
  "matchReason": "FullAccess: User 'DEDGE\\FKGEISTA' matches configured user 'DEDGE\\FKGEISTA'"
}
```

### `/api/auth/debug`
Returns detailed authentication diagnostics:

```json
{
  "authEnabled": true,
  "isAuthenticated": true,
  "rawUsername": "DEDGE\\FKGEISTA",
  "authenticationType": "Negotiate",
  "accessLevel": "full",
  "configuredFullAccessUsers": ["DEDGE\\FKGEISTA"],
  "configuredFullAccessGroups": ["DEDGE\\Domain Admins"],
  "roleChecks": [
    { "group": "DEDGE\\Domain Admins", "level": "FullAccess", "isInRole": false }
  ],
  "claims": [
    { "type": "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name", "value": "DEDGE\\FKGEISTA" }
  ],
  "claimsCount": 15
}
```

---

## Quick Diagnostic Script

Run this on the **client machine** to diagnose auth issues:

```powershell
$server = "dedge-server"
$port = 8998

Write-Host "=== Authentication Diagnostic ===" -ForegroundColor Cyan

# Check domain membership
$cs = Get-WmiObject -Class Win32_ComputerSystem
Write-Host "`n1. Computer Domain Status:"
Write-Host "   Computer: $($cs.Name)"
Write-Host "   Domain: $($cs.Domain)"
Write-Host "   Part of Domain: $($cs.PartOfDomain)"

# Check Intranet Zone
Write-Host "`n2. Intranet Zone Configuration:"
$zonePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\Domains\$server"
if (Test-Path $zonePath) {
    Write-Host "   $server is in Intranet Zone: YES" -ForegroundColor Green
} else {
    Write-Host "   $server is in Intranet Zone: NO" -ForegroundColor Red
    Write-Host "   Fix: Add to Intranet Zone (see commands above)"
}

# Test auth endpoint
Write-Host "`n3. Testing Authentication:"
try {
    $result = Invoke-RestMethod -Uri "http://$($server):$port/api/auth/debug" -UseDefaultCredentials -AllowUnencryptedAuthentication -TimeoutSec 10
    Write-Host "   Authenticated: $($result.isAuthenticated)"
    Write-Host "   Username: $($result.rawUsername)"
    Write-Host "   Access Level: $($result.accessLevel)"
    Write-Host "   Match Reason: $($result.matchReason)"
    Write-Host "   Claims Count: $($result.claimsCount)"
} catch {
    Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
}
```

---

## Configuration Reference

### appsettings.json Authentication Section

```json
{
  "Authentication": {
    "Enabled": true,
    "FullAccess": {
      "Groups": [
        "DEDGE\\Domain Admins",
        "DEDGE\\ACL_ERPUTV_Utvikling_Full"
      ],
      "Users": [
        "DEDGE\\FKGEISTA",
        "DEDGE\\FKSVEERI"
      ]
    },
    "Standard": {
      "Groups": ["DEDGE\\ServerMonitor-Users"],
      "Users": []
    },
    "Blocked": {
      "Groups": [],
      "Users": []
    }
  }
}
```

### Username Format Handling

The Dashboard normalizes usernames to handle different formats:
- `DOMAIN\username` (traditional)
- `username@domain.com` (UPN)
- `username` (just username)

All formats are compared case-insensitively.

---

## See Also

- [Microsoft: Negotiate Authentication](https://docs.microsoft.com/en-us/aspnet/core/security/authentication/windowsauth)
- [Kerberos SPN Configuration](https://docs.microsoft.com/en-us/windows-server/security/kerberos/kerberos-constrained-delegation-overview)
