# [ERROR] MCP endpoint returns HTML instead of JSON-RPC response

| Field | Value |
|---|---|
| Source Project | DedgePsh |
| Target Project | AutoDocJson |
| Created | 2026-03-25 12:39 |
| Author | FKGEISTA (Cursor Agent) |
| Priority | High |

## Problem Description

The AutoDocJson MCP endpoint at `http://dedge-server/AutoDocJson/` returns an HTML page instead of a JSON-RPC response when receiving a valid MCP `initialize` request.

The `Test-AutoDocMcpCursor.ps1` test sends a POST with `Content-Type: application/json` containing:

```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test-client","version":"1.0"}}}
```

The response body starts with `<` (HTML), causing `ConvertFrom-Json` to fail:

```
Conversion from JSON failed with error: Unexpected character encountered
while parsing value: <. Path '', line 0, position 0.
```

This was discovered when running `Setup-AllMcpServers.ps1` which runs all MCP setup and test scripts. All 6 setup scripts passed, but `Test-AutoDocMcpCursor` failed during the test phase.

## Affected Files

- The IIS virtual application `AutoDocJson` on `dedge-server` (runtime)
- `AutoDocJson.Web.dll` — the ASP.NET Core process hosting the MCP Streamable HTTP endpoint

## Possible Causes

1. **App pool stopped or crashed** — AutoDocJson app pool on `dedge-server` is not running, and IIS returns a default error page
2. **ASP.NET Core process not starting** — `AutoDocJson.Web.dll` fails on startup, IIS returns a 502/500 HTML error
3. **MCP endpoint path mismatch** — the Streamable HTTP MCP handler may be registered at a sub-path (e.g. `/mcp`) rather than the root `/`
4. **Missing or outdated deployment** — the published version on the server may not include the MCP endpoint

## Suggested Fix

1. **Diagnose from DedgePsh:**
   ```powershell
   pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\Test-IISSite.ps1" -SiteName AutoDocJson
   ```

2. **Check what the endpoint actually returns:**
   ```powershell
   $r = Invoke-WebRequest -Uri "http://dedge-server/AutoDocJson/" -Method POST `
       -Body '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' `
       -Headers @{"Content-Type"="application/json"} -UseBasicParsing
   Write-Host "Status: $($r.StatusCode), Content-Type: $($r.Headers['Content-Type'])"
   Write-Host $r.Content.Substring(0, [Math]::Min(500, $r.Content.Length))
   ```

3. **If the app needs redeployment:**
   ```powershell
   pwsh.exe -NoProfile -File "C:\opt\src\AutoDocJson\Build-And-Publish.ps1"
   pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\IIS-DeployApp.ps1" -SiteName AutoDocJson
   ```

4. **If the MCP handler is at a sub-path**, update the endpoint URL in `DedgePsh\DevTools\CodingTools\McpServers\Setup-AutoDocMcpCursor\Setup-AutoDocMcpCursor.ps1` and in the Cursor `mcp.json` registration.

## Context

Running `Setup-AllMcpServers.ps1` as part of the MCP server consolidation in DedgePsh. All setup scripts passed (registration in `mcp.json` succeeded), but the end-to-end test that actually calls the AutoDocJson HTTP endpoint failed. The Db2 Query, PostgreSQL, and RAG MCP tests all passed.
