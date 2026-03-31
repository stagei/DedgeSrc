# Copy-VcSourceFiles — Collection and Match Process

**Script:** `DevTools/LegacyCodeTools/VisualCobol/Copy-VcSourceFiles.ps1 -CollectAll`
**Created:** 2026-03-11

---

## Output Folder Structure

```
C:\opt\data\VisualCobol\Copy-VcSourceFiles\
├── Sources\
│   ├── cbl\                  # CBL programs — basename matches a .int file
│   ├── cbl_uncertain\        # CBL programs — no .int match, or displaced
│   ├── cpy\                  # Copy elements — referenced by COPY statements
│   └── cpy_uncertain\        # Copy elements — unreferenced or uncertain
├── FileIndex-{timestamp}.json    # Full metadata for every file processed
├── FileIndex-{timestamp}.tsv     # Tab-separated summary for Excel/grep
└── CollectAll-{timestamp}.json   # Run summary with stats
```

---

## Source Folders (54 total)

```mermaid
flowchart LR
    subgraph pri [Priority Folders — Pri1 to Pri4]
        P1["Pri1: fkavd\NT"]
        P2["Pri2: fkavd\utgatt"]
        P3["Pri3: CBLARKIV"]
        P4["Pri4: fkavd\BACKUP-20160310"]
    end

    subgraph nonpri [Non-Priority Folders — 50 folders]
        NP1["fka\ref, fka\work, ..."]
        NP2["fkavd\prod, fkavd\test, ..."]
        NP3["Git repo: Dedge\cbl, cpy, gs"]
    end

    pri -->|"Scanned first, in order"| LOOP[Collection Loop]
    nonpri -->|"Scanned after Pri4"| LOOP
```

---

## Collection Flow

```mermaid
flowchart TD
    START[File from source folder] --> EXT{Known extension?}

    EXT -->|".BND"| SKIP_EXT[Skipped — excluded extension]
    EXT -->|".CBL .COB"| CBL_GROUP[CBL group]
    EXT -->|".CPY .CPB .DCL .CPX .GS .IMP .MF .INT .IDY"| CPY_GROUP[CPY group]
    EXT -->|"Other"| CONTENT_CHECK["Test-CobolContent\n(read file, check for COBOL markers)"]

    CONTENT_CHECK --> CC_RESULT{Confidence?}
    CC_RESULT -->|"HIGH/MEDIUM\nwith PROGRAM-ID"| CBL_UNC_CC[cbl_uncertain]
    CC_RESULT -->|"HIGH/MEDIUM\nno PROGRAM-ID"| CPY_UNC_CC[cpy_uncertain]
    CC_RESULT -->|LOW| CPY_UNC_CC
    CC_RESULT -->|NONE| SKIP_CC[Skipped — not COBOL]

    CBL_GROUP --> INT_CHECK{"Basename in\n.int file list?"}
    CPY_GROUP --> REGEX_CHECK{"Basename matches\nuncertain regex?"}

    INT_CHECK -->|"No — not a known program"| CBL_UNC["cbl_uncertain\n(no dedup tracking)"]
    INT_CHECK -->|"Yes — known .int program"| DEDUP

    REGEX_CHECK -->|"Yes (date, backup, spaces)"| CPY_UNC["cpy_uncertain\n(no dedup tracking)"]
    REGEX_CHECK -->|"No — clean name"| DEDUP

    DEDUP{Basename already\nin tracking dict?}

    DEDUP -->|"Not seen"| CASE_A["Case A: Copy to cbl/ or cpy/\nRecord in tracking dict"]

    DEDUP -->|"Seen, existing\nis from priority"| CASE_B["Case B: SKIP entirely\n(priority source wins)"]

    DEDUP -->|"Seen, current is priority\nexisting is not"| CASE_C["Case C: Displace existing\nto *_uncertain as _matchN\nCopy new to cbl/ or cpy/"]

    DEDUP -->|"Both non-priority\nnew is NEWER"| CASE_D["Case D: Displace old\nto *_uncertain as _matchN\nCopy new to cbl/ or cpy/"]

    DEDUP -->|"Both non-priority\nnew is OLDER"| CASE_E["Case E: Copy new\nto *_uncertain as _matchN"]
```

---

## CBL Basename Matching — .int File Comparison

The script loads all `*.int` files from `\\DEDGE.fk.no\erpprog\cobnt` (non-recursive) at startup. The basenames of these files are the **canonical program names**. A CBL file is "certain" only if its basename exactly matches one of these `.int` basenames.

```mermaid
flowchart TD
    LOAD["Startup: Load *.int from\n\\\\DEDGE.fk.no\\erpprog\\cobnt"] --> HASHSET["HashSet of .int basenames\n(case-insensitive)"]

    FILE["CBL file: BSHBUOR_2.CBL\nBaseName: BSHBUOR_2"] --> LOOKUP{"BSHBUOR_2 in\n.int HashSet?"}

    LOOKUP -->|"No"| UNC["cbl_uncertain/\nReason: No matching .int basename"]
    LOOKUP -->|"Yes"| CERTAIN["cbl/ — enters\npriority dedup logic"]
```

### Examples with .int comparison

| Filename | BaseName | In .int list? | Result |
|---|---|---|---|
| `BSHBUOR.CBL` | `BSHBUOR` | YES — `BSHBUOR.INT` exists | `cbl/` |
| `bshbuor_20100305.cbl` | `bshbuor_20100305` | NO | `cbl_uncertain/` |
| `BSHBUOR_2.CBL` | `BSHBUOR_2` | NO | `cbl_uncertain/` |
| `BSHBUOR_NY.CBL` | `BSHBUOR_NY` | NO | `cbl_uncertain/` |
| `BACKUP_OIAAUTO.CBL` | `BACKUP_OIAAUTO` | NO | `cbl_uncertain/` |
| `AAAM006.CBL` | `AAAM006` | YES — `AAAM006.INT` exists | `cbl/` |

No regex heuristic needed for CBL files — the `.int` list is the single source of truth.

---

## CPY Basename Matching — Two-Phase

CPY files do not have `.int` equivalents. They are validated in two phases:

**Phase 1 (during collection):** Regex heuristic catches obvious non-basenames:

```
^(BACKUP|KOPI|...)[-_]      prefix markers
[\s_-]\d{4,}                date suffixes (_170108)
[-_](OLD|NY|ASK|...)        backup/variant suffixes
\s                          spaces in name
\d{6,}                      6+ consecutive digits
```

**Phase 2 (post-collection):** Parse all CBL files for `COPY` statements. Any CPY file not referenced by any COPY statement is moved to `cpy_uncertain/`.

```mermaid
flowchart TD
    PARSE["Parse all CBL files in cbl/\nExtract COPY statement references"] --> REFS["Build HashSet of\nreferenced copy element names"]

    REFS --> CHECK["For each file in cpy/"]
    CHECK --> MATCH{Basename in\nreferenced set?}
    MATCH -->|Yes| KEEP["Stays in cpy/"]
    MATCH -->|No| MOVE["Moved to cpy_uncertain/\nAction = moved_post_validation\nReason = not referenced by COPY"]
```

---

## JSON Tracking

Every file encountered generates a metadata record in `FileIndex-{timestamp}.json`:

```
BaseName, OriginalName, SourcePath, SourceFolder, Extension,
Type (cbl/cpy), IsPrioritySource, CreationTime, LastWriteTime,
FileSize, Action, Reason, DestinationPath, DestinationFolder,
RenamedTo, DisplacedBy, MatchTag, IntMatch, PostValidation
```

| Action | Meaning |
|---|---|
| `copied` | File copied to destination folder |
| `skipped` | Duplicate skipped (priority exists, same-size, or non-COBOL) |
| `displaced` | Existing file moved to *_uncertain because a newer/priority file replaced it |
| `moved_post_validation` | CPY file moved from cpy/ to cpy_uncertain/ (not referenced by COPY) |
