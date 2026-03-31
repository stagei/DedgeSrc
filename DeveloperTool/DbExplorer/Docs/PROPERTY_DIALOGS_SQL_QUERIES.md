# Property Dialogs SQL Queries Reference

This document contains all SQL queries used in property dialogs/windows for various database objects.

## Table of Contents
- [Table Details Dialog](#table-details-dialog)
- [Package Details Dialog](#package-details-dialog)
- [User/Role/Group Details Dialog](#userrolegroup-details-dialog)
- [Object Details Dialog (Generic)](#object-details-dialog-generic)

---

## Table Details Dialog

### Get Table Columns
```sql
SELECT 
    TRIM(COLNAME) AS ColumnName,
    TRIM(TYPENAME) AS DataType,
    LENGTH,
    SCALE,
    CASE WHEN NULLS = 'Y' THEN 'Yes' ELSE 'No' END AS Nullable,
    COALESCE(TRIM(DEFAULT), '-') AS DefaultValue,
    COALESCE(TRIM(REMARKS), '') AS Remarks
FROM SYSCAT.COLUMNS 
WHERE TABSCHEMA = ? AND TABNAME = ?
ORDER BY COLNO
```

**Parameters:**
- `?` (1) = `schemaName` (trimmed)
- `?` (2) = `tableName` (trimmed)

---

### Get Primary Key
```sql
SELECT 
    TRIM(CONSTNAME) AS ConstraintName,
    TRIM(COLNAME) AS ColumnName
FROM SYSCAT.KEYCOLUSE
WHERE TABSCHEMA = ? AND TABNAME = ?
  AND CONSTNAME IN (
      SELECT CONSTNAME 
      FROM SYSCAT.TABCONST 
      WHERE TABSCHEMA = ? AND TABNAME = ?
        AND TYPE = 'P'
  )
ORDER BY COLSEQ
```

**Parameters:**
- `?` (1) = `schemaName` (trimmed)
- `?` (2) = `tableName` (trimmed)
- `?` (3) = `schemaName` (trimmed)
- `?` (4) = `tableName` (trimmed)

---

### Get Foreign Keys
```sql
SELECT 
    TRIM(R.CONSTNAME) AS FKName,
    TRIM(R.REFTABSCHEMA) AS RefSchema,
    TRIM(R.REFTABNAME) AS RefTable,
    TRIM(K.COLNAME) AS ColumnName,
    TRIM(R.DELETERULE) AS DeleteRule,
    TRIM(R.UPDATERULE) AS UpdateRule
FROM SYSCAT.REFERENCES R
JOIN SYSCAT.KEYCOLUSE K ON R.CONSTNAME = K.CONSTNAME 
    AND R.TABSCHEMA = K.TABSCHEMA 
    AND R.TABNAME = K.TABNAME
WHERE R.TABSCHEMA = ? AND R.TABNAME = ?
ORDER BY R.CONSTNAME, K.COLSEQ
```

**Parameters:**
- `?` (1) = `schemaName` (trimmed)
- `?` (2) = `tableName` (trimmed)

**Delete/Update Rules:**
- `C` = Cascade
- `A` = No action
- `N` = Set null
- `R` = Restrict

---

### Get Table Indexes
```sql
SELECT 
    TRIM(INDNAME) AS IndexName,
    TRIM(UNIQUERULE) AS UniqueRule,
    TRIM(COLNAMES) AS Columns,
    TRIM(INDEXTYPE) AS IndexType,
    TRIM(REMARKS) AS Remarks
FROM SYSCAT.INDEXES
WHERE TABSCHEMA = ? AND TABNAME = ?
ORDER BY INDNAME
```

**Parameters:**
- `?` (1) = `schemaName` (trimmed)
- `?` (2) = `tableName` (trimmed)

---

### Get Table Statistics
```sql
SELECT 
    CARD AS RowCount,
    NPAGES AS NumberOfPages,
    FPAGES AS FormattedPages,
    OVERFLOW AS OverflowPages,
    STATS_TIME AS LastStatsTime
FROM SYSCAT.TABLES
WHERE TABSCHEMA = ? AND TABNAME = ?
```

**Parameters:**
- `?` (1) = `schemaName` (trimmed)
- `?` (2) = `tableName` (trimmed)

---

### Get Table DDL (CREATE)
```sql
-- Note: DB2 doesn't have built-in DDL extraction
-- This is constructed programmatically from SYSCAT metadata
SELECT 
    TRIM(T.TABSCHEMA) AS TabSchema,
    TRIM(T.TABNAME) AS TabName,
    TRIM(T.TBSPACE) AS Tablespace,
    TRIM(T.REMARKS) AS Remarks,
    T.COMPRESSION,
    T.CARD,
    T.NPAGES
FROM SYSCAT.TABLES T
WHERE T.TABSCHEMA = ? AND T.TABNAME = ?
```

**Parameters:**
- `?` (1) = `schemaName` (trimmed)
- `?` (2) = `tableName` (trimmed)

---

## Package Details Dialog

### Get Package Properties
```sql
SELECT 
    TRIM(PKGSCHEMA) AS PackageSchema,
    TRIM(PKGNAME) AS PackageName,
    TRIM(BOUNDBY) AS BoundBy,
    TRIM(OWNER) AS Owner,
    TRIM(ISOLATION) AS Isolation,
    CREATE_TIME,
    TRIM(REMARKS) AS Remarks
FROM SYSCAT.PACKAGES
WHERE PKGSCHEMA = ? AND PKGNAME = ?
```

**Parameters:**
- `?` (1) = `packageSchema` (trimmed)
- `?` (2) = `packageName` (trimmed)

---

### Get Package SQL Statements
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

**Parameters:**
- `?` (1) = `packageSchema` (trimmed)
- `?` (2) = `packageName` (trimmed)

**Note:** Multiple rows with same STMTNO/SECTNO represent a single statement split across rows. Concatenate TEXT fields.

---

## User/Role/Group Details Dialog

### Get Database Authorities for Principal
```sql
SELECT 
    DBADMAUTH,
    SECADMAUTH,
    DATAACCESSAUTH,
    ACCESSCTRLAUTH,
    CREATETABAUTH,
    BINDADDAUTH,
    CONNECTAUTH,
    NOFENCEAUTH,
    IMPLICIT_SCHEMAAUTH,
    LOADAUTH,
    EXTERNALROUTINEAUTH,
    QUIESCECONNECTAUTH
FROM SYSCAT.DBAUTH
WHERE GRANTEE = ?
```

**Parameters:**
- `?` = `principalName` (trimmed)

---

### Get Table Privileges for Principal
```sql
SELECT 
    TRIM(TABSCHEMA) AS Schema,
    TRIM(TABNAME) AS TableName,
    CONTROLAUTH AS ControlAuth,
    ALTERAUTH AS AlterAuth,
    DELETEAUTH AS DeleteAuth,
    INSERTAUTH AS InsertAuth,
    SELECTAUTH AS SelectAuth,
    UPDATEAUTH AS UpdateAuth,
    REFAUTH AS RefAuth,
    INDEXAUTH AS IndexAuth
FROM SYSCAT.TABAUTH
WHERE GRANTEE = ?
  AND GRANTEETYPE = ?
ORDER BY TABSCHEMA, TABNAME
```

**Parameters:**
- `?` (1) = `principalName` (trimmed)
- `?` (2) = `granteeType` ('U' for user, 'G' for group, 'R' for role)

---

### Get Schema Privileges for Principal
```sql
SELECT 
    TRIM(SCHEMANAME) AS SchemaName,
    ALTERINAUTH AS AlterInAuth,
    CREATEINAUTH AS CreateInAuth,
    DROPINAUTH AS DropInAuth
FROM SYSCAT.SCHEMAAUTH
WHERE GRANTEE = ?
  AND GRANTEETYPE = ?
ORDER BY SCHEMANAME
```

**Parameters:**
- `?` (1) = `principalName` (trimmed)
- `?` (2) = `granteeType` ('U' for user, 'G' for group, 'R' for role)

---

### Get Routine Privileges for Principal
```sql
SELECT 
    TRIM(SCHEMA) AS Schema,
    TRIM(SPECIFICNAME) AS SpecificName,
    TRIM(ROUTINENAME) AS RoutineName,
    EXECUTEAUTH AS ExecuteAuth
FROM SYSCAT.ROUTINEAUTH
WHERE GRANTEE = ?
  AND GRANTEETYPE = ?
ORDER BY SCHEMA, SPECIFICNAME
```

**Parameters:**
- `?` (1) = `principalName` (trimmed)
- `?` (2) = `granteeType` ('U' for user, 'G' for group, 'R' for role)

---

### Get Role Memberships for User
```sql
SELECT 
    TRIM(ROLENAME) AS RoleName
FROM SYSCAT.ROLEAUTH
WHERE GRANTEE = ?
  AND GRANTEETYPE = 'U'
ORDER BY ROLENAME
```

**Parameters:**
- `?` = `userName` (trimmed)

---

### Get Members of Role/Group
```sql
SELECT 
    TRIM(GRANTEE) AS Grantee,
    TRIM(GRANTEETYPE) AS GranteeType
FROM SYSCAT.ROLEAUTH
WHERE ROLENAME = ?
ORDER BY GRANTEE
```

**Parameters:**
- `?` = `roleName` or `groupName` (trimmed)

**Grantee Types:**
- `U` = User
- `G` = Group
- `R` = Role

---

## Object Details Dialog (Generic)

### Get View Definition
```sql
SELECT 
    TRIM(TEXT) AS ViewDefinition
FROM SYSCAT.VIEWS
WHERE VIEWSCHEMA = ? AND VIEWNAME = ?
```

**Parameters:**
- `?` (1) = `schemaName` (trimmed)
- `?` (2) = `viewName` (trimmed)

---

### Get Routine Definition (Procedure/Function)
```sql
SELECT 
    TRIM(TEXT) AS RoutineDefinition,
    TRIM(LANGUAGE) AS Language,
    PARM_COUNT AS ParameterCount,
    TRIM(ORIGIN) AS Origin,
    TRIM(DETERMINISTIC) AS Deterministic,
    TRIM(SQL_DATA_ACCESS) AS SqlDataAccess
FROM SYSCAT.ROUTINES
WHERE ROUTINESCHEMA = ? AND ROUTINENAME = ?
```

**Parameters:**
- `?` (1) = `schemaName` (trimmed)
- `?` (2) = `routineName` (trimmed)

---

### Get Trigger Definition
```sql
SELECT 
    TRIM(TEXT) AS TriggerDefinition,
    TRIM(TRIGEVENT) AS TriggerEvent,
    TRIM(TRIGTIME) AS TriggerTime,
    TRIM(TABSCHEMA) AS TableSchema,
    TRIM(TABNAME) AS TableName,
    TRIM(GRANULARITY) AS Granularity
FROM SYSCAT.TRIGGERS
WHERE TRIGSCHEMA = ? AND TRIGNAME = ?
```

**Parameters:**
- `?` (1) = `schemaName` (trimmed)
- `?` (2) = `triggerName` (trimmed)

---

### Get Index Details
```sql
SELECT 
    TRIM(INDNAME) AS IndexName,
    TRIM(TABSCHEMA) AS TableSchema,
    TRIM(TABNAME) AS TableName,
    TRIM(UNIQUERULE) AS UniqueRule,
    TRIM(INDEXTYPE) AS IndexType,
    TRIM(COLNAMES) AS ColumnNames,
    NLEAF AS NumberOfLeafPages,
    NLEVELS AS NumberOfLevels,
    FULLKEYCARD AS FullKeyCardinality,
    CLUSTERRATIO AS ClusterRatio,
    CREATE_TIME,
    TRIM(REMARKS) AS Remarks
FROM SYSCAT.INDEXES
WHERE INDSCHEMA = ? AND INDNAME = ?
```

**Parameters:**
- `?` (1) = `schemaName` (trimmed)
- `?` (2) = `indexName` (trimmed)

---

### Get Sequence Details
```sql
SELECT 
    TRIM(SEQNAME) AS SequenceName,
    TRIM(SEQTYPE) AS SequenceType,
    START AS StartValue,
    INCREMENT AS IncrementBy,
    MINVALUE,
    MAXVALUE,
    TRIM(CYCLE) AS Cycle,
    CACHE AS CacheSize,
    TRIM(ORDER) AS OrderFlag,
    CREATE_TIME,
    TRIM(REMARKS) AS Remarks
FROM SYSCAT.SEQUENCES
WHERE SEQSCHEMA = ? AND SEQNAME = ?
```

**Parameters:**
- `?` (1) = `schemaName` (trimmed)
- `?` (2) = `sequenceName` (trimmed)

---

### Get Synonym/Alias Details
```sql
SELECT 
    TRIM(TABNAME) AS AliasName,
    TRIM(BASE_TABSCHEMA) AS BaseSchema,
    TRIM(BASE_TABNAME) AS BaseTable,
    TRIM(OWNER) AS Owner,
    CREATE_TIME,
    TRIM(REMARKS) AS Remarks
FROM SYSCAT.TABLES
WHERE TABSCHEMA = ? AND TABNAME = ?
  AND TYPE = 'A'
```

**Parameters:**
- `?` (1) = `schemaName` (trimmed)
- `?` (2) = `aliasName` (trimmed)

---

### Get User-Defined Type Details
```sql
SELECT 
    TRIM(TYPENAME) AS TypeName,
    TRIM(METATYPE) AS MetaType,
    TRIM(SOURCESCHEMA) AS SourceSchema,
    TRIM(SOURCENAME) AS SourceName,
    LENGTH,
    SCALE,
    TRIM(OWNER) AS Owner,
    CREATE_TIME,
    TRIM(REMARKS) AS Remarks
FROM SYSCAT.DATATYPES
WHERE TYPESCHEMA = ? AND TYPENAME = ?
```

**Parameters:**
- `?` (1) = `schemaName` (trimmed)
- `?` (2) = `typeName` (trimmed)

---

### Get Tablespace Details
```sql
SELECT 
    TRIM(TBSPACE) AS TablespaceName,
    TRIM(TBSPACETYPE) AS TablespaceType,
    TRIM(DATATYPE) AS DataType,
    PAGESIZE,
    EXTENTSIZE,
    PREFETCHSIZE,
    TRIM(OWNER) AS Owner,
    CREATE_TIME,
    TRIM(REMARKS) AS Remarks
FROM SYSCAT.TABLESPACES
WHERE TBSPACE = ?
```

**Parameters:**
- `?` = `tablespaceName` (trimmed)

---

## DDL Generation Queries

### Generate CREATE TABLE DDL
Requires combining multiple queries:
1. Table definition (from SYSCAT.TABLES)
2. Column definitions (from SYSCAT.COLUMNS)
3. Primary key (from SYSCAT.TABCONST + SYSCAT.KEYCOLUSE)
4. Foreign keys (from SYSCAT.REFERENCES + SYSCAT.KEYCOLUSE)
5. Indexes (from SYSCAT.INDEXES)
6. Comments (from SYSCAT.TABLES.REMARKS + SYSCAT.COLUMNS.REMARKS)

### Generate DROP DDL
```sql
-- Generic DROP statement
DROP {OBJECT_TYPE} {SCHEMA}.{OBJECT_NAME}
```

Examples:
- `DROP TABLE SCHEMA.TABLENAME`
- `DROP VIEW SCHEMA.VIEWNAME`
- `DROP PROCEDURE SCHEMA.PROCNAME`
- `DROP FUNCTION SCHEMA.FUNCNAME`
- `DROP INDEX SCHEMA.INDEXNAME`
- `DROP TRIGGER SCHEMA.TRIGGERNAME`
- `DROP SEQUENCE SCHEMA.SEQNAME`

---

## Common Issues & Solutions

### Space Padding
**Problem:** DB2 stores names in `CHAR` columns which are space-padded.

**Solution:**
- Always use `TRIM()` in SQL: `TRIM(COLNAME) AS COLNAME`
- Always `.Trim()` in C#: `reader.GetString(0).Trim()`
- Trim parameter values before binding: `schemaName.Trim()`

### Parameter Binding
**Problem:** Named parameters (`@param`) vs positional (`?`)

**Solution:**
- Use positional parameters (`?`) for DB2
- Remove `@` prefix from parameter names
- Trim values before adding to parameters

### NULL Handling
**Problem:** `DBNull.Value` in C# when database column is NULL

**Solution:**
```csharp
var value = reader.IsDBNull(columnIndex) 
    ? string.Empty 
    : reader.GetString(columnIndex).Trim();
```

### Multi-Row Text
**Problem:** Some TEXT fields (like SYSCAT.STATEMENTS.TEXT) span multiple rows

**Solution:**
- Order by sequence number
- Concatenate TEXT values
- Example: `ORDER BY STMTNO, SECTNO, SEQNO`

---

## Testing Queries

### Quick Test Template
```sql
-- Replace placeholders with actual values
-- Test on your DB2 server using db2 command line or another tool

-- Example: Test Views query for TV schema
SELECT 
    TRIM(VIEWNAME) AS VIEWNAME,
    TRIM(OWNER) AS OWNER,
    TRIM(REMARKS) AS REMARKS
FROM SYSCAT.VIEWS
WHERE VIEWSCHEMA = 'TV'
ORDER BY VIEWNAME;

-- Example: Test Package SQL statements
SELECT 
    TRIM(STMTNO) AS StmtNo,
    TRIM(SECTNO) AS SectionNo,
    TRIM(SEQNO) AS SeqNo,
    TRIM(TEXT) AS StatementText
FROM SYSCAT.STATEMENTS
WHERE PKGSCHEMA = 'AKA' AND PKGNAME = 'BUHSTART'
ORDER BY STMTNO, SECTNO, SEQNO;
```

### Verification Checklist
- [ ] Query returns expected rows
- [ ] No space padding in results (all strings trimmed)
- [ ] NULL values handled gracefully
- [ ] Column names match C# code expectations
- [ ] ORDER BY clause produces consistent results
- [ ] Parameters bind correctly (test with literal values first)

