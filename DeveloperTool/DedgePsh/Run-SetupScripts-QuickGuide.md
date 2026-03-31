# Run Setup Scripts (Coding Tools)

Please run the following commands:

```powershell
Import-Module SoftwareUtils -Force
Install-OurPshApp -AppName "Setup-CursorDb2Mcp"
Install-OurPshApp -AppName "Setup-OllamaRag"
Install-OurPshApp -AppName "Setup-CursorRag"
Install-OurPshApp -AppName "Setup-CursorUserSettings"
Install-OurPshApp -AppName "Setup-OllamaDb2"
```

## What each script does

- `Setup-CursorDb2Mcp`
  - Registers the `db2-query` MCP server in Cursor `mcp.json`.
  - Result: Cursor can use the remote DB2 query MCP endpoint.

- `Setup-OllamaRag`
  - Adds `Ask-Rag` helper in PowerShell profile and configures it for remote RAG servers.
  - Result: You can ask documentation questions from terminal using Ollama + RAG.

- `Setup-CursorRag`
  - Configures Cursor to use remote RAG doc servers (via proxy + mcp entries).
  - Result: Cursor chat can query the shared RAG indexes after restart.

- `Setup-CursorUserSettings`
  - Applies team-standard Cursor user settings and installs recommended Cursor extensions.
  - Result: Standardized Cursor setup (settings + extensions) for the current user.

- `Setup-OllamaDb2`
  - Sets up a local Ollama DB2 bridge to the remote `CursorDb2McpServer`.
  - Result: You get local helper commands for DB2 Q&A with Ollama (`Start-Db2Bridge`, `Ask-Db2`).

## Expected overall result

After running all five installs, the machine is ready for:

- Cursor + DB2 MCP queries
- Cursor + RAG documentation queries
- Ollama terminal usage for both RAG and DB2 workflows
- Team-standard Cursor configuration
