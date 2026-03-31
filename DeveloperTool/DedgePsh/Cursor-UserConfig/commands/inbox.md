**User command (global):** `%USERPROFILE%\.cursor\commands\inbox.md` — scans all sibling git repos for pending `_inbox/` reports and processes them. Works with any multi-repo layout where projects share a common source root.

---

Scan and process all pending cross-project inbox reports across every git repo under the source root.

## Step 1: Discover source root and pending reports

Dynamically find the source root (parent of the current workspace) and all git repos with `_inbox` folders:

```powershell
# Auto-detect source root from current workspace
$sourceRoot = (Get-Item (git rev-parse --show-toplevel)).Parent.FullName

$repos = Get-ChildItem -Path $sourceRoot -Directory | Where-Object { Test-Path (Join-Path $_.FullName ".git") }
$pending = foreach ($repo in $repos) {
    $inbox = Join-Path $repo.FullName "_inbox"
    if (Test-Path $inbox) {
        Get-ChildItem -Path $inbox -Filter "*.md" -File | ForEach-Object {
            [PSCustomObject]@{ Project = $repo.Name; File = $_.Name; FullPath = $_.FullName }
        }
    }
}
```

- List all `.md` files directly in `_inbox/` (exclude `implemented/` and `refused/` subfolders)
- Present a summary table to the user: **Project | File | Date | Type | Title**
- If no pending reports are found, tell the user and stop

## Step 2: Process each report

For each pending report, in order:

1. Read the full report markdown
2. Analyze whether the fix is feasible in the target project
3. **If feasible:**
   - Create a plan for the changes
   - Implement the changes
   - Commit with message: `fix(<scope>): <description> [from inbox report]`
   - Create `_inbox/implemented/` if it doesn't exist
   - Move the report file to `_inbox/implemented/`
4. **If not feasible** (needs human decision, out of scope, risky, etc.):
   - Append a `## Refused` section to the report with date and reason
   - Create `_inbox/refused/` if it doesn't exist
   - Move the report file to `_inbox/refused/`
5. **If the report affects production code:**
   - Ask the user for confirmation before implementing
   - Flag with priority and risk assessment

## Step 3: Summary

After processing all reports, present a final table:

**Project | Report | Action (Implemented/Refused) | Details**

## Rules

- Always create a plan before implementing
- Commit changes after each report is processed
- Preserve original filenames when moving to implemented/ or refused/
- Dynamic discovery only — never use a hardcoded repo list
- If a project needs to be opened in Cursor for the fix: `cursor "<project_path>"`
- The `_inbox/` folder should be version-controlled (not in `.gitignore`)

## Report format reference

Reports follow this naming convention: `_inbox/YYYYMMDD-HHMMSS_<short-slug>.md`

TYPE values in reports: `ERROR`, `CHANGE`, `MISSING`, `IMPROVEMENT`

Priority guidelines:
- `Critical` — blocks current task or breaks production
- `High` — significant bug or missing functionality
- `Medium` — improvement or non-blocking change
- `Low` — cosmetic, documentation, or minor cleanup
