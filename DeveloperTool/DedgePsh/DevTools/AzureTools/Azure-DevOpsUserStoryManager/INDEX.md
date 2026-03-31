# Azure DevOps User Story Manager - Documentation Index

**Your complete guide to all documentation files**

---

## 🚀 Start Here

| If you want to... | Read this file |
|-------------------|----------------|
| **Get started in 5 minutes** | [QUICKSTART.md](QUICKSTART.md) |
| **See what this is** | [FINAL-SUMMARY.md](FINAL-SUMMARY.md) |
| **Quick command reference** | [QUICK-REFERENCE-CARD.md](QUICK-REFERENCE-CARD.md) |
| **Complete usage guide** | [README.md](README.md) |

---

## 📚 All Documentation Files

### **Getting Started**
| File | Purpose | Who Should Read |
|------|---------|-----------------|
| [QUICKSTART.md](QUICKSTART.md) | 5-minute getting started guide | **Everyone - Start here!** |
| [QUICK-REFERENCE-CARD.md](QUICK-REFERENCE-CARD.md) | Printable command reference | Everyone |
| [README.md](README.md) | Complete usage guide | Everyone |

### **Setup & Configuration**
| File | Purpose | Who Should Read |
|------|---------|-----------------|
| [TEAM-CONFIGURATION.md](TEAM-CONFIGURATION.md) | Team member configuration guide | Team leads, new members |
| [TEAM-CONFIG-UPDATE-SUMMARY.md](TEAM-CONFIG-UPDATE-SUMMARY.md) | Team config implementation | Optional reading |
| [NOTE-PAT-MOVED.md](NOTE-PAT-MOVED.md) | ⚠️ PAT management moved to new folder | Everyone (points to new location) |

### **PAT Management (Moved to Dedicated Folder)**
| File | Purpose | Location |
|------|---------|----------|
| [../Azure-DevOpsPAT-Manager/README.md](../Azure-DevOpsPAT-Manager/README.md) | How to set up Azure PAT | **Use this for PAT setup** |
| [../Azure-DevOpsPAT-Manager/Setup-AzureDevOpsPAT.ps1](../Azure-DevOpsPAT-Manager/Setup-AzureDevOpsPAT.ps1) | PAT setup script | Run this to configure PAT |
| [../Azure-DevOpsPAT-Manager/Get-AzureDevOpsPat.ps1](../Azure-DevOpsPAT-Manager/Get-AzureDevOpsPat.ps1) | Functions for GlobalFunctions | For admin integration |

### **Implementation & Technical**
| File | Purpose | Who Should Read |
|------|---------|-----------------|
| [IMPLEMENTATION-SUMMARY.md](IMPLEMENTATION-SUMMARY.md) | What was built and how | Developers, maintainers |
| [Azure-DevOpsUserStoryManager-Analysis.md](Azure-DevOpsUserStoryManager-Analysis.md) | Technical deep dive (981 lines!) | Developers |
| [CHANGELOG.md](CHANGELOG.md) | Version history and changes | When troubleshooting |
| [FINAL-SUMMARY.md](FINAL-SUMMARY.md) | Complete project overview | Project managers |

### **Integration & Examples**
| File | Purpose | Who Should Read |
|------|---------|-----------------|
| [CURSORRULES-EXAMPLE.md](CURSORRULES-EXAMPLE.md) | Cursor AI integration guide | Everyone using Cursor |
| [Examples/Example-CompleteFeature.ps1](Examples/Example-CompleteFeature.ps1) | Complete feature workflow | Developers |
| [Examples/Example-QuickUpdate.ps1](Examples/Example-QuickUpdate.ps1) | Quick status updates | Everyone |
| [Examples/Example-GitIntegration.ps1](Examples/Example-GitIntegration.ps1) | Git commit integration | Advanced users |

### **Scripts**
| File | Purpose | When to Run |
|------|---------|-------------|
| [Azure-DevOpsUserStoryManager.ps1](Azure-DevOpsUserStoryManager.ps1) | Main application | Anytime to manage work items |
| [_deploy.ps1](_deploy.ps1) | Deployment script | When deploying to servers |

### **PAT Management (Separate Folder)**
| File | Purpose | When to Run |
|------|---------|-------------|
| [../Azure-DevOpsPAT-Manager/Setup-AzureDevOpsPAT.ps1](../Azure-DevOpsPAT-Manager/Setup-AzureDevOpsPAT.ps1) | PAT setup helper | First time, when PAT expires |
| [../Azure-DevOpsPAT-Manager/Get-AzureDevOpsPat.ps1](../Azure-DevOpsPAT-Manager/Get-AzureDevOpsPat.ps1) | Functions for GlobalFunctions | Admin integration |
| [../Azure-DevOpsPAT-Manager/README.md](../Azure-DevOpsPAT-Manager/README.md) | PAT Manager documentation | Setup and troubleshooting |

---

## 🎯 By User Type

### **First-Time User**
1. [QUICKSTART.md](QUICKSTART.md) - Start here
2. [PAT-SETUP-README.md](PAT-SETUP-README.md) - Set up your PAT
3. [QUICK-REFERENCE-CARD.md](QUICK-REFERENCE-CARD.md) - Keep handy
4. [README.md](README.md) - Learn all features

### **Regular User**
1. [QUICK-REFERENCE-CARD.md](QUICK-REFERENCE-CARD.md) - Daily commands
2. [Examples/](Examples/) - Copy useful patterns
3. [CURSORRULES-EXAMPLE.md](CURSORRULES-EXAMPLE.md) - Cursor integration

### **Team Lead**
1. [TEAM-CONFIGURATION.md](TEAM-CONFIGURATION.md) - Team setup
2. [FINAL-SUMMARY.md](FINAL-SUMMARY.md) - Complete overview
3. [TEAM-CONFIG-UPDATE-SUMMARY.md](TEAM-CONFIG-UPDATE-SUMMARY.md) - How team config works

### **Developer/Maintainer**
1. [IMPLEMENTATION-SUMMARY.md](IMPLEMENTATION-SUMMARY.md) - Architecture
2. [Azure-DevOpsUserStoryManager-Analysis.md](Azure-DevOpsUserStoryManager-Analysis.md) - Deep dive
3. [CHANGELOG.md](CHANGELOG.md) - Version history
4. [../Azure-DevOpsPAT-Manager/Get-AzureDevOpsPat.ps1](../Azure-DevOpsPAT-Manager/Get-AzureDevOpsPat.ps1) - PAT functions for GlobalFunctions

### **Troubleshooter**
1. [README.md](README.md) - Troubleshooting section
2. [../Azure-DevOpsPAT-Manager/README.md](../Azure-DevOpsPAT-Manager/README.md) - PAT issues and setup
3. [CHANGELOG.md](CHANGELOG.md) - Known issues
4. [NOTE-PAT-MOVED.md](NOTE-PAT-MOVED.md) - PAT management moved

---

## 📊 Documentation Statistics

- **Total Files:** 16 (13 docs + 3 scripts)
- **Total Lines:** 10,500+
- **Code Lines:** 2,000+
- **Documentation Lines:** 8,500+
- **Example Scripts:** 3
- **Core Functions:** 25+

---

## 🎓 Learning Path

### **Day 1: Setup**
1. Read: [QUICKSTART.md](QUICKSTART.md)
2. Navigate to: `cd ..\Azure-DevOpsPAT-Manager`
3. Run: `.\Setup-AzureDevOpsPAT.ps1`
4. Test: `/ado` in Cursor

### **Day 2: Basic Usage**
1. Read: [QUICK-REFERENCE-CARD.md](QUICK-REFERENCE-CARD.md)
2. Try: Get, Update, Comment operations
3. Practice: `/ado` commands in Cursor

### **Day 3: Advanced Features**
1. Read: [README.md](README.md) - Complete guide
2. Try: Attach files, Link code, Create subtasks
3. Explore: [Examples/](Examples/) folder

### **Week 2: Master It**
1. Read: [CURSORRULES-EXAMPLE.md](CURSORRULES-EXAMPLE.md)
2. Create: Custom workflow scripts
3. Integrate: With your git workflow

---

## 🔍 Find Specific Information

| Looking for... | Check |
|----------------|-------|
| How to set up PAT | [../Azure-DevOpsPAT-Manager/README.md](../Azure-DevOpsPAT-Manager/README.md) |
| Cursor commands | [CURSORRULES-EXAMPLE.md](CURSORRULES-EXAMPLE.md), [QUICK-REFERENCE-CARD.md](QUICK-REFERENCE-CARD.md) |
| Team config | [TEAM-CONFIGURATION.md](TEAM-CONFIGURATION.md) |
| Your PAT location | [../Azure-DevOpsPAT-Manager/README.md](../Azure-DevOpsPAT-Manager/README.md) |
| Command examples | [README.md](README.md), [Examples/](Examples/) |
| What changed | [CHANGELOG.md](CHANGELOG.md) |
| Technical details | [Azure-DevOpsUserStoryManager-Analysis.md](Azure-DevOpsUserStoryManager-Analysis.md) |
| Complete overview | [FINAL-SUMMARY.md](FINAL-SUMMARY.md) |
| PAT moved notice | [NOTE-PAT-MOVED.md](NOTE-PAT-MOVED.md) |

---

## 📱 Contact Info Auto-Detection

**Your email and SMS are automatically detected!**

```powershell
# Get your info
Get-CurrentUserEmail      # Your email
Get-CurrentUserSms        # Your SMS number
Get-CurrentUserFullName   # Your full name
```

| Username | Auto-Detected Email |
|----------|---------------------|
| FKGEISTA | geir.helge.starholm@Dedge.no |
| FKSVEERI | svein.morten.erikstad@Dedge.no |
| FKMISTA | mina.marie.starholm@Dedge.no |
| FKCELERI | Celine.Andreassen.Erikstad@Dedge.no |

---

## 🆘 Quick Help

### **PAT Not Configured**
```powershell
cd ..\Azure-DevOpsPAT-Manager
.\Setup-AzureDevOpsPAT.ps1
```

### **PAT Expired**
```powershell
cd ..\Azure-DevOpsPAT-Manager
.\Setup-AzureDevOpsPAT.ps1  # Creates new one
```

### **Check Status**
```powershell
Show-AzureDevOpsConfig
```

### **Test Connection**
```powershell
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 274033 -Action Get
```

---

## 🎯 Most Common Commands

### **1. Check Work Item**
```
/ado 12345
```

### **2. Complete Feature**
```
"I completed feature 12345"
```
Cursor automatically updates work item!

### **3. Add Comment**
```powershell
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 `
    -Action Comment -Comment "Done and tested"
```

### **4. Change Status to Active**
```powershell
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 12345 `
    -Action Status -State "Active"
```

### **5. Interactive Mode**
```powershell
.\Azure-DevOpsUserStoryManager.ps1 -Interactive
```

---

## 📂 File Locations

**Main Script:**
```
C:\opt\src\DedgePsh\DevTools\AdminTools\Azure-DevOpsUserStoryManager\
```

**Your PAT File:**
```
C:\opt\data\UserConfig\{YourUsername}\AzureDevOpsPat.json
```

**Cursor Rules:**
```
C:\opt\src\DedgePsh\.cursorrules
```

---

## ✅ Checklist for New Users

- [ ] Install Azure CLI: `winget install Microsoft.AzureCLI`
- [ ] Navigate to: `cd ..\Azure-DevOpsPAT-Manager`
- [ ] Run PAT setup: `.\Setup-AzureDevOpsPAT.ps1`
- [ ] Create PAT in browser
- [ ] Paste PAT when prompted
- [ ] Test with: `/ado` command
- [ ] Read: [QUICK-REFERENCE-CARD.md](QUICK-REFERENCE-CARD.md)
- [ ] Bookmark this INDEX.md file

---

## 🎉 You're Ready!

**Everything you need is documented and ready to use!**

**Start with:** [QUICKSTART.md](QUICKSTART.md)  
**Questions?** Check [README.md](README.md)  
**Issues?** See troubleshooting in [PAT-SETUP-README.md](PAT-SETUP-README.md)

---

**Last Updated:** 2025-12-16  
**Total Documentation:** 13 files, 8,500+ lines  
**Status:** ✅ Complete

**Happy automating!** 🚀
