# Azure DevOps User Story Manager - Quick Reference Card

**Print this for your desk or save for quick access!**

---

## ⚡ First Time Setup (Run Once)

```powershell
cd C:\opt\src\DedgePsh\DevTools\AdminTools\Azure-DevOpsPAT-Manager
.\Setup-AzureDevOpsPAT.ps1
```

**Email auto-detected from your username!**

**PAT Manager Location:** `DevTools/AdminTools/Azure-DevOpsPAT-Manager/`

---

## 🎯 Cursor AI Commands

| Command | What It Does |
|---------|--------------|
| `/ado` | Show Azure DevOps options menu |
| `/ado 12345` | Update work item 12345 |
| `/ado new` | Create new work item (Norwegian) |
| `/ado skip` | Skip for this session |

---

## 💻 PowerShell Commands

### **Quick Commands**
```powershell
# Get work item
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 -Action Get

# Interactive mode
.\Azure-DevOpsUserStoryManager.ps1 -Interactive
```

### **All Actions**
```powershell
-Action Get          # View details
-Action Update       # Update description
-Action Comment      # Add comment
-Action Attach       # Upload file
-Action Link         # Add link (code or URL)
-Action Status       # Change state
-Action AddTags      # Add tags
-Action Subtask      # Create subtask
```

---

## 👥 Team Member Info

| User | Email | SMS |
|------|-------|-----|
| **FKGEISTA** | geir.helge.starholm@... | +4797188358 |
| **FKSVEERI** | svein.morten.erikstad@... | +4795762742 |
| **FKMISTA** | mina.marie.starholm@... | +4799348397 |
| **FKCELERI** | Celine.Andreassen.Erikstad@... | +4745269945 |

**All auto-detected based on `$env:USERNAME`!**

---

## 📍 Your PAT File Location

```
C:\opt\data\UserConfig\{YourUsername}\AzureDevOpsPat.json
```

**Examples:**
- FKGEISTA: `C:\opt\data\UserConfig\FKGEISTA\AzureDevOpsPat.json`
- FKSVEERI: `C:\opt\data\UserConfig\FKSVEERI\AzureDevOpsPat.json`

---

## ✅ Check Your Configuration

```powershell
Import-Module GlobalFunctions -Force
Show-AzureDevOpsConfig
```

---

## 🔧 Common Operations

### **Update Work Item**
```powershell
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 `
    -Action Update -Description "New description"
```

### **Add Comment**
```powershell
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 `
    -Action Comment -Comment "Completed implementation"
```

### **Link Code File**
```powershell
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 `
    -Action Link -Url "DevTools/MyScript.ps1"
```

### **Change Status**
```powershell
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 `
    -Action Status -State "Resolved"
```

States: `New`, `Active`, `Resolved`, `Closed`

---

## 📱 SMS Notifications

**Long operations (>5 minutes) automatically send SMS to YOUR number!**

No configuration needed - uses your SMS from team config.

---

## 🆘 Troubleshooting

### **PAT Not Configured**
```powershell
cd ..\Azure-DevOpsPAT-Manager
.\Setup-AzureDevOpsPAT.ps1
```

### **PAT Expired (401 Error)**
```powershell
cd ..\Azure-DevOpsPAT-Manager
.\Setup-AzureDevOpsPAT.ps1  # Creates new PAT
```

### **Check Configuration**
```powershell
Show-AzureDevOpsConfig
```

### **Azure CLI Not Installed**
```powershell
winget install Microsoft.AzureCLI
az extension add --name azure-devops --yes
```

---

## 📖 Full Documentation

| Topic | File |
|-------|------|
| Quick Start | `QUICKSTART.md` |
| Full Guide | `README.md` |
| Team Config | `TEAM-CONFIGURATION.md` |
| PAT Setup | `PAT-SETUP-README.md` |
| Examples | `Examples/` folder |

---

## 🎯 Quick Wins

### **Example 1: Get Work Item**
```
Cursor: "/ado 274033"
System: [Shows work item details]
```

### **Example 2: Complete Feature**
```
You: "I completed the login feature for story 12345"
Cursor: [Updates description, links files, changes to Resolved]
```

### **Example 3: Add Documentation**
```
You: "Attach spec.pdf to story 12345"
Cursor: [Uploads and attaches file]
```

---

## ⭐ Pro Tips

1. **Use /ado often** - Keep work items updated
2. **Link code files** - Always link implementation files
3. **Norwegian titles** - Use Norwegian for new work items
4. **Status current** - Keep work item status up to date
5. **Add comments** - Document what you did and why

---

**Version:** 2.0  
**Updated:** 2025-12-16  
**Team:** 4 members  
**Status:** ✅ Ready

**Keep this handy!** 📌
