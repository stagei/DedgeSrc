# Deploy Pipeline Verification Report

**Date:** 2026-03-22 15:54–15:57  
**Tested by:** AI Agent (Cursor)  
**Test folder:** `DevTools\DatabaseTools\Db2-LargeTableYearSplit`  
**Target server:** `t-no1fkmmig-db`  

---

## Objective

Verify that when a script's `_deploy.ps1` is executed, **both** the script changes **and** any changes to modules in `_Modules/` are:

1. Copied from source to local staging (`C:\opt\DedgePshApps\`)
2. Code-signed with the Dedge AS certificate
3. Distributed to the remote staging area (`C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgePshApps\`)
4. Distributed to the target server install path (`\\t-no1fkmmig-db\opt\DedgePshApps\`)

---

## Test Setup

| Item | File | Location |
|------|------|----------|
| **Script** | `Get-SplitJobStatus.ps1` | `DevTools\DatabaseTools\Db2-LargeTableYearSplit\` |
| **Module** | `GlobalFunctions.psm1` | `_Modules\GlobalFunctions\` |
| **Deploy script** | `_deploy.ps1` | Calls `Deploy-Files -FromFolder $PSScriptRoot -ComputerNameList @("t-no1fkmmig-db")` |

The script imports `GlobalFunctions` and `Db2-Handler` via `Import-Module`. Deploy-Handler auto-detects these module dependencies by scanning `Import-Module` statements.

### Test changes applied

- **Script:** Added comment `# Deploy pipeline test marker 2026-03-22 - script change (remove after test)` at line 1
- **Module:** Added comment `# Deploy pipeline test marker 2026-03-22 - module change (remove after test)` at line 1

---

## Baseline (Before Changes)

| Location | Script Hash (SHA256) | Module Hash (SHA256) |
|----------|---------------------|----------------------|
| Source (repo) | `7E3BA26F...54E92` | `2C329688...9CEEA` |
| Local staging | `88CC78B8...B4EBE` (signed) | `3BC3FB7D...70AD8` (signed) |
| Remote staging | `88CC78B8...B4EBE` (signed) | `3BC3FB7D...70AD8` (signed) |
| Target server | `88CC78B8...B4EBE` (signed) | `3BC3FB7D...70AD8` (signed) |

**Observation:** Source and staging hashes differ (expected — signature block is appended during signing). All three staging/deploy locations are identical.

---

## Deploy Execution

Command: `_deploy.ps1` from `Db2-LargeTableYearSplit\`

### Deploy log (key events)

```
[15:54:47] Hash mismatch - Copying new version to staging: GlobalFunctions.psm1
[15:54:56] Successfully signed: C:\opt\DedgePshApps\CommonModules\GlobalFunctions\GlobalFunctions.psm1
[15:54:56] New version detected and signed. Created version file CommonModules-20260322155456369.version
[15:54:56] Deploying App Db2-LargeTableYearSplit to 2 paths:
[15:54:56]   → C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgePshApps\CommonModules
[15:54:56]   → \\t-no1fkmmig-db.DEDGE.fk.no\opt\DedgePshApps\CommonModules
[15:55:01] Hash mismatch - Copying new version to staging: Get-SplitJobStatus.ps1
[15:55:11] Successfully signed: C:\opt\DedgePshApps\Db2-LargeTableYearSplit\Get-SplitJobStatus.ps1
[15:55:11] New version detected and signed. Created version file Db2-LargeTableYearSplit-20260322155511224.version
[15:55:11] Deploying App Db2-LargeTableYearSplit to 2 paths:
[15:55:11]   → C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgePshApps\Db2-LargeTableYearSplit
[15:55:11]   → \\t-no1fkmmig-db.DEDGE.fk.no\opt\DedgePshApps\Db2-LargeTableYearSplit
```

### Deploy sequence observed

1. **Module first:** Deploy-Handler detected `GlobalFunctions` as a dependency, found the hash mismatch, copied to local staging, signed it, then distributed.
2. **Script second:** After module deployment, the script was processed — hash mismatch detected, copied, signed, distributed.
3. **Total time:** 26 seconds

---

## Post-Deploy Verification

### Test marker presence

| Location | Script has marker | Module has marker |
|----------|:-:|:-:|
| Source (repo) | YES | YES |
| Local staging (`C:\opt\DedgePshApps\`) | YES | YES |
| Remote staging (`C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\...`) | YES | YES |
| Target server (`\\t-no1fkmmig-db\opt\...`) | YES | YES |

### Signature verification

| Location | Script Signed | Script Sig Status | Module Signed | Module Sig Status |
|----------|:-:|:-:|:-:|:-:|
| Source (repo) | No | N/A | No | N/A |
| Local staging | Yes | **Valid** | Yes | **Valid** |
| Remote staging | Yes | **Valid** | Yes | **Valid** |
| Target server | Yes | **Valid** | Yes | **Valid** |

**Certificate subject:** `CN=Dedge AS, O=Dedge AS, L=Lillestrøm, C=NO`

### Hash consistency (post-deploy)

| File | Local Staging | Remote Staging | Target Server | Consistent? |
|------|:--:|:--:|:--:|:-:|
| Script | `0BC228...DD59` | `0BC228...DD59` | `0BC228...DD59` | **YES** |
| Module | `62ACFA...7980` | `62ACFA...7980` | `62ACFA...7980` | **YES** |

### Version markers (post-deploy)

| Location | Script Version | Module Version |
|----------|---------------|----------------|
| Local staging | `Db2-LargeTableYearSplit-20260322155511224.version` | `CommonModules-20260322155456369.version` |
| Target server | `Db2-LargeTableYearSplit-20260322155511224.version` | `CommonModules-20260322155456369.version` |

---

## Findings

### PASS: Deploy pipeline works correctly

1. **Module auto-detection works.** Running a script's `_deploy.ps1` automatically detects module dependencies (via `Import-Module` scanning) and includes them in the deployment.
2. **Signing works.** Both scripts and modules are code-signed with the Dedge AS certificate. Signature status is `Valid` at all locations.
3. **Hash consistency.** All three deploy destinations (local staging, remote staging, target server) receive identical copies.
4. **Version tracking.** Version marker files are created and propagated consistently.

### IMPORTANT CAVEAT: Module scope is limited to script targets

When deploying via a script's `_deploy.ps1`, the module changes **only propagate to the servers in that script's `ComputerNameList`**. In this test:

- `_deploy.ps1` targets `@("t-no1fkmmig-db")`
- Module was deployed to: `dedge-server` (staging) + `t-no1fkmmig-db` (target)
- Module was **NOT** deployed to other servers (e.g., `p-no1fkmrap-db`, `t-no1fkmtst-db`, etc.)

**Impact:** If you change a shared module and only deploy via one script's `_deploy.ps1`, other servers will remain on the old version of that module. To update the module on **all** servers, run `_Modules\_deploy.ps1` which targets all servers via `Get-ValidServerNameList`.

### OBSERVED ISSUE: File lock during rapid re-deploy

During the revert deploy (second run within ~60 seconds), `DedgeSign` reported a file lock error on `GlobalFunctions.psm1`:

```
Failed to sign file. Exit code: 1. Output: SignTool Error: The file is being used by another process.
```

Despite the signing failure, Deploy-Handler still created a version file and proceeded with distribution. The file was distributed **unsigned** to some destinations. A subsequent retry resolved the issue.

**Recommendation:** Deploy-Handler should either retry signing on file-lock errors or halt distribution when signing fails.

---

## Conclusion

The `_deploy.ps1` pipeline **correctly propagates both script and module changes** through the full chain: source → local staging (signed) → remote staging → target server. The key constraint is that module distribution scope is limited to the script's `ComputerNameList`. For shared module changes affecting all servers, use `_Modules\_deploy.ps1` instead.

---

## Cleanup

All test markers were reverted and clean versions were redeployed. No test artifacts remain in production.
