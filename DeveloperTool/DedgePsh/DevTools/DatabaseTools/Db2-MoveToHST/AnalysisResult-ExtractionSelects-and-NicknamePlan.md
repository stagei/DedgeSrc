# Extraction SELECTs and Nickname-Based Continuous Migration Plan

**Author:** Geir Helge Starholm, www.dEdge.no  
**Created:** 2026-03-10  
**Technology:** DB2 LUW — Federated Nicknames  

---

## Goal

Replace the manual IXF export/import cycle with a **continuous, automated process** that:

1. **Finds candidate rows** in BASISPRO based on date criteria
2. **INSERTs directly into BASISHST** via DB2 federated nicknames (no IXF files)
3. **Verifies the transfer** (row counts, checksums)
4. **DELETEs from BASISPRO** only after confirmed success

---

## Prerequisites: Nickname Discovery

Before building the automation, query the actual nicknames in BASISPRO:

```sql
-- Run on BASISPRO (or BASISTST) to discover existing nicknames to BASISHST
SELECT SUBSTR(N.TABNAME,1,32)        AS NICKNAME_NAME,
       SUBSTR(N.REMOTE_TABLE,1,32)   AS HST_TABLE,
       SUBSTR(N.REMOTE_SCHEMA,1,10)  AS HST_SCHEMA,
       SUBSTR(N.SERVERNAME,1,20)     AS FEDERATED_SERVER,
       SUBSTR(N.TABSCHEMA,1,10)      AS LOCAL_SCHEMA
FROM SYSCAT.NICKNAMES N
WHERE N.REMOTE_TABLE LIKE 'H_%'
   OR N.REMOTE_TABLE LIKE 'AH_%'
   OR N.REMOTE_TABLE IN ('LASS','VAREBEVEGELSE','KORRIGERINGER',
                          'BEST_TIL_HIST','VISMA_TRANSER%')
ORDER BY N.TABNAME
FETCH FIRST 100 ROWS ONLY;
```

> **TODO:** Run this query via db2-query MCP when available. The nickname names used below (e.g. `DBM.HST_H_ORDREHODE`) are **placeholders** — replace with actual names from the catalog.

---

## Data Domain 1: Sales Orders (H_ORDRE)

### Source Tables and Key Relationships

```
BASISPRO                          BASISHST (via nickname)
─────────────────                 ─────────────────────────
DBM.ORDREHODE          ────►      DBM.H_ORDREHODE
  ├── DBM.ORDRELINJER  ────►        ├── DBM.H_ORDRELINJER
  └── DBM.ORDREMERKNAD ────►        └── DBM.H_ORDREMERKNAD
DBM.LASS               ────►      DBM.LASS (in HST)
DBM.VAREBEVEGELSE      ────►      DBM.VAREBEVEGELSE (in HST)
DBM.KORRIGERINGER      ────►      DBM.KORRIGERINGER (in HST)
```

### Original Export SELECTs (from the legacy scripts)

**ORDREHODE** — Header records, year derived from TILFAKTDATO:

```sql
-- Source: CREOPTIMA.SQL, fksql.impoptima2010, imp_opt_2018
-- TILFAKTDATO = invoice date in YYYYMMDD decimal format
-- INT(TILFAKTDATO/10000) extracts the year → becomes AAR column in BASISHST

EXPORT TO P:\tru\ORDREH{YEAR}.IXF OF IXF
  SELECT INT(H.TILFAKTDATO/10000), H.*
  FROM DBM.ORDREHODE H
  WHERE H.TILFAKTDATO BETWEEN {YEAR}0101 AND {YEAR}1231;
```

**ORDRELINJER** — Order lines, joined via AVDNR + ORDRENR:

```sql
EXPORT TO P:\tru\ORDREL{YEAR}.IXF OF IXF
  SELECT INT(H.TILFAKTDATO/10000), L.*
  FROM DBM.ORDREHODE H, DBM.ORDRELINJER L
  WHERE H.AVDNR = L.AVDNR
    AND H.ORDRENR = L.ORDRENR
    AND H.TILFAKTDATO BETWEEN {YEAR}0101 AND {YEAR}1231;
```

**ORDREMERKNAD** — Order remarks, joined via AVDNR + ORDRENR:

```sql
EXPORT TO P:\tru\ORDREM{YEAR}.IXF OF IXF
  SELECT INT(H.TILFAKTDATO/10000), M.*
  FROM DBM.ORDREHODE H, DBM.ORDREMERKNAD M
  WHERE H.AVDNR = M.AVDNR
    AND H.ORDRENR = M.ORDRENR
    AND H.TILFAKTDATO BETWEEN {YEAR}0101 AND {YEAR}1231;
```

**LASS** — Load/shipment records, joined via AVDNR + LASSNR through ORDRELINJER:

```sql
-- LASS has its own AAR. Year is KJØREDATO-based.
EXPORT TO P:\tru\LASS{YEAR}.IXF OF IXF
  SELECT INT(L.KJØREDATO/10000), L.*
  FROM DBM.LASS L
  WHERE L.KJØREDATO BETWEEN {YEAR}0101 AND {YEAR}1231;
```

**VAREBEVEGELSE** — Inventory movements, year from LAGERDATO:

```sql
EXPORT TO P:\tru\VAREBEV{YEAR}.IXF OF IXF
  SELECT V.*
  FROM DBM.VAREBEVEGELSE V
  WHERE V.LAGERDATO BETWEEN {YEAR}0101 AND {YEAR}1231;
```

> Note: VAREBEVEGELSE in BASISHST does **not** have an AAR column (per CREOPTIMA.SQL DDL). It is the only table without year partitioning.

**KORRIGERINGER** — Stock corrections, year from KORRDATO:

```sql
EXPORT TO P:\tru\BEHOLDKORR{YEAR}.IXF OF IXF
  SELECT INT(K.KORRDATO/10000), K.*
  FROM DBM.KORRIGERINGER K
  WHERE K.KORRDATO BETWEEN {YEAR}0101 AND {YEAR}1231;
```

### Candidate Selection Query (for continuous process)

```sql
-- Find orders in BASISPRO that are fully invoiced and old enough to archive
-- TILFAKTDATO > 0 means the order has been invoiced
-- We pick orders where the invoice date is at least 2 full years ago
SELECT COUNT(*) AS CANDIDATES,
       INT(H.TILFAKTDATO/10000) AS AAR
FROM DBM.ORDREHODE H
WHERE H.TILFAKTDATO > 0
  AND H.TILFAKTDATO < (YEAR(CURRENT DATE) - 1) * 10000 + 0101
GROUP BY INT(H.TILFAKTDATO/10000)
ORDER BY AAR;
```

### Nickname-Based INSERT (replaces export/import)

```sql
-- Step 1: INSERT headers into BASISHST via nickname
INSERT INTO DBM.HST_H_ORDREHODE
  SELECT INT(H.TILFAKTDATO/10000), H.*
  FROM DBM.ORDREHODE H
  WHERE H.TILFAKTDATO BETWEEN @StartDate AND @EndDate;

-- Step 2: INSERT lines
INSERT INTO DBM.HST_H_ORDRELINJER
  SELECT INT(H.TILFAKTDATO/10000), L.*
  FROM DBM.ORDREHODE H, DBM.ORDRELINJER L
  WHERE H.AVDNR = L.AVDNR
    AND H.ORDRENR = L.ORDRENR
    AND H.TILFAKTDATO BETWEEN @StartDate AND @EndDate;

-- Step 3: INSERT remarks
INSERT INTO DBM.HST_H_ORDREMERKNAD
  SELECT INT(H.TILFAKTDATO/10000), M.*
  FROM DBM.ORDREHODE H, DBM.ORDREMERKNAD M
  WHERE H.AVDNR = M.AVDNR
    AND H.ORDRENR = M.ORDRENR
    AND H.TILFAKTDATO BETWEEN @StartDate AND @EndDate;

-- Step 4: INSERT lass
INSERT INTO DBM.HST_LASS
  SELECT INT(L.KJØREDATO/10000), L.*
  FROM DBM.LASS L
  WHERE L.KJØREDATO BETWEEN @StartDate AND @EndDate;

-- Step 5: INSERT varebevegelse (no AAR column)
INSERT INTO DBM.HST_VAREBEVEGELSE
  SELECT V.*
  FROM DBM.VAREBEVEGELSE V
  WHERE V.LAGERDATO BETWEEN @StartDate AND @EndDate;

-- Step 6: INSERT korrigeringer
INSERT INTO DBM.HST_KORRIGERINGER
  SELECT INT(K.KORRDATO/10000), K.*
  FROM DBM.KORRIGERINGER K
  WHERE K.KORRDATO BETWEEN @StartDate AND @EndDate;
```

### Verification Queries

```sql
-- After INSERT, verify counts match on both sides
-- Run on BASISPRO:
SELECT COUNT(*) AS PRO_COUNT
FROM DBM.ORDREHODE H
WHERE H.TILFAKTDATO BETWEEN @StartDate AND @EndDate;

-- Run on BASISHST (via nickname):
SELECT COUNT(*) AS HST_COUNT
FROM DBM.HST_H_ORDREHODE
WHERE AAR = @Year;
```

### Delete from BASISPRO (after verified transfer)

```sql
-- Delete remarks first (no FK cascade from ORDREHODE in BASISPRO)
DELETE FROM DBM.ORDREMERKNAD M
WHERE EXISTS (
  SELECT 1 FROM DBM.ORDREHODE H
  WHERE H.AVDNR = M.AVDNR AND H.ORDRENR = M.ORDRENR
    AND H.TILFAKTDATO BETWEEN @StartDate AND @EndDate
);

-- Delete lines
DELETE FROM DBM.ORDRELINJER L
WHERE EXISTS (
  SELECT 1 FROM DBM.ORDREHODE H
  WHERE H.AVDNR = L.AVDNR AND H.ORDRENR = L.ORDRENR
    AND H.TILFAKTDATO BETWEEN @StartDate AND @EndDate
);

-- Delete headers last
DELETE FROM DBM.ORDREHODE H
WHERE H.TILFAKTDATO BETWEEN @StartDate AND @EndDate;

-- LASS, VAREBEVEGELSE, KORRIGERINGER deleted independently by their own date
DELETE FROM DBM.LASS WHERE KJØREDATO BETWEEN @StartDate AND @EndDate;
DELETE FROM DBM.VAREBEVEGELSE WHERE LAGERDATO BETWEEN @StartDate AND @EndDate;
DELETE FROM DBM.KORRIGERINGER WHERE KORRDATO BETWEEN @StartDate AND @EndDate;
```

---

## Data Domain 2: Archive Orders (AH_ORDRE)

### Source Tables and Key Relationships

```
BASISPRO                              BASISHST (via nickname)
─────────────────                     ─────────────────────────
DBM.AH_ORDREHODE           ────►      DBM.AH_ORDREHODE (has AAR)
  ├── DBM.AH_ORDRELINJER   ────►        ├── DBM.AH_ORDRELINJER
  ├── DBM.H_VERKSTEDHODE   ────►        ├── DBM.H_VERKSTEDHODE
  ├── DBM.H_VERKSTED_TIMER ────►        ├── DBM.H_VERKSTED_TIMER
  └── DBM.H_VERKSTEDTEKST  ────►        └── DBM.H_VERKSTEDTEKST
```

### Original Export SELECTs

The legacy process used a **two-phase approach** with a staging table:

**Phase 1 — Build candidate list** (on BASISPRO/BASISREG):

```sql
-- Source: a_exp_ordre20221113, fksql_aordre_2010.srv_erp1
-- Identify which AH_ORDREHODE rows to move based on OPPRETTET_DATO
EXPORT TO P:\tru\AH_ORDRE_FLYTTES_{YEAR}.ixf OF IXF
  SELECT INT(OPPRETTET_DATO/10000),
         AVDNR, ORDRENR,
         CURRENT TIMESTAMP, ' '
  FROM DBM.AH_ORDREHODE
  WHERE OPPRETTET_DATO BETWEEN {YEAR}0101 AND {YEAR}1231;

-- Load into staging table on BASISPRO
LOAD FROM P:\tru\AH_ORDRE_FLYTTES_{YEAR}.ixf OF IXF
  REPLACE INTO DBM.AH_ORDRE_TIL_HIST NONRECOVERABLE;
RUNSTATS ON TABLE DBM.AH_ORDRE_TIL_HIST AND INDEXES ALL;
```

**Phase 2 — Export joined data** using staging table:

```sql
-- AH_ORDREHODE with year prefix
EXPORT TO P:\tru\AH_ORDREH{YEAR}.ixf OF IXF
  SELECT {YEAR}, H.*
  FROM DBM.AH_ORDREHODE H, DBM.AH_ORDRE_TIL_HIST T
  WHERE H.AVDNR = T.AVDNR AND H.ORDRENR = T.ORDRENR;

-- AH_ORDRELINJER with year prefix
EXPORT TO P:\tru\AH_ORDREL{YEAR}.ixf OF IXF
  SELECT {YEAR}, L.*
  FROM DBM.AH_ORDRELINJER L, DBM.AH_ORDRE_TIL_HIST T
  WHERE L.AVDNR = T.AVDNR AND L.ORDRENR = T.ORDRENR;

-- H_VERKSTEDHODE with year prefix
EXPORT TO P:\tru\AH_VERKSTEDHODE{YEAR}.ixf OF IXF
  SELECT {YEAR}, M.*
  FROM DBM.H_VERKSTEDHODE M, DBM.AH_ORDRE_TIL_HIST T
  WHERE M.AVDNR = T.AVDNR AND M.ORDRENR = T.ORDRENR;

-- H_VERKSTED_TIMER with year prefix
EXPORT TO P:\tru\AH_VERKSTED_TIMER{YEAR}.ixf OF IXF
  SELECT {YEAR}, M.*
  FROM DBM.H_VERKSTED_TIMER M, DBM.AH_ORDRE_TIL_HIST T
  WHERE M.AVDNR = T.AVDNR AND M.ORDRENR = T.ORDRENR;

-- H_VERKSTEDTEKST with year prefix
EXPORT TO P:\tru\AH_VERKSTEDTEKST{YEAR}.ixf OF IXF
  SELECT {YEAR}, M.*
  FROM DBM.H_VERKSTEDTEKST M, DBM.AH_ORDRE_TIL_HIST T
  WHERE M.AVDNR = T.AVDNR AND M.ORDRENR = T.ORDRENR;
```

**Per-avdeling variant** (avd 2852 and 8039 had their own staging tables):

```sql
-- Source: exp_ordre_2852_20220508, fksql_8039_2013.erp1_meh
-- Same pattern but with AVDNR filter and separate staging table

SELECT INT(OPPRETTET_DATO/10000), AVDNR, ORDRENR, CURRENT TIMESTAMP, ' '
FROM DBM.AH_ORDREHODE
WHERE AVDNR = 2852
  AND OPPRETTET_DATO BETWEEN 20150101 AND 20151231;

-- Then join with staging table DBM.AH_ORDRE_TIL_HIST_2852 / _8039
```

### Candidate Selection Query (for continuous process)

```sql
-- Find archive orders old enough to move (2+ years old)
SELECT COUNT(*) AS CANDIDATES,
       INT(OPPRETTET_DATO/10000) AS AAR
FROM DBM.AH_ORDREHODE
WHERE OPPRETTET_DATO > 0
  AND OPPRETTET_DATO < (YEAR(CURRENT DATE) - 1) * 10000 + 0101
GROUP BY INT(OPPRETTET_DATO/10000)
ORDER BY AAR;
```

### Nickname-Based INSERT (no staging table needed)

With nicknames, the staging table approach is unnecessary — we can INSERT directly:

```sql
-- Step 1: INSERT headers
INSERT INTO DBM.HST_AH_ORDREHODE
  SELECT INT(OPPRETTET_DATO/10000), H.*
  FROM DBM.AH_ORDREHODE H
  WHERE H.OPPRETTET_DATO BETWEEN @StartDate AND @EndDate;

-- Step 2: INSERT lines (join to header for date filter)
INSERT INTO DBM.HST_AH_ORDRELINJER
  SELECT INT(H.OPPRETTET_DATO/10000), L.*
  FROM DBM.AH_ORDREHODE H, DBM.AH_ORDRELINJER L
  WHERE H.AVDNR = L.AVDNR AND H.ORDRENR = L.ORDRENR
    AND H.OPPRETTET_DATO BETWEEN @StartDate AND @EndDate;

-- Step 3: INSERT verksted hode
INSERT INTO DBM.HST_H_VERKSTEDHODE
  SELECT INT(H.OPPRETTET_DATO/10000), M.*
  FROM DBM.AH_ORDREHODE H, DBM.H_VERKSTEDHODE M
  WHERE H.AVDNR = M.AVDNR AND H.ORDRENR = M.ORDRENR
    AND H.OPPRETTET_DATO BETWEEN @StartDate AND @EndDate;

-- Step 4: INSERT verksted timer
INSERT INTO DBM.HST_H_VERKSTED_TIMER
  SELECT INT(H.OPPRETTET_DATO/10000), M.*
  FROM DBM.AH_ORDREHODE H, DBM.H_VERKSTED_TIMER M
  WHERE H.AVDNR = M.AVDNR AND H.ORDRENR = M.ORDRENR
    AND H.OPPRETTET_DATO BETWEEN @StartDate AND @EndDate;

-- Step 5: INSERT verksted tekst
INSERT INTO DBM.HST_H_VERKSTEDTEKST
  SELECT INT(H.OPPRETTET_DATO/10000), M.*
  FROM DBM.AH_ORDREHODE H, DBM.H_VERKSTEDTEKST M
  WHERE H.AVDNR = M.AVDNR AND H.ORDRENR = M.ORDRENR
    AND H.OPPRETTET_DATO BETWEEN @StartDate AND @EndDate;
```

### Delete from BASISPRO (after verified transfer)

```sql
-- Delete child tables first (join to header for date scope)

DELETE FROM DBM.H_VERKSTEDTEKST M
WHERE EXISTS (SELECT 1 FROM DBM.AH_ORDREHODE H
  WHERE H.AVDNR = M.AVDNR AND H.ORDRENR = M.ORDRENR
    AND H.OPPRETTET_DATO BETWEEN @StartDate AND @EndDate);

DELETE FROM DBM.H_VERKSTED_TIMER M
WHERE EXISTS (SELECT 1 FROM DBM.AH_ORDREHODE H
  WHERE H.AVDNR = M.AVDNR AND H.ORDRENR = M.ORDRENR
    AND H.OPPRETTET_DATO BETWEEN @StartDate AND @EndDate);

DELETE FROM DBM.H_VERKSTEDHODE M
WHERE EXISTS (SELECT 1 FROM DBM.AH_ORDREHODE H
  WHERE H.AVDNR = M.AVDNR AND H.ORDRENR = M.ORDRENR
    AND H.OPPRETTET_DATO BETWEEN @StartDate AND @EndDate);

DELETE FROM DBM.AH_ORDRELINJER L
WHERE EXISTS (SELECT 1 FROM DBM.AH_ORDREHODE H
  WHERE H.AVDNR = L.AVDNR AND H.ORDRENR = L.ORDRENR
    AND H.OPPRETTET_DATO BETWEEN @StartDate AND @EndDate);

-- Delete header last
DELETE FROM DBM.AH_ORDREHODE H
WHERE H.OPPRETTET_DATO BETWEEN @StartDate AND @EndDate;
```

---

## Data Domain 3: Purchase Orders (Bestillinger)

### Source Tables and Key Relationships

```
BASISPRO                              BASISHST (via nickname)
─────────────────                     ─────────────────────────
DBM.A_BESTHODE             ────►      DBM.AH_BESTHODE + DBM.H_BESTHODE
  └── DBM.A_BESTLIN        ────►      DBM.AH_BESTLIN  + DBM.H_BESTLIN
DBM.A_VIHODE               ────►      DBM.AH_VIHODE   + DBM.H_VIHODE
  └── DBM.A_VILIN          ────►      DBM.AH_VILIN    + DBM.H_VILIN
DBM.INNGANG_FAKO           ────►      DBM.H_INNGANG_FAKO
```

### Original Export SELECTs

The purchase order domain used the **BEST_TIL_HIST staging table** to track which orders to move. The actual export SELECTs are not preserved as `.sql` files — only the LOAD commands are in `FKSQL.besth_imp14a` and `sjekk_felter_A.sql`. The IXF filenames tell us the convention:

```
BTHI_H15B.ixf  → BEST_TIL_HIST (staging)
BEHA_H15B.ixf  → AH_BESTHODE
BELA_H15B.ixf  → AH_BESTLIN
BEH_H15B.ixf   → H_BESTHODE
BEL_H15B.ixf   → H_BESTLIN
VIHA_H15B.ixf  → AH_VIHODE
VILA_H15B.ixf  → AH_VILIN
VIH_H15B.ixf   → H_VIHODE
VIL_H15B.ixf   → H_VILIN
INFA_H15B.ixf  → H_INNGANG_FAKO
```

**Reconstructed export pattern** (based on table structure and the count script):

```sql
-- Staging: identify purchase orders ready for archival
-- Source: count (file)
SELECT INT(ORDREDATO/10000) AS AAR, A.ORDRENR, A.AVDNR,
       CURRENT TIMESTAMP, ' '
FROM DBM.A_BESTHODE A
WHERE A.ORDREDATO < {CUTOFF_DATE}
  AND A.ORDRESTATUS IN ('IA')  -- Inactive/Archived status
;

-- Export headers with year prefix
SELECT INT(A.ORDREDATO/10000), A.*
FROM DBM.A_BESTHODE A
WHERE EXISTS (SELECT 1 FROM DBM.BEST_TIL_HIST B
              WHERE B.ORDRENR = A.ORDRENR);

-- Export lines with year prefix
SELECT INT(A.ORDREDATO/10000), L.*
FROM DBM.A_BESTHODE A, DBM.A_BESTLIN L
WHERE A.ORDRENR = L.ORDRENR
  AND EXISTS (SELECT 1 FROM DBM.BEST_TIL_HIST B
              WHERE B.ORDRENR = A.ORDRENR);
```

**Goods receipt export** (from `inng_til_hist.sql` — avdnr 8039, year 2022):

```sql
-- Export receipt headers for closed/completed receipts
SELECT INT(INNGDATO/10000), H.*
FROM DBM.A_VIHODE H
WHERE AVDNR = 8039
  AND INNGDATO BETWEEN 20220101 AND 20221231
  AND ((ORDRENR = 0)
    OR (EXISTS (SELECT 1 FROM DBM.A_BESTHODE B
        WHERE H.ORDRENR = B.ORDRENR
          AND (B.ORDRESTATUS IN ('IA') OR VINNGSTATUS = 'VF'))));

-- Export receipt lines
SELECT INT(H.INNGDATO/10000), L.*
FROM DBM.A_VIHODE H, DBM.A_VILIN L
WHERE H.AVDNR = 8039
  AND H.INNGDATO BETWEEN 20220101 AND 20221231
  AND ((H.ORDRENR = 0)
    OR (EXISTS (SELECT 1 FROM DBM.A_BESTHODE B
        WHERE H.ORDRENR = B.ORDRENR
          AND (ORDRESTATUS IN ('IA') OR VINNGSTATUS = 'VF'))))
  AND H.AVDNR = L.AVDNR
  AND H.INNGANGNR = L.INNGANGNR;
```

### Candidate Selection Query

```sql
-- Purchase orders: find completed/inactive orders older than cutoff
SELECT COUNT(*) AS CANDIDATES,
       INT(ORDREDATO/10000) AS AAR
FROM DBM.A_BESTHODE
WHERE ORDRESTATUS IN ('IA')
  AND ORDREDATO > 0
  AND ORDREDATO < (YEAR(CURRENT DATE) - 1) * 10000 + 0101
GROUP BY INT(ORDREDATO/10000)
ORDER BY AAR;

-- Goods receipts: find completed receipts older than cutoff
SELECT COUNT(*) AS CANDIDATES,
       INT(INNGDATO/10000) AS AAR
FROM DBM.A_VIHODE H
WHERE INNGDATO > 0
  AND INNGDATO < (YEAR(CURRENT DATE) - 1) * 10000 + 0101
  AND ((ORDRENR = 0)
    OR (EXISTS (SELECT 1 FROM DBM.A_BESTHODE B
        WHERE H.ORDRENR = B.ORDRENR
          AND (B.ORDRESTATUS IN ('IA') OR VINNGSTATUS = 'VF'))))
GROUP BY INT(INNGDATO/10000)
ORDER BY AAR;
```

### Nickname-Based INSERT

```sql
-- Purchase order headers → two target tables in BASISHST
INSERT INTO DBM.HST_AH_BESTHODE
  SELECT INT(A.ORDREDATO/10000), A.*
  FROM DBM.A_BESTHODE A
  WHERE A.ORDREDATO BETWEEN @StartDate AND @EndDate
    AND A.ORDRESTATUS IN ('IA');

INSERT INTO DBM.HST_AH_BESTLIN
  SELECT INT(A.ORDREDATO/10000), L.*
  FROM DBM.A_BESTHODE A, DBM.A_BESTLIN L
  WHERE A.ORDRENR = L.ORDRENR
    AND A.ORDREDATO BETWEEN @StartDate AND @EndDate
    AND A.ORDRESTATUS IN ('IA');

-- Goods receipt headers
INSERT INTO DBM.HST_AH_VIHODE
  SELECT INT(H.INNGDATO/10000), H.*
  FROM DBM.A_VIHODE H
  WHERE H.INNGDATO BETWEEN @StartDate AND @EndDate
    AND ((H.ORDRENR = 0)
      OR (EXISTS (SELECT 1 FROM DBM.A_BESTHODE B
          WHERE H.ORDRENR = B.ORDRENR
            AND (B.ORDRESTATUS IN ('IA') OR VINNGSTATUS = 'VF'))));

-- Goods receipt lines
INSERT INTO DBM.HST_AH_VILIN
  SELECT INT(H.INNGDATO/10000), L.*
  FROM DBM.A_VIHODE H, DBM.A_VILIN L
  WHERE H.AVDNR = L.AVDNR AND H.INNGANGNR = L.INNGANGNR
    AND H.INNGDATO BETWEEN @StartDate AND @EndDate
    AND ((H.ORDRENR = 0)
      OR (EXISTS (SELECT 1 FROM DBM.A_BESTHODE B
          WHERE H.ORDRENR = B.ORDRENR
            AND (B.ORDRESTATUS IN ('IA') OR VINNGSTATUS = 'VF'))));

-- Invoice matching
INSERT INTO DBM.HST_H_INNGANG_FAKO
  SELECT INT(F.INNG_DATO/10000), F.*
  FROM DBM.INNGANG_FAKO F
  WHERE F.INNG_DATO BETWEEN @StartDate AND @EndDate;
```

### Delete from BASISPRO

```sql
-- Delete receipt lines first (quarterly chunks from legacy script)
DELETE FROM DBM.A_VILIN L
WHERE EXISTS (SELECT 1 FROM DBM.A_VIHODE H
  WHERE L.AVDNR = H.AVDNR AND L.INNGANGNR = H.INNGANGNR
    AND H.INNGDATO BETWEEN @StartDate AND @EndDate
    AND ((H.ORDRENR = 0)
      OR (EXISTS (SELECT 1 FROM DBM.A_BESTHODE B
          WHERE H.ORDRENR = B.ORDRENR
            AND (B.ORDRESTATUS IN ('IA') OR VINNGSTATUS = 'VF')))));

-- Delete receipt headers
DELETE FROM DBM.A_VIHODE H
WHERE H.INNGDATO BETWEEN @StartDate AND @EndDate
  AND ((H.ORDRENR = 0)
    OR (EXISTS (SELECT 1 FROM DBM.A_BESTHODE B
        WHERE H.ORDRENR = B.ORDRENR
          AND (B.ORDRESTATUS IN ('IA') OR VINNGSTATUS = 'VF'))));

-- Delete purchase order lines
DELETE FROM DBM.A_BESTLIN L
WHERE EXISTS (SELECT 1 FROM DBM.A_BESTHODE A
  WHERE A.ORDRENR = L.ORDRENR
    AND A.ORDREDATO BETWEEN @StartDate AND @EndDate
    AND A.ORDRESTATUS IN ('IA'));

-- Delete purchase order headers
DELETE FROM DBM.A_BESTHODE A
WHERE A.ORDREDATO BETWEEN @StartDate AND @EndDate
  AND A.ORDRESTATUS IN ('IA');

-- Delete invoice matching
DELETE FROM DBM.INNGANG_FAKO F
WHERE F.INNG_DATO BETWEEN @StartDate AND @EndDate;
```

---

## Data Domain 4: Invoicing (H_FAKT)

### Original Export SELECTs

```sql
-- Source: expfakt.ddl
-- Note: exports used FAKTDATO_SENTRAL for header, TIDSPUNKT for lines

-- Headers
SELECT INT(H.FAKTDATO_SENTRAL/10000), H.*
FROM DBM.H_FAKT_ORDREHODE H
WHERE H.FAKTDATO_SENTRAL BETWEEN {YEAR}0101 AND {YEAR}1231;

-- Lines (joined via AVDNR + ORDRENR, with TIDSPUNKT range)
SELECT INT(H.FAKTDATO_SENTRAL/10000), L.*
FROM DBM.H_FAKT_ORDREHODE H, DBM.H_FAKT_ORDRELINJER L
WHERE H.AVDNR = L.AVDNR
  AND H.ORDRENR = L.ORDRENR
  AND H.FAKTDATO_SENTRAL BETWEEN {YEAR}0101 AND {YEAR}1231;
```

### Nickname-Based INSERT

```sql
INSERT INTO DBM.HST_H_FAKT_ORDREHODE
  SELECT INT(H.FAKTDATO_SENTRAL/10000), H.*
  FROM DBM.H_FAKT_ORDREHODE H
  WHERE H.FAKTDATO_SENTRAL BETWEEN @StartDate AND @EndDate;

INSERT INTO DBM.HST_H_FAKT_ORDRELINJER
  SELECT INT(H.FAKTDATO_SENTRAL/10000), L.*
  FROM DBM.H_FAKT_ORDREHODE H, DBM.H_FAKT_ORDRELINJER L
  WHERE H.AVDNR = L.AVDNR AND H.ORDRENR = L.ORDRENR
    AND H.FAKTDATO_SENTRAL BETWEEN @StartDate AND @EndDate;
```

---

## Data Domain 5: Visma Transactions

### Original Export SELECTs

```sql
-- Source: exp_visma_transer_18_19, exp_visma_transer_15_17
-- Uses DEL format (delimited), not IXF

-- Recent period (REPLACE into main table)
SELECT * FROM DBM.VISMA_TRANSER
WHERE BILAGSDATO > 20180000;

-- Older period (into period-specific table)
SELECT * FROM DBM.VISMA_TRANSER
WHERE BILAGSDATO < 20180101;
```

### Nickname-Based INSERT

```sql
-- Visma transactions don't have AAR column — they go into period tables
INSERT INTO DBM.HST_VISMA_TRANSER
  SELECT * FROM DBM.VISMA_TRANSER
  WHERE BILAGSDATO BETWEEN @StartDate AND @EndDate;
```

---

## Data Domain 6: Cash Register Transactions

### Original Export SELECTs

```sql
-- Source: expkasstran_20221113 (only shows CONNECT, actual export not preserved)
-- Target: DBM.H_KASS_TRANSER in BASISHST
-- Loaded from: kasstran_for_2016_ovrige.ixf (2,284,905 rows)
-- Filter was likely: records before 2016
```

### Nickname-Based INSERT

```sql
INSERT INTO DBM.HST_H_KASS_TRANSER
  SELECT INT(date_column/10000), K.*
  FROM DBM.KASS_TRANSER K
  WHERE date_column BETWEEN @StartDate AND @EndDate;
-- NOTE: exact date column name needs verification from BASISPRO schema
```

---

## Complete Reference: AAR Column Derivation

| Data Domain | Source Date Column | AAR Calculation | Filter Pattern |
|---|---|---|---|
| Sales Orders (H_ORDRE) | `ORDREHODE.TILFAKTDATO` | `INT(TILFAKTDATO/10000)` | `TILFAKTDATO BETWEEN yyyymmdd AND yyyymmdd` |
| Archive Orders (AH_ORDRE) | `AH_ORDREHODE.OPPRETTET_DATO` | `INT(OPPRETTET_DATO/10000)` | `OPPRETTET_DATO BETWEEN ...` |
| Purchase Orders | `A_BESTHODE.ORDREDATO` | `INT(ORDREDATO/10000)` | `ORDREDATO BETWEEN ...` |
| Goods Receipts | `A_VIHODE.INNGDATO` | `INT(INNGDATO/10000)` | `INNGDATO BETWEEN ...` |
| Invoice Matching | `INNGANG_FAKO.INNG_DATO` | `INT(INNG_DATO/10000)` | `INNG_DATO BETWEEN ...` |
| Invoicing | `H_FAKT_ORDREHODE.FAKTDATO_SENTRAL` | `INT(FAKTDATO_SENTRAL/10000)` | `FAKTDATO_SENTRAL BETWEEN ...` |
| LASS | `LASS.KJØREDATO` | `INT(KJØREDATO/10000)` | `KJØREDATO BETWEEN ...` |
| VAREBEVEGELSE | `VAREBEVEGELSE.LAGERDATO` | _(no AAR — table has no year column)_ | `LAGERDATO BETWEEN ...` |
| KORRIGERINGER | `KORRIGERINGER.KORRDATO` | `INT(KORRDATO/10000)` | `KORRDATO BETWEEN ...` |
| Visma Transactions | `VISMA_TRANSER.BILAGSDATO` | _(period-specific tables)_ | `BILAGSDATO BETWEEN ...` |
| Cash Register | _(needs verification)_ | `INT(date/10000)` | _(needs verification)_ |

---

## Complete Reference: Table Relationships (JOIN Keys)

Understanding the joins is critical for correct INSERT and DELETE ordering.

| Parent Table | Child Table | JOIN Columns | FK Cascade? |
|---|---|---|---|
| `ORDREHODE` | `ORDRELINJER` | `AVDNR, ORDRENR` | Check BASISPRO |
| `ORDREHODE` | `ORDREMERKNAD` | `AVDNR, ORDRENR` | Check BASISPRO |
| `AH_ORDREHODE` | `AH_ORDRELINJER` | `AVDNR, ORDRENR` | No (verified from scripts) |
| `AH_ORDREHODE` | `H_VERKSTEDHODE` | `AVDNR, ORDRENR` | No |
| `AH_ORDREHODE` | `H_VERKSTED_TIMER` | `AVDNR, ORDRENR` | No |
| `AH_ORDREHODE` | `H_VERKSTEDTEKST` | `AVDNR, ORDRENR` | No |
| `A_BESTHODE` | `A_BESTLIN` | `ORDRENR` | Check BASISPRO |
| `A_VIHODE` | `A_VILIN` | `AVDNR, INNGANGNR` | Check BASISPRO |
| `H_FAKT_ORDREHODE` | `H_FAKT_ORDRELINJER` | `AVDNR, ORDRENR` | CASCADE (from DDL) |

**INSERT order:** Parent first, then children  
**DELETE order:** Children first, then parent

---

## Proposed Continuous Process Flow

```
┌────────────────────────────────────────────────────┐
│  1. FIND CANDIDATES                                │
│     SELECT COUNT(*), AAR FROM source_table         │
│     WHERE date_column < cutoff                     │
│     GROUP BY AAR                                   │
│                                                    │
│  → Log: "Found N rows in year YYYY for domain X"   │
├────────────────────────────────────────────────────┤
│  2. SCHEMA CHECK                                   │
│     Compare SYSCAT.COLUMNS counts:                 │
│     BASISPRO table should have (N) columns         │
│     BASISHST table should have (N+1) for AAR       │
│                                                    │
│  → Abort if mismatch                               │
├────────────────────────────────────────────────────┤
│  3. CHECK FOR DUPLICATES                           │
│     SELECT COUNT(*) FROM nickname                  │
│     WHERE AAR = @Year [AND AVDNR/ORDRENR match]    │
│                                                    │
│  → If rows already exist, skip or handle           │
├────────────────────────────────────────────────────┤
│  4. INSERT VIA NICKNAME                            │
│     INSERT INTO nickname SELECT AAR, source.*      │
│     FROM source_table WHERE date BETWEEN ...       │
│                                                    │
│     Do parent tables first, children second         │
│     Capture: @@ROWCOUNT for each INSERT            │
├────────────────────────────────────────────────────┤
│  5. VERIFY                                         │
│     Compare source count with nickname count       │
│     SELECT COUNT(*) from source WHERE ...          │
│     SELECT COUNT(*) from nickname WHERE AAR = ...  │
│                                                    │
│  → Abort delete if counts don't match              │
├────────────────────────────────────────────────────┤
│  6. DELETE FROM SOURCE                             │
│     Delete children first, parent last             │
│     Use chunked deletes (quarterly) for large sets │
│                                                    │
│     Capture: @@ROWCOUNT for each DELETE            │
├────────────────────────────────────────────────────┤
│  7. LOG AND NOTIFY                                 │
│     Write-LogMessage with all counts               │
│     Send-Sms if run > 5 minutes                    │
└────────────────────────────────────────────────────┘
```

---

## Chunked DELETE Strategy

The legacy scripts (`inng_til_hist.sql`) show that large deletes were split into quarterly chunks to reduce lock escalation and transaction log pressure:

```sql
-- Instead of one massive DELETE for a full year:
-- DELETE FROM table WHERE date BETWEEN 20220101 AND 20221231

-- Split into quarters:
DELETE FROM table WHERE date BETWEEN 20220101 AND 20220331;
DELETE FROM table WHERE date BETWEEN 20220401 AND 20220630;
DELETE FROM table WHERE date BETWEEN 20220701 AND 20220930;
DELETE FROM table WHERE date BETWEEN 20221001 AND 20221231;
```

This should be preserved in the automated solution — parameterized by chunk size (month or quarter).

---

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Nickname INSERT fails mid-batch | Use COMMIT after each table pair (header+lines). Verify counts before proceeding. |
| Duplicate inserts on re-run | Check for existing AAR+AVDNR+ORDRENR in BASISHST before INSERT. |
| Schema drift (new columns in BASISPRO) | Auto-compare `SYSCAT.COLUMNS` counts before each run. Abort and alert if mismatch. |
| BASISHST nicknames are read-only | Verify with: `SELECT * FROM SYSCAT.NICKNAMES WHERE ... ` — check if INSERT is allowed on the federated server mapping. |
| Large transaction log on INSERT via nickname | Use COMMIT every N rows or batch by month instead of full year. |
| FK constraints prevent DELETE order | Always delete children before parents. Map all FK relationships first. |
| Network failure during federated INSERT | Verify counts after each INSERT. Build idempotent re-run capability. |
