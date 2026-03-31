# DedgeCommon v1.5.14 Release Notes

**Release Date:** 2025-12-16  
**Previous Version:** 1.5.13  
**Current Version:** 1.5.14

---

## 🎯 Overview

This release fixes critical bugs in COBOL program execution related to folder path resolution and monitor file location.

---

## 🐛 Bug Fixes

### 1. Fixed GetCobolIntFolderByDatabaseName() Path Resolution ✅
**Issue:** Method was constructing incorrect path `E:\opt\DedgePshApps\CobolInt\{database}` that doesn't exist.

**Fix:** Now correctly returns COBOL Object Path from FkEnvironmentSettings:
- On app servers with COB folders: Returns `E:\COBPRD\` or `E:\COBTST\`
- On workstations: Returns `\\DEDGE.fk.no\erpprog\cobnt\` or `cobtst\`

**Impact:** COBOL programs can now find their .rc and .mfout files correctly.

**File:** `FkFolders.cs` (lines 222-235)

```csharp
public string GetCobolIntFolderByDatabaseName(string databaseName)
{
    // CRITICAL: COBOL INT Folder = COBOL Object Path
    var settings = FkEnvironmentSettings.GetSettings(overrideDatabase: databaseName);
    return settings.CobolObjectPath;
}
```

---

### 2. Fixed Monitor File Network Path ✅
**Issue:** Monitor files were being written to local COBOL folder instead of network location.

**Fix:** Monitor files now correctly go to network location based on environment:
- **PRD:** `\\DEDGE.fk.no\erpprog\cobnt\monitor\`
- **TST/UTB/DEV:** `\\DEDGE.fk.no\erpprog\cobtst\monitor\`

**Impact:** Monitor files are now centralized and accessible from all servers.

**File:** `RunCblProgram.cs` (lines 114-149)

```csharp
private static void WriteMonitorFile(string content, string databaseName)
{
    var settings = FkEnvironmentSettings.GetSettings(overrideDatabase: databaseName);
    
    string monitorPath;
    if (settings.Environment.Equals("PRD", StringComparison.OrdinalIgnoreCase))
    {
        monitorPath = @"\\DEDGE.fk.no\erpprog\cobnt\monitor";
    }
    else
    {
        monitorPath = @"\\DEDGE.fk.no\erpprog\cobtst\monitor";
    }
    
    string monitorFilename = Path.Combine(monitorPath, 
        $"{Environment.MachineName}{DateTime.Now:yyyyMMddHHmmss}.MON");
    File.WriteAllText(monitorFilename, content, Encoding.ASCII);
}
```

---

### 3. Removed Incorrect Path References ✅
**Action:** Verified no remaining references to incorrect path construction.

**Verified Clean:** No more references to:
- `E:\opt\DedgePshApps\CobolInt\`
- `C:\opt\DedgePshApps\CobolInt\`

---

### 4. Cleaned Up Monitor Folder Creation ✅
**Removed:** Unnecessary monitor subfolder creation in local COBOL INT folder.

**Reason:** Monitor files go to network location, not local folder.

**File:** `RunCblProgram.cs` (lines 244-283)

---

## 📊 Impact Assessment

### Before (v1.5.13 and earlier):
```
COBOL Object Path: E:\COBPRD\               ✅ Correct
COBOL INT Folder:  E:\opt\DedgePshApps\CobolInt\BASISPRO  ❌ Wrong!
Monitor Files:     E:\COBPRD\monitor\       ❌ Wrong!

Result: DirectoryNotFoundException
```

### After (v1.5.14):
```
COBOL Object Path: E:\COBPRD\               ✅ Correct
COBOL INT Folder:  E:\COBPRD\               ✅ Correct (same!)
Monitor Files:     \\DEDGE.fk.no\erpprog\cobnt\monitor\  ✅ Correct!

Result: All files in correct locations
```

---

## 🧪 Testing Checklist

Before deploying to production, verify:

- [ ] **DedgeCommon v1.5.14** builds successfully ✅ (completed)
- [ ] No linter errors ✅ (completed)
- [ ] NuGet package created ✅ (completed)
- [ ] Test on dev/test server (pending)
- [ ] Verify COBOL program execution works (pending)
- [ ] Check .rc files written to COBOL Object Path (pending)
- [ ] Check .mfout files written to COBOL Object Path (pending)
- [ ] Check monitor files in network location (pending)
- [ ] Test both PRD and TST environments (pending)

---

## 📦 Deployment Instructions

### 1. Deploy DedgeCommon v1.5.14 to NuGet Feed

```powershell
# Package is already built at:
# c:\opt\src\DedgeCommon\DedgeCommon\bin\x64\Debug\Dedge.DedgeCommon.1.5.14.nupkg

# Push to Azure DevOps feed (adjust command as needed)
dotnet nuget push "c:\opt\src\DedgeCommon\DedgeCommon\bin\x64\Debug\Dedge.DedgeCommon.1.5.14.nupkg" --source "Dedge"
```

### 2. Update Dependent Projects

All projects using DedgeCommon COBOL functionality should update:

```powershell
# In project directory (e.g., GetPeppolDirectory)
dotnet add package Dedge.DedgeCommon --version 1.5.14
```

**Projects that need updating:**
- GetPeppolDirectory
- Any other projects using `RunCblProgram.CblRun()`
- Any projects using `FkFolders.GetCobolIntFolderByDatabaseName()`

---

## 🔍 Verification Commands

After deployment, verify on app servers:

```powershell
# On p-no1fkmprd-app (PRD):
# 1. Check COBOL programs exist
dir E:\COBPRD\AABELMA.int

# 2. After execution, check runtime files
dir E:\COBPRD\AABELMA.rc
dir E:\COBPRD\AABELMA.mfout

# 3. Check monitor files in network location
dir \\DEDGE.fk.no\erpprog\cobnt\monitor\p-no1fkmprd-app*.MON

# 4. Verify no incorrect folders created
dir E:\opt\DedgePshApps\CobolInt\  # Should not exist
```

---

## ⚠️ Breaking Changes

**None** - This is a bug fix release that corrects incorrect behavior.

Applications using `GetCobolIntFolderByDatabaseName()` or `RunCblProgram.CblRun()` will now work correctly without code changes.

---

## 📚 Related Documentation

- `COBOL_FIX_TODO.md` - Detailed fix documentation
- `COBOL_FOLDER_RESOLUTION_EXPLAINED.md` - Path resolution explanation
- `ARCHITECTURE_FKENVIRONMENTSETTINGS_INTEGRATION.md` - Architecture decisions
- `README.md` - General DedgeCommon documentation

---

## 👥 Credits

**Developer:** Geir Helge Starholm  
**Issue Reported:** GetPeppolDirectory DirectoryNotFoundException  
**Fixed Date:** 2025-12-16

---

## 📝 Version History

- **v1.5.14** (2025-12-16) - Fixed COBOL folder path resolution and monitor file locations
- **v1.5.13** (previous) - Prior version with path bugs

---

**Status:** ✅ Ready for testing and deployment
