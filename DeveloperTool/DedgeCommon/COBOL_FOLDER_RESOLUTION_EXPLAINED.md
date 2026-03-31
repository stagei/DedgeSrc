# COBOL Folder Resolution Logic - Comprehensive Explanation

**Date:** 2025-12-18  
**Purpose:** Explain the complete COBOL folder resolution logic in DedgeCommon

---

## 🎯 The Problem to Solve

When running COBOL programs, we need to determine **two different paths**:

1. **COBOL Object Path** - Where compiled COBOL programs (.int files) are located
2. **COBOL INT Folder** - Where runtime files (.rc, .mfout, monitor files) are written

---

## 📂 Understanding the Two Paths

### COBOL Object Path (Program Files)
**Purpose:** Location of compiled COBOL programs  
**Example:** `\\DEDGE.fk.no\erpprog\cobnt\` or `E:\COBPRD\`

**Contents:**
- Compiled COBOL programs (.int files)
- Copybooks
- Source code (sometimes)

### COBOL INT Folder (Runtime/Working Directory)
**Purpose:** Location for runtime files and output  
**Example:** `E:\opt\DedgePshApps\CobolInt\BASISPRO`

**Contents:**
- Return code files (.rc)
- Transcript files (.mfout)
- Monitor files (.MON in monitor\ subfolder)
- Temporary working files

---

## 🔄 Current Logic Flow

### Step 1: Determine COBOL Object Path

**When running FkEnvironmentSettings.GetSettings(overrideDatabase: "BASISPRO"):**

#### 1a. Map Database to Catalog (via DatabasesV2.json)
```
Database: FKMPRD
  ↓ (lookup in DatabasesV2.json)
Catalog: BASISPRO (PrimaryCatalogName)
```

#### 1b. Map Catalog to COBOL Path (via switch statement)
```csharp
"BASISPRO" => @"\\DEDGE.fk.no\erpprog\cobnt\"
```

#### 1c. Check for App Server Override
```csharp
if (IsServer && ComputerName.EndsWith("-APP") && Environment.Length == 3)
{
    // Search for COBPRD folder on all drives
    string findFolderName = $"COB{settings.Environment}";  // "COBPRD"
    
    foreach (drive in C:, D:, E:, ...)
    {
        if (Directory.Exists($"{drive}:\COBPRD"))
        {
            settings.CobolObjectPath = $"{drive}:\COBPRD\";
            break;
        }
    }
}
```

**Result:** Either network path OR local COBPRD folder

---

### Step 2: Determine COBOL INT Folder

**This is where files are created during execution.**

#### Current Implementation (GetCobolIntFolderByDatabaseName):
```csharp
string baseOptPath = GetOptPath();  // Returns "C:\opt" or "E:\opt"
string cobolIntPath = Path.Combine(baseOptPath, "DedgePshApps", "CobolInt", databaseName);
// Returns: E:\opt\DedgePshApps\CobolInt\BASISPRO
```

---

## ❌ The Current Problem

### Issue 1: COBOL INT Path May Not Exist
The path `E:\opt\DedgePshApps\CobolInt\BASISPRO` may not exist, causing:
```
DirectoryNotFoundException: Could not find a part of the path 'E:\opt\DedgePshApps\CobolInt\BASISPRO\AABELMA.mfout'
```

**Current Fix (v1.5.13):** Auto-creates directory with WARNING

### Issue 2: Wrong COBOL INT Location?
**Your Intent:** COBOL INT folder should be related to where COBOL programs run

**On App Server with COBPRD:**
- COBOL Object Path: `E:\COBPRD\` (found)
- COBOL INT Folder: Should be `E:\COBPRD\INT\` or similar?
- Currently: `E:\opt\DedgePshApps\CobolInt\BASISPRO` (unrelated)

---

## 💡 Your Intended Logic (As I Understand It)

### For Production App Server (p-no1fkmprd-app):

#### Step 1: Find COBPRD Folder
```
Search: C:\COBPRD, D:\COBPRD, E:\COBPRD, ...
Found: E:\COBPRD
```

#### Step 2: Set COBOL Object Path
```
settings.CobolObjectPath = "E:\COBPRD\"
```

#### Step 3: Determine COBOL INT Folder
**Option A - Related to COBOL Object Path:**
```
If COBOL Object Path is E:\COBPRD\
Then COBOL INT = E:\COBPRD\INT\ or E:\COBPRD\CobolInt\
```

**Option B - Use Network Drive Fallback:**
```
1. Try N:\cobnt\INT\ or N:\cobnt\CobolInt\BASISPRO
2. If N: not mapped, map it to \\DEDGE.fk.no\erpprog
3. Then use N:\cobnt\INT\
```

---

## 🔍 Current GetPeppolDirectory Usage

Looking at the error, GetPeppolDirectory calls:
```csharp
RunCblProgram.CblRun(connectionKey, "AABELMA", null, Batch);
```

This triggers:
1. `FkEnvironmentSettings.GetSettings(overrideDatabase: "BASISPRO")`
2. `FkFolders.GetCobolIntFolderByDatabaseName("BASISPRO")`
3. Returns: `E:\opt\DedgePshApps\CobolInt\BASISPRO`
4. **Fails:** Directory doesn't exist

---

## 🎯 Questions to Clarify:

### Q1: Where Should COBOL INT Folder Really Be?

**Option A:** Always under `{GetOptPath()}\DedgePshApps\CobolInt\{DatabaseName}`
- Current: `E:\opt\DedgePshApps\CobolInt\BASISPRO`
- Should it just create this if missing? (Currently does in v1.5.13)

**Option B:** Related to COBOL Object Path
- If using `E:\COBPRD\`, then `E:\COBPRD\INT\`
- If using network, then `N:\cobnt\CobolInt\BASISPRO` or similar

### Q2: When to Map Network Drives?

Should `FkEnvironmentSettings` or `RunCblProgram`:
1. Check if N: drive exists?
2. If not, call `NetworkShareManager.MapDrive("N", "\\DEDGE.fk.no\erpprog")`?
3. Then use N: drive for paths?

### Q3: What's the PowerShell Behavior?

Need to check original PowerShell `Get-GlobalEnvironmentSettings`:
- Where does it set the COBOL INT folder?
- Does it map drives automatically?
- What's the relationship between COBOL Object Path and INT folder?

---

## 📋 Original PowerShell Code Context

From `Get-GlobalEnvironmentSettings`:
```powershell
# Sets COBOL Object Path based on database
$settings.CobolObjectPath = switch ($settings.Database) {
    'BASISPRO' { "\\DEDGE.fk.no\erpprog\cobnt\" }
    # ...
}

# Override if on app server
if (($settings.IsServer) -and ($env:COMPUTERNAME.ToUpper().EndsWith("-APP")) -and $settings.Environment.Length -eq 3) {
    $findFolderName = "COB$($settings.Environment)"
    $foundFolderPath = Find-ExistingFolder -Name $findFolderName
    if ($foundFolderPath) {
        $settings.CobolObjectPath = $foundFolderPath
    }
}
```

**But I don't see where it sets the INT folder in the PowerShell!**

---

## 🔧 Likely Solution

### The COBOL INT Folder Is Probably:

**Hypothesis:** The working directory for COBOL programs should be a subdirectory under the COBOL Object Path, not a separate location.

**Example for BASISPRO on app server with COBPRD:**
```
COBOL Object Path: E:\COBPRD\
COBOL INT Folder:  E:\COBPRD\INT\  (or E:\COBPRD\CobolInt\)
```

**Example for BASISPRO without local COBPRD:**
```
COBOL Object Path: \\DEDGE.fk.no\erpprog\cobnt\
COBOL INT Folder:  \\DEDGE.fk.no\erpprog\cobnt\CobolInt\BASISPRO
```

---

## 🎯 Recommendation

### Fix GetCobolIntFolderByDatabaseName:

Instead of:
```csharp
string baseOptPath = GetOptPath();  // E:\opt
string cobolIntPath = Path.Combine(baseOptPath, "DedgePshApps", "CobolInt", databaseName);
// Returns: E:\opt\DedgePshApps\CobolInt\BASISPRO
```

Should be:
```csharp
// Get current COBOL Object Path from environment settings
var settings = FkEnvironmentSettings.GetSettings(overrideDatabase: databaseName);
string cobolObjectPath = settings.CobolObjectPath;

// COBOL INT folder is under the COBOL Object Path
string cobolIntPath = Path.Combine(cobolObjectPath, "CobolInt", databaseName);
// Returns: E:\COBPRD\CobolInt\BASISPRO or \\DEDGE.fk.no\erpprog\cobnt\CobolInt\BASISPRO
```

---

## ⚠️ Need Clarification

Before I fix this, please confirm:

1. **Where should COBOL INT folder be?**
   - Under COBOL Object Path? (E:\COBPRD\INT\)
   - Or separate location? (E:\opt\DedgePshApps\CobolInt\BASISPRO)

2. **What's the PowerShell behavior?**
   - Where does it put .rc and .mfout files?
   - Check a working server to see actual paths

3. **Network Drive Mapping**
   - Should we auto-map N: drive if missing?
   - Or assume it's already mapped?

---

**Please check a working production server to see:**
```powershell
# On p-no1fkmprd-app, after running COBOL program:
dir E:\COBPRD        # COBOL programs here?
dir E:\opt\DedgePshApps\CobolInt\BASISPRO   # Runtime files here?
dir N:\cobnt         # Or here?
```

**This will tell us the correct path structure!**

---

**Created:** 2025-12-18  
**Status:** Awaiting clarification on correct folder structure  
**Current Version:** 1.5.13 (with workaround - creates missing folders)
