# DB2 Kerberos Authentication Fix - Summary

**Date:** 2025-12-16  
**Issue:** DB2 connections failing with SQL30082N error when using Kerberos/SSO authentication

## Problem

When attempting to connect to DB2 databases with `AuthenticationType: "Kerberos"` configured in DatabasesV2.json, connections were failing with:

```
ERROR [08001] [IBM] SQL30082N Security processing failed with reason "17" ("UNSUPPORTED FUNCTION"). SQLSTATE=08001
```

## Root Cause

The connection string was being generated **without** the `Authentication=Kerberos` parameter required by the IBM DB2 driver for Kerberos authentication. Simply omitting UID/PWD is not sufficient.

### Incorrect Connection String (Before Fix)
```
Database=BASISTST;Server=t-no1fkmtst-db:3701;
```
-
### Correct Connection String (After Fix)--
```
Database=BASISTST;Server=t-no1fkmtst-db:3701;Authentication=Kerberos;
```

## Solution

Modified `DedgeConnection.cs` `GenerateConnectionString()` method to explicitly add `Authentication=Kerberos;` parameter when:
- `AuthenticationType` is "Kerberos"  
- No override credentials are provided

## Changes Made

### 1. DedgeConnection.cs - Line ~1040
```csharp
if (accessPoint.ProviderEnum == DatabaseProvider.DB2)
{
    connectionString = $"Database={accessPoint.CatalogName};Server={accessPoint.ServerName}:{accessPoint.Port};";
    
    if (includeCredentials)
    {
        connectionString += $"UID={uid};PWD={pwd};";
    }
    else if (useKerberos)
    {
        // For DB2 Kerberos authentication, must explicitly specify Authentication=Kerberos
        connectionString += "Authentication=Kerberos;";
    }
}
```

### 2. Test Program Created
Created `SimpleFkkTotstTest` to verify the fix:
- Loads DatabasesV2.json directly
- Finds FKMTST database  
- Connects using Kerberos authentication
- Executes test query: `SELECT TABNAME FROM SYSCAT.TABLES`
- Saves results to file

## Test Results

✅ **Connection successful** using Kerberos/SSO authentication  
✅ **Query executed successfully** - returned 10 rows  
✅ **No credentials needed** - uses Windows integrated authentication

### Test Output
```
Database: FKMTST
CatalogName: BASISTST
Server: t-no1fkmtst-db:3701
Authentication: Kerberos

Query: SELECT TABNAME FROM SYSCAT.TABLES FETCH FIRST 10 ROWS ONLY
Rows returned: 10

Results:
EXPLAIN_ARGUMENT
EXPLAIN_INSTANCE
EXPLAIN_OBJECT
EXPLAIN_OPERATOR
EXPLAIN_PREDICATE
EXPLAIN_STATEMENT
EXPLAIN_STREAM
LOSTUEN
M3_CIDMAS
AARSAK
```

## Key Learnings

1. **DB2 Kerberos requires explicit parameter**: The IBM DB2 .NET driver requires `Authentication=Kerberos` in the connection string
2. **Empty credentials don't work**: Simply omitting UID/PWD is not sufficient for Kerberos authentication
3. **Database vs CatalogName**: Applications use the CatalogName (alias) from PrimaryCatalogName, NOT the Database name
4. **PrimaryDb vs Alias**: PrimaryDb is for administrative access only; applications ALWAYS use Alias type

## Configuration Requirements

For Kerberos authentication to work in DatabasesV2.json:

```json
{
  "Database": "FKMTST",
  "PrimaryCatalogName": "BASISTST",
  "AccessPoints": [
    {
      "CatalogName": "BASISTST",
      "AccessPointType": "Alias",
      "AuthenticationType": "Kerberos",
      "UID": "",  // Not used for Kerberos
      "PWD": "",  // Not used for Kerberos
      "IsActive": true
    }
  ]
}
```

## Benefits

- ✅ True Single Sign-On (SSO) - uses Windows credentials
- ✅ No passwords in connection strings
- ✅ Automatic credential management via Windows/Kerberos
- ✅ More secure - no hardcoded credentials

## Next Steps

The VerifyFunctionality test program should now work correctly with the updated DedgeCommon library. Run it to verify full functionality including:
- Connection creation
- Transaction management  
- Query execution
- Error handling
- Notification sending

---

**Files Modified:**
- `DedgeCommon/DedgeConnection.cs` - Added Authentication=Kerberos parameter
- `SimpleFkkTotstTest/Program.cs` - Created test to verify fix
- `SimpleFkkTotstTest/SimpleFkkTotstTest.csproj` - Added IBM.Data.Db2 package reference
