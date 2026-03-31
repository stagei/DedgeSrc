# DedgeCommon v1.5.18 Release Notes

**Release Date:** 2025-12-16  
**Previous Version:** 1.5.14  
**Current Version:** 1.5.18

---

## 🎯 Overview

This release adds critical validation to COBOL folder detection to ensure only legitimate COBOL object folders are used, and prevents automatic creation of COBOL folders.

---

## 🔒 Security & Validation Enhancements

### 1. Added Minimum .int File Count Validation ✅
**File:** `FkEnvironmentSettings.cs`

**Change:**
- Added constant `MinimumIntFilesForLocalCobFolder = 100` at class level
- Local COB folders (like `E:\COBPRD\`) are only accepted if they contain at least 100 .int files
- This prevents accidentally using incorrect folders

**Code:**
```csharp
private const int MinimumIntFilesForLocalCobFolder = 100;

// In FindCobFolder:
int intFileCount = Directory.GetFiles(testPath, "*.int", SearchOption.TopDirectoryOnly).Length;

if (intFileCount >= MinimumIntFilesForLocalCobFolder)
{
    DedgeNLog.Debug($"Found valid COB folder on {drive.Name}: {testPath}");
    DedgeNLog.Debug($"  Contains {intFileCount} .int files (minimum: {MinimumIntFilesForLocalCobFolder})");
    return testPath;
}
else
{
    DedgeNLog.Debug($"Found COB folder on {drive.Name} but insufficient .int files: {testPath}");
    DedgeNLog.Debug($"  Contains {intFileCount} .int files (minimum required: {MinimumIntFilesForLocalCobFolder})");
    DedgeNLog.Debug($"  Skipping this folder and continuing search");
}
```

**Impact:** Only servers with properly configured COBOL folders (containing many .int files) will use local paths.

---

### 2. Removed Automatic COBOL Folder Creation ✅
**File:** `RunCblProgram.cs`

**Previous Behavior:**
- Would attempt to create COBOL INT folder if it didn't exist
- Could create incorrect directories

**New Behavior:**
- NEVER creates COBOL INT folders automatically
- Immediately fails with clear error message if folder doesn't exist
- Provides diagnostic information about expected folder locations

**Code:**
```csharp
// CRITICAL: NEVER create COBOL INT folder - it must exist!
if (!Directory.Exists(cobolIntFolder))
{
    DedgeNLog.Error($"FATAL: COBOL INT folder does not exist: {cobolIntFolder}");
    DedgeNLog.Error($"  Database: {databaseName}");
    DedgeNLog.Error($"  Environment: {_environmentSettings.Environment}");
    DedgeNLog.Error($"  Expected locations:");
    DedgeNLog.Error($"    - Local COB folder (app servers only): E:\\COB{_environmentSettings.Environment}\\");
    DedgeNLog.Error($"    - Network share (workstations): \\\\DEDGE.fk.no\\erpprog\\cobnt\\ or cobtst\\");
    DedgeNLog.Error($"");
    DedgeNLog.Error($"  COBOL INT folders are NEVER created automatically!");
    DedgeNLog.Error($"  They must be pre-configured by system administrators.");
    throw new DirectoryNotFoundException(...);
}
```

**Impact:**
- Prevents accidental creation of incorrect folders
- Clear error messages help diagnose configuration issues
- Enforces proper system administration

---

### 3. Enhanced Folder Search Documentation ✅
**File:** `FkEnvironmentSettings.cs`

**Added XML documentation:**
```csharp
/// <summary>
/// Searches for a COB folder across all valid drives.
/// NEVER creates the folder - only searches for existing ones.
/// Only accepts folder if it contains at least MinimumIntFilesForLocalCobFolder .int files.
/// Mimics the PowerShell Find-ExistingFolder function behavior.
/// </summary>
```

---

## 📊 Validation Logic

### Local COB Folder Selection Criteria:

**For a folder to be selected as COBOL Object Path, it must:**

1. ✅ **Exist** - Folder must already exist (never created)
2. ✅ **Be on fixed drive** - C:, D:, E:, etc. (not network or removable)
3. ✅ **Match naming** - `COB{Environment}` (e.g., COBPRD, COBTST)
4. ✅ **Contain .int files** - At least 100 .int files in root directory

**If criteria not met:** Falls back to network UNC path

---

## 🔍 Example Scenarios

### Scenario 1: Production App Server
```
1. Database: BASISPRO → Environment: PRD
2. Search for: COBPRD
3. Found: E:\COBPRD\
4. Validation:
   - Folder exists: ✅ YES
   - Contains .int files: ✅ 547 files (minimum: 100)
5. Result: Uses E:\COBPRD\
```

### Scenario 2: Test Server with Empty Folder
```
1. Database: BASISTST → Environment: TST
2. Search for: COBTST
3. Found: E:\COBTST\
4. Validation:
   - Folder exists: ✅ YES
   - Contains .int files: ❌ 12 files (minimum: 100)
5. Result: Skips E:\COBTST\, uses \\DEDGE.fk.no\erpprog\cobtst\
```

### Scenario 3: Workstation
```
1. Database: BASISPRO → Environment: PRD
2. Search for: COBPRD
3. Found: (none)
4. Result: Uses \\DEDGE.fk.no\erpprog\cobnt\
```

---

## ⚠️ Breaking Changes

**None** - These are internal validation improvements that enhance security and prevent misconfigurations.

Applications will continue to work as before, but with better validation:
- Servers with properly configured COB folders: Continue using local paths
- Servers with empty/incorrect COB folders: Automatically fall back to network paths
- Workstations: Continue using network paths

---

## 🧪 Testing Recommendations

After deploying v1.5.18, verify:

1. **On app servers with COB folders:**
   - Verify local folder is used
   - Check logs show .int file count
   - Confirm at least 100 .int files present

2. **On workstations:**
   - Verify network UNC path is used
   - Verify COBOL programs run correctly

3. **Error handling:**
   - Test on system with no COBOL access
   - Verify clear error messages appear

---

## 📦 Deployment

**Package:** Dedge.DedgeCommon.1.5.18.nupkg  
**Feed:** Azure DevOps Dedge feed  
**Status:** ✅ Deployed successfully

**Update consuming applications:**
```xml
<PackageReference Include="Dedge.DedgeCommon" Version="1.5.18" />
```

---

## 📚 Related Documentation

- `COBOL_FIX_TODO.md` - Original fix documentation
- `COBOL_FOLDER_RESOLUTION_EXPLAINED.md` - Path resolution explanation
- `RELEASE_NOTES_1.5.14.md` - Previous release notes

---

## 🎉 Summary

### What Changed:
✅ **Added 100 .int file minimum requirement for local COB folders**  
✅ **Removed automatic folder creation (security enhancement)**  
✅ **Enhanced error messages and diagnostics**  
✅ **Better validation and logging**

### Why:
- Prevents incorrect folder usage
- Enforces proper system configuration
- Improves security by not creating folders automatically
- Provides better diagnostics when issues occur

### Impact:
- Only servers with proper COBOL installations use local folders
- Other systems automatically fall back to network paths
- Better error messages when configuration issues occur

---

**Status:** ✅ **DEPLOYED**  
**Version:** 1.5.18  
**Date:** 2025-12-16  
**Developer:** Geir Helge Starholm
