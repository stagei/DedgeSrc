# PSScriptAnalyzer Linter Warnings - Analysis & Fixes
**File:** `GlobalFunctions.psm1`  
**Generated:** December 16, 2025  
**Total Warnings:** 10

---

## ⚠️ Warning 1: Unused Variable `$exceptionLine`
**Line:** 1217  
**Code:** `PSUseDeclaredVarsMoreThanAssignments`  
**Severity:** Warning

### Current Code:
```powershell
if ($originalException.InvocationInfo.Line) {
    $exceptionStatement = $originalException.InvocationInfo.Line    # Line 1214
}
if ($originalException.InvocationInfo.Line) {
    $exceptionLine = $originalException.InvocationInfo.Line         # Line 1217 ← UNUSED
}
```

### Analysis:
- **Duplicate assignment** - Same value assigned to both `$exceptionStatement` (line 1214) and `$exceptionLine` (line 1217)
- `$exceptionStatement` is used later in the code
- `$exceptionLine` is never referenced

### Recommendation: **REMOVE**
```powershell
# DELETE lines 1216-1218
```

### Impact: ✅ Safe - Variable is completely unused

---

## ⚠️ Warning 2: Unused Variable `$allLoggingFile`
**Line:** 1634  
**Code:** `PSUseDeclaredVarsMoreThanAssignments`  
**Severity:** Warning

### Current Code:
```powershell
$allLoggingFolder = Join-Path $env:OptPath "data\AllPwshLog"
if (-not (Test-Path $allLoggingFolder -PathType Container)) {
    New-Item -ItemType Directory -Path $allLoggingFolder -Force | Out-Null
}
# Create all logging file if it doesn't exist
$getDate = $logStartDateTime.ToString("yyyyMMdd")
$allLoggingFile = Join-Path $allLoggingFolder $($env:COMPUTERNAME + "_" + $getDate + ".log")  # ← UNUSED
$additionalLogEntryInfo = ""
```

### Analysis:
- Variable calculated but **never used**
- Looks like **incomplete implementation**
- Comment says "Create all logging file if it doesn't exist" but file is never created or checked
- Later code writes directly to `$logFile` from `Add-GlobalDynamicLogFileNames` (line 1652)

### Recommendation: **REMOVE** (Implementation Abandoned)
```powershell
# DELETE lines 1632-1634 (comment and variable assignment)
```

**Alternative:** If the intention was to ensure file exists, add:
```powershell
$allLoggingFile = Join-Path $allLoggingFolder $($env:COMPUTERNAME + "_" + $getDate + ".log")
if (-not (Test-Path $allLoggingFile -PathType Leaf)) {
    New-Item -ItemType File -Path $allLoggingFile -Force | Out-Null
}
```

### Impact: ✅ Safe to remove (abandoned feature) OR ⚠️ Implement if file creation was intended

---

## ⚠️ Warning 3: Unused Variable `$fkAdminFolderStructureKeyWordsArray`
**Line:** 3623  
**Code:** `PSUseDeclaredVarsMoreThanAssignments`  
**Severity:** Warning

### Current Code:
```powershell
function Get-AdminInboxFilename {
    # ...
    $determinedRelativePath = ""
    $fkAdminFolderStructureKeyWordsArray = @()  # ← NEVER USED
    $allDatabases = @()
    $allInstances = @()                         # ← ALSO NEVER USED (Warning 4)
    if (Test-IsDbServer) {
        $allDatabases = Get-DatabasesV2Json | ...
        $allInstances = Get-DatabasesV2Json | ... # Assigned but never used
        
        foreach ($element in $pathSplit) {
            foreach ($database in $allDatabases) {  # Only $allDatabases is used
                # ...
            }
        }
    }
    return $determinedRelativePath
}
```

### Analysis:
- **Function appears incomplete** - `Get-AdminInboxFilename` has parameters but minimal implementation
- `$fkAdminFolderStructureKeyWordsArray` initialized but never populated or used
- `$allInstances` retrieved but never used (related to Warning 4)
- Function returns `$determinedRelativePath` which is built only from `$allDatabases`

### Recommendation: **REMOVE BOTH VARIABLES**
```powershell
# DELETE line 3623: $fkAdminFolderStructureKeyWordsArray = @()
# DELETE line 3625: $allInstances = @()
# DELETE line 3628: Assignment to $allInstances
```

### Impact: ✅ Safe - Variables are initialized but never used in any logic

---

## ⚠️ Warning 4: Unused Variable `$allInstances`
**Line:** 3625  
**Code:** `PSUseDeclaredVarsMoreThanAssignments`  
**Severity:** Warning

### See Warning 3 Above
- Same function, same issue
- Part of incomplete `Get-AdminInboxFilename` implementation

---

## ⚠️ Warning 5 & 6: Unused Variables `$fileSize` and `$fileDateTime`
**Lines:** 4416-4417  
**Code:** `PSUseDeclaredVarsMoreThanAssignments`  
**Severity:** Warning

### Current Code:
```powershell
# Inside Start-RoboCopy function, parsing robocopy output
foreach ($line in $robocopyOutput) {
    if ($line.StartsWith("Newer") -or $line.StartsWith("New File")) {
        # Regex to extract: Size (digits), DateTime, and FullPath
        if ($line -match '^\s*(\d+)\s+(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\s+(.+)$') {
            $fileSize = $matches[1]         # ← NEVER USED
            $fileDateTime = $matches[2]     # ← NEVER USED
            $sourceFilePath = $matches[3].Trim()
            
            # Later code gets actual file info from filesystem:
            $sourceFileInfo = Get-Item -Path $sourceFilePath
            # Uses $sourceFileInfo.Length and $sourceFileInfo.LastWriteTime instead
        }
    }
}
```

### Analysis:
- Variables extract data from **robocopy output** but never used
- Code immediately re-queries filesystem for accurate data using `Get-Item`
- Uses `$sourceFileInfo.Length` (not `$fileSize`)
- Uses `$sourceFileInfo.LastWriteTime` (not `$fileDateTime`)

### Recommendation: **REMOVE**
```powershell
# DELETE lines 4416-4417
# Keep only:
if ($line -match '^\s*(\d+)\s+(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\s+(.+)$') {
    $sourceFilePath = $matches[3].Trim()
    # ... rest of code
}
```

### Impact: ✅ Safe - Extracted values are never used; real values come from `Get-Item`

---

## ⚠️ Warning 7: Unused Variable `$folderName`
**Line:** 7090  
**Code:** `PSUseDeclaredVarsMoreThanAssignments`  
**Severity:** Warning

### Current Code:
```powershell
# Inside Get-RegistryPropertiesFromPath function
if (Test-Path -Path $searchPath -PathType Container -ErrorAction SilentlyContinue) {
    $relativePath = $searchPath -replace "^.*?::", "" -replace "^.*?:", ""
    $folderName = Split-Path -Path $searchPath -Leaf  # ← CALCULATED BUT UNUSED
    
    # The code that would have used $folderName is commented out:
    # $returnObject.result += [PSCustomObject]@{
    #     Path         = $searchPath
    #     Name         = $folderName     # ← Would be used here
    #     Value        = $null
    #     DataType     = "Folder"
    #     ...
    # }
```

### Analysis:
- Variable calculated but code that uses it is **commented out** (lines 7092-7100)
- Feature was **intentionally disabled**
- `$relativePath` is also calculated but unused (only used in commented section)

### Recommendation: **REMOVE** (or restore commented feature)

**Option 1: Remove unused variable**
```powershell
# DELETE line 7090: $folderName = Split-Path -Path $searchPath -Leaf
```

**Option 2: Restore the feature** (if folder entries should be shown)
```powershell
# UNCOMMENT lines 7092-7100 if folder entries should be included
```

### Impact: ✅ Safe to remove OR ⚠️ Restore feature if intentionally disabled temporarily

---

## ⚠️ Warning 8: Unused Variable `$subfolderRelativePath`
**Line:** 7112  
**Code:** `PSUseDeclaredVarsMoreThanAssignments`  
**Severity:** Warning

### Current Code:
```powershell
foreach ($subfolder in $subfolders) {
    # ...
    if ($shouldIncludeSubfolder) {
        $subfolderRelativePath = $subfolder.PSPath -replace "^.*?::", "" -replace "^.*?:", ""  # ← NEVER USED
        
        $returnObject.result += [PSCustomObject]@{
            Path         = $subfolder.PSPath
            Name         = $subfolder.PSChildName
            Value        = $null
            DataType     = "Folder"
            KeyPath      = ""
            RelativePath = "."     # ← Hardcoded instead of using $subfolderRelativePath
            ItemType     = "Folder"
        }
    }
}
```

### Analysis:
- **Bug/oversight** - Variable calculated but not used in output object
- Should probably be: `RelativePath = $subfolderRelativePath` instead of `RelativePath = "."`

### Recommendation: **FIX** (Use the calculated value)
```powershell
$subfolderRelativePath = $subfolder.PSPath -replace "^.*?::", "" -replace "^.*?:", ""

$returnObject.result += [PSCustomObject]@{
    Path         = $subfolder.PSPath
    Name         = $subfolder.PSChildName
    Value        = $null
    DataType     = "Folder"
    KeyPath      = ""
    RelativePath = $subfolderRelativePath  # ← FIX: Use calculated value
    ItemType     = "Folder"
}
```

### Impact: 🐛 **BUG FIX** - This appears to be unfinished code that should use the calculated value

---

## ⚠️ Warning 9 & 10: Automatic Variable `$event`
**Lines:** 7352 & 7419  
**Code:** `PSAvoidAssignmentToAutomaticVariable`  
**Severity:** Warning

### Current Code:
```powershell
# Line 7352:
foreach ($event in $logonEvents) {  # ← Using automatic variable name
    $xml = [xml]$event.ToXml()
    # ...
}

# Line 7419:
foreach ($event in $failedLogonEvents) {  # ← Using automatic variable name
    $xml = [xml]$event.ToXml()
    # ...
}
```

### Analysis:
- `$event` is a **PowerShell automatic variable**
- Using it as loop variable can cause unexpected behavior
- Best practice is to use different name

### Recommendation: **RENAME**
```powershell
# Line 7352:
foreach ($logonEvent in $logonEvents) {
    $xml = [xml]$logonEvent.ToXml()
    $eventData = @{}
    
    foreach ($data in $xml.Event.EventData.Data) {
        $eventData[$data.Name] = $data.'#text'
    }
    
    if ($eventData.LogonType -in @('10', '3')) {
        # ... rest of code ...
        $logonTime = $logonEvent.TimeCreated  # Changed from $event
        # ... etc
    }
}

# Line 7419:
foreach ($failedEvent in $failedLogonEvents) {
    $xml = [xml]$failedEvent.ToXml()
    # ... similar pattern ...
    $logonTime = $failedEvent.TimeCreated  # Changed from $event
}
```

### Impact: ⚠️ **Best Practice** - Prevents potential issues with automatic variables

---

## 📊 Summary Table

| Line | Variable | Issue | Action | Priority |
|------|----------|-------|--------|----------|
| 1217 | `$exceptionLine` | Duplicate/unused | **REMOVE** | ✅ Safe |
| 1634 | `$allLoggingFile` | Incomplete feature | **REMOVE** | ✅ Safe |
| 3623 | `$fkAdminFolderStructureKeyWordsArray` | Never used | **REMOVE** | ✅ Safe |
| 3625 | `$allInstances` | Never used | **REMOVE** | ✅ Safe |
| 4416 | `$fileSize` | Parsed but unused | **REMOVE** | ✅ Safe |
| 4417 | `$fileDateTime` | Parsed but unused | **REMOVE** | ✅ Safe |
| 7090 | `$folderName` | Feature disabled | **REMOVE** | ✅ Safe |
| 7112 | `$subfolderRelativePath` | Should be used | **FIX BUG** | 🐛 Fix |
| 7352 | `$event` | Automatic variable | **RENAME** | ⚠️ Best Practice |
| 7419 | `$event` | Automatic variable | **RENAME** | ⚠️ Best Practice |

---

## 🔧 Recommended Fixes (PowerShell Script)

```powershell
# Fix 1: Remove duplicate $exceptionLine (line 1217)
# DELETE lines 1216-1218

# Fix 2: Remove unused $allLoggingFile (line 1634)
# DELETE lines 1632-1634

# Fix 3: Remove unused variables in Get-AdminInboxFilename (lines 3623, 3625)
# DELETE line 3623: $fkAdminFolderStructureKeyWordsArray = @()
# DELETE line 3625: $allInstances = @()
# DELETE line 3628: The assignment to $allInstances

# Fix 4 & 5: Remove unused regex captures (lines 4416-4417)
# DELETE lines 4416-4417

# Fix 6: Remove unused $folderName (line 7090)
# DELETE line 7090: $folderName = Split-Path -Path $searchPath -Leaf
# Also DELETE line 7089: $relativePath assignment (also unused in this block)

# Fix 7: USE the calculated $subfolderRelativePath (line 7112)
# CHANGE line 7120: RelativePath = "." 
# TO: RelativePath = $subfolderRelativePath

# Fix 8 & 9: Rename $event to avoid automatic variable (lines 7352, 7419)
# RENAME all instances of $event to $logonEvent (first loop)
# RENAME all instances of $event to $failedEvent (second loop)
```

---

## 🎯 Quick Fix Priority

### High Priority (Fixes bugs/best practices):
1. **Line 7112** - Fix `$subfolderRelativePath` not being used (Bug)
2. **Lines 7352, 7419** - Rename `$event` to avoid automatic variable conflicts

### Medium Priority (Cleanup):
3. **Lines 1217, 1634, 3623, 3625, 4416-4417, 7090** - Remove all unused variables

---

## 📝 Notes

1. **After fixes**, re-run PSScriptAnalyzer to verify all warnings are resolved:
   ```powershell
   Invoke-ScriptAnalyzer -Path .\GlobalFunctions.psm1 -Severity Warning
   ```

2. **Test thoroughly** after removing variables, especially:
   - `Write-LogMessage` function (fixes 1-2)
   - `Get-AdminInboxFilename` function (fix 3)
   - `Start-RoboCopy` function (fixes 4-5)
   - `Get-RegistryPropertiesFromPath` function (fixes 6-7)
   - `Find-RdpConnectedMachineAndUserInfo` function (fixes 8-9)

3. **Git commit message suggestion**:
   ```
   fix: resolve PSScriptAnalyzer warnings in GlobalFunctions
   
   - Remove duplicate/unused variables (lines 1217, 1634, 3623, 3625, 4416-4417, 7090)
   - Fix bug: use $subfolderRelativePath instead of hardcoded "." (line 7120)
   - Rename $event to avoid automatic variable conflicts (lines 7352, 7419)
   
   Resolves 10 PSScriptAnalyzer warnings
   ```

---

*Analysis completed: December 16, 2025*  
*Tool: PSScriptAnalyzer*  
*File: GlobalFunctions.psm1 (8,703 lines)*
