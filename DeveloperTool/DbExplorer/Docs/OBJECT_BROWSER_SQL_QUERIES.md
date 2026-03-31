# Object Browser SQL Queries Reference

This document contains all SQL queries used to populate the Object Browser tree view.

## Table of Contents
- [Top-Level Categories](#top-level-categories)
- [Schemas](#schemas)
- [Tables](#tables)
- [Views](#views)
- [Procedures](#procedures)
- [Functions](#functions)
- [Indexes](#indexes)
- [Triggers](#triggers)
- [Sequences](#sequences)
- [Synonyms](#synonyms)
- [Packages](#packages)
- [User-Defined Types](#user-defined-types)
- [Tablespaces](#tablespaces)
- [Security (Roles, Groups, Users)](#security)

---

## Top-Level Categories

### Get Category Counts

**Schemas Count:**
```sql
SELECT COUNT(DISTINCT SCHEMANAME) 
FROM SYSCAT.SCHEMATA
```

**Tables Count:**
```sql
SELECT COUNT(*) 
FROM SYSCAT.TABLES 
WHERE TYPE IN ('T', 'S', 'G', 'H', 'L', 'N', 'U', 'W')
```

**Views Count:**
```sql
SELECT COUNT(*) 
FROM SYSCAT.VIEWS
```

**Procedures Count:**
```sql
SELECT COUNT(*) 
FROM SYSCAT.ROUTINES 
WHERE ROUTINETYPE = 'P'
```

**Functions Count:**
```sql
SELECT COUNT(*) 
FROM SYSCAT.ROUTINES 
WHERE ROUTINETYPE = 'F'
```

**Indexes Count:**
```sql
SELECT COUNT(*) 
FROM SYSCAT.INDEXES
```

**Triggers Count:**
```sql
SELECT COUNT(*) 
FROM SYSCAT.TRIGGERS
```

**Sequences Count:**
```sql
SELECT COUNT(*) 
FROM SYSCAT.SEQUENCES 
WHERE SEQTYPE = 'S'
```

**Synonyms Count:**
```sql
SELECT COUNT(*) 
FROM SYSCAT.TABLES 
WHERE TYPE = 'A'
```

**Packages Count:**
```sql
SELECT COUNT(*) 
FROM SYSCAT.PACKAGES
```

**User-Defined Types Count:**
```sql
SELECT COUNT(*) 
FROM SYSCAT.DATATYPES 
WHERE METATYPE IN ('S', 'D')
```

**Tablespaces Count:**
```sql
SELECT COUNT(*) 
FROM SYSCAT.TABLESPACES
```

**Aliases Count:**
```sql
SELECT COUNT(*) 
FROM SYSCAT.TABLES 
WHERE TYPE = 'A'
```

---

## Schemas

### Get All Schemas
```sql
SELECT 
    TRIM(SCHEMANAME) AS SCHEMANAME, 
    TRIM(OWNER) AS OWNER, 
    CREATE_TIME, 
    TRIM(REMARKS) AS REMARKS
FROM SYSCAT.SCHEMATA
ORDER BY SCHEMANAME
```

**System Schemas:** `SYSCAT`, `SYSIBM`, `SYSFUN`, `SYSPROC`, `SYSSTAT`, `SYSTOOLS`, `SYSIBMADM`, `SYSIBMTS`, `SYSPUBLIC`, `NULLID`

---

## Tables

### Get Tables for Schema
```sql
SELECT 
    TRIM(TABNAME) AS TABNAME,
    TRIM(TYPE) AS TYPE,
    TRIM(OWNER) AS OWNER,
    CARD AS ROW_COUNT,
    TRIM(TBSPACE) AS TBSPACE,
    CREATE_TIME,
    TRIM(REMARKS) AS REMARKS
FROM SYSCAT.TABLES
WHERE TABSCHEMA = ?
  AND TYPE IN ('T', 'S', 'G', 'H', 'L', 'N', 'U', 'W')
ORDER BY TABNAME
```

**Parameters:**
- `?` = `schemaName` (trimmed)

**Table Types:**
- `T` = Table
- `S` = Staging table
- `G` = Global temporary table
- `H` = Hierarchy table
- `L` = Auxiliary table
- `N` = Nickname
- `U` = Typed table
- `W` = Typed view

---

## Views

### Get Views for Schema
```sql
SELECT 
    TRIM(V.VIEWNAME) AS VIEWNAME,
    TRIM(T.DEFINER) AS OWNER,
    TRIM(T.REMARKS) AS REMARKS,
    T.ALTER_TIME
FROM SYSCAT.TABLES T
JOIN SYSCAT.VIEWS V ON T.TABSCHEMA = V.VIEWSCHEMA 
    AND T.TABNAME = V.VIEWNAME
WHERE T.TYPE = 'V' AND T.TABSCHEMA = ?
ORDER BY V.VIEWNAME
```

**Parameters:**
- `?` = `schemaName` (trimmed)

**Note:** 
- PROVEN PATTERN from Db2CreateDBQA_NonRelated.sql (Line 544-558)
- CRITICAL: Start from SYSCAT.TABLES (not VIEWS) and join to VIEWS
- Filter by T.TYPE = 'V' to get views
- REMARKS comes from SYSCAT.TABLES, not SYSCAT.VIEWS
- Use DEFINER (not OWNER) from TABLES for consistency
- ALTER_TIME comes from TABLES

---

## Procedures

### Get Procedures for Schema
```sql
SELECT 
    TRIM(ROUTINENAME) AS ROUTINENAME,
    TRIM(SPECIFICNAME) AS SPECIFICNAME,
    TRIM(LANGUAGE) AS LANGUAGE,
    PARM_COUNT,
    CREATE_TIME,
    TRIM(OWNER) AS OWNER,
    TRIM(REMARKS) AS REMARKS
FROM SYSCAT.ROUTINES
WHERE ROUTINESCHEMA = ?
  AND ROUTINETYPE = 'P'
ORDER BY ROUTINENAME
```

**Parameters:**
- `?` = `schemaName` (trimmed)

---

## Functions

### Get Functions for Schema
```sql
SELECT 
    TRIM(ROUTINENAME) AS ROUTINENAME,
    TRIM(SPECIFICNAME) AS SPECIFICNAME,
    TRIM(LANGUAGE) AS LANGUAGE,
    PARM_COUNT,
    TRIM(FUNCTIONTYPE) AS FUNCTIONTYPE,
    CREATE_TIME,
    TRIM(OWNER) AS OWNER,
    TRIM(REMARKS) AS REMARKS
FROM SYSCAT.ROUTINES
WHERE ROUTINESCHEMA = ?
  AND ROUTINETYPE = 'F'
ORDER BY ROUTINENAME
```

**Parameters:**
- `?` = `schemaName` (trimmed)

**Function Types:**
- `S` = Scalar function
- `T` = Table function
- `R` = Row function

---

## Indexes

### Get Indexes for Schema
```sql
SELECT 
    TRIM(INDNAME) AS INDNAME,
    TRIM(TABNAME) AS TABNAME,
    TRIM(TABSCHEMA) AS TABSCHEMA,
    TRIM(UNIQUERULE) AS UNIQUERULE,
    TRIM(INDEXTYPE) AS INDEXTYPE,
    TRIM(COLNAMES) AS COLNAMES,
    TRIM(REMARKS) AS REMARKS
FROM SYSCAT.INDEXES
WHERE INDSCHEMA = ?
ORDER BY INDNAME
```

**Parameters:**
- `?` = `schemaName` (trimmed)

**Unique Rules:**
- `P` = Primary key
- `U` = Unique
- `D` = Duplicates allowed

**Index Types:**
- `CLUS` = Clustering
- `REG` = Regular
- `DIM` = Dimension block

---

## Triggers

### Get Triggers for Schema
```sql
SELECT 
    TRIM(TRIGNAME) AS TRIGNAME,
    TRIM(TABNAME) AS TABNAME,
    TRIM(TABSCHEMA) AS TABSCHEMA,
    TRIM(TRIGEVENT) AS TRIGEVENT,
    TRIM(TRIGTIME) AS TRIGTIME,
    CREATE_TIME,
    TRIM(REMARKS) AS REMARKS
FROM SYSCAT.TRIGGERS
WHERE TRIGSCHEMA = ?
ORDER BY TRIGNAME
```

**Parameters:**
- `?` = `schemaName` (trimmed)

**Trigger Events:**
- `I` = Insert
- `U` = Update
- `D` = Delete

**Trigger Times:**
- `A` = After
- `B` = Before
- `I` = Instead of

---

## Sequences

### Get Sequences for Schema
```sql
SELECT 
    TRIM(SEQNAME) AS SEQNAME,
    TRIM(SEQTYPE) AS SEQTYPE,
    START,
    INCREMENT,
    MINVALUE,
    MAXVALUE,
    TRIM(CYCLE) AS CYCLE,
    CACHE,
    TRIM(ORDER) AS ORDER_FLAG,
    CREATE_TIME,
    TRIM(REMARKS) AS REMARKS
FROM SYSCAT.SEQUENCES
WHERE SEQSCHEMA = ?
  AND SEQTYPE = 'S'
ORDER BY SEQNAME
```

**Parameters:**
- `?` = `schemaName` (trimmed)

---

## Synonyms

### Get Synonyms for Schema
```sql
SELECT 
    TRIM(TABNAME) AS TABNAME,
    TRIM(BASE_TABSCHEMA) AS BASE_TABSCHEMA,
    TRIM(BASE_TABNAME) AS BASE_TABNAME,
    TRIM(OWNER) AS OWNER,
    TRIM(REMARKS) AS REMARKS
FROM SYSCAT.TABLES
WHERE TABSCHEMA = ?
  AND TYPE = 'A'
ORDER BY TABNAME
```

**Parameters:**
- `?` = `schemaName` (trimmed)

---

## Packages

### Get All Packages
```sql
SELECT 
    TRIM(PKGSCHEMA) AS PKGSCHEMA,
    TRIM(PKGNAME) AS PKGNAME,
    TRIM(BOUNDBY) AS BOUNDBY,
    TRIM(OWNER) AS OWNER,
    TRIM(ISOLATION) AS ISOLATION,
    CREATE_TIME,
    TRIM(REMARKS) AS REMARKS
FROM SYSCAT.PACKAGES
ORDER BY PKGSCHEMA, PKGNAME
```

### Get Packages for Schema
```sql
SELECT 
    TRIM(PKGNAME) AS PKGNAME,
    TRIM(BOUNDBY) AS BOUNDBY,
    TRIM(OWNER) AS OWNER,
    TRIM(ISOLATION) AS ISOLATION,
    CREATE_TIME,
    TRIM(REMARKS) AS REMARKS
FROM SYSCAT.PACKAGES
WHERE PKGSCHEMA = ?
ORDER BY PKGNAME
```

**Parameters:**
- `?` = `schemaName` (trimmed)

---

## User-Defined Types

### Get Types for Schema
```sql
SELECT 
    TRIM(TYPENAME) AS TYPENAME,
    TRIM(METATYPE) AS METATYPE,
    TRIM(OWNER) AS OWNER,
    CREATE_TIME,
    TRIM(REMARKS) AS REMARKS
FROM SYSCAT.DATATYPES
WHERE TYPESCHEMA = ?
  AND METATYPE IN ('S', 'D')
ORDER BY TYPENAME
```

**Parameters:**
- `?` = `schemaName` (trimmed)

**Meta Types:**
- `S` = System type
- `D` = Distinct type

---

## Tablespaces

### Get All Tablespaces
```sql
SELECT 
    TRIM(TBSPACE) AS TBSPACE,
    TRIM(TBSPACETYPE) AS TBSPACETYPE,
    TRIM(DATATYPE) AS DATATYPE,
    PAGESIZE,
    TRIM(OWNER) AS OWNER,
    CREATE_TIME,
    TRIM(REMARKS) AS REMARKS
FROM SYSCAT.TABLESPACES
ORDER BY TBSPACE
```

**Tablespace Types:**
- `D` = Database-managed space (DMS)
- `S` = System-managed space (SMS)
- `A` = Automatic storage

**Data Types:**
- `A` = Any
- `L` = Long
- `T` = Temporary

---

## Security

### Roles

#### Get All Roles
```sql
SELECT DISTINCT 
    TRIM(ROLENAME) AS ROLENAME,
    TRIM(OWNER) AS OWNER,
    CREATE_TIME,
    TRIM(REMARKS) AS REMARKS
FROM SYSCAT.ROLES
ORDER BY ROLENAME
```

#### Get Role Members
```sql
SELECT 
    TRIM(GRANTEE) AS GRANTEE,
    TRIM(GRANTEETYPE) AS GRANTEETYPE
FROM SYSCAT.ROLEAUTH
WHERE ROLENAME = ?
ORDER BY GRANTEE
```

**Parameters:**
- `?` = `roleName` (trimmed)

---

### Groups

#### Get All Groups
```sql
SELECT DISTINCT 
    TRIM(GRANTEE) AS GRANTEE
FROM SYSCAT.DBAUTH
WHERE GRANTEETYPE = 'G'
ORDER BY GRANTEE
```

#### Get Group Members
```sql
SELECT 
    TRIM(GRANTEE) AS GRANTEE
FROM SYSCAT.ROLEAUTH
WHERE ROLENAME = ?
  AND GRANTEETYPE = 'U'
ORDER BY GRANTEE
```

**Parameters:**
- `?` = `groupName` (trimmed)

---

### Users

#### Get All Users
```sql
SELECT DISTINCT 
    TRIM(GRANTEE) AS GRANTEE
FROM SYSCAT.DBAUTH
WHERE GRANTEETYPE = 'U'
ORDER BY GRANTEE
```

#### Get Database Authorities for User
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
- `?` = `userName` (trimmed)

**Authority Values:**
- `Y` = Yes
- `N` = No
- `G` = Granted with grant option

---

## Notes

### Parameter Binding
- All parameters are positional (`?`)
- Parameter values are trimmed before binding
- Schema names stored as `CHAR` in DB2 are space-padded

### Column Trimming
- `TRIM()` is applied in SQL to all `CHAR` columns
- Additional `.Trim()` is applied in C# for safety
- This prevents comparison issues with space-padded values

### System Objects
- System schemas are filtered in UI based on access level
- Standard users see only user-created schemas
- Advanced/DBA users see all schemas including system

### Performance
- Queries use lazy loading (executed on node expansion)
- Counts are pre-calculated and cached
- Large result sets are loaded asynchronously

