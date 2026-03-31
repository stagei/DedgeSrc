# Deploy-NuGetPackage.ps1 - Generic NuGet Deployment Script

**Purpose:** Generic, reusable script for deploying any .NET NuGet package with automatic version bumping.

---

## 🎯 Overview

This script can deploy **any NuGet package** - not just DedgeCommon!

**Features:**
- ✅ Automatic version bumping (Major/Minor/Patch)
- ✅ Loads PAT from OneDrive config file
- ✅ Works with any .csproj file
- ✅ Configurable NuGet source
- ✅ Clean build process
- ✅ Error handling and reporting

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
.\Deploy-NuGetPackage.ps1 `
    -ProjectFile "Path\To\YourProject.csproj" `
    -Force

# With custom source
.\Deploy-NuGetPackage.ps1 `
    -ProjectFile "MyLib\MyLib.csproj" `
    -NuGetSource "MyPrivateFeed" `
    -Force

# Jump to version 2.0 (auto-completes to 2.0.0)
.\Deploy-NuGetPackage.ps1 `
    -ProjectFile "MyLib\MyLib.csproj" `
    -SpecificVersion "2.0" `
    -Force

# Or just major version (becomes 2.0.0)
.\Deploy-NuGetPackage.ps1 `
    -SpecificVersion "2" `
    -Force

# Full version also supported
.\Deploy-NuGetPackage.ps1 `
    -SpecificVersion "2.1.5" `
    -Force
```

---

## 📋 Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `ProjectFile` | ✅ Yes | (none) | Path to .csproj file (relative or absolute) |
| `VersionBump` | No | "Patch" | Version component to bump: Major, Minor, Patch |
| `SpecificVersion` | No | (auto) | Set specific version instead of bumping |
| `PAT` | No | (config/prompt) | Personal Access Token for NuGet feed |
| `ConfigFileName` | No | "<PackageId>Config.json" | Config file name in OneDrive Documents |
| `NuGetSource` | No | "Dedge" | NuGet source name |
| `Force` | No | false | Skip confirmation prompts |

---

## 📁 Config File Format

The script automatically loads PAT from a JSON file in OneDrive Documents.

**Location:** `%OneDriveCommercial%\Documents\<ConfigFileName>`

**Example - DedgeCommonNuget.json:**
```json
{
  "Purpose": "DedgeCommonNuget",
  "Email": "your.email@company.com",
  "PAT": "YOUR_AZURE_DEVOPS_PAT_HERE",
  "NuGetSource": "Dedge",
  "NuGetSourceUrl": "https://pkgs.dev.azure.com/org/project/_packaging/feed/nuget/v3/index.json",
  "LastUpdated": "2025-12-17",
  "Notes": "Update PAT when it expires. Requires Packaging permissions."
}
```

**Example - MyLibraryConfig.json:**
```json
{
  "Purpose": "MyLibrary",
  "Email": "dev@company.com",
  "PAT": "YOUR_PAT",
  "NuGetSource": "MyFeed"
}
```

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

### 4. PAT Loading
Priority order:
1. `-PAT` parameter (if provided)
2. OneDrive config file (auto-loads)
3. Manual prompt (if needed)

### 5. Deployment
- Pushes to specified NuGet source
- Handles errors gracefully
- Provides clear feedback

---

## 💡 Usage Examples

### Example 1: DedgeCommon (Simple)
```powershell
cd C:\opt\src\DedgeCommon
.\Deploy-Package.ps1 -Force
# Uses: DedgeCommon\DedgeCommon.csproj, DedgeCommonNuget.json, Dedge source
```

### Example 2: Another Library
```powershell
cd C:\Projects\MyLibrary

# First time - create config file in OneDrive Documents\MyLibraryConfig.json
# Then deploy:
..\DedgeCommon\Deploy-NuGetPackage.ps1 `
    -ProjectFile "MyLibrary.csproj" `
    -NuGetSource "MyFeed" `
    -Force
```

### Example 3: Public NuGet.org
```powershell
.\Deploy-NuGetPackage.ps1 `
    -ProjectFile "MyPublicLib\MyPublicLib.csproj" `
    -NuGetSource "nuget.org" `
    -ConfigFileName "MyPublicLibConfig.json" `
    -Force
```

### Example 4: Multiple Projects
```powershell
# Deploy all libraries in a solution
$projects = @(
    "Library1\Library1.csproj",
    "Library2\Library2.csproj",
    "Library3\Library3.csproj"
)

foreach ($proj in $projects) {
    .\Deploy-NuGetPackage.ps1 -ProjectFile $proj -Force
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
  Loading from: C:\Users\...\OneDrive\Documents\DedgeCommonNuget.json
  [OK] PAT loaded from config
  Email: user@company.com
  Source: Dedge

Step 6: Pushing to NuGet feed (Dedge)...
  [OK] Package pushed successfully!

===============================================================
   Deployment Summary
===============================================================

Project:    Dedge.DedgeCommon
Version:    1.4.9 -> 1.4.10
Package:    Dedge.DedgeCommon.1.4.10.nupkg
Size:       3.45 MB
Source:     Dedge
Build:      [OK]
Deploy:     [OK] Deployed

[SUCCESS] Package 1.4.10 deployed to Dedge!
```

---

## 🎓 Advanced Usage

### Custom Config Location
```powershell
# Use custom config file name
.\Deploy-NuGetPackage.ps1 `
    -ProjectFile "MyLib.csproj" `
    -ConfigFileName "MyCustomConfig.json"
```

### Override Everything
```powershell
# Don't use config file, provide everything
.\Deploy-NuGetPackage.ps1 `
    -ProjectFile "MyLib.csproj" `
    -PAT "YOUR_PAT" `
    -NuGetSource "CustomFeed" `
    -SpecificVersion "2.0.0" `
    -Force
```

### CI/CD Pipeline
```powershell
# In your build pipeline
$pat = $env:NUGET_PAT  # From secret variable

.\Deploy-NuGetPackage.ps1 `
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
.\Deploy-NuGetPackage.ps1 `
    -ProjectFile "DedgeCommon\DedgeCommon.csproj" `
    -ConfigFileName "DedgeCommonNuget.json" `
    -NuGetSource "Dedge" `
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
& "$PSScriptRoot\Deploy-NuGetPackage.ps1" `
    -ProjectFile "MyLibrary\MyLibrary.csproj" `
    -ConfigFileName "MyLibraryConfig.json" `
    -NuGetSource "MyFeed" `
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
.\Deploy-NuGetPackage.ps1 -ProjectFile "Path\To\Project.csproj" -Force
```

### With Custom Everything
```powershell
.\Deploy-NuGetPackage.ps1 `
    -ProjectFile "Project.csproj" `
    -SpecificVersion "2.0.0" `
    -PAT "YOUR_PAT" `
    -NuGetSource "YourFeed" `
    -ConfigFileName "YourConfig.json" `
    -Force
```

---

**Created:** 2025-12-17  
**Purpose:** Generic NuGet deployment for any project  
**Status:** Production-ready
