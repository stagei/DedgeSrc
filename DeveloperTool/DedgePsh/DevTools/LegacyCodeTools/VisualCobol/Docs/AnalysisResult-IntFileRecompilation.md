# Do We Need to Recompile Old .INT Files from Micro Focus Net Express 5.1?

**Author:** Geir Helge Starholm, www.dEdge.no
**Created:** 2026-03-02
**Technology:** Rocket Visual COBOL 11 / Micro Focus Net Express 5.1

---

## Short Answer

**Yes -- recompilation is required.** You cannot reliably use old `.INT` files compiled with Micro Focus Net Express 5.1 under the Rocket Visual COBOL 11 runtime. Old `.GNT` files are explicitly **not supported at all**.

---

## Detailed Findings

### 1. .GNT Files: Explicitly Incompatible

The Rocket Visual COBOL 11 documentation states this directly:

> **.gnt files that were part of the Net Express cannot be used in Visual COBOL and are ignored.**
>
> -- *Converting Net Express Projects to Visual Studio Projects* (Rocket Visual COBOL Documentation Version 11)

If any production programs use `.GNT` files, they **must** be recompiled. There is no workaround.

### 2. .INT Files: Not Guaranteed Compatible

While `.INT` files use a portable intermediate code format, the documentation provides strong evidence that old `.INT` files should be recompiled:

| Evidence | Source |
|---|---|
| COBRT211 error: *"Program not executable by Run-Time System (Fatal). System executable, shared library, and callable shared object files that have been linked using older COBOL systems could be incompatible."* Resolution: **Recompile and/or relink.** | COBRT211 message reference |
| 32-bit/64-bit incompatibility: *"All code must be compiled and linked using the same word length. A 64-bit run-time system does not run programs compiled and/or linked on 32-bit platforms."* | COBRT211 message reference |
| Behavioral changes between versions: FCD format defaults changed from FCD2 to FCD3, Communication section syntax removed, line numbering behavior changed | Significant Changes in Behavior or Usage, Backward Compatibility with Older Generation Products |
| Rocket recommends compiling to `.dll`/`.exe` instead of `.int`/`.gnt` | Specifying Build Settings |

### 3. Rocket Software's Official Recommendation

From *Specifying Build Settings* (Rocket Visual COBOL Documentation Version 11):

> **Rocket Software recommends that you compile your new projects to native executables, .dll and .exe, instead of to .int or .gnt code.**
>
> .dll and .exe files have multiple advantages:
> - Better performance compared to .int and .gnt code
> - Support for the use of native resources with your projects
> - Support for static references to native APIs
> - The code is shared between the processes
> - Enable linking COBOL, C and C++ code together

### 4. Complete List of Recompilation Disqualifiers

Every item below is a documented difference between Net Express 5.1 and Rocket Visual COBOL 11 that can cause an old `.INT` file to **fail, crash, or produce wrong results** at runtime without recompilation.

#### Category A: Hard Blockers (will crash or refuse to load)

| # | Disqualifier | Runtime Error | Source |
|---|---|---|---|
| A1 | **.GNT files** from Net Express are explicitly blocked | Ignored / not loaded | Converting Net Express Projects to Visual Studio Projects |
| A2 | **32-bit INT on 64-bit runtime** -- Net Express 5.1 was 32-bit only. Visual COBOL defaults to 64-bit (`COBMODE=64` since R4+). If the runtime is launched in 64-bit mode, old 32-bit INT files will not execute. | `COBRT211` Fatal | COBRT211 message reference |
| A3 | **Incompatible runtime system version** -- linked executables, shared libraries, and callable shared objects from older COBOL systems may be incompatible with the current runtime | `COBRT211` Fatal | COBRT211 message reference |
| A4 | **OO programs compiled with incompatible version** -- object-oriented programs from an older compiler version may be incompatible with the OO support in the current runtime | `COBRT212` Fatal | COBRT212 message reference |
| A5 | **coblongjmp() in error/exit/signal handlers** -- previously allowed (documented as restriction), now enforced. Programs using this pattern will crash. | `COBRT131` Fatal | Significant Changes in Behavior or Usage |
| A6 | **COMMUNICATION SECTION** -- syntax was deprecated, still accepted in Net Express, now generates a hard error. Programs compiled with COMMUNICATION SECTION will contain code paths that reference removed runtime support. | `COBCH1895` (at recompile) / undefined behavior at runtime | Significant Changes in Behavior or Usage |
| A7 | **Incompatible Class Library version** -- if the INT file uses class library calls, the version mismatch between Net Express and Visual COBOL class libraries causes a fatal error | `COBRT111` Fatal | COBRT111 message reference |
| A8 | **IDY file mismatch** -- old `.idy` symbol files from Net Express are not compatible with Visual COBOL. Debugging/animation will fail. Support for `.idy` files from previous product versions was explicitly changed in v10.0. | `COBOP070` Cautionary | COBOP070 message reference, Significant Changes in Behavior (v10.0) |

#### Category B: Silent Data Corruption / Wrong Results (will run but produce incorrect output)

| # | Disqualifier | What Goes Wrong | Source |
|---|---|---|---|
| B1 | **FCD format default changed** from FCD2 (Net Express) to FCD3 (Visual COBOL) | File handling operations (`OPEN`, `READ`, `WRITE`, `CLOSE`) may pass wrong FCD structures to EXTFH/EXTSM, causing `RTS114` errors or silent data corruption | Backward Compatibility with Earlier Rocket COBOL Products |
| B2 | **IDXFORMAT default changed** from 4 (Net Express) to 8 (Visual COBOL) | Indexed file operations will use wrong format. New files created with format 8 are unreadable by old format-4 programs and vice versa | Backward Compatibility with Net Express 5.1 |
| B3 | **FILEMAXSIZE default changed** from 4 (Net Express) to 8 (Visual COBOL) | File size limits calculated differently. Large files may be handled incorrectly | Backward Compatibility with Net Express 5.1 |
| B4 | **DBCS literal treatment changed** -- Net Express treated alphanumeric literals containing only DBCS characters as class NCHAR. Visual COBOL treats all unqualified literals as alphanumeric. | String comparisons involving DBCS data produce different results (wrong padding) | Backward Compatibility with Net Express 5.1 |
| B5 | **Fixed Binary (p<=7) default changed** -- now 8-bit signed 2's complement integer by default | Arithmetic operations with small binary fields may produce different results | Significant Changes in Behavior (v2.2 Update 2) |
| B6 | **FCD initialization requirement** -- applications calling EXTFH or EXTSM must now initialize FCD with binary zeros in unused/reserved areas | `RTS114` errors or unpredictable file handling results | Significant Changes in Behavior or Usage |
| B7 | **MFALLOC_PCFILE default changed** from N to Y | Cataloguing files with `DSORG=PS` now creates physical files by default. May create unexpected files on disk. | Significant Changes in Behavior (v2.2 Update 2) |

#### Category C: Environment / Configuration Conflicts

| # | Disqualifier | What Goes Wrong | Source |
|---|---|---|---|
| C1 | **COBMODE default changed** from 32-bit to 64-bit (since Visual COBOL R4+) | Programs expecting 32-bit mode will fail if COBMODE is not explicitly set | Backward Compatibility with Net Express 5.1 |
| C2 | **COBREG_PARSED environment conflict** -- running Visual COBOL alongside Net Express causes registry/environment conflicts | Tools and utilities from one product interfere with the other | Backward Compatibility with Older Generation Products |
| C3 | **DB2 ECM updated for 64-bit** -- the DB2 External Compiler Module was updated to resolve runtime errors in 64-bit mode | DB2-bound programs must be recompiled with updated ECM and rebound | Significant Changes in Behavior (v2.0) |
| C4 | **Licensing system changed** -- SafeNet Sentinel licensing deprecated (removed in v10.0), replaced by RocketPass | Runtime may refuse to execute if licensing check fails | Significant Changes in Behavior (v10.0) |
| C5 | **ILUSING directive scope changed** -- scope now limited to the source file it is set in, not globally | Programs relying on global ILUSING may fail to resolve types | Significant Changes in Behavior (v2.0) |
| C6 | **Report Writer behavior changed** -- HOSTRW with mainframe dialect now produces full ASA control characters | Report output may differ from Net Express | Significant Changes in Behavior (v2.2 Update 2) |

#### Category D: Removed / Unsupported Features

| # | Feature | Status in Visual COBOL 11 | Source |
|---|---|---|---|
| D1 | **Animator** (debugger) | Removed -- replaced by Visual Studio debugger | Backward Compatibility with Net Express 5.1 |
| D2 | **Data Tools** (Data File Converter, Data File Editor, Fix File Index, IMS Database Editor) | Removed | Backward Compatibility with Net Express 5.1 |
| D3 | **FaultFinder** diagnostic tool | Removed (tunables `faultfind_*` must be removed) | Backward Compatibility with Older Generation Products |
| D4 | **Dialog System** (windowed UI for COBOL) | Available via Compatibility AddPack only, threading model changed | Significant Changes in Behavior (v2.3.1) |
| D5 | **command_line_linkage tunable** | Deprecated (use COMMAND-LINE-LINKAGE directive instead) | Significant Changes in Behavior (v2.3.2) |

---

## How to Check Your INT Files Against This List

For each production `.INT` file, check if the original `.CBL` source uses any of the features listed above. A quick scan can identify the most common disqualifiers:

```powershell
# Scan for common disqualifiers in COBOL source files
$patterns = @(
    @{ Pattern = 'COMMUNICATION\s+SECTION';     Risk = 'A6 - COMMUNICATION SECTION removed' }
    @{ Pattern = 'CALL.*coblongjmp';             Risk = 'A5 - coblongjmp() now fatal in handlers' }
    @{ Pattern = 'EXTFH|EXTSM';                  Risk = 'B1/B6 - FCD format + initialization changed' }
    @{ Pattern = 'NCHAR|DBCS';                    Risk = 'B4 - DBCS literal treatment changed' }
    @{ Pattern = 'EXEC\s+SQL';                    Risk = 'C3 - DB2 ECM updated, must recompile+rebind' }
    @{ Pattern = 'FAULTFIND';                     Risk = 'D3 - FaultFinder removed' }
    @{ Pattern = 'ILUSING';                       Risk = 'C5 - ILUSING scope changed' }
)
```

---

## Recommendation for Dedge Migration

### Phase 1: Recompile Everything

All `.INT` files currently deployed to `\\DEDGE.fk.no\erpprog\COBNT` must be recompiled from source using the Rocket Visual COBOL 11 compiler. Use the existing migration toolset:

```
1. Switch-CobolEnvironment.ps1 -Mode VC        # Set environment
2. Initialize-VcEnvironment.ps1                 # Create directory structure
3. Invoke-VcCodeMigration.ps1                   # Full pipeline: search, replace, copy, compile
```

### Phase 2: Consider Moving to .DLL/.EXE (Long Term)

Per Rocket's recommendation, the long-term target should be native executables (`.dll`/`.exe`) instead of `.INT` files, for performance and compatibility benefits.

### Phase 3: Programs Without Source Code

The `Compare-VcSourceToInt.ps1` audit script identifies production `.INT` files that have no matching `.CBL` source. These programs:

- **Cannot be recompiled** (no source)
- **May or may not work** under Visual COBOL runtime
- Must be tested individually against the new runtime
- If they fail with COBRT211, they are dead code and must be replaced or retired

---

## Summary Decision Matrix

| File Type | From Net Express 5.1 | Can Use As-Is? | Action Required |
|---|---|---|---|
| `.INT` (32-bit) | Yes | **No** (not reliable) | Recompile from source |
| `.GNT` | Yes | **No** (explicitly blocked) | Recompile from source |
| `.CBL` source | Yes | N/A (source code) | Recompile with Visual COBOL 11 |
| `.CPY` copybooks | Yes | Yes | No change needed (text files) |
| `.BND` bind files | Yes | **No** | Rebind against DB2 after recompile |
| `.BAT` / `.REX` scripts | Yes | Mostly | Update paths (Micro Focus -> Rocket Software) |

---

## Sources

| Source | Document |
|---|---|
| RAG: `user-visual-cobol-docs` | Converting Net Express Projects to Visual Studio Projects.md |
| RAG: `user-visual-cobol-docs` | Specifying Build Settings.md |
| RAG: `user-visual-cobol-docs` | COBRT211 Program not executable by Run-Time System (Fatal).md |
| RAG: `user-visual-cobol-docs` | Backward Compatibility with Older Generation Products.md |
| RAG: `user-visual-cobol-docs` | Significant Changes in Behavior or Usage.md |
| RAG: `user-visual-cobol-docs` | Upgrading from Rocket Net Express.md |
| RAG: `user-visual-cobol-docs` | Best Practice When Upgrading a Legacy Application.md |
| RAG: `user-visual-cobol-docs` | Building COBOL applications.md |
| RAG: `user-visual-cobol-docs` | New Features in 11.0.md |

All sources from **Rocket Visual COBOL Documentation Version 11** and **Visual COBOL Messages Reference 11**, accessed via the `user-visual-cobol-docs` RAG MCP server.
