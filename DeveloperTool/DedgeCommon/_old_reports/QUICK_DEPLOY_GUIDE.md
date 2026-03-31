sfu# DedgeCommon Quick Deploy Guide

**Purpose:** Quick reference for deploying DedgeCommon packages

---

## 🚀 Most Common Commands

### Standard Patch Version (1.4.11 → 1.4.12)
```powershell
cd C:\opt\src\DedgeCommon
.\Deploy-NuGetPackage.ps1 -Force
# After successful deployment, automatically opens Azure DevOps package page in browser!
```

### Jump to Version 2.0
```powershell
.\Deploy-NuGetPackage.ps1 -SpecificVersion "2.0" -Force
```

### Minor Version Bump (1.4.11 → 1.5.0)
```powershell
.\Deploy-NuGetPackage.ps1 -VersionBump Minor -Force
```

### Major Version Bump (1.4.11 → 2.0.0)
```powershell
.\Deploy-NuGetPackage.ps1 -VersionBump Major -Force
```

### Without Opening Browser
```powershell
.\Deploy-NuGetPackage.ps1 -Force -NoOpenBrowser
```

---

## 📋 Version Specification Features

### Auto-Completion
The script supports **partial versions** that auto-complete:

| You Specify | Becomes | Example |
|-------------|---------|---------|
| `"2"` | `"2.0.0"` | Major version jump |
| `"2.0"` | `"2.0.0"` | Major.Minor jump |
| `"2.1.5"` | `"2.1.5"` | Full version |

**Usage:**
```powershell
# These all work:
.\Deploy-NuGetPackage.ps1 -SpecificVersion "2" -Force
.\Deploy-NuGetPackage.ps1 -SpecificVersion "2.0" -Force
.\Deploy-NuGetPackage.ps1 -SpecificVersion "2.0.0" -Force
```

---

## 🔐 PAT Configuration

**Config File:** `%OneDriveCommercial%\AzureAccessTokens.json`

**Location:** Directly under your OneDrive root (not in Documents folder)

```json
{
  "DefaultPAT": "YOUR_PAT_HERE",
  "DefaultEmail": "your.email@company.com",
  "DefaultNuGetSource": "Dedge",
  "Packages": {
    "Dedge.DedgeCommon": {
      "PAT": "",
      "NuGetSource": "Dedge"
    }
  }
}
```

**Update PAT:** Edit `DefaultPAT` in AzureAccessTokens.json and run the script again.

**Environment Variable Override:**
```powershell
$env:AZURE_ACCESS_TOKENS = "C:\CustomLocation\Tokens.json"
```

---

## 🎯 Quick Scenarios

### Scenario 1: Bug Fix Release
```powershell
# 1.4.11 → 1.4.12
.\Deploy-NuGetPackage.ps1 -Force
```

### Scenario 2: New Features
```powershell
# 1.4.11 → 1.5.0
.\Deploy-NuGetPackage.ps1 -VersionBump Minor -Force
```

### Scenario 3: Breaking Changes / Major Rewrite
```powershell
# 1.4.11 → 2.0.0
.\Deploy-NuGetPackage.ps1 -VersionBump Major -Force

# Or specify directly:
.\Deploy-NuGetPackage.ps1 -SpecificVersion "2.0" -Force
```

### Scenario 4: Specific Version Needed
```powershell
# Set exact version
.\Deploy-NuGetPackage.ps1 -SpecificVersion "1.5.3" -Force
```

---

## ⚠️ If Deployment Fails (401)

**PAT is expired or invalid.**

### Fix:
1. Go to: https://dev.azure.com/Dedge/_usersSettings/tokens
2. Create new PAT with **"Packaging (Read, write, & manage)"** scope
3. Update config file: `Dedge.DedgeCommonConfig.json`
4. Run script again

---

## 📦 What Gets Built

**Current Version:** 1.4.11  
**Package Name:** Dedge.DedgeCommon  
**Location:** `DedgeCommon\bin\x64\Release\Dedge.DedgeCommon.<version>.nupkg`  

---

## ✅ Complete Workflow

```powershell
# 1. Navigate to project
cd C:\opt\src\DedgeCommon

# 2. Deploy (auto-bumps patch version)
.\Deploy-NuGetPackage.ps1 -Force

# 3. Script will:
#    - Update version (e.g., 1.4.11 → 1.4.12)
#    - Build Release package
#    - Load PAT from OneDrive config
#    - Push to Dedge feed
#    - Show summary

# 4. If successful, update consuming apps:
#    <PackageReference Include="Dedge.DedgeCommon" Version="1.4.12" />
```

---

## 🎓 Advanced Examples

### Test Build Without Deployment
```powershell
# Just press Enter when prompted for PAT
.\Deploy-NuGetPackage.ps1

# Or use empty PAT parameter
.\Deploy-NuGetPackage.ps1 -PAT "" -Force
```

### Deploy Specific Version Without Bump
```powershell
# Set exact version you want
.\Deploy-NuGetPackage.ps1 -SpecificVersion "1.5.0" -Force
```

### Deploy with Override PAT (Don't Use Config)
```powershell
.\Deploy-NuGetPackage.ps1 -PAT "TEMPORARY_PAT" -Force
```

---

## 📊 Current Status

**Package Built:** v1.4.11 ✅  
**Script Default:** DedgeCommon\DedgeCommon.csproj ✅  
**Config File:** Auto-loads from OneDrive ✅  
**PAT Status:** Needs update (401 error) ⚠️  

---

## 🎯 Next Deployment

When you have a valid PAT:

```powershell
# Just run this!
.\Deploy-NuGetPackage.ps1 -Force
```

It will automatically:
- Bump to 1.4.12
- Build package
- Load PAT from OneDrive
- Deploy to Dedge
- Show success message

---

**Quick Deploy Guide Created:** 2025-12-17  
**Current Package:** v1.4.11  
**Ready to Deploy:** Update PAT in config and run script!
