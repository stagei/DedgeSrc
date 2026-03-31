# Service Account Integration - GlobalSettings.json

**Feature:** Automatic GlobalSettings.json update for service account PAT

---

## 🎯 Purpose

When setting up the Azure DevOps service account PAT, the script can automatically update the global configuration file used by all servers.

---

## 📧 Service Account

**Email:** `srv_Dedge_repo@Dedge.onmicrosoft.com`

**Purpose:** Azure DevOps automation service account for server-wide operations

---

## 📍 Global Configuration File

**Location:**
```
C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\GlobalSettings.json
```

**Structure (AzureDevOps section):**
```json
{
  "AzureDevOps": {
    "Organization": "Dedge",
    "Project": "Dedge",
    "Repository": "Dedge",
    "Pat": "service-account-pat-token-here",
    "PatComment": "Privileges: Work Items: Read, Write & Manage; Code: Read | Expires: 2025-03-16 | Updated: 2025-12-16 12:00:00 by FKGEISTA"
  }
}
```

---

## 🚀 How It Works

### **Automatic Detection**

When you run setup with service account email:

```powershell
.\Setup-AzureDevOpsPAT.ps1 -Email "srv_Dedge_repo@Dedge.onmicrosoft.com"
```

**The script automatically:**
1. ✅ Detects it's the service account
2. ✅ Completes normal PAT setup
3. ✅ **Prompts to update GlobalSettings.json**

### **The Prompt**

```
================================================================
  Step 5: Update Common Config File (Service Account)
================================================================

Service account detected: srv_Dedge_repo@Dedge.onmicrosoft.com
Common config file: C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\GlobalSettings.json

This will update ONLY the Pat field in GlobalSettings.json
  • Pat: [new PAT token]
  • PatComment: Privileges and expiry info

Organization, Project, and Repository fields will NOT be changed

Please provide PAT details for documentation:
PAT privileges (e.g., 'Work Items: Read, Write & Manage; Code: Read'):
PAT expiry in days (e.g., 90):

Do you want to update the common config file? (y/n):
```

### **If You Choose 'y' (Yes)**

**The script will:**
1. ✅ Read current GlobalSettings.json
2. ✅ Create timestamped backup
3. ✅ Update ONLY these fields:
   - Pat (new token)
   - PatComment (privileges, expiry, updated date/user)
4. ✅ Preserve existing fields (Organization, Project, Repository)
5. ✅ Save updated configuration
6. ✅ Confirm success

**Example interaction:**
```
Please provide PAT details for documentation:
Recommended: Work Items: Read, Write & Manage; Code: Read & Write; Packaging: Read & Write
PAT privileges (press Enter for recommended, or type custom): [Enter]
Using recommended privileges

PAT expiry in days (default: 90, press Enter to accept): [Enter]
Using 90 days expiry
```

**Backup example:**
```
GlobalSettings_backup_20251216120000.json
```

### **If You Choose 'n' (No)**

- Script continues without updating GlobalSettings.json
- Only user-specific PAT file is saved
- You can manually update GlobalSettings.json later

---

## 📋 Fields Updated

The script updates ONLY these fields:

| Field | Value | Action |
|-------|-------|--------|
| **Pat** | [new token] | ✅ UPDATED |
| **PatComment** | Privileges, expiry, update info | ✅ UPDATED/ADDED |

**Fields PRESERVED (not changed):**

| Field | Action |
|-------|--------|
| **Organization** | ⊝ UNCHANGED - Preserves existing value |
| **Project** | ⊝ UNCHANGED - Preserves existing value |
| **Repository** | ⊝ UNCHANGED - Preserves existing value |

**PatComment Format:**
```
"Privileges: Work Items: Read, Write & Manage; Code: Read & Write; Packaging: Read & Write | Expires: 2025-03-16 | Updated: 2025-12-16 12:00:00 by FKGEISTA"
```

**Components:**
- **Privileges:** Work Items (RWM), Code (RW), Packaging (RW)
- **Expires:** Calculated from expiry days (90 days default)
- **Updated:** Timestamp and username who updated

---

## 🔐 Security Features

### **1. Backup Protection**
```
Before update: Creates backup with timestamp
Example: GlobalSettings_backup_20251216120000.json
Location: Same directory as GlobalSettings.json
```

### **2. User Confirmation**
- Always prompts before updating
- User must explicitly type 'y' to proceed
- Can skip if uncertain

### **3. Validation**
- PAT validated before any file updates
- Ensures PAT works before saving
- Prevents saving invalid PATs

### **4. Error Handling**
- If update fails, original file unchanged
- Backup still available for recovery
- Clear error messages

---

## 🎯 Use Cases

### **Use Case 1: Service Account PAT Update**

**Scenario:** Service account PAT is expiring

**Steps:**
```powershell
# 1. Run setup with service account email
.\Setup-AzureDevOpsPAT.ps1 -Email "srv_Dedge_repo@Dedge.onmicrosoft.com"

# 2. Create new PAT in browser

# 3. Paste PAT when prompted

# 4. When prompted about GlobalSettings.json:
Do you want to update the common config file? (y/n): y

# 5. Done! Both locations updated:
#    - C:\opt\data\UserConfig\{user}\AzureDevOpsPat.json
#    - C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\GlobalSettings.json
```

**Result:**
- ✅ New PAT saved locally
- ✅ GlobalSettings.json updated with all fields
- ✅ Backup created
- ✅ All servers can use new PAT

### **Use Case 2: Manual GlobalSettings.json Update Later**

**Scenario:** You chose 'n' initially but want to update later

**Option 1 - Re-run setup:**
```powershell
.\Setup-AzureDevOpsPAT.ps1 -Email "srv_Dedge_repo@Dedge.onmicrosoft.com"
# This time choose 'y' when prompted
```

**Option 2 - Manual update:**
```powershell
# Read user-specific config
$userConfig = Get-Content "C:\opt\data\UserConfig\$env:USERNAME\AzureDevOpsPat.json" | ConvertFrom-Json

# Update GlobalSettings.json manually
$globalSettings = Get-Content "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\GlobalSettings.json" | ConvertFrom-Json

$globalSettings.AzureDevOps.Organization = $userConfig.Organization
$globalSettings.AzureDevOps.Project = $userConfig.Project
$globalSettings.AzureDevOps.Repository = $userConfig.Project
$globalSettings.AzureDevOps.Pat = $userConfig.PAT

$globalSettings | ConvertTo-Json -Depth 10 | Set-Content "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\GlobalSettings.json"
```

---

## ⚠️ Important Notes

### **When to Use Service Account Email**

**Use service account for:**
- ✅ Automated server operations
- ✅ Scheduled tasks running as service account
- ✅ System-wide Azure DevOps operations
- ✅ Operations that need to work on all servers

**Use personal account for:**
- ✅ Individual development work
- ✅ Personal Cursor AI integration
- ✅ User-specific work item management
- ✅ Local testing and development

### **GlobalSettings.json Access**

**Requirements:**
- Network access to: `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\`
- Write permissions to GlobalSettings.json
- Typically requires admin or service account privileges

**If file is not accessible:**
- Script will show warning and skip update
- User-specific PAT file is still saved
- Can update GlobalSettings.json manually later

---

## 📊 Update Flow

```
User runs setup with service account email
           ↓
srv_Dedge_repo@Dedge.onmicrosoft.com detected
           ↓
Normal PAT setup completes
           ↓
Script prompts: "Update GlobalSettings.json?"
           ↓
      User chooses:
      ↓           ↓
     'y'         'n'
      ↓           ↓
  Update      Skip update
  GlobalSettings   (user-specific only)
      ↓
  Create backup
      ↓
  Prompt for PAT details:
  • Privileges
  • Expiry days
      ↓
  Update 2 fields:
  • Pat (new token)
  • PatComment (privileges + expiry)
      ↓
  Preserve existing:
  • Organization
  • Project
  • Repository
      ↓
  Save file
      ↓
  ✓ Available globally!
```

---

## 🔍 Verification

### **Check User-Specific Config**
```powershell
$userConfig = Get-Content "C:\opt\data\UserConfig\$env:USERNAME\AzureDevOpsPat.json" | ConvertFrom-Json
$userConfig.PAT
```

### **Check GlobalSettings.json**
```powershell
$globalSettings = Get-Content "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\GlobalSettings.json" | ConvertFrom-Json
$globalSettings.AzureDevOps
```

**Expected Output:**
```
Organization : Dedge
Project      : Dedge
Repository   : Dedge
Pat          : [new PAT token]
PatComment   : Privileges: Work Items: Read, Write & Manage; Code: Read | Expires: 2025-03-16 | Updated: 2025-12-16 12:00:00 by FKGEISTA
```

### **Check Backups**
```powershell
Get-ChildItem "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\GlobalSettings_backup_*.json" | 
    Sort-Object LastWriteTime -Descending | 
    Select-Object -First 5
```

---

## 📚 Related Files

- **Setup Script:** `Setup-AzureDevOpsPAT.ps1` (contains update logic)
- **Functions:** `Get-AzureDevOpsPat.ps1` (for GlobalFunctions)
- **Main README:** `README.md`
- **Cursor Rules:** `.cursorrules` (service account configured)

---

## ✅ Summary

**Service Account Integration Features:**

✅ **Auto-detection** - Recognizes service account email  
✅ **Prompts user** - Asks before updating global file  
✅ **Creates backup** - Timestamped backup before changes  
✅ **Updates Pat only** - Preserves Organization, Project, Repository  
✅ **Adds metadata** - PatComment with privileges and expiry  
✅ **Error handling** - Safe updates with rollback capability  
✅ **Confirmation** - Shows what was updated and what was preserved  

**Result:** Service account PAT can be managed centrally and made available to all servers!

---

**Feature:** Service Account GlobalSettings.json Integration  
**Version:** 1.0  
**Date:** 2025-12-16  
**Status:** ✅ Implemented  
**No Linter Errors:** ✅
