# VisualCobol Toolset — Analysis

**Author:** Geir Helge Starholm  
**Created:** 2026-02-20  
**Technology:** PowerShell / Micro Focus COBOL / Rocket Visual COBOL

---

## Overview

This toolset supports the migration, compilation, and runtime management of legacy COBOL code
(originally developed under **Micro Focus Net Express 5.1**) into the modern
**Rocket Visual COBOL** environment targeting Visual Studio 2022.

The code being migrated is the **Dedge** ERP system — a batch-oriented COBOL application
that connects to **DB2** and uses **Dialog System** for windowed UI programs.

---

## Installed Environments

| Product | Path |
|---|---|
| Rocket Visual COBOL | `C:\Program Files (x86)\Rocket Software\Visual COBOL\` |
| Micro Focus Net Express 5.1 | `C:\Program Files (x86)\Micro Focus\Net Express 5.1\Base` |
| Dialog System | `C:\Program Files (x86)\Micro Focus\Net Express 5.1\DIALOGSYSTEM` |

> **Important:** All `.bat` and `.ps1` scripts in this toolset reference the **old Micro Focus
> path** (`C:\Program Files (x86)\Micro Focus\Visual COBOL\`) for the compiler (`cobol.exe`)
> and runtime (`runw.exe`). Since Visual COBOL is now installed under the **Rocket Software**
> path, these paths must be updated before scripts will work correctly.

---

## Folder Structure

```
DevTools/LegacyCodeTools/VisualCobol/
│
├── Install-VisualCobolVS2022.ps1          # Multi-attempt installer with support-case report
├── Uninstall-Reinstall-VisualCobolVS2022.ps1  # Uninstall + reinstall in one script
├── Start-VS2022.ps1                       # Launcher for Visual Studio 2022
├── RaiseASupportCaseWithRocket.md         # Guide for opening a Rocket Software support case
│
├── switchMF/
│   └── switchMF.ps1                       # Toggle machine PATH between MF and VC environments
│
├── VisualCobolRunScripts/
│   ├── SetupEnv.bat                       # Creates directory structure + compiler directive files
│   ├── deploy.bat                         # Copies directives to VCPATH\cfg
│   ├── VcComplie.bat                      # COBOL compiler wrapper (32-bit or 64-bit)
│   ├── VcRunWin.bat                       # Runs a compiled COBOL program (32-bit / windowed)
│   ├── VcRunBat.bat                       # Runs a compiled COBOL program (64-bit / batch)
│   ├── VcCompilerDirectivesStd.dir        # Standard compiler directive set
│   ├── VcCompilerDirectivesSql.dir        # DB2 SQL compiler directive set
│   └── VcCompilerDirectivesStdProxy.dir   # Proxy directive that references the std .dir file
│
├── VisualCobolCodeMigration/
│   ├── Orchestrator.ps1                   # End-to-end migration orchestrator
│   ├── VisualCobolCodeSearch.ps1          # Scans COBOL sources for portability issues
│   ├── VisualCobolCodeReplace.ps1         # Applies automated code transformations
│   └── VisualCobolMoveCode.ps1            # Copies source files into VCPATH layout
│
├── VisualCobolCompareSrcToInt/
│   ├── VisualCobolCompareSrcToInt.ps1     # Compares production .INT files against source
│   ├── CheckFiles.ps1                     # Simple file-existence checker
│   └── InsertSourceReport.sql             # Generated SQL for DB2 source tracking table
│
└── VisualCobolBatchCompile/
    └── VisualCobolBatchCompile.ps1        # Batch compiles all .CBL files and reports errors
```

---

## Script-by-Script Analysis

---

### `switchMF\switchMF.ps1`

**Purpose:** Switches the machine-level `PATH` and COBOL environment variables between two
compilation environments: legacy **Micro Focus Net Express** (`MF`) and **Visual COBOL** (`VC`).

**Parameters:**

| Value | Description |
|---|---|
| `MF` | Activates Net Express 5.1 paths (Base + Dialog System) |
| `VC` | Activates Visual COBOL paths + sets `VCPATH`, `COBCPY`, `COBPATH`, etc. |
| `VCL` / `VCX` | Defined in ValidateSet but not yet implemented in script body |

**What it does for `VC` mode:**

- Sets `VCPATH = C:\fkavd\Dedge2`
- Sets `COBCPY` — copybook search path (cpy/, cpy/sys/cpy/, cbl/)
- Sets `COBPATH` — INT file search path (int/, gs/, cbl/)
- Sets `COBDIR` — compiler base directory
- Sets `COBMODE = 32`
- Sets `LIB` — to the Visual COBOL lib folder
- Removes all Micro Focus entries from PATH
- Adds Visual COBOL bin/, lib/ and IBM DB2 BIN to PATH

**What it does for `MF` mode:**

- Removes Visual COBOL and DB2 entries from PATH
- Adds Net Express 5.1 Base\bin and DialogSystem\bin

**Note:** The path values still point to `C:\Program Files (x86)\Micro Focus\Visual COBOL\`
which needs updating to `C:\Program Files (x86)\Rocket Software\Visual COBOL\`.

---

### `Install-VisualCobolVS2022.ps1`

**Purpose:** Attempts to install Rocket Visual COBOL 11.0 (`vcvs2022_110.exe`) for Visual
Studio 2022 using up to four different installer strategies, and generates a formatted
Markdown support-case report for Rocket Software.

**Installation attempts (in order):**

| # | Method | Description |
|---|---|---|
| 1 | `/?` | Queries installer for help/valid switches |
| 2 | `/install /passive /norestart /log` | Minimal UI install |
| 3 | `/install /quiet /norestart /log` | No-UI install (only if attempt 2 failed) |
| 4 | `/install /quiet ignorechecks=1 /log` | Bypasses VS2022 detection (only if 2+3 failed) |

**Known issue captured in the script:** The installer reports `VS2022ValidInstance=0` and
fails the WiX bundle condition `VS2022ValidInstance="1"`. This happens because Visual Studio
2022 Community and the newer VS 2026 (18.0) are both present but the installer does not
recognize VS 2026 as a valid VS 2022 instance.

**Output:** Writes a detailed `.md` report and installer log files to `$PSScriptRoot`.

---

### `Uninstall-Reinstall-VisualCobolVS2022.ps1`

**Purpose:** Performs a clean uninstall followed by reinstall of Rocket Visual COBOL 11.0
for Visual Studio 2022 in a single automated run.

**Parameters:**

| Parameter | Default | Description |
|---|---|---|
| `-InstallerPath` | `Downloads\vcvs2022_110.exe` | Path to installer EXE |
| `-UninstallOnly` | (switch) | Stop after uninstall, skip reinstall |
| `-UseIgnoreChecksOnInstall` | (switch) | Adds `ignorechecks=1` to bypass VS detection |

**Steps:**
1. Runs `/uninstall /quiet /norestart /log`
2. Waits 5 seconds
3. Runs `/install /quiet /norestart /log` (optionally with `ignorechecks=1`)
4. Treats exit code `3010` as success (reboot required but not an error)

---

### `Start-VS2022.ps1`

**Purpose:** Finds and launches `devenv.exe` for Visual Studio 2022 across all common
edition install paths (Community, Professional, Enterprise, BuildTools).

**Usage:** Run directly from PowerShell — no parameters needed.

---

### `VisualCobolRunScripts\SetupEnv.bat`

**Purpose:** One-time environment bootstrap. Creates the full `VCPATH` directory layout and
writes the compiler directive files.

**Directories created under `%VCPATH%`:**

```
bnd\    cfg\    dir\    int\    lst\    net\    tmp\
src\bat\  src\rex\  src\psh\  src\cbl\imp\  src\cbl\cpy\  src\cbl\cpy\sys\cpy\
```

**Directive files generated:**

- `VcCompilerDirectivesStd.dir` — standard compilation settings (Visual Studio 4, variable
  source format, tab stop 4, warnings level 1, max 100 errors)
- `VcCompilerDirectivesSql.dir` — DB2 SQL pre-compiler settings (DB2DEV database, BINDDIR,
  COLLECTION=DBM, UDB-VERSION=V9)
- `VcCompilerDirectivesStdProxy.dir` — proxy directive that points to the std .dir by path

---

### `VisualCobolRunScripts\VcComplie.bat`

**Purpose:** Wraps the `cobol.exe` compiler for a single `.CBL` source file.

**Parameters:** `FILENAME` (base name without extension), `COBMODE` (32 or 64)

**What it does:**
1. Sets compiler paths based on 32-bit or 64-bit mode
2. Cleans old output (`.int`, `.lst`, `.bnd`, `.dir`) for the file
3. Generates a per-file `.dir` directive file pointing to `VcCompilerDirectivesStd.dir`
4. If the source file contains `EXEC SQL`, automatically appends the SQL directive file
5. Invokes `cobol.exe` with source → INT → LST output paths

**Path issue:** References `C:\Program Files (x86)\Micro Focus\Visual COBOL\bin[64]\cobol.exe`
— must be updated to Rocket Software path.

---

### `VisualCobolRunScripts\VcRunWin.bat`

**Purpose:** Runs a compiled COBOL program in **32-bit windowed mode** using `runw.exe`.

**Usage pattern:** Designed to be called from a Windows shortcut:
```
cmd.exe /c start /min "" "%VCPATH%\cfg\VcRunWin.bat" PROGRAMNAME DB2DEV
```

Sets `COBMODE=32` and launches `runw.exe` from the 32-bit bin folder.

---

### `VisualCobolRunScripts\VcRunBat.bat`

**Purpose:** Same as `VcRunWin.bat` but uses **64-bit mode** (`bin64\runw.exe`).

Sets `COBMODE=64`. Used for batch (non-windowed) COBOL programs.

---

### `VisualCobolCodeMigration\Orchestrator.ps1`

**Purpose:** Ties the entire migration pipeline together in one sequence.

**Pipeline:**
1. Sends SMS notification that migration has started
2. Runs `SetupEnv.bat` (creates directory structure)
3. Runs `deploy.bat` (copies directives to cfg/)
4. Runs `VisualCobolCodeSearch.ps1` (scans for portability issues)
5. Runs `VisualCobolCodeReplace.ps1` (applies automated fixes)
6. Runs `VisualCobolMoveCode.ps1` (copies source files into VCPATH layout)
7. Runs `VisualCobolBatchCompile.ps1` (compiles everything)
8. Sends SMS notification on completion

**Note:** Uses the older `FKASendSMSDirect` module (pre-dates `GlobalFunctions`). The
`$pathHere = $$` line is a bug — `$$` is the last token of the previous command, not the
script path. The intent was `$PSScriptRoot`.

---

### `VisualCobolCodeMigration\VisualCobolCodeSearch.ps1`

**Purpose:** Scans all COBOL source files in the Dedge repository for patterns that are
problematic during migration to Visual COBOL. Results go to text files.

**Searches for:**
- UNC paths (`\\server\share`) hardcoded in COBOL source
- Drive-letter paths (`K:\`, `L:\`, etc.)
- `EXEC SQL` statements (programs needing DB2 pre-compiler)
- Specific DB2 command patterns
- Dialog System calls
- Other migration-sensitive patterns

**Output:** Text report files in the script's folder.

---

### `VisualCobolCodeMigration\VisualCobolCodeReplace.ps1`

**Purpose:** Applies automated code transformations to migrate portability issues found by
`VisualCobolCodeSearch.ps1`.

**Transformations include:**
- UNC path → local path conversions
- Drive-letter substitutions (K:\, L:\ → local equivalents)
- DB2 alias name replacements
- Code pattern rewrites required by Visual COBOL's stricter parser

---

### `VisualCobolCodeMigration\VisualCobolMoveCode.ps1`

**Purpose:** Copies COBOL source files from the source location into the standardized
`VCPATH` folder layout:

```
VCPATH\src\cbl\    ← .CBL source files
VCPATH\src\cbl\cpy\ ← .CPY copybook files
VCPATH\src\rex\    ← .REX REXX scripts
VCPATH\src\bat\    ← .BAT batch files
```

---

### `VisualCobolBatchCompile\VisualCobolBatchCompile.ps1`

**Purpose:** Iterates over all `.CBL` files in `$VCPATH\src\cbl\`, compiles each one via
`VcComplie.bat`, and reports errors with source-line context.

**Skip logic — files excluded from compilation:**
- `DOHCBLD`, `DOHCHK`, `DOHCHK2–4/6`, `DOHUTGAT`, `DOHSCAN` (known problem files)
- Files with 6- or 8-digit date patterns in the filename (backup/archive copies)
- Files with spaces in the filename

**Error parsing logic:**

After each compile, the script reads the `.LST` listing file and:
1. Looks for `"* Last message on page:"` — absence means compilation stopped with a fatal error
2. If the LST is missing entirely, reads the compiler log for `": error COB..."` and exits
3. If errors are found in the LST, extracts:
   - Source line number from the listing
   - Error code and description text
   - Context lines from around the error

**Regex used for error detection:**
```
\*(?=\s{0,4}\d{0,4}-)(\s*\d{1,4})-([a-z])\*
```
> Matches COBOL compiler error markers in LST files.  
> - `\*` — literal asterisk (compiler error line prefix)  
> - `(?=\s{0,4}\d{0,4}-)` — lookahead: up to 4 spaces, digits, then a dash  
> - `(\s*\d{1,4})` — capture group 1: optional spaces + 1–4 digit error number  
> - `-([a-z])` — capture group 2: error severity letter (e/w/i)  
> - `\*` — closing asterisk

**Logging:** Uses a local `LogMessage` function writing to
`$env:OptPath\src\DedgePsh\DevTools\VisualCobolBatchCompile\VisualCobolBatchCompile.log`.

> **Note:** This script pre-dates the `GlobalFunctions` module and does not use
> `Write-LogMessage`. Should be refactored.

---

### `VisualCobolCompareSrcToInt\VisualCobolCompareSrcToInt.ps1`

**Purpose:** Performs an inventory audit — for every `.INT` file deployed to production
(`\\DEDGE.fk.no\erpprog\COBNT`), determines whether a matching `.CBL` source file exists
and whether the compiled module is still in active use.

**What it does:**

1. Scans the production INT folder for all compiled modules
2. Collects source files from multiple network locations:
   - `\\DEDGE.fk.no\erputv\Utvikling\fkavd\NT\` (primary source)
   - `\\DEDGE.fk.no\erputv\Utvikling\fkavd\utgatt\` (retired/archived source)
   - `\\DEDGE.fk.no\erputv\Utvikling\CBLARKIV\` (ZIP archive per program)
   - `\\p-no1fkmprd-app\opt\DedgePshApps\` (production PowerShell scripts)
3. Cleans out noise files (year-stamped backups 2001–2024, date-pattern names, spaces in name)
4. For each INT file without a matching source, performs a **recursive usage search** across
   all production scripts/bat/rex/cbl to determine if the module is still called
5. Generates:
   - `MissingSourceReport.csv` — only programs without source
   - `AllSourceReport.csv` — full inventory
   - `InsertSourceReport.sql` — SQL INSERT statements for `DBM.DB_STAT_SOURCE_REPORT`

**DB2 output table:** `DBM.DB_STAT_SOURCE_REPORT` on server `p-no1fkmprd-db.DEDGE.fk.no`
(BASISPRO DSN, port 3700). The actual ODBC insertion code exists but is commented out.

---

### `VisualCobolCompareSrcToInt\CheckFiles.ps1`

**Purpose:** Quick sanity check — verifies that specific expected files exist across multiple
directories. Used during migration validation.

---

## Compiler Directive Files

### `VcCompilerDirectivesStd.dir`

```
visualstudio"4"
anim
cobidy"C:\fkavd\Dedge2\int\"
sourcetabstop"4"
sourceformat"Variable"
noquery
warnings"1"
max-error"100"
```

| Directive | Meaning |
|---|---|
| `visualstudio"4"` | Target Visual Studio integration level 4 |
| `anim` | Animated (windowed) execution support |
| `cobidy` | Output path for compiled `.int` intermediate files |
| `sourcetabstop"4"` | Tab width = 4 spaces |
| `sourceformat"Variable"` | Accept variable-length source lines (not fixed 72-col) |
| `noquery` | Suppress interactive queries during compilation |
| `warnings"1"` | Warning verbosity level |
| `max-error"100"` | Stop after 100 errors |

### `VcCompilerDirectivesSql.dir`

```
DB2(DB)
DB2(DB=DB2DEV)
DB2(BINDDIR=C:\fkavd\Dedge2\bnd)
DB2(COPY)
DB2(NOINIT)
DB2(COLLECTION=DBM)
DB2(UDB-VERSION=V9)
DB2(BIND)
```

| Directive | Meaning |
|---|---|
| `DB2(DB=DB2DEV)` | Target DB2 database alias `DB2DEV` |
| `DB2(BINDDIR=...)` | Where to store generated `.bnd` bind files |
| `DB2(COPY)` | Copy SQL include members |
| `DB2(NOINIT)` | Don't initialize DB2 connection on startup |
| `DB2(COLLECTION=DBM)` | Bind package to collection `DBM` |
| `DB2(UDB-VERSION=V9)` | Target DB2 UDB version 9 |
| `DB2(BIND)` | Auto-bind packages after compile |

---

## Key Path Constants

| Variable | Value |
|---|---|
| `VCPATH` | `C:\fkavd\Dedge2` |
| `COBCPY` | `%VCPATH%\src\cbl\cpy;%VCPATH%\src\cbl\cpy\sys\cpy;%VCPATH%\src\cbl` |
| `COBPATH` | `%VCPATH%\int;%VCPATH%\gs;%VCPATH%\src\cbl` |
| `COBMODE` | `32` (standard) or `64` (batch) |
| Production INT source | `\\DEDGE.fk.no\erpprog\COBNT` |
| Source repository | `\\DEDGE.fk.no\erputv\Utvikling\fkavd\NT` |
| COBOL archive | `\\DEDGE.fk.no\erputv\Utvikling\CBLARKIV` |
| DB2 server | `p-no1fkmprd-db.DEDGE.fk.no:3700` (DSN: BASISPRO) |

---

## Issues and Recommendations

### Critical: Compiler Path Mismatch

All batch files and `switchMF.ps1` reference:
```
C:\Program Files (x86)\Micro Focus\Visual COBOL\bin\cobol.exe
```
But Visual COBOL is now installed at:
```
C:\Program Files (x86)\Rocket Software\Visual COBOL\
```

**Action required:** Update all path references in:
- `VcComplie.bat`
- `VcRunWin.bat`
- `VcRunBat.bat`
- `switchMF.ps1`

---

### `switchMF.ps1` Missing `VCL` and `VCX` Cases

The `-switch` parameter accepts `VCL` and `VCX` values (in `[ValidateSet]`) but neither has
an implementation block in the script. If selected, the script silently does nothing.

---

### `Orchestrator.ps1` Bug — `$pathHere = $$`

Line 3 sets `$pathHere = $$`. In PowerShell, `$$` is the last token of the previous command,
not the current script directory. The intent was `$PSScriptRoot`. This will cause wrong
`Set-Location` calls and the downstream script invocations will fail.

**Fix:**
```powershell
$pathHere = $PSScriptRoot
```

---

### `VisualCobolBatchCompile.ps1` — Hardcoded Single-File Filter

Line 122 overrides the file loop to target only `AAXFKTSX.CBL`:
```powershell
$files = Get-ChildItem -Path "$VCPATH\src\cbl" -Filter "AAXFKTSX.CBL"
```
This was left from a debugging session. Remove or comment out to restore full-batch compilation.

---

### Logging Not Using `GlobalFunctions`

`VisualCobolBatchCompile.ps1` and `VisualCobolCompareSrcToInt.ps1` use a local `LogMessage`
function instead of `Write-LogMessage` from the `GlobalFunctions` module. They also write to
non-standard log paths. Should be migrated to the standard pattern:

```powershell
Import-Module GlobalFunctions -Force
Write-LogMessage "Message" -Level INFO
```

---

### DB2 Insert in `VisualCobolCompareSrcToInt.ps1` Is Commented Out

The script generates the SQL file and CSV reports but the actual DB2 insertion (ODBC) is
commented out across three different implementation attempts. Only the SQL file output
(`InsertSourceReport.sql`) works at present. The intention was to insert directly into
`DBM.DB_STAT_SOURCE_REPORT`, but this requires the BASISPRO ODBC DSN to be configured on
the developer machine.

---

## Migration Workflow — Step-by-Step

```
1. switchMF.ps1 -switch VC          ← Set machine environment to Visual COBOL
2. SetupEnv.bat                      ← Create VCPATH folder structure + directive files
3. deploy.bat                        ← Copy directives to VCPATH\cfg
4. VisualCobolCodeSearch.ps1         ← Identify portability issues in source
5. VisualCobolCodeReplace.ps1        ← Apply automated fixes
6. VisualCobolMoveCode.ps1           ← Copy files into VCPATH layout
7. VisualCobolBatchCompile.ps1       ← Compile all .CBL files
8. VisualCobolCompareSrcToInt.ps1    ← Audit source vs production INT inventory
```

Or run the entire pipeline in one go (after fixing the `$$` bug):
```powershell
.\VisualCobolCodeMigration\Orchestrator.ps1
```
