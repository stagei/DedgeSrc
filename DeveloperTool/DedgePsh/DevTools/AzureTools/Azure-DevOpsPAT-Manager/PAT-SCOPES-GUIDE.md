# Azure DevOps PAT Scopes Guide

**Complete guide to required PAT permissions for Dedge project**

---

## 🎯 Required Scopes for All Users

**For full functionality of all Azure DevOps tools, your PAT must have these scopes:**

| Scope | Permission Level | Purpose |
|-------|-----------------|---------|
| **Work Items** | Read, Write & Manage | All work item operations |
| **Code** | Read & Write | Repository access and linking |
| **Packaging** | Read & Write | NuGet package management |

---

## 📋 Scope Details

### **1. Work Items: Read, Write & Manage** ✅

**Enables:**
- ✅ View work items (User Stories, Tasks, Bugs, Epics)
- ✅ Create new work items
- ✅ Update work item descriptions and fields
- ✅ Add comments/discussions
- ✅ Upload and attach files/documents
- ✅ Change work item state (New → Active → Resolved → Closed)
- ✅ Add and update tags
- ✅ Create subtasks
- ✅ Add work item relations (parent/child, dependencies)
- ✅ Manage work item queries

**Used by:**
- Azure-DevOpsUserStoryManager.ps1 (all operations)
- Azure-DevOpsItemCreator.ps1
- Import-AllTasksToAzureDevOps.ps1

**Required for Cursor `/ado` commands**

---

### **2. Code: Read & Write** ✅

**Enables:**
- ✅ Read repository contents
- ✅ Browse code files
- ✅ Link work items to code files
- ✅ Add repository hyperlinks to work items
- ✅ Push code changes (for git operations)
- ✅ Create/update branches
- ✅ Access commit history
- ✅ View pull requests

**Used by:**
- Azure-DevOpsUserStoryManager.ps1 (link repository files)
- Example-GitIntegration.ps1 (link commits to work items)
- Any tool that needs to reference code in the repository

**Note:** "Read & Write" recommended even if you only link files, to support future features.

---

### **3. Packaging: Read & Write** ✅

**Enables:**
- ✅ View NuGet packages in feeds
- ✅ Publish new NuGet packages
- ✅ Update existing packages
- ✅ Manage package versions
- ✅ Delete packages
- ✅ Access artifact feeds
- ✅ Manage package metadata

**Used by:**
- Future NuGet package automation
- Artifact management tools
- CI/CD pipelines that publish packages

**Important:** Required for complete Azure DevOps automation in Dedge project.

---

## 🔧 How to Set Scopes

### **In Azure DevOps Browser (When Creating PAT)**

1. Go to: https://dev.azure.com/Dedge/_usersSettings/tokens
2. Click "New Token"
3. Enter name: "PowerShell Automation - Full Access"
4. Set expiration: 90 days (or longer)
5. **Select these scopes:**

```
☑ Work Items
  ☑ Read
  ☑ Write  
  ☑ Manage

☑ Code
  ☑ Read
  ☑ Write

☑ Packaging
  ☑ Read
  ☑ Write
```

6. Click "Create"
7. **Copy the token immediately!**

---

## 📊 Scope Comparison

### **Minimal Scopes** (Not Recommended) ❌
```
Work Items: Read only
```
**Can only:** View work items  
**Cannot:** Update, comment, attach files, change status

### **Basic Scopes** (Limited) ⚠️
```
Work Items: Read, Write & Manage
```
**Can:** All work item operations  
**Cannot:** Link code files, manage packages

### **Recommended Scopes** (Full Functionality) ✅
```
Work Items: Read, Write & Manage
Code: Read & Write
Packaging: Read & Write
```
**Can:** Everything - all features in Azure-DevOpsUserStoryManager and more!

---

## 🎯 Feature Matrix

| Feature | Work Items | Code | Packaging |
|---------|------------|------|-----------|
| Get work item | ✅ Read | - | - |
| Update description | ✅ Write | - | - |
| Add comment | ✅ Write | - | - |
| Attach file | ✅ Write | - | - |
| Link repository file | ✅ Write | ✅ Read | - |
| Change status | ✅ Write | - | - |
| Add tags | ✅ Write | - | - |
| Create subtask | ✅ Manage | - | - |
| Push code changes | - | ✅ Write | - |
| Link commits | ✅ Write | ✅ Read | - |
| Publish NuGet package | - | - | ✅ Write |
| Manage artifacts | - | - | ✅ Write |

---

## 📝 Privilege String for Documentation

**When prompted by Setup-AzureDevOpsPAT.ps1, use:**

```
Work Items: Read, Write & Manage; Code: Read & Write; Packaging: Read & Write
```

**This is the recommended privilege string for all users and service accounts.**

---

## ⚠️ Common Mistakes

### **Mistake 1: Only selecting "Read"**
```
Work Items: Read only  ❌
```
**Problem:** Cannot update work items, add comments, or attachments  
**Fix:** Select Read, Write & Manage

### **Mistake 2: Forgetting Code scope**
```
Work Items: Read, Write & Manage  ⚠️
(No Code scope selected)
```
**Problem:** Cannot link repository files to work items  
**Fix:** Add Code: Read & Write

### **Mistake 3: Missing Packaging scope**
```
Work Items + Code selected  ⚠️
(No Packaging scope)
```
**Problem:** Cannot manage NuGet packages or artifacts  
**Fix:** Add Packaging: Read & Write

---

## 🔐 Security Considerations

### **Principle of Least Privilege**

While we recommend "Read, Write & Manage" for full functionality:
- If you only need to view work items → Use "Read" only
- If you don't need NuGet → Skip "Packaging" scope
- If you only link files, not push code → Code "Read" only

**However, for team standardization, we recommend all users have the same scopes.**

### **Scope Limitations**

**These scopes do NOT grant:**
- ❌ Project administration rights
- ❌ User management
- ❌ Pipeline creation/deletion (only execution)
- ❌ Service endpoint management
- ❌ Agent pool management

**Only grants access to:**
- ✅ Work items (within your permissions)
- ✅ Code repositories (based on repo permissions)
- ✅ Package feeds (based on feed permissions)

---

## 📚 Azure DevOps Scopes Reference

### **Available Work Item Permissions**
- **Read:** View work items and queries
- **Write:** Create and modify work items
- **Manage:** Manage queries, work item types, and settings

### **Available Code Permissions**
- **Read:** View repositories, branches, commits
- **Write:** Push changes, create branches
- **Manage:** Manage repository settings and permissions

### **Available Packaging Permissions**
- **Read:** View packages in feeds
- **Write:** Publish and update packages
- **Manage:** Manage feed settings and permissions

---

## 🎯 Recommended PAT Configuration

### **For All Team Members (FKGEISTA, FKSVEERI, FKMISTA, FKCELERI)**

**Scopes:**
```
✓ Work Items: Read, Write & Manage
✓ Code: Read & Write
✓ Packaging: Read & Write
```

**Expiration:** 90 days

**Name suggestion:** "PowerShell Automation - {Your Name}"

**Purpose:** Full Azure DevOps automation with Cursor AI and all tools

---

### **For Service Account (srv_Dedge_repo@Dedge.onmicrosoft.com)**

**Scopes:**
```
✓ Work Items: Read, Write & Manage
✓ Code: Read & Write
✓ Packaging: Read & Write
```

**Expiration:** 90 days

**Name suggestion:** "Service Account - Automation Full Access"

**Purpose:** Server-wide automation, scheduled tasks, global operations

**Additional:** Updates GlobalSettings.json for all servers

---

## ✅ Verification

### **Check Your PAT Scopes**

After creating PAT, verify in Azure DevOps:
1. Go to: https://dev.azure.com/Dedge/_usersSettings/tokens
2. Find your PAT in the list
3. Click to view details
4. Confirm scopes include:
   - ✓ Work Items (Read, Write & Manage)
   - ✓ Code (Read & Write)
   - ✓ Packaging (Read & Write)

### **Test PAT Functionality**

```powershell
# After setup, test each area:

# 1. Test work items
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 274033 -Action Get

# 2. Test code linking
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 274033 -Action Link -Url "DevTools/Script.ps1"

# 3. Test updates
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId 274033 -Action Comment -Comment "Testing PAT scopes"
```

If all tests pass, your PAT has correct scopes! ✅

---

## 📖 Documentation References

**Azure DevOps Official Docs:**
- PAT Scopes: https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate
- Work Items API: https://learn.microsoft.com/en-us/rest/api/azure/devops/wit/
- Code/Git API: https://learn.microsoft.com/en-us/rest/api/azure/devops/git/
- Packaging API: https://learn.microsoft.com/en-us/rest/api/azure/devops/artifactspackagetypes/

---

## 🎉 Summary

**For Dedge Project - All Users Need:**

```
Work Items: Read, Write & Manage
Code: Read & Write  
Packaging: Read & Write
```

**This enables:**
- ✅ Complete work item management
- ✅ Repository file linking
- ✅ NuGet package operations
- ✅ All Azure-DevOpsUserStoryManager features
- ✅ Full Cursor AI integration
- ✅ Future-proof for new features

**Setup guides you through selecting these scopes automatically!** 🚀

---

**Guide Version:** 1.0  
**Date:** 2025-12-16  
**Applies to:** Dedge Project  
**Status:** ✅ Verified via Web Search
