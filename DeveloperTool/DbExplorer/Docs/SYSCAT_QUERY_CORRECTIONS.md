# SYSCAT Query Corrections Based on Proven Patterns

This document lists all corrections to be made to SQL queries based on proven patterns from `Db2CreateDBQA_NonRelated.sql`.

## Key Findings from Proven Document

### 1. Views Query Pattern (Line 544-558)
**Proven Pattern:**
```sql
SELECT
    'VIEW' AS TYPE,
    'SYSCAT.VIEWS' AS SOURCE,
    V.VIEWSCHEMA AS SCHEMA,
    V.VIEWNAME AS NAME,
    V."DEFINER" AS LAST_CHANGE_BY,
    T.ALTER_TIME AS LAST_CHANGED_DATETIME,
    V.TEXT
FROM SYSCAT.TABLES T 
JOIN SYSCAT.VIEWS V ON T.TABSCHEMA = V.VIEWSCHEMA AND T.TABNAME = V.VIEWNAME
WHERE T.TYPE = 'V' AND T.TABSCHEMA IN (...)
```

**Key Points:**
- Start from `SYSCAT.TABLES` and join to `SYSCAT.VIEWS`
- Filter `T.TYPE = 'V'` to get views
- `REMARKS` comes from `SYSCAT.TABLES`
- `ALTER_TIME`, `DEFINER` come from `SYSCAT.TABLES`
- `TEXT`, `OWNER` come from `SYSCAT.VIEWS`

### 2. MQT (Materialized Query Tables) Pattern (Line 562-574)
**Proven Pattern:**
```sql
SELECT
    'MQT' AS TYPE,
    V.VIEWSCHEMA AS SCHEMA,
    V.VIEWNAME AS NAME,
    V."DEFINER" AS LAST_CHANGE_BY,
    T.ALTER_TIME AS LAST_CHANGED_DATETIME,
    V.TEXT
FROM SYSCAT.TABLES T 
JOIN SYSCAT.VIEWS V ON T.TABSCHEMA = V.VIEWSCHEMA AND T.TABNAME = V.VIEWNAME
WHERE T.TYPE = 'S' AND T.TABSCHEMA IN (...)
```

**Key Points:**
- MQTs have `T.TYPE = 'S'` (Staging/Summary table)
- Also need join between TABLES and VIEWS

### 3. Routines with Multiple Overloads (Line 526-527)
**Proven Pattern:**
```sql
CASE 
    WHEN ROUTINETYPE = 'P' THEN 
        TRIM(X.ROUTINESCHEMA) || '.' || X.ROUTINENAME || 
        CASE 
            WHEN (SELECT COUNT(*) FROM SYSCAT.ROUTINES Y 
                  WHERE X.ROUTINESCHEMA = Y.ROUTINESCHEMA 
                  AND X.ROUTINENAME = Y.ROUTINENAME) > 1        
            THEN '_PARAM_COUNT_' || TRIM(CHAR(X.PARM_COUNT))        
            ELSE ''        
        END || '.PRC.DDL.SQL'
    ELSE TRIM(X.ROUTINESCHEMA) || '.' || X.ROUTINENAME || '.FNC.DDL.SQL'
END AS FILENAME
```

**Key Points:**
- Procedures/Functions can have multiple overloads with same name
- Distinguish by parameter count when multiple exist
- Use `SPECIFICNAME` or `PARM_COUNT` to differentiate

### 4. Create Table Pattern (Line 170-188)
**Proven Pattern:**
```sql
SELECT
    X.TABSCHEMA,
    Y.TYPE AS TAB_TYPE,
    Y.REFRESH,
    X.TABNAME,
    Y.ALTER_TIME AS LAST_CHANGED_DATETIME,
    Y.DEFINER AS LAST_CHANGE_BY,
    VARCHAR(
        'CREATE TABLE ' || trim(X.TABSCHEMA) || '.' || trim(X.TABNAME) || ' (' || CHR(10) || 
        '#COLUMN_INFO#' || CHR(10) || 
        '   ) ' || CHR(10) || 
        CASE WHEN Y.DATACAPTURE = 'Y' THEN '   DATA CAPTURE CHANGES ' ELSE '   ' END || 
        'IN ' || TRIM(Y.TBSPACE) || ';' || CHR(10)
    ) AS TEXT
FROM SYSCAT.COLUMNS X
JOIN SYSCAT.TABLES Y ON X.TABSCHEMA = Y.TABSCHEMA AND X.TABNAME = Y.TABNAME 
    AND Y.TYPE IN ('T')
WHERE X.TABSCHEMA IN (...)
GROUP BY X.TABSCHEMA, Y.TYPE, Y.REFRESH, X.TABNAME, Y.DATACAPTURE, Y.TBSPACE, Y.ALTER_TIME, Y.DEFINER
```

**Key Points:**
- Join COLUMNS to TABLES
- GROUP BY to get unique table rows
- Include `DATACAPTURE`, `TBSPACE`, `ALTER_TIME`, `DEFINER`

### 5. Foreign Key Pattern (Line 274-396)
**Proven Pattern:**
```sql
SELECT
    FK.TABSCHEMA,
    FK.TABNAME,
    FK.CONSTNAME,
    VARCHAR(
        'ALTER TABLE ' || TRIM(FK.TABSCHEMA) || '.' || TRIM(FK.TABNAME) || 
        ' ADD CONSTRAINT ' || TRIM(FK.CONSTNAME) || ' FOREIGN KEY (' || 
        RTRIM(REPLACE(...)) ||  -- Multiple REPLACE to handle spaces
        ') REFERENCES ' || TRIM(FK.REFTABSCHEMA) || '.' || TRIM(FK.REFTABNAME) || 
        ' (' || RTRIM(REPLACE(...)) || ') ' ||
        CASE FK.DELETERULE
            WHEN 'C' THEN ' ON DELETE CASCADE'
            WHEN 'R' THEN ' ON DELETE RESTRICT'
            WHEN 'N' THEN ' ON DELETE SET NULL'
            WHEN 'A' THEN ' ON DELETE NO ACTION'
            ELSE ''
        END ||
        CASE FK.UPDATERULE
            WHEN 'R' THEN ' ON UPDATE RESTRICT'
            WHEN 'C' THEN ' ON UPDATE CASCADE'
            WHEN 'N' THEN ' ON UPDATE SET NULL'
            WHEN 'A' THEN ' ON UPDATE NO ACTION'
            ELSE ''
        END
    ) AS TEXT
FROM SYSCAT.REFERENCES FK
WHERE TABSCHEMA IN (...)
```

**Key Points:**
- Use `FK_COLNAMES` and `PK_COLNAMES` from `SYSCAT.REFERENCES`
- Multiple `REPLACE` calls to handle space padding
- Include `DELETERULE` and `UPDATERULE`

### 6. Index Pattern (Line 402-465)
**Proven Pattern:**
```sql
SELECT
    I.TABSCHEMA,
    I.TABNAME,
    I.INDNAME AS CONSTNAME,
    I.CREATE_TIME AS LAST_CHANGED_DATETIME,
    I.DEFINER AS LAST_CHANGE_BY,
    MAX(I.CREATE_TIME) AS LAST_ALTER_TIME,
    CASE 
        WHEN I.UNIQUERULE = 'P' THEN 'PRIMARY_KEY_INDEX'
        WHEN I.UNIQUERULE = 'U' THEN 'UNIQUE_INDEX'
        WHEN I.INDEXTYPE = 'REF' THEN 'REF_INDEX'
        WHEN I.INDEXTYPE = 'DIM' THEN 'DIMENSION_INDEX'
        ELSE 'INDEX'
    END AS TYPE,
    VARCHAR(
        'CREATE ' || 
        CASE WHEN I.UNIQUERULE IN ('U', 'P') THEN 'UNIQUE ' ELSE '' END || 
        CASE 
            WHEN I.INDEXTYPE = 'REF' THEN 'REF '
            WHEN I.INDEXTYPE = 'DIM' THEN 'DIMENSION '
            ELSE ''
        END ||
        'INDEX ' || TRIM(I.INDSCHEMA) || '.' || TRIM(I.INDNAME) || 
        ' ON ' || TRIM(I.TABSCHEMA) || '.' || TRIM(I.TABNAME) || 
        ' (' || LISTAGG(C.COLNAME || ' ' || CASE WHEN C.COLORDER = 'A' THEN 'ASC' ELSE 'DESC' END, ', ') 
                WITHIN GROUP (ORDER BY C.COLSEQ) || ')' ||
        CASE WHEN I.COMPRESSION = 'Y' THEN ' COMPRESSION' ELSE '' END || 
        CASE WHEN I.MINPCTUSED > 0 THEN ' MINPCTUSED ' || TRIM(CHAR(I.MINPCTUSED)) ELSE '' END || ';'
    ) AS TEXT
FROM SYSCAT.INDEXCOLUSE C
JOIN SYSCAT.INDEXES I ON C.INDNAME = I.INDNAME
WHERE I.TABSCHEMA IN (...)
GROUP BY I.INDNAME, I.INDSCHEMA, I.TABSCHEMA, I.TABNAME, I.INDEXTYPE, 
         I.COMPRESSION, I.MINPCTUSED, I.UNIQUERULE, I.CREATE_TIME, I.DEFINER
```

**Key Points:**
- Join `SYSCAT.INDEXCOLUSE` to `SYSCAT.INDEXES`
- Use `LISTAGG` with `COLORDER` (ASC/DESC)
- GROUP BY all index properties
- Include `COMPRESSION` and `MINPCTUSED`

### 7. Primary Key Pattern (Line 247-268)
**Proven Pattern:**
```sql
SELECT
    TABSCHEMA,
    TABNAME,
    CONSTNAME,
    VARCHAR(
        'ALTER TABLE ' || TRIM(TABSCHEMA) || '.' || TRIM(TABNAME) || 
        ' ADD PRIMARY KEY (' || 
        LISTAGG(TRIM(COLNAME), ', ') WITHIN GROUP (ORDER BY COLSEQ) || 
        ');'
    ) AS TEXT
FROM SYSCAT.KEYCOLUSE
WHERE TABSCHEMA IN (...)
GROUP BY TABSCHEMA, TABNAME, CONSTNAME
```

**Key Points:**
- Use `SYSCAT.KEYCOLUSE` directly
- Use `LISTAGG` to combine columns
- ORDER BY `COLSEQ`

### 8. Column Definition Pattern (Line 206-241)
**Proven Pattern:**
```sql
SELECT
    X.TABSCHEMA,
    X.TABNAME,
    X.COLNO,
    '"' || X.COLNAME || '"' || ' ' || X.TYPENAME || ' ' || 
    CASE
        WHEN X.TYPENAME = 'INTEGER' THEN ''
        WHEN X.TYPENAME = 'DECIMAL' THEN '(' || X.LENGTH || ',' || TRIM(CHAR(X.SCALE)) || ')'
        WHEN X.TYPENAME = 'TIMESTAMP' THEN '(' || TRIM(CHAR(X.SCALE)) || ')'
        WHEN X.TYPENAME = 'DATE' THEN ''
        ELSE '(' || X.LENGTH || ')'
    END || 
    CASE WHEN X.NULLS = 'N' THEN ' NOT NULL' ELSE '' END ||
    CASE WHEN X.DEFAULT IS NOT NULL THEN ' WITH DEFAULT ' || TRIM(X.DEFAULT) ELSE '' END
    AS TEXT
FROM SYSCAT.COLUMNS X
JOIN SYSCAT.TABLES Y ON X.TABSCHEMA = Y.TABSCHEMA AND X.TABNAME = Y.TABNAME 
    AND Y.TYPE IN ('T')
WHERE X.TABSCHEMA IN (...)
```

**Key Points:**
- Quote column names with `"`
- Handle type-specific length/scale logic
- Include `NULLS` and `DEFAULT`

### 9. View Drop Pattern (Line 846-856)
**Proven Pattern:**
```sql
SELECT
    VIEWSCHEMA AS schema_name,
    VIEWNAME AS object_name,
    'VIEW' AS object_type,
    'DROP VIEW ' || trim(VIEWSCHEMA) || '.' || trim(VIEWNAME) || ';' AS drop_statement
FROM SYSCAT.TABLES T 
JOIN SYSCAT.VIEWS V ON T.TABSCHEMA = V.VIEWSCHEMA AND T.TABNAME = V.VIEWNAME 
WHERE T.TYPE = 'V' AND T.TABSCHEMA IN (...)
```

**Key Points:**
- Always join TABLES and VIEWS
- Filter by `T.TYPE = 'V'`

### 10. Package SQL Statements Pattern (Line 680-692)
**Proven Pattern:**
```sql
SELECT
    z.PKGSCHEMA,
    z.PKGNAME,
    z.LASTUSED,
    x.TEXT
FROM SYSCAT.STATEMENTS x
JOIN SYSCAT.PACKAGES z ON x.PKGSCHEMA = z.PKGSCHEMA AND x.PKGNAME = z.PKGNAME
WHERE z.LASTUSED > CURRENT DATE - 3 YEARS
```

**Key Points:**
- Join `SYSCAT.STATEMENTS` to `SYSCAT.PACKAGES`
- Match on both `PKGSCHEMA` and `PKGNAME`

## Required Code Changes

### 1. Services/ObjectBrowserService.cs - GetViewsAsync
**Current:**
```sql
SELECT 
    TRIM(V.VIEWNAME) AS VIEWNAME,
    TRIM(V.OWNER) AS OWNER,
    TRIM(T.REMARKS) AS REMARKS
FROM SYSCAT.VIEWS V
JOIN SYSCAT.TABLES T ON V.VIEWSCHEMA = T.TABSCHEMA AND V.VIEWNAME = T.TABNAME
WHERE V.VIEWSCHEMA = ?
ORDER BY V.VIEWNAME
```

**Should Be (Based on Proven Pattern):**
```sql
SELECT 
    TRIM(V.VIEWNAME) AS VIEWNAME,
    TRIM(V.DEFINER) AS OWNER,
    TRIM(T.REMARKS) AS REMARKS,
    T.ALTER_TIME
FROM SYSCAT.TABLES T 
JOIN SYSCAT.VIEWS V ON T.TABSCHEMA = V.VIEWSCHEMA AND T.TABNAME = V.VIEWNAME
WHERE T.TYPE = 'V' AND T.TABSCHEMA = ?
ORDER BY V.VIEWNAME
```

**Note:** Use `V.DEFINER` instead of `V.OWNER`, and include `T.ALTER_TIME`

### 2. Dialogs/PackageDetailsDialog.xaml.cs - GetPackageStatements
**Current:**
```sql
SELECT 
    TRIM(STMTNO) AS StmtNo,
    TRIM(SECTNO) AS SectionNo,
    TRIM(SEQNO) AS SeqNo,
    TRIM(TEXT) AS StatementText
FROM SYSCAT.STATEMENTS
WHERE PKGSCHEMA = ? AND PKGNAME = ?
ORDER BY STMTNO, SECTNO, SEQNO
```

**Should Be (Based on Proven Pattern):**
```sql
SELECT 
    TRIM(S.STMTNO) AS StmtNo,
    TRIM(S.SECTNO) AS SectionNo,
    TRIM(S.SEQNO) AS SeqNo,
    TRIM(S.TEXT) AS StatementText,
    P.LASTUSED
FROM SYSCAT.STATEMENTS S
JOIN SYSCAT.PACKAGES P ON S.PKGSCHEMA = P.PKGSCHEMA AND S.PKGNAME = P.PKGNAME
WHERE S.PKGSCHEMA = ? AND S.PKGNAME = ?
ORDER BY S.STMTNO, S.SECTNO, S.SEQNO
```

**Note:** Join to PACKAGES to get additional metadata like `LASTUSED`

### 3. Services/DdlGeneratorService.cs - GenerateIndexDdl
**Should Use Pattern from Line 402-465:**
- Join `SYSCAT.INDEXCOLUSE` to `SYSCAT.INDEXES`
- Use `LISTAGG` with `COLORDER` (ASC/DESC)
- Include `COMPRESSION` and `MINPCTUSED`

### 4. Services/DdlGeneratorService.cs - GenerateForeignKeyDdl
**Should Use Pattern from Line 274-396:**
- Use `FK_COLNAMES` and `PK_COLNAMES` directly from `SYSCAT.REFERENCES`
- Include multiple `REPLACE` to handle space padding
- Include `DELETERULE` and `UPDATERULE` CASE statements

### 5. Dialogs/TableDetailsDialog.xaml.cs - GetColumns
**Should Use Pattern from Line 206-241:**
- Quote column names with `"`
- Type-specific length/scale handling
- Include `DEFAULT` with `WITH DEFAULT` keyword

## Summary of Key Patterns

1. **Views**: Always join `SYSCAT.TABLES` (T.TYPE='V') with `SYSCAT.VIEWS`
2. **Owner/Definer**: Use `DEFINER` from source table, not `OWNER`
3. **Timestamps**: Use `ALTER_TIME` from `SYSCAT.TABLES` for views
4. **Foreign Keys**: Use `FK_COLNAMES`/`PK_COLNAMES` directly from `SYSCAT.REFERENCES`
5. **Indexes**: Join `INDEXCOLUSE` to get column order (ASC/DESC)
6. **Primary Keys**: Use `LISTAGG` on `SYSCAT.KEYCOLUSE`
7. **Space Padding**: Multiple `REPLACE` calls or `TRIM` + `RTRIM`
8. **Package Statements**: Always join to `SYSCAT.PACKAGES` for metadata
9. **Quotes**: Column names should be quoted with `"`
10. **Type Filtering**: Use `TYPE` column in `SYSCAT.TABLES` ('V'=View, 'S'=MQT, 'T'=Table)

## Testing Priority

1. ✅ Views query (already corrected)
2. Package SQL statements query
3. Index DDL generation
4. Foreign Key DDL generation
5. Column definitions with quoted names
6. Primary Key DDL with LISTAGG
7. Table creation DDL with DATACAPTURE

