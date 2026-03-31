# DB2 MCP Server - Server-Side Reinstall Guide

This guide reinstalls the IIS-hosted server part of `CursorDb2McpServer` on `dedge-server`.

## Scope

- Reinstall server binaries to the staging share
- Redeploy IIS app (`Default Web Site/CursorDb2McpServer`)
- Verify MCP endpoint and tool flow

This does **not** update local Cursor client config (use `Register-McpServer.ps1` for that).

## Prerequisites

- `pwsh.exe` (PowerShell 7+)
- .NET SDK/runtime compatible with `net10.0`
- Access to:
  - `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\CursorDb2McpServer`
  - `C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\IIS-DeployApp.ps1`

Project facts:

- Target framework: `net10.0` (`CursorDb2McpServer.csproj`)
- Publish profile: `WebApp-FileSystem.pubxml`
- Staging target: `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\CursorDb2McpServer`
- IIS template: `CursorDb2McpServer_WinApp.deploy.json`

## Reinstall Steps

### 1) Publish to staging share

From repo root:

```powershell
pwsh.exe -NoProfile -File "C:\opt\src\CursorDb2McpServer\Build-And-Publish.ps1"
```

Equivalent manual command:

```powershell
dotnet publish "C:\opt\src\CursorDb2McpServer\CursorDb2McpServer\CursorDb2McpServer.csproj" -c Release -p:PublishProfile=WebApp-FileSystem -v minimal
```

### 2) Deploy IIS app

```powershell
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\IIS-DeployApp.ps1" -SiteName CursorDb2McpServer
```

Expected deployment shape:

- Parent site: `Default Web Site`
- Virtual path: `/CursorDb2McpServer`
- App pool: `CursorDb2McpServer`
- DLL: `CursorDb2McpServer.dll`

### 3) Verify server is reachable

Run the MCP verification script:

```powershell
pwsh.exe -NoProfile -File "C:\opt\src\CursorDb2McpServer\Test-McpQuery.ps1"
```

Expected:

- `Server: CursorDb2McpServer v...`
- `Tool: query_db2`
- Query succeeds and returns database/user

### 4) Optional direct HTTP smoke test

```powershell
$url = "http://dedge-server/CursorDb2McpServer/"
$body = @{
  jsonrpc = "2.0"
  id = 1
  method = "initialize"
  params = @{
    protocolVersion = "2024-11-05"
    capabilities = @{}
    clientInfo = @{ name = "smoke-test"; version = "1.0" }
  }
} | ConvertTo-Json -Depth 10

Invoke-WebRequest -Uri $url -Method Post -Body $body -ContentType "application/json" -Headers @{ Accept = "application/json, text/event-stream" }
```

## Post-Reinstall Client Check

If users cannot see/use `db2-query`, they must re-register the remote MCP endpoint:

```powershell
pwsh.exe -NoProfile -File "C:\opt\src\CursorDb2McpServer\Register-McpServer.ps1"
```

Then restart Cursor.

## Troubleshooting

| Symptom | Likely cause | Action |
|---|---|---|
| Timeout / unreachable endpoint | IIS app not deployed/running | Re-run IIS deploy command |
| 404 on `/mcp` | Wrong endpoint path | Use `http://dedge-server/CursorDb2McpServer/` (no `/mcp`) |
| 406 Not Acceptable | Missing `Accept` header | Use `Accept: application/json, text/event-stream` |
| Session header error | Stateful transport | Reuse `Mcp-Session-Id` after initialize (handled by `Test-McpQuery.ps1`) |
| Startup crash after deploy | Runtime mismatch | Ensure app/server runtime supports `net10.0` |

## Important Usage Safety

- `query_db2` is read-only (SELECT/WITH/VALUES only)
- Always provide `databaseName` using alias values (for example `BASISTST`)
- If `databaseName` is omitted, default is `BASISRAP` (production)
