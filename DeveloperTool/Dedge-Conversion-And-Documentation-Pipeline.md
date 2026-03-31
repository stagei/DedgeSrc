# Dedge conversion, rebranding & documentation pipeline

This document explains **how the current system works**, using **Mermaid** as the primary notation.  
**Single source of truth for paths:** `C:\opt\src\DedgeSrc\DeveloperTool\`

---

## 1. Big picture: three layers

```mermaid
flowchart TB
    subgraph sources["Source repositories (read-only for conversion)"]
        S1["Repos under C:\\opt\\src\\"]
        S2["FKMenyPSH _Modules + DevTools"]
    end

    subgraph config["Configuration"]
        AJ["all-projects.json\n(catalog & metadata)"]
        CJ["convertapps.json\n(currentPath → copyToPath)"]
    end

    subgraph pipeline["Automation"]
        CV["Convert-AppsToDedge.ps1"]
        CAP["Capture-CSharpAppScreenshots.ps1\n(C# web only)"]
    end

    subgraph outputs["Outputs under DeveloperTool"]
        DT["Rebranded trees\n(AiDoc, DedgePsh, DedgeAuth, …)"]
        BD["_BusinessDocs/\n*.md, competitors/, screenshots/"]
        SK["Cursor skill\ndedge-product-docs"]
    end

    S1 --> CV
    S2 --> CV
    CJ --> CV
    CV --> DT

    AJ --> BD
    CJ --> BD
    DT -.->|"optional: describe copies"| BD

    AJ --> CAP
    CAP --> BD

    BD --> SK
```

- **`all-projects.json`** — *what* products exist (name, category, stack, description). Used for documentation scope and narrative.
- **`convertapps.json`** — *where* each product is copied and transformed. Drives **only** `Convert-AppsToDedge.ps1`.
- **`Convert-AppsToDedge.ps1`** — physical **copy + rebrand**; never writes back to source paths.

---

## 2. Data flow: from JSON to folders

```mermaid
flowchart LR
    subgraph json["convertapps.json"]
        P["projects[]"]
        P --> E1["name"]
        P --> E2["currentPath"]
        P --> E3["copyToPath"]
    end

    E2 -->|"robocopy /E"| T["copyToPath tree"]
    E3 --> T

    T --> R1["Text: UNC + Fk + emails + URLs"]
    T --> R2["Rename files & dirs"]
    T --> R3["Replace dedge.ico bytes"]

    R1 --> OUT["Rebranded sandbox"]
    R2 --> OUT
    R3 --> OUT
```

Each `projects[]` entry is processed **in order**. For every entry the script:

1. Deletes the previous `copyToPath` (if present).
2. Copies from `currentPath` with **robocopy**, excluding `.git`, `bin`, `obj`, `node_modules`, etc.
3. Walks **all non-binary text files** (size ≤ 10 MB) and applies transforms.
4. Renames **files** then **directories** (deepest first) using literal find/replace rules.
5. Overwrites every `dedge.ico` with the binary from `DbExplorer\Resources\dEdge.ico`.

---

## 3. Inside one conversion: text and renames

```mermaid
flowchart TD
    A["New copy at copyToPath"] --> B["Enumerate text files"]
    B --> C{"Binary extension?"}
    C -->|yes| B
    C -->|no| D["Read UTF-8 text"]

    D --> E["Apply UncRules\n(\\\\server\\share → local Dedge paths)"]
    E --> F["Apply ContentRules\n(regex: FkAuth, FKMeny, emails, …)"]
    F --> G{"Content changed?"}
    G -->|yes| H["Write UTF-8 BOM"]
    G -->|no| B
    H --> B

    A --> I["Invoke-FileRenames"]
    I --> J["Rename files: Fk* → Dedge*"]
    J --> K["Rename directories\n(longest path first)"]
    K --> L["Invoke-IconReplacement\nall dedge.ico"]

    L --> M["Project done"]
```

**Rule categories** (conceptually):

| Bucket | Role |
|--------|------|
| **UncRules** | Map UNC shares (e.g. test server) to `DedgeSystemTools\Folders\...` |
| **ContentRules** | Regex replacements: branding, namespaces, emails → `geir.helge.starholm@dedge.no`, URLs → `www.dedge.no`, asset names (`fk.ico` → `dedge.ico`) |
| **RenameRules** | Literal substring renames on **file and folder names** |

---

## 4. DedgePsh layout (after conversion)

```mermaid
flowchart TB
    subgraph dp["DedgePsh\\"]
        CT["CodingTools scripts\n(former FKMenyPSH\\DevTools\\CodingTools)"]
        M["_Modules\\\n37 PowerShell modules"]
        DV["DevTools\\"]
    end

    subgraph dvcat["DevTools categories"]
        A1["AdminTools"]
        A2["AI"]
        A3["AzureTools"]
        A4["DatabaseTools"]
        A5["FixJobs"]
        A6["GitTools"]
        A7["InfrastructureTools"]
        A8["LegacyCodeTools"]
        A9["LogTools"]
        A10["SystemTools"]
        A11["UtilityTools"]
        A12["WebSites"]
    end

    DV --> A1
    DV --> A2
    DV --> A3
    DV --> A4
    DV --> A5
    DV --> A6
    DV --> A7
    DV --> A8
    DV --> A9
    DV --> A10
    DV --> A11
    DV --> A12
```

`convertapps.json` uses **separate entries** (e.g. `DedgePsh-Modules`, `DedgePsh-DatabaseTools`) that all land under `DedgePsh\` without duplicating the root CodingTools copy.

---

## 5. Documentation pipeline (logical phases)

```mermaid
flowchart TD
    subgraph phase1["Phase 1 — Sandbox"]
        P1["Run Convert-AppsToDedge.ps1"]
    end

    subgraph phase2["Phase 2 — Market context"]
        P2["Competitor research per product"]
        P2 --> F2["_BusinessDocs/competitors/*.md + *.json"]
    end

    subgraph phase3["Phase 3 — Product stories"]
        P3["Business-English per-product MD\n(Mermaid, no code jargon)"]
        P3 --> F3["_BusinessDocs/<Product>.md"]
    end

    subgraph phase4["Phase 4 — Master narrative"]
        P4["Merge / maintain portfolio"]
        P4 --> F4["Dedge-Business-Portfolio.md"]
    end

    subgraph phase5["Phase 5 — Evidence"]
        P5["Screenshots: browser, copies, headless C# script"]
        P5 --> F5["_BusinessDocs/screenshots/..."]
    end

    phase1 --> phase2
    phase2 --> phase3
    phase3 --> phase4
    phase4 --> phase5

    SK["Cursor skill: dedge-product-docs"] -.->|"documents intended flow"| phase2
    SK -.-> phase3
    SK -.-> phase5
```

**Idempotence (typical convention):** competitor files and per-product MD are often **skipped if the file already exists** so you do not overwrite hand-edited docs. The **conversion script** always refreshes the sandbox copy when you run it.

---

## 6. How documentation files relate to products

```mermaid
flowchart LR
    AP["all-projects.json\nprojects[].name"]

    AP --> MD1["DedgePsh-Modules.md"]
    AP --> MD2["DedgePsh-DatabaseTools.md"]
    AP --> MD3["ServerMonitor.md"]
    AP --> MDn["…"]

    AP --> CP1["competitors/ServerMonitor-competitors.json"]
    AP --> CP2["competitors/ServerMonitor-competitors.md"]

    MD1 --> BP["Dedge-Business-Portfolio.md"]
    MD2 --> BP
    MD3 --> BP
    MDn --> BP
```

Naming is **aligned to product keys** where possible; DedgePsh sub-suites use prefixes like `DedgePsh-DatabaseTools.md`.

---

## 7. C# screenshot sub-pipeline (only .NET web hosts)

PowerShell-only entries from `all-projects.json` are **out of scope** for this script.

```mermaid
sequenceDiagram
    participant S as Capture-CSharpAppScreenshots.ps1
    participant D as dotnet run
    participant E as Edge headless
    participant FS as _BusinessDocs/screenshots/CSharp

    S->>S: Pick target (csproj + port + URL paths)
    S->>D: start --urls http://127.0.0.1:PORT
    D-->>S: TCP listen
    S->>E: --screenshot=out.png URL
    E-->>FS: PNG (when successful)
    S->>D: stop process / free port
```

**Included:** e.g. AiDoc.WebNew, AutoDocJson.Web, SystemAnalyzer.Web, GenericLogHandler API, SqlMermaid web/REST, CursorDb2McpServer, FkAuth API.  
**Excluded:** libraries without Kestrel (`DedgeCommon`), GitHist, CursorRulesLibrary, all `DedgePsh-*` PowerShell suites, Python/PHP/static-only entries.

See `PIPELINE-CONTINUATION-STATE.md` for **known screenshot reliability issues** and next fixes.

---

## 8. Cursor skill vs scripts

```mermaid
flowchart LR
    U["User: /dedgedocs or chat instruction"]
    U --> AG["Cursor agent reads SKILL.md"]
    AG --> R1["Run or verify Convert-AppsToDedge.ps1"]
    AG --> R2["Research + write docs"]
    AG --> R3["Run Capture-CSharpAppScreenshots.ps1\nor browser tools"]

    R1 --> DT["DeveloperTool output"]
    R2 --> DT
    R3 --> DT
```

The skill is **orchestration documentation** for the agent; the **executable** conversion is always `Convert-AppsToDedge.ps1` + `convertapps.json`.

---

## 9. Adding a new product (checklist)

```mermaid
flowchart TD
    A["New repo or folder under C:\\opt\\src"] --> B["Add object to all-projects.json\n(name, category, path, stack, description)"]
    B --> C["Add object to convertapps.json\n(currentPath, copyToPath, name)"]
    C --> D["Run Convert-AppsToDedge.ps1"]
    D --> E["Create competitors + product MD\n(if not using skip-if-exists workflow)"]
    E --> F["Update Dedge-Business-Portfolio.md"]
    F --> G["Optional: extend Capture-CSharpAppScreenshots.ps1\nif .NET web app"]
```

---

## 10. File map (quick reference)

```mermaid
flowchart TB
    ROOT["DeveloperTool\\"]

    ROOT --> CA["Convert-AppsToDedge.ps1"]
    ROOT --> CAP["Capture-CSharpAppScreenshots.ps1"]
    ROOT --> APJ["all-projects.json"]
    ROOT --> CPJ["convertapps.json"]
    ROOT --> ST["PIPELINE-CONTINUATION-STATE.md"]
    ROOT --> DG["Dedge-Conversion-And-Documentation-Pipeline.md"]

    ROOT --> BD["_BusinessDocs\\"]
    BD --> BP["Dedge-Business-Portfolio.md"]
    BD --> CM["*.md per product"]
    BD --> CO["competitors\\"]
    BD --> SC["screenshots\\"]

    ROOT --> DP["DedgePsh\\"]
    ROOT --> OTH["Other copied apps\nAiDoc.WebNew, DedgeAuth, …"]
```

---

*End of pipeline overview. For live troubleshooting and resume checkpoints, use `PIPELINE-CONTINUATION-STATE.md`.*

---

## Cursor integration (same folder)

- **Rule:** `.cursor/rules/dedge-developer-tool-pipeline.mdc` — applies when matching pipeline paths.
- **Command:** `.cursor/commands/dedge-pipeline.md` — use **`/dedge-pipeline`** in chat (subcommands: `help`, `state`, `diagram`, `convert`, `screenshots`, `docs`).
