# Team Member Configuration Guide

**Team-specific automatic configuration for Azure DevOps and notifications**

---

## 👥 Team Members

The following 4 team members are configured in `.cursorrules`:

| Username | Full Name | Email | SMS Number |
|----------|-----------|-------|------------|
| FKGEISTA | Geir Helge Starholm | geir.helge.starholm@Dedge.no | +4797188358 |
| FKSVEERI | Svein Morten Erikstad | svein.morten.erikstad@Dedge.no | +4795762742 |
| FKMISTA | Mina Marie Starholm | mina.marie.starholm@Dedge.no | +4799348397 |
| FKCELERI | Celine Andreassen Erikstad | Celine.Andreassen.Erikstad@Dedge.no | +4745269945 |

---

## 🎯 Automatic User Detection

All tools and scripts automatically detect the current user and use their configuration:

```powershell
# This happens automatically in the background
$currentUser = $env:USERNAME

# System automatically selects:
$email = Get-CurrentUserEmail        # Your email
$sms = Get-CurrentUserSms            # Your SMS number
$name = Get-CurrentUserFullName      # Your full name
$pat = Get-AzureDevOpsPat            # Your Azure PAT
```

---

## 📱 SMS Notifications

### **How It Works**

When Agent operations take more than 5 minutes, **you** receive an SMS notification automatically:

```powershell
# Automatic user detection
$smsNumber = switch ($env:USERNAME) {
    "FKGEISTA" { "+4797188358" }
    "FKSVEERI" { "+4795762742" }
    "FKMISTA"  { "+4799348397" }
    "FKCELERI" { "+4745269945" }
    default    { "+4797188358" } # Fallback
}

# Send to YOUR number
Send-Sms $smsNumber "Agent completed: <operation summary>"
```

### **Example Notifications**

**FKGEISTA will receive:**
```
To: +4797188358
"Agent completed: Fixed 10 linter warnings in GlobalFunctions.psm1. All tests passed."
```

**FKSVEERI will receive:**
```
To: +4795762742
"Agent completed: Fixed 10 linter warnings in GlobalFunctions.psm1. All tests passed."
```

**Each user gets their own notifications!**

---

## 🔷 Azure DevOps Integration

### **How It Works**

Azure DevOps operations automatically use **your** email for assignments:

```powershell
# Auto-detect current user's email
$assignedTo = switch ($env:USERNAME) {
    "FKGEISTA" { "geir.helge.starholm@Dedge.no" }
    "FKSVEERI" { "svein.morten.erikstad@Dedge.no" }
    "FKMISTA"  { "mina.marie.starholm@Dedge.no" }
    "FKCELERI" { "Celine.Andreassen.Erikstad@Dedge.no" }
}

# Work items created are automatically assigned to YOU
az boards work-item create --type "User Story" --assigned-to "$assignedTo"
```

### **PAT Setup**

Each user has their own PAT token:

```powershell
# Run setup (email auto-detected)
.\Setup-AzureDevOpsPAT.ps1

# Or specify explicitly
.\Setup-AzureDevOpsPAT.ps1 -Email "your.email@Dedge.no"
```

**The script automatically:**
1. ✅ Detects your email from username
2. ✅ Opens browser for PAT creation
3. ✅ Stores YOUR PAT in configuration
4. ✅ Configures Azure CLI with YOUR credentials

---

## 🔧 PAT Configuration Per User

Each user has their own PAT stored in a **secure user-specific location**:

### **User-Specific PAT Locations**

| User | PAT File Location |
|------|-------------------|
| FKGEISTA | `C:\opt\data\UserConfig\FKGEISTA\AzureDevOpsPat.json` |
| FKSVEERI | `C:\opt\data\UserConfig\FKSVEERI\AzureDevOpsPat.json` |
| FKMISTA | `C:\opt\data\UserConfig\FKMISTA\AzureDevOpsPat.json` |
| FKCELERI | `C:\opt\data\UserConfig\FKCELERI\AzureDevOpsPat.json` |

**Pattern:** `C:\opt\data\UserConfig\{USERNAME}\AzureDevOpsPat.json`

### **Configuration Format**
```json
{
  "Organization": "Dedge",
  "Project": "Dedge",
  "PAT": "user-specific-pat-token-here",
  "LastUpdated": "2025-12-16 12:00:00",
  "UpdatedBy": "FKGEISTA",
  "Email": "geir.helge.starholm@Dedge.no"
}
```

### **Security Benefits**
- ✅ Each user has completely separate PAT file
- ✅ PATs never overlap or conflict
- ✅ Easy to identify configured users
- ✅ User-specific directory permissions can be applied
- ✅ No shared credential files

**Each user on each computer has their own isolated config file!**

---

## 🚀 Quick Start for Each User

### **FKGEISTA**
```powershell
# Email auto-detected
.\Setup-AzureDevOpsPAT.ps1

# Or explicit
.\Setup-AzureDevOpsPAT.ps1 -Email "geir.helge.starholm@Dedge.no"
```

### **FKSVEERI**
```powershell
# Email auto-detected
.\Setup-AzureDevOpsPAT.ps1

# Or explicit
.\Setup-AzureDevOpsPAT.ps1 -Email "svein.morten.erikstad@Dedge.no"
```

### **FKMISTA**
```powershell
# Email auto-detected
.\Setup-AzureDevOpsPAT.ps1

# Or explicit
.\Setup-AzureDevOpsPAT.ps1 -Email "mina.marie.starholm@Dedge.no"
```

### **FKCELERI**
```powershell
# Email auto-detected
.\Setup-AzureDevOpsPAT.ps1

# Or explicit
.\Setup-AzureDevOpsPAT.ps1 -Email "Celine.Andreassen.Erikstad@Dedge.no"
```

---

## 💡 User-Specific Functions

### **Available in GlobalFunctions (After Integration)**

```powershell
# Get your email
$myEmail = Get-CurrentUserEmail
# Returns: "geir.helge.starholm@Dedge.no" (if you're FKGEISTA)

# Get your SMS number
$mySms = Get-CurrentUserSms
# Returns: "+4797188358" (if you're FKGEISTA)

# Get your full name
$myName = Get-CurrentUserFullName
# Returns: "Geir Helge Starholm" (if you're FKGEISTA)

# Get your complete config
$myConfig = Get-CurrentUserConfig
# Returns: PSCustomObject with all your info
```

---

## 🎯 Example Workflows

### **Example 1: Send Yourself a Notification**
```powershell
# Old way (hardcoded)
Send-Sms "+4797188358" "Task completed"

# New way (automatic)
$mySms = Get-CurrentUserSms
Send-Sms $mySms "Task completed"
```

### **Example 2: Create Work Item Assigned to Yourself**
```powershell
# Automatic assignment
$myEmail = Get-CurrentUserEmail

az boards work-item create `
    --type "User Story" `
    --title "My Task" `
    --assigned-to "$myEmail"
# Automatically assigned to the current user!
```

### **Example 3: Setup Azure PAT**
```powershell
# Run on any machine
.\Setup-AzureDevOpsPAT.ps1

# Email is automatically detected based on who you are!
# FKGEISTA → geir.helge.starholm@Dedge.no
# FKSVEERI → svein.morten.erikstad@Dedge.no
# FKMISTA  → mina.marie.starholm@Dedge.no
# FKCELERI → Celine.Andreassen.Erikstad@Dedge.no
```

---

## 🔄 Multi-User Workflow

### **Scenario: Multiple Users on Same Server**

Each user maintains their own configuration:

**FKGEISTA logs in:**
```powershell
# PAT setup creates:
C:\opt\src\DedgePsh\_Modules\GlobalFunctions\AzureDevOpsConfig.json
{
  "Email": "geir.helge.starholm@Dedge.no",
  "PAT": "geir-pat-token",
  "UpdatedBy": "FKGEISTA"
}

# Work items assigned to:
geir.helge.starholm@Dedge.no

# SMS notifications sent to:
+4797188358
```

**FKSVEERI logs in:**
```powershell
# PAT setup creates:
C:\opt\src\DedgePsh\_Modules\GlobalFunctions\AzureDevOpsConfig.json
{
  "Email": "svein.morten.erikstad@Dedge.no",
  "PAT": "svein-pat-token",
  "UpdatedBy": "FKSVEERI"
}

# Work items assigned to:
svein.morten.erikstad@Dedge.no

# SMS notifications sent to:
+4795762742
```

**Each user has their own configuration based on who's logged in!**

---

## 📋 Integration Checklist

### **For Each User**

- [ ] Run PAT setup script (email auto-detected)
- [ ] Create PAT in browser
- [ ] Paste PAT when prompted
- [ ] Verify validation passes
- [ ] Test with `/ado` command
- [ ] Confirm SMS notifications work
- [ ] Confirm work items assigned correctly

### **One-Time Setup (Already Done)**

- [x] Team member configuration added to `.cursorrules`
- [x] User detection functions created
- [x] Setup script updated for auto-detection
- [x] Azure DevOps integration configured
- [x] SMS notification system updated

---

## 🛠️ Updating Team Configuration

### **Add New Team Member**

To add a new team member, update `.cursorrules`:

```yaml
Users:
  - Username: NEWUSER
    FullName: New User Name
    Email: new.user@Dedge.no
    SmsNumber: +47XXXXXXXX
    AzurePat: # Stored in GlobalFunctions config
```

Then update the switch statements in:
1. `.cursorrules` (Team Member Configuration section)
2. `GlobalFunctions-PAT-Helper.ps1` (Get-CurrentUserConfig function)

### **Update User Information**

If email or SMS changes:

1. Update `.cursorrules`
2. Update `GlobalFunctions-PAT-Helper.ps1`
3. Each user re-runs: `.\Setup-AzureDevOpsPAT.ps1`

---

## 🔒 Security Notes

### **PAT Separation**
- ✅ Each user has their own PAT
- ✅ PATs are stored per-user on each machine
- ✅ One user's PAT doesn't affect others
- ✅ If one PAT is compromised, others are safe

### **Privacy**
- ✅ SMS numbers are private to each user
- ✅ Emails are work emails only
- ✅ No personal information shared across users

### **Access Control**
- ✅ Each user can only use their own credentials
- ✅ Work items track who created/modified them
- ✅ Audit trail shows real user actions

---

## 📊 User Detection Flow

```
User logs in to Windows
         │
         ▼
$env:USERNAME is set (e.g., "FKGEISTA")
         │
         ▼
Script/Function calls Get-CurrentUserConfig
         │
         ▼
Switch statement matches username
         │
         ▼
Returns user-specific configuration
         │
         ├─► Email: geir.helge.starholm@Dedge.no
         ├─► SMS: +4797188358
         ├─► Name: Geir Helge Starholm
         └─► PAT: (from AzureDevOpsConfig.json)
         │
         ▼
All operations use YOUR information automatically!
```

---

## ✅ Benefits

### **For Individual Users**
1. **No configuration needed** - Auto-detected by username
2. **Personal notifications** - SMS to your number only
3. **Own PAT tokens** - Secure and separate
4. **Correct assignments** - Work items assigned to you
5. **Privacy** - Your credentials stay yours

### **For Team**
1. **Consistent** - Everyone uses same tools
2. **Auditable** - Track who did what
3. **Secure** - Separate credentials
4. **Maintainable** - Central configuration in .cursorrules
5. **Scalable** - Easy to add new members

---

## 🎯 Quick Reference

### **Current User Functions**
```powershell
Get-CurrentUserConfig     # All info
Get-CurrentUserEmail      # Email only
Get-CurrentUserSms        # SMS only
Get-CurrentUserFullName   # Name only
```

### **Azure DevOps Functions**
```powershell
Get-AzureDevOpsPat           # Your PAT
Get-AzureDevOpsOrganization  # Organization
Get-AzureDevOpsProject       # Project
Test-AzureDevOpsConfig       # Validate config
Show-AzureDevOpsConfig       # Display config
```

### **Setup Commands**
```powershell
# Setup Azure PAT (email auto-detected)
.\Setup-AzureDevOpsPAT.ps1

# Show current configuration
Import-Module GlobalFunctions -Force
Show-AzureDevOpsConfig

# Get your email
Get-CurrentUserEmail
```

---

## 🔍 Check Your Configuration

### **Check if PAT is Configured**
```powershell
Import-Module GlobalFunctions -Force

# Show your configuration
Show-AzureDevOpsConfig
```

**If Configured - Output:**
```
═══ Azure DevOps Configuration ═══
Current User:       FKGEISTA
Config File:        C:\opt\data\UserConfig\FKGEISTA\AzureDevOpsPat.json
Status:             ✓ Configured

Configuration Details:
  Organization:     Dedge
  Project:          Dedge
  Email:            geir.helge.starholm@Dedge.no
  PAT Configured:   Yes
  Last Updated:     2025-12-16 12:00:00

Testing connection...
Connection Status:  ✓ Connected
```

**If NOT Configured - Output:**
```
═══ Azure DevOps Configuration ═══
Current User:       FKSVEERI
Config File:        C:\opt\data\UserConfig\FKSVEERI\AzureDevOpsPat.json
Status:             ✗ Not Configured

⚠️  PAT file does not exist for user: FKSVEERI

To configure Azure DevOps:
  cd C:\opt\src\DedgePsh\DevTools\AdminTools\Azure-DevOpsUserStoryManager
  .\Setup-AzureDevOpsPAT.ps1
```

### **Automatic Prompt When Missing**

If you try to use Azure DevOps features without PAT configured:

```
⚠️  Azure DevOps PAT Not Configured
═══════════════════════════════════════════
User:     FKSVEERI
Expected: C:\opt\data\UserConfig\FKSVEERI\AzureDevOpsPat.json

PAT file does not exist for your user.

📋 To set up Azure DevOps integration:
   cd C:\opt\src\DedgePsh\DevTools\AdminTools\Azure-DevOpsUserStoryManager
   .\Setup-AzureDevOpsPAT.ps1

Would you like to run the setup now? (y/n):
```

- Type `y` → Setup launches automatically!
- Type `n` → Skips Azure DevOps for now

---

## 🎉 Summary

**You now have team-specific configuration that:**

✅ **Auto-detects** who's logged in  
✅ **Uses correct email** for Azure DevOps  
✅ **Sends SMS** to the right person  
✅ **Assigns work items** to current user  
✅ **Maintains separate PATs** for security  
✅ **Works for all 4 team members**  

**No manual configuration needed - just log in and use the tools!** 🚀

---

## 📝 For New Team Members

When a new team member joins:

1. **Add to `.cursorrules`** - Add their info to Team Member Configuration
2. **Update helper functions** - Add to `GlobalFunctions-PAT-Helper.ps1`
3. **User runs setup** - `.\Setup-AzureDevOpsPAT.ps1` (email auto-detected)
4. **Done!** - All tools work automatically

---

**Version:** 1.0  
**Date:** 2025-12-16  
**Team Size:** 4 members  
**Status:** ✅ Configured
