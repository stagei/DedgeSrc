# [RESOLVED] MCP endpoint blocked by DedgeAuth middleware

| Field | Value |
|---|---|
| Source Project | DedgePsh (MCP server test suite) |
| Target Project | AutoDocJson |
| Created | 2026-03-25 19:05 |
| Resolved | 2026-03-29 20:00 |
| Author | FKGEISTA (Cursor Agent) |
| Priority | Medium |
| Resolution | Added `/mcp` to `DedgeAuth.SkipPathPrefixes` in `appsettings.json` (Option B). All 3 MCP tools verified working without auth. |

## Problem Description

The Streamable HTTP MCP endpoint at `/mcp` (mapped via `app.MapMcp("/mcp")` on line 35 of `Program.cs`) is blocked by DedgeAuth authentication middleware (`app.UseDedgeAuth()` on line 37). All POST requests to both `http://dedge-server/AutoDocJson/` and `http://dedge-server/AutoDocJson/mcp` return an HTTP 200 with the DedgeAuth login page (HTML) instead of a JSON-RPC MCP response.

The `/health` endpoint works without authentication, confirming that DedgeAuth selectively allows some paths. The MCP endpoint is not in that allow-list.

This prevents Cursor and other MCP clients from connecting to the autodoc-query MCP server.

## Affected Files

- `AutoDocJson.Web/Program.cs` (lines 35–37) — MCP endpoint mapped before DedgeAuth middleware but still intercepted

## Suggested Fix

Exclude the `/mcp` endpoint from DedgeAuth authentication. Two approaches:

### Option A: AllowAnonymous on MCP endpoint

If the MCP SDK supports it, configure the endpoint to allow anonymous access:

```csharp
app.MapMcp("/mcp").AllowAnonymous();
```

### Option B: Configure DedgeAuth exclusion path

If DedgeAuth supports path exclusions (similar to how `/health` is accessible), add `/mcp` to the exclusion list in `appsettings.json`:

```json
{
  "DedgeAuth": {
    "ExcludePaths": ["/health", "/mcp"]
  }
}
```

### Option C: Reorder middleware

If `MapMcp` supports terminal middleware semantics, ensure it short-circuits before DedgeAuth runs. This may require using `app.Map("/mcp", ...)` with a branch that skips auth:

```csharp
app.Map("/mcp", branch =>
{
    branch.MapMcp();
});
app.UseDedgeAuth();
```

### Verification

After fixing, run the MCP test from DedgePsh:

```powershell
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\CodingTools\McpServers\Setup-AutoDocMcpCursor\Test-AutoDocMcpCursor.ps1"
```

Or the full test suite:

```powershell
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\CodingTools\McpServers\Setup-AllMcpServers\Test-AllMcpServers.ps1"
```

## Context

Discovered while building and running `Test-AllMcpServers.ps1` — a test suite for all MCP servers (Cursor + Ollama). The AutoDoc MCP is the only server that fails. All other MCP servers (DB2 Query, PostgreSQL, RAG x3, Ollama x2) pass their tests.

The `CursorDb2McpServer` IIS app works because it is a dedicated MCP-only virtual application that does not use DedgeAuth middleware. AutoDocJson is a full web application with DedgeAuth enabled for its UI, and the MCP endpoint is an additional feature within the same app.

## Secondary Issue (DedgePsh — already fixed)

The setup script `Setup-AutoDocMcpCursor.ps1` registered the endpoint URL as `http://dedge-server/AutoDocJson/` (root) instead of `http://dedge-server/AutoDocJson/mcp` (the actual MCP path mapped in Program.cs). This has been corrected in DedgePsh alongside the test script.
