## GitChangeActivityReport

A small PowerShell tool for producing a **multi-repo “what did I change”** report based on git history.

- **Scope discovery**: finds all repos by scanning for `.git` folders under a root.
- **User matching**: filters commits by `--author` (name/email).
- **Statistics**: line additions/deletions per file, folder, repo; markdown counted separately.
- **Headlines**: tries to infer a human headline for each changed file (class name, function name, SQL object, etc.).

Tip: If you override `-Authors`, prefer **email addresses** (author display names vary across repos).

### Files
- `New-GitChangeActivityReport.ps1`: main entry point
- `New-GitChangeActivityAiSummary.ps1`: offline “AI style” narrative summary from JSON
- `Test-GitChangeActivityReportTotals.ps1`: re-count & validate totals against git
- `_deploy.ps1`: standard deploy wrapper
- `CURSOR_USAGE.md`: how to run in Cursor
