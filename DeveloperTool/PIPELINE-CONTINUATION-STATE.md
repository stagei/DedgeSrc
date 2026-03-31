# Dedge pipeline — continuation state

**Last updated:** 2026-03-31 (session checkpoint)

Use this file when resuming work so you know what exists, what was last attempted, and what is still open.

---

## Canonical root

All conversion output, business docs, and screenshot targets live under:

`C:\opt\src\DedgeSrc\DeveloperTool\`

Original source repos under `C:\opt\src\` are **not** modified by the conversion script.

---

## What is in place (done)

| Artifact | Path | Notes |
|----------|------|--------|
| Project catalog (metadata) | `all-projects.json` | 39 logical products; lists name, category, path, stack, description |
| Copy map | `convertapps.json` | 38 `projects[]` entries: `currentPath` → `copyToPath` under `DeveloperTool` |
| Copy + rebrand script | `Convert-AppsToDedge.ps1` | Robocopy, text replace, file/dir rename, `dedge.ico` binary copy from DbExplorer |
| Business docs folder | `_BusinessDocs\` | Per-product `.md`, `competitors\*.md` + `*.json`, `Dedge-Business-Portfolio.md` (~2.6k lines) |
| DedgePsh bundle | `DedgePsh\` | CodingTools at root + `_Modules\` + `DevTools\{12 categories}\` (rebranded copies) |
| Cursor skill | `%USERPROFILE%\.cursor\skills\dedge-product-docs\SKILL.md` | Trigger: `/dedgedocs` — describes phases and paths |
| C# screenshot script | `Capture-CSharpAppScreenshots.ps1` | Headless Edge; C# web apps only; see **Open issues** |
| Screenshot readme | `_BusinessDocs\screenshots\CSharp-README.md` | Scope: excludes PowerShell from automated C# captures |

---

## Last known conversion run (typical)

- **Script:** `Convert-AppsToDedge.ps1`
- **Result pattern:** ~38 copied, thousands of text files modified, hundreds of renames, multiple icons replaced
- **Log:** `Convert-AppsToDedge_yyyyMMdd_HHmmss.log` next to the script

Re-run any time after editing `convertapps.json`; each project target folder is **deleted and recopied** before transforms.

---

## Documentation pipeline (manual / agent)

Phases described in the Cursor skill (not all are a single executable):

1. **Convert** — `Convert-AppsToDedge.ps1`
2. **Competitors** — web research → `_BusinessDocs\competitors\{Product}-competitors.{md,json}` (skip if exists)
3. **Per-product business MD** — `_BusinessDocs\{Product}.md` (skip if exists)
4. **Master portfolio** — `Dedge-Business-Portfolio.md` (merge / expand as needed)
5. **Screenshots** — mix of browser MCP, copied assets, and `Capture-CSharpAppScreenshots.ps1`

---

## Open issues / resume here

### 1. C# headless screenshots (`Capture-CSharpAppScreenshots.ps1`)

- **Goal:** PNGs under `_BusinessDocs\screenshots\CSharp\<AppKey>\`
- **Observed:** Runs complete per-app lifecycle (dotnet logs show listening), but **PNG creation was unreliable** in testing: `Invoke-HeadlessScreenshot` uses `System.Diagnostics.ProcessStartInfo` + `ArgumentList` for Edge — verify API usage (`ArgumentList` is a `StringCollection`; `AddRange` with string array may need fixing, or use `Start-Process -ArgumentList` array).
- **Timeouts:** `ServerMonitor` (Windows auth / environment) and `DedgeAuth` (DB) may hit **StartTimeout** if local DB or auth prerequisites are missing.
- **Next steps:** Fix Edge invocation; optionally add `Start-Process -Wait` wrapper; confirm files appear with a single-app test:  
  `pwsh -File .\Capture-CSharpAppScreenshots.ps1 -Apps @('CursorDb2McpServer')`

### 2. `Dedge-Business-Portfolio.md` vs `all-projects.json`

- Portfolio version and product counts were bumped when DedgePsh modules/DevTools were added; keep **narrative + JSON** aligned when adding entries to `convertapps.json` / `all-projects.json`.

### 3. Duplicate / “copy” folders in source `_Modules`

- Source may still contain e.g. `Deploy-Handler copy`; conversion copies as-is until renamed in source or extra rules are added.

---

## Azure DevOps (optional cross-reference)

- Story created earlier for the documentation pipeline: **WI-283784** (org: felleskjopet / project FKMeny).  
- DocView repo may contain `_azstory.json` linking that work item.

---

## Quick commands

```powershell
# Full re-convert (from DeveloperTool folder)
pwsh.exe -NoProfile -File .\Convert-AppsToDedge.ps1

# Dry run (no copy)
pwsh.exe -NoProfile -File .\Convert-AppsToDedge.ps1 -DryRun

# C# screenshots (after fixing Edge invocation if needed)
pwsh.exe -NoProfile -File .\Capture-CSharpAppScreenshots.ps1 -SkipBuild
```

---

## Related diagram doc

For a **Mermaid-first** explanation of the whole system, see:

`Dedge-Conversion-And-Documentation-Pipeline.md` (same folder as this file).

## Cursor rule and command (this folder)

| File | Purpose |
|------|---------|
| `.cursor/rules/dedge-developer-tool-pipeline.mdc` | Project rule when editing pipeline files (globs on `convertapps.json`, `_BusinessDocs`, etc.) |
| `.cursor/commands/dedge-pipeline.md` | Slash command **`/dedge-pipeline`** with subcommands (`help`, `state`, `diagram`, `convert`, `screenshots`, `docs`) |
