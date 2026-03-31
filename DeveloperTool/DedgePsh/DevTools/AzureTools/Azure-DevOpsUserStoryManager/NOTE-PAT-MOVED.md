# ⚠️ PAT Management Has Moved

**Important:** Azure DevOps PAT management is now in a separate folder!

---

## 📍 New Location

```
DevTools/AdminTools/Azure-DevOpsPAT-Manager/
```

**Full path:**
```
C:\opt\src\DedgePsh\DevTools\AdminTools\Azure-DevOpsPAT-Manager\
```

---

## 🎯 Why It Moved

PAT management is now **separated** for better organization:
- ✅ Can be used by ANY Azure DevOps tool (not just User Story Manager)
- ✅ Clear separation of concerns
- ✅ Easier to find and maintain
- ✅ Reusable across projects

---

## 🚀 New Commands

### **Setup PAT**
```powershell
cd ..\Azure-DevOpsPAT-Manager
.\Setup-AzureDevOpsPAT.ps1
```

### **Check Status**
```powershell
Import-Module GlobalFunctions -Force
Show-AzureDevOpsConfig
```

---

## ⚠️ Old Files in This Folder

The following files in this folder are **deprecated** and point to old locations:

- ❌ `Setup-AzureDevOpsPAT.ps1` (old location - DO NOT USE)
- ❌ `GlobalFunctions-PAT-Helper.ps1` (old location - DO NOT USE)
- ❌ `PAT-SETUP-README.md` (old docs)
- ❌ `PAT-SETUP-SUMMARY.md` (old docs)
- ❌ `USER-SPECIFIC-PAT-STORAGE.md` (moved)

**Use the new PAT Manager folder instead!**

---

## ✅ Use This Instead

**Navigate to PAT Manager:**
```powershell
cd C:\opt\src\DedgePsh\DevTools\AdminTools\Azure-DevOpsPAT-Manager
```

**Read documentation:**
```
README.md                  - How to use PAT Manager
COMPLETE-SUMMARY.md        - Overview
REORGANIZATION-SUMMARY.md  - Why it was separated
```

---

## 📚 This Folder Now Contains

**Only Work Item Management:**
- `Azure-DevOpsUserStoryManager.ps1` ← Main tool
- `Examples/` ← Workflow examples
- `README.md` ← How to use User Story Manager
- `QUICKSTART.md` ← Quick start guide
- Other documentation for work item operations

**For PAT management, use:** `../Azure-DevOpsPAT-Manager/`

---

**Date:** 2025-12-16  
**Status:** PAT management relocated  
**New Location:** `DevTools/AdminTools/Azure-DevOpsPAT-Manager/`
