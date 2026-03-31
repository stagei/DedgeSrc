# AdEntra-GroupTools

PowerShell tools for Active Directory and Entra ID group inspection and JSON export.

## Scripts

| Script | Purpose |
|--------|---------|
| `Export-AdEntraGroupsToJson.ps1` | Export all groups with metadata; **containment** section lists `roots` and `edges` (parent→child) to preserve nesting. |
| `Get-AdGroupMembershipSummary.ps1` | Quick summary of direct members (users vs nested groups) for one AD group. |
| `Get-EntraGroupMembershipSummary.ps1` | Same for one Entra group via Microsoft Graph (requires `Connect-MgGraph`). |

## Viewer (`AdEntra-Groups-Viewer.html`)

Open the HTML file in a browser. Use **Choose JSON file** or **drag-and-drop** your `AdEntra-Groups-export-*.json` (required for `file://` — browsers block silent disk reads). Search (press `/` to focus), filter by scope/category, paginate the table.

The **right panel** has two tabs: **Details** (attributes, contains, member-of with links) and **Tree explorer** — **name prefix tree** (underscore naming, e.g. `AVD_FKA_Stab_IT_IogT` → `…_Samhandling`) and **AD nested groups** from `memberGroupGuids`. Tree nodes are clickable to select the group.

If you serve the folder over HTTP (same directory as the JSON), you can open  
`AdEntra-Groups-Viewer.html?json=AdEntra-Groups-export-20260320-150113.json` to load that file automatically.

## Export JSON model

- **metadata**: export time, computer, `source` mode.
- **activeDirectory** (when `AdOnly` or `Both`):
  - **metadata**: counts, domain DNS, warnings.
  - **groups**: flat list with `memberGroupGuids` and `memberOfGroupGuids`.
  - **containment.roots**: group GUIDs that are not nested inside another exported group.
  - **containment.edges**: `{ parentObjectGuid, childObjectGuid }` for direct “group contains group” links.
- **entra**: same shape with `id` instead of `objectGuid` when Graph export succeeds; otherwise `{ skipped, reason }`.

## Parameters (export)

- `-Source AdOnly` (default), `EntraOnly`, or `Both`
- `-OutputPath` — optional; default under `%OptPath%\data\<scriptFolder>\`
- `-SearchBase` — limit AD search to an OU
- `-SkipServerCheck` — allow running off-server (not recommended)

**AD data source:** Uses the `ActiveDirectory` module when available (RSAT). If that module is missing (common on some servers), the script falls back to `System.DirectoryServices` LDAP against the domain naming context.

## Deploy

```powershell
pwsh.exe -NoProfile -File .\_deploy.ps1
```

## Remote run (Cursor-ServerOrchestrator)

```powershell
. "C:\opt\src\DedgePsh\DevTools\CodingTools\Cursor-ServerOrchestrator\_helpers\_CursorAgent.ps1"
Invoke-ServerCommand -ServerName 't-no1fkmmig-db' `
  -Command '%OptPath%\DedgePshApps\AdEntra-GroupTools\Export-AdEntraGroupsToJson.ps1' `
  -Project 'ad-group-export' `
  -Timeout 7200
```

Output path is logged and appears under `\\<server>\opt\data\AdEntra-GroupTools\` by default. After each run, the same file is **copied to the script folder** (`DedgePshApps\AdEntra-GroupTools\` on the server, or the repo folder when run locally) so you can open it beside the `.ps1` files.
