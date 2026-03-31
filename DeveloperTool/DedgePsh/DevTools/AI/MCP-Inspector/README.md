# MCP Inspector

Interactive debugger for **Model Context Protocol (MCP)** servers.  
Use it to inspect, test, and troubleshoot MCP tool calls directly in a browser UI.

---

## What It Is

[MCP Inspector](https://github.com/modelcontextprotocol/inspector) is an open-source tool from Anthropic that lets you:

- Connect to any MCP server (local or remote)
- Browse available **tools**, **resources**, and **prompts**
- Make live tool calls and inspect request/response payloads
- Debug problems with MCP integrations (e.g. Cursor IDE extensions)

It runs a local proxy and serves a browser UI at `http://localhost:3000`.

---

## Prerequisites

| Requirement | Version | Check |
|-------------|---------|-------|
| Node.js | >= 18 | `node --version` |
| npm | >= 9 | `npm --version` |
| Internet access | (first install only) | — |

Node.js is already available on this machine (`v22.x`).

---

## Quick Start

```powershell
# Start inspector (installs if needed, opens browser automatically)
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\AI\MCP-Inspector\Start-McpInspector.ps1"
```

The browser opens at `http://localhost:3000`. From there you can connect to any MCP server.

---

## Script Parameters

```powershell
.\Start-McpInspector.ps1 [-Port <int>] [-McpServerCommand <string>] [-NoBrowser] [-SkipInstall]
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Port` | `3000` | Port for the inspector UI |
| `-McpServerCommand` | *(none)* | Launch and pre-connect to an MCP server process |
| `-NoBrowser` | *(false)* | Suppress automatic browser launch |
| `-SkipInstall` | *(false)* | Skip the npm install check (use when offline) |

---

## Usage with the DedgeAuth Ecosystem

The DedgeAuth apps use Cursor's built-in **`cursor-ide-browser`** MCP server for browser testing.  
MCP Inspector is most useful for:

### 1. Debugging the cursor-ide-browser MCP

If Cursor's browser MCP behaves unexpectedly (wrong snapshots, click failures), you can inspect its raw calls:

1. Find the browser MCP server command in your Cursor extension settings
2. Run:
   ```powershell
   .\Start-McpInspector.ps1 -McpServerCommand "node C:\path\to\cursor-ide-browser\server.js"
   ```
3. In the UI, call `browser_navigate`, `browser_snapshot`, etc. directly without going through Cursor

### 2. Building a Custom DedgeAuth MCP Server

If you want to expose DedgeAuth operations (user management, app registration, log queries) as MCP tools callable from Cursor or other AI agents, create a Node.js or .NET MCP server and debug it here:

```powershell
# Example: launch a custom DedgeAuth MCP server during development
.\Start-McpInspector.ps1 -McpServerCommand "node C:\opt\src\DedgeAuthMcp\server.js"
```

Tool examples you might build:
- `get_users` → calls `GET /api/users`
- `search_logs` → calls GenericLogHandler log search API
- `get_server_status` → calls ServerMonitorDashboard API

### 3. Connecting via SSE (Remote Server)

If the MCP server exposes an SSE endpoint (e.g. running inside IIS):

1. Start the inspector: `.\Start-McpInspector.ps1`
2. In the browser UI, choose **SSE** transport
3. Enter the URL, e.g.: `http://localhost/DedgeAuth/mcp/sse`

---

## Connecting to a Running MCP Server in the UI

Once the inspector is running at `http://localhost:3000`:

1. **Transport**: Choose `stdio` (local process) or `SSE` (HTTP endpoint)
2. **Command** (stdio): Full path to the server executable, e.g. `node server.js`
3. **URL** (SSE): Full URL to the SSE endpoint
4. Click **Connect**
5. Browse **Tools**, **Resources**, and **Prompts** tabs
6. Select a tool → fill in arguments → click **Run Tool**
7. Inspect the raw JSON request and response

---

## Registering an MCP Server in Cursor

To make a custom MCP server available as tools inside Cursor's AI agent:

Edit `C:\Users\FKGEISTA\.cursor\mcp.json`:

```json
{
  "mcpServers": {
    "my-DedgeAuth-mcp": {
      "command": "node",
      "args": ["C:\\opt\\src\\DedgeAuthMcp\\server.js"],
      "env": {
        "DedgeAuth_URL": "http://localhost/DedgeAuth",
        "DedgeAuth_TOKEN": "<your-token>"
      }
    }
  }
}
```

After saving, Cursor picks up the server automatically.  
Use MCP Inspector to test the server **before** registering it in Cursor.

---

## Troubleshooting

| Problem | Likely Cause | Fix |
|---------|-------------|-----|
| `node not found` | Node.js not on PATH | Restart terminal or reinstall Node.js |
| `npm install failed` | Permissions or network | Run as Administrator; check proxy settings |
| Browser opens but shows blank | Server not started yet | Wait a few seconds, refresh |
| Tool call returns error | Server bug or wrong args | Check server logs; use inspector's raw JSON view |
| Port 3000 in use | Another process | Use `-Port 4000` or another free port |

---

## Updating MCP Inspector

```powershell
npm install -g @modelcontextprotocol/inspector@latest
```

Or just run `Start-McpInspector.ps1` — it checks for the package on every launch  
(use `-SkipInstall` to bypass this check when offline).

---

## Links

- [MCP Inspector on GitHub](https://github.com/modelcontextprotocol/inspector)
- [Model Context Protocol spec](https://spec.modelcontextprotocol.io)
- [Cursor MCP documentation](https://docs.cursor.com/advanced/mcp)
