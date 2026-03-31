# AutoDoc Regeneration Logic

## Overview

This document describes how the `AutoDocBatchRunner.ps1` determines whether to regenerate documentation files when using `Regenerate = "Incremental"` mode (the default).

## Key Finding: Missing Files Are Always Regenerated

**Yes, the system will regenerate missing files even if the source hasn't changed.**

When a generated HTML file is deleted, the system will regenerate it on the next run with `Regenerate = "Incremental"`, regardless of whether:
- The SQL table's `ALTER_TIME` has changed
- The source file's git commit date has changed

This is because the **file existence check occurs BEFORE the date comparison checks** in the regeneration logic.

---

## SQL Files (`RegenerateAutoDocSql`)

The decision logic executes in this order:

| Priority | Check | Action if True |
|----------|-------|----------------|
| 1 | AutodocFunctions module modified | Regenerate |
| 2 | `sqlmmdtemplate.html` modified | Regenerate |
| 3 | **Output file does not exist** | **Regenerate** |
| 4 | `Regenerate = "All"` or `"Clean"` | Regenerate |
| 5 | `ALTER_TIME` > HTML file date | Regenerate |

### Relevant Code (Lines 1187-1190)

```powershell
if (-Not (Test-Path $contentFilename -PathType Leaf)) {
    $returnValue = $true
    Write-LogMessage ("Regenerate " + $tableName + " -  Not previously generated: " + $contentFilename) -Level INFO
    return $returnValue
}
```

**Result:** If you delete a generated `.sql.html` file, it will be regenerated even if the table's `ALTER_TIME` is unchanged.

---

## COBOL Files (.cbl)

The decision logic for COBOL (and other script types) executes in this order:

| Priority | Check | Action if True |
|----------|-------|----------------|
| 1 | Source file in `_old` folder | Skip (never regenerate) |
| 2 | `Regenerate = "Errors"` and error file exists | Regenerate |
| 3 | AutodocFunctions module modified | Regenerate |
| 4 | `cblmmdtemplate.html` modified | Regenerate |
| 5 | **Output file does not exist** | **Regenerate** |
| 6 | Git commit date > last generation date | Regenerate |
| 7 | Error file (.err) exists | Regenerate |

### Relevant Code (Lines 1119-1124)

```powershell
$contentFilename = $outputFolder + "\" + $fileName.Name + ".html"
if (-Not (Test-Path $contentFilename -PathType Leaf)) {
    $returnValue = $true
    Write-LogMessage ("Regenerate " + $fileName.Name + " -  Not previously generated: " + $contentFilename) -Level INFO -QuietMode
    return $returnValue
}
```

**Result:** If you delete a generated `.cbl.html` file, it will be regenerated even if the source file hasn't been committed since the last generation.

---

## PowerShell Files (.ps1)

Same logic as COBOL, but checks `ps1mmdtemplate.html` instead.

| Priority | Check | Action if True |
|----------|-------|----------------|
| 1 | Source file in `_old` folder | Skip |
| 2 | `Regenerate = "Errors"` and error file exists | Regenerate |
| 3 | AutodocFunctions module modified | Regenerate |
| 4 | `ps1mmdtemplate.html` modified | Regenerate |
| 5 | **Output file does not exist** | **Regenerate** |
| 6 | Git commit date > last generation date | Regenerate |
| 7 | Error file (.err) exists | Regenerate |

**Result:** If you delete a generated `.ps1.html` file, it will be regenerated.

---

## REXX Files (.rex)

Same logic as COBOL, but checks `rexmmdtemplate.html` instead.

| Priority | Check | Action if True |
|----------|-------|----------------|
| 1 | Source file in `_old` folder | Skip |
| 2 | `Regenerate = "Errors"` and error file exists | Regenerate |
| 3 | AutodocFunctions module modified | Regenerate |
| 4 | `rexmmdtemplate.html` modified | Regenerate |
| 5 | **Output file does not exist** | **Regenerate** |
| 6 | Git commit date > last generation date | Regenerate |
| 7 | Error file (.err) exists | Regenerate |

**Result:** If you delete a generated `.rex.html` file, it will be regenerated.

---

## Batch Files (.bat)

Same logic as COBOL, but checks `batmmdtemplate.html` instead.

| Priority | Check | Action if True |
|----------|-------|----------------|
| 1 | Source file in `_old` folder | Skip |
| 2 | `Regenerate = "Errors"` and error file exists | Regenerate |
| 3 | AutodocFunctions module modified | Regenerate |
| 4 | `batmmdtemplate.html` modified | Regenerate |
| 5 | **Output file does not exist** | **Regenerate** |
| 6 | Git commit date > last generation date | Regenerate |
| 7 | Error file (.err) exists | Regenerate |

**Result:** If you delete a generated `.bat.html` file, it will be regenerated.

---

## C# Solutions (.sln) and Ecosystems

C# projects are handled differently from other file types. They use **filesystem LastWriteTime** instead of git commit dates.

The approach is efficient: find the **single newest file** in the project and compare its date against the generated HTML date.

### C# Ecosystem Diagrams

An ecosystem diagram covers all projects in a folder (e.g., ServerMonitor).

| Priority | Check | Action if True |
|----------|-------|----------------|
| 1 | `Regenerate = "All"` or `"Clean"` | Regenerate |
| 2 | **Output file does not exist** | **Regenerate** |
| 3 | Newest `.csproj` or `.cs` file's LastWriteTime > HTML date | Regenerate |

### C# Solution Diagrams

Individual solution files (`.sln`) generate their own diagrams.

| Priority | Check | Action if True |
|----------|-------|----------------|
| 1 | `Regenerate = "All"` or `"Clean"` | Regenerate |
| 2 | **Output file does not exist** | **Regenerate** |
| 3 | `.sln` file's LastWriteTime > HTML date | Regenerate |
| 4 | Newest `.cs` file's LastWriteTime > HTML date | Regenerate |

### Relevant Code (Lines 1496-1507 for Ecosystem)

```powershell
# Find the SINGLE newest file - efficient approach
$newestFile = Get-ChildItem -Path $serverMonitorFolder -Include "*.csproj", "*.cs" -Recurse | 
    Where-Object { $_.DirectoryName -notmatch '\\(bin|obj)[\\/]' } |
    Sort-Object LastWriteTime -Descending | 
    Select-Object -First 1

if ($newestFile) {
    $newestDate = [int]$newestFile.LastWriteTime.ToString("yyyyMMdd")
    if ($newestDate -le $ecosystemDate) {
        $shouldGenerateEcosystem = $false  # No changes - skip
    }
}
```

### Relevant Code (Lines 1551-1561 for Solutions)

```powershell
# Find the SINGLE newest .cs file
$newestCsFile = Get-ChildItem -Path $solutionFolder -Filter "*.cs" -Recurse | 
    Sort-Object LastWriteTime -Descending | 
    Select-Object -First 1

if ($newestCsFile) {
    $csDate = [int]$newestCsFile.LastWriteTime.ToString("yyyyMMdd")
    if ($csDate -le $htmlDate) {
        $shouldRegenerate = $false  # No changes - skip
    }
}
```

**Result:** If you delete a generated `.csharp.html` file, it will be regenerated. The system efficiently finds only the newest file to determine if any changes occurred.

### Important Note: C# Uses Filesystem Dates, Not Git

Unlike other file types that use **git commit dates**, C# projects use **filesystem LastWriteTime**. This means:

- Local file modifications (even uncommitted) **will** trigger regeneration
- Pulling changes from git **will** trigger regeneration (files get new LastWriteTime)
- This is more aggressive than the git-based approach used for CBL/PS1/REX/BAT

---

## Summary Table

| File Type | Template File | Change Detection Method | Missing File Regenerates? |
|-----------|---------------|------------------------|---------------------------|
| SQL (.sql) | `sqlmmdtemplate.html` | DB2 `ALTER_TIME` vs HTML date | **Yes** |
| COBOL (.cbl) | `cblmmdtemplate.html` | Git commit date | **Yes** |
| PowerShell (.ps1) | `ps1mmdtemplate.html` | Git commit date | **Yes** |
| REXX (.rex) | `rexmmdtemplate.html` | Git commit date | **Yes** |
| Batch (.bat) | `batmmdtemplate.html` | Git commit date | **Yes** |
| C# Solution (.sln) | `csharpmmdtemplate.html` | Filesystem LastWriteTime | **Yes** |
| C# Ecosystem | `csharpmmdtemplate.html` | Filesystem LastWriteTime | **Yes** |

---

## Regeneration Mode Reference

**Important:** No regeneration mode deletes files from OutputFolder except `Clean`. Files are simply overwritten when regenerated.

| Mode | Description | Deletes Files? |
|------|-------------|----------------|
| `Incremental` | Default. Regenerates changed/missing files only | **No** |
| `All` | Regenerates everything (overwrites existing) | **No** |
| `Errors` | Only regenerates files with previous errors (.err files) | **No** |
| `JsonOnly` | Only regenerates JSON index files | **No** |
| `Single` | Regenerates a single specified file (use with `-SingleFile`) | **No** |
| `Clean` | **FULL RESET**: Deletes files, clears tmp/git, then regenerates all | **Yes** |

### Clean Mode Details

`Clean` is the **only** mode that deletes files. It performs a full reset before regenerating.

| What it deletes | What it preserves |
|-----------------|-------------------|
| tmp folder (cobdok, thread data) | `_images/` folder |
| AutoDocLastExecution.dat | `_js/` folder |
| Git checkout folders | `_css/` folder |
| All .html files (except protected) | `index.html` |
| All .mmd files | `web.config` |
| All .err files | |
| All .json files in `_json/` | |

---

## FileTypes Filter Parameter

The `-FileTypes` parameter allows filtering generation to specific file type(s).

| Type | Description | Handler Function |
|------|-------------|------------------|
| `Cbl` | COBOL programs | `HandleCblFiles` |
| `Rex` | REXX scripts | `HandleScriptFiles` |
| `Bat` | Batch scripts | `HandleScriptFiles` |
| `Ps1` | PowerShell scripts | `HandleScriptFiles` |
| `Sql` | SQL tables (DB2) | `HandleSqlTables` |
| `CSharp` | C# projects/solutions | `HandleCSharpProjects` |
| `All` | All types (default) | All handlers |

### Usage Examples

```powershell
# Generate only COBOL files
.\AutoDocBatchRunner.ps1 -FileTypes Cbl

# Generate SQL and C# only
.\AutoDocBatchRunner.ps1 -FileTypes Sql, CSharp

# Generate all script types (no SQL or C#)
.\AutoDocBatchRunner.ps1 -FileTypes Cbl, Rex, Bat, Ps1

# Default - all types (same as current behavior)
.\AutoDocBatchRunner.ps1

# Explicit all types
.\AutoDocBatchRunner.ps1 -FileTypes All
```

### Behavior Notes

- When `-FileTypes` is omitted or set to `All`, all file types are processed
- Can be combined with `-Regenerate` modes (e.g., `-Regenerate All -FileTypes Cbl`)
- The `JsonOnly` regeneration mode skips file processing entirely regardless of FileTypes

---

## Technical Notes

1. **Global Triggers**: All file types will also regenerate if the `AutodocFunctions.psm1` module has been modified, regardless of individual source file changes.

2. **Template Triggers**: Each file type has its own template file. If the template is modified, all files of that type will regenerate.

3. **Error Recovery**: Files with existing `.err` error files will always be regenerated (attempted again) even in `Incremental` mode.

4. **Exclusion Rule**: Files located in any folder named `_old` are always skipped, regardless of regeneration mode.

5. **C# Excludes bin/obj**: When scanning for `.cs` file changes, the system excludes `bin` and `obj` directories to avoid false positives from compiled output.

---

## Change Detection Method Comparison

| Method | Used By | Detects Uncommitted Changes? | Notes |
|--------|---------|------------------------------|-------|
| Git commit date | CBL, PS1, REX, BAT | **No** | Only committed changes trigger regeneration |
| Filesystem LastWriteTime | C# | **Yes** | Any file modification triggers regeneration |
| DB2 ALTER_TIME | SQL | N/A | Based on database DDL metadata |

### Implications

- **CBL/PS1/REX/BAT**: You can modify files locally without triggering regeneration. Only after committing will the next run pick up the change.
- **C#**: Any edit to a `.cs` file (even uncommitted) will trigger regeneration on the next run.
- **SQL**: Changes are tracked via DB2's internal catalog - regeneration happens when table structure changes.
