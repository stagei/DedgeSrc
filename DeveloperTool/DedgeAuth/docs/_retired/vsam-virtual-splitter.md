# Virtual VSAM Splitter – Dual-Target CRUD Architecture

## Overview

This document describes two architectural approaches for COBOL programs accessing data:

1. **Traditional** – COBOL program reads/writes a VSAM file directly.
2. **Virtual VSAM Splitter** – A transparent middleware layer that presents a standard VSAM interface to the COBOL program while simultaneously performing identical CRUD operations on both a VSAM file **and** a DB2 table.

The splitter allows development teams to migrate from VSAM to DB2 incrementally – or run both in parallel – without changing existing COBOL application code.

---

## 1. Traditional COBOL → VSAM

```mermaid
flowchart LR
    subgraph Mainframe
        COBOL["COBOL Program"]
        VSAM[("VSAM File\n(KSDS / ESDS / RRDS)")]
    end

    COBOL -- "OPEN / READ / WRITE\nREWRITE / DELETE / CLOSE" --> VSAM

    style COBOL fill:#4a90d9,color:#fff,stroke:#2a5a8a
    style VSAM fill:#f5a623,color:#fff,stroke:#c47d12
```

### CRUD Operations (Traditional)

| Operation | COBOL Verb       | VSAM Action            |
|-----------|------------------|------------------------|
| **C**reate | `WRITE`         | Insert record into VSAM dataset |
| **R**ead   | `READ` / `START` | Sequential or keyed read |
| **U**pdate | `REWRITE`       | Update record in place  |
| **D**elete | `DELETE`         | Logically remove record |

In this model the COBOL program owns the full I/O lifecycle. Any downstream system that needs the same data must read the VSAM file separately or receive a batch extract.

---

## 2. Virtual VSAM Splitter Architecture

```mermaid
flowchart TB
    subgraph Mainframe
        COBOL["COBOL Program\n(unchanged source)"]

        subgraph Splitter["Virtual VSAM Splitter"]
            direction TB
            API["VSAM-Compatible\nI/O Interface"]
            ENGINE["Dual-Write Engine"]
            SYNC["Sync & Conflict\nResolver"]
        end

        VSAM[("VSAM File\n(KSDS / ESDS / RRDS)")]
        DB2[("DB2 Table")]
    end

    COBOL -- "OPEN / READ / WRITE\nREWRITE / DELETE / CLOSE" --> API
    API --> ENGINE
    ENGINE -- "VSAM I/O verbs" --> VSAM
    ENGINE -- "SQL INSERT / SELECT\nUPDATE / DELETE" --> DB2
    SYNC -. "consistency check" .-> VSAM
    SYNC -. "consistency check" .-> DB2

    style COBOL fill:#4a90d9,color:#fff,stroke:#2a5a8a
    style API fill:#7b68ee,color:#fff,stroke:#5a4abf
    style ENGINE fill:#7b68ee,color:#fff,stroke:#5a4abf
    style SYNC fill:#7b68ee,color:#fff,stroke:#5a4abf
    style Splitter fill:#e8e0ff,stroke:#7b68ee,stroke-width:2px
    style VSAM fill:#f5a623,color:#fff,stroke:#c47d12
    style DB2 fill:#50c878,color:#fff,stroke:#2e8b57
```

### How It Works

1. **COBOL program** issues standard VSAM I/O verbs (`OPEN`, `READ`, `WRITE`, `REWRITE`, `DELETE`, `CLOSE`).
2. The **Virtual VSAM Splitter** intercepts these calls via the VSAM-Compatible I/O Interface. From the COBOL program's perspective, it is talking to a normal VSAM file.
3. The **Dual-Write Engine** translates each COBOL verb into two parallel operations:
   - Native VSAM I/O against the original dataset.
   - Equivalent SQL statement against the DB2 table.
4. The **Sync & Conflict Resolver** periodically validates that both targets remain consistent.

---

## 3. CRUD Mapping – Splitter Detail

```mermaid
flowchart LR
    subgraph COBOL Verb
        W["WRITE record"]
        R["READ record"]
        RW["REWRITE record"]
        D["DELETE record"]
    end

    subgraph Splitter["Virtual VSAM Splitter"]
        SW["Split WRITE"]
        SR["Split READ"]
        SRW["Split REWRITE"]
        SD["Split DELETE"]
    end

    subgraph VSAM Target
        VW["VSAM WRITE"]
        VR["VSAM READ"]
        VRW["VSAM REWRITE"]
        VD["VSAM DELETE"]
    end

    subgraph DB2 Target
        DI["INSERT INTO table"]
        DS["SELECT FROM table"]
        DU["UPDATE table"]
        DD["DELETE FROM table"]
    end

    W --> SW
    R --> SR
    RW --> SRW
    D --> SD

    SW --> VW
    SW --> DI

    SR --> VR
    SR --> DS

    SRW --> VRW
    SRW --> DU

    SD --> VD
    SD --> DD

    style SW fill:#7b68ee,color:#fff
    style SR fill:#7b68ee,color:#fff
    style SRW fill:#7b68ee,color:#fff
    style SD fill:#7b68ee,color:#fff
```

| COBOL Verb | VSAM Operation | DB2 Equivalent | Notes |
|------------|---------------|----------------|-------|
| `WRITE`    | Insert record into dataset | `INSERT INTO table (cols) VALUES (...)` | Key mapped from VSAM record key |
| `READ`     | Keyed or sequential read   | `SELECT ... FROM table WHERE key = ?`   | Splitter can choose primary source |
| `REWRITE`  | Update record in place     | `UPDATE table SET ... WHERE key = ?`    | Must hold current record position |
| `DELETE`   | Logically remove record    | `DELETE FROM table WHERE key = ?`       | Cascading rules configurable |
| `START`    | Position cursor            | `SELECT ... WHERE key >= ? ORDER BY key`| Browse / range scan |
| `CLOSE`    | Close dataset              | `COMMIT` (if auto-commit off)           | Ensures DB2 transaction finality |

---

## 4. Sequence – Write Operation Through the Splitter

```mermaid
sequenceDiagram
    participant COBOL as COBOL Program
    participant Splitter as Virtual VSAM Splitter
    participant VSAM as VSAM File
    participant DB2 as DB2 Table

    COBOL->>Splitter: WRITE record
    activate Splitter

    par VSAM Write
        Splitter->>VSAM: WRITE record (native I/O)
        VSAM-->>Splitter: STATUS = 00 (success)
    and DB2 Insert
        Splitter->>DB2: INSERT INTO table VALUES (...)
        DB2-->>Splitter: SQLCODE = 0 (success)
    end

    alt Both succeed
        Splitter-->>COBOL: FILE STATUS = 00
    else One or both fail
        Splitter->>Splitter: Rollback / compensate
        Splitter-->>COBOL: FILE STATUS = error code
    end

    deactivate Splitter
```

---

## 5. Sequence – Read Operation Through the Splitter

```mermaid
sequenceDiagram
    participant COBOL as COBOL Program
    participant Splitter as Virtual VSAM Splitter
    participant VSAM as VSAM File
    participant DB2 as DB2 Table

    COBOL->>Splitter: READ record (key = K)
    activate Splitter

    alt Primary source = VSAM
        Splitter->>VSAM: READ record (key = K)
        VSAM-->>Splitter: Record data + STATUS 00
    else Primary source = DB2
        Splitter->>DB2: SELECT * FROM table WHERE key = K
        DB2-->>Splitter: Result row + SQLCODE 0
    end

    Splitter-->>COBOL: Record data + FILE STATUS 00
    deactivate Splitter

    Note over Splitter: Primary source is configurable.<br/>Default: VSAM (preserves legacy behavior).
```

---

## 6. Deployment Modes

The splitter supports three runtime modes, allowing teams to migrate at their own pace:

```mermaid
flowchart TB
    subgraph Mode1["Mode 1 – VSAM Only (bypass)"]
        C1["COBOL"] --> S1["Splitter\n(pass-through)"] --> V1[("VSAM")]
    end

    subgraph Mode2["Mode 2 – Dual Write (migration)"]
        C2["COBOL"] --> S2["Splitter\n(dual-write)"]
        S2 --> V2[("VSAM")]
        S2 --> D2[("DB2")]
    end

    subgraph Mode3["Mode 3 – DB2 Only (target state)"]
        C3["COBOL"] --> S3["Splitter\n(DB2 only)"] --> D3[("DB2")]
    end

    Mode1 -. "Enable dual-write" .-> Mode2
    Mode2 -. "Decommission VSAM" .-> Mode3

    style Mode1 fill:#fff3e0,stroke:#f5a623
    style Mode2 fill:#e8e0ff,stroke:#7b68ee
    style Mode3 fill:#e0f5e8,stroke:#50c878
```

| Mode | VSAM Active | DB2 Active | Use Case |
|------|:-----------:|:----------:|----------|
| **1 – VSAM Only** | Yes | No | Legacy baseline; splitter is transparent pass-through |
| **2 – Dual Write** | Yes | Yes | Migration period; both targets receive all CRUD ops |
| **3 – DB2 Only** | No | Yes | Target state; VSAM decommissioned, COBOL code unchanged |

---

## 7. Key Benefits

- **Zero COBOL code changes** – The program continues issuing standard VSAM I/O verbs.
- **Incremental migration** – Teams switch from Mode 1 → 2 → 3 at their own pace.
- **Parallel validation** – In Mode 2, data in VSAM and DB2 can be compared to verify correctness before cutting over.
- **Programmer choice** – Individual applications can independently choose VSAM, dual-write, or DB2-only via configuration, not code changes.
- **Rollback safety** – If DB2 issues arise, switch back to Mode 1 instantly.

---

## 8. Configuration Example (JCL / Splitter Config)

```text
* Virtual VSAM Splitter configuration
SPLITTER.MODE        = DUAL          * VSAM | DUAL | DB2
SPLITTER.PRIMARY.SRC = VSAM          * Primary read source: VSAM | DB2
SPLITTER.VSAM.DSN    = PROD.CUST.MASTER
SPLITTER.DB2.SUBSYS  = DB2P
SPLITTER.DB2.TABLE   = SCHEMA1.CUSTOMER
SPLITTER.DB2.COMMIT  = AUTO          * AUTO | MANUAL
SPLITTER.SYNC.CHECK  = ENABLED       * ENABLED | DISABLED
SPLITTER.SYNC.FREQ   = 1000          * Check consistency every N operations
```

The COBOL program's JCL `DD` statement points to the splitter rather than the raw VSAM dataset. The splitter reads its own configuration and routes I/O accordingly.
