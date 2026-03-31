---
name: git-smart-commit
description: >-
  Analyze all uncommitted changes, group them by related module/feature/area,
  create separate git commits with AI-generated messages per group, then push.
  Use when the user types /commit, /smartcommit, asks to "commit everything",
  "commit and push", or wants organized atomic commits from a batch of changes.
---

# Git Smart Commit

Automatically analyze all uncommitted changes, group them into logical atomic commits by relatedness, generate descriptive commit messages, and push.

## Trigger

Activate when the user asks to commit all changes, types `/commit` or `/smartcommit`, or asks for organized/grouped commits.

## Workflow

### Step 1: Gather State

Run these in parallel:

```
git status --porcelain
git diff --stat
git diff --cached --stat
git log --oneline -5
```

Collect:
- **Unstaged modified files** (` M`, `MM`)
- **Staged files** (`A `, `M `, `D `, etc.)
- **Untracked files** (`??`)
- **Recent commit style** (from `git log`)

If there are no changes at all, tell the user and stop.

### Step 2: Read Changed Files

For each changed file, read just enough to understand what changed:

```
git diff -- <file>          # unstaged changes
git diff --cached -- <file> # staged changes
```

For untracked files, read the file content directly.

### Step 3: Group Changes

Analyze all changes and group them into **logical commits**. Group by:

1. **Same feature/purpose** — files that implement the same feature together (e.g., a controller + its model + its migration)
2. **Same module/project** — changes within the same project folder or namespace
3. **Same type of change** — e.g., all dependency updates, all config changes, all formatting fixes
4. **Standalone files** — files that don't relate to any other change get their own commit

Grouping priority (highest first):
- Files changed for the same functional reason (feature, bugfix, refactor)
- Files in the same project/module that were modified together
- Infrastructure/config changes (`.csproj`, `appsettings.json`, `.ps1` scripts)
- Documentation changes

Each group becomes one commit. Aim for **2–8 commits** for a typical session. Don't over-split (one file per commit is too granular unless truly unrelated). Don't under-split (one giant commit defeats the purpose).

### Step 4: Commit Loop

For each group, in dependency order (foundational changes first):

1. **Stage the files**:
   ```
   git add <file1> <file2> ...
   ```

2. **Generate the commit message** from the actual diff content:
   - First `-m`: Short summary (≤50 chars) describing *what* changed — use imperative mood ("Add", "Fix", "Update", "Refactor", "Remove")
   - Additional `-m` flags: One per notable change, prefixed with `- `
   - Describe what was changed, not why you are committing

3. **Commit** using PowerShell-safe format:
   ```powershell
   git commit -m "Short summary of change" -m "- Detail 1" -m "- Detail 2"
   ```

4. **Verify** the commit succeeded (check exit code). If it fails due to a pre-commit hook modifying files, stage the modified files and create a NEW commit (never amend).

5. **Repeat** for the next group.

### Step 5: Verify All Committed

Run `git status` after the loop. If any files remain uncommitted:
- Determine if they were missed or intentionally skipped
- If missed: create an additional commit for them
- If intentionally skipped (e.g., `.env`, secrets, build artifacts): tell the user

Loop back to Step 4 if needed until `git status` shows a clean working tree (or only intentionally-ignored files remain).

### Step 6: Push

Once all commits are made:

```
git push
```

If the push fails because the remote has new commits, pull with rebase first:

```
git pull --rebase
git push
```

Report the final result: number of commits created, summary of each, and push status.

## Commit Message Rules

- **No `--trailer`**, no `Co-authored-by`, no AI attribution
- **No heredoc syntax** — PowerShell does not support `<<'EOF'`
- **Multiple `-m` flags** for multi-line messages
- **Imperative mood** for the summary: "Add feature" not "Added feature"
- **Focus on changes**: describe what was changed in the codebase
- First `-m` ≤ 50 chars, body `-m` entries ≤ 72 chars each
- Follow the existing commit style visible in `git log`

## Grouping Examples

### Example A: Feature + Config

Files changed:
- `src/Services/AuthService.cs` (new method)
- `src/Api/Controllers/AuthController.cs` (new endpoint)
- `src/Core/Models/LoginToken.cs` (new property)
- `appsettings.json` (new config key)
- `README.md` (updated docs)

Groups:
1. **Commit 1**: `AuthService.cs` + `AuthController.cs` + `LoginToken.cs` + `appsettings.json` → "Add magic link authentication" with details
2. **Commit 2**: `README.md` → "Update README with magic link documentation"

### Example B: Multi-area changes

Files changed:
- `Build-And-Publish.ps1` (script fix)
- `src/Data/Migrations/20260318_AddColumn.cs` (new migration)
- `src/Core/Models/User.cs` (new property)
- `package.json` (dependency bump)
- `src/Api/wwwroot/css/site.css` (style tweak)

Groups:
1. **Commit 1**: Migration + User.cs → "Add preferred_language column to users"
2. **Commit 2**: `site.css` → "Fix header alignment in mobile view"
3. **Commit 3**: `Build-And-Publish.ps1` → "Fix version bump path in build script"
4. **Commit 4**: `package.json` → "Update npm dependencies"

## Edge Cases

- **Secrets/credentials**: Never commit `.env`, `credentials.json`, PAT files, or similar. Warn the user.
- **Binary files**: Include them in commits but don't try to diff them. Mention them in the commit message.
- **Merge conflicts**: If encountered, stop and tell the user.
- **Empty diff**: If `git status` shows changes but `git diff` is empty, the files may be staged already — handle accordingly.
- **Single change**: If there's only one logical group, make one commit. Don't force multiple commits.

## Output

After completion, display a summary:

```
Committed and pushed N commits:
  1. abc1234 — Add magic link authentication
  2. def5678 — Update README with magic link docs
  3. ghi9012 — Fix build script version path

Branch: main → origin/main (pushed)
```
