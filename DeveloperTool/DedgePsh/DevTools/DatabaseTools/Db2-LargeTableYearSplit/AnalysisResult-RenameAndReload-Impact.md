# Impact Analysis: RENAME + DROP + CREATE LIKE Approach

**Author:** Geir Helge Starholm, www.dEdge.no
**Created:** 2026-03-17
**Technology:** DB2 LUW 12.1
**Source database:** BASISTST (FKMTST), verified via MCP db2-query
**Config file:** ArchiveTables.json

---

## Overview

This document analyzes the consequences of using a **RENAME TABLE + CREATE TABLE LIKE + EXPORT/LOAD** strategy
to split large archive tables by year. The approach renames the original table to `*_TMP`, creates a new empty
table with the original name, exports only the rows that should remain (current year data) into the new table,
and leaves the `_TMP` table available for offline year-splitting or eventual DROP.

**Key Db2 behavior** (source: `db2_sql_reference_1213.md`):
> "All indexes, materialized query tables, staging tables, primary keys, foreign keys, and check constraints
> referencing the dropped tables are dropped. All views and triggers that reference the dropped tables are
> made inoperative. All packages depending on any object dropped or marked inoperative will be invalidated."

**Important:** `CREATE TABLE ... LIKE` does **NOT** copy indexes, grants, views, or triggers. These must
be explicitly recreated from exported DDL after the new table is created.

---

## Tables in Scope

| Table | Rows (est.) | Columns | Data Pages | TimestampColumn |
|---|---|---|---|---|
| `DBM.VISMA_TRANSER` | 52,528,311 | 64 | 2,394,801 | TIDSPUNKT_VISMA |
| `DBM.D365_BUNTER` | 1,554,142 | 130 | 388,731 | T_TPKT_VISMA |

---

## DBM.VISMA_TRANSER

### Views (0 directly affected)

| View | Schema | References | Affected? |
|---|---|---|---|
| `VISMA_TRANSER_BA45_HST` | DV | `DBM.VISMA_TRANSER_08_11` (year-split copy) | **No** |

The only view found references a year-split table (`_08_11`), not the original `VISMA_TRANSER`.

### Triggers

None.

### Foreign Key Constraints

None.

### Stored Procedures / Functions

None (SYSCAT.ROUTINEDEP and SYSCAT.FUNCDEP empty for this table).

### Indexes (6 -- all lost on DROP, must be recreated)

| Index Name | Unique | Columns |
|---|---|---|
| `SQL120125135026000` | **PK** | `DATO ASC, TIDSPUNKT_FORSYS ASC` |
| `VISMA_TRANSER_BBT_N` | D | `BILAGSART ASC, BILAGSDATO ASC, TIDSPUNKT_VISMA ASC` |
| `VISMA_TRANSER_I1_N` | D | `TRANSTYPE ASC, DEBET_KONTONR ASC, KREDIT_KONTONR ASC` |
| `VISMA_TRANSER_I2_N` | D | `LEVAVD ASC, ORDRENR ASC, FKNR ASC, TRANSTYPE ASC, DEBET_KONTONR ASC, KREDIT_KONTONR ASC` |
| `VISMA_TRANSER_I3_N` | D | `BILAGSDATO ASC, BILAGSNUMMER ASC, FAKTURANR ASC, ORDRENR ASC, DEBET_KONTONR ASC, KREDIT_KONTONR ASC, TRANSTYPE ASC` |
| `VISMA_TRANSER_I7_N` | D | `DATO ASC, TIDSPUNKT_FORSYS ASC, REFERANSENR ASC, TIL_VISMA ASC` |

### Grants (30 entries)

| Grantee | SELECT | INSERT | UPDATE | DELETE | CONTROL | Grantor(s) |
|---|---|---|---|---|---|---|
| TRU | G | G | G | G | **Y** | SYSIBM (owner) |
| VKR | Y | Y | Y | Y | N | TRU, DB2NT |
| FKMTSTADM | Y | Y | Y | Y | N | FKSVEERI |
| FKTSTSTD | Y | Y | Y | Y | N | T1_SRV_FKMTST_DB |
| DB2ADMNS | Y | N | N | N | N | DB2NT, T1_SRV_FKMTST_DB |
| DB2NT | Y | N | N | N | N | DB2NT |
| DB2USERS | Y | N | N | N | N | DB2NT, T1_SRV_FKMTST_DB |
| FKDEVADM | Y | N | N | N | N | DB2NT, T1_SRV_FKMTST_DB |
| FKDEVDBA | Y | N | N | N | N | T1_SRV_FKMTST_DB |
| FKGEISTA | Y | N | N | N | N | DB2NT |
| FKPRDADM | Y | N | N | N | N | DB2NT, T1_SRV_FKMTST_DB |
| FKPRDDBA | Y | N | N | N | N | T1_SRV_FKMTST_DB |
| FKSVEERI | Y | N | N | N | N | DB2NT |
| FKTSTADM | Y | N | N | N | N | DB2NT, T1_SRV_FKMTST_DB |
| FKTSTDBA | Y | N | N | N | N | T1_SRV_FKMTST_DB |
| FKTSTDRDO | Y | N | N | N | N | T1_SRV_FKMTST_DB |
| PUBLIC | Y | N | N | N | N | TRU, DB2NT, MEH |
| SRV_DATAVAREHUS | Y | N | N | N | N | DB2NT, T1_SRV_FKMTST_DB |
| SRV_DB2 | Y | N | N | N | N | DB2NT |
| SRV_SFKSS07 | Y | N | N | N | N | DB2NT |
| T1_SRV_FKMTST_DB | Y | N | N | N | N | DB2NT |

### Bound COBOL Packages (46 programs -- invalidated on DROP)

These packages reference `DBM.VISMA_TRANSER` and will be **invalidated** when the table is dropped.
With `auto_reval=DEFERRED` (Db2 default), they are automatically revalidated on next access.
Alternatively, run `db2rbind` to rebind all at once.

| # | Package | # | Package | # | Package |
|---|---|---|---|---|---|
| 1 | D3BD3FIL | 17 | HDXMOTPO | 33 | HLBBEVO |
| 2 | HBBAUTO | 18 | HDXNYEP6 | 34 | HLBKORA |
| 3 | HBBECOL | 19 | HDXNYEP7 | 35 | HLBKORO |
| 4 | HBBEHAN | 20 | HDXUPD01 | 36 | HLBUTLE |
| 5 | HBBOCR | 21 | HFBFAKO | 37 | HLBVINA |
| 6 | HBBOCR2 | 22 | HFBFASF | 38 | HLBVUTA |
| 7 | HBBOCR3 | 23 | HFBFAUT | 39 | HLXBEVO2 |
| 8 | HDAVTRA | 24 | HFXFAUTV | 40 | HLXKORA |
| 9 | HDBVFIL | 25 | HFXFIX01 | 41 | HPBAVRE |
| 10 | HDXMOTP1 | 26 | HFXFIX02 | 42 | HPBPFSK |
| 11 | HDXMOTP2 | 27 | HFXFIX03 | 43 | HPXVING |
| 12 | HDXMOTP3 | 28 | HFXFIX04 | 44 | M3BM3FIL |
| 13 | HDXMOTP4 | 29 | HFXNULL | 45 | OKBASFA |
| 14 | HDXMOTP5 | 30 | HFXOPOS | 46 | OKBASFT |
| 15 | HDXMOTP6 | 31 | HLBBEVA | | |
| 16 | HDXMOTP7 | 32 | HLBBEVK | | |

### COBOL Programs with Direct SQL on VISMA_TRANSER (from Dedge-code RAG)

| Program | Operation | Detail |
|---|---|---|
| `hdbvfVF.cbl` | UPDATE | Sets PRODUKT_VISMA, PRODUKT |
| `hdbvfVF-BasisKAT.cbl` | UPDATE | Sets REFERANSENR, TIDSPUNKT_VISMA |

These programs will fail with SQL errors if they run while the table is renamed/dropped.
After the new table is created and data loaded, the packages auto-revalidate on next access.

---

## DBM.D365_BUNTER

### Views (1 directly affected)

| View | Schema | Affected? | Action Required |
|---|---|---|---|
| `RPA_AVSTEMMING_BUNTER` | TV | **Yes** | Becomes INOPERATIVE on DROP; must be recreated |

**Full view DDL** (from SYSCAT.VIEWS):
```sql
CREATE OR REPLACE VIEW TV.RPA_AVSTEMMING_BUNTER AS
SELECT distinct
    HO.FAKTDATO_SENTRAL AS fakturadato,
    HO.FAKTURANR,
    HO.AVDNR,
    HO.ORDRENR,
    CONCAT(HO.AVDNR, HO.ORDRENR) AS AvdOrdre,
    HO.BETBET,
    HO.ordrebelop AS uten_mva,
    HO.FAKTURABELOP AS inkl_mva,
    BU.T_STATUS_BILAG
FROM dbm.D365_BUNTER BU
LEFT JOIN dbm.H_FAKT_ORDREHODE HO
    ON HO.AVDNR = BU.T_SORDRE_AVDNR
    AND HO.ORDRENR = BU.T_SORDRE_ORDRENR
WHERE HO.FAKTDATO_SENTRAL >= FK.ND2CD(CURRENT DATE - 1 DAYS)
    AND SD_STATUS IN (41, 49, 53, 55)
    AND KUNDEGRUPPE NOT IN (10, 23, 24)
    AND HO.ordretype <> 36
    AND BU.V_VOTP IN (15, 21, 22)
    AND BU.T_SKIP_KONTO_BUNT = 'J'
    AND BU.T_UTPLK_D3_SORDRE = 'J';
```

Additional dependencies of this view:
- `DBM.H_FAKT_ORDREHODE` (table)
- `FK.SQL050503151039100` (function, `FK.ND2CD`)

### Triggers

None.

### Foreign Key Constraints

None.

### Stored Procedures / Functions

None.

### Indexes (24 -- all lost on DROP, must be recreated)

| Index Name | Unique | Key Columns |
|---|---|---|
| `SQL211022154835770` | **PK** | `T_UTPLK_DATO_Dedge, T_TPKT_D3_BUNTER` |
| `D365_BUNTER_I1` | D | `V_VOTP, T_SKIP_KONTO_BUNT, T_UTPLK_D3_BUNTFIL, T_STATUS_BILAG, T_STATUS_LINJE, T_FEIL1_LINJE, T_FEIL2_LINJE, T_FEIL3_LINJE, T_FEIL4_LINJE` |
| `D365_BUNTER_I2` | D | `V_VOTP, T_SKIP_KONTO_BUNT, T_UTPLK_D3_SORDRE, T_STATUS_BILAG, T_STATUS_LINJE, T_FEIL1_LINJE, T_FEIL2_LINJE, T_FEIL3_LINJE, T_FEIL4_LINJE` |
| `D365_BUNTER_I3` | D | `V_VOTP, T_SKIP_KONTO_BUNT, T_UTPLK_D3_IORDRE, T_STATUS_BILAG, T_STATUS_LINJE, T_FEIL1_LINJE, T_FEIL2_LINJE, T_FEIL3_LINJE, T_FEIL4_LINJE` |
| `D365_BUNTER_I4` | D | `V_VOTP, T_UTPLK_DATO_Dedge, V_VODT, V_VONO` |
| `D365_BUNTER_I5` | D | `V_VONO, T_SORDRE_AVDNR, T_SORDRE_ORDRENR, T_SORDRE_LINJENR, V_VOTP, V_FREE2, T_SKIP_KONTO_BUNT, V_VODT` |
| `D365_BUNTER_I55` | D | `T_SORDRE_AVDNR, T_SORDRE_ORDRENR, T_SORDRE_LINJENR, V_VONO, T_SKIP_KONTO_BUNT, V_VODT` |
| `D365_BUNTER_I6` | D | `V_VOTP, V_R1, V_R2, V_R3, D_VAREGRUPPE, V_FREE2` |
| `D365_BUNTER_I7` | D | `T_TRANSTYPE, V_DBACNO, V_CRACNO` |
| `D365_BUNTER_I8` | D | `V_VOTP, V_VONO, D_ACCOUNTTYPE, D_MAINACCOUNT` |
| `D365_BUNTER_I9` | D | `V_VOTP, V_TXT` |
| `D365_BUNTER_I10` | D | `T_UTPLK_DATO_Dedge, T_TPKT_Dedge, V_VOGR1` |
| `D365_BUNTER_I11` | D | `V_FREE4, V_FREE1, V_FREE2, T_TRANSTYPE, V_DBACNO, V_CRACNO` |
| `D365_BUNTER_I12` | D | `T_TRANSTYPE, V_FREE4, T_KUNDEGRUPPE, T_KUNDENR, V_FREE1, V_FREE2, V_DBACNO, V_CRACNO` |
| `D365_BUNTER_I13` | D | `V_VODT, V_VONO, V_INVONO, V_FREE4, V_FREE1, V_DBACNO, V_CRACNO, T_TRANSTYPE` |
| `D365_BUNTER_I14` | D | `D_KOSTNADSSTED, D_SITE, D_FORRETNINGSOMRADE, D_FKAT` |
| `D365_BUNTER_I15` | D | `D_TRANSDATE, D_VOUCHER, V_FREE4, D_MAINACCOUNT` |
| `D365_BUNTER_I16` | D | `D_TRANSDATE, V_VOTP, V_FREE3` |
| `D365_BUNTER_I17` | D | `D_TRANSDATE, V_VOTP, T_ORDRETYPE, T_KONTOKODE, T_SALGSKONSULENT, T_MEKANIKER` |
| `D365_BUNTER_I18` | D | `D_VOUCHER, V_VOTP, V_VODT, T_FEIL1_LINJE, T_FEIL2_LINJE, T_FEIL3_LINJE, T_FEIL4_LINJE` |
| `D365_BUNTER_I20` | D | `V_VOTP, D_VOUCHER` |
| `D365_BUNTER_I21` | D | `V_VOTP, V_VONO` |
| `D365_BUNTER_I22` | D | `V_VOTP, V_VODT` |
| `D365_BUNTER_I23` | D | `V_VOTP, T_TPKT_BRUKER_KORR` |

### Grants (26 entries)

| Grantee | SELECT | INSERT | UPDATE | DELETE | CONTROL | Grantor(s) |
|---|---|---|---|---|---|---|
| DB2NT | G | G | G | G | **Y** | SYSIBM (owner) |
| FKMTSTADM | Y | Y | Y | Y | N | FKSVEERI |
| FKTSTSTD | Y | Y | Y | Y | N | T1_SRV_FKMTST_DB |
| DB2ADMNS | Y | N | N | N | N | DB2NT, T1_SRV_FKMTST_DB |
| DB2USERS | Y | N | N | N | N | DB2NT, T1_SRV_FKMTST_DB |
| FKDEVADM | Y | N | N | N | N | DB2NT, T1_SRV_FKMTST_DB |
| FKDEVDBA | Y | N | N | N | N | T1_SRV_FKMTST_DB |
| FKGEISTA | Y | N | N | N | N | DB2NT |
| FKPRDADM | Y | N | N | N | N | DB2NT, T1_SRV_FKMTST_DB |
| FKPRDDBA | Y | N | N | N | N | T1_SRV_FKMTST_DB |
| FKSVEERI | Y | N | N | N | N | DB2NT |
| FKTSTADM | Y | N | N | N | N | DB2NT, T1_SRV_FKMTST_DB |
| FKTSTDBA | Y | N | N | N | N | T1_SRV_FKMTST_DB |
| FKTSTDRDO | Y | N | N | N | N | T1_SRV_FKMTST_DB |
| PUBLIC | Y | N | N | N | N | DB2NT |
| SRV_DATAVAREHUS | Y | N | N | N | N | DB2NT, T1_SRV_FKMTST_DB |
| SRV_DB2 | Y | N | N | N | N | DB2NT |
| SRV_SFKSS07 | Y | N | N | N | N | DB2NT |
| T1_SRV_FKMTST_DB | Y | N | N | N | N | DB2NT |

### Bound COBOL Packages (1 program -- invalidated on DROP)

| Package |
|---|
| D3HBUNT |

### COBOL Programs with Direct SQL on D365_BUNTER (from Dedge-code RAG)

| Program | Operation | Detail |
|---|---|---|
| `d3hbunt.cbl` | SELECT | Main bunt handling program |
| `d5hbunt.cbl` | INSERT/UPDATE | Operates on `DBM.D365_BUNTER_NOTAT` (related table, not D365_BUNTER itself) |

---

## Summary: Recovery Steps After RENAME + CREATE LIKE

After executing:
```sql
RENAME TABLE DBM.VISMA_TRANSER TO VISMA_TRANSER_TMP;
CREATE TABLE DBM.VISMA_TRANSER LIKE DBM.VISMA_TRANSER_TMP;
-- (EXPORT/LOAD current year data into new table)
```

The following must be done to restore full functionality:

### 1. Recreate Indexes

Run the exported `*_indexes.sql` files. Order matters: create the primary key first,
then non-unique indexes. Index creation on a loaded table is faster than maintaining
indexes during bulk inserts.

### 2. Recreate Views

For `DBM.D365_BUNTER` only: recreate `TV.RPA_AVSTEMMING_BUNTER` using the exported DDL.
`VISMA_TRANSER` has no directly dependent views.

### 3. Re-apply Grants

Run the exported `*_grants.sql` files to restore all permissions on the new table.

### 4. Rebind COBOL Packages

Either rely on automatic revalidation (`auto_reval=DEFERRED`) or run:
```
db2rbind <database> -l rebind.log all
```

This rebinds all 46 packages for VISMA_TRANSER and 1 package for D365_BUNTER.

### 5. Application Downtime Consideration

- COBOL programs accessing VISMA_TRANSER (46 packages) will fail between the RENAME
  and the completion of index/grant recreation
- The view `TV.RPA_AVSTEMMING_BUNTER` will be inoperative until recreated
- Plan execution during a maintenance window or batch processing pause

---

## RAG MCP Access Summary

| RAG MCP | Result |
|---|---|
| db2-docs | Queried for DROP TABLE consequences; returned excerpts from `db2_sql_reference_1213.md` |
| Dedge-code | Queried for COBOL programs referencing VISMA_TRANSER and D365_BUNTER |
| db2-query (MCP) | Queried BASISTST catalog tables: SYSCAT.VIEWS, INDEXES, TRIGGERS, REFERENCES, TABDEP, TABAUTH, PACKAGEDEP, ROUTINEDEP, FUNCDEP, COLUMNS, TABLES |
