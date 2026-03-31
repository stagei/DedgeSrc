# AnalysisResult — UseNewConfigurations Incompatibilities in Db2-Handler

**Author:** Geir Helge Starholm, www.dEdge.no  
**Created:** 2026-03-01  
**Technology:** DB2 / PowerShell

---

## Overview

When `UseNewConfigurations` is set on the WorkObject, the database should use:
- **Automatic storage** for tablespaces
- **AUTOSIZE YES** for all bufferpools (no hardcoded sizes)
- **SELF_TUNING_MEM ON** (DB2 manages memory allocation dynamically)

This document lists all locations in `Db2-Handler.psm1` that set values incompatible with the new configuration model.

---

## Fixed (already guarded by UseNewConfigurations)

| Location | Function | What | Status |
|---|---|---|---|
| Line ~7087 | `Set-PostRestoreConfiguration` | Hardcoded bufferpool CREATE/ALTER with fixed sizes (IBMDEFAULTBP 3M/100K, BIGTAB 2M/500K, USER32 5K) | **FIXED** — skipped when UseNewConfigurations |
| Line ~7088 | `Set-PostRestoreConfiguration` | `SELF_TUNING_MEM OFF` | **FIXED** — set to ON when UseNewConfigurations |

---

## Candidates for future review

### 1. `Set-Db2InitialConfiguration` — DB2_OVERRIDE_BPF=5000 (line ~7015)

```powershell
$db2Commands += "db2set -i $($WorkObject.InstanceName) DB2_OVERRIDE_BPF=5000"
```

**What it does:** Forces all bufferpools to 5000 pages regardless of their configured size. Used as a safety net during initial database creation/restore so the instance can start even with large bufferpool definitions.

**Incompatibility:** With UseNewConfigurations, bufferpools should use AUTOSIZE. Setting DB2_OVERRIDE_BPF overrides AUTOSIZE behavior. It IS cleared later in `Set-PostRestoreConfiguration` (line ~7140: `db2set -i ... DB2_OVERRIDE_BPF=`), but during the window between these two calls, the override is active.

**Risk:** LOW — the override is temporary and is cleared in the same pipeline. No action needed unless the pipeline is interrupted between these steps.

**Recommendation:** Consider skipping `DB2_OVERRIDE_BPF=5000` when UseNewConfigurations, since automatic bufferpools don't need the override.

---

### 2. `Add-DatabaseConfigurations` — SELF_TUNING_MEM OFF (lines ~3473, ~3493)

```powershell
# PrimaryDb branch (line 3473):
$db2Commands += "db2 update db cfg for $($WorkObject.DatabaseName) using SELF_TUNING_MEM OFF"

# FederatedDb branch (line 3493):
$db2Commands += "db2 update db cfg for $($WorkObject.DatabaseName) using SELF_TUNING_MEM OFF"
```

**What it does:** Disables self-tuning memory during initial database configuration, before restore happens.

**Incompatibility:** UseNewConfigurations expects SELF_TUNING_MEM ON. This is later overridden by `Set-PostRestoreConfiguration` (which now sets it to ON when UseNewConfigurations), so the final state is correct. But the intermediate state has it OFF.

**Risk:** LOW — `Set-PostRestoreConfiguration` runs after this and corrects the value. Only matters if pipeline stops between these steps.

**Recommendation:** Add `UseNewConfigurations` guard here too for consistency, or accept the current behavior since the final state is correct.

---

### 3. `Add-DatabaseConfigurations` — AUTO_MAINT OFF (line ~3507)

```powershell
$db2Commands += "db2 update db cfg for $($WorkObject.DatabaseName) using AUTO_MAINT OFF"
```

**What it does:** Disables automatic maintenance (auto-backup, auto-runstats, auto-reorg) unconditionally for all configurations.

**Incompatibility:** None currently — even with UseNewConfigurations, AUTO_MAINT OFF is intentional (maintenance is handled by scheduled tasks, not DB2's built-in scheduler).

**Risk:** NONE — this is the desired behavior for both old and new configurations.

**Recommendation:** No change needed.

---

### 4. `Set-PostRestoreConfiguration` — DB2_OVERRIDE_BPF= clear (line ~7140)

```powershell
$db2Commands += "db2set -i $($WorkObject.InstanceName) DB2_OVERRIDE_BPF="
```

**What it does:** Clears the bufferpool override set during initial configuration.

**Incompatibility:** None — this is correct for both old and new configurations. For UseNewConfigurations it's a no-op (the override shouldn't have been set in the first place if item #1 above is addressed).

**Risk:** NONE.

---

## Summary

| # | Function | Setting | Risk | Action |
|---|---|---|---|---|
| 1 | `Set-Db2InitialConfiguration` | `DB2_OVERRIDE_BPF=5000` | LOW | Consider skipping with UseNewConfigurations |
| 2 | `Add-DatabaseConfigurations` | `SELF_TUNING_MEM OFF` | LOW | Consider adding guard for consistency |
| 3 | `Add-DatabaseConfigurations` | `AUTO_MAINT OFF` | NONE | Keep as-is |
| 4 | `Set-PostRestoreConfiguration` | `DB2_OVERRIDE_BPF=` (clear) | NONE | Keep as-is |

Only items 1 and 2 are candidates for future guarding. Both are LOW risk because subsequent steps correct the final state. Item 3 is intentionally the same for both old and new configurations.
