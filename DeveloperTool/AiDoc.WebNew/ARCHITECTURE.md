# AiDoc.WebNew — Python & Non-C# Architecture

## 1. System Overview

How all components connect — from client-side Cursor/Ollama through local MCP proxies, to the server-side HTTP services, Python core, and ChromaDB storage.

```mermaid
flowchart TB
    subgraph CLIENTS["Client Side"]
        CURSOR["Cursor IDE\n(MCP stdio)"]
        BROWSER["Web Browser\n(Admin UI)"]
        OLLAMA["Ollama / PowerShell\n(Ask-Rag)"]
    end

    subgraph PROXY["Local MCP Proxies (dev machines)"]
        SMP["server_mcp_proxy.py\n--rag db2-docs\n--remote-url http://server:8484"]
        SP["server_proxy.py\n--rag visual-cobol-docs\n--remote-host server:8485"]
    end

    subgraph SERVER["Application Server (dedge-server)"]
        subgraph IIS["IIS / ASP.NET Core"]
            CSHARP["AiDoc.WebNew\nC# .NET 10 API"]
        end

        subgraph NSSM["Windows Services via NSSM"]
            SRV1["server_http.py\n--rag db2-docs :8484"]
            SRV2["server_http.py\n--rag visual-cobol-docs :8485"]
            SRV3["server_http.py\n--rag Dedge-code :8486"]
        end

        subgraph PYCORE["Python Core (in venv)"]
            SERVER_MOD["server.py\nsearch_db2_docs()"]
            EMBED["rag_embedding.py\nLocalONNXMiniLM_L6_V2"]
        end

        subgraph STORAGE["Data Layer"]
            CHROMADB[("ChromaDB\nPersistentClient\n.index/ folders")]
            LIBRARY[("AiDoc.Library\n%OptPath%/data/")]
            ONNX["all-MiniLM-L6-v2\nONNX model 86MB"]
        end
    end

    CURSOR -->|MCP stdio| SMP
    CURSOR -->|MCP stdio| SP
    SMP -->|HTTP POST /query| SRV1
    SP -->|HTTP POST /query| SRV2
    BROWSER -->|HTTPS| CSHARP
    OLLAMA -->|HTTP| CSHARP
    CSHARP -->|HTTP /health + /rags| SRV1
    CSHARP -->|pwsh.exe Rebuild| PYCORE
    SRV1 --> SERVER_MOD
    SRV2 --> SERVER_MOD
    SRV3 --> SERVER_MOD
    SERVER_MOD --> EMBED
    EMBED --> ONNX
    SERVER_MOD --> CHROMADB
    CHROMADB --> LIBRARY
```

---

## 2. Index Build Pipeline

How RAG indexes are created — from trigger (Admin UI or API) through PowerShell orchestration, Python chunking/embedding, to ChromaDB vector storage.

```mermaid
flowchart LR
    subgraph TRIGGER["Trigger"]
        UI["Admin UI\nRebuild Button"]
        API["C# API\nPOST /api/rags/name/rebuild"]
    end

    subgraph ORCH["PowerShell Orchestrator"]
        REBUILD["Rebuild-RagIndex.ps1\nWrites .running status\nTracks PID + progress %"]
    end

    subgraph Dedge["Dedge-code Special Steps"]
        GIT["Git Clone/Pull\nAzure DevOps repos"]
        DB2EXP["Export-Db2ForRag\ndb2look DDL + queries"]
        RAGMD["Write-RagMarkdown\nConvert to .md"]
    end

    subgraph PYBUILD["Python Build"]
        BUILD["build_index.py\n--rag name"]
        CHUNK["chunk.py\n2400-char chunks\n300-char overlap"]
        CONVERT["convert_to_md.py\n.pdf/.docx to .md"]
    end

    subgraph VECTORIZE["Vectorization"]
        ONNX2["ONNX Runtime\nall-MiniLM-L6-v2"]
        CHROMA2[("ChromaDB\nPersistentClient")]
    end

    subgraph OUTPUT["Output"]
        INDEX[".index/ folder\nvector database on disk"]
        MANIFEST[".index_manifest.json\nbuiltAt + sourceHash"]
    end

    UI --> API
    API -->|pwsh.exe -File| REBUILD
    REBUILD -->|Dedge-code only| GIT
    GIT --> DB2EXP --> RAGMD --> BUILD
    REBUILD -->|other RAGs| BUILD
    BUILD --> CHUNK
    BUILD --> CONVERT
    CHUNK -->|text + metadata| ONNX2
    ONNX2 -->|384-dim vectors| CHROMA2
    CHROMA2 --> INDEX
    BUILD --> MANIFEST
```

---

## 3. Query Flow

The full path of a semantic search query — from Cursor IDE through the local MCP proxy, over HTTP to the server, through ONNX embedding and ChromaDB similarity search, back to the client.

```mermaid
sequenceDiagram
    participant C as Cursor IDE
    participant P as server_mcp_proxy.py<br/>(local MCP stdio)
    participant H as server_http.py<br/>(remote HTTP :848x)
    participant S as server.py<br/>(search_db2_docs)
    participant E as rag_embedding.py<br/>(ONNX MiniLM)
    participant D as ChromaDB<br/>(.index/)

    C->>P: MCP tool call: query_docs("SQL0805N error")
    P->>H: POST /query {"query", "n_results":6}
    H->>S: search_db2_docs(query, n=6)
    S->>E: Embed query text
    E->>E: ONNX Runtime inference → 384-dim vector
    E-->>S: query vector [0.12, -0.34, ...]
    S->>D: coll.query(query_texts, n_results=6)
    D->>D: Cosine similarity search (HNSW)
    D-->>S: Top 6 chunks + metadata + distances
    S-->>H: Formatted result text with citations
    H-->>P: JSON {"result": "[1] source:... chunk text..."}
    P-->>C: MCP response with RAG context
```

---

## 4. Server File Layout

```mermaid
flowchart TB
    subgraph APP["E:\opt\DedgeWinApps\AiDocNew-Web"]
        DOTNET["*.dll, web.config\nASP.NET Core app"]
        subgraph PY["python/"]
            SCRIPTS_PY["server.py, server_http.py\nbuild_index.py, chunk.py\nconvert_to_md.py\nrag_embedding.py, rag_logging.py"]
            VENV[".venv/\ncreated by _install.ps1"]
            WHEELS["wheels/\n89 pre-downloaded .whl files"]
            ONNX_DIR[".onnx_models/all-MiniLM-L6-v2/\nmodel.onnx 86MB + tokenizer"]
        end
        subgraph SC["scripts/"]
            INSTALL_SVC["Install-RagHttpService.ps1"]
            REBUILD_SC["Rebuild-RagIndex.ps1"]
            FIX_VENV["Fix-VenvAndRestart.ps1"]
            KILL["Kill-HungRebuild.ps1"]
        end
        INST["_install.ps1\npost-deploy: creates venv\ninstalls wheels offline\nregisters NSSM services"]
    end

    subgraph LIB["E:\opt\data\AiDoc.Library"]
        DB2["db2-docs/\n*.md + .index/ + .index_manifest.json"]
        COBOL["visual-cobol-docs/\n*.md + .index/ + .index_manifest.json"]
        Dedge["Dedge-code/\ncode/ + _databases/ + .index/"]
        REG["rag-registry.json\nname, port, description"]
    end

    INST -->|pip install --no-index| VENV
    VENV -->|runs| SCRIPTS_PY
    SCRIPTS_PY -->|loads| ONNX_DIR
    SCRIPTS_PY -->|reads/writes| LIB
```

---

## 5. Component Reference

### Python Scripts

| Component | Role | Description |
|-----------|------|-------------|
| `server_http.py` | HTTP RAG Service | Runs as a Windows Service via NSSM. Exposes `/query`, `/health`, and `/rags` endpoints. One instance per RAG on its own port (8484, 8485, 8486). Network-accessible entry point for all RAG queries. |
| `server.py` | Search Engine Core | Contains `search_db2_docs()` — opens ChromaDB persistent index, runs vector similarity queries, formats results with source citations and distance scores. Also serves as standalone MCP stdio server for direct local use. |
| `server_mcp_proxy.py` | Client MCP Bridge (URL) | Thin local proxy on dev machines. Cursor connects via MCP stdio; forwards queries as HTTP POST to remote `server_http.py` using `--remote-url`. No ChromaDB or ONNX needed locally. |
| `server_proxy.py` | Client MCP Bridge (host+port) | Same as above but takes `--remote-host` and `--remote-port` separately. |
| `build_index.py` | Index Builder | Builds ChromaDB vector indexes from markdown. Supports `--rag NAME` (single) or `--all`. Chunks docs, generates ONNX embeddings, stores in ChromaDB, writes `.index_manifest.json` with build timestamp and source hash. |
| `chunk.py` | Document Chunker | Splits markdown into ~2400-char chunks with 300-char overlap, breaking at paragraph boundaries. Generates stable SHA-256 chunk IDs for deduplication. |
| `rag_embedding.py` | Embedding Function | Wraps ChromaDB's `ONNXMiniLM_L6_V2` to use a bundled local model from `python/.onnx_models/` instead of downloading from HuggingFace. Makes the system fully portable and offline. |
| `convert_to_md.py` | File Converter | Converts `.pdf` (pypdf), `.docx` (python-docx), `.txt` to Markdown during index building. |
| `rag_logging.py` | Logging | Daily log files to `C:\opt\data\AllPwshLog` as `RAG-Python_HOSTNAME_yyyyMMdd.log`. Shared log directory with PowerShell logs. |

### Key Libraries & Models

| Component | Description |
|-----------|-------------|
| **ChromaDB 1.5.5** | Embedded vector database using `PersistentClient` (SQLite + HNSW on disk). Each RAG has its own `.index/` folder inside `AiDoc.Library/<rag-name>/`. Stores document chunks as vectors alongside metadata (source file, chunk ID). Cosine similarity search at query time. |
| **all-MiniLM-L6-v2 (ONNX)** | Sentence-transformer model producing 384-dimensional vectors. Runs locally via ONNX Runtime — no GPU, no internet. `model.onnx` (86MB) + tokenizer files bundled in `python/.onnx_models/`. Same model used for both indexing and querying to ensure consistent embeddings. |
| **Python venv + 89 Wheels** | Fully offline installation via `pip install --no-index --find-links wheels/`. `_install.ps1` creates the venv, installs all wheels, and registers NSSM services. Zero internet access needed on the server. |
| **NSSM** | Non-Sucking Service Manager. Wraps `server_http.py` processes as proper Windows Services with auto-restart, delayed-auto start, and log rotation. |
| **MCP (Model Context Protocol)** | Stdio-based protocol for Cursor IDE to communicate with tool servers. The proxy scripts implement MCP servers that forward to HTTP. |

### PowerShell Scripts

| Script | Role | Description |
|--------|------|-------------|
| `_install.ps1` | Post-Deploy Setup | Creates Python venv from system Python, installs 89 wheels offline, registers NSSM services for each RAG. Runs automatically after IIS deployment. |
| `Install-RagHttpService.ps1` | Service Installer | Registers a single RAG HTTP server as a Windows Service via NSSM. Configures auto-restart, logging, firewall rules. Supports `-Interactive` mode for dev. |
| `Rebuild-RagIndex.ps1` | Build Orchestrator | Full rebuild pipeline. For `Dedge-code`: clones Azure DevOps repos, exports DB2 schemas via `db2look`, converts to markdown, then calls `build_index.py`. Writes `.running` status file with PID and progress % for the C# API to poll. |
| `Fix-VenvAndRestart.ps1` | Recovery Tool | Stops all NSSM services, deletes venv, runs `_install.ps1` to recreate from wheels, restarts services. Nuclear option for corrupted venvs. |
| `Kill-HungRebuild.ps1` | Process Cleanup | Finds and kills hung `build_index.py` processes by inspecting command lines via WMI. Won't touch running service processes (`server_http.py`). |

---

## 6. Data Flow Summary

```mermaid
flowchart LR
    subgraph SOURCES["Source Documents"]
        MD["Markdown files\n(.md)"]
        PDF["PDF/DOCX\n(.pdf, .docx)"]
        DB2S["DB2 Schemas\n(db2look DDL)"]
        GIT2["Git Repos\n(Azure DevOps)"]
    end

    subgraph PROCESSING["Processing Pipeline"]
        CONV["convert_to_md.py\n→ Markdown"]
        CHUNKER["chunk.py\n→ 2400-char chunks"]
    end

    subgraph EMBEDDING["Embedding"]
        ONNX3["ONNX Runtime\nall-MiniLM-L6-v2\n→ 384-dim vectors"]
    end

    subgraph STORE["Storage"]
        CHROMA3[("ChromaDB\n.index/ on disk\nSQLite + HNSW")]
    end

    subgraph QUERY["Query Path"]
        HTTP["HTTP /query\nserver_http.py"]
        SEARCH["server.py\nsearch_db2_docs()"]
        RESULT["Top-K chunks\n+ source + distance"]
    end

    MD --> CHUNKER
    PDF --> CONV --> CHUNKER
    DB2S --> CHUNKER
    GIT2 --> CHUNKER
    CHUNKER --> ONNX3
    ONNX3 --> CHROMA3
    HTTP --> SEARCH
    SEARCH --> ONNX3
    SEARCH --> CHROMA3
    CHROMA3 --> RESULT
```

---

## 7. Port Assignments

| Port | RAG | Service Name |
|------|-----|-------------|
| 8484 | db2-docs | AiDocRag |
| 8485 | visual-cobol-docs | AiDocRagCobol |
| 8486 | Dedge-code | AiDocRagDedge |

## 8. Key Paths

| Path | Purpose |
|------|---------|
| `E:\opt\DedgeWinApps\AiDocNew-Web\` | Deployed application root |
| `E:\opt\DedgeWinApps\AiDocNew-Web\python\` | Python scripts, venv, wheels, ONNX model |
| `E:\opt\data\AiDoc.Library\` | RAG document libraries and ChromaDB indexes |
| `E:\opt\data\AiDoc.Library\rag-registry.json` | Central registry of all RAGs and their ports |
| `C:\opt\data\AllPwshLog\` | Shared log directory (PowerShell + Python) |
