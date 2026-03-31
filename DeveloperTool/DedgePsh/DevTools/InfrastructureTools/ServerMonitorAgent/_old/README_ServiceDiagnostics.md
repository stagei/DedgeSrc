# Service Security Diagnostics Tools

This directory contains tools to diagnose and troubleshoot Windows Service logon rights issues.

## Problem

When installing a Windows service with a specific user account, you may encounter error **%%1069**:

```
The service was unable to log on as DOMAIN\Username with the currently configured password due to the following error:
Logon failure: the user has not been granted the requested logon type at this computer.

This service account does not have the required user right "Log on as a service."
```

## Diagnostic Tools

### 1. Export-ServiceSecuritySettings.ps1

Captures comprehensive security settings for diagnosis with **automatic folder organization**.

**Usage:**

```powershell
# Auto-detect service state and organize output
.\Export-ServiceSecuritySettings.ps1

# Check specific user (still auto-detects folder)
.\Export-ServiceSecuritySettings.ps1 -Username "DEDGE\FKTSTADM"

# Manual folder override (if needed)
.\Export-ServiceSecuritySettings.ps1 -OutputPrefix "CustomFolder"
```

**Automatic Folder Organization:**

The script automatically detects the service state and organizes output files:

- **BeforeServiceAdded** - Service not installed yet
- **AfterServiceFail** - Service exists but not running (Status: Stopped, Failed, etc.)
- **AfterServiceOk** - Service exists and is running

**What it captures:**

- ✅ Complete security policy (all user rights)
- ✅ Specific user rights (SeServiceLogonRight, SeBatchLogonRight, etc.)
- ✅ User and SID information
- ✅ Service configuration
- ✅ Group Policy settings (HTML report)
- ✅ Registry keys related to services
- ✅ Recent Event Log entries (service failures, logon events)

**Output Files:**

Files are organized in `SecurityDiagnostics\[FolderName]\` subfolders:

- `[timestamp]_UserInfo.json` - User and SID information
- `[timestamp]_SecurityPolicy.inf` - Complete security policy
- `[timestamp]_UserRights.json` - All user rights assignments
- `[timestamp]_TargetUserRights.json` - **Rights for target user with GRANTED/NOT GRANTED status**
- `[timestamp]_ServiceInfo.json` - Service configuration
- `[timestamp]_GroupPolicy.html` - Group Policy report (open in browser)
- `[timestamp]_Registry.json` - Relevant registry keys
- `[timestamp]_EventLogs.json` - Recent event log entries (last 24 hours)
- `[timestamp]_SUMMARY.txt` - Summary and diagnostic steps

**Example folder structure:**
```
SecurityDiagnostics\
├── BeforeServiceAdded\
│   ├── 20231211_120000_UserInfo.json
│   ├── 20231211_120000_SecurityPolicy.inf
│   └── ...
├── AfterServiceFail\
│   ├── 20231211_130000_UserInfo.json
│   ├── 20231211_130000_SecurityPolicy.inf
│   └── ...
└── AfterServiceOk\
    ├── 20231211_140000_UserInfo.json
    ├── 20231211_140000_SecurityPolicy.inf
    └── ...
```

### 2. Compare-SecurityCaptures.ps1

Compares "before" and "after" captures to identify changes.

**Usage:**

```powershell
# Auto-detect and compare latest captures
.\Compare-SecurityCaptures.ps1

# Compare specific files
.\Compare-SecurityCaptures.ps1 -BeforeFile ".\SecurityDiagnostics\before_20231211_120000_UserRights.json" -AfterFile ".\SecurityDiagnostics\after_20231211_130000_UserRights.json"

# Check specific user
.\Compare-SecurityCaptures.ps1 -Username "DEDGE\FKTSTADM"
```

## Recommended Workflow

### Step 1: Capture Initial State

```powershell
# Run as Administrator - automatically detects service state
.\Export-ServiceSecuritySettings.ps1
```

**Result:** Captures to `SecurityDiagnostics\BeforeServiceAdded\` (if service doesn't exist)

### Step 2: Install/Configure Service

Either use the installation script or configure manually:

```powershell
# Option A: Use installation script
.\Install-ServerMonitorService.ps1

# Option B: Manual configuration
# 1. Open Services (services.msc)
# 2. Find your service
# 3. Properties -> Log On tab
# 4. Select "This account" and enter credentials
# 5. Click Apply/OK
```

### Step 3: Capture After Installation

```powershell
# Run again - automatically detects new state
.\Export-ServiceSecuritySettings.ps1
```

**Result:** Captures to either:
- `SecurityDiagnostics\AfterServiceFail\` (if service failed to start)
- `SecurityDiagnostics\AfterServiceOk\` (if service is running)

### Step 4: Compare and Diagnose

```powershell
# Auto-compare latest captures from different folders
.\Compare-SecurityCaptures.ps1

# Check specific user rights
.\Compare-SecurityCaptures.ps1 -Username "DEDGE\FKTSTADM"
```

**The comparison automatically finds:**
- Latest file from `BeforeServiceAdded` folder as "before"
- Latest file from `AfterServiceFail` or `AfterServiceOk` as "after"

### Step 5: Review Findings

1. **Check TargetUserRights.json** - See if `SeServiceLogonRight` was granted
2. **Review GroupPolicy.html** - Check if domain GPO is overriding local settings
3. **Check EventLogs.json** - Look for Event ID 7041 (service logon failure)
4. **Compare UserRights.json** - See what changed between before/after

## Common Issues and Solutions

### Issue 1: Rights Not Applied

**Symptom:** `Grant-ServiceLogonRight` runs but service still fails to start.

**Diagnosis:**
```powershell
# Check the after capture
Get-Content .\SecurityDiagnostics\after_*_TargetUserRights.json | ConvertFrom-Json
```

Look for:
- `SeServiceLogonRight` - Should show `HasRight: true`
- `SeDenyServiceLogonRight` - Should show `HasRight: false` (deny takes precedence!)

**Solution:**
1. If `SeServiceLogonRight` shows `false`, the function didn't work correctly
2. If `SeDenyServiceLogonRight` shows `true`, remove the deny first:
   ```powershell
   # Manually edit security policy to remove from deny list
   secpol.msc -> Local Policies -> User Rights Assignment
   ```

### Issue 2: Group Policy Override

**Symptom:** Local rights are granted but service still fails.

**Diagnosis:**
```powershell
# Open the Group Policy HTML report
explorer.exe .\SecurityDiagnostics\after_*_GroupPolicy.html
```

Look for:
- User Rights Assignment policies
- "Log on as a service" policy
- Check if domain GPO is restricting this right

**Solution:**
1. Contact domain administrator
2. Request GPO exemption or addition to allowed list
3. Alternatively, test with local admin account to confirm GPO is the issue

### Issue 3: Wrong User SID

**Symptom:** Function runs but grants rights to wrong user.

**Diagnosis:**
```powershell
# Check UserInfo.json
Get-Content .\SecurityDiagnostics\after_*_UserInfo.json | ConvertFrom-Json

# Compare with UserRights.json
Get-Content .\SecurityDiagnostics\after_*_UserRights.json | ConvertFrom-Json
```

**Solution:**
- Ensure `Grant-ServiceLogonRight -Username "DOMAIN\User"` uses correct format
- Verify the SID in UserInfo.json matches the SID in UserRights.json for SeServiceLogonRight

### Issue 4: Password Issues

**Symptom:** Rights are correct but service still fails with logon error.

**Diagnosis:**
```powershell
# Check EventLogs.json for Event ID 4625 (failed logon)
Get-Content .\SecurityDiagnostics\after_*_EventLogs.json | ConvertFrom-Json | Where-Object Id -eq 4625
```

**Solution:**
1. Verify password is correct
2. Check if password expired
3. Verify account is not locked or disabled
4. Test credentials:
   ```powershell
   runas /user:DOMAIN\Username cmd
   ```

## Manual Verification

If scripts aren't available, manually verify using:

### Check Current Rights

```powershell
# Export policy
secedit /export /cfg C:\temp\secpol.cfg

# View policy file
notepad C:\temp\secpol.cfg

# Look for [Privilege Rights] section
# Find: SeServiceLogonRight = *S-1-5-21-...
```

### Check Service Configuration

```powershell
# Get service details
Get-CimInstance -ClassName Win32_Service -Filter "Name='ServerMonitor'" | Select-Object Name, StartName, State, Status

# View service properties
sc.exe qc ServerMonitor
```

### Check Event Logs

```powershell
# Service start failures (Event ID 7000, 7041)
Get-WinEvent -FilterHashtable @{LogName='System'; Id=7000,7041} -MaxEvents 10

# Logon failures (Event ID 4625)
Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4625} -MaxEvents 10
```

## Troubleshooting the Diagnostic Scripts

### Script Requires Administrator

Both diagnostic scripts require administrator privileges.

```powershell
# Run PowerShell as Administrator
Start-Process powershell.exe -Verb RunAs
```

### Module Import Errors

```powershell
# Ensure GlobalFunctions module is available
Import-Module GlobalFunctions -Force
```

### GPResult Fails

If Group Policy export fails:
```powershell
# Run gpupdate first
gpupdate /force

# Then try export again
gpresult /H C:\temp\gpreport.html /F
```

## Files Generated

Example output after running captures during installation workflow:

```
SecurityDiagnostics\
├── BeforeServiceAdded\
│   ├── 20231211_120000_UserInfo.json
│   ├── 20231211_120000_SecurityPolicy.inf
│   ├── 20231211_120000_UserRights.json
│   ├── 20231211_120000_TargetUserRights.json
│   ├── 20231211_120000_ServiceInfo.json
│   ├── 20231211_120000_GroupPolicy.html
│   ├── 20231211_120000_Registry.json
│   ├── 20231211_120000_EventLogs.json
│   └── 20231211_120000_SUMMARY.txt
│
├── AfterServiceFail\
│   ├── 20231211_130000_UserInfo.json
│   ├── 20231211_130000_SecurityPolicy.inf
│   ├── 20231211_130000_UserRights.json
│   ├── 20231211_130000_TargetUserRights.json
│   ├── 20231211_130000_ServiceInfo.json
│   ├── 20231211_130000_GroupPolicy.html
│   ├── 20231211_130000_Registry.json
│   ├── 20231211_130000_EventLogs.json
│   └── 20231211_130000_SUMMARY.txt
│
└── AfterServiceOk\
    ├── 20231211_140000_UserInfo.json
    ├── 20231211_140000_SecurityPolicy.inf
    ├── 20231211_140000_UserRights.json
    ├── 20231211_140000_TargetUserRights.json
    ├── 20231211_140000_ServiceInfo.json
    ├── 20231211_140000_GroupPolicy.html
    ├── 20231211_140000_Registry.json
    ├── 20231211_140000_EventLogs.json
    └── 20231211_140000_SUMMARY.txt
```

## Author

**Geir Helge Starholm**  
Website: [www.dEdge.no](https://www.dEdge.no)

## See Also

- [Install-ServerMonitorService.ps1](./Install-ServerMonitorService.ps1) - Main installation script
- [Grant-ServiceLogonRight](../../_Modules/Infrastructure/Infrastructure.psm1) - Function to grant service logon rights
- [Grant-BatchLogonRight](../../_Modules/Infrastructure/Infrastructure.psm1) - Function to grant batch logon rights

