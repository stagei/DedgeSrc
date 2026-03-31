**User command (global):** `%USERPROFILE%\.cursor\commands\sysdocs.md` — Cursor merges this with any project-level `sysdocs.md`. The project version in DedgePsh has FK-specific DocView paths and examples.

> **Canonical project copy (Dedge):** `C:\opt\src\DedgePsh\.cursor\commands\sysdocs.md`

---

Publish project documentation to a documentation web portal (e.g. DocView) under `System/<Tech>/`.

## Subcommands

| Usage | Description |
|-------|-------------|
| `/sysdocs help` | Explain what this command does and show all subcommands |
| `/sysdocs @path/to/project` | Create or overwrite README.md from scratch and publish |
| `/sysdocs update @path/to/project` | Detect changes, update existing README.md, republish |
| `/sysdocs publish @path/to/project` | Republish existing README.md to DocView without editing |

Default (no subcommand): **create** — full generation from scratch.

---

## Subcommand: `help`

When the user types `/sysdocs help`, respond with a concise summary — do NOT read the full rule file back to the user. Instead, present this:

```
/sysdocs — System Documentation Publisher

Generates comprehensive README.md documentation for any project and publishes
it to a documentation web portal (e.g. DocView).

Subcommands:
  /sysdocs @project           Create README from scratch, publish
  /sysdocs update @project    Detect code changes, update existing README, republish
  /sysdocs publish @project   Republish existing README without editing
  /sysdocs help               Show this help

What it does:
  1. Reads all scripts, configs, and code in the project folder
  2. Discovers git contributors for the author list
  3. Auto-detects technology (PowerShell, C#, Cobol, Python, Node.js)
  4. Generates a README.md with:
     - Parameter tables, usage examples, dependency lists
     - Mermaid diagrams (architecture, sequence, flowcharts)
     - File structure, troubleshooting, configuration docs
  5. Scans project files for .mdc rule references
  6. Documents what each referenced rule does (inline summary, NOT copying .mdc files)
  7. Refreshes the doc portal cache
  8. Returns clickable URLs

The "update" subcommand is incremental — it reads the existing README,
compares it to the current code, and only modifies sections that are
outdated (new params, new functions, changed files, etc.).

Examples:
  /sysdocs @DevTools/CodingTools/Cursor-AgentCLI
  /sysdocs update @DevTools/CodingTools/Cursor-AgentCLI
  /sysdocs publish @_Modules/GlobalFunctions
```

---

## Subcommand: `update`

Automatically detect code changes since the README was last written, update the documentation in-place, and republish.

### Update workflow

1. **Read the existing README.md** in the project folder. If none exists, fall back to the `create` workflow.

2. **Read all source files** in the project folder (scripts, configs, modules, tests). Build a current picture of:
   - All parameters (from `param()` blocks and comment-based help)
   - All functions (public and internal)
   - All imports/dependencies
   - All config files and their structure
   - File list and line counts

3. **Diff against the README.** Compare the current code state to what the README documents:
   - **New parameters** not mentioned in the README
   - **New functions** not documented
   - **New files** (scripts, examples, configs) not in the file structure section
   - **Changed defaults** or types that no longer match
   - **New features** (e.g. new switches, new output properties, new MCP categories)
   - **Removed items** still mentioned in README

4. **Update the README in-place.** For each detected change:
   - Add new parameters to the parameter tables
   - Add new functions to the internal functions table (if one exists)
   - Update file structure listings
   - Add or update Mermaid diagrams if the flow changed significantly
   - Update the `**Updated:**` date in the header to today
   - Add new usage examples for new features
   - Update line counts, file sizes, or other metrics
   - **Preserve** all existing sections, diagrams, and prose that are still accurate
   - **Do NOT** rewrite sections that haven't changed

5. **Republish** (steps 3-8 from the create workflow below).

6. **Report changes.** In addition to the standard report, list what was updated:
   ```
   Updated README.md for Cursor-AgentCLI:
   - Added 2 new parameters (-SessionId, -Continue) to parameter tables
   - Added Save-SessionResult to internal functions table
   - Updated sequence diagram with session resume flow
   - Added "Quick Reference" section
   - Updated file structure (955 → 980 lines)
   
   Published: Cursor-AgentCLI - Cursor Agent CLI PowerShell Wrapper.md
   DocView: [Open in DocView](<url>)
   ```

### Update detection heuristics

For **PowerShell scripts** (`.ps1`):
- Parse `param()` block for parameter names, types, defaults, and ValidateSet values
- Parse `function` declarations for internal/helper functions
- Check `Import-Module` statements for dependencies
- Check comment-based help (`.SYNOPSIS`, `.PARAMETER`, `.EXAMPLE`) for new entries

For **C# projects** (`.cs`, `.csproj`):
- Check controller/endpoint methods for new API routes
- Check `Program.cs` / `Startup.cs` for middleware changes
- Check `.csproj` for new package references

For **config files** (`.json`, `.xml`):
- Compare structure against what README documents

### When NOT to update

- If the README is missing entirely → use `create` instead
- If the only changes are whitespace/formatting → skip, report "no significant changes"
- If the README has no recognizable structure (no headings, no tables) → use `create` to regenerate

---

## Subcommand: `publish`

Republish an existing README.md to the doc portal without editing it.

1. Read the README.md from the project folder
2. Skip steps 1-2 of the create workflow (no generation or editing)
3. Execute steps 3-8 (detect tech, compute path, copy, refresh, URL, report)

---

## Create workflow (default)

### 1. Identify the target project

- If the user specifies a path or project name, use that.
- If no path is given, use the current workspace.
- If the user says "publish all DevTools docs" or similar, iterate over all subprojects under `<git-root>\DevTools\` that contain a `README.md`.

### 2. Find or create documentation

- Look for `README.md` (or other `.md` files) in the project root.
- If no markdown documentation exists, **generate a `README.md`** by:
  1. Reading the project's scripts, code, and config files to understand what it does.
  2. Writing a comprehensive `README.md` with this header:

     ```markdown
     # <Project Name>

     **Authors:** <list all contributors>
     **Created:** <YYYY-MM-DD>
     **Updated:** <YYYY-MM-DD>
     **Technology:** <technology name>

     ---

     ## Overview

     <What this project does>

     ---
     ```

     **Author discovery:** Run `git log --format="%aN <%aE>" -- "<project-folder-relative-path>/" | sort -u` to get all unique contributors to the project folder. List all authors, not just the current user. Match emails against the team config to get full names; for unrecognized emails use the git display name as-is.

  3. Including sections for: Overview, Usage, Parameters, Configuration, Dependencies, and any relevant details.
  4. Include **Mermaid diagrams** to describe the high-level flow of the project. Use `flowchart`, `sequenceDiagram`, or `graph` as appropriate. Every generated README should have at least one Mermaid diagram showing the main workflow or architecture. Place diagrams in a `## How It Works` or `## Architecture` section near the top.
  5. Saving it in the project folder as `README.md`.

### 2a. Document referenced rules (inline — NEVER copy .mdc files)

Scan all project files for `.mdc` rule references. For each referenced rule:
1. Read the `.mdc` file to understand what it does
2. Write a **short inline summary** (1–3 sentences) in the README explaining the rule's purpose and effect
3. **Do NOT copy** the `.mdc` file to DocView or any doc portal
4. If the project generates or runs **more than one script or command**, include a **Mermaid diagram** showing the execution flow, script relationships, or command sequence

`.mdc` files are Cursor IDE internal configuration — they are NOT documentation artifacts. They contain agent instructions that are meaningless outside Cursor and clutter the doc portal. The README should explain what each rule does in plain language so readers understand the project's AI behavior without needing Cursor.

Example of correct inline documentation:
```markdown
## Related Cursor Rules
| Rule | Purpose |
|------|---------|
| `team-and-sms.mdc` | Defines team members, SMS numbers, and auto-notification for long operations |
| `powershell-standards.mdc` | Enforces `Write-LogMessage`, `Deploy-Handler` patterns, switch/bool conventions |
```

### 3. Auto-detect technology

Use `Cursor-Handler` to scan the project folder:

```powershell
Import-Module Cursor-Handler -Force
$tech = Get-ProjectTech -ProjectPath $projectRoot
```

Returns: `PowerShell`, `CSharp`, `Cobol`, `Python`, `NodeJS`, or `Unknown`. If `Unknown`, ask the user.

### 4. Compute the doc portal target path

**Base:** The documentation share root under `System\<Tech>\`.

> **FK DocView base:** `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\Webs\DocViewWeb\Content\System\<Tech>\`

**Path rules:**

- **Standalone projects** (e.g. `C:\opt\src\DedgeAuth`):
  `System\CSharp\DedgeAuth\DedgeAuth - <Title from # heading>.md`

- **DevTools subprojects** (e.g. `<git-root>\DevTools\DatabaseTools\Db2-ShadowDatabase`):
  Preserve the DevTools hierarchy:
  `System\PowerShell\<RepoName>\DevTools\DatabaseTools\Db2-ShadowDatabase - <Title>.md`

- **Modules** (e.g. `<git-root>\_Modules\GlobalFunctions`):
  `System\PowerShell\<RepoName>\_Modules\GlobalFunctions - <Title>.md`

**Filename convention:** `<ProjectFolderName> - <Descriptive Title>.md`
- The descriptive title comes from the first `# heading` in the markdown.
- If no heading, generate one from the project folder name.
- Example: `Db2-ShadowDatabase - Shadow Database Pipeline.md`

### 5-7. Publish to DocView (copy, refresh cache, generate URL)

Use `Cursor-Handler` for the full publish pipeline:

```powershell
Import-Module Cursor-Handler -Force
$result = Publish-ToDocView -SourceFile $sourceFile -Tech $tech `
    -RelativePath $relativePath -DescriptiveTitle $descriptiveFilename
# Returns: $result.DocViewUrl, $result.TargetPath
```

Or use the combined pipeline that handles steps 2a + 3 + 5-7 in one call:

```powershell
Import-Module Cursor-Handler -Force
$result = Publish-CursorSysDocs -SourceFile $sourceFile -ProjectRoot $projectRoot `
    -GitRoot $gitRoot -RelativePath $relativePath -DescriptiveTitle $descriptiveFilename
# Returns: $result.docViewUrl, $result.tech, $result.targetPath
```

> **FK DocView share:** `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\Webs\DocViewWeb\Content\`
> **FK DocView API:** `http://dedge-server/DocView/api/document/refresh`

### 8. Report to user

Summarize what was published. Include the portal URL as a **clickable markdown link**:

- Source file path
- Target UNC path
- **Portal URL** — display as `[Open in DocView](<url>)`
- Technology detected
- Whether README.md was newly generated, updated, or republished as-is
- Cache refresh result
- If `update`: list of specific changes made to the README

Example output:
```
Published: Cursor-ServerOrchestrator - Remote Command Execution Framework.md
DocView: [Open in DocView](http://<app-server>/DocView/#System/PowerShell/...)
```

---

## Prohibited Patterns

### NEVER copy .mdc files to DocView

`.mdc` files are Cursor-internal agent configuration. They must NEVER be copied to any documentation portal. Instead, summarize what each referenced rule does in a "Related Cursor Rules" table in the README itself.

### NEVER generate intra-document anchor TOCs

Do NOT generate `### Table of Contents` sections with `[link](#anchor)` navigation inside the README. These anchors do not work reliably across markdown renderers (GitHub, DocView, etc.) and produce broken navigation. If the document needs structure, rely on the heading hierarchy itself — readers and renderers use the sidebar/outline for navigation.
