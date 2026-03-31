fix# COBOL Folder Resolution - TODO List

**Issue:** COBOL INT Folder is being constructed incorrectly  
**Date:** 2025-12-18  
**Current Version:** 1.5.14

---

## ✅ Clarification Received

**COBOL Object Path and COBOL INT Folder are THE SAME PATH!**

- ✅ Both point to where compiled programs are (.int files)
- ✅ Both point to where runtime files are written (.rc, .mfout)
- ✅ They are not separate locations!

**Exception:** Monitor files go to a different network location based on environment.

---

## 🐛 Current Bug

### What's Wrong:
```csharp
// GetCobolIntFolderByDatabaseName() - WRONG!
string baseOptPath = GetOptPath();  // E:\opt
string cobolIntPath = Path.Combine(baseOptPath, "DedgePshApps", "CobolInt", databaseName);
return cobolIntPath;  // Returns: E:\opt\DedgePshApps\CobolInt\BASISPRO ❌
```

**This creates a separate path that shouldn't exist!**

### What It Should Be:
```csharp
// Should return the COBOL Object Path from FkEnvironmentSettings
var settings = FkEnvironmentSettings.GetSettings(overrideDatabase: databaseName);
return settings.CobolObjectPath;  // Returns: E:\COBPRD\ or \\DEDGE.fk.no\erpprog\cobnt\ ✅
```

---

## 📋 TODO List - Fixes Needed

### Fix 1: GetCobolIntFolderByDatabaseName() ✅ COMPLETED
**File:** `DedgeCommon\FkFolders.cs`

**Status:** ✅ **FIXED in v1.5.14**

**Implementation:**
```csharp
public string GetCobolIntFolderByDatabaseName(string databaseName)
{
    // COBOL INT Folder = COBOL Object Path (they are the same!)
    var settings = FkEnvironmentSettings.GetSettings(overrideDatabase: databaseName);
    return settings.CobolObjectPath;
}
```

**Result:** 
- On app server with COBPRD: Returns `E:\COBPRD\`
- Without COBPRD: Returns `\\DEDGE.fk.no\erpprog\cobnt\`

---

### Fix 2: Monitor File Path Logic ✅ COMPLETED
**File:** `DedgeCommon\RunCblProgram.cs`

**Status:** ✅ **FIXED in v1.5.14**

**Implementation:**
```csharp
private static void WriteMonitorFile(string content, string databaseName)
{
    // Get environment settings to determine correct network path
    var settings = FkEnvironmentSettings.GetSettings(overrideDatabase: databaseName);
    
    // Monitor files always go to network location, not local COBOL Object Path
    string monitorPath;
    if (settings.Environment.Equals("PRD", StringComparison.OrdinalIgnoreCase))
    {
        monitorPath = @"\\DEDGE.fk.no\erpprog\cobnt\monitor";
    }
    else
    {
        // TST, UTB, DEV, etc. all use cobtst
        monitorPath = @"\\DEDGE.fk.no\erpprog\cobtst\monitor";
    }
    
    string monitorFilename = Path.Combine(monitorPath, $"{Environment.MachineName}{DateTime.Now:yyyyMMddHHmmss}.MON");
    File.WriteAllText(monitorFilename, content, Encoding.ASCII);
}
```

**Result:**
- PRD environment: `\\DEDGE.fk.no\erpprog\cobnt\monitor\`
- Other environments: `\\DEDGE.fk.no\erpprog\cobtst\monitor\`

---

### Fix 3: Remove E:\opt\DedgePshApps\CobolInt\ References ✅ COMPLETED
**Files:** Multiple

**Status:** ✅ **FIXED in v1.5.14**

**Action:** Verified no remaining references to:
- `E:\opt\DedgePshApps\CobolInt\`
- `C:\opt\DedgePshApps\CobolInt\`

All incorrect path constructions have been removed.

---

### Fix 4: Update GetCobolIntFolder(ConnectionKey) - Already Fixed ✅
**File:** `DedgeCommon\FkFolders.cs` (line 208-212)

**Status:** ✅ Already fixed in v1.5.13
```csharp
public string GetCobolIntFolder(DedgeConnection.ConnectionKey connectionKey)
{
    string databaseName = DedgeConnection.GetDatabaseName(connectionKey);
    return GetCobolIntFolderByDatabaseName(databaseName);
}
```

This will work correctly once Fix #1 is applied.

---

### Fix 5: Update RunCblProgram to Use Correct Paths
**File:** `DedgeCommon\RunCblProgram.cs`

**Update logging and execution:**
```csharp
// COBOL INT folder = COBOL Object Path
string cobolIntFolder = _fkFolders.GetCobolIntFolderByDatabaseName(databaseName);
// After Fix #1, this returns the COBOL Object Path

DedgeNLog.Info($"  COBOL Object Path: {cobolIntFolder}");
DedgeNLog.Info($"  COBOL INT Folder: {cobolIntFolder}");  // Same!
```

---

### Fix 6: Update WriteMonitorFile Calls ✅ COMPLETED
**File:** `DedgeCommon\RunCblProgram.cs`

**Status:** ✅ **FIXED in v1.5.14**

**Changes:**
```csharp
// Updated all calls to pass database name
WriteMonitorFile(wkmon, _environmentSettings.Database);
```

All calls updated (2 locations in CheckProcessLog method).

---

### Fix 7: Network Drive Mapping (Optional Enhancement)
**File:** `DedgeCommon\FkEnvironmentSettings.cs` or `RunCblProgram.cs`

**Add check:**
```csharp
// If COBOL Object Path uses N: drive
if (settings.CobolObjectPath.StartsWith("N:", StringComparison.OrdinalIgnoreCase))
{
    // Check if N: is mapped
    if (!Directory.Exists("N:\\"))
    {
        DedgeNLog.Info("N: drive not mapped, mapping now...");
        NetworkShareManager.EnsureDriveMapped("N", @"\\DEDGE.fk.no\erpprog");
    }
}
```

---

### Fix 8: Update Documentation
**File:** `DedgeCommon\README.md`, `COBOL_FOLDER_RESOLUTION_EXPLAINED.md`

**Clarify:**
- COBOL Object Path = COBOL INT Folder (same location)
- Monitor files go to separate network location
- Runtime files (.rc, .mfout) written to COBOL Object Path

---

### Fix 9: Remove Directory Auto-Creation (Maybe)
**File:** `DedgeCommon\RunCblProgram.cs`

**Current:** Creates `E:\opt\DedgePshApps\CobolInt\BASISPRO` if missing

**After Fix:** COBOL INT = COBOL Object Path, which should always exist
- `E:\COBPRD\` (app server - exists)
- `\\DEDGE.fk.no\erpprog\cobnt\` (network - exists)

**Decision:** Keep auto-creation but make it create files in temp location if COBOL Object Path doesn't exist?

---

### Fix 10: Testing Strategy
**After all fixes:**

1. Test on workstation (network path)
2. Test on app server (local COBPRD)
3. Verify .rc files in correct location
4. Verify .mfout files in correct location  
5. Verify monitor files in network location
6. Check both PRD and TST environments

---

## 🎯 Priority Order

### HIGH PRIORITY (Critical Bugs): ✅ COMPLETED
1. ✅ **Fix 1** - GetCobolIntFolderByDatabaseName returns COBOL Object Path (v1.5.14)
2. ✅ **Fix 2** - Monitor file path based on environment (v1.5.14)
3. ✅ **Fix 6** - Update WriteMonitorFile calls (v1.5.14)

### MEDIUM PRIORITY (Important):
4. ⏳ **Fix 5** - Update RunCblProgram logging (optional enhancement)
5. ✅ **Fix 3** - Remove wrong path references (v1.5.14)

### LOW PRIORITY (Nice to Have):
6. ✅ **Fix 7** - Auto network drive mapping
7. ✅ **Fix 8** - Documentation updates
8. ✅ **Fix 9** - Reconsider auto-creation logic

---

## 📊 Impact Assessment

### After Fixes:

**On Production App Server (p-no1fkmprd-app):**
```
COBOL Object Path: E:\COBPRD\
COBOL INT Folder:  E:\COBPRD\ (same!)
Monitor Files:     \\DEDGE.fk.no\erpprog\cobnt\monitor\

AABELMA.int → E:\COBPRD\AABELMA.int
AABELMA.rc → E:\COBPRD\AABELMA.rc
AABELMA.mfout → E:\COBPRD\AABELMA.mfout
Monitor file → \\DEDGE.fk.no\erpprog\cobnt\monitor\p-no1fkmprd-app20251218123456.MON
```

**On Test Server (t-no1fkmtst-app):**
```
COBOL Object Path: E:\COBTST\ (or network)
COBOL INT Folder:  E:\COBTST\ (same!)
Monitor Files:     \\DEDGE.fk.no\erpprog\cobtst\monitor\

Files written to COBTST folder
Monitor files to cobtst\monitor
```

---

## ✅ Next Steps

1. ✅ ~~**Confirm understanding**~~ - Confirmed correct
2. ✅ ~~**Apply Fix #1**~~ - GetCobolIntFolderByDatabaseName returns COBOL Object Path (DONE)
3. ✅ ~~**Apply Fix #2**~~ - Monitor file network path fixed (DONE)
4. ✅ ~~**Deploy**~~ - Pushed v1.5.14 to NuGet feed (DONE 2025-12-16)
5. ⏳ **Test** - Verify on dev/test environment (NEXT)
6. ⏳ **Verify** - Test GetPeppolDirectory with new version (PENDING)

---

**Created:** 2025-12-18  
**Updated:** 2025-12-16  
**Status:** ✅ Critical fixes completed in v1.5.14  
**Current Version:** 1.5.14
