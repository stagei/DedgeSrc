# Azure-NugetVersionPush.ps1 - Generic NuGet Deployment Script

**Purpose:** Generic, reusable script for deploying any .NET NuGet package with automatic version bumping.

---

## 🎯 Overview

This script can deploy **any NuGet package** - not just DedgeCommon!

**Features:**
- ✅ Automatic version bumping (Major/Minor/Patch) or specific version setting
- ✅ Loads PAT from multiple standard locations (OneDrive, Documents, AppData, etc.)
- ✅ Interactive menu to select from saved configurations
- ✅ Works with any .csproj file
- ✅ Configurable NuGet feed and Azure DevOps project
- ✅ Detects and notifies about duplicate config files
- ✅ Saves deployment parameters for future use
- ✅ Clean build process with error handling
- ✅ Prompts for version type when using SpecificVersion

---

## 🚀 Usage

### For DedgeCommon (use the wrapper)
```powershell
# Simple - uses defaults
.\Deploy-Package.ps1 -Force

# Bump minor version
.\Deploy-Package.ps1 -VersionBump Minor -Force
```

### For Any Other Package
```powershell
# Generic script with project path
.\Azure-NugetVersionPush.ps1 `
    -ProjectFile "Path\To\YourProject.csproj" `
    -Force

# With custom feed
.\Azure-NugetVersionPush.ps1 `
    -ProjectFile "MyLib\MyLib.csproj" `
    -NuGetFeed "MyPrivateFeed" `
    -Force

# Jump to version 2.0 (auto-completes to 2.0.0)
.\Azure-NugetVersionPush.ps1 `
    -ProjectFile "MyLib\MyLib.csproj" `
    -SpecificVersion "2.0" `
    -Force

# Or just major version (becomes 2.0.0)
.\Azure-NugetVersionPush.ps1 `
    -SpecificVersion "2" `
    -Force

# Full version also supported
.\Azure-NugetVersionPush.ps1 `
    -SpecificVersion "2.1.5" `
    -Force
```

---

## 📋 Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `Organization` | No | "" | Azure DevOps organization name (prompts if empty) |
| `Project` | No | "" | Azure DevOps project name (prompts if empty) |
| `ProjectFile` | Conditional | "" | Path to .csproj file (required, shows menu if empty) |
| `NuGetFeed` | No | "" | NuGet feed name to push package to (prompts if empty) |
| `VersionBump` | No | "Patch" | Version component to bump: Major, Minor, Patch |
| `SpecificVersion` | No | (auto) | Set specific version instead of bumping (prompts for type) |
| `PAT` | No | (config/prompt) | Personal Access Token for NuGet feed |
| `AzureAccessTokensFileName` | No | "AzureAccessTokens.json" | Filename to search for when loading PAT from standard locations |
| `Force` | No | false | Skip confirmation prompts |
| `NoOpenBrowser` | No | false | Don't open browser to package page after deployment |

---

## 📁 Config File Locations

The script searches for `$AzureAccessTokensFileName` in these standard locations:

1. **OneDrive:** `%OneDriveCommercial%\AzureAccessTokens.json`
2. **OneDrive (alternate):** `%OneDrive%\AzureAccessTokens.json`
3. **Documents:** `%USERPROFILE%\Documents\AzureAccessTokens.json`
4. **AppData Roaming:** `%USERPROFILE%\AppData\Roaming\AzureAccessTokens.json`
5. **AppData Local:** `%USERPROFILE%\AppData\Local\AzureAccessTokens.json`

**Duplicate Detection:**
- If multiple files are found, the script notifies you and uses the most recently modified file
- All found instances are listed with their modification times

---

## 🔧 How It Works

### 1. Project Detection
- Reads .csproj file
- Extracts PackageId (or uses project name)
- Gets current version

### 2. Version Management
- Parses current version (Major.Minor.Patch)
- Bumps specified component
- Or sets specific version
- Updates .csproj file

### 3. Build Process
- Cleans old .nupkg files
- Builds in Release configuration
- Verifies package created

### 4. Configuration Menu
If any parameters are empty (especially ProjectFile), the script:
- Loads saved configurations from `Azure-NugetVersionPush-Config.json`
- Displays an interactive menu to select from saved configs
- Only fills empty parameters (doesn't override provided ones)
- Supports multiple saved configurations

### 5. PAT Loading
Priority order:
1. `-PAT` parameter (if provided)
2. `$AzureAccessTokensFileName` from standard locations (searches multiple folders)
3. Manual prompt (if needed)

**Config File Search:**
- Searches multiple standard locations automatically
- Detects duplicates and notifies user
- Uses most recently modified file if multiple found
- If no file is found (or token cannot be determined), the script prompts for manual PAT entry

### 6. Version Type Prompt (SpecificVersion)
When using `-SpecificVersion`, the script prompts:
- [1] Patch (bug fixes, small changes)
- [2] Minor (new features, backward compatible)
- [3] Major (breaking changes)

### 7. Deployment
- Pushes to specified NuGet feed
- Handles errors gracefully
- Provides clear feedback
- Opens package page in browser (unless `-NoOpenBrowser`)

### 8. Config Saving
After successful deployment:
- Saves Organization, Project, NuGetFeed, and ProjectFile to `Azure-NugetVersionPush-Config.json`
- Avoids duplicates (won't save if identical config already exists)
- Supports multiple saved configurations (array format)

---

## 💡 Usage Examples

### Example 1: DedgeCommon (Simple)
```powershell
cd C:\opt\src\DedgeCommon
.\Deploy-Package.ps1 -Force
# Uses: DedgeCommon\DedgeCommon.csproj, DedgeCommonNuget.json, Dedge source
```

### Example 2: Using Saved Configuration
```powershell
# Run without parameters - script will show menu to select from saved configs
.\Azure-NugetVersionPush.ps1

# Or provide only some parameters - missing ones will be loaded from saved config
.\Azure-NugetVersionPush.ps1 -Organization "Dedge" -Project "Dedge"
# ProjectFile and NuGetFeed will be selected from menu
```

### Example 3: Another Library
```powershell
cd C:\Projects\MyLibrary

# First time - provide all parameters
.\Azure-NugetVersionPush.ps1 `
    -ProjectFile "MyLibrary.csproj" `
    -Organization "Dedge" `
    -Project "MyProject" `
    -NuGetFeed "MyFeed" `
    -Force

# Next time - use saved config via menu
.\Azure-NugetVersionPush.ps1
```

### Example 4: Specific Version with Type Prompt
```powershell
.\Azure-NugetVersionPush.ps1 `
    -ProjectFile "MyLib.csproj" `
    -SpecificVersion "2.0" `
    -Force

# Script will prompt:
# What type of version change is this?
#   [1] Patch (bug fixes, small changes)
#   [2] Minor (new features, backward compatible)
#   [3] Major (breaking changes)
```

### Example 5: Public NuGet.org
```powershell
.\Azure-NugetVersionPush.ps1 `
    -ProjectFile "MyPublicLib\MyPublicLib.csproj" `
    -NuGetFeed "nuget.org" `
    -Force
```

### Example 6: Multiple Projects
```powershell
# Deploy all libraries in a solution
$projects = @(
    "Library1\Library1.csproj",
    "Library2\Library2.csproj",
    "Library3\Library3.csproj"
)

foreach ($proj in $projects) {
    .\Azure-NugetVersionPush.ps1 -ProjectFile $proj -Force
}
```

---

## 🔐 Security

**PAT Storage:**
- ✅ Stored in OneDrive (synced, backed up)
- ✅ Outside source control (not in git)
- ✅ Per-package configuration
- ✅ Easy to update when expired

**Best Practices:**
1. Use service account PATs for automation
2. Set appropriate expiration (90 days recommended)
3. Rotate PATs regularly
4. Use minimum required permissions (Packaging only)

---

## 📊 Example Output

```
=== Generic NuGet Package Deployment ===

Project: DedgeCommon
File: C:\opt\src\DedgeCommon\DedgeCommon\DedgeCommon.csproj

Current Version: 1.4.9
Target Version:  1.4.10 (Patch bump)

===============================================================

Step 1: Updating version...
  [OK] Version updated to 1.4.10

Step 2: Cleaning old packages...
  [OK] Cleaned old packages from: DedgeCommon\bin\x64\Release

Step 3: Building Release...
  Building: C:\opt\src\DedgeCommon\DedgeCommon\DedgeCommon.csproj
  [OK] Build successful

Step 4: Locating package...
  [OK] Package found
  Name: Dedge.DedgeCommon.1.4.10.nupkg
  Size: 3.45 MB
  Location: DedgeCommon\bin\x64\Release\Dedge.DedgeCommon.1.4.10.nupkg

Step 5: Getting PAT...
  Using config from: C:\Users\...\OneDrive\AzureAccessTokens.json
  Loading from: AzureAccessTokens.json
  [OK] Token loaded: NugetAccessToken
  Email: user@company.com
  Project: Dedge

Step 6: Pushing to NuGet feed (Dedge)...
  [OK] Package pushed successfully!

===============================================================
   Deployment Summary
===============================================================

Project:    Dedge.DedgeCommon
Version:    1.4.9 -> 1.4.10
Package:    Dedge.DedgeCommon.1.4.10.nupkg
Size:       3.45 MB
Feed:       Dedge
Build:      [OK]
Deploy:     [OK] Deployed

[SUCCESS] Package 1.4.10 deployed to Dedge!
```

---

## 🎓 Advanced Usage

### Custom Config Location
```powershell
# Use custom AzureAccessTokens filename (searched in standard locations)
.\Azure-NugetVersionPush.ps1 `
    -ProjectFile "MyLib.csproj" `
    -AzureAccessTokensFileName "AzureAccessTokens.json"
```

### Override Everything
```powershell
# Don't use config file, provide everything
.\Azure-NugetVersionPush.ps1 `
    -ProjectFile "MyLib.csproj" `
    -PAT "YOUR_PAT" `
    -NuGetFeed "CustomFeed" `
    -SpecificVersion "2.0.0" `
    -Force
```

### CI/CD Pipeline
```powershell
# In your build pipeline
$pat = $env:NUGET_PAT  # From secret variable

.\Azure-NugetVersionPush.ps1 `
    -ProjectFile $env:PROJECT_FILE `
    -PAT $pat `
    -Force
```

---

## 📦 DedgeCommon-Specific Wrapper

The `Deploy-Package.ps1` script is a convenience wrapper for DedgeCommon:

```powershell
# Simple wrapper
.\Deploy-Package.ps1 -Force

# Internally calls:
.\Azure-NugetVersionPush.ps1 `
    -ProjectFile "DedgeCommon\DedgeCommon.csproj" `
    -ConfigFileName "DedgeCommonNuget.json" `
    -NuGetFeed "Dedge" `
    -Force
```

You can create similar wrappers for your other packages!

---

## 🔧 Creating Wrappers for Other Projects

### Example: MyLibrary Wrapper

**File:** `Deploy-MyLibrary.ps1`
```powershell
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("Major", "Minor", "Patch")]
    [string]$VersionBump = "Patch",
    
    [Parameter(Mandatory = $false)]
    [string]$PAT,
    
    [Parameter(Mandatory = $false)]
    [switch]$Force
)

# Call generic script with MyLibrary-specific parameters
& "$PSScriptRoot\Azure-NugetVersionPush.ps1" `
    -ProjectFile "MyLibrary\MyLibrary.csproj" `
    -ConfigFileName "MyLibraryConfig.json" `
    -NuGetFeed "MyFeed" `
    -VersionBump $VersionBump `
    -PAT $PAT `
    -Force:$Force
```

---

## ✅ Benefits

### Reusability
- ✅ One script for all NuGet packages
- ✅ No code duplication
- ✅ Easy to maintain
- ✅ Consistent deployment process

### Flexibility
- ✅ Works with any .csproj
- ✅ Any NuGet source (Azure DevOps, nuget.org, private feeds)
- ✅ Custom config files
- ✅ Override any setting

### Convenience
- ✅ Auto-loads PAT from config
- ✅ Creates wrappers for quick deployment
- ✅ Handles errors gracefully
- ✅ Clear status messages

---

## 🎯 Quick Reference

### For DedgeCommon
```powershell
.\Deploy-Package.ps1 -Force
```

### For Any Other Package
```powershell
.\Azure-NugetVersionPush.ps1 -ProjectFile "Path\To\Project.csproj" -Force
```

### With Custom Everything
```powershell
.\Azure-NugetVersionPush.ps1 `
    -ProjectFile "Project.csproj" `
    -SpecificVersion "2.0.0" `
    -PAT "YOUR_PAT" `
    -NuGetFeed "YourFeed" `
    -Force
```

---

---

## 💾 Saved Configuration File

The script saves successful deployment parameters to `Azure-NugetVersionPush-Config.json` in the same folder as the script.

**Format:**
```json
[
  {
    "Organization": "Dedge",
    "Project": "Dedge",
    "NuGetFeed": "Dedge",
    "ProjectFile": "C:\\opt\\src\\DedgeCommon\\DedgeCommon\\DedgeCommon.csproj"
  },
  {
    "Organization": "Dedge",
    "Project": "OtherProject",
    "NuGetFeed": "OtherFeed",
    "ProjectFile": "C:\\opt\\src\\OtherProject\\OtherProject.csproj"
  }
]
```

**Features:**
- Multiple configurations supported (array format)
- Duplicate detection (won't save identical configs)
- Automatically used when parameters are empty
- Interactive menu for selection

---

## 🔍 Duplicate Config File Detection

If multiple `AzureAccessTokens.json` files are found in different locations, the script will:

1. **List all found instances** with modification times
2. **Use the most recently modified file**
3. **Notify you** about the duplicates

**Example warning:**
```
[WARNING] Found 2 instances of AzureAccessTokens.json:
  - C:\Users\...\Documents\AzureAccessTokens.json (Modified: 2025-12-17 10:00:00)
  - C:\Users\...\OneDrive\AzureAccessTokens.json (Modified: 2025-12-17 14:46:40)
Using most recently modified file
```

---

**Created:** 2025-12-17  
**Last Updated:** 2025-12-17  
**Purpose:** Generic NuGet deployment for any project  
**Status:** Production-ready
