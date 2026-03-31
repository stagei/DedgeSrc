# Dedge DeveloperTool — pipeline command (`/dedge-pipeline`)

**Workspace root:** `C:\opt\src\DedgeSrc\DeveloperTool` (or open any repo that contains this folder).

This command tells the agent to use the **Dedge conversion, rebranding, and documentation pipeline** documented here and in the paired rule `.cursor/rules/dedge-developer-tool-pipeline.mdc`.

---

## Subcommands

| Subcommand | Action |
|------------|--------|
| `/dedge-pipeline` or `/dedge-pipeline help` | Show this overview and point to the markdown references below. |
| `/dedge-pipeline state` | Read and summarize `PIPELINE-CONTINUATION-STATE.md` (resume checklist, open issues). |
| `/dedge-pipeline diagram` | Summarize flow using the Mermaid narratives in `Dedge-Conversion-And-Documentation-Pipeline.md` (do not paste the whole file unless asked). |
| `/dedge-pipeline convert` | Confirm `convertapps.json`, then run `pwsh.exe -NoProfile -File .\Convert-AppsToDedge.ps1` from `DeveloperTool` (use `-DryRun` only if the user asks). |
| `/dedge-pipeline screenshots` | Run or fix `Capture-CSharpAppScreenshots.ps1` for **C# web apps only**; respect `_BusinessDocs/screenshots/CSharp-README.md`. Do not screenshot PowerShell-only products from `all-projects.json`. |
| `/dedge-pipeline docs` | Follow skill `dedge-product-docs`: refresh competitor/product/master docs under `_BusinessDocs\` without blindly overwriting existing `.md` if the pipeline says skip. |

---

## Canonical paths (always use these)

| Item | Path |
|------|------|
| Copy map | `DeveloperTool\convertapps.json` |
| Product catalog | `DeveloperTool\all-projects.json` |
| Convert script | `DeveloperTool\Convert-AppsToDedge.ps1` |
| C# screenshots | `DeveloperTool\Capture-CSharpAppScreenshots.ps1` |
| Business output | `DeveloperTool\_BusinessDocs\` |
| Continuation state | `DeveloperTool\PIPELINE-CONTINUATION-STATE.md` |
| Mermaid pipeline doc | `DeveloperTool\Dedge-Conversion-And-Documentation-Pipeline.md` |

---

## One-line flow

`convertapps.json` → `Convert-AppsToDedge.ps1` → rebranded trees under `DeveloperTool\` → `_BusinessDocs\` (competitors, per-product MD, portfolio, screenshots).

---

## User skill (full autonomous doc pass)

For a full regeneration pass aligned with JSON + competitor research + business copy, use **`/dedgedocs`** (loads `%USERPROFILE%\.cursor\skills\dedge-product-docs\SKILL.md`).

---

## Logging (when running scripts on FK tooling)

If scripts support it, use `Write-LogMessage` from `GlobalFunctions` per workspace standards; the conversion script uses its own timestamped log file.
