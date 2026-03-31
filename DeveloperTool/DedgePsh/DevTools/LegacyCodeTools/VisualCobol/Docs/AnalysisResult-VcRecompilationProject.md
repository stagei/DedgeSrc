# Visual COBOL Recompilation Project — Analysis & Status

**Author:** Geir Helge Starholm, www.dEdge.no  
**Created:** 2026-03-10  
**Technology:** Visual COBOL 11 (Rocket Software), PowerShell 7, DB2 LUW

---

## Overview

This document tracks the comprehensive effort to recompile all legacy COBOL programs
using Rocket Visual COBOL 11 and bind them to DB2 databases. The project transforms
~3,471 CBL source files from legacy runtime formats into modern `.int` intermediates.

---

## 1. Source File Inventory

### Collection Results (Step10-Copy-VcSourceFiles)

| Folder | Count | Description |
|--------|------:|-------------|
| `cbl` | 3,471 | Primary COBOL programs (high-confidence matches) |
| `cbl_uncertain` | 7,652 | COBOL files with uncertain origin/naming |
| `cpy` | 17 | Confirmed copybooks |
| `cpy_uncertain` | 9,626 | Copybooks from various sources, unverified |
| **Total** | **20,766** | All collected source files |

**Location:** `C:\opt\data\VisualCobol\Step1-Copy-VcSourceFiles\Sources\`

### Encoding

All source files use **Windows-1252 (ANSI)** encoding. Norwegian characters (Æ Ø Å æ ø å)
are encoded in code page 1252. Scripts must use:

```powershell
$ansiEncoding = [System.Text.Encoding]::GetEncoding(1252)
Get-Content -Path $file -Encoding $ansiEncoding
```

PowerShell 7 defaults to UTF-8, which mangles 1252 characters. This was a root cause of
early compilation issues and has been fixed in `Invoke-VcCompile.ps1` and
`Step40-Invoke-VcBatchCompile.ps1`.

### Source Format

Most programs use `$SET` directives in their headers:

| Directive Pattern | Format | DB2? | Count (sample) |
|-------------------|--------|------|----------------|
| `$SET DB2(NOINIT DB=FKAVDNT ...) SOURCEFORMAT(VARIABLE)` | Variable | Yes | ~80% |
| `$SET MF ANS85` | Fixed | No/Yes | ~15% |
| No `$SET` | Variable (implicit) | No | ~5% |

The compiler directives file overrides the inline `$SET DB2(DB=...)` with the target
database alias from `VcCompilerDirectivesSql.dir`.

---

## 2. Compilation Infrastructure

### Scripts Created/Modified

| Script | Purpose | Status |
|--------|---------|--------|
| `Invoke-VcCompile.ps1` | Single-file compiler wrapper | **Modified** — ANSI-1252 encoding fix |
| `Invoke-VcFullPipeline.ps1` | **NEW** — Comprehensive compile+bind pipeline | Created |
| `Copy-VcSourcesToServer.ps1` | **NEW** — Copy sources to server via UNC | Created |
| `Install-RocketVisualCobol.ps1` | **NEW** — Install VC packages via Install-WindowsApps | Created |
| `_deploy.ps1` | Deploy scripts to dedge-server | **Modified** — added ComputerNameList |
| `Steps/Step30-Initialize-VcEnvironment.ps1` | Environment setup | **Modified** — DbAlias default to FKAVDNT |
| `Steps/Step40-Invoke-VcBatchCompile.ps1` | Batch compilation | **Modified** — ANSI-1252 encoding fix |

### Compiler Environment

| Variable | Value |
|----------|-------|
| `COBDIR` | `<VcBase>;<VcPath>\int;<VcPath>\gs;<VcPath>\src\cbl` |
| `COBPATH` | `<VcPath>\int;<VcPath>\gs;<VcPath>\src\cbl` |
| `COBCPY` | `<VcPath>\src\cbl\cpy;<VcPath>\src\cbl\cpy\sys\cpy;<VcPath>\src\cbl` |
| `COBMODE` | `32` (default) |
| `VCPATH` | `C:\fkavd\Dedge2` (default) |

### Compiler Paths (auto-detected)

| Vendor | Base Path |
|--------|-----------|
| Rocket Software | `C:\Program Files (x86)\Rocket Software\Visual COBOL\` |
| Micro Focus (legacy) | `C:\Program Files (x86)\Micro Focus\Visual COBOL\` |

---

## 3. Compilation Results (Historical)

### Early Batch Run (Fail-Fast Mode)

Programs were compiled one-by-one with `-StopOnFirstError` to identify and fix blockers.

#### Successfully Resolved Errors

| Program | Error | Root Cause | Fix Applied |
|---------|-------|------------|-------------|
| AXALBEL | COBCH0008 Unknown copybook GMASEMA.CPY | Missing copybook | Created placeholder from GMASEMA.CBL |
| AXBRIMPM | COBCH0008 Unknown GMADATO.CPY, FFAR.DCL | Missing copybooks | Created placeholders + DCL from SYSCAT.COLUMNS |
| AXBRIMPS | COBDB0103 FFAR-REGEL-ID mismatch | Wrong COMP type in DCL | Fixed to PIC S9(9) COMP-5 |
| BDBPURE | COBCH0012 REKP-HOSTVARIABLE not declared | Missing REKP.DCL | Reconstructed from SYSCAT.COLUMNS for DBM.LEV_REKL_PURRING |
| BDANETTO | COBCH0012 multiple undeclared operands | Missing BDANETTO.CPY | Reconstructed copybook from program usage |
| BDHETIK | Multiple COBCH0012, COBDB0103, COBDB0109 | 10+ missing/wrong copybooks | Reconstructed GMAPRTR, GMAOSNT, GMAMVAS, B912, GMAITAK, KAET.DCL, VAR2.DCL, ETH.DCL, VAR.DCL, KAMP.DCL, GMACOMP |
| BDHMARK | COBCH0219 Illegal level number | Trailing sequence numbers in data declarations | Removed extraneous trailing numbers |

#### DCL Files Reconstructed from DB2 SYSCAT.COLUMNS

| DCL File | DB2 Table | Key Decisions |
|----------|-----------|---------------|
| FFAR.DCL | DBM.FLOG_DedgeAXIA_REGLER_STG | DECIMAL → PIC S9(9) COMP-5, TIMESTAMP → PIC X(26) |
| REKP.DCL | DBM.LEV_REKL_PURRING | VARCHAR → 49-level with length prefix |
| KAET.DCL | DBM.KAMPANJE_ETIK | COMP-3 for packed decimal |
| VAR2.DCL | DBM.VAREREGISTER_DEL2 | VARCHAR(2000) → 49-level, COMP-5 for DECIMAL |
| ETH.DCL | DBM.ETIKETT_TYPE | Added STREKKODE-TYPE and AVDNR columns |
| VAR.DCL | DBM.VAREREGISTER | Added RAB-GRUPPE, RAB-GRUPPE-LAAS, MVA-SATS-KODE |
| KAMP.DCL | DBM.KAMPANJE | Added AVDNR, corrected KAMPANJE-TYPE |

#### COBOL Type Mapping Rules (DB2 → COBOL Host Variables)

| DB2 Type | COBOL PIC | Notes |
|----------|-----------|-------|
| DECIMAL(p,0) where p≤9 | PIC S9(p) COMP-3 | Packed decimal, common for FKNRs |
| DECIMAL(p,s) | PIC S9(p-s)V9(s) COMP-3 | With decimal places |
| SMALLINT | PIC S9(4) COMP-5 | Binary 2-byte |
| INTEGER | PIC S9(9) COMP-5 | Binary 4-byte |
| CHAR(n) | PIC X(n) | Fixed-length character |
| VARCHAR(n) | 49-level structure | `49 xxx-L PIC S9(4) COMP-5` + `49 xxx-D PIC X(n)` |
| TIMESTAMP | PIC X(26) | ISO string format |
| DATE | PIC X(10) or PIC S9(8) COMP-3 | Depends on legacy convention |

---

## 4. Comprehensive Pipeline Script

### Invoke-VcFullPipeline.ps1

A new self-contained script that performs the entire compile+bind workflow:

1. **Phase 0:** Validate inputs, check DatabasesV2.json
2. **Phase 1:** Create VCPATH directory structure
3. **Phase 2:** Deploy CBL + CPY sources into VCPATH layout
4. **Phase 3:** Generate compiler directive files (Std + SQL)
5. **Phase 4:** Batch compile all programs
6. **Phase 5:** DB2 Bind (Kerberos SSO, no password required)
7. **Phase 6:** Generate JSON report + optional SMS notification

**Usage:**

```powershell
# Compile all, bind to FKAVDNT (default)
.\Invoke-VcFullPipeline.ps1

# Compile only (no bind)
.\Invoke-VcFullPipeline.ps1 -SkipBind

# Compile and bind to BASISTST
.\Invoke-VcFullPipeline.ps1 -DatabaseAlias BASISTST

# Custom source folders
.\Invoke-VcFullPipeline.ps1 -CblFolder 'D:\sources\cbl' -CpyFolder 'D:\sources\cpy' -DatabaseAlias BASISMIG
```

### Key Features

- **ANSI-1252 aware:** All file reading uses `[System.Text.Encoding]::GetEncoding(1252)`
- **Auto-detects compiler path:** Tries Rocket Software first, falls back to Micro Focus
- **Auto-detects SQL programs:** Scans for `EXEC SQL` to add DB2 directives
- **Source format heuristic:** Detects fixed vs variable format from sequence numbers
- **DatabasesV2.json validation:** Validates alias against central config
- **Kerberos SSO:** DB2 bind uses `CONNECT TO <alias>` without credentials
- **Progress reporting:** Logs every 100 programs with compile rate
- **JSON reports:** Pipeline and bind reports saved to VCPATH
- **SMS notification:** Optional `-SendNotification` flag

---

## 5. Server Deployment

### Source Copy Script

`Copy-VcSourcesToServer.ps1` copies all collected sources to a target server:

```powershell
# Default: copy to dedge-server
.\Copy-VcSourcesToServer.ps1

# Copy to a different server
.\Copy-VcSourcesToServer.ps1 -TargetServer 't-no1fkmmig-db'

# Force overwrite all files
.\Copy-VcSourcesToServer.ps1 -Force
```

Target path: `\\<server>\opt\data\VisualCobol\Sources\{cbl,cpy,cbl_uncertain,cpy_uncertain}`

### Deploy Scripts

`_deploy.ps1` deploys all VisualCobol scripts to `dedge-server`:

```powershell
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\VisualCobol\_deploy.ps1"
```

---

## 6. Rocket Visual COBOL Software Packages

### Available Packages on C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\WindowsApps\

| Package Name | Installer | Type |
|--------------|-----------|------|
| Rocket Visual Cobol For Visual Studio 2022 Version 11 | `vcvs2022_110.exe` | IDE integration (base) |
| Rocket Visual Cobol For Visual Studio 2022 Version 11 Update Patch 3 | `vcvs2022_110_pu03_390812.exe` | IDE patch |
| Rocket Visual Cobol Server Version 11 | `cs_110.exe` / `csx64_110.exe` | Server runtime (base) |
| Rocket Visual Cobol Server Version 11 Update Patch 3 | `cs_110_pu03_390812.exe` / `csx64_110_pu03_390812.exe` | Server runtime patch |
| Rocket Temp | Multiple subfolders | Staging area for all products |

### Build Tools (in staging folders)

| Tool | Executable | Purpose |
|------|-----------|---------|
| Build Tools x86 | `vcbt_110.exe` / `vcbt_110_pu03_390812.exe` | Headless compilation (32-bit) |
| Build Tools x64 | `vcbtx64_110.exe` / `vcbtx64_110_pu03_390812.exe` | Headless compilation (64-bit) |

### Installation

All packages are registered in `SoftwareUtils.psm1` and can be installed via:

```powershell
Import-Module SoftwareUtils -Force

# Install VS2022 base + patch
Install-WindowsApps -AppName 'Rocket Visual Cobol For Visual Studio 2022 Version 11'
Install-WindowsApps -AppName 'Rocket Visual Cobol For Visual Studio 2022 Version 11 Update Patch 3'

# Install Server base + patch
Install-WindowsApps -AppName 'Rocket Visual Cobol Server Version 11'
Install-WindowsApps -AppName 'Rocket Visual Cobol Server Version 11 Update Patch 3'
```

Or use the convenience wrapper:

```powershell
.\Install-RocketVisualCobol.ps1 -Package All          # Everything
.\Install-RocketVisualCobol.ps1 -Package All-VS2022    # VS2022 base + patch
.\Install-RocketVisualCobol.ps1 -Package All-Server    # Server base + patch
.\Install-RocketVisualCobol.ps1 -Package Server-Base   # Single package
```

**Install order:** Always install base before patch.

---

## 7. Known Issues & Remaining Work

### Resolved Issues

| Issue | Resolution |
|-------|-----------|
| ANSI-1252 encoding not handled | Fixed in Invoke-VcCompile.ps1 and Step4 |
| Default DB alias was DB2DEV | Changed to FKAVDNT (matches $SET headers) |
| Only a few programs compiled | Pipeline now targets all 3,471 programs |
| Missing copybooks/DCLs | 10+ reconstructed from SYSCAT.COLUMNS and program usage |
| Trailing sequence numbers in source | Cleaned in affected files (BDHMARK.CBL) |

### Expected Remaining Failures

| Category | Estimated Count | Reason |
|----------|----------------:|--------|
| Missing copybooks (COBCH0008) | ~130 unique | Not all copybooks exist in any known source |
| DCL/host variable mismatches (COBDB0103) | Unknown | Some tables may have changed schema |
| Legacy constructs (COBCH0xxx) | ~50 | Older COBOL syntax not supported in VC 11 |
| Date-pattern filenames (skipped) | Variable | Backup/archive copies excluded automatically |

### Next Steps

1. **Run full pipeline** on dedge-server after deploying sources
2. **Analyze FailedCompilations.txt** to categorize remaining errors
3. **Reconstruct remaining DCL files** from SYSCAT.COLUMNS as needed
4. **Bind successfully compiled programs** to FKAVDNT
5. **Validate .int files** against production runtime

---

## 8. File Reference

### Project Structure

```
DevTools/LegacyCodeTools/VisualCobol/
├── _deploy.ps1                      # Deploy to dedge-server
├── Invoke-VcCompile.ps1             # Single-file compiler (ANSI-1252 fixed)
├── Invoke-VcFullPipeline.ps1        # NEW: Full compile+bind pipeline
├── Copy-VcSourcesToServer.ps1       # NEW: Copy sources via UNC
├── Install-RocketVisualCobol.ps1    # NEW: Install VC packages
├── Invoke-VcCodeMigration.ps1       # Migration orchestrator
├── Config/                          # Compiler directive templates
├── Steps/
│   ├── Step10-Copy-VcSourceFiles.ps1
│   ├── Step20-Test-VcMissingCopybooks.ps1
│   ├── Step30-Initialize-VcEnvironment.ps1  # Modified: FKAVDNT default
│   ├── Step40-Invoke-VcBatchCompile.ps1     # Modified: ANSI-1252 fixed
│   ├── Step50-Invoke-VcDb2Bind.ps1
│   ├── Step60-Get-VcMigrationStatusReport.ps1
│   ├── Step70-Deploy-VcCompiledToServer.ps1 # ManualRestart
│   ├── Step80-Copy-VcSourcesToServer.ps1    # ManualRestart
│   ├── steps-config.json                    # Step definitions
│   └── current-step.json                    # Pipeline state (auto-generated)
├── OneTime/                         # One-time setup scripts
├── RecompilationReport/             # Generated reports
└── _old/                            # Archived/superseded scripts
```

### Module Changes

| Module | Change |
|--------|--------|
| `_Modules/SoftwareUtils/SoftwareUtils.psm1` | Added 5 new Rocket VC switch cases in Install-WindowsApps |

---

## 9. Database Configuration Reference

### DatabasesV2.json Aliases (FKM Application)

| Alias | Environment | Server | Safe for Testing |
|-------|-------------|--------|:----------------:|
| FKAVDNT | DEV | t-no1fkmdev-db | Yes |
| BASISTST | TST | t-no1fkmtst-db | Yes |
| BASISVFT | VFT | t-no1fkmvft-db | Yes |
| BASISFUT | FUT | t-no1fkmfut-db | Yes |
| BASISKAT | KAT | t-no1fkmkat-db | Yes |
| BASISMIG | MIG | t-no1fkmmig-db | Yes |
| BASISRAP | RAP | p-no1fkmrap-db | **PRODUCTION** |
| BASISPRO | PRD | p-no1fkmprd-db | **PRODUCTION** |

All test databases (`t-` prefix) use Kerberos SSO. The pipeline script validates
the alias against DatabasesV2.json before starting compilation.
