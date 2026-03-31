# Analysis: Setup-AllMcpServers Test Failures

**Date:** 2026-03-25
**Script:** `Setup-AllMcpServers.ps1`
**Run:** 12:12:04 – 12:13:20 (76 seconds)
**Result:** 12 scripts, 11 OK, 1 FAIL

---

## Summary

| Phase | Client | Script | Status | Issue |
|---|---|---|---|---|
| Setup | Cursor | Setup-AutoDocMcpCursor | OK | — |
| Setup | Cursor | Setup-Db2QueryMcpCursor | OK | — |
| Setup | Cursor | Setup-PostgreSqlMcpCursor | OK | — |
| Setup | Cursor | Setup-RagMcpCursor | OK | — |
| Setup | Ollama | Setup-Db2QueryMcpOllama | OK | — |
| Setup | Ollama | Setup-RagMcpOllama | OK | — |
| Test | Cursor | Test-AutoDocMcpCursor | **FAIL** | Server returns HTML, not JSON |
| Test | Cursor | Test-Db2QueryMcpCursor | OK | — |
| Test | Cursor | Test-PostgreSqlMcpCursor | OK* | *Query fails — 0 databases loaded* |
| Test | Cursor | Test-RagMcpCursor | OK | — |
| Test | Ollama | Test-Db2QueryMcpOllama | OK | — |
| Test | Ollama | Test-RagMcpOllama | OK | — |

All 6 **setup** scripts passed. Two **test** scripts have issues (one hard fail, one silent error).

---

## Issue 1: Test-AutoDocMcpCursor FAIL — Server returns HTML instead of JSON

### Symptom

```
ConvertFrom-Json: Test-AutoDocMcpCursor.ps1:69:23
  Conversion from JSON failed with error: Unexpected character encountered
  while parsing value: <. Path '', line 0, position 0.
```

### Root Cause

The test sends a JSON-RPC POST to `http://dedge-server/AutoDocJson/` and expects a JSON response. The server returns content starting with `<` — an HTML page (likely an IIS error page or default page).

This means:

1. **The AutoDocJson IIS virtual application is not responding with JSON-RPC.** Possible causes:
   - The AutoDocJson app pool is stopped or recycled and not restarting
   - The ASP.NET Core process (`AutoDocJson.Web.dll`) has crashed or is not accepting MCP requests at the root path
   - The MCP Streamable HTTP endpoint is at a sub-path (e.g. `/mcp`) rather than the root `/`
   - IIS is returning a default error page (404/500/502) before the request reaches the ASP.NET Core app

2. **The `Send-McpRequest` function** in `Test-AutoDocMcpCursor.ps1` does not check the HTTP status code before parsing. It uses `Invoke-WebRequest` which throws on 4xx/5xx by default, but if IIS returns a 200 with an HTML body (e.g., a default page or error page with `customErrors mode="On"`), the function proceeds to `ConvertFrom-Json` on HTML content.

### Fix Guidance

1. **Check the AutoDocJson app on dedge-server:**
   ```powershell
   # Diagnose the IIS app
   pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\Test-IISSite.ps1" -SiteName AutoDocJson
   
   # Or rebuild and redeploy
   pwsh.exe -NoProfile -File "C:\opt\src\AutoDocJson\Build-And-Publish.ps1"
   pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\WebSites\IIS-DeployApp\IIS-DeployApp.ps1" -SiteName AutoDocJson
   ```

2. **Verify the MCP endpoint manually:**
   ```powershell
   $response = Invoke-WebRequest -Uri "http://dedge-server/AutoDocJson/" -Method POST `
       -Body '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' `
       -Headers @{"Content-Type"="application/json"} -UseBasicParsing
   Write-Host "Status: $($response.StatusCode)"
   Write-Host "Content-Type: $($response.Headers['Content-Type'])"
   Write-Host "Body (first 200 chars): $($response.Content.Substring(0, [Math]::Min(200, $response.Content.Length)))"
   ```

3. **Harden the test script** to detect HTML responses before parsing:
   - Check `$response.Headers["Content-Type"]` for `application/json` before calling `ConvertFrom-Json`
   - Check HTTP status code explicitly

---

## Issue 2: Test-PostgreSqlMcpCursor — 0 Databases Loaded (Silent Error)

### Symptom

```
[INFO] 4. Listing databases...
[INFO]    Available databases: 0
[INFO] 5. Executing test query on DedgeAuth (TST)...
[ERROR]   Query error: Database 'DedgeAuth' not found. Available:
```

The MCP server starts, initializes, lists tools, and enforces read-only correctly — but it loads **zero** database configurations. The test still reports **OK** because it only marks failure if the server process crashes.

### Root Cause

The folder restructure from `DevTools/CodingTools/Setup-PostgreSqlMcpCursor/` to `DevTools/CodingTools/McpServers/Setup-PostgreSqlMcpCursor/` broke the relative path to `PostgreSqlDatabases.json`.

In `postgresql-mcp-server.mjs` (line 46):

```javascript
join(__dirname, "..", "..", "DatabaseTools", "PostGreSql-DatabaseSetup", "PostgreSqlDatabases.json")
```

| | Old location | New location |
|---|---|---|
| `__dirname` | `CodingTools/Setup-PostgreSqlMcpCursor` | `CodingTools/McpServers/Setup-PostgreSqlMcpCursor` |
| `../..` | `DevTools/` | `DevTools/CodingTools/` |
| Resolved path | `DevTools/DatabaseTools/PostGreSql-DatabaseSetup/PostgreSqlDatabases.json` | `DevTools/CodingTools/DatabaseTools/PostGreSql-DatabaseSetup/PostgreSqlDatabases.json` |
| Exists? | Yes | **No** |

The fallback path (`$OptPath/DedgePshApps/PostGreSql-DatabaseSetup/PostgreSqlDatabases.json`) also fails because `PostGreSql-DatabaseSetup` hasn't been deployed locally on this developer machine.

Since no candidate path exists, `loadDatabaseConfig()` returns `[]` (empty array), resulting in 0 databases.

### Fix

Update the relative path in `postgresql-mcp-server.mjs` line 46 to go up three levels instead of two:

```javascript
// Before (broken after folder move)
join(__dirname, "..", "..", "DatabaseTools", "PostGreSql-DatabaseSetup", "PostgreSqlDatabases.json")

// After (correct for McpServers/ subfolder)
join(__dirname, "..", "..", "..", "DatabaseTools", "PostGreSql-DatabaseSetup", "PostgreSqlDatabases.json")
```

### Secondary Fix: Test Should Report Query Failure

`Test-PostgreSqlMcpCursor.ps1` sets `$script:testPassed = $true` unconditionally at line 202 even when the query returned an error. The "Database not found" error is logged but does not affect the final status. The test should fail when the query returns an error or when 0 databases are available.

---

## Affected Files

| File | Issue | Fix Required |
|---|---|---|
| `Setup-PostgreSqlMcpCursor/postgresql-mcp-server.mjs:46` | Broken relative path after folder move | Change `"..", ".."` to `"..", "..", ".."` |
| `Setup-PostgreSqlMcpCursor/Test-PostgreSqlMcpCursor.ps1` | Does not fail on query errors | Mark test failed when query returns error or 0 databases |
| `Setup-AutoDocMcpCursor/Test-AutoDocMcpCursor.ps1` | Does not handle HTML responses | Check Content-Type before parsing JSON |
| AutoDocJson IIS app on `dedge-server` | Not returning JSON-RPC responses | Diagnose app pool / ASP.NET Core process |
