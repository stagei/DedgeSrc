# DB2 Query MCP Server — Developer Setup

A shared MCP server running on `dedge-server` that lets Cursor query DB2 databases directly from chat. No local DB2 client, drivers, or credentials needed.

## Quick Setup

### 1. Register the MCP server

Open a terminal and run:

```powershell
pwsh.exe -NoProfile -File "c:\opt\src\CursorDb2McpServer\Register-McpServer.ps1"
```

This adds the `db2-query` entry to your `~/.cursor/mcp.json`. Any existing MCP servers you have configured are preserved.

### 2. Restart Cursor

Close and reopen Cursor. The `db2-query` tool appears in the MCP tools list (look for the hammer icon in chat).

### 3. Start querying

Ask Cursor to query DB2 in natural language:

> "Query FKMTST: show me the first 10 rows from DBM.Z_AVDTAB"

Or be explicit:

> "Use the db2-query MCP tool to run `SELECT * FROM DBM.Z_AVDTAB FETCH FIRST 10 ROWS ONLY` against FKMTST"

## Manual Setup (alternative)

If you prefer to configure manually, add this to `%USERPROFILE%\.cursor\mcp.json`:

```json
{
  "mcpServers": {
    "db2-query": {
      "url": "http://dedge-server/CursorDb2McpServer/"
    }
  }
}
```

If the file already exists, merge the `db2-query` entry into your existing `mcpServers` block.

## Available Databases

| Catalog    | Environment | Notes                            |
|------------|-------------|----------------------------------|
| `FKMTST`   | Test        | Use for development and testing  |
| `BASISRAP` | Production  | Default when databaseName is empty |

## What You Can Do

- **SELECT** queries, including **WITH ... SELECT** (CTEs) and **VALUES**
- Results come back as JSON with column names and rows
- Large result sets are handled automatically

## Restrictions

- **Read-only** — INSERT, UPDATE, DELETE, DROP, CREATE, ALTER, and other DDL/DML are blocked
- The server enforces this regardless of your DB2 permissions

## Character Encoding

The DB2 databases use **Windows-1252 (ANSI)** encoding. Norwegian characters (Æ Ø Å) display correctly in Cursor chat. When writing results to files, use appropriate encoding:

- PowerShell: `-Encoding windows-1252`
- Python: `encoding='cp1252'`

## Verifying the Connection

Run the test script to confirm everything works:

```powershell
pwsh.exe -NoProfile -File "c:\opt\src\CursorDb2McpServer\Test-McpQuery.ps1"
```

Expected output:

```
Testing CursorDb2McpServer at http://dedge-server/CursorDb2McpServer/

1. Sending initialize request...
   Server: CursorDb2McpServer v1.0.0.0
   Protocol: 2024-11-05
   Session: ...
2. Listing tools...
   Tool: query_db2 - Execute a read-only SQL query...
3. Executing test query...
   Database: FKMTST
   User: FKTSTADM
   Rows: 1

Test complete.
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Tool not showing in Cursor | Restart Cursor after running `Register-McpServer.ps1` |
| Connection refused | Verify `dedge-server` is reachable: `curl http://dedge-server/CursorDb2McpServer/` |
| Timeout on queries | Large queries may take time; the server has a 60-second timeout |
| Wrong database name | Check the catalog name — use `FKMTST` for test, `BASISRAP` for production |
