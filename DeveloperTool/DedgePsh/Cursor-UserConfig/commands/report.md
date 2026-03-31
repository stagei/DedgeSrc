**User command (global):** `%USERPROFILE%\.cursor\commands\report.md` — creates cross-project change/error reports when a discovered issue belongs to a different repo. Works with any multi-repo layout where projects are siblings under a common source root.

---

Create a cross-project change/error report for an issue that belongs to another project.

## Instructions

1. **Gather context** from the current conversation or ask the user to describe the issue.

2. **Discover the source root** — find the parent directory containing sibling git repos:

   ```powershell
   # Auto-detect: walk up from current workspace until we find a folder with multiple .git children
   $sourceRoot = (Get-Item (git rev-parse --show-toplevel)).Parent.FullName
   ```

   | Layout example | Source root |
   |---|---|
   | `C:\opt\src\ProjectA`, `C:\opt\src\ProjectB` | `C:\opt\src` |
   | `D:\repos\frontend`, `D:\repos\backend` | `D:\repos` |

3. **Run the discovery script** (if available in the current workspace) to find the target project, related code, middleware pipeline, existing reports, and recent git history:

   ```powershell
   # Canonical path (Dedge): C:\opt\src\DedgePsh\DevTools\CodingTools\CrossProjectReport\Find-ReportContext.ps1
   # If the script exists in the current workspace, use it:
   $discoveryScript = Get-ChildItem -Path "<git-root>" -Recurse -Filter "Find-ReportContext.ps1" -ErrorAction SilentlyContinue | Select-Object -First 1
   if ($discoveryScript) {
       pwsh.exe -NoProfile -File $discoveryScript.FullName `
         -FilePath "<affected file or project path>" `
         -SearchTerms "<term1>,<term2>,<term3>" `
         -Url "<IIS URL if applicable>"
   }
   ```

   The script returns structured JSON with:
   - **TargetProject** — name, path, detected tech stack
   - **EntryPoints** — Program.cs, Startup.cs, .csproj, appsettings.json, main scripts
   - **SearchResults** — code locations matching the search terms with file, line, content
   - **MiddlewarePipeline** — ordered list of `app.Use*`, `app.Map*`, `builder.Services.Add*` calls (.NET only)
   - **ExistingInboxReports** — any existing `_inbox/*.md` files (to avoid duplicates)
   - **RecentCommits** — last 10 commits with hash, subject, author, time
   - **DeployTemplate** — IIS deploy config if available (SiteName, AppType, ApiPort, HealthEndpoint)

4. **If no discovery script exists**, manually identify the target project:

   ```powershell
   $repos = Get-ChildItem -Path $sourceRoot -Directory | Where-Object { Test-Path (Join-Path $_.FullName ".git") }
   # Find which repo owns the affected file
   $targetRepo = $repos | Where-Object { $affectedPath.StartsWith($_.FullName) }
   ```

5. **If an existing inbox report** covers the same issue, tell the user and ask whether to update it or create a new one.

6. **Determine ownership:**
   - If the target is the **current workspace** — fix it directly. No report needed. Tell the user.
   - If the target is a **different project** — proceed with report creation.

7. **Read the affected source files** to understand the exact code that needs changing. Focus on:
   - Entry points (Program.cs, main scripts) — especially middleware pipeline order
   - Config files (appsettings.json, *.config) — for configuration-based fixes
   - Search result lines — the code that matches the reported issue

8. **Create the report:**
   a. Create `<target_project>/_inbox/` if it doesn't exist.
   b. Write `_inbox/YYYYMMDD-HHMMSS_<slug>.md` using the report template below.
   c. Include code snippets with **file paths and line numbers**.
   d. Run `cursor "<target_project_path>"` to open the project in a new Cursor window.
   e. Summarize the report (path, type, priority, affected files) to the user.

## Discovery Script Parameters

| Parameter | Description | Example |
|---|---|---|
| `-FilePath` | File or folder inside the target project | `<source-root>\AutoDocJson\AutoDocJson.Web\Program.cs` |
| `-SearchTerms` | Comma-separated keywords to search for | `MapMcp,UseDedgeAuth,AllowAnonymous` |
| `-Url` | URL that resolves to owning project via deploy templates | `http://myserver/AutoDocJson/mcp` |
| `-SourceProject` | Override source project name (auto-detected from git) | `MyProject` |
| `-MaxResults` | Max search hits per term (default: 10) | `5` |

At least one of `-FilePath` or `-Url` is required to identify the target project.

## Report Template

```markdown
# [TYPE] Short Description

| Field | Value |
|---|---|
| Source Project | <project where discovered> |
| Target Project | <project where fix is needed> |
| Created | YYYY-MM-DD HH:mm |
| Author | <$env:USERNAME> (Cursor Agent) |
| Priority | Low / Medium / High / Critical |
| Tech Stack | <DotNet, PowerShell, NodeJs, Python, etc.> |
| IIS Site | <from deploy template if available> |

## Problem Description

<what is wrong or missing — include specific error messages or behavior observed>

## Affected Files

<include file path, line number, and relevant code snippet>

- `relative/path/to/file.ext` (line N) — description
  ```csharp
  // relevant code
  ```

## Middleware Pipeline

<show the ordered pipeline to illustrate where the issue occurs — .NET apps only>

| # | Line | Call | Note |
|---|---|---|---|
| 6 | 35 | `app.MapMcp("/mcp");` | MCP endpoint mapped here |
| 7 | 37 | `app.UseDedgeAuth();` | Auth middleware blocks MCP |

## Suggested Fix

<concrete steps or code changes — reference specific files and lines>

## Verification

<how to test the fix>

## Context

<what task triggered this discovery>

## Discovery Data

<paste key sections of JSON output for the receiving agent to use>
```

TYPE values: `ERROR`, `CHANGE`, `MISSING`, `IMPROVEMENT`
Slug: lowercase, hyphenated, max 50 chars (e.g. `fix-mcp-auth-bypass`).

## Quick Examples

```powershell
# Report from a URL (IIS app returning wrong response)
pwsh.exe -NoProfile -File "<git-root>\DevTools\CodingTools\CrossProjectReport\Find-ReportContext.ps1" `
  -Url "http://myserver/AutoDocJson/mcp" -SearchTerms "MapMcp,UseDedgeAuth"

# Report from a file path (bug in a specific source file)
pwsh.exe -NoProfile -File "<git-root>\DevTools\CodingTools\CrossProjectReport\Find-ReportContext.ps1" `
  -FilePath "<source-root>\GenericLogHandler\src\WebApi\Program.cs" -SearchTerms "health,authorize"

# Report from a project folder (general improvement)
pwsh.exe -NoProfile -File "<git-root>\DevTools\CodingTools\CrossProjectReport\Find-ReportContext.ps1" `
  -FilePath "<source-root>\DedgeAuth" -SearchTerms "ExcludePaths,MapMcp"
```

| Canonical path (Dedge) | `C:\opt\src\DedgePsh\DevTools\CodingTools\CrossProjectReport\Find-ReportContext.ps1` |
|---|---|
