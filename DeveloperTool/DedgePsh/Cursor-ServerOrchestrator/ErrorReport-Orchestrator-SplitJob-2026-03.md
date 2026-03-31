# Error report: Cursor-ServerOrchestrator + Db2-LargeTableYearSplit (March 2026)

**Audience:** Agent or operator maintaining **Cursor-ServerOrchestrator** and long-running jobs triggered via `Invoke-ServerCommand` / file-based slots.  
**Environment:** `t-no1fkmmig-db`, project slots `large-table-split` and `ltsplit-ordre`, script `%OptPath%\DedgePshApps\Db2-LargeTableYearSplit\Db2-LargeTableYearSplit.ps1`.

---

## Summary

Several issues made **monitoring and success/failure attribution unreliable**: orchestrator **result JSON** did not always match the command the operator thought they submitted; **slot reuse** and **long-running jobs** confused timelines; the **application script** sometimes exited **0** while **RenameAndReload** failed internally. This report documents observed behavior so the orchestrator agent can harden checks and documentation.

---

## 1. Result file vs. actual command (stale or mismatched metadata)

**Observed**

- `last_result_<user>_<project>.json` showed **`arguments`: `-RestoreFromPrd:$false`** and short elapsed time (~2–3 minutes) while embedded **stdout** still contained **multi-hour restore** output (`RESTORE DATABASE … CONTINUE`, `SET TABLESPACE CONTAINERS …`).
- Another result block showed **`completedAt`** ~20:16 with **`arguments`** `-RestoreFromPrd:$false` but output clearly belonging to an **earlier** or **different** phase (e.g. restore still running at ~18:03 in the same log file).

**Impact**

- An agent that trusts **`last_result_*.json` alone** can mark a run “done” or “no restore” incorrectly.
- **`output` is truncated** (“last 500 lines”) — cannot reconstruct full timeline from JSON only.

**Recommendation**

- Always correlate **`startedAt` / `completedAt`** with **`command`** and **`arguments`** and, if possible, **orchestrator `running_command_*.json`** timestamps.
- Treat **`last_result`** as “last completed slot execution” — not necessarily “the command I just queued” if another run was already in progress or queued.

---

## 2. One slot per server — queueing and `Wait-ForResult`

**Observed**

- **`Invoke-ServerCommand`** was invoked with a **new** project name (`ltsplit-ordre`) while a **long** job may still have been active or **another** slot/file state existed.
- **`Get-AllRunningSlots`** showed an active run: `Db2-LargeTableYearSplit.ps1`, **PID**, **`startedAt`**, project **`ltsplit-ordre`**.
- **`Test-OrchestratorReady -Project 'large-table-split'`** reported **IDLE** with a **last completed** time — **different project** = **different suffix** = different `last_result_*` file.

**Impact**

- “Idle on `large-table-split`” does **not** mean the server is idle for **all** split jobs; another **project** string = another slot.
- Agents must use **`Get-AllRunningSlots`** or the **exact `Project`** used in `Invoke-ServerCommand` when polling.

**Recommendation**

- Document: **`Project` parameter maps to `slotSuffix`** — always use **one consistent project name** per workflow, or always query **all running slots** before submitting.
- Prefer **`Get-AllRunningSlots -ServerName '<db-server>'`** before **`Invoke-ServerCommand`**.

---

## 3. Client wait duration vs. server runtime

**Observed**

- **`Invoke-ServerCommand -Timeout 7200`** waited until a result appeared; elapsed ~**8187 s** (~2.3 h) matched a **long** server-side run (`RestoreFromPrd:$true` / restore phase), not the short **~110 s** run the operator intended with `-RestoreFromPrd:$false`.

**Impact**

- The **client** waited for **whichever** job finished first in that slot — if the slot picked up a **previously queued** or **overlapping** execution, the **wait** attaches to **that** run’s `last_result`.

**Recommendation**

- After submission, verify **`running_command_<suffix>.json`** matches **expected command + arguments** before assuming the wait is for the right job.
- Consider **unique project names per invocation** (e.g. include date or guid) if strict 1:1 traceability is required — with cleanup of old result files documented.

---

## 4. Exit code 0 vs. application failure (Db2-LargeTableYearSplit)

**Observed** (application behavior **before** script fixes)

- Orchestrator reported **`exitCode`: 0**, **`status`: COMPLETED**, while **`RenameAndReload`** for **`DBM.K_ORDREHODE`** **failed** (e.g. **`SQL0750N`** rename, **`SQL0206N`** / **`INDSCHEMA`** on FK rebuild, empty view DDL recovery).
- Log lines: **`RenameAndReload failed`** … then later **`[JOB_COMPLETED] Db2-LargeTableYearSplit.ps1`**.

**Impact**

- **Orchestrator-level success** did **not** mean **business success** (all SQL objects recreated).

**Recommendation**

- For this app, agents should **grep app log** (`opt\data\Db2-LargeTableYearSplit\FkLog_*.log`) for:
  - **`=== RenameAndReload COMPLETE ===`**
  - Absence of **`RenameAndReload failed`**
- Application was later tightened to **throw** on DDL replay failure and **rethrow** on RenameAndReload failure — **re-verify** orchestrator still receives non-zero exit when the script exits 1.

---

## 5. Remote log and UNC access

**Observed**

- Reading **large** logs directly over **UNC** is slow / brittle; workspace rule: **copy to local temp** then `Select-String` / `Get-Content`.

**Recommendation**

- Orchestrator agent should **always** `Copy-Item` `\\<server>\opt\data\...\FkLog_*.log` to `%TEMP%` before analysis.

---

## 6. Monitoring script gap

**Observed**

- `_MonitorOrchestrator.ps1` (if present) only checks **`last_result`** for JSON with `exitCode`/`status` — does **not** validate **command line**, **arguments**, or **app log success strings**.

**Recommendation**

- Extend monitoring to:
  - Parse **`command` / `arguments` / `startedAt`** from `last_result_*.json`.
  - Optionally tail **app-specific** log for success/failure patterns when the command is known (e.g. LargeTableYearSplit).

---

## Checklist for the orchestrator-handling agent

| Step | Action |
|------|--------|
| 1 | `Get-AllRunningSlots -ServerName '<target>'` before submit |
| 2 | Submit with explicit **`-Project`**; remember suffix = `USERNAME_project` |
| 3 | Confirm **`running_command_*.json`** matches intended **command + arguments** |
| 4 | After completion, read **`last_result_*.json`** — verify **arguments** + **elapsed** + **timestamps** |
| 5 | For Db2-LargeTableYearSplit: copy **app log** locally; search **`RenameAndReload COMPLETE`** / **`RenameAndReload failed`** |
| 6 | Do not equate **orchestrator COMPLETED** with **DDL replay success** without log proof |

---

## Source attribution

| Source | Use |
|--------|-----|
| Conversation + log analysis on `t-no1fkmmig-db` | Symptoms and timelines |
| `DevTools/CodingTools/Cursor-ServerOrchestrator/_helpers/_CursorAgent.ps1` | `Invoke-ServerCommand`, `Test-OrchestratorReady`, `Get-AllRunningSlots` |
| `DevTools/DatabaseTools/Db2-LargeTableYearSplit/Db2-LargeTableYearSplit.ps1` | Prior exit-0 vs internal failure behavior (since tightened) |

| RAG MCP | Result |
|---------|--------|
| Not used | N/A |

---

## Suggested follow-ups (orchestrator / ops)

1. **Result JSON:** include **full** command line and **hash** of submitted `next_command_*.json` to disambiguate runs.
2. **Docs:** one paragraph in `_CursorAgent.ps1` comment block: “**Project** = slot; multiple projects = multiple concurrent logical queues per server.”
3. **Db2 app:** confirm **`exit 1`** propagates to orchestrator **`last_result.exitCode`** after strict `throw` paths.

---

*End of report.*
