# AnalysisResult: CommonModules Hash Mismatch Root Cause

**Author:** Geir Helge Starholm, www.dEdge.no  
**Created:** 2026-03-04  
**Technology:** PowerShell / Deploy-Handler

---

## Overview

When deploying any script via `Deploy-Handler`, **all CommonModules** report "Hash mismatch - Copying new version to staging" even though no source files have changed. This causes a full re-sign of every module (~30 files), adding 5+ minutes to every deployment. The problem recurs several times a day.

---

## Symptom

```
[Deploy-Handler.Copy-FilesToStaging.568] [INFO] Hash mismatch - Copying new version to staging: Agent-Handler.psm1
[DedgeSign.Set-Signature.416] [INFO] Successfully signed: C:\opt\DedgePshApps\CommonModules\Agent-Handler\Agent-Handler.psm1
[Deploy-Handler.Copy-FilesToStaging.568] [INFO] Hash mismatch - Copying new version to staging: AlertWKMon.psm1
[DedgeSign.Set-Signature.416] [INFO] Successfully signed: C:\opt\DedgePshApps\CommonModules\AlertWKMon\AlertWKMon.psm1
...
(repeats for ALL modules)
```

ALL modules show hash mismatch simultaneously, not just one or two. This is the key indicator that the `.unsigned` tracking files have been deleted.

---

## Root Cause Chain

The problem is caused by a chain of five interacting issues. The primary root cause is a bug in `Start-RoboCopy`.

### Step 1: Bug in `Start-RoboCopy` (PRIMARY ROOT CAUSE)

**File:** `_Modules\GlobalFunctions\GlobalFunctions.psm1`, lines 4918–4928

```powershell
# Line 4919: When -NoPurge is set, /PURGE is correctly omitted
if (-not $NoPurge) {
    $command = "$robocopyPath `"$fromFolder`" `"$deployFolder`" /PURGE"
} else {
    $command = "$robocopyPath `"$fromFolder`" `"$deployFolder`""
}

# Line 4927: When -Recurse is set, /MIR is ALWAYS added — /MIR = /E + /PURGE
if ($Recurse) {
    $command += " /MIR /R:3 /W:1"   # BUG: /MIR re-introduces /PURGE
}
```

When a caller passes both `-Recurse` and `-NoPurge`, the intent is "copy recursively but don't delete extra files in the destination". The initial command correctly omits `/PURGE`. But the `-Recurse` block unconditionally adds `/MIR`, which is equivalent to `/E + /PURGE`. This contradicts the `-NoPurge` flag and deletes destination files not present in the source.

### Step 2: `Install-OurPshAppSlave` Triggers the Bug

**File:** `_Modules\SoftwareUtils\SoftwareUtils.psm1`, line 4015

```powershell
$null = Start-Robocopy -SourceFolder $appSourcePath -DestinationFolder $appPath -Recurse -NoPurge -QuietMode
```

This function copies from the **network share** (e.g. `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgePshApps\CommonModules`) to the **local staging folder** (`C:\opt\DedgePshApps\CommonModules`).

The network share **never** has `.unsigned` files because Deploy-Handler explicitly excludes them when copying to deploy paths (line 740 of `Deploy-Handler.psm1`):

```powershell
robocopy "$DistributionSource" "$DeployPath" /S /XF *.unsigned deploy*.ps1 deploy*.bat deploy*.cmd ...
```

Because of the `Start-RoboCopy` bug, the `/MIR` flag purges all files in the local destination that don't exist in the network share source — **including all `.unsigned` tracking files**.

### Step 3: `Install-OurPshApp` Auto-Installs CommonModules

**File:** `_Modules\SoftwareUtils\SoftwareUtils.psm1`, lines 4093–4094

```powershell
if ($AppName.ToLower() -ne "commonmodules" -and -not $CalledByInitMachine) {
    $null = Install-OurPshAppSlave -AppName "CommonModules" -SkipReInstall:$SkipReInstall
}
```

**Any** call to `Install-OurPshApp` for **any** application automatically installs CommonModules first. This means any script that calls `Install-OurPshApp("SomeApp")` inadvertently triggers the `.unsigned` file destruction described in Step 2.

### Step 4: Silent Hash Failure in Deploy-Handler

**File:** `_Modules\Deploy-Handler\Deploy-Handler.psm1`, lines 554–567

```powershell
try {
    $newFileHash = Get-FileHash -Path $FilePath -Algorithm SHA256 -ErrorAction SilentlyContinue
    $newFileHash = $newFileHash.Hash
    # Get hash of unsigned file
    $unsignedHash = Get-FileHash -Path $unsignedFile -Algorithm SHA256 -ErrorAction SilentlyContinue
    $unsignedHash = $unsignedHash.Hash   # Returns $null when file is missing
}
catch {
    Write-LogMessage "Error getting hash of $stagingFile ..." -Level WARN
    $newFileHash = 1
    $unsignedHash = 2
}
# Compare hashes
if ($newFileHash -ne $unsignedHash) {
    Write-LogMessage "Hash mismatch - Copying new version to staging: $fileName" -Level INFO
```

When `.unsigned` files are missing:
- `Get-FileHash` returns `$null` (no exception due to `-ErrorAction SilentlyContinue`)
- `$unsignedHash` becomes `$null`
- The comparison `"<valid-hash>" -ne $null` is **always `$true`**
- **Every** module reports "Hash mismatch" and gets re-copied and re-signed

There is no warning logged that the `.unsigned` file was missing — the failure is completely silent.

### Step 5: `DeployModules = $true` Default Amplifies the Problem

**File:** `_Modules\Deploy-Handler\Deploy-Handler.psm1`, line 1062

```powershell
[bool]$DeployModules = $true,
```

Every `Deploy-Files` call triggers a full CommonModules deployment, even when deploying a single unrelated script. This means the hash-mismatch check runs for all ~30 modules on every deployment, and when `.unsigned` files are missing, **all** of them are re-signed unnecessarily.

---

## Event Sequence

```
  Some script calls Install-OurPshApp("SomeApp")
  │
  ├─ Install-OurPshApp auto-installs CommonModules first (Step 3)
  │   └─ Install-OurPshAppSlave("CommonModules")
  │       └─ Start-Robocopy -Recurse -NoPurge (Step 2)
  │           └─ BUG: /MIR used despite -NoPurge (Step 1)
  │               └─ All .unsigned files DELETED from C:\opt\DedgePshApps\CommonModules
  │                  (network share source has no .unsigned files)
  │
  ├─ Later: User runs Deploy-Files for any script
  │   └─ DeployModules = $true (default) (Step 5)
  │       └─ Deploy-FilesInternal for _Modules
  │           └─ Copy-FilesToStaging checks each module:
  │               └─ Get-FileHash on .unsigned → returns $null (Step 4)
  │                   └─ "valid-hash" -ne $null → TRUE
  │                       └─ "Hash mismatch" for ALL modules
  │                           └─ All ~30 modules re-copied and re-signed (5+ min)
```

---

## Fixes

### Fix 1: `Start-RoboCopy` — Use `/E` Instead of `/MIR` When `-NoPurge`

**File:** `_Modules\GlobalFunctions\GlobalFunctions.psm1`, lines 4927–4929

**Before:**
```powershell
if ($Recurse) {
    $command += " /MIR /R:3 /W:1"
}
```

**After:**
```powershell
if ($Recurse) {
    if ($NoPurge) {
        $command += " /E /R:3 /W:1"
    }
    else {
        $command += " /MIR /R:3 /W:1"
    }
}
```

**Why:** `/E` copies subdirectories (including empty ones) without purging destination files. `/MIR` = `/E` + `/PURGE`. When the caller explicitly requests `-NoPurge`, using `/E` respects that intent.

### Fix 2: Add `*.unsigned` to Default Excludes in `Start-RoboCopy`

**File:** `_Modules\GlobalFunctions\GlobalFunctions.psm1`, lines 4864–4867

**Before:**
```powershell
$excludeString = ""
$Exclude += "_QuickDeploy*.ps1"
$Exclude += "_deployAll.ps1"
$Exclude += "_deploy.ps1"
```

**After:**
```powershell
$excludeString = ""
$Exclude += "_QuickDeploy*.ps1"
$Exclude += "_deployAll.ps1"
$Exclude += "_deploy.ps1"
$Exclude += "*.unsigned"
```

**Why:** Defense in depth. Even if `/MIR` is used elsewhere, `.unsigned` tracking files are excluded from robocopy's file selection entirely, so they won't be purged from the destination.

### Fix 3: Handle Missing `.unsigned` Files Explicitly in Deploy-Handler

**File:** `_Modules\Deploy-Handler\Deploy-Handler.psm1`, lines 552–565

**Before:**
```powershell
if (-not $SkipSign) {
    # Get hash of new file
    try {
        $newFileHash = Get-FileHash -Path $FilePath -Algorithm SHA256 -ErrorAction SilentlyContinue
        $newFileHash = $newFileHash.Hash
        # Get hash of unsigned file
        $unsignedHash = Get-FileHash -Path $unsignedFile -Algorithm SHA256 -ErrorAction SilentlyContinue
        $unsignedHash = $unsignedHash.Hash
    }
    catch {
        Write-LogMessage "Error getting hash of $stagingFile - $($_.Exception.Message)" -Level WARN
        $newFileHash = 1
        $unsignedHash = 2
    }
```

**After:**
```powershell
if (-not $SkipSign) {
    if (-not (Test-Path $unsignedFile -PathType Leaf)) {
        Write-LogMessage "No .unsigned tracking file for: $($fileName) (first deploy or tracking lost)" -Level WARN
        Copy-SignAndBackupFile -FilePath $FilePath -StagingFile $stagingFile -UnsignedFile $unsignedFile -FileName $fileName -FromFolder $FromFolder -AppName $AppName -SkipSign $SkipSign -CurrentDeployFileInfo $CurrentDeployFileInfo
        return $stagingFile
    }
    # Get hash of new file
    try {
        $newFileHash = Get-FileHash -Path $FilePath -Algorithm SHA256 -ErrorAction SilentlyContinue
        $newFileHash = $newFileHash.Hash
        # Get hash of unsigned file
        $unsignedHash = Get-FileHash -Path $unsignedFile -Algorithm SHA256 -ErrorAction SilentlyContinue
        $unsignedHash = $unsignedHash.Hash
    }
    catch {
        Write-LogMessage "Error getting hash of $stagingFile - $($_.Exception.Message)" -Level WARN
        $newFileHash = 1
        $unsignedHash = 2
    }
```

**Why:** Makes the missing-tracking-file scenario visible in logs (WARN level) instead of silently reporting a false "Hash mismatch" at INFO level. This makes it immediately obvious when `.unsigned` files have been wiped, distinguishing it from a genuine source change.

### Fix 4: Add `-DeployModules:$false` Where Module Deployment Is Redundant

When `Build-And-Publish.ps1` (e.g. DedgeAuth) calls multiple `_deploy.ps1` scripts in sequence, only the **first** needs `DeployModules = $true`. Subsequent calls redundantly re-deploy CommonModules. Adding `-DeployModules:$false` to subsequent `Deploy-Files` calls in those `_deploy.ps1` scripts reduces deployment time and avoids re-triggering the hash-mismatch check.

This fix is a performance optimization and does not affect the core bug.

---

## Fix Priority and Status

| Fix | Impact | Risk | Priority | Status |
|-----|--------|------|----------|--------|
| Fix 1: `/E` vs `/MIR` | Eliminates the root cause | Low — only changes behavior when `-NoPurge` is set | **Critical** | **Applied** |
| Fix 2: `*.unsigned` exclude | Defense in depth | Very low — adds one more exclude pattern | **High** | **Applied** |
| Fix 3: Explicit missing-file handling | Improves diagnostics | Low — no behavior change, adds warning | **High** | **Applied** |
| Fix 4: `-DeployModules:$false` | Reduces deploy time | Very low — opt-in per script | **Medium** | **Applied** |

---

## How to Verify the Fix

1. After applying Fix 1 and Fix 2, run a deployment: `Deploy-Files -FromFolder <any script>`
2. Verify that `.unsigned` files exist in `C:\opt\DedgePshApps\CommonModules\<module>\`:
   ```powershell
   Get-ChildItem -Path "$env:OptPath\DedgePshApps\CommonModules" -Recurse -Filter "*.unsigned" | Select-Object FullName
   ```
3. Run `Install-OurPshApp -AppName "CommonModules"` (simulates the triggering event)
4. Verify `.unsigned` files still exist after step 3
5. Run another deployment and confirm modules show "Executable file is unchanged. Skipping:" instead of "Hash mismatch"

---

## Files Involved

| File | Role | Changed |
|------|------|---------|
| `_Modules\GlobalFunctions\GlobalFunctions.psm1` | `Start-RoboCopy` function (bug location) | Fix 1, Fix 2 |
| `_Modules\SoftwareUtils\SoftwareUtils.psm1` | `Install-OurPshAppSlave` / `Install-OurPshApp` (trigger) | — |
| `_Modules\Deploy-Handler\Deploy-Handler.psm1` | `Copy-FilesToStaging` (hash comparison) | Fix 3 |
| `DevTools\WebSites\DedgeAuth\DedgeAuth-DatabaseSetup\_deploy.ps1` | Deploy to DB servers | Fix 4 |
| `DevTools\WebSites\IIS-DeployApp\_deploy.ps1` | Deploy to app servers | Fix 4 |
| `C:\opt\src\DedgeAuth\Build-And-Publish.ps1` | Orchestrates deploy scripts | Fix 4 |
