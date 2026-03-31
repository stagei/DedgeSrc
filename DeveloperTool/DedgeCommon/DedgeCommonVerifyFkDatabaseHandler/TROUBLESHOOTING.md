# VerifyFunctionality Test Program - Troubleshooting Guide

## Overview

The `VerifyFunctionality` test program is designed to verify the `DedgeCommon` database handler functionality by:
1. Enabling database logging
2. Creating a test table
3. Inserting test data
4. Verifying the data
5. Cleaning up
6. Sending notifications

---

## Connection Details

### Primary ConnectionKey (for database logging)
```
Application:    FKM
Environment:    PRD (Production!)
Version:        2.0
InstanceName:   DB2 (default)
```

### Actual Database Connection (for testing)
```
Database:       BASISTST (Test environment)
Server:         erp2db2.DEDGE.fk.no
Port:           3701
Authentication: Kerberos
UID:            db2nt (fallback only)
PWD:            ntdb2 (fallback only)
```

### Configuration File Location
```
C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\DatabasesV2.json
```

---

## Potential Issues and Solutions

### 1. Configuration File Access Issue

**Problem:** The configuration file is located on a network share (`dedge-server`). If this share is inaccessible:
- The program will fail to load database configurations
- A fallback configuration will be used instead

**Symptoms:**
- Error: "Configuration file not found"
- Error: "Failed to load configuration"
- Unexpected connection errors when fallback differs from production config

**Solution:**
1. Verify network connectivity to `dedge-server`
2. Check that you have read access to the `DedgeCommon\Configfiles\` folder
3. Ensure the `DatabasesV2.json` file exists and is valid JSON

```powershell
# Test access to config file
Test-Path "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\DatabasesV2.json"

# Try to read the file
Get-Content "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\DatabasesV2.json" | ConvertFrom-Json
```

---

### 2. Kerberos Authentication Failure (DB2 Error -30082)

**Problem:** The database uses Kerberos authentication. If your Windows credentials are not valid for the DB2 server, you'll get error `-30082`.

**Symptoms:**
- `DB2 Error -30082`: Security processing failed
- Stack overflow (if recursive logging is triggered - now fixed with recursion guards)
- Connection timeout or access denied errors

**The Current Windows User Connecting:**
With Kerberos authentication, the **current logged-in Windows user** is used. Check with:
```powershell
whoami
# Expected format: DOMAIN\username (e.g., DEDGE\your.username)
```

**Solution:**
1. Verify your Windows account is in the correct domain (`DEDGE`)
2. Ensure your account has DB2 access permissions
3. Check that Kerberos tickets are valid:
```powershell
klist
```
4. If tickets are expired, re-authenticate or get new tickets

---

### 3. Mixed Environment Configuration

**Problem:** The test program has a configuration mismatch:
- Database logging is enabled for **PRD** (Production)
- Actual test operations are performed on **BASISTST** (Test)

**Code Reference (Program.cs lines 11-15, 29, 41):**
```csharp
// Logging goes to PRODUCTION
private static readonly DedgeConnection.ConnectionKey _ConnectionKey =
    new DedgeConnection.ConnectionKey(
            DedgeConnection.FkApplication.FKM,
            DedgeConnection.FkEnvironment.PRD  // <-- PRD!
        );

// ... later in Main()
DedgeNLog.EnableDatabaseLogging(_ConnectionKey);  // Logs to PRD database

// But tests run against TEST database
using var dbHandler = DedgeDbHandler.Create(DedgeConnection.GetConnectionKeyByDatabaseName("BASISTST"));
```

**Impact:**
- If you can't connect to PRD, database logging will fail
- Logging failures could cause errors or stack overflows (before our fix)
- Test data is written to TST, but logs go to PRD

**Solution:** Change the logging to use TST environment:
```csharp
private static readonly DedgeConnection.ConnectionKey _ConnectionKey =
    new DedgeConnection.ConnectionKey(
            DedgeConnection.FkApplication.FKM,
            DedgeConnection.FkEnvironment.TST  // Changed to TST
        );
```

---

### 4. Recursive Logging Stack Overflow (NOW FIXED)

**Problem:** If database logging fails (e.g., DB2 error -30082), the error handler would try to log the error to the database, which would fail again, causing infinite recursion.

**This has been fixed** by adding recursion guards in:
- `DedgeCommon/Db2Handler.cs` - `MapDb2ErrorToDbSqlError()` method
- `DedgeCommon/SqlServerHandler.cs` - `MapSqlServerErrorToDbSqlError()` method
- `DedgeCommon/DedgeNLog.cs` - `RealDbLogging()` method

---

### 5. Network/Firewall Issues

**Problem:** Cannot reach the DB2 server on the network.

**Symptoms:**
- Connection timeout errors
- "Server not found" errors

**Solution:**
```powershell
# Test connectivity to DB2 server for BASISTST (Test)
Test-NetConnection -ComputerName "erp2db2.DEDGE.fk.no" -Port 3701

# Test connectivity to DB2 server for BASISPRO (Production)
Test-NetConnection -ComputerName "erp1db2.DEDGE.fk.no" -Port 3700
```

---

### 6. Missing DB2 Client Driver

**Problem:** The IBM DB2 client driver (`IBM.Data.Db2.dll`) requires a native driver (`clidriver`) to be present.

**Symptoms:**
- `DllNotFoundException`
- `IBM.Data.Db2` related errors

**Solution:**
Verify the `clidriver` folder exists in the output directory:
```
DedgeCommonVerifyFkDatabaseHandler\bin\Debug\net8.0\clidriver\
```

---

## Database and User Summary

| Item | Value |
|------|-------|
| **Database for Logging** | PRD environment (BASISPRO) |
| **Database for Tests** | TST environment (BASISTST) |
| **Server (TST)** | erp2db2.DEDGE.fk.no:3701 |
| **Server (PRD)** | erp1db2.DEDGE.fk.no:3700 |
| **Authentication** | Kerberos (Windows integrated) |
| **User** | Current Windows user (run `whoami`) |
| **Schema** | DBM |
| **Test Table** | DBM.TEST_FKDATABASEHANDLER |

---

## Recommended Fix: Align Environments

Change `Program.cs` line 14 from `PRD` to `TST`:

```csharp
private static readonly DedgeConnection.ConnectionKey _ConnectionKey =
    new DedgeConnection.ConnectionKey(
            DedgeConnection.FkApplication.FKM,
            DedgeConnection.FkEnvironment.TST  // Use TST for consistency
        );
```

This ensures both database logging and test operations target the same environment.

---

## Quick Diagnostic Commands

```powershell
# 1. Check current Windows user (this is who connects via Kerberos)
whoami

# 2. Check Kerberos tickets
klist

# 3. Test config file access
Test-Path "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\DatabasesV2.json"

# 4. Test DB2 server connectivity (TST)
Test-NetConnection -ComputerName "erp2db2.DEDGE.fk.no" -Port 3701

# 5. Test DB2 server connectivity (PRD)
Test-NetConnection -ComputerName "erp1db2.DEDGE.fk.no" -Port 3700
```

