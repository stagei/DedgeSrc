# Cursor Rules Library — Symlinks and UNC Path Setup

This document explains how to use symbolic links (symlinks) so that project rules point to this central CursorRulesLibrary, optionally via a UNC path on a file server. This eliminates rule duplication across repositories.

---

## Overview

Instead of copying rules into each project's `.cursor/rules/`, you create **symlinks** that point to files in this library. When Cursor reads a rule file, it follows the symlink to the actual content.

| Approach | Location | Pros | Cons |
|----------|----------|------|------|
| **Local symlinks** | Target: `C:\opt\src\CursorRulesLibrary\Library\...` | Works offline | Requires CursorRulesLibrary cloned locally |
| **UNC symlinks** | Target: `\\server\share\CursorRulesLibrary\...` | Single source on server, no local clone needed | Requires network access |

---

## Prerequisites

### Windows

1. **Symlink support**: Administrator rights **or** [Developer Mode](https://learn.microsoft.com/en-us/windows/apps/get-started/enable-your-device-for-development) enabled.
2. **Git**: `core.symlinks` should be `true`:
   ```powershell
   git config --global core.symlinks true
   ```
3. **UNC (if used)**: Read access to the network share where CursorRulesLibrary is published.

---

## Library Structure

```
CursorRulesLibrary/Library/
├── Shared/           # (optional) Cross-project rules — create this folder for rules like command-rag-status.mdc
├── Agent/            # command-autocur, no-remote-execution
├── PowerShell/       # powershell-standards
├── Server/           # server-app-layout
├── Db2/
├── ...
└── SYMLINKS-AND-UNC-SETUP.md   (this file)
```

---

## Creating Symlinks

### Option A: Local Path (CursorRulesLibrary in same repo tree)

If CursorRulesLibrary is at `C:\opt\src\CursorRulesLibrary` and your project is at `C:\opt\src\GetPeppolDirectory`:

```powershell
$projectRoot = "C:\opt\src\GetPeppolDirectory"
$libraryRoot = "C:\opt\src\CursorRulesLibrary\Library"

# Single rule
New-Item -ItemType SymbolicLink -Force `
  -Path "$projectRoot\.cursor\rules\command-rag-status.mdc" `
  -Target "$libraryRoot\Shared\command-rag-status.mdc"

# Multiple rules from Shared folder
Get-ChildItem "$libraryRoot\Shared\*.mdc" | ForEach-Object {
  New-Item -ItemType SymbolicLink -Force `
    -Path "$projectRoot\.cursor\rules\$($_.Name)" `
    -Target $_.FullName
}
```

### Option B: UNC Path (Library on server)

Publish CursorRulesLibrary to a server share, e.g. `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\CursorRulesLibrary\` or `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\CursorRulesLibrary\`.

```powershell
$projectRoot = "C:\opt\src\GetPeppolDirectory"
$libraryUnc  = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\CursorRulesLibrary\Library"

New-Item -ItemType SymbolicLink -Force `
  -Path "$projectRoot\.cursor\rules\command-rag-status.mdc" `
  -Target "$libraryUnc\Shared\command-rag-status.mdc"
```

### Option C: Directory Junction (Windows, no admin)

If symlinks fail, use a **directory junction** (directory only):

```powershell
cmd /c mklink /J "$projectRoot\.cursor\rules\Shared" "$libraryRoot\Shared"
```

Then rules would live in `.cursor\rules\Shared\command-rag-status.mdc`. Cursor treats it as a normal subfolder. Junctions don't work for individual files.

---

## Git Behavior

- **Symlinks are tracked by Git.** Git stores the link target path.
- On `git clone` or `git checkout`, Git recreates the symlink.
- If the target path doesn't exist (e.g. no network, wrong machine), the symlink is **broken** — the rule file has no content and Cursor won't load it.

---

## Publishing to Server (UNC Setup)

1. **Copy or sync** this Library to a server share:
   ```powershell
   robocopy C:\opt\src\CursorRulesLibrary\Library C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\CursorRulesLibrary\Library /MIR
   ```

2. **Create symlinks** in each project pointing to the UNC path.

3. **Commit the symlinks** to each project's repo. Git stores the UNC target.

4. **Schedule or script** periodic sync from source (e.g. when CursorRulesLibrary is updated) to the server share.

---

## Pros and Cons of UNC Symlinks

| Pros | Cons |
|------|------|
| Single source of truth on server | Requires network access; offline = no rules |
| No need to clone CursorRulesLibrary locally | UNC is Windows-specific |
| Updates on server = everyone gets them immediately | Some environments restrict symlinks or UNC |
| Central control and auditing | Small read latency over network |

---

## Fallback: Sync Script (No Symlinks)

If symlinks or UNC are not viable, use a **sync script** that copies rules from this library into each project:

```powershell
# Sync-RulesFromLibrary.ps1
$libraryRoot = "C:\opt\src\CursorRulesLibrary\Library"
$projects = Get-ChildItem "C:\opt\src" -Directory | Where-Object { Test-Path "$($_.FullName)\.cursor\rules" }

foreach ($p in $projects) {
  Copy-Item "$libraryRoot\Shared\*.mdc" "$($p.FullName)\.cursor\rules\" -Force
}
```

Run after updating the library. Projects get real files; no symlinks. Works offline.

---

## Checklist for New Projects

1. Ensure `.cursor\rules\` exists in the project.
2. Create symlinks (or copy files) from `Library\Shared\` and other needed folders.
3. Test: Open project in Cursor, type `/rag` (or another command) — rule should apply.
4. Commit symlinks to Git if using shared setup.

---

## Related

- **Rules organization**: See `TRANSFER-TO-LIBRARY.md` (if present) for moving rules into the library.
- **Command migration**: We replaced `--rag` → `/rag`, `--autocur` → `/autocur`, etc. Use slash commands in rules.
