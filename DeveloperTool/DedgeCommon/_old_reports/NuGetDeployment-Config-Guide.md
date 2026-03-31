# AzureAccessTokens.json - Centralized Configuration Guide

**Purpose:** Single configuration file for all Azure access tokens and NuGet deployments

---

## 🎯 Overview

Store all your Azure DevOps PATs in **one centralized file** for all NuGet deployments!

**Location:** `%OneDriveCommercial%\AzureAccessTokens.json`  
**Note:** Directly under OneDrive root, not in Documents folder

---

## 📋 File Structure

```json
{
  "DefaultPAT": "YOUR_AZURE_DEVOPS_PAT",
  "DefaultEmail": "your.email@company.com",
  "DefaultNuGetSource": "Dedge",
  "LastUpdated": "2025-12-17",
  "Notes": "Centralized config for all NuGet packages. Update PAT when expires.",
  "Packages": {
    "Dedge.DedgeCommon": {
      "PAT": "",
      "NuGetSource": "Dedge",
      "NuGetSourceUrl": "https://pkgs.dev.azure.com/org/project/_packaging/feed/nuget/v3/index.json",
      "Notes": "Leave PAT empty to use DefaultPAT"
    },
    "YourOtherPackage": {
      "PAT": "PACKAGE_SPECIFIC_PAT",
      "NuGetSource": "OtherFeed",
      "Notes": "Can override with package-specific PAT if needed"
    }
  }
}
```

---

## 🔧 How It Works

### Priority Order for PAT:
1. **Parameter** - `-PAT` parameter (highest priority)
2. **Package-Specific** - `Packages.<PackageId>.PAT` (if not empty)
3. **Default** - `DefaultPAT` (fallback)
4. **Prompt** - Manual entry (last resort)

### Priority Order for NuGet Source:
1. **Parameter** - `-NuGetSource` parameter
2. **Package-Specific** - `Packages.<PackageId>.NuGetSource`
3. **Default** - `DefaultNuGetSource`

---

## 💡 Use Cases

### Use Case 1: All Packages Use Same PAT (Recommended)
```json
{
  "DefaultPAT": "YOUR_PAT_FOR_ALL_PACKAGES",
  "DefaultEmail": "dev@company.com",
  "DefaultNuGetSource": "Dedge",
  "Packages": {
    "Dedge.DedgeCommon": {
      "PAT": "",
      "Notes": "Uses DefaultPAT"
    },
    "MyOtherLibrary": {
      "PAT": "",
      "Notes": "Uses DefaultPAT"
    },
    "AnotherPackage": {
      "PAT": "",
      "Notes": "Uses DefaultPAT"
    }
  }
}
```

**Benefit:** Update PAT in one place, affects all packages!

### Use Case 2: Mix of Default and Package-Specific PATs
```json
{
  "DefaultPAT": "GENERAL_PURPOSE_PAT",
  "Packages": {
    "PublicPackage": {
      "PAT": "NUGET_ORG_PAT",
      "NuGetSource": "nuget.org",
      "Notes": "Uses different PAT for public feed"
    },
    "PrivatePackage1": {
      "PAT": "",
      "Notes": "Uses DefaultPAT for Azure DevOps"
    },
    "PrivatePackage2": {
      "PAT": "",
      "Notes": "Uses DefaultPAT for Azure DevOps"
    }
  }
}
```

### Use Case 3: Different Feeds
```json
{
  "DefaultPAT": "AZURE_DEVOPS_PAT",
  "Packages": {
    "InternalTool": {
      "PAT": "",
      "NuGetSource": "Dedge"
    },
    "SharedLibrary": {
      "PAT": "",
      "NuGetSource": "SharedFeed"
    },
    "PublicLibrary": {
      "PAT": "PUBLIC_NUGET_PAT",
      "NuGetSource": "nuget.org"
    }
  }
}
```

---

## 🚀 Benefits

### 1. Single PAT Management
- ✅ Update PAT in one place
- ✅ Automatically affects all packages
- ✅ No need to update multiple files

### 2. Flexibility
- ✅ Can override per package if needed
- ✅ Support multiple feeds
- ✅ Mix default and specific PATs

### 3. Organized
- ✅ All deployment config in one file
- ✅ Easy to see all your packages
- ✅ Centralized documentation

### 4. Synchronized
- ✅ Stored in OneDrive
- ✅ Synced across devices
- ✅ Backed up automatically

---

## 📖 Migration Guide

### From Legacy Config Files

**Old Way (Multiple Files):**
```
Documents\
├── Dedge.DedgeCommonConfig.json
├── MyOtherPackageConfig.json
├── AnotherPackageConfig.json
└── ... (one file per package)
```

**New Way (One File):**
```
Documents\
└── NuGetDeployment.json (contains all packages)
```

### Migration Steps:

1. **Create centralized config** (done ✅)
2. **Copy PAT from old configs** to `DefaultPAT`
3. **Add package entries** to `Packages` section
4. **Test deployment** - script automatically uses new config
5. **Delete old configs** - once verified working

---

## 🔐 Security Best Practices

### PAT Management
1. **One PAT for Multiple Packages** - Simplifies management
2. **Rotate Regularly** - Update `DefaultPAT` when expires
3. **Minimum Permissions** - Only "Packaging (Read, write, & manage)"
4. **Service Account** - Use service account PAT for automation

### File Security
- ✅ Stored in OneDrive (encrypted in transit)
- ✅ Outside git repository
- ✅ Backed up automatically
- ⚠️ PAT is in plain text - protect file access

---

## 📊 Example: Managing Multiple Packages

```json
{
  "DefaultPAT": "YOUR_MAIN_PAT",
  "DefaultEmail": "dev-team@company.com",
  "DefaultNuGetSource": "Dedge",
  "LastUpdated": "2025-12-17",
  "Packages": {
    "Dedge.DedgeCommon": {
      "PAT": "",
      "NuGetSource": "Dedge"
    },
    "Dedge.Infrastructure": {
      "PAT": "",
      "NuGetSource": "Dedge"
    },
    "Dedge.DevTools": {
      "PAT": "",
      "NuGetSource": "Dedge"
    },
    "CompanyPublicLib": {
      "PAT": "DIFFERENT_PAT_FOR_PUBLIC",
      "NuGetSource": "nuget.org"
    }
  }
}
```

**Usage:**
```powershell
# All use same config file
.\Deploy-NuGetPackage.ps1 -ProjectFile "DedgeCommon\DedgeCommon.csproj" -Force
.\Deploy-NuGetPackage.ps1 -ProjectFile "Infrastructure\Infrastructure.csproj" -Force
.\Deploy-NuGetPackage.ps1 -ProjectFile "DevTools\DevTools.csproj" -Force
```

---

## 🔄 Backward Compatibility

The script still supports legacy package-specific config files:

**Priority Order:**
1. Centralized config (`NuGetDeployment.json`) - **Checked first**
2. Legacy config (`<PackageId>Config.json`) - **Fallback**
3. Manual prompt - **Last resort**

**Transition Period:**
- ✅ Old configs still work
- ✅ Migrate at your own pace
- ✅ Both formats supported

---

## ✅ Quick Start

### For DedgeCommon
1. Config file already created ✅
2. Update `DefaultPAT` with valid PAT
3. Run: `.\Deploy-NuGetPackage.ps1 -Force`

### For New Packages
1. Add entry to `Packages` section
2. Use empty PAT to use default
3. Deploy: `.\Deploy-NuGetPackage.ps1 -ProjectFile "NewPackage.csproj" -Force`

---

## 🎯 Config File Location

### Default Location
**Path:** `%OneDriveCommercial%\Documents\NuGetDeployment.json`

**To Edit:**
```powershell
# Open in notepad
notepad "$env:OneDriveCommercial\Documents\NuGetDeployment.json"

# Or in VS Code
code "$env:OneDriveCommercial\Documents\NuGetDeployment.json"
```

### Override with Environment Variable

You can override the config file location using the `NUGET_DEPLOY_CONFIG` environment variable:

**Set for Current Session:**
```powershell
$env:NUGET_DEPLOY_CONFIG = "C:\MyCustomLocation\MyNuGetConfig.json"
.\Deploy-NuGetPackage.ps1 -Force
```

**Set Permanently (User):**
```powershell
[Environment]::SetEnvironmentVariable("NUGET_DEPLOY_CONFIG", "C:\MyCustomLocation\MyNuGetConfig.json", "User")
```

**Set Permanently (System - requires admin):**
```powershell
[Environment]::SetEnvironmentVariable("NUGET_DEPLOY_CONFIG", "C:\MyCustomLocation\MyNuGetConfig.json", "Machine")
```

**Use Cases:**
- Different config for dev/prod environments
- Team-shared config on network drive
- CI/CD pipeline with custom config
- Multiple profiles for different feeds

**Example:**
```powershell
# Development config
$env:NUGET_DEPLOY_CONFIG = "\\teamshare\configs\NuGetDev.json"
Deploy-NuGetPackage.ps1 -Force

# Production config  
$env:NUGET_DEPLOY_CONFIG = "\\teamshare\configs\NuGetProd.json"
Deploy-NuGetPackage.ps1 -Force
```

---

## 📝 Template for New Packages

Add this to the `Packages` section:

```json
"YourPackageId": {
  "PAT": "",
  "NuGetSource": "Dedge",
  "NuGetSourceUrl": "https://...",
  "Notes": "Description of this package"
}
```

Leave `PAT` empty to use `DefaultPAT`.

---

**Created:** 2025-12-17  
**File:** NuGetDeployment.json  
**Status:** Active  
**Benefit:** One file for all packages!
