# DedgeCommon Deployment Guide

**Quick Reference:** How to deploy new versions of DedgeCommon

---

## 🚀 Deployment Script Location

**Use the centralized DevTools script:**
```
C:\opt\src\DedgePsh\DevTools\GitTools\Azure-NugetVersionPush\Azure-NugetVersionPush.ps1
```

**Why this script?**
- ✅ More generic and feature-rich than the local version
- ✅ Interactive menu for saved configurations
- ✅ Searches multiple locations for AzureAccessTokens.json
- ✅ Detects and notifies about duplicate configs
- ✅ Saves deployment parameters for reuse
- ✅ Shared across all Dedge projects

---

## 💻 Quick Commands

### Interactive Deployment (Recommended for First Time)
```powershell
C:\opt\src\DedgePsh\DevTools\GitTools\Azure-NugetVersionPush\Azure-NugetVersionPush.ps1
```

Shows menu of saved configurations or prompts for:
- Organization (Dedge)
- Project (Dedge)
- NuGet Feed (Dedge)
- Project File (path to DedgeCommon.csproj)

### Automated Deployment (After First Use)
```powershell
C:\opt\src\DedgePsh\DevTools\GitTools\Azure-NugetVersionPush\Azure-NugetVersionPush.ps1 -ProjectFile "C:\opt\src\DedgeCommon\DedgeCommon\DedgeCommon.csproj" -Force
```

Uses saved configuration from previous deployment.

### Specific Version
```powershell
# Jump to v2.0.0
C:\opt\src\DedgePsh\DevTools\GitTools\Azure-NugetVersionPush\Azure-NugetVersionPush.ps1 -ProjectFile "C:\opt\src\DedgeCommon\DedgeCommon\DedgeCommon.csproj" -SpecificVersion "2.0" -Force
```

### Minor/Major Version Bump
```powershell
# Minor bump (1.5.5 → 1.6.0)
C:\opt\src\DedgePsh\DevTools\GitTools\Azure-NugetVersionPush\Azure-NugetVersionPush.ps1 -ProjectFile "C:\opt\src\DedgeCommon\DedgeCommon\DedgeCommon.csproj" -VersionBump Minor -Force

# Major bump (1.5.5 → 2.0.0)
C:\opt\src\DedgePsh\DevTools\GitTools\Azure-NugetVersionPush\Azure-NugetVersionPush.ps1 -ProjectFile "C:\opt\src\DedgeCommon\DedgeCommon\DedgeCommon.csproj" -VersionBump Major -Force
```

---

## 📋 What the Script Does

1. **Version Management** - Bumps or sets version in .csproj
2. **Clean Build** - Removes old packages, builds Release
3. **PAT Loading** - Searches for AzureAccessTokens.json in standard locations
4. **Expiration Check** - Warns if PAT expiring soon
5. **Deployment** - Pushes to Azure DevOps NuGet feed
6. **Browser** - Opens package page in browser
7. **Config Save** - Saves deployment parameters for next time

---

## 🔐 Configuration

### Required: AzureAccessTokens.json

**Location:** One of these (script searches automatically):
- `%OneDriveCommercial%\AzureAccessTokens.json` ← Recommended
- `%OneDrive%\AzureAccessTokens.json`
- `%USERPROFILE%\Documents\AzureAccessTokens.json`
- `%USERPROFILE%\AppData\Roaming\AzureAccessTokens.json`
- `%USERPROFILE%\AppData\Local\AzureAccessTokens.json`

**Format:**
```json
[
  {
    "Id": "Dedge_NugetAccessToken",
    "Token": "YOUR_PAT_HERE",
    "Email": "your.email@company.com",
    "ProjectName": "Dedge",
    "ExpirationDate": "2026-12-17",
    "LastUpdated": "2025-12-18",
    "Notes": "PAT requires 'Packaging (Read, write, & manage)' permissions."
  }
]
```

### Saved Deployment Config

After first successful deployment, config is saved to:
```
C:\opt\src\DedgePsh\DevTools\GitTools\Azure-NugetVersionPush\Azure-NugetVersionPush-Config.json
```

**Format:**
```json
[
  {
    "Organization": "Dedge",
    "Project": "Dedge",
    "NuGetFeed": "Dedge",
    "ProjectFile": "C:\\opt\\src\\DedgeCommon\\DedgeCommon\\DedgeCommon.csproj"
  }
]
```

Next time you run the script without parameters, it shows a menu of saved configs!

---

## ✅ Pre-Deployment Checklist

Before deploying:
- ✅ Code changes committed to git
- ✅ Tests passing (run VerifyFunctionality)
- ✅ README.md updated if needed
- ✅ Breaking changes documented (if any)
- ✅ Valid PAT in AzureAccessTokens.json

---

## 🎯 Typical Deployment Workflow

### Bug Fix (Patch)
```powershell
# 1. Fix bug, commit changes
# 2. Deploy with patch bump
C:\opt\src\DedgePsh\DevTools\GitTools\Azure-NugetVersionPush\Azure-NugetVersionPush.ps1 -ProjectFile "C:\opt\src\DedgeCommon\DedgeCommon\DedgeCommon.csproj" -Force

# Version: 1.5.5 → 1.5.6
```

### New Feature (Minor)
```powershell
# 1. Implement feature, update README, commit
# 2. Deploy with minor bump
C:\opt\src\DedgePsh\DevTools\GitTools\Azure-NugetVersionPush\Azure-NugetVersionPush.ps1 -ProjectFile "C:\opt\src\DedgeCommon\DedgeCommon\DedgeCommon.csproj" -VersionBump Minor -Force

# Version: 1.5.5 → 1.6.0
```

### Breaking Change (Major)
```powershell
# 1. Make changes, update docs, test thoroughly, commit
# 2. Deploy with major bump
C:\opt\src\DedgePsh\DevTools\GitTools\Azure-NugetVersionPush\Azure-NugetVersionPush.ps1 -ProjectFile "C:\opt\src\DedgeCommon\DedgeCommon\DedgeCommon.csproj" -VersionBump Major -Force

# Version: 1.5.5 → 2.0.0
```

---

## 📦 Package Verification

After deployment:
1. **Browser opens** to package page automatically
2. **Verify version** appears in Azure DevOps
3. **Wait 5-10 minutes** for README to render
4. **Test in consuming app** before wider deployment

**Package URL:**
https://dev.azure.com/Dedge/Dedge/_artifacts/feed/Dedge/NuGet/Dedge.DedgeCommon

---

## ⚠️ Troubleshooting

### "No PAT found"
Create `AzureAccessTokens.json` in OneDrive root with valid PAT.

### "401 Unauthorized"
PAT is missing "Packaging (Read, write, & manage)" permission.

### "Menu shows no configs"
First time running - select parameters, they'll be saved for next time.

### "Multiple AzureAccessTokens.json found"
Script will use most recent one and notify you. Delete duplicates.

---

## 🔄 Migration from Old Script

**Old local script:** `Deploy-NuGetPackage.ps1` (moved to _old folder)  
**New centralized script:** `Azure-NugetVersionPush.ps1` in DevTools

**Benefits of new script:**
- ✅ Interactive menu for saved configurations
- ✅ Better config file searching
- ✅ Duplicate detection
- ✅ Shared across all projects
- ✅ More robust parameter handling

---

**Deployment Guide Updated:** 2025-12-18  
**Script Location:** DedgePsh\DevTools\GitTools\Azure-NugetVersionPush\  
**Status:** Production-ready
