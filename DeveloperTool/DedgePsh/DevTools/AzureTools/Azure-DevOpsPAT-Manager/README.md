# Azure DevOps PAT Manager

**Centralized PAT (Personal Access Token) management for Azure DevOps with user-specific secure storage**

---

## 📖 Overview

This tool manages Azure DevOps Personal Access Tokens (PATs) for all team members with:
- ✅ User-specific secure storage
- ✅ Automatic email detection
- ✅ Guided PAT creation process
- ✅ Validation and testing
- ✅ Azure CLI configuration

---

## 📁 PAT Storage Locations

Each user has their own isolated PAT file:

```
C:\opt\data\UserConfig\
├── FKGEISTA\AzureDevOpsPat.json  ← Geir's PAT
├── FKSVEERI\AzureDevOpsPat.json  ← Svein's PAT
├── FKMISTA\AzureDevOpsPat.json   ← Mina's PAT
└── FKCELERI\AzureDevOpsPat.json  ← Celine's PAT
```

**Pattern:** `C:\opt\data\UserConfig\{USERNAME}\AzureDevOpsPat.json`

---

## 🚀 Quick Start

### **Run Setup (Email Auto-Detected)**
```powershell
cd C:\opt\src\DedgePsh\DevTools\AdminTools\Azure-DevOpsPAT-Manager

# Email is automatically detected from your username!
.\Setup-AzureDevOpsPAT.ps1
```

**That's it!** The script will:
1. Auto-detect your email
2. Open browser for PAT creation
3. Guide you through the process with **required scopes**
4. Save PAT to your user-specific location
5. **If service account:** Prompt to update GlobalSettings.json
6. Configure Azure CLI

### **Required PAT Scopes**

When creating your PAT in the browser, select these scopes:

| Scope | Permission | Purpose |
|-------|------------|---------|
| **Work Items** | Read, Write & Manage | Create/update work items, add comments, attachments |
| **Code** | Read & Write | Read repositories, link code files, access repo content |
| **Packaging** | Read & Write | Manage NuGet packages and artifacts for the project |

**These scopes enable ALL features in Azure-DevOpsUserStoryManager and related tools.**

### **Service Account Setup**

If you're setting up the service account PAT:

```powershell
.\Setup-AzureDevOpsPAT.ps1 -Email "srv_Dedge_repo@Dedge.onmicrosoft.com"
```

**Additional step:** The script will prompt to update the common config file:
- Location: `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\GlobalSettings.json`
- Updates: Organization, Project, Repository, Pat
- Creates backup before updating
- Makes PAT available globally to all servers

---

## 👥 Team Members

| Username | Email | PAT Location |
|----------|-------|--------------|
| FKGEISTA | geir.helge.starholm@Dedge.no | `C:\opt\data\UserConfig\FKGEISTA\AzureDevOpsPat.json` |
| FKSVEERI | svein.morten.erikstad@Dedge.no | `C:\opt\data\UserConfig\FKSVEERI\AzureDevOpsPat.json` |
| FKMISTA | mina.marie.starholm@Dedge.no | `C:\opt\data\UserConfig\FKMISTA\AzureDevOpsPat.json` |
| FKCELERI | Celine.Andreassen.Erikstad@Dedge.no | `C:\opt\data\UserConfig\FKCELERI\AzureDevOpsPat.json` |

---

## 📝 Files in This Folder

| File | Purpose |
|------|---------|
| `Setup-AzureDevOpsPAT.ps1` | PAT setup script (main tool) |
| `Get-AzureDevOpsPat.ps1` | Functions to add to GlobalFunctions |
| `README.md` | This file |
| `_deploy.ps1` | Deployment script |

---

## 🔧 Integration with GlobalFunctions

Copy the functions from `Get-AzureDevOpsPat.ps1` into `GlobalFunctions.psm1`:

### **Functions to Add:**
- `Get-CurrentUserConfig` - User info by username
- `Get-CurrentUserEmail` - Auto-detected email
- `Get-CurrentUserSms` - Auto-detected SMS
- `Get-CurrentUserFullName` - Full name
- `Get-AzureDevOpsPatConfigFile` - PAT file path
- `Test-AzureDevOpsPatConfigured` - Check if PAT exists
- `Get-AzureDevOpsStoredConfig` - Load PAT config
- `Get-AzureDevOpsPat` - Get PAT (prompts if missing)
- `Get-AzureDevOpsOrganization` - Organization name
- `Get-AzureDevOpsProject` - Project name
- `Get-AzureDevOpsRepository` - Repository name
- `Test-AzureDevOpsConfig` - Validate config
- `Show-AzureDevOpsConfig` - Display config

---

## 🎯 Usage Examples

### **Setup PAT (First Time)**
```powershell
.\Setup-AzureDevOpsPAT.ps1
# Email auto-detected: geir.helge.starholm@Dedge.no (if you're FKGEISTA)
```

### **Check Your Configuration**
```powershell
Import-Module GlobalFunctions -Force
Show-AzureDevOpsConfig
```

### **Get Your PAT**
```powershell
$pat = Get-AzureDevOpsPat
# Loads from: C:\opt\data\UserConfig\{YourUsername}\AzureDevOpsPat.json
```

### **Check if Configured**
```powershell
if (Test-AzureDevOpsPatConfigured) {
    Write-Host "PAT is configured"
}
else {
    Write-Host "PAT needs setup"
}
```

---

## 📋 Complete PAT Scopes Reference

For detailed information about required scopes, see: [PAT-SCOPES-GUIDE.md](PAT-SCOPES-GUIDE.md)

**Quick Reference:**
- Work Items: Read, Write & Manage
- Code: Read & Write
- Packaging: Read & Write

---

## 🔐 Security Features

### **1. User-Specific Storage**
- Each user has separate directory
- No shared credential files
- Complete isolation between users

### **2. Secure Input**
- PAT input is hidden (no echo)
- Secure string handling
- Automatic memory cleanup

### **3. Validation**
- PAT tested before saving
- Permissions verified
- Project access confirmed

### **4. Audit Trail**
- Tracks who updated last
- Stores update timestamp
- Easy to identify configured users

---

## 📱 Related Tools

### **Azure DevOps User Story Manager**
Uses PAT from this manager:
```
Location: DevTools/AdminTools/Azure-DevOpsUserStoryManager
Uses: Get-AzureDevOpsPat to get PAT automatically
```

### **Other Azure DevOps Tools**
Any tool needing Azure DevOps PAT should use:
```powershell
Import-Module GlobalFunctions -Force
$pat = Get-AzureDevOpsPat  # Auto-loads from user-specific location
```

---

## 🆘 Troubleshooting

### **PAT Not Found**
```powershell
# Check if configured
Test-AzureDevOpsPatConfigured

# If false, run setup
.\Setup-AzureDevOpsPAT.ps1
```

### **PAT Expired (401 Errors)**
```powershell
# Run setup again to create new PAT
.\Setup-AzureDevOpsPAT.ps1
```

### **Check Configuration**
```powershell
Show-AzureDevOpsConfig
```

### **Manual PAT File Check**
```powershell
$patFile = "C:\opt\data\UserConfig\$env:USERNAME\AzureDevOpsPat.json"
Test-Path $patFile
```

---

## 💡 For Other Tools

If you're creating a new tool that needs Azure DevOps PAT:

```powershell
Import-Module GlobalFunctions -Force

# Get PAT (prompts for setup if missing)
$pat = Get-AzureDevOpsPat

# Or check first
if (Test-AzureDevOpsPatConfigured) {
    $pat = Get-AzureDevOpsPat
    # Use PAT for Azure DevOps operations
}
else {
    Write-Host "Please run Setup-AzureDevOpsPAT.ps1 first"
}
```

---

## 🔧 Service Account Integration

### **GlobalSettings.json Update**

When setting up PAT for service account (`srv_Dedge_repo@Dedge.onmicrosoft.com`), the script offers to update the global configuration file.

**File Location:**
```
C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\GlobalSettings.json
```

**Fields Updated:**
```json
{
  "AzureDevOps": {
    "Organization": "Dedge",           ← Preserved (not changed)
    "Project": "Dedge",                      ← Preserved (not changed)
    "Repository": "Dedge",                   ← Preserved (not changed)
    "Pat": "new-service-account-pat-token",   ← UPDATED
    "PatComment": "Privileges: Work Items: Read, Write & Manage | Expires: 2025-03-16 | Updated: 2025-12-16 by FKGEISTA"  ← UPDATED
  }
}
```

**Process:**
1. Script detects service account email
2. Prompts for PAT privileges and expiry days
3. Prompts: "Do you want to update the common config file? (y/n)"
4. If yes:
   - Creates backup: `GlobalSettings_backup_yyyyMMddHHmmss.json`
   - Updates ONLY Pat and PatComment fields
   - Preserves Organization, Project, Repository
   - Saves updated configuration
   - PAT available globally to all servers

**Benefits:**
- ✅ Service account PAT available system-wide
- ✅ Automatic backup before changes
- ✅ All servers can use updated PAT
- ✅ Preserves existing configuration
- ✅ Documents privileges and expiry date
- ✅ Tracks who updated and when

---

## 📚 Related Documentation

- **Azure DevOps User Story Manager:** `../Azure-DevOpsUserStoryManager/README.md`
- **Team Configuration Guide:** `../Azure-DevOpsUserStoryManager/TEAM-CONFIGURATION.md`
- **Cursor Rules:** `../../../.cursorrules`

---

## 🎉 Summary

This folder contains the **centralized PAT management system** for Azure DevOps:

✅ **User-specific secure storage**  
✅ **Automatic email detection**  
✅ **Guided setup process**  
✅ **Validation and testing**  
✅ **Azure CLI configuration**  
✅ **Service account GlobalSettings.json integration**  
✅ **Functions for GlobalFunctions integration**  

**Purpose:** Separate PAT management from individual Azure DevOps tools for better organization and reusability.

---

**Location:** `DevTools/AdminTools/Azure-DevOpsPAT-Manager/`  
**Version:** 1.0  
**Date:** 2025-12-16  
**Status:** ✅ Production Ready
