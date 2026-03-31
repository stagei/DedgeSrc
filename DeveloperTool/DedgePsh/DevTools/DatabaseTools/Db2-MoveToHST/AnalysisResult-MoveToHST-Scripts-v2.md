# Analysis: Db2-MoveToHST — BASISPRO to BASISHST Data Migration

**Author:** Geir Helge Starholm, www.dEdge.no  
**Created:** 2026-03-10  
**Technology:** DB2 LUW  
**Scope:** BASISPRO → BASISHST only (BASISRAP retrievals excluded)  

---

## Overview

This document describes the **data archival process** from BASISPRO (production) to BASISHST (history). It is derived from 53 legacy scripts spanning 20+ years, distilled into parameterized patterns ready for automation.

All year-specific values, avdeling numbers, and file paths from the legacy scripts have been replaced with parameters.

---

## Architecture: How Data Flows from BASISPRO to BASISHST

```
BASISPRO (Production)
    │
    │  1. SELECT with date-based filter
    │     Compute INT(date_column/10000) as AAR column
    │
    ▼
BASISHST (History Database)
    │
    │  2. Verify row counts match
    │
    ▼
BASISPRO
    │
    │  3. DELETE from source (children first, parent last)
    │
    ▼
BASISPRO data volume reduced
```

### Key Design Pattern

All BASISHST tables have an extra column **`AAR`** (year, `DECIMAL(4,0)`) as the **first column** in the primary key. This column does not exist in the source BASISPRO tables. The migration step computes the year from a date field using `INT(date_column/10000)` and prepends it to the row.

---

## Data Domains Being Archived

### 1. Sales Orders (Ordrer) — The Primary Use Case

| Source Table (BASISPRO) | Target Table (BASISHST) | Description |
|---|---|---|
| `DBM.ORDREHODE` | `DBM.H_ORDREHODE` | Order headers |
| `DBM.ORDRELINJER` | `DBM.H_ORDRELINJER` | Order lines |
| `DBM.ORDREMERKNAD` | `DBM.H_ORDREMERKNAD` | Order remarks |
| `DBM.LASS` | `DBM.LASS` | Load/shipment records |
| `DBM.VAREBEVEGELSE` | `DBM.VAREBEVEGELSE` | Inventory movements |
| `DBM.KORRIGERINGER` | `DBM.KORRIGERINGER` | Stock corrections |

**Year partitioning:** `TILFAKTDATO` (invoice date) → `INT(TILFAKTDATO/10000)` = year

### 2. Archive Orders (AH_Ordrer) — COBOL-batch archive orders

| Source Table (BASISPRO) | Target Table (BASISHST) | Description |
|---|---|---|
| `DBM.AH_ORDREHODE` | `DBM.AH_ORDREHODE` | Archive order headers |
| `DBM.AH_ORDRELINJER` | `DBM.AH_ORDRELINJER` | Archive order lines |
| `DBM.H_VERKSTEDHODE` | `DBM.H_VERKSTEDHODE` | Workshop headers |
| `DBM.H_VERKSTED_TIMER` | `DBM.H_VERKSTED_TIMER` | Workshop hours |
| `DBM.H_VERKSTEDTEKST` | `DBM.H_VERKSTEDTEKST` | Workshop text |

**Year partitioning:** `OPPRETTET_DATO` → `INT(OPPRETTET_DATO/10000)` = year

### 3. Purchase Orders (Bestillinger)

| Source Table (BASISPRO) | Target Table (BASISHST) | Description |
|---|---|---|
| `DBM.A_BESTHODE` | `DBM.AH_BESTHODE` + `DBM.H_BESTHODE` | Purchase order headers |
| `DBM.A_BESTLIN` | `DBM.AH_BESTLIN` + `DBM.H_BESTLIN` | Purchase order lines |
| `DBM.A_VIHODE` | `DBM.AH_VIHODE` + `DBM.H_VIHODE` | Goods receipt headers |
| `DBM.A_VILIN` | `DBM.AH_VILIN` + `DBM.H_VILIN` | Goods receipt lines |
| `DBM.INNGANG_FAKO` | `DBM.H_INNGANG_FAKO` | Invoice matching |

**Year partitioning:** `ORDREDATO` / `INNGDATO` → `INT(date/10000)` = year

### 4. Invoicing (Fakturering)

| Source Table (BASISPRO) | Target Table (BASISHST) | Description |
|---|---|---|
| `DBM.H_FAKT_ORDREHODE` | `DBM.H_FAKT_ORDREHODE` | Invoice order headers |
| `DBM.H_FAKT_ORDRELINJER` | `DBM.H_FAKT_ORDRELINJER` | Invoice order lines |

**Year partitioning:** `FAKTDATO_SENTRAL` → `INT(FAKTDATO_SENTRAL/10000)` = year

### 5. Visma Transactions

| Source Table (BASISPRO) | Target Table (BASISHST) | Description |
|---|---|---|
| `DBM.VISMA_TRANSER` | `DBM.VISMA_TRANSER` (period tables) | Accounting transactions to Visma |

**Year partitioning:** `BILAGSDATO` → `INT(BILAGSDATO/10000)` = year

### 6. Cash Register Transactions (Kassetransaksjoner)

| Source Table (BASISPRO) | Target Table (BASISHST) | Description |
|---|---|---|
| `DBM.KASS_TRANSER` | `DBM.H_KASS_TRANSER` | Cash register transactions |

**Year partitioning:** _(date column needs verification from BASISPRO schema)_

---

## DDL: BASISHST Target Table Structures

These define the BASISHST target tables. Every table mirrors its BASISPRO source but has `AAR DECIMAL(4,0)` prepended as the first PK column.

| DDL File | Tables Created |
|---|---|
| `CREOPTIMA.SQL` | `H_ORDREHODE`, `H_ORDRELINJER`, `H_ORDREMERKNAD`, `LASS`, `VAREBEVEGELSE` |
| `CREKORR.SQL` | `KORRIGERINGER` |
| `cre_H_fakt.sql` | `H_FAKT_ORDREHODE`, `H_FAKT_ORDRELINJER` |
| `sjekktab` | `H_INNGANG_FAKO`, `INNGANG_FAKO` |

### Example: H_ORDREHODE DDL (from CREOPTIMA.SQL)

```sql
CREATE TABLE DBM.H_ORDREHODE (
  AAR                DECIMAL     (4,0)     NOT NULL WITH DEFAULT 0.0,
  -- ... all columns from BASISPRO.DBM.ORDREHODE follow ...
    PRIMARY KEY(AAR, AVDNR, ORDRENR)
  ) ;
CREATE INDEX DBM.H_ORDRENR_IX       ON DBM.H_ORDREHODE (ORDRENR);
CREATE INDEX DBM.HHODE_KUNDENR      ON DBM.H_ORDREHODE (KUNDENR, AAR);
CREATE INDEX DBM.H_INIT_ORDRENR_IX  ON DBM.H_ORDREHODE (INIT_ORDRENR);
```

### Example: H_ORDRELINJER DDL (from CREOPTIMA.SQL)

```sql
CREATE TABLE DBM.H_ORDRELINJER (
  AAR                DECIMAL     (4,0)     NOT NULL WITH DEFAULT 0.0,
  -- ... all columns from BASISPRO.DBM.ORDRELINJER follow ...
    PRIMARY KEY(AAR, AVDNR, ORDRENR, LINJENR),
    FOREIGN KEY ORDREHOD (AAR, AVDNR, ORDRENR)
      REFERENCES  DBM.H_ORDREHODE        ON DELETE CASCADE
  ) ;
```

### Example: KORRIGERINGER DDL (from CREKORR.SQL)

```sql
CREATE TABLE DBM.KORRIGERINGER (
  AAR                DECIMAL     (4,0)     NOT NULL WITH DEFAULT 0.0,
  AVDNR              DECIMAL     (6,0)     NOT NULL WITH DEFAULT 0.0,
  KORRNR             DECIMAL     (5,0)     NOT NULL WITH DEFAULT 0.0,
  KORRDATO           DECIMAL     (8,0)     NOT NULL WITH DEFAULT 0.0,
  -- ... remaining stock correction fields ...
    PRIMARY KEY(AAR, AVDNR, KORRNR, LINJENR)
  ) ;
```

### Note: VAREBEVEGELSE is the exception

`VAREBEVEGELSE` in BASISHST does **not** have an AAR column. Its primary key is the same as in BASISPRO:

```sql
PRIMARY KEY(AVDNR, FKNR, TIDSPUNKT, TRANSKODE, FRA_LAGERSTED, TIL_LAGERSTED)
```

---

## Schema Validation (Critical Pre-Step)

Before any migration, column counts must be compared between BASISPRO and BASISHST. BASISHST tables should have exactly **one more column** (AAR) than BASISPRO, except VAREBEVEGELSE which has the same count.

### Parameterized Schema Check

```sql
-- Run against BASISPRO
SELECT 'BASISPRO' AS DB, SUBSTR(TABNAME,1,32) AS TABNAME, COUNT(*) AS COL_COUNT
FROM SYSCAT.COLUMNS
WHERE TABSCHEMA = 'DBM'
  AND TABNAME IN (
    'ORDREHODE','ORDRELINJER','ORDREMERKNAD',
    'LASS','VAREBEVEGELSE','KORRIGERINGER',
    'AH_ORDREHODE','AH_ORDRELINJER',
    'H_VERKSTEDHODE','H_VERKSTED_TIMER','H_VERKSTEDTEKST',
    'A_BESTHODE','A_BESTLIN','A_VIHODE','A_VILIN',
    'INNGANG_FAKO',
    'H_FAKT_ORDREHODE','H_FAKT_ORDRELINJER',
    'AH_BESTHODE','AH_BESTLIN',
    'H_BESTHODE','H_BESTLIN',
    'AH_VIHODE','AH_VILIN',
    'H_VIHODE','H_VILIN',
    'H_INNGANG_FAKO'
  )
GROUP BY TABNAME
ORDER BY TABNAME;

-- Run against BASISHST (same query)
-- Expected: each table has source_col_count + 1 (for AAR)
-- Exception: VAREBEVEGELSE has same count (no AAR)
```

### ALTER TABLE Scripts (Schema Evolution)

When BASISPRO gets new columns, BASISHST must be updated to match. Legacy examples:

| DDL File | Purpose |
|---|---|
| `alter.sql` | Adds `VAREGR` to `KORRIGERINGER` |
| `alter_ordreh` | Renames `NOTAV` → `NOTAV_GML`, adds new `NOTAV CHAR(8)` to `H_ORDREHODE` |
| `alter20120707` | Batch addition of columns to `AH_BESTHODE`, `H_BESTHODE`, `AH_BESTLIN`, `H_BESTLIN`, `AH_VIHODE`, `AH_VILIN`, `H_VILIN` |

---

## Extraction SELECT Patterns (Parameterized)

All parameters use `@` prefix notation. Replace with actual values at runtime.

### Domain 1: Sales Orders (H_ORDRE)

**ORDREHODE** — headers:

```sql
SELECT INT(H.TILFAKTDATO/10000) AS AAR, H.*
FROM DBM.ORDREHODE H
WHERE H.TILFAKTDATO BETWEEN @StartDate AND @EndDate;
```

**ORDRELINJER** — lines (joined to header for date filter):

```sql
SELECT INT(H.TILFAKTDATO/10000) AS AAR, L.*
FROM DBM.ORDREHODE H, DBM.ORDRELINJER L
WHERE H.AVDNR = L.AVDNR
  AND H.ORDRENR = L.ORDRENR
  AND H.TILFAKTDATO BETWEEN @StartDate AND @EndDate;
```

**ORDREMERKNAD** — remarks:

```sql
SELECT INT(H.TILFAKTDATO/10000) AS AAR, M.*
FROM DBM.ORDREHODE H, DBM.ORDREMERKNAD M
WHERE H.AVDNR = M.AVDNR
  AND H.ORDRENR = M.ORDRENR
  AND H.TILFAKTDATO BETWEEN @StartDate AND @EndDate;
```

**LASS** — load/shipment (independent date):

```sql
SELECT INT(L.KJØREDATO/10000) AS AAR, L.*
FROM DBM.LASS L
WHERE L.KJØREDATO BETWEEN @StartDate AND @EndDate;
```

**VAREBEVEGELSE** — inventory movements (no AAR):

```sql
SELECT V.*
FROM DBM.VAREBEVEGELSE V
WHERE V.LAGERDATO BETWEEN @StartDate AND @EndDate;
```

**KORRIGERINGER** — stock corrections:

```sql
SELECT INT(K.KORRDATO/10000) AS AAR, K.*
FROM DBM.KORRIGERINGER K
WHERE K.KORRDATO BETWEEN @StartDate AND @EndDate;
```

### Domain 2: Archive Orders (AH_ORDRE)

**AH_ORDREHODE** — headers:

```sql
SELECT INT(H.OPPRETTET_DATO/10000) AS AAR, H.*
FROM DBM.AH_ORDREHODE H
WHERE H.OPPRETTET_DATO BETWEEN @StartDate AND @EndDate;
```

**AH_ORDRELINJER** — lines (joined to header for date filter):

```sql
SELECT INT(H.OPPRETTET_DATO/10000) AS AAR, L.*
FROM DBM.AH_ORDREHODE H, DBM.AH_ORDRELINJER L
WHERE H.AVDNR = L.AVDNR
  AND H.ORDRENR = L.ORDRENR
  AND H.OPPRETTET_DATO BETWEEN @StartDate AND @EndDate;
```

**H_VERKSTEDHODE** — workshop headers:

```sql
SELECT INT(H.OPPRETTET_DATO/10000) AS AAR, M.*
FROM DBM.AH_ORDREHODE H, DBM.H_VERKSTEDHODE M
WHERE H.AVDNR = M.AVDNR
  AND H.ORDRENR = M.ORDRENR
  AND H.OPPRETTET_DATO BETWEEN @StartDate AND @EndDate;
```

**H_VERKSTED_TIMER** — workshop hours:

```sql
SELECT INT(H.OPPRETTET_DATO/10000) AS AAR, M.*
FROM DBM.AH_ORDREHODE H, DBM.H_VERKSTED_TIMER M
WHERE H.AVDNR = M.AVDNR
  AND H.ORDRENR = M.ORDRENR
  AND H.OPPRETTET_DATO BETWEEN @StartDate AND @EndDate;
```

**H_VERKSTEDTEKST** — workshop text:

```sql
SELECT INT(H.OPPRETTET_DATO/10000) AS AAR, M.*
FROM DBM.AH_ORDREHODE H, DBM.H_VERKSTEDTEKST M
WHERE H.AVDNR = M.AVDNR
  AND H.ORDRENR = M.ORDRENR
  AND H.OPPRETTET_DATO BETWEEN @StartDate AND @EndDate;
```

### Domain 3: Purchase Orders (Bestillinger)

**A_BESTHODE** — purchase order headers:

```sql
SELECT INT(A.ORDREDATO/10000) AS AAR, A.*
FROM DBM.A_BESTHODE A
WHERE A.ORDREDATO BETWEEN @StartDate AND @EndDate
  AND A.ORDRESTATUS IN ('IA');
```

**A_BESTLIN** — purchase order lines:

```sql
SELECT INT(A.ORDREDATO/10000) AS AAR, L.*
FROM DBM.A_BESTHODE A, DBM.A_BESTLIN L
WHERE A.ORDRENR = L.ORDRENR
  AND A.ORDREDATO BETWEEN @StartDate AND @EndDate
  AND A.ORDRESTATUS IN ('IA');
```

**A_VIHODE** — goods receipt headers:

```sql
SELECT INT(H.INNGDATO/10000) AS AAR, H.*
FROM DBM.A_VIHODE H
WHERE H.INNGDATO BETWEEN @StartDate AND @EndDate
  AND ((H.ORDRENR = 0)
    OR (EXISTS (SELECT 1 FROM DBM.A_BESTHODE B
        WHERE H.ORDRENR = B.ORDRENR
          AND (B.ORDRESTATUS IN ('IA') OR VINNGSTATUS = 'VF'))));
```

**A_VILIN** — goods receipt lines:

```sql
SELECT INT(H.INNGDATO/10000) AS AAR, L.*
FROM DBM.A_VIHODE H, DBM.A_VILIN L
WHERE H.AVDNR = L.AVDNR
  AND H.INNGANGNR = L.INNGANGNR
  AND H.INNGDATO BETWEEN @StartDate AND @EndDate
  AND ((H.ORDRENR = 0)
    OR (EXISTS (SELECT 1 FROM DBM.A_BESTHODE B
        WHERE H.ORDRENR = B.ORDRENR
          AND (B.ORDRESTATUS IN ('IA') OR VINNGSTATUS = 'VF'))));
```

**INNGANG_FAKO** — invoice matching:

```sql
SELECT INT(F.INNG_DATO/10000) AS AAR, F.*
FROM DBM.INNGANG_FAKO F
WHERE F.INNG_DATO BETWEEN @StartDate AND @EndDate;
```

### Domain 4: Invoicing (H_FAKT)

**H_FAKT_ORDREHODE** — invoice headers:

```sql
SELECT INT(H.FAKTDATO_SENTRAL/10000) AS AAR, H.*
FROM DBM.H_FAKT_ORDREHODE H
WHERE H.FAKTDATO_SENTRAL BETWEEN @StartDate AND @EndDate;
```

**H_FAKT_ORDRELINJER** — invoice lines:

```sql
SELECT INT(H.FAKTDATO_SENTRAL/10000) AS AAR, L.*
FROM DBM.H_FAKT_ORDREHODE H, DBM.H_FAKT_ORDRELINJER L
WHERE H.AVDNR = L.AVDNR
  AND H.ORDRENR = L.ORDRENR
  AND H.FAKTDATO_SENTRAL BETWEEN @StartDate AND @EndDate;
```

### Domain 5: Visma Transactions

```sql
SELECT V.*
FROM DBM.VISMA_TRANSER V
WHERE V.BILAGSDATO BETWEEN @StartDate AND @EndDate;
```

### Domain 6: Cash Register Transactions

```sql
-- Date column name needs verification from BASISPRO schema
SELECT K.*
FROM DBM.KASS_TRANSER K
WHERE K.{DATE_COLUMN} BETWEEN @StartDate AND @EndDate;
```

---

## Candidate Selection Queries

These queries find rows in BASISPRO that are eligible for archival. The `@CutoffDate` parameter controls the age threshold (typically: data older than 2 full calendar years).

```sql
-- @CutoffDate example: (YEAR(CURRENT DATE) - 2) * 10000 + 1231
-- i.e., everything up to and including Dec 31 two years ago
```

### Sales Orders

```sql
SELECT INT(H.TILFAKTDATO/10000) AS AAR, COUNT(*) AS ROW_COUNT
FROM DBM.ORDREHODE H
WHERE H.TILFAKTDATO > 0
  AND H.TILFAKTDATO <= @CutoffDate
GROUP BY INT(H.TILFAKTDATO/10000)
ORDER BY AAR;
```

### Archive Orders

```sql
SELECT INT(OPPRETTET_DATO/10000) AS AAR, COUNT(*) AS ROW_COUNT
FROM DBM.AH_ORDREHODE
WHERE OPPRETTET_DATO > 0
  AND OPPRETTET_DATO <= @CutoffDate
GROUP BY INT(OPPRETTET_DATO/10000)
ORDER BY AAR;
```

### Purchase Orders

```sql
SELECT INT(ORDREDATO/10000) AS AAR, COUNT(*) AS ROW_COUNT
FROM DBM.A_BESTHODE
WHERE ORDRESTATUS IN ('IA')
  AND ORDREDATO > 0
  AND ORDREDATO <= @CutoffDate
GROUP BY INT(ORDREDATO/10000)
ORDER BY AAR;
```

### Goods Receipts

```sql
SELECT INT(INNGDATO/10000) AS AAR, COUNT(*) AS ROW_COUNT
FROM DBM.A_VIHODE H
WHERE INNGDATO > 0
  AND INNGDATO <= @CutoffDate
  AND ((ORDRENR = 0)
    OR (EXISTS (SELECT 1 FROM DBM.A_BESTHODE B
        WHERE H.ORDRENR = B.ORDRENR
          AND (B.ORDRESTATUS IN ('IA') OR VINNGSTATUS = 'VF'))))
GROUP BY INT(INNGDATO/10000)
ORDER BY AAR;
```

### Invoicing

```sql
SELECT INT(FAKTDATO_SENTRAL/10000) AS AAR, COUNT(*) AS ROW_COUNT
FROM DBM.H_FAKT_ORDREHODE
WHERE FAKTDATO_SENTRAL > 0
  AND FAKTDATO_SENTRAL <= @CutoffDate
GROUP BY INT(FAKTDATO_SENTRAL/10000)
ORDER BY AAR;
```

### Visma Transactions

```sql
SELECT INT(BILAGSDATO/10000) AS AAR, COUNT(*) AS ROW_COUNT
FROM DBM.VISMA_TRANSER
WHERE BILAGSDATO > 0
  AND BILAGSDATO <= @CutoffDate
GROUP BY INT(BILAGSDATO/10000)
ORDER BY AAR;
```

---

## Delete Patterns (Parameterized)

Deletes are executed **after verified transfer**. Children are deleted before parents. Large deletes should be chunked by quarter to avoid lock escalation.

### Domain 1: Sales Orders

```sql
-- 1. Remarks (child)
DELETE FROM DBM.ORDREMERKNAD M
WHERE EXISTS (SELECT 1 FROM DBM.ORDREHODE H
  WHERE H.AVDNR = M.AVDNR AND H.ORDRENR = M.ORDRENR
    AND H.TILFAKTDATO BETWEEN @StartDate AND @EndDate);

-- 2. Lines (child)
DELETE FROM DBM.ORDRELINJER L
WHERE EXISTS (SELECT 1 FROM DBM.ORDREHODE H
  WHERE H.AVDNR = L.AVDNR AND H.ORDRENR = L.ORDRENR
    AND H.TILFAKTDATO BETWEEN @StartDate AND @EndDate);

-- 3. Headers (parent)
DELETE FROM DBM.ORDREHODE H
WHERE H.TILFAKTDATO BETWEEN @StartDate AND @EndDate;

-- 4. Independent tables (own date columns)
DELETE FROM DBM.LASS
WHERE KJØREDATO BETWEEN @StartDate AND @EndDate;

DELETE FROM DBM.VAREBEVEGELSE
WHERE LAGERDATO BETWEEN @StartDate AND @EndDate;

DELETE FROM DBM.KORRIGERINGER
WHERE KORRDATO BETWEEN @StartDate AND @EndDate;
```

### Domain 2: Archive Orders

```sql
-- 1. Workshop text (child)
DELETE FROM DBM.H_VERKSTEDTEKST M
WHERE EXISTS (SELECT 1 FROM DBM.AH_ORDREHODE H
  WHERE H.AVDNR = M.AVDNR AND H.ORDRENR = M.ORDRENR
    AND H.OPPRETTET_DATO BETWEEN @StartDate AND @EndDate);

-- 2. Workshop hours (child)
DELETE FROM DBM.H_VERKSTED_TIMER M
WHERE EXISTS (SELECT 1 FROM DBM.AH_ORDREHODE H
  WHERE H.AVDNR = M.AVDNR AND H.ORDRENR = M.ORDRENR
    AND H.OPPRETTET_DATO BETWEEN @StartDate AND @EndDate);

-- 3. Workshop headers (child)
DELETE FROM DBM.H_VERKSTEDHODE M
WHERE EXISTS (SELECT 1 FROM DBM.AH_ORDREHODE H
  WHERE H.AVDNR = M.AVDNR AND H.ORDRENR = M.ORDRENR
    AND H.OPPRETTET_DATO BETWEEN @StartDate AND @EndDate);

-- 4. Order lines (child)
DELETE FROM DBM.AH_ORDRELINJER L
WHERE EXISTS (SELECT 1 FROM DBM.AH_ORDREHODE H
  WHERE H.AVDNR = L.AVDNR AND H.ORDRENR = L.ORDRENR
    AND H.OPPRETTET_DATO BETWEEN @StartDate AND @EndDate);

-- 5. Order headers (parent)
DELETE FROM DBM.AH_ORDREHODE H
WHERE H.OPPRETTET_DATO BETWEEN @StartDate AND @EndDate;
```

### Domain 3: Purchase Orders

```sql
-- 1. Receipt lines (child)
DELETE FROM DBM.A_VILIN L
WHERE EXISTS (SELECT 1 FROM DBM.A_VIHODE H
  WHERE L.AVDNR = H.AVDNR AND L.INNGANGNR = H.INNGANGNR
    AND H.INNGDATO BETWEEN @StartDate AND @EndDate
    AND ((H.ORDRENR = 0)
      OR (EXISTS (SELECT 1 FROM DBM.A_BESTHODE B
          WHERE H.ORDRENR = B.ORDRENR
            AND (B.ORDRESTATUS IN ('IA') OR VINNGSTATUS = 'VF')))));

-- 2. Receipt headers (parent)
DELETE FROM DBM.A_VIHODE H
WHERE H.INNGDATO BETWEEN @StartDate AND @EndDate
  AND ((H.ORDRENR = 0)
    OR (EXISTS (SELECT 1 FROM DBM.A_BESTHODE B
        WHERE H.ORDRENR = B.ORDRENR
          AND (B.ORDRESTATUS IN ('IA') OR VINNGSTATUS = 'VF'))));

-- 3. Purchase order lines (child)
DELETE FROM DBM.A_BESTLIN L
WHERE EXISTS (SELECT 1 FROM DBM.A_BESTHODE A
  WHERE A.ORDRENR = L.ORDRENR
    AND A.ORDREDATO BETWEEN @StartDate AND @EndDate
    AND A.ORDRESTATUS IN ('IA'));

-- 4. Purchase order headers (parent)
DELETE FROM DBM.A_BESTHODE A
WHERE A.ORDREDATO BETWEEN @StartDate AND @EndDate
  AND A.ORDRESTATUS IN ('IA');

-- 5. Invoice matching
DELETE FROM DBM.INNGANG_FAKO F
WHERE F.INNG_DATO BETWEEN @StartDate AND @EndDate;
```

### Domain 4: Invoicing

```sql
-- 1. Lines (child, FK CASCADE exists in DDL)
DELETE FROM DBM.H_FAKT_ORDRELINJER L
WHERE EXISTS (SELECT 1 FROM DBM.H_FAKT_ORDREHODE H
  WHERE H.AVDNR = L.AVDNR AND H.ORDRENR = L.ORDRENR
    AND H.FAKTDATO_SENTRAL BETWEEN @StartDate AND @EndDate);

-- 2. Headers (parent)
DELETE FROM DBM.H_FAKT_ORDREHODE H
WHERE H.FAKTDATO_SENTRAL BETWEEN @StartDate AND @EndDate;
```

### Domain 5: Visma Transactions

```sql
DELETE FROM DBM.VISMA_TRANSER
WHERE BILAGSDATO BETWEEN @StartDate AND @EndDate;
```

### Chunked Delete Strategy

For large result sets, split deletes into monthly or quarterly chunks:

```sql
-- Instead of full-year delete:
-- DELETE FROM table WHERE date_col BETWEEN @Year*10000+0101 AND @Year*10000+1231

-- Chunk by quarter:
DELETE FROM table WHERE date_col BETWEEN @Year*10000+0101 AND @Year*10000+0331;
DELETE FROM table WHERE date_col BETWEEN @Year*10000+0401 AND @Year*10000+0630;
DELETE FROM table WHERE date_col BETWEEN @Year*10000+0701 AND @Year*10000+0930;
DELETE FROM table WHERE date_col BETWEEN @Year*10000+1001 AND @Year*10000+1231;
```

---

## Verification Queries

After INSERT into BASISHST, verify row counts match before deleting from BASISPRO.

### Count in BASISPRO (source)

```sql
SELECT COUNT(*) AS SOURCE_COUNT
FROM DBM.{SOURCE_TABLE}
WHERE {DATE_COLUMN} BETWEEN @StartDate AND @EndDate;
```

### Count in BASISHST (target via nickname or direct)

```sql
SELECT COUNT(*) AS TARGET_COUNT
FROM {BASISHST_TABLE_OR_NICKNAME}
WHERE AAR = @Year;
```

### Verification rule

- `TARGET_COUNT` must equal `SOURCE_COUNT`
- If BASISHST already had rows for this AAR, compare the **delta** (new count minus pre-existing count)
- Abort delete if counts do not match

---

## Complete Reference: AAR Column Derivation

| Data Domain | Source Table | Date Column | AAR Calculation | Has AAR in BASISHST? |
|---|---|---|---|---|
| Sales Orders | `ORDREHODE` | `TILFAKTDATO` | `INT(TILFAKTDATO/10000)` | Yes |
| Sales Orders | `ORDRELINJER` | _(via ORDREHODE join)_ | `INT(H.TILFAKTDATO/10000)` | Yes |
| Sales Orders | `ORDREMERKNAD` | _(via ORDREHODE join)_ | `INT(H.TILFAKTDATO/10000)` | Yes |
| Sales Orders | `LASS` | `KJØREDATO` | `INT(KJØREDATO/10000)` | Yes |
| Sales Orders | `VAREBEVEGELSE` | `LAGERDATO` | _(none — no AAR column)_ | **No** |
| Sales Orders | `KORRIGERINGER` | `KORRDATO` | `INT(KORRDATO/10000)` | Yes |
| Archive Orders | `AH_ORDREHODE` | `OPPRETTET_DATO` | `INT(OPPRETTET_DATO/10000)` | Yes |
| Archive Orders | `AH_ORDRELINJER` | _(via AH_ORDREHODE join)_ | `INT(H.OPPRETTET_DATO/10000)` | Yes |
| Archive Orders | `H_VERKSTEDHODE` | _(via AH_ORDREHODE join)_ | `INT(H.OPPRETTET_DATO/10000)` | Yes |
| Archive Orders | `H_VERKSTED_TIMER` | _(via AH_ORDREHODE join)_ | `INT(H.OPPRETTET_DATO/10000)` | Yes |
| Archive Orders | `H_VERKSTEDTEKST` | _(via AH_ORDREHODE join)_ | `INT(H.OPPRETTET_DATO/10000)` | Yes |
| Purchase Orders | `A_BESTHODE` | `ORDREDATO` | `INT(ORDREDATO/10000)` | Yes |
| Purchase Orders | `A_BESTLIN` | _(via A_BESTHODE join)_ | `INT(A.ORDREDATO/10000)` | Yes |
| Goods Receipts | `A_VIHODE` | `INNGDATO` | `INT(INNGDATO/10000)` | Yes |
| Goods Receipts | `A_VILIN` | _(via A_VIHODE join)_ | `INT(H.INNGDATO/10000)` | Yes |
| Invoice Matching | `INNGANG_FAKO` | `INNG_DATO` | `INT(INNG_DATO/10000)` | Yes |
| Invoicing | `H_FAKT_ORDREHODE` | `FAKTDATO_SENTRAL` | `INT(FAKTDATO_SENTRAL/10000)` | Yes |
| Invoicing | `H_FAKT_ORDRELINJER` | _(via H_FAKT_ORDREHODE join)_ | `INT(H.FAKTDATO_SENTRAL/10000)` | Yes |
| Visma | `VISMA_TRANSER` | `BILAGSDATO` | `INT(BILAGSDATO/10000)` | Period tables |
| Cash Register | `KASS_TRANSER` | _(needs verification)_ | _(needs verification)_ | Yes |

---

## Table Relationships and JOIN Keys

| Parent Table | Child Table | JOIN Columns | Notes |
|---|---|---|---|
| `ORDREHODE` | `ORDRELINJER` | `AVDNR, ORDRENR` | |
| `ORDREHODE` | `ORDREMERKNAD` | `AVDNR, ORDRENR` | |
| `AH_ORDREHODE` | `AH_ORDRELINJER` | `AVDNR, ORDRENR` | |
| `AH_ORDREHODE` | `H_VERKSTEDHODE` | `AVDNR, ORDRENR` | |
| `AH_ORDREHODE` | `H_VERKSTED_TIMER` | `AVDNR, ORDRENR` | |
| `AH_ORDREHODE` | `H_VERKSTEDTEKST` | `AVDNR, ORDRENR` | |
| `A_BESTHODE` | `A_BESTLIN` | `ORDRENR` | |
| `A_VIHODE` | `A_VILIN` | `AVDNR, INNGANGNR` | |
| `H_FAKT_ORDREHODE` | `H_FAKT_ORDRELINJER` | `AVDNR, ORDRENR` | FK with ON DELETE CASCADE |

**INSERT order:** Parent first, then children  
**DELETE order:** Children first, then parent

---

## Orphan Cleanup Queries

These clean up records in BASISPRO that reference orders no longer present (already moved or deleted).

### KD_KONT_ORDRE — orphaned customer account order links

```sql
DELETE FROM DBM.KD_KONT_ORDRE K
WHERE NOT EXISTS (SELECT 1 FROM DBM.ORDREHODE O
    WHERE K.AVDNR = O.AVDNR AND K.ORDRENR = O.ORDRENR)
  AND NOT EXISTS (SELECT 1 FROM DBM.H_ORDREHODE H
    WHERE K.AVDNR = H.AVDNR AND K.ORDRENR = H.ORDRENR);
```

### AH_ORDRELINJER_ENDR — orphaned order line change records

```sql
DELETE FROM DBM.AH_ORDRELINJER_ENDR E
WHERE NOT EXISTS (SELECT 1 FROM DBM.AH_ORDRELINJER L
    WHERE E.AVDNR = L.AVDNR
      AND E.ORDRENR = L.ORDRENR
      AND E.LINJENR = L.LINJENR)
  AND TIDSPUNKT < CURRENT TIMESTAMP - @RetentionDays DAYS;
```

### ORDRELINJER_VEI — orphaned weighing records

```sql
DELETE FROM DBM.ORDRELINJER_VEI
WHERE TIDSPUNKT_VB < CURRENT TIMESTAMP - @RetentionDays DAYS;
```

---

## Backup

```bat
set DB2INSTANCE=DB2HST
DB2 BACKUP DATABASE BASISHST ONLINE TO "G:\DB2HSTBACKUP"
  WITH 2 BUFFERS BUFFER 1024 PARALLELISM 1 COMPRESS
  UTIL_IMPACT_PRIORITY 50 INCLUDE LOGS WITHOUT PROMPTING
```

---

## Parameters Summary

| Parameter | Description | Example |
|---|---|---|
| `@StartDate` | First day of period (YYYYMMDD decimal) | `@Year * 10000 + 0101` |
| `@EndDate` | Last day of period (YYYYMMDD decimal) | `@Year * 10000 + 1231` |
| `@Year` | Target year for archival | `YEAR(CURRENT DATE) - 2` |
| `@CutoffDate` | Maximum date for candidate selection | `(YEAR(CURRENT DATE) - 2) * 10000 + 1231` |
| `@RetentionDays` | Days to retain orphan cleanup records | `730` (2 years) |
