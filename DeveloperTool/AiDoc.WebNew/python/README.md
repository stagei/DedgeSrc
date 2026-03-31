# AiDoc RAG – Python engine

The Python RAG engine powers the AiDoc vector search. It builds ChromaDB indexes from markdown content in `AiDoc.Library/` and serves them via MCP (stdio) or HTTP for the AiDoc web portal.

## Architecture

```
AiDoc.Python/          ← this folder (engine code)
AiDoc.Library/         ← sibling folder (RAG content + indexes)
  ├── db2-docs/
  ├── visual-cobol-docs/
  ├── Dedge-code/
  └── rag-registry.json
```

On servers, the library is deployed separately to `$env:OptPath\data\AiDoc.Library`. The Python engine resolves the library location automatically (env var `AIDOC_LIBRARY_DIR` → `$OptPath\data\AiDoc.Library` → sibling `AiDoc.Library/`).

## How it works

1. **Sources**: Markdown content lives in `AiDoc.Library/<rag-name>/` subfolders.
2. **Chunking**: Markdown is split into ~2400-character chunks with overlap (`chunk.py`).
3. **Embeddings**: Chunks are embedded with ChromaDB's ONNX `all-MiniLM-L6-v2` (local, no API key).
4. **Index**: Stored in `AiDoc.Library/<rag-name>/.index/` (ChromaDB, persistent, gitignored).
5. **Serving**: `server.py` (MCP/stdio) or `server_http.py` (HTTP) exposes semantic search per RAG.

## Setup

### 1. Python

Use **Python 3.10, 3.12, or 3.13**. **Python 3.14 is not supported** (ChromaDB/pydantic incompatibility). Prefer a virtual environment:

```powershell
cd C:\opt\src\AiDoc\AiDoc.Python
py -3.13 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

### 2. Build indexes

Build all RAG indexes from the library:

```powershell
python build_index.py --all
```

Each `AiDoc.Library/<name>/` subfolder gets an index at `AiDoc.Library/<name>/.index`.

To build a single RAG:

```powershell
python build_index.py --rag db2-docs
```

On the server, `Rebuild-RagIndex.ps1` (from DedgePsh) handles building with live progress reporting.

### 3. Add the server to Cursor MCP

See **[docs/Configure-Cursor-RAG.md](../docs/Configure-Cursor-RAG.md)** for full steps. In short: **Settings → Cursor Settings → MCP** (or edit your MCP config file).

**Global MCP config** — edit `%USERPROFILE%\.cursor\mcp.json`:

```json
{
  "mcpServers": {
    "db2-docs": {
      "command": "C:\\opt\\src\\AiDoc\\AiDoc.Python\\.venv\\Scripts\\python.exe",
      "args": ["C:\\opt\\src\\AiDoc\\AiDoc.Python\\server.py", "--rag", "db2-docs"],
      "cwd": "C:\\opt\\src\\AiDoc\\AiDoc.Python"
    }
  }
}
```

Restart Cursor after saving. To register all library RAGs at once:

```powershell
pwsh.exe -File C:\opt\src\AiDoc\AiDoc.Python\scripts\Register-AllCursorRagMcp.ps1
```

### 4. Test

**In Cursor chat**, ask a question that should use the docs. The AI will call the RAG tool and cite the source files. Example questions:
- "What does SQL30082N reason code 36 mean?"
- "How do I fix DB2 security processing failed?"
- "Explain COBCH0779 Visual COBOL"

**From CLI:**

```powershell
pwsh.exe -File "C:\opt\src\AiDoc\AiDoc.Python\scripts\Test-RagFromCli.ps1" -Query "SQL30082N reason code 36"
```

## Files

| File | Purpose |
|------|---------|
| `build_index.py` | Builds ChromaDB indexes from `AiDoc.Library/<name>/` content. |
| `chunk.py` | Document chunking (2400 chars, 300 overlap). |
| `server.py` | MCP server (stdio); exposes `query_db2_manuals` per RAG. |
| `server_http.py` | HTTP server; used by AiDoc.Web to proxy queries. |
| `convert_to_md.py` | Converts `.pdf` and `.docx` files to markdown. |
| `rag_embedding.py` | Embedding model management. |
| `rag_sources.json` | Legacy source config (superseded by library layout). |
| `.db2-docs-index/` | Legacy single-RAG index (gitignored, see note below). |
| `scripts/` | PowerShell helpers for library management and Cursor registration. |
| `test_rag_query.py` | CLI RAG query test without Cursor. |

### Legacy: `.db2-docs-index/`

This folder is the original single-RAG index from before the library system was introduced. It is used only by the legacy code path in `build_index.py` (no `--rag`/`--all` flags) and `server.py` (no `--rag` flag). The folder is gitignored and can be safely deleted — all current indexes live in `AiDoc.Library/<name>/.index/`.

## Adding a new RAG

1. Create a folder under `AiDoc.Library/` with your markdown files.
2. Register in `AiDoc.Library/rag-registry.json`.
3. Build the index: `python build_index.py --rag <name>`
4. Register in Cursor: `pwsh.exe -File scripts\Sync-LibraryRagsToCursor.ps1`

Or use the wrapper script: `Add-RagToLibrary.ps1 -Name <name> [-SourcePath <path>]` (see [docs/Library-RAG-Scripts.md](../docs/Library-RAG-Scripts.md)).

## Troubleshooting

- **"RAG index not found"** — Run `python build_index.py --rag <name>` with the venv active.

- **Cursor doesn't show the tool** — Check MCP in Cursor settings. Verify `command`, `args`, and `cwd`. Restart Cursor after config changes.

- **Slow first query** — The first call loads the embedding model and ChromaDB; later queries are faster.

- **No good results** — Try rephrasing or increasing `n_results`.

- **"Search failed: Cannot send a request, as the client has been closed."** — The MCP server process exited. Restart Cursor. If your network blocks Hugging Face, use a pre-cached model (see [docs/RAG-Backup-and-Distribution.md](../docs/RAG-Backup-and-Distribution.md)).

For more details, see [docs/Configure-Cursor-RAG.md](../docs/Configure-Cursor-RAG.md).
