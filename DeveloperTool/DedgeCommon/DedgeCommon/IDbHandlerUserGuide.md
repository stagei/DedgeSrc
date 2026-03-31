# IDbHandler User Guide

**Interface:** `DedgeCommon.IDbHandler`  
**Version:** 1.5.35  
**Purpose:** Common interface for all database handlers (DB2, SQL Server, PostgreSQL)

---

## 🎯 Overview

IDbHandler is the interface that all database handlers implement. Use this for polymorphism when you need to work with multiple database types.

---

## 📋 Usage Pattern

```csharp
using DedgeCommon;

// Factory returns IDbHandler
IDbHandler db = DedgeDbHandler.CreateByDatabaseName("FKMPRD");

// All handlers implement these methods:
var data = db.ExecuteQueryAsDataTable("SELECT * FROM TABLE");
int rows = db.ExecuteNonQuery("INSERT INTO TABLE VALUES (1, 'Test')");
db.BeginTransaction();
db.CommitTransaction();
```

---

## 📚 Key Members

### Methods (All Implementations Must Provide)
- **ExecuteQueryAsDataTable(string query)** - Execute SELECT
- **ExecuteNonQuery(string sql)** - Execute INSERT/UPDATE/DELETE
- **BeginTransaction()** - Start transaction
- **CommitTransaction()** - Commit transaction
- **RollbackTransaction()** - Rollback transaction
- **GetDatabaseName()** - Get database name
- **Dispose()** - Clean up resources

---

## 🔗 Implementations

- **Db2Handler** - IBM DB2 implementation
- **SqlServerHandler** - SQL Server implementation  
- **PostgresHandler** - PostgreSQL implementation

---

**Last Updated:** 2025-12-19  
**Included in Package:** Yes
