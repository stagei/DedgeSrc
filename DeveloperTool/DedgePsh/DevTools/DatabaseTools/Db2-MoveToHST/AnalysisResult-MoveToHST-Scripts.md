# Analysis: Db2-MoveToHST — BASISPRO to BASISHST Data Migration Scripts

**Author:** Geir Helge Starholm, www.dEdge.no  
**Created:** 2026-03-10  
**Technology:** DB2 LUW  

---

## Overview

The `Db2-MoveToHST` folder contains **53 files** — a mix of SQL scripts, DB2 command files, execution logs, DDL definitions, and one batch file. These files collectively document a **manual, ad-hoc process** for archiving transactional data from the **BASISPRO** (production) database to the **BASISHST** (history) database.

The process has been executed by hand over **20+ years** (2003–2023), with scripts customized per year and per avdeling (branch/division). There is no automation framework, no scheduling, and no standardized procedure — each migration is a one-off operation.

---

## Architecture: How Data Flows from BASISPRO to BASISHST

```
BASISPRO / BASISREG (Production)
    │
    │  1. EXPORT TO ... OF IXF  (select with year-based filter)
    │     Adds INT(date/10000) as AAR column prefix
    │
    ▼
IXF Files on shared drive (P:\tru\, K:\FKAVD\BASISHST\, F:\tron\)
    │
    │  2. LOAD FROM ... OF IXF INSERT INTO ... NONRECOVERABLE
    │     SET INTEGRITY FOR ... IMMEDIATE UNCHECKED
    │
    ▼
BASISHST (History Database)
    │
    │  3. DELETE from BASISPRO (manual, after verification)
    │
    ▼
BASISPRO data volume reduced
```

### Key Design Pattern

All BASISHST tables have an extra column **`AAR`** (year) as the first column in the primary key, which does not exist in the source BASISPRO tables. The export step computes this year from a date field (`INT(date/10000)`) and prepends it to the row data.

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

**Year partitioning:** TILFAKTDATO (invoice date) → `INT(TILFAKTDATO/10000)` = year  
**Last known run:** Year 2018 data loaded on 2022-03-13

### 2. Internal Orders (AH_Ordrer) — COBOL-batch archive orders

| Source Table (BASISPRO) | Target Table (BASISHST) | Description |
|---|---|---|
| `DBM.AH_ORDREHODE` | `DBM.AH_ORDREHODE` | Archive order headers |
| `DBM.AH_ORDRELINJER` | `DBM.AH_ORDRELINJER` | Archive order lines |
| `DBM.H_VERKSTEDHODE` | `DBM.H_VERKSTEDHODE` | Workshop headers |
| `DBM.H_VERKSTED_TIMER` | `DBM.H_VERKSTED_TIMER` | Workshop hours |
| `DBM.H_VERKSTEDTEKST` | `DBM.H_VERKSTEDTEKST` | Workshop text |

**Year partitioning:** OPPRETTET_DATO → `INT(OPPRETTET_DATO/10000)` = year  
**Staging table:** `DBM.AH_ORDRE_TIL_HIST` — temporary lookup to identify which orders to move  
**Last known run:** Year 2012 data loaded on 2022-11-13

### 3. Purchase Orders (Bestillinger)

| Source Table (BASISPRO) | Target Table (BASISHST) | Description |
|---|---|---|
| `DBM.A_BESTHODE` | `DBM.AH_BESTHODE` + `DBM.H_BESTHODE` | Purchase order headers |
| `DBM.A_BESTLIN` | `DBM.AH_BESTLIN` + `DBM.H_BESTLIN` | Purchase order lines |
| `DBM.A_VIHODE` | `DBM.AH_VIHODE` + `DBM.H_VIHODE` | Goods receipt headers |
| `DBM.A_VILIN` | `DBM.AH_VILIN` + `DBM.H_VILIN` | Goods receipt lines |
| `DBM.INNGANG_FAKO` | `DBM.H_INNGANG_FAKO` | Invoice matching |

**Staging table:** `DBM.BEST_TIL_HIST` — identifies which purchase orders to move  
**Last known run:** 2015 (15B suffix files), loaded via `sjekk_felter_A.sql`

### 4. Invoicing (Fakturering)

| Source Table (BASISPRO) | Target Table (BASISHST) | Description |
|---|---|---|
| `DBM.H_FAKT_ORDREHODE` | `DBM.H_FAKT_ORDREHODE` | Invoice order headers |
| `DBM.H_FAKT_ORDRELINJER` | `DBM.H_FAKT_ORDRELINJER` | Invoice order lines |

**Year partitioning:** FAKTDATO_SENTRAL → year  
**DDL defined in:** `cre_H_fakt.sql`

### 5. Visma Transactions

| Source Table (BASISPRO) | Target Table (BASISHST) | Description |
|---|---|---|
| `DBM.VISMA_TRANSER` | `DBM.VISMA_TRANSER_15_17` | Visma transactions 2015–2017 |
| `DBM.VISMA_TRANSER` | `DBM.VISMA_TRANSER_08_11` | Visma transactions 2008–2011 |
| `DBM.VISMA_TRANSER` | `DBM.VISMA_TRANSER_12_14` | Visma transactions 2012–2014 |

**Format:** DEL (delimited) instead of IXF  
**Last known run:** 2018/2019 data exported; pre-2018 to separate tables

### 6. Cash Register Transactions (Kassetransaksjoner)

| Source Table (BASISPRO) | Target Table (BASISHST) | Description |
|---|---|---|
| `DBM.KASS_TRANSER` | `DBM.H_KASS_TRANSER` | Cash register transactions |

**Last known run:** Pre-2016 data loaded on 2022-11-13

### 7. Legacy Faktura Data (P7910A1 schema)

| Source Table (BASISRAP) | Target Table (BASISHST) | Description |
|---|---|---|
| `P7910A1.FKFAHEAD97/98/99` | (unknown target) | Invoice headers 1997–1999 |
| `P7910A1.FKFAVLIN97/98/99` | (unknown target) | Invoice lines 1997–1999 |
| `P7910A1.FKFAKOMM97/98/99` | (unknown target) | Invoice comments 1997–1999 |
| `P7910A1.FKFAUTLV97/98/99` | (unknown target) | Delivery data 1997–1999 |
| `P7910A1.FKFAVAMO97/98/99` | (unknown target) | VAT/tax data 1997–1999 |
| `P7910A1.FKFASAMF97/98/99` | (unknown target) | Summary data 1997–1999 |

**Source:** BASISRAP (not BASISPRO)  
**Historical:** Only 1997–1999 data, very old export

---

## Active Scripts — File-by-File Analysis

### Category 1: DDL / Table Creation Scripts

These define the BASISHST target tables. Must be kept in sync with BASISPRO schema changes.

| File | Purpose | Status |
|---|---|---|
| `CREOPTIMA.SQL` | Creates `H_ORDREHODE`, `H_ORDRELINJER`, `H_ORDREMERKNAD`, `LASS`, `VAREBEVEGELSE` tables with AAR column and indexes | **Active DDL** |
| `CREKORR.SQL` | Creates `KORRIGERINGER` table with AAR column | **Active DDL** |
| `cre_H_fakt.sql` | Creates `H_FAKT_ORDREHODE` and `H_FAKT_ORDRELINJER` tables | **Active DDL** |
| `ah_ordre_til_hist` | Creates `AH_ORDRE_TIL_HIST` staging table | **Active DDL** |
| `tr` | Creates `VISMA_TRANSER_15_17` and `VISMA_TRANSER_12_14` tables with indexes | **Active DDL** |
| `sjekktab` | Creates `H_INNGANG_FAKO` and `INNGANG_FAKO` tables | **Active DDL** |

#### CREOPTIMA.SQL — Core order tables DDL

```sql
CREATE TABLE DBM.H_ORDREHODE (
  AAR                DECIMAL     (4,0)     NOT NULL WITH DEFAULT 0.0,
  AVDNR              DECIMAL     (6,0)     NOT NULL WITH DEFAULT 0.0,
  ORDRENR            DECIMAL     (6,0)     NOT NULL WITH DEFAULT 0.0,
  -- ... 70+ columns matching BASISPRO.DBM.ORDREHODE ...
  SAAKORN_ABONNEMENT CHARACTER   (1)       NOT NULL WITH DEFAULT ' ',
    PRIMARY KEY(AAR, AVDNR, ORDRENR)
  ) ;
-- Also creates: H_ORDRELINJER, H_ORDREMERKNAD, LASS, VAREBEVEGELSE
```

#### CREKORR.SQL — Corrections table DDL

```sql
CREATE TABLE DBM.KORRIGERINGER (
  AAR                DECIMAL     (4,0)     NOT NULL WITH DEFAULT 0.0,
  AVDNR              DECIMAL     (6,0)     NOT NULL WITH DEFAULT 0.0,
  KORRNR             DECIMAL     (5,0)     NOT NULL WITH DEFAULT 0.0,
  -- ... stock correction fields ...
    PRIMARY KEY(aar, AVDNR, KORRNR, LINJENR)
  ) ;
```

---

### Category 2: Schema Validation Scripts

These scripts verify that BASISPRO and BASISHST table schemas are in sync before running export/import.

| File | Purpose | Status |
|---|---|---|
| `sjekk_felter_A.sql` | Compares column counts between BASISPRO and BASISHST for purchase/receipt tables | **Active — must run before every migration** |
| `A_ORDRE_SJEKK_FELTER.SQL` | Compares column counts for AH_ORDRE and VERKSTED tables | **Active — must run before every migration** |

#### sjekk_felter_A.sql — Schema validation (critical pre-step)

```sql
-- Checks that column counts match between BASISPRO and BASISHST
-- Tables: AH_BESTHODE, AH_BESTLIN, H_BESTHODE, H_BESTLIN,
--         AH_VIHODE, AH_VILIN, H_VIHODE, H_VILIN, H_INNGANG_FAKO,
--         AH_ORDREHODE, AH_ORDRELINJER,
--         H_VERKSTEDHODE, H_VERKSTED_TIMER, H_VERKSTEDTEKST
-- NOTE: BASISHST tables should have 1 MORE column (AAR) than BASISPRO
connect to basispro;
select 'BASISPRO', substr(TABNAME,1,32), count(*)
 from syscat.columns
where TABSCHEMA = 'DBM'
and TABNAME IN ('AH_BESTHODE','AH_BESTLIN', ...)
group by tabname order by tabname;

connect to basishst;
select 'BASISHST', substr(TABNAME,1,32), count(*)
 from syscat.columns
where TABSCHEMA = 'DBM'
and TABNAME IN ('AH_BESTHODE','AH_BESTLIN', ...)
group by tabname order by tabname;
```

---

### Category 3: ALTER TABLE Scripts (Schema Evolution)

These add columns to BASISHST tables when BASISPRO gets new columns.

| File | Purpose | When Applied |
|---|---|---|
| `alter.sql` | Adds `VAREGR` to `KORRIGERINGER` | Historical |
| `alter_ordreh` | Renames `NOTAV` → `NOTAV_GML`, adds new `NOTAV CHAR(8)` to `H_ORDREHODE` | Historical |
| `alter20120707` | Adds multiple columns to `AH_BESTHODE`, `H_BESTHODE`, `AH_BESTLIN`, `H_BESTLIN`, `AH_VIHODE`, `AH_VILIN`, `H_VILIN` | 2012-07-07 |
| `sjekktab` (partial) | Adds `IFAKT` column to `VAREBEVEGELSE` | Historical |

#### alter20120707 — Batch schema evolution example

```sql
alter table dbm.ah_besthode add
  SPEDNR              DECIMAL(6,0) NOT NULL WITH DEFAULT 0.0;
alter table dbm.ah_besthode add
  AUTO_INNGANG        DECIMAL(1,0) NOT NULL WITH DEFAULT 0.0;
alter table dbm.ah_besthode add
  MOTTATT_EDI_OBK     CHARACTER(1) NOT NULL WITH DEFAULT ' ';
alter table dbm.ah_besthode add
  TRANSPORT_TYPE      CHARACTER(2) NOT NULL WITH DEFAULT ' ';
alter table dbm.ah_besthode add
  SAMPAKK_STATUS      CHARACTER(2) NOT NULL WITH DEFAULT ' ';
-- ... more columns for multiple tables ...
```

---

### Category 4: Export Scripts (BASISPRO → IXF)

These run on the production server to extract data.

| File | Year/Scope | What It Exports | Source DB |
|---|---|---|---|
| `expoptfix1.ddl` | 2005 (specific ordrenr) | Missing orders from BASISRAP to fix gaps | BASISRAP |
| `expfakt.ddl` | 2000 | `H_FAKT_ORDRELINJER` with year prefix | BASISPRO |
| `exp_visma_transer_18_19` | 2018–2019 | `VISMA_TRANSER` where bilagsdato > 20180000 | BASISPRO |
| `exp_visma_transer_15_17` | 2015–2017 | `VISMA_TRANSER` where bilagsdato < 20180101 | BASISPRO |
| `exp_ordre_2852_20220508` | 2015 (avd 2852) | AH_ORDRE + verksted for avdnr=2852 | BASISPRO |
| `a_exp_ordre20221113` | 2012 (all avd) | AH_ORDRE + verksted, full year 2012 | BASISPRO |
| `expkasstran_20221113` | pre-2016 | Cash register transactions | BASISPRO |

#### a_exp_ordre20221113 — Most recent full AH_ORDRE export (2022-11-13)

```sql
CONNECT TO BASISREG;
-- Step 1: Build staging table of orders to move
EXPORT TO P:\tru\AH_ORDRE_FLYTTES_2012.ixf OF IXF
  SELECT INT(OPPRETTET_DATO/10000), AVDNR, ORDRENR,
         CURRENT TIMESTAMP, ' '
  FROM DBM.AH_ORDREHODE
  WHERE OPPRETTET_DATO BETWEEN 20120101 AND 20121231;
-- Result: 2,994,751 rows

LOAD FROM P:\tru\AH_ORDRE_FLYTTES_2012.ixf OF IXF
  REPLACE INTO DBM.AH_ORDRE_TIL_HIST NONRECOVERABLE;

-- Step 2: Export each related table with year prefix
EXPORT TO P:\tru\AH_ORDREH2012.ixf OF IXF
  SELECT 2012, H.*
  FROM DBM.AH_ORDREHODE H, dbm.ah_ordre_til_hist T
  WHERE H.AVDNR = T.AVDNR AND H.ORDRENR = T.ORDRENR;
-- Result: 2,994,751 rows

EXPORT TO P:\tru\AH_ORDREL2012.ixf OF IXF
  SELECT 2012, L.*
  FROM DBM.AH_ORDRELINJER L, dbm.ah_ordre_til_hist T
  WHERE L.AVDNR = T.AVDNR AND L.ORDRENR = T.ORDRENR;
-- Result: 6,966,653 rows

-- Similarly for: H_VERKSTEDHODE (53,441), H_VERKSTED_TIMER (69,220),
--                H_VERKSTEDTEKST (225,367)
```

---

### Category 5: Import/Load Scripts (IXF → BASISHST)

These run on the BASISHST server to load the exported data.

| File | Year/Scope | Tables Loaded | Server |
|---|---|---|---|
| `fksql.imp06A` | 2006 | H_ORDREHODE (278K rows) | BASISHST (DB2 8.2) |
| `fksql.imp06B` | 2006 | H_ORDRELINJER, H_ORDREMERKNAD, LASS, VAREBEVEGELSE, KORRIGERINGER | BASISHST (DB2 8.2) |
| `fksql.imp08A` | 2008 | H_ORDREHODE (373K rows) | BASISHST |
| `fksql.impoptima2010` | 2010 | All 6 order tables + LASS, VAREBEVEGELSE, KORRIGERINGER | BASISHST |
| `FKSQL.IMP_2011` | 2011 | All 6 order tables + LASS, VAREBEVEGELSE, KORRIGERINGER | BASISHST |
| `imp_opt_2018` | 2018 | All 6 order tables + LASS, VAREBEVEGELSE, KORRIGERINGER | BASISHST (latest H_ORDRE) |
| `FKSQL.besth_imp14a` | 2014 | BEST_TIL_HIST, AH_BESTHODE, AH_BESTLIN, H_BESTHODE, H_BESTLIN, AH_VIHODE, AH_VILIN, H_VIHODE, H_VILIN, H_INNGANG_FAKO | BASISHST |
| `a_imp_ordre20221113` | 2012 | AH_ORDREHODE, AH_ORDRELINJER, H_VERKSTEDHODE, H_VERKSTED_TIMER, H_VERKSTEDTEKST | BASISHST (latest AH_ORDRE) |
| `imp_ordre_2852_20220508` | 2015 (avd 2852) | Same AH_ORDRE set, filtered by avdnr=2852 | BASISHST |
| `imp_visma_transer_18_19` | 2018–2019 | `VISMA_TRANSER` (REPLACE) | BASISHST |
| `imp_visma_transer_15_17` | 2015–2017 | `VISMA_TRANSER_15_17` | BASISHST |
| `FKSQL.load_vismatranser_08_11` | 2008–2011 | `VISMA_TRANSER_08_11` (165M rows!) | BASISHST |
| `impkasstran_20221113` | pre-2016 | `H_KASS_TRANSER` (2.28M rows) | BASISHST |
| `impoptfix1.ddl` | 2005 fix | H_ORDREHODE, H_ORDRELINJER, H_ORDREMERKNAD (missing orders) | BASISHST |
| `IMPOPTIMA2.DDL` | 2000 | KORRIGERINGER (from BASISRAP) | BASISHST |
| `FKSQL.NETADM` | 2003 | H_ORDREHODE — **FAILED** (file access denied) | BASISHST (DB2 8.2) |

#### Standard LOAD pattern used throughout

```sql
CONNECT TO BASISHST;

-- Load with NONRECOVERABLE (no transaction log overhead)
LOAD FROM P:\tru\ORDREH2018.IXF OF IXF
  INSERT INTO DBM.H_ORDREHODE NONRECOVERABLE;

-- Fix integrity check state after load
SET INTEGRITY FOR DBM.H_ORDREHODE CHECK, MATERIALIZED QUERY,
  STAGING, FOREIGN KEY, GENERATED COLUMN IMMEDIATE UNCHECKED;

-- Repeat for each related table...
```

---

### Category 6: Cleanup / Delete Scripts

These delete old data from BASISPRO after successful migration, or clean orphaned data.

| File | Purpose |
|---|---|
| `del.sql` | Deletes from `H_ORDREHODE` where TILFAKTDATO=0 and old timestamps (1997–1999) |
| `DEL_OLIN_VEI.SQL` | Deletes from `ORDRELINJER_VEI` where timestamp < 2007 and AVDNR=3005 |
| `RYDDOPTIMA.SQL` | Deletes orphaned records from `AH_ORDRELINJER_ENDR` |
| `RYDD_GAMMELT.SQL` | Deletes orphaned records from `KD_KONT_ORDRE` |
| `a_ordre_gen_del` | Generates DELETE statements per day for `AH_ORDREHODE` (year 2005) |
| `BESTH_DEL_x` | Deletes from `A_BESTHODE` based on `BEST_TIL_HIST` staging table |
| `inng_til_hist.sql` | **Multi-step** script: export `A_VIHODE`/`A_VILIN` → import into `AH_VIHODE`/`AH_VILIN` → delete from source (avdnr 8039, year 2022) |

#### inng_til_hist.sql — Complete export-import-delete cycle for goods receipts

```sql
-- Step 1: Export headers and lines for avd 8039, year 2022
export to avihode.ixf of ixf
select int(inngdato/10000), h.*
from dbm.a_vihode h
where avdnr = 8039
and inngdato between 20220101 and 20221231
and((ordrenr = 0) or (exists (select 1 from dbm.a_besthode b
   where h.ordrenr = b.ordrenr
   and (b.ordrestatus in('IA') or vinngstatus='VF'))));

-- Step 2: Import into archive tables
import from avihode.ixf of ixf insert into dbm.ah_vihode;
import from avilin.ixf of ixf insert into dbm.ah_vilin;

-- Step 3: Delete lines from source (quarterly batches to reduce lock size)
delete from dbm.a_vilin l where avdnr = 8039
and exists (select 1 from dbm.a_vihode h
  where l.avdnr = h.avdnr and l.inngangnr = h.inngangnr
  and inngdato between 20220101 and 20220331 ...);

-- Step 4: Delete headers from source
delete from dbm.a_vihode h where avdnr = 8039
and inngdato between 20220101 and 20221231 ...;
```

---

### Category 7: Query / Verification Scripts

| File | Purpose |
|---|---|
| `tr.sql` | `SELECT MAX(TILFAKTDATO) FROM DBM.H_ORDREHODE` — check latest order date in history |
| `count` | Count orders in `A_BESTHODE` staged for migration via `BEST_TIL_HIST` |
| `sel_innkjop` | Query purchase order details from `AH_BESTHODE`/`AH_BESTLIN` |

---

### Category 8: Backup

| File | Purpose | Last Run |
|---|---|---|
| `backup_basishst.bat` | Online backup of BASISHST to `G:\DB2HSTBACKUP` with compression | 2023-04-02 |

#### backup_basishst.bat

```bat
REM kjørt 02.04.2023
set DB2INSTANCE=DB2HST
DB2 BACKUP DATABASE BASISHST ONLINE TO "G:\DB2HSTBACKUP" WITH 2 BUFFERS
  BUFFER 1024 PARALLELISM 1 COMPRESS UTIL_IMPACT_PRIORITY 50
  INCLUDE LOGS WITHOUT PROMPTING
```

---

### Category 9: Log Files / Failed Runs

| File | Contents |
|---|---|
| `FKSQL.P7910A1` | Log of exporting 1997–1999 invoice data from BASISRAP (P7910A1 schema) |
| `FKSQL.NETADM` | **Failed** load attempt — file access denied on UNC path `\\SFKDC02\EDB\` |
| `FKSQL.ah_ordre2` | Log of exporting AH_ORDRE data for year <2000 from BASISRAP |
| `FKSQLU` | Notes about missing/inaccessible files |
| `a_ordre_exp2003.log2` | Log of exporting AH_ORDRE lines and verksted for year 2003 |
| `a_ordre_imp_8039_2013.erp_srv` | Log of export for avdnr 8039, year 2013 (from BASISREG) |
| `a_ordre_imp_2010.srv_erp1` | Log of import into BASISHST for AH_ORDRE 2010 data |
| `fksql_aordre_2010.srv_erp1` | Log of export for AH_ORDRE year 2010 (from BASISREG) |
| `fksql_8039_2013.erp1_meh` | Log of export for avdnr 8039, year 2013 (from BASISREG) |
| `imp_ordre_2852_20220508` | Log of import for avd 2852, year 2015 into BASISHST |
| `exp_ordre_2852_20220508` | Log of export for avd 2852, year 2015 from BASISPRO |
| `x` | Load of `AH_ORDRE_TIL_HIST` staging data |
| `xx` | Connect to BASISHST (incomplete/test) |
| `trx` | Connect to BASISHST — output only (no actual commands) |

---

## The Standard Migration Procedure (Reconstructed)

Based on analysis of all scripts, the manual procedure is:

### For H_ORDRE (Sales Orders) — `fksql.impoptima*` / `imp_opt_*`

1. **Pre-check:** Run `sjekk_felter_A.sql` or `A_ORDRE_SJEKK_FELTER.SQL` to verify column counts match
2. **Export from BASISPRO:** `EXPORT TO ... OF IXF SELECT INT(TILFAKTDATO/10000), H.* FROM DBM.ORDREHODE H WHERE TILFAKTDATO BETWEEN {start} AND {end}`
3. **Export related tables:** ORDRELINJER, ORDREMERKNAD, LASS, VAREBEVEGELSE, KORRIGERINGER (each with year prefix)
4. **Copy IXF files** from BASISPRO server to BASISHST server (via `P:\tru\`)
5. **Load into BASISHST:** `LOAD FROM ... OF IXF INSERT INTO DBM.H_ORDREHODE NONRECOVERABLE`
6. **Fix integrity:** `SET INTEGRITY FOR DBM.H_ORDREHODE CHECK, ... IMMEDIATE UNCHECKED`
7. **Verify counts** match export counts
8. **Backup BASISHST** (optional, via `backup_basishst.bat`)

### For AH_ORDRE (Archive Orders) — `a_exp_ordre*` / `a_imp_ordre*`

1. **Pre-check:** Run `A_ORDRE_SJEKK_FELTER.SQL` to verify schema sync
2. **Build staging table:** Export order keys to `AH_ORDRE_TIL_HIST` staging table
3. **Export from BASISPRO/BASISREG:** Join source tables with staging table, prepend year
4. **Copy IXF files** to BASISHST server
5. **Load into BASISHST:** LOAD + SET INTEGRITY for each table
6. **Delete from BASISPRO** (separate manual step, done later)

### For Bestillinger (Purchase Orders) — `FKSQL.besth_imp*`

1. **Pre-check:** Run `sjekk_felter_A.sql`
2. **Build staging table:** `BEST_TIL_HIST`
3. **Export all related tables** with year prefix
4. **Load into BASISHST** (9 tables in sequence)
5. **Delete from BASISPRO** via `BESTH_DEL_x`

---

## Volumes and Timelines

| Year Migrated | When | Main Data | Row Counts |
|---|---|---|---|
| 1997–1999 | ~2007 | Legacy invoice (P7910A1) | ~12M rows total |
| 2000 | ~2010 | H_FAKT orders, KORRIGERINGER | Various |
| 2003 | ~2010 | AH_ORDRELINJER + verksted | 3M + 33K + 40K |
| 2005 | ~2010 | Fix for missing orders | 7 specific orders |
| 2006 | 2010-03-22 | Full H_ORDRE cycle | 278K + 1.1M + 89K + 81K + 991K + 23K |
| 2008 | 2010-03-22 | H_ORDREHODE only | 373K |
| 2008–2011 | 2013-08-11 | VISMA_TRANSER | 165M rows |
| 2010 | 2012-03-12 | Full H_ORDRE cycle | 411K + 1.9M + 141K + 135K + 1.8M + 117K |
| 2010 (AH) | 2018-12-02 | AH_ORDRE cycle | 3M + 6.9M + 53K + 68K + 200K |
| 2011 | 2014-02-15 | Full H_ORDRE cycle | 206K + 1M + 65K + 67K + 911K + 56K |
| 2012 | 2012-07-07 | ALTER tables for new columns | Schema only |
| 2013 (avd 8039) | 2018-12-01 | AH_ORDRE for avdnr 8039 | 124K + 400K |
| 2014 | 2014-02-15 | Full bestilling cycle | 350K + 338K + 1.6M + 12K + 31K + 308K + 1M + 14K + 31K + 153K |
| 2015 (avd 2852) | 2022-05-08 | AH_ORDRE for avdnr 2852 | 98K + 247K + 2K + 3K + 10K |
| 2015–2017 | ~2022 | VISMA_TRANSER split | Separate table |
| 2018 | 2022-03-13 | Full H_ORDRE cycle | 215K + 1.2M + 62K + 92K + 976K + 41K |
| 2018–2019 | ~2022 | VISMA_TRANSER | DEL format, REPLACE |
| 2012 (AH) | 2022-11-13 | AH_ORDRE full year | 2.9M + 6.9M + 53K + 69K + 225K |
| pre-2016 | 2022-11-13 | KASS_TRANSER | 2.28M |
| 2022 (avd 8039) | ~2022 | Goods receipts (A_VIHODE/A_VILIN) | Manual script |
| Backup | 2023-04-02 | Full BASISHST backup | — |

---

## Identified Problems for Automation

1. **Entirely manual:** Every migration is a copy-paste-edit operation. No scripts accept parameters.
2. **Year-specific file names:** IXF files are hardcoded with year suffixes (ORDREH2018.IXF, AH_ORDREH2012.ixf).
3. **No error handling:** Scripts have no rollback, no validation, no count verification beyond visual inspection.
4. **Schema drift risk:** The `sjekk_felter_A.sql` check is manual. If forgotten, LOADs fail with column mismatch.
5. **Inconsistent delete strategy:** Some deletes are by quarter (to reduce locks), others by year, some never done.
6. **Mixed file paths:** Scripts reference `K:\`, `F:\`, `P:\`, `\\SFKDC02\EDB\` — no consistent staging area.
7. **No idempotency:** Running twice inserts duplicates. The LOAD NONRECOVERABLE + INSERT mode doesn't handle re-runs.
8. **DB2 version progression:** Files show DB2 8.2 → 9.7 → 9.7.11. Current version unclear.
9. **Multiple operators:** Scripts executed by TRU, SRV_ERP1, SRV_ERP2, SRV_DB2, NETADM, MEH — no single owner.
10. **Incomplete migrations:** Some years have only partial tables migrated (e.g., 2008 only has H_ORDREHODE).

---

## Recommendations for Modern Automation

A new PowerShell-based solution should:

1. **Parameterize by year, avdnr, and data domain** (orders, purchases, visma, etc.)
2. **Auto-detect schema differences** between BASISPRO and BASISHST
3. **Generate export/load commands dynamically** from table metadata
4. **Use consistent staging paths** (UNC or opt\data\)
5. **Verify row counts** after each LOAD and compare with EXPORT
6. **Support idempotent re-runs** (check if year/data already exists in BASISHST)
7. **Handle the AAR column injection** automatically via `INT(date_column/10000)`
8. **Log all operations** via `Write-LogMessage`
9. **Send notifications** on completion via SMS
10. **Integrate with Cursor-ServerOrchestrator** for remote execution on the DB2 server

### Date Column Mapping (for automation)

| Data Domain | Date Column | AAR Calculation |
|---|---|---|
| H_ORDRE (sales) | `TILFAKTDATO` | `INT(TILFAKTDATO/10000)` |
| AH_ORDRE (archive) | `OPPRETTET_DATO` | `INT(OPPRETTET_DATO/10000)` |
| Bestillinger | `ORDREDATO` | `INT(ORDREDATO/10000)` |
| Inngang (receipts) | `INNGDATO` | `INT(INNGDATO/10000)` |
| VISMA_TRANSER | `BILAGSDATO` | `INT(BILAGSDATO/10000)` |
| H_FAKT (invoices) | `FAKTDATO_SENTRAL` | `INT(FAKTDATO_SENTRAL/10000)` |
| KASS_TRANSER | (unknown) | Needs investigation |

---

## File Inventory Summary

| Category | Count | Files |
|---|---|---|
| DDL / Table Creation | 6 | `CREOPTIMA.SQL`, `CREKORR.SQL`, `cre_H_fakt.sql`, `ah_ordre_til_hist`, `tr`, `sjekktab` |
| Schema Validation | 2 | `sjekk_felter_A.sql`, `A_ORDRE_SJEKK_FELTER.SQL` |
| ALTER TABLE | 4 | `alter.sql`, `alter_ordreh`, `alter20120707`, `sjekktab` (partial) |
| Export Scripts | 7 | `expoptfix1.ddl`, `expfakt.ddl`, `exp_visma_transer_*` (2), `exp_ordre_2852_*`, `a_exp_ordre20221113`, `expkasstran_20221113` |
| Import/Load Scripts | 16 | `fksql.imp06A/B`, `fksql.imp08A`, `fksql.impoptima2010`, `FKSQL.IMP_2011`, `imp_opt_2018`, `FKSQL.besth_imp14a`, `a_imp_ordre20221113`, `imp_ordre_2852_*`, `imp_visma_transer_*` (2), `FKSQL.load_vismatranser_*`, `impkasstran_20221113`, `impoptfix1.ddl`, `IMPOPTIMA2.DDL`, `x` |
| Delete/Cleanup | 7 | `del.sql`, `DEL_OLIN_VEI.SQL`, `RYDDOPTIMA.SQL`, `RYDD_GAMMELT.SQL`, `a_ordre_gen_del`, `BESTH_DEL_x`, `inng_til_hist.sql` |
| Query/Verification | 3 | `tr.sql`, `count`, `sel_innkjop` |
| Backup | 1 | `backup_basishst.bat` |
| Logs / Output Files | 8 | `FKSQL.P7910A1`, `FKSQL.NETADM`, `FKSQL.ah_ordre2`, `FKSQLU`, `a_ordre_exp2003.log2`, `a_ordre_imp_8039_2013.erp_srv`, `fksql_aordre_2010.srv_erp1`, `fksql_8039_2013.erp1_meh` |
| Stubs / Incomplete | 4 | `xx`, `trx`, `a_ordre_imp_2010.srv_erp1`, `imp_opt_2018` (partial log) |
| **Total** | **53** | |
