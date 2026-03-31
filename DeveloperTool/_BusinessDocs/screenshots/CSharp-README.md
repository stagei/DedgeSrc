# C# application screenshots (from `all-projects.json`)

Screenshots are generated only for **.NET / C# web hosts** that appear in `../all-projects.json` as product entries. **PowerShell** suites (GitHist, CursorRulesLibrary, CodingTools, VcHelpExport, Pwsh2CSharp, all `DedgePsh-*`) are **not** captured here.

## Script

Run from repo root or any folder (uses absolute paths):

```powershell
pwsh.exe -NoProfile -File "C:\opt\src\DedgeSrc\DeveloperTool\Capture-CSharpAppScreenshots.ps1"
```

Optional:

- `-SkipBuild` — skip `dotnet build` (faster if already built).
- `-Apps @('AutoDocJson','DedgeAuth')` — only these keys from the internal manifest.

Output folder: `_BusinessDocs/screenshots/CSharp/<AppKey>/` (next to this file: `CSharp/`).

Each run writes `dotnet-run.stdout.log` / `dotnet-run.stderr.log` per app for troubleshooting.

## Included web apps (C#)

| Key | Source project | Typical URLs captured |
|-----|----------------|----------------------|
| AiDoc.WebNew | `AiDoc.WebNew.csproj` | `/AiDocNew/scalar/v1`, `/AiDocNew/` |
| CursorDb2McpServer | `CursorDb2McpServer.csproj` | `/` |
| AutoDocJson | `AutoDocJson.Web.csproj` | `/health`, `/`, `/docs/` |
| SystemAnalyzer | `SystemAnalyzer.Web.csproj` | `/scalar/v1`, `/` |
| ServerMonitor | `ServerMonitorDashboard.csproj` | `/`, `/health` |
| GenericLogHandler | `GenericLogHandler.WebApi.csproj` | `/scalar/v1`, `/health` |
| SqlMermaidErdTools-Web | `ProductStore.csproj` | `/`, `/api/products` |
| SqlMermaidErdTools-REST | `SqlMermaidApi.csproj` | `/swagger`, `/health` |
| DedgeAuth | `FkAuth.Api.csproj` | `/scalar/v1`, `/health` |

Ports are fixed in the script (127.0.0.1) so runs do not clash with your normal `launchSettings.json` profiles.

## Explicitly excluded (from `all-projects.json`)

| Reason | Examples |
|--------|----------|
| PowerShell-only | GitHist, CursorRulesLibrary, CodingTools, VcHelpExport, Pwsh2CSharp, `DedgePsh-*` |
| Library / no HTTP host | DedgeCommon (`FkCommon`), SqlMmdConverter |
| Python | Pdf2Markdown, SiteGrabber |
| PHP / static HTML | OnePager, LillestromOsteopati sites |
| Markdown-only | DevDocs |

## Desktop C# (future)

MouseJiggler, RemoteConnect, and DbExplorer (WPF/WinForms) are **not** automated here: they need a visible UI session or a packaged build path. Capture those manually or extend the script to start a published `.exe` and use desktop capture tooling.

## Requirements

- `dotnet` SDK on PATH  
- Microsoft Edge (x86 or x64) for `--headless=new --screenshot=...`  
- `GlobalFunctions` module optional (falls back to `Write-Host`)  
- Database-backed apps (e.g. FkAuth, GenericLogHandler) must be able to start locally (connection strings / local DB); otherwise the run logs a start timeout and continues.
