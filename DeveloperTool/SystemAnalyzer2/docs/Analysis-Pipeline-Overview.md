# Analysis Pipeline Overview

Visual overview of the SystemAnalyzer analysis pipeline — from seed input to web visualization.

## End-to-End Flow

```mermaid
flowchart TB
    subgraph INPUT["Input"]
        SEED["all.json<br/>Seed program list<br/>(menu screens + batch jobs)"]
        PROFILES["AnalysisProfiles/<br/>KD_Korn, CobDok,<br/>FkKonto, Vareregister"]
    end

    PROFILES -.->|"provides"| SEED

    subgraph TRIGGER["Trigger Methods"]
    
        direction LR
        CLI["Run-Analysis.ps1<br/>(CLI)"]
        WEB["Web UI<br/>POST /api/job/start"]
        BATCH["SystemAnalyzer.Batch<br/>(C# process spawner)"]
    end

    SEED --> CLI
    SEED --> WEB
    WEB --> BATCH

    CLI --> PIPE
    BATCH --> PIPE

    PIPE["Invoke-FullAnalysis.ps1<br/>(8-phase pipeline)"]

    subgraph DATASOURCES["External Data Sources"]
        direction LR
        SRC["COBOL Source Tree<br/>cbl/*.CBL, cpy/*.CPY"]
        RAG["Dedge Code RAG<br/>:8486"]
        VCRAG["Visual COBOL RAG<br/>:8485"]
        DB2["DB2 Catalog<br/>BASISTST via ODBC"]
        MCP["CursorDb2McpServer<br/>(HTTP fallback)"]
        OLLAMA["Ollama AI<br/>qwen2.5:7b"]
        ADOC["AutoDocJson<br/>Pre-parsed program data"]
    end

    DB2 -.->|"fallback"| MCP
    DATASOURCES --> PIPE

    CACHE["AnalysisCommon/Objects/<br/>Cached extraction + AI facts<br/>+ table metadata"]
    PIPE <-->|"read / write"| CACHE
    NAMING["AnalysisCommon/Naming/<br/>TableNames, ColumnNames,<br/>ProgramNames"]
    PIPE <-->|"read / write"| NAMING
    PROTOCOLS["AnalysisStatic/AiProtocols/<br/>Prompt templates + contracts"]
    PROTOCOLS -.->|"governs AI calls"| PIPE

    PIPE --> OUTPUT

    subgraph OUTPUT["Output: AnalysisResults/{alias}/"]
        direction LR
        TP["all_total_programs.json"]
        CG["all_call_graph.json"]
        ST["all_sql_tables.json"]
        CE["all_copy_elements.json"]
        FI["all_file_io.json"]
        DM["dependency_master.json"]
        SV["source_verification.json"]
        D2V["db2_table_validation.json"]
    end

    OUTPUT --> WEBUI["Web UI<br/>graph.html"]

    style PIPE fill:#d4a373,color:#000,stroke:#bc6c25,stroke-width:2px
    style SEED fill:#2d6a4f,color:#fff
    style WEBUI fill:#40916c,color:#fff
    style CACHE fill:#457b9d,color:#fff,stroke:#1d3557,stroke-width:2px
    style PROTOCOLS fill:#6c757d,color:#fff
```

## Pre-run cleanup and publish targets (SystemAnalyzer2)

- **Default** (`CleanBeforeRun`, on unless `--no-clean-before-run`): before creating a new `_History` run folder, removes prior **published** outputs for the alias at each distinct results root: all `*.json` and `*.md` in `{root}/{alias}/`, and the `{root}/{alias}/autodoc/` tree. **`_History` is kept.**
- **AnalysisCommon2**: when the profile declares `databases` for multi-DB discovery, `AnalysisCommon2/Databases/*.json` is deleted before re-export (same default).
- **Dual publish**: the latest run is copied to **both** `DataRoot/{alias}` and `AnalysisResultsRoot/{alias}` when those paths differ, so the web API (which reads `AnalysisResultsRoot`) stays aligned with batch history under `DataRoot`.
- **AutoDoc in web**: `GET /api/autodoc/{file}?alias={alias}` resolves `{AnalysisResultsRoot}/{alias}/autodoc/{file}` and `{DataRoot}/{alias}/autodoc/{file}` before the central `AutoDocJsonPath`.
- **Technology catalog in web**: `GET /api/technology/analysis/{alias}` returns `wwwroot/data/supported-technologies.json` plus profile technology rows from `all.json` (and `profileDatabases`).

## The 8-Phase Pipeline

```mermaid
flowchart TD
    P1["<b>Phase 1 — Load & Index</b><br/>Read all.json seed list<br/>Index COBOL source tree<br/>(cblIndex, copyIndex, fullIndex)"]
    P2["<b>Phase 2 — Extract Seed Dependencies</b><br/>For each seed program, extract:<br/>CALL targets, SQL tables,<br/>COPY elements, File I/O"]
    P3["<b>Phase 3 — CALL Expansion</b><br/>Iteratively analyze newly discovered<br/>CALL targets (up to 5 rounds)<br/>until no new programs found"]
    P4["<b>Phase 4 — DB2 Validation</b><br/>Validate every SQL table name<br/>against SYSCAT.TABLES via ODBC"]
    P5["<b>Phase 5 — Table Discovery (RAG)</b><br/>For each table, ask RAG:<br/>'Which other programs use this table?'<br/>Add undiscovered programs"]
    P6["<b>Phase 6 — Extract New Dependencies</b><br/>Run Phase 2 extraction on<br/>programs discovered in Phase 5"]
    P7["<b>Phase 7 — Verify & Classify</b><br/>1. Source verification (.CBL exists?)<br/>2. Standard COBOL filter (RAG+Ollama)<br/>3. Rule-based classification<br/>4. COBDOK metadata enrichment"]
    P8["<b>Phase 8a-e — Produce Output</b><br/>Serialize all data to JSON files"]
    P8F["<b>Phase 8f — Naming Pipeline</b><br/>Context-enriched Ollama calls:<br/>CamelCase table/column/program names<br/>+ FK inference"]
    P8P["<b>Phase 8 — Publish</b><br/>Copy to alias folder + _History"]

    P1 --> P2
    P2 --> P3
    P3 --> P4
    P4 --> P5
    P5 --> P6
    P6 --> P7
    P7 --> P8
    P8 --> P8F
    P8F --> P8P

    style P1 fill:#264653,color:#fff
    style P2 fill:#2a9d8f,color:#fff
    style P3 fill:#e9c46a,color:#000
    style P4 fill:#f4a261,color:#000
    style P5 fill:#e76f51,color:#fff
    style P6 fill:#e76f51,color:#fff
    style P7 fill:#264653,color:#fff
    style P8 fill:#2a9d8f,color:#fff
    style P8F fill:#1d4e89,color:#fff
    style P8P fill:#40916c,color:#fff
```

## Phase 2–3: Dependency Extraction Detail

```mermaid
flowchart LR
    SRC["COBOL Program<br/>(e.g. RUHBEHK.CBL)"]

    SRC --> CACHECHK{"Objects/ cache<br/>hash matches?"}
    CACHECHK -->|"HIT"| CACHED["Return cached<br/>extraction"]
    CACHECHK -->|"MISS"| SOURCES

    subgraph SOURCES["Data Source Priority (on cache miss)"]
        direction TB
        S1["1. Local .CBL files<br/>(regex parsing)"]
        S2["2. RAG semantic search<br/>(HTTP query)"]
        S3["3. AutoDocJson<br/>(pre-parsed cache)"]
        S1 --> S2
        S2 --> S3
    end

    SOURCES --> CALL["CALL Targets<br/>CALL 'RUHVAL1'"]
    SOURCES --> SQL["SQL Operations<br/>EXEC SQL SELECT FROM<br/>DBM.TILGKORN"]
    SOURCES --> COPY["COPY Elements<br/>COPY CPYDATA"]
    SOURCES --> FIO["File I/O<br/>ASSIGN TO<br/>'N:\COBNT\KORNRAP'"]

    FIO --> OL["Ollama AI<br/>Resolves variable-based<br/>filenames"]

    CALL --> SAVECACHE["Save to<br/>Objects/ cache"]
    SQL --> SAVECACHE
    COPY --> SAVECACHE
    OL --> SAVECACHE

    style SRC fill:#6c757d,color:#fff
    style CACHECHK fill:#e9c46a,color:#000
    style CACHED fill:#2a9d8f,color:#fff
    style CALL fill:#457b9d,color:#fff
    style SQL fill:#e63946,color:#fff
    style COPY fill:#a8dadc,color:#000
    style FIO fill:#f1faee,color:#000
    style OL fill:#9b2226,color:#fff
    style SAVECACHE fill:#457b9d,color:#fff
```

## Phase 3: Iterative CALL Expansion

```mermaid
flowchart TD
    SEED["~120 seed programs<br/>(from all.json)"]
    SEED -->|"Phase 2"| ROUND0["Extract CALL targets"]
    ROUND0 -->|"new programs found"| R1["Iteration 1<br/>~42 new programs"]
    R1 -->|"their CALL targets"| R2["Iteration 2<br/>~15 new programs"]
    R2 --> R3["Iteration 3<br/>~3 new programs"]
    R3 --> R4["Iteration 4<br/>0 new programs — STOP"]
    R4 --> TOTAL["Total: ~180 programs"]

    style SEED fill:#264653,color:#fff
    style R4 fill:#2a9d8f,color:#fff
    style TOTAL fill:#40916c,color:#fff
```

## Phase 7: Verification & Classification

```mermaid
flowchart TD
    PROGS["All discovered programs<br/>(~200+)"]

    PROGS --> SV["Source Verification<br/>Does .CBL exist?<br/>(includes U/V fuzzy matching)"]
    PROGS --> STD["Standard COBOL Filter<br/>RAG + Ollama identify<br/>utility vs business programs"]
    PROGS --> CLS["Rule-Based Classification<br/>RUH* = Korn maintenance<br/>RSK* = Seed/KD<br/>etc."]
    PROGS --> COB["COBDOK Enrichment<br/>modul.csv metadata<br/>system, sub-system,<br/>UTGATT (deprecated)"]

    SV --> OUT["Classified & Verified<br/>Program Set"]
    STD --> OUT
    CLS --> OUT
    COB --> OUT

    style PROGS fill:#6c757d,color:#fff
    style OUT fill:#2a9d8f,color:#fff
```

## Output File Relationships

```mermaid
flowchart LR
    DM["dependency_master.json<br/>(complete superset)"]

    DM --> TP["all_total_programs.json<br/>Programs + metadata"]
    DM --> CG["all_call_graph.json<br/>Caller → Callee edges"]
    DM --> ST["all_sql_tables.json<br/>Table refs + operations"]
    DM --> CE["all_copy_elements.json<br/>Copybook cross-refs"]
    DM --> FI["all_file_io.json<br/>File I/O mappings"]

    SV["source_verification.json"] -.-> TP
    D2["db2_table_validation.json"] -.-> ST
    SC["standard_cobol_filtered.json"] -.-> TP

    subgraph "Web UI reads"
        TP
        CG
        ST
        CE
        FI
        SV
        D2
    end

    style DM fill:#d4a373,color:#000,stroke:#bc6c25,stroke-width:2px
```

## AnalysisCommon — Object Cache Layer

The pipeline uses a persistent cache (`AnalysisCommon/Objects/`) to avoid redundant work.
Since the COBOL source being analyzed is legacy code that rarely changes, each program only
needs to be fully extracted and AI-analyzed once.

### Cache-First Extraction

```mermaid
flowchart TD
    START["Extract-ProgramDependencies(PROGRAM)"]
    START --> RESOLVE["Resolve source path<br/>Read source text"]
    RESOLVE --> HASH["Compute SHA256<br/>of source text"]
    HASH --> CHECK{"Objects/{PROGRAM}.cbl.json<br/>extraction.sourceHash<br/>matches?"}
    CHECK -->|"hash matches"| HIT["Return cached extraction<br/>(skip regex + Ollama)"]
    CHECK -->|"no match or<br/>no cache"| EXTRACT["Full extraction:<br/>Get-CopyElements<br/>Get-SqlOperations<br/>Get-CallTargets<br/>Get-FileIO<br/>Resolve-VariableFilenames"]
    EXTRACT --> SAVE["Save extraction + hash<br/>to Objects/ cache"]
    SAVE --> RETURN["Return result"]
    HIT --> RETURN

    style HIT fill:#2a9d8f,color:#fff
    style EXTRACT fill:#e76f51,color:#fff
    style CHECK fill:#e9c46a,color:#000
```

### Accumulated Facts Per Object

Each `Objects/{NAME}.{type}.json` file accumulates facts from different pipeline steps.
A fact is only computed if it is not already present in the cached file.

```mermaid
flowchart LR
    subgraph ObjectFile["RUHBEHK.cbl.json"]
        direction TB
        EX["<b>extraction</b><br/>copyElements, sqlOperations,<br/>callTargets, fileIO,<br/>sourceHash, sourcePath"]
        SC["<b>isStandardCobol</b><br/>YES/NO verdict,<br/>RAG evidence"]
        CL["<b>classification</b><br/>program role (main-ui,<br/>batch, webservice, etc.)"]
        VF["<b>variableFilenames</b><br/>resolved ASSIGN paths<br/>per logical file name"]
    end

    P2["Phase 2/3/6<br/>Extraction"] -->|"adds"| EX
    P7S["Post-Phase-7<br/>Standard Filter"] -->|"adds"| SC
    P7C["Phase 7<br/>Classification"] -->|"adds"| CL
    P2V["Within Extraction<br/>Ollama resolution"] -->|"adds"| VF

    style ObjectFile fill:#264653,color:#fff
    style EX fill:#2a9d8f,color:#fff
    style SC fill:#457b9d,color:#fff
    style CL fill:#6c757d,color:#fff
    style VF fill:#9b2226,color:#fff
```

### Element Type Suffixes

Files use a dot-suffix to disambiguate elements with the same base name:

```mermaid
flowchart LR
    subgraph Objects["AnalysisCommon/Objects/"]
        direction TB
        CBL["AAADATO<b>.cbl</b>.json<br/>COBOL program"]
        CPB["ADRNY<b>.cpb</b>.json<br/>Copybook"]
        DCL["3KUN<b>.dcl</b>.json<br/>SQL declare"]
        SQT["ADRI<b>.sqltable</b>.json<br/>SQL table"]
        FIL["TILGJVAREREG<b>.file</b>.json<br/>File I/O target"]
    end

    style CBL fill:#2a9d8f,color:#fff
    style CPB fill:#a8dadc,color:#000
    style DCL fill:#e63946,color:#fff
    style SQT fill:#f4a261,color:#000
    style FIL fill:#f1faee,color:#000
```

### AI Protocols

Prompt templates and response contracts are stored in `AnalysisStatic/AiProtocols/`:

| Protocol File | Purpose | AI Model |
|---|---|---|
| `Cbl-VariableFilenames.mdc` | Resolve variable ASSIGN paths from COBOL source | Ollama (qwen2.5:7b) |
| `Cbl-StandardProgramFilter.mdc` | Determine if a program is standard COBOL or application code | RAG + Ollama |
| `Cbl-ProgramClassification.mdc` | Classify program role (UI, batch, service, utility) | Rule-based (future: AI) |

Each `.mdc` file defines the prompt template, expected JSON response format, examples,
and model guidance. These protocols enable upgrading individual facts with more capable
models (e.g. Claude Opus) without re-running the full pipeline.

### Table Metadata Cache (Objects/*.sqltable.json)

During Phase 4, when tables are validated against DB2, the pipeline also bulk-fetches
full catalog metadata (table comments, column names/types/comments, explicit foreign keys)
and caches it per table. After Phase 6, newly discovered tables are also cached.

```mermaid
flowchart TD
    P4["Phase 4: DB2 Validation"]
    P4 --> BULK["Bulk fetch from DB2<br/>SYSCAT.TABLES + COLUMNS + REFERENCES"]
    BULK --> CHECK{"Objects/{TABLE}.sqltable.json<br/>exists?"}
    CHECK -->|"YES"| SKIP["Skip (already cached)"]
    CHECK -->|"NO"| SAVE["Write .sqltable.json<br/>schemas, type, remarks,<br/>all columns, explicit FKs"]
    P6["After Phase 6"] --> CHECK2{"New tables<br/>from RAG discovery?"}
    CHECK2 -->|"YES"| CHECK

    style BULK fill:#f4a261,color:#000
    style SAVE fill:#2a9d8f,color:#fff
    style SKIP fill:#6c757d,color:#fff
```

### Naming Cache (AnalysisCommon/Naming/)

AI-generated modern names are stored in three subfolders:

```mermaid
flowchart LR
    subgraph Naming["AnalysisCommon/Naming/"]
        direction TB
        TN["<b>TableNames/</b><br/>CamelCase C# class names<br/>per DB2 table"]
        CN["<b>ColumnNames/</b><br/>CamelCase property names<br/>+ English descriptions<br/>+ inferred FK relationships"]
        PN["<b>ProgramNames/</b><br/>Descriptive C# project names<br/>per COBOL program"]
    end

    P8F["Phase 8f<br/>Naming Pipeline"] --> Naming

    style Naming fill:#264653,color:#fff
    style TN fill:#1d4e89,color:#fff
    style CN fill:#1d4e89,color:#fff
    style PN fill:#1d4e89,color:#fff
    style P8F fill:#d4a373,color:#000
```

### Phase 8f: Modern CamelCase Naming Pipeline

Phase 8f runs after the file I/O output (8e) and before the run summary. It uses a
three-layer architecture to produce context-aware names:

```mermaid
flowchart TD
    subgraph L1["Layer 1: DB2 Metadata Cache"]
        META["Read Objects/*.sqltable.json<br/>Table schemas, columns, FKs"]
    end

    subgraph L2["Layer 2: Cross-Table Context"]
        COL["Column-to-tables index<br/>(KUNDNR → KUNDE, A_ORDREHODE, FAKTURA...)"]
        USAGE["Table-usage-by-programs map<br/>(which programs use each table)"]
        CALLEDBY["CalledBy map<br/>(reverse call graph)"]
        RAG["RAG enrichment<br/>Dedge-code snippets<br/>showing JOIN patterns"]
    end

    subgraph L3["Layer 3: Ollama Naming"]
        TBL["Table naming<br/>Ollama → CamelCase class name + namespace"]
        COLS["Column naming + FK inference<br/>Ollama → property names + descriptions<br/>+ FK confidence levels"]
        PROG["Program naming<br/>Ollama → C# project name + namespace"]
    end

    L1 --> L2
    L2 --> L3
    L3 --> INJECT["Inject into<br/>dependency_master.json<br/>futureProjectName,<br/>futureTableName,<br/>tableNaming section"]

    style L1 fill:#264653,color:#fff
    style L2 fill:#457b9d,color:#fff
    style L3 fill:#2a9d8f,color:#fff
    style INJECT fill:#d4a373,color:#000
```

### FK Inference Signals

For each column, three signals are combined to determine foreign key relationships:

| Signal | Source | Confidence |
|--------|--------|------------|
| Explicit DB2 FK | SYSCAT.REFERENCES | `high` |
| Column name match + RAG JOIN evidence | Cross-table index + Dedge-code RAG | `high` |
| Column name match + consistent type | Cross-table index + SYSCAT.COLUMNS | `medium` |
| Column name match only | Cross-table index | `low` |

### Naming AI Protocols

| Protocol File | Purpose | Input Context |
|---|---|---|
| `Naming-TableNames.mdc` | CamelCase C# class name per table | Table remarks, columns, program usage, RAG snippets |
| `Naming-ColumnNames.mdc` | CamelCase property names + FK inference | Column metadata, cross-table index, explicit FKs, RAG JOINs |
| `Naming-ProgramNames.mdc` | Descriptive C# project name per program | Classification, COBDOK, tables used, call graph, RAG |

### Cache Interaction With the Pipeline

```mermaid
sequenceDiagram
    participant P as Pipeline
    participant C as Objects Cache
    participant S as COBOL Source
    participant AI as Ollama / RAG

    P->>S: Read source text
    P->>P: Compute SHA256 hash
    P->>C: Check extraction.sourceHash
    alt Hash matches
        C-->>P: Return cached extraction
        Note over P: Skip regex + Ollama
    else No cache or hash differs
        P->>S: Parse with regex
        P->>AI: Resolve variable filenames
        P->>C: Save extraction + hash
    end

    P->>C: Check isStandardCobol
    alt Fact exists
        C-->>P: Return cached verdict
    else Missing
        P->>AI: RAG query + Ollama classify
        P->>C: Save isStandardCobol fact
    end

    P->>C: Check classification
    alt Fact exists
        C-->>P: Return cached classification
    else Missing
        P->>P: Apply rule-based classification
        P->>C: Save classification fact
    end
```

## Deployment Modes

```mermaid
flowchart TB
    subgraph LOCAL["Run-Local.ps1 — Developer Mode"]
        direction LR
        K["Kestrel<br/>localhost:5042"]
        K -->|"reads"| LR1["C:\opt\src\SystemAnalyzer\<br/>AnalysisResults\"]
        LR1 --- LN["No auth required<br/>No server dependencies<br/>Data in repo<br/>No batch pipeline"]
    end

    subgraph DEPLOYED["Build-And-Publish.ps1 — Server Mode"]
        direction LR
        IIS["IIS<br/>dedge-server"]
        IIS -->|"reads"| SR["C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\<br/>SystemAnalyzer\AnalysisResults\"]
        SR --- SN["DedgeAuth login required<br/>Full batch pipeline<br/>RAG + DB2 + Ollama<br/>Network share data"]
    end

    subgraph ANALYSIS["Run-Analysis.ps1"]
        direction LR
        RA["Direct mode<br/>Output → server UNC"]
        RL["Local mode (-LocalExecution)<br/>Output → C:\temp\<br/>then sync to server"]
    end

    ANALYSIS -->|"produces results for"| DEPLOYED
    LOCAL -.->|"ships with<br/>pre-built results"| LR1

    style LOCAL fill:#1b4332,color:#fff
    style DEPLOYED fill:#264653,color:#fff
    style ANALYSIS fill:#d4a373,color:#000
```

## History & Versioning

```mermaid
flowchart TD
    RUN["Pipeline Run<br/>(Phase 8)"]

    RUN -->|"1. create timestamped copy"| HIST["_History/<br/>KD_Korn_20260324_000552/<br/>(immutable snapshot)"]

    RUN -->|"2. overwrite alias folder"| ALIAS["KD_Korn/<br/>(latest results)"]

    RUN -->|"3. update index"| IDX["analyses.json<br/>(run history + metadata)"]

    ALIAS -->|"served by"| API["Web API<br/>GET /api/data/{alias}/{file}"]
    IDX -->|"served by"| LIST["Web API<br/>GET /api/analysis/list"]

    style RUN fill:#d4a373,color:#000,stroke:#bc6c25,stroke-width:2px
    style ALIAS fill:#2a9d8f,color:#fff
    style HIST fill:#6c757d,color:#fff
```
