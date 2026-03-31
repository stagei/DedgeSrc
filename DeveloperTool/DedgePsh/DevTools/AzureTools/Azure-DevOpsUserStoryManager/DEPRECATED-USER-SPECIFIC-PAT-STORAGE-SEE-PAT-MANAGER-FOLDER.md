# User-Specific PAT Storage System

**Secure, isolated PAT storage for each team member**

---

## 🗂️ Storage Structure

```
C:\opt\data\UserConfig\
├── FKGEISTA\
│   └── AzureDevOpsPat.json  ← Geir's PAT
├── FKSVEERI\
│   └── AzureDevOpsPat.json  ← Svein's PAT
├── FKMISTA\
│   └── AzureDevOpsPat.json  ← Mina's PAT
└── FKCELERI\
    └── AzureDevOpsPat.json  ← Celine's PAT
```

**Each user has their own isolated directory and PAT file!**

---

## 📍 File Locations

### **User: FKGEISTA**
```
C:\opt\data\UserConfig\FKGEISTA\AzureDevOpsPat.json
```
**Contains:**
```json
{
  "Organization": "Dedge",
  "Project": "Dedge",
  "PAT": "geir-specific-pat-token",
  "Email": "geir.helge.starholm@Dedge.no",
  "LastUpdated": "2025-12-16 12:00:00",
  "UpdatedBy": "FKGEISTA"
}
```

### **User: FKSVEERI**
```
C:\opt\data\UserConfig\FKSVEERI\AzureDevOpsPat.json
```
**Contains:**
```json
{
  "Organization": "Dedge",
  "Project": "Dedge",
  "PAT": "svein-specific-pat-token",
  "Email": "svein.morten.erikstad@Dedge.no",
  "LastUpdated": "2025-12-16 12:00:00",
  "UpdatedBy": "FKSVEERI"
}
```

### **User: FKMISTA**
```
C:\opt\data\UserConfig\FKMISTA\AzureDevOpsPat.json
```
**Contains:**
```json
{
  "Organization": "Dedge",
  "Project": "Dedge",
  "PAT": "mina-specific-pat-token",
  "Email": "mina.marie.starholm@Dedge.no",
  "LastUpdated": "2025-12-16 12:00:00",
  "UpdatedBy": "FKMISTA"
}
```

### **User: FKCELERI**
```
C:\opt\data\UserConfig\FKCELERI\AzureDevOpsPat.json
```
**Contains:**
```json
{
  "Organization": "Dedge",
  "Project": "Dedge",
  "PAT": "celine-specific-pat-token",
  "Email": "Celine.Andreassen.Erikstad@Dedge.no",
  "LastUpdated": "2025-12-16 12:00:00",
  "UpdatedBy": "FKCELERI"
}
```

---

## 🔍 Detection Logic

### **When Script Runs**

```powershell
# Step 1: Determine current user
$username = $env:USERNAME  # e.g., "FKGEISTA"

# Step 2: Build expected file path
$patFile = "C:\opt\data\UserConfig\$username\AzureDevOpsPat.json"

# Step 3: Check if file exists
if (Test-Path $patFile) {
    # PAT configured - load and use
    $config = Get-Content $patFile | ConvertFrom-Json
    $pat = $config.PAT
}
else {
    # PAT NOT configured - prompt user
    Write-Host "⚠️ PAT not configured for $username"
    Write-Host "Would you like to set up now? (y/n)"
    
    if (Read-Host -eq 'y') {
        .\Setup-AzureDevOpsPAT.ps1  # Launches setup
    }
}
```

---

## 🎯 Automatic Setup Prompt

When you try to use Azure DevOps without PAT configured:

```
⚠️  Azure DevOps PAT Not Configured
═══════════════════════════════════════════
User:     FKSVEERI
Expected: C:\opt\data\UserConfig\FKSVEERI\AzureDevOpsPat.json

PAT file does not exist for your user.

📋 To set up Azure DevOps integration:
   cd C:\opt\src\DedgePsh\DevTools\AdminTools\Azure-DevOpsUserStoryManager
   .\Setup-AzureDevOpsPAT.ps1

Would you like to run the setup now? (y/n): _
```

**Type `y`:**
- ✅ Setup script launches immediately
- ✅ Browser opens to create PAT
- ✅ You paste PAT (hidden)
- ✅ Configuration saved automatically
- ✅ Ready to use!

**Type `n`:**
- ✅ Operation cancelled gracefully
- ✅ You can run setup later
- ✅ Scripts continue without Azure DevOps features

---

## 🔒 Security Benefits

### **1. Complete Isolation**
```
User A's PAT  →  C:\opt\data\UserConfig\UserA\
User B's PAT  →  C:\opt\data\UserConfig\UserB\
User C's PAT  →  C:\opt\data\UserConfig\UserC\

NO OVERLAP - Completely separate!
```

### **2. Directory Permissions (Optional)**
You can apply Windows ACLs:
```powershell
# Restrict directory to specific user only
icacls "C:\opt\data\UserConfig\FKGEISTA" /inheritance:r
icacls "C:\opt\data\UserConfig\FKGEISTA" /grant "FKGEISTA:(OI)(CI)F"
```

### **3. Easy Audit**
```powershell
# Check who has PAT configured
Get-ChildItem "C:\opt\data\UserConfig" -Directory | ForEach-Object {
    $patFile = Join-Path $_.FullName "AzureDevOpsPat.json"
    [PSCustomObject]@{
        User = $_.Name
        Configured = (Test-Path $patFile)
        LastModified = if (Test-Path $patFile) { 
            (Get-Item $patFile).LastWriteTime 
        } else { 
            "N/A" 
        }
    }
}
```

**Output:**
```
User      Configured  LastModified
----      ----------  ------------
FKGEISTA  True        2025-12-16 12:00:00
FKSVEERI  False       N/A
FKMISTA   True        2025-12-15 10:30:00
FKCELERI  False       N/A
```

---

## 📊 Configuration Flow

```
User logs in as FKGEISTA
         │
         ▼
System checks: C:\opt\data\UserConfig\FKGEISTA\AzureDevOpsPat.json
         │
         ├─► File EXISTS
         │   │
         │   ▼
         │   Load PAT from file
         │   Use FKGEISTA's PAT
         │   All Azure DevOps operations work ✓
         │
         └─► File DOES NOT EXIST
             │
             ▼
             Show prompt:
             "⚠️ PAT not configured for FKGEISTA
              Would you like to set up now? (y/n)"
             │
             ├─► User types 'y'
             │   │
             │   ▼
             │   Launch Setup-AzureDevOpsPAT.ps1
             │   Email auto-detected: geir.helge.starholm@Dedge.no
             │   User creates PAT in browser
             │   File created: C:\opt\data\UserConfig\FKGEISTA\AzureDevOpsPat.json
             │   Configuration complete ✓
             │
             └─► User types 'n'
                 │
                 ▼
                 Skip Azure DevOps features
                 Continue without PAT
```

---

## 🛠️ Functions for Detection

### **New Functions Added to GlobalFunctions**

```powershell
# Check if current user has PAT configured
Test-AzureDevOpsPatConfigured
# Returns: $true or $false

# Get PAT file path for current user
Get-AzureDevOpsConfigFile
# Returns: "C:\opt\data\UserConfig\FKGEISTA\AzureDevOpsPat.json"

# Get PAT (prompts for setup if missing)
Get-AzureDevOpsPat
# Returns: PAT token OR prompts for setup

# Get PAT silently (no prompts, throws error if missing)
Get-AzureDevOpsPat -Silent
# Returns: PAT token OR throws error
```

---

## 📋 Status Check Commands

### **Check if YOU have PAT configured**
```powershell
Test-AzureDevOpsPatConfigured
# Returns: $true or $false
```

### **Show YOUR configuration**
```powershell
Show-AzureDevOpsConfig
# Displays all config details or setup prompt
```

### **Check your PAT file location**
```powershell
Get-AzureDevOpsConfigFile
# Returns: C:\opt\data\UserConfig\{YourUsername}\AzureDevOpsPat.json
```

### **List all configured users**
```powershell
Get-ChildItem "C:\opt\data\UserConfig" -Directory | ForEach-Object {
    $patFile = Join-Path $_.FullName "AzureDevOpsPat.json"
    if (Test-Path $patFile) {
        $config = Get-Content $patFile | ConvertFrom-Json
        [PSCustomObject]@{
            User = $_.Name
            Email = $config.Email
            LastUpdated = $config.LastUpdated
        }
    }
}
```

---

## 🎯 Setup for Each User

### **First Time Setup**

Each team member runs **once** on their computer:

```powershell
cd C:\opt\src\DedgePsh\DevTools\AdminTools\Azure-DevOpsUserStoryManager

# Run setup - email auto-detected!
.\Setup-AzureDevOpsPAT.ps1
```

**What happens:**
1. Email auto-detected from username
2. Browser opens to create PAT
3. You paste PAT (hidden input)
4. File saved to: `C:\opt\data\UserConfig\{YourUsername}\AzureDevOpsPat.json`
5. Azure CLI configured
6. Ready to use!

**File created for you:**
- FKGEISTA → `C:\opt\data\UserConfig\FKGEISTA\AzureDevOpsPat.json`
- FKSVEERI → `C:\opt\data\UserConfig\FKSVEERI\AzureDevOpsPat.json`
- FKMISTA → `C:\opt\data\UserConfig\FKMISTA\AzureDevOpsPat.json`
- FKCELERI → `C:\opt\data\UserConfig\FKCELERI\AzureDevOpsPat.json`

---

## 🔄 What If File Doesn't Exist?

### **Scenario 1: Using Azure DevOps Tools**

When you try `/ado 12345`:

```
⚠️  Azure DevOps PAT Not Configured
User:     FKMISTA
Expected: C:\opt\data\UserConfig\FKMISTA\AzureDevOpsPat.json

Would you like to run the setup now? (y/n): y

✓ Auto-detected email for FKMISTA: mina.marie.starholm@Dedge.no
[Browser opens for PAT creation]
[You create and paste PAT]
✓ Configuration saved to: C:\opt\data\UserConfig\FKMISTA\AzureDevOpsPat.json
✓ Azure DevOps ready to use!
```

### **Scenario 2: Checking Configuration**

```powershell
Show-AzureDevOpsConfig
```

**If file doesn't exist:**
```
═══ Azure DevOps Configuration ═══
Current User:       FKCELERI
Config File:        C:\opt\data\UserConfig\FKCELERI\AzureDevOpsPat.json
Status:             ✗ Not Configured

⚠️  PAT file does not exist for user: FKCELERI

To configure Azure DevOps:
  cd C:\opt\src\DedgePsh\DevTools\AdminTools\Azure-DevOpsUserStoryManager
  .\Setup-AzureDevOpsPAT.ps1
═══════════════════════════════════
```

---

## ✅ Benefits of User-Specific Storage

### **1. Complete Isolation**
- Each user has separate directory
- No file conflicts
- No credential sharing

### **2. Easy Management**
- See who's configured: `dir C:\opt\data\UserConfig`
- Delete specific user: `Remove-Item C:\opt\data\UserConfig\USERNAME -Recurse`
- Audit by checking file timestamps

### **3. Security**
- Can apply Windows ACLs per directory
- Each user only accesses their own file
- PAT exposure is limited to one user

### **4. Clarity**
- Clear file structure
- Easy to troubleshoot
- Know exactly where each user's PAT is

### **5. Automatic Detection**
- System knows if user has PAT
- Prompts for setup if missing
- No manual checking needed

---

## 🎉 Summary

**Storage Pattern:**
```
C:\opt\data\UserConfig\{USERNAME}\AzureDevOpsPat.json
```

**Detection:**
- File exists → User is configured ✓
- File missing → Prompt for setup

**Setup:**
- Run: `.\Setup-AzureDevOpsPAT.ps1`
- Email auto-detected
- File created automatically

**Security:**
- Completely isolated per user
- No shared credentials
- Clear audit trail

**Ready for team use!** 🚀

---

**Version:** 2.0  
**Date:** 2025-12-16  
**Storage Type:** User-Specific  
**Status:** ✅ Implemented
