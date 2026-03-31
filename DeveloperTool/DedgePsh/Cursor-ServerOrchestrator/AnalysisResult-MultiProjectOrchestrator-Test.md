# Cursor-ServerOrchestrator Multi-Project Test Report

**Date:** 2026-03-23 04:29-04:36  
**Server:** `dedge-server`  
**Tested by:** AI Agent (Cursor)

---

## Summary

| Test | Result |
|------|--------|
| 1. Deployment verification | **PASS** -- 15 files deployed, version 20260322 |
| 2. Command submission + pickup | **PASS** -- picked up within ~40s |
| 3. Multi-project concurrency | **PASS** -- two slots ran simultaneously |
| 4. Stdout capture + result files | **PASS** -- output captured correctly |
| 5. History archiving | **PASS** -- suffixed history files created |
| 6. DateTime parsing bug | **FOUND + FIXED** -- culture mismatch in 4 locations |
| 7. ACL on data folder | **PASS** -- Administrators + SYSTEM + developer group |

---

## Test 1: Deployment Verification

**App path:** `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\DedgePshApps\Cursor-ServerOrchestrator\`

15 files deployed correctly:

| File | Size | Last Modified |
|------|------|-------------|
| `Invoke-CursorOrchestrator.ps1` | 42 KB | 2026-03-22 21:18 |
| `_helpers\_CursorAgent.ps1` | 34 KB | 2026-03-22 21:18 |
| `_helpers\_Shared.ps1` | 29 KB | 2026-03-22 21:18 |
| `_helpers\Run-InlineScript.ps1` | 22 KB | 2026-03-03 21:41 |
| `_helpers\Set-CommandFolderAcl.ps1` | 25 KB | 2026-03-18 13:42 |
| `_helpers\Test-CommandSecurity.ps1` | 23 KB | 2026-03-03 21:20 |
| `_localHelpers\Get-OrchestratorStatus.ps1` | 33 KB | 2026-03-22 21:18 |
| `_install.ps1` | 22 KB | 2026-03-11 12:20 |
| + 4 docs, 3 template files | | |

**Data folder:** `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\Cursor-ServerOrchestrator\` -- 43 files, 100 history entries.

---

## Test 2 + 3: Multi-Project Concurrent Execution

Two inline scripts submitted simultaneously with different project names:

| Property | Slot A (`test-slot-A`) | Slot B (`test-slot-B`) |
|----------|:---:|:---:|
| Command file | `next_command_FKGEISTA_test-slot-A.json` | `next_command_FKGEISTA_test-slot-B.json` |
| Submitted at | 04:30:47 | 04:30:48 |
| Picked up at | 04:31:09 | 04:31:13 |
| PID | 12196 | 9292 |
| Status | COMPLETED | COMPLETED |
| Exit code | 0 | 0 |
| Elapsed | 16.2s | 12.8s |
| Completed at | 04:31:25 | 04:31:26 |

### Concurrency verification

Both processes were observed **RUNNING simultaneously** during poll 3 (elapsed ~30s). Slot A started at 04:31:09, Slot B at 04:31:13 -- they overlapped from 04:31:13 to 04:31:25 (12 seconds of concurrent execution).

### Output captured

```
Slot A: SLOT-A-START / Hostname: dedge-server / User: FKTSTADM / SLOT-A-DONE
Slot B: SLOT-B-START / OS: Microsoft Windows NT 10.0.26100.0 / PSVersion: 7.5.4 / SLOT-B-DONE
```

### History files created

```
2026-03-23_043125_FKGEISTA_test-slot-A_result.json
2026-03-23_043126_FKGEISTA_test-slot-B_result.json
```

---

## Test 4: Slot Isolation

Verified that different `-Project` values create separate file suffixes and run independently:

- Suffix format: `<USERNAME>_<sanitized-project>` (e.g. `FKGEISTA_test-slot-A`)
- Each slot has its own: `next_command_*.json`, `running_command_*.json`, `last_result_*.json`, `stdout_capture_*.txt`
- Slots do not interfere with each other

---

## Bug Found + Fixed: DateTime Parsing

### Problem

`[datetime]::Parse()` failed when parsing dates from `running_command_*.json` files:

```
Exception calling "Parse" with "1" argument(s): "String '03/23/2026 04:31:09'
was not recognized as a valid DateTime."
```

### Root cause

PowerShell 7's `ConvertFrom-Json` auto-converts ISO 8601 strings (`2026-03-23T04:31:09`) into `[DateTime]` objects. When passed to `[datetime]::Parse()`, the DateTime is implicitly converted to a string using the server's culture (US: `MM/dd/yyyy`), which then fails to parse on the dev machine (Norwegian `nb-NO` culture expects `dd.MM.yyyy`).

### Fix applied

Replaced bare `[datetime]::Parse()` with culture-aware handling in 4 locations:

```powershell
# Before (broken across cultures)
$startedAt = [datetime]::Parse($running.startedAt)

# After (handles both DateTime objects and ISO strings)
$startedAt = if ($running.startedAt -is [datetime]) { $running.startedAt } else {
    [datetime]::Parse($running.startedAt, [System.Globalization.CultureInfo]::InvariantCulture)
}
```

**Files fixed:**
1. `_helpers\_Shared.ps1` line 158 (Read-RunningCommand)
2. `_helpers\_CursorAgent.ps1` line 247 (Get-AllRunningSlots)
3. `_localHelpers\Get-OrchestratorStatus.ps1` line 80 (running slot parser)
4. `_localHelpers\Get-OrchestratorStatus.ps1` line 97 (legacy running parser)

**Deployed to:** All 37 servers via `_deploy.ps1` (81.7 seconds).

### Verified

Post-fix `Invoke-ServerScript` retest completed without any datetime errors.

---

## Test 5: ACL on Data Folder

| Identity | Rights | Type |
|----------|--------|------|
| `NT-MYNDIGHET\SYSTEM` | FullControl | Allow |
| `BUILTIN\Administratorer` | FullControl | Allow |
| `SID S-1-5-21-...70319` (developer group) | Modify, Synchronize | Allow |

The developer group has Modify rights, which is required for writing command files and reading results over UNC.

---

## Orchestrator Architecture Verified

```
Developer Machine                           dedge-server
┌──────────────────────┐                    ┌────────────────────────────────┐
│ Cursor IDE           │                    │ Scheduled Task (every 60s)     │
│  └── _CursorAgent.ps1│                    │  └── Invoke-CursorOrchestrator │
│       │              │                    │       │                        │
│  Write-CommandFile ──┼── UNC write ──────►│  Scan next_command_*.json      │
│       │              │                    │       │                        │
│  Wait-ForResult ─────┼── UNC poll ◄──────│  Start-Process (per slot)      │
│       │              │                    │       │                        │
│  Read stdout/result ─┼── UNC read ◄──────│  Write running_command_*.json  │
│                      │                    │  Capture stdout/stderr         │
│                      │                    │  Write last_result_*.json      │
│                      │                    │  Archive to history/           │
└──────────────────────┘                    └────────────────────────────────┘
```

**Key design:** No PS remoting. All communication via UNC file shares. Multi-project concurrency via suffixed filenames (`<user>_<project>`).

---

## Conclusion

The multi-project orchestrator is fully operational on `dedge-server`. Concurrent execution, stdout capture, result files, history archiving, and slot isolation all work correctly. A culture-dependent datetime parsing bug was discovered and fixed across all servers during testing.
