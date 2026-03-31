# DB2 Database Privileges and Authorities Guide

This document explains all the database-level privileges and authorities that can be granted in IBM DB2, their purposes, and compatibility considerations.

## Overview

Database privileges in DB2 control what users can do at the database level (as opposed to object-level privileges that control access to specific tables, views, etc.). These privileges are stored in the `SYSCAT.DBAUTH` catalog view.

## Core Database Privileges

### BINDADD
**Purpose:** Grants the authority to create packages in the database.
**Why it exists:** Packages are compiled SQL statements. This privilege controls who can create/bind new packages.
**Compatibility:** Universal across all DB2 platforms.
**Documentation:** [IBM DB2 GRANT Database Authorities](https://www.ibm.com/docs/en/db2/11.5?topic=statements-grant-database-authorities)

### CONNECT
**Purpose:** Grants the authority to connect to the database.
**Why it exists:** Basic access control - users need this to even connect to the database.
**Compatibility:** Universal across all DB2 platforms.
**Documentation:** [IBM DB2 GRANT Database Authorities](https://www.ibm.com/docs/en/db2/11.5?topic=statements-grant-database-authorities)

### CREATETAB
**Purpose:** Grants the authority to create base tables in the database.
**Why it exists:** Controls who can create new tables in the database.
**Compatibility:** Universal across all DB2 platforms.
**Documentation:** [IBM DB2 GRANT Database Authorities](https://www.ibm.com/docs/en/db2/11.5?topic=statements-grant-database-authorities)

### IMPLICIT_SCHEMA
**Purpose:** Grants the authority to implicitly create schemas.
**Why it exists:** When creating objects, if the schema doesn't exist, this privilege allows it to be created automatically.
**Compatibility:** Universal across all DB2 platforms.
**Documentation:** [IBM DB2 GRANT Database Authorities](https://www.ibm.com/docs/en/db2/11.5?topic=statements-grant-database-authorities)

### LOAD
**Purpose:** Grants the authority to use the LOAD utility.
**Why it exists:** The LOAD utility is a high-performance data loading tool that requires special privileges.
**Compatibility:** Universal across all DB2 platforms.
**Documentation:** [IBM DB2 GRANT Database Authorities](https://www.ibm.com/docs/en/db2/11.5?topic=statements-grant-database-authorities)

### QUIESCE_CONNECT
**Purpose:** Grants the authority to connect to the database while it is quiesced.
**Why it exists:** Allows administrative access during maintenance windows when the database is in quiesce mode.
**Compatibility:** Universal across all DB2 platforms.
**Documentation:** [IBM DB2 GRANT Database Authorities](https://www.ibm.com/docs/en/db2/11.5?topic=statements-grant-database-authorities)

### EXPLAIN
**Purpose:** Grants the authority to explain SQL statements without requiring data access.
**Why it exists:** Allows users to analyze query execution plans for performance tuning without needing actual data access.
**Compatibility:** Universal across all DB2 platforms.
**Documentation:** [IBM DB2 GRANT Database Authorities](https://www.ibm.com/docs/en/db2/11.5?topic=statements-grant-database-authorities)

## Administrative Authorities

### DBADM (Database Administrator)
**Purpose:** Grants nearly all privileges on nearly all objects in the database.
**Why it exists:** Provides comprehensive database administration capabilities.
**Limitations:** Does not include ACCESSCTRL, DATAACCESS, or SECADM authorities.
**Compatibility:** Universal across all DB2 platforms.
**Documentation:** [IBM DB2 GRANT Database Authorities](https://www.ibm.com/docs/en/db2/11.5?topic=statements-grant-database-authorities)

### SECADM (Security Administrator)
**Purpose:** Grants security administration authority.
**Why it exists:** Separates security management from general database administration.
**Capabilities:**
- Create/drop security objects (audit policies, roles, security labels, etc.)
- Grant/revoke authorities, privileges, roles
- Grant/revoke SETSESSIONUSER privilege
- Transfer ownership of objects
**Compatibility:** Universal across all DB2 platforms.
**Documentation:** [IBM DB2 GRANT Database Authorities](https://www.ibm.com/docs/en/db2/11.5?topic=statements-grant-database-authorities)

### ACCESSCTRL (Access Control)
**Purpose:** Grants access control authority.
**Why it exists:** Provides privilege management capabilities separate from data access.
**Capabilities:**
- Grant/revoke database authorities (BINDADD, CONNECT, CREATETAB, etc.)
- Grant/revoke all object-level privileges
**Limitations:** Cannot be granted to PUBLIC.
**Compatibility:** Universal across all DB2 platforms.
**Documentation:** [IBM DB2 GRANT Database Authorities](https://www.ibm.com/docs/en/db2/11.5?topic=statements-grant-database-authorities)

### DATAACCESS (Data Access)
**Purpose:** Grants comprehensive data access authority.
**Why it exists:** Separates data access from privilege management.
**Capabilities:**
- Select, insert, update, delete, and load data
- Run any package
- Run any routine (except audit routines)
**Limitations:** Cannot be granted to PUBLIC.
**Compatibility:** Universal across all DB2 platforms.
**Documentation:** [IBM DB2 GRANT Database Authorities](https://www.ibm.com/docs/en/db2/11.5?topic=statements-grant-database-authorities)

### SQLADM (SQL Administrator)
**Purpose:** Grants SQL statement execution management authority.
**Why it exists:** Allows management of SQL execution without requiring full database admin rights.
**Capabilities:**
- Create/drop/flush event monitors
- Explain/prepare/describe SQL statements
- Flush optimization profile cache and package cache
- Execute RUNSTATS utility
- Manage usage lists
**Compatibility:** Universal across all DB2 platforms.
**Documentation:** [IBM DB2 GRANT Database Authorities](https://www.ibm.com/docs/en/db2/11.5?topic=statements-grant-database-authorities)

### WLMADM (Workload Manager Administrator)
**Purpose:** Grants workload management authority.
**Why it exists:** Allows management of workloads and service classes for performance management.
**Capabilities:**
- Create/drop/alter service classes, thresholds, work action sets, work class sets, workloads
**Compatibility:** Universal across all DB2 platforms.
**Documentation:** [IBM DB2 GRANT Database Authorities](https://www.ibm.com/docs/en/db2/11.5?topic=statements-grant-database-authorities)

## Security and Routine Privileges

### CREATE_SECURE_OBJECT
**Purpose:** Grants the authority to create secure triggers and functions.
**Why it exists:** Provides additional security layer for creating sensitive database objects.
**Capabilities:**
- Create secure triggers and secure functions
- Alter the secure attribute of such objects
**Compatibility:** Universal across all DB2 platforms.
**Documentation:** [IBM DB2 GRANT Database Authorities](https://www.ibm.com/docs/en/db2/11.5?topic=statements-grant-database-authorities)

### CREATE_EXTERNAL_ROUTINE
**Purpose:** Grants the authority to register external routines (stored procedures, functions written in C, Java, etc.).
**Why it exists:** External routines can potentially harm the database server, so this requires special privilege.
**Security Note:** Use with caution as external routines can have adverse side effects.
**Compatibility:** Available in DB2 LUW v11.5+. 
**Documentation:** [IBM DB2 CREATE PROCEDURE External](https://www.ibm.com/docs/en/db2/11.5?topic=statements-create-procedure-external)

### CREATE_NOT_FENCED_ROUTINE
**Purpose:** Grants the authority to register routines that run in the database manager's process (not fenced).
**Why it exists:** Not-fenced routines have higher performance but pose security risks as they run in the DB2 engine's address space.
**Security Note:** Extremely dangerous if not properly coded - can compromise database integrity.
**Auto-Grant:** Automatically grants CREATE_EXTERNAL_ROUTINE as well.
**Compatibility:** Available in DB2 LUW v11.5+.
**Documentation:** [IBM DB2 CREATE PROCEDURE External](https://www.ibm.com/docs/en/db2/11.5?topic=statements-create-procedure-external)

## Catalog Columns That Exist But Are Not Directly Grantable

### LIBRARYADMAUTH
**Purpose:** Appears in SYSCAT.DBAUTH but is not directly grantable in DB2 LUW.
**Why it exists:** Compatibility with DB2 for z/OS catalog structure.
**Status:** This column exists for structural compatibility but has no corresponding GRANT statement in DB2 LUW v12.1.
**Platform Difference:** This privilege may be available on DB2 for z/OS but not on DB2 LUW.
**Documentation:** [IBM DB2 z/OS vs LUW Differences](https://www.ibm.com/docs/en/db2/11.5)

## Important Security Considerations

### Authorities That Cannot Be Granted to PUBLIC
The following authorities have security restrictions and cannot be granted to PUBLIC:
- ACCESSCTRL
- CREATE_SECURE_OBJECT
- DATAACCESS
- DBADM
- SECADM

### Version Compatibility Notes
- **DB2 v11.5.7+**: Enhanced security model for CREATE_EXTERNAL_ROUTINE and CREATE_NOT_FENCED_ROUTINE
- **Registry Variable**: `DB2_ALTERNATE_AUTHZ_BEHAVIOUR` can modify authorization behavior
- **Security Enhancement**: Starting with DB2 v11.5.8, SYSADM authority is required for external routine privileges by default

## Best Practices

1. **Principle of Least Privilege**: Only grant the minimum privileges necessary for users to perform their tasks.

2. **Separate Duties**: Use different authorities (SECADM, ACCESSCTRL, DATAACCESS) to implement separation of duties.

3. **External Routines**: Be extremely cautious with CREATE_EXTERNAL_ROUTINE and CREATE_NOT_FENCED_ROUTINE privileges.

4. **Regular Audits**: Regularly review granted privileges using the SYSCAT.DBAUTH catalog view.

5. **Documentation**: Always document why specific privileges were granted to specific users.

## Verification Queries

To check current database authorities:

```sql
-- Check all database authorities for a specific user
SELECT * FROM SYSCAT.DBAUTH WHERE GRANTEE = 'USERNAME';

-- Check who has DBADM authority
SELECT GRANTEE, GRANTOR, GRANTEDTS 
FROM SYSCAT.DBAUTH 
WHERE DBADMAUTH = 'Y';

-- Check external routine privileges
SELECT GRANTEE, EXTERNALROUTINEAUTH, NOFENCEAUTH, LIBRARYADMAUTH
FROM SYSCAT.DBAUTH 
WHERE GRANTEE = 'USERNAME';
```

## References

- [IBM DB2 GRANT Database Authorities Documentation](https://www.ibm.com/docs/en/db2/11.5?topic=statements-grant-database-authorities)
- [IBM DB2 Authorization and Privileges](https://www.ibm.com/docs/en/db2/11.5?topic=security-authorization-privileges-object-ownership)
- [IBM DB2 CREATE PROCEDURE External](https://www.ibm.com/docs/en/db2/11.5?topic=statements-create-procedure-external)
- [IBM DB2 SYSCAT.DBAUTH Catalog View](https://www.ibm.com/docs/en/db2/11.5?topic=views-syscatdbauth)

---

*Last Updated: January 2025*
*Version: DB2 LUW v12.1* 