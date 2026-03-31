# CursorDb2McpServer

MCP server that lets Cursor run read-only SQL queries against DB2 databases. Hosted on IIS at `dedge-server` — no local installation required.

## Recommended setup (no repo clone needed)

If you already have `DedgePsh`, use the CodingTools scripts directly:

```powershell
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\CodingTools\Setup-CursorDb2Mcp\Setup-CursorDb2Mcp.ps1"
```

Then restart Cursor.

Optional: set up local Ollama to use the same remote DB2 MCP server:

```powershell
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\CodingTools\Setup-OllamaDb2\Setup-OllamaDb2.ps1"
```

Verify availability after restart:

```powershell
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\CodingTools\Setup-OllamaDb2\Test-OllamaDb2.ps1" -AutoStartBridge
```

After that, restart PowerShell and use:

```powershell
Start-Db2Bridge
Ask-Db2 "How many rows are in DBM.A_ORDREHODE on BASISTST?"
```

## Clone this repo (contributors)

```powershell
git clone https://Dedge@dev.azure.com/Dedge/Dedge/_git/CursorDb2McpServer c:\opt\src\CursorDb2McpServer
```

## Setup from this repo (alternative)

```powershell
pwsh.exe -NoProfile -File "c:\opt\src\CursorDb2McpServer\Register-McpServer.ps1"
```

Then restart Cursor.

This adds the following to `~/.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "db2-query": {
      "url": "http://dedge-server/CursorDb2McpServer/"
    }
  }
}
```

After restart, Cursor shows `db2-query` in Settings > MCP.

## Usage

Just ask Cursor in natural language — the AI agent picks up the `db2-query` tool automatically. There is no `@` shortcut for MCP tools; they don't appear in the `@` menu. Examples:

- *"Count rows in DBM.A_ORDREHODE on BASISTST"*
- *"Show the first 10 rows from DBM.A_ORDRELINJE on BASISTST"*
- *"What columns does DBM.A_ORDREHODE have on BASISTST?"*

Always mention which database to use. If you don't, the default is **BASISRAP (PRODUCTION)**.

## Available Databases

Use the **Alias** name as `databaseName`.

### FKM (Dedge)

| databaseName | Env | Description |
|-------------|-----|-------------|
| `BASISTST` | TST | Test — recommended for development |
| `FKAVDNT` | DEV | Development |
| `BASISVFT` | VFT | Forsprang test |
| `BASISFUT` | FUT | Functional test |
| `BASISKAT` | KAT | Customer acceptance test |
| `BASISPER` | PER | Performance test |
| `BASISMIG` | MIG | Migration test |
| `BASISVFK` | VFK | Supply chain acceptance test |
| `BASISRAP` | RAP | **PRODUCTION** — Report database |
| `BASISPRO` | PRD | **PRODUCTION** — Main database |
| `BASISREG` | PRD | **PRODUCTION** — Main database (alt alias) |
| `BASISHST` | HST | **PRODUCTION** — History |

### INL (Innlan)

| databaseName | Env | Description |
|-------------|-----|-------------|
| `FKKTOTST` | TST | Test |
| `FKKTODEV` | DEV | Development |
| `FKKONTO` | PRD | **PRODUCTION** |

### DOC / VIS

| databaseName | Env | Description |
|-------------|-----|-------------|
| `COBDOK` | PRD | **PRODUCTION** — COBDOK |
| `VISMABUS` | PRD | **PRODUCTION** — Visma |

## Restrictions

- **Read-only** — SELECT, WITH ... SELECT, VALUES only
- INSERT, UPDATE, DELETE, DROP, CREATE, ALTER are blocked
- All databases use **Windows-1252 encoding** (Norwegian characters Æ Ø Å work in Cursor chat)

## Verify

Run the test script to confirm the server is responding:

```powershell
pwsh.exe -NoProfile -File "c:\opt\src\CursorDb2McpServer\Test-McpQuery.ps1"
```
