# Installing SqlMermaidErdTools from GitHub Packages

This guide explains how to install and use the **SqlMermaidErdTools** NuGet package from the private GitHub Packages registry.

---

## 📋 Prerequisites

1. **.NET 10.0 SDK** or later
2. **GitHub Account** with access to the package
3. **GitHub Personal Access Token (PAT)** with `read:packages` scope

---

## 🔑 Step 1: Token Already Provided

The PAT token is pre-configured in the commands below. No additional setup needed.

---

## 📦 Step 2: Add the GitHub Packages Source

Run this command **once** to add the private NuGet source:

```powershell
dotnet nuget add source "https://nuget.pkg.github.com/stagei/index.json" `
    --name "github-stagei" `
    --username "stagei" `
    --password "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" `
    --store-password-in-clear-text
```

> ⚠️ **Note**: This token is for internal use only. Do not share outside the organization.

### Alternative: Add to nuget.config

Create or update `nuget.config` in your project root:

```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
    <add key="github-stagei" value="https://nuget.pkg.github.com/stagei/index.json" />
  </packageSources>
  <packageSourceCredentials>
    <github-stagei>
      <add key="Username" value="stagei" />
      <add key="ClearTextPassword" value="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" />
    </github-stagei>
  </packageSourceCredentials>
</configuration>
```

> ⚠️ **Internal Use Only**: This nuget.config contains credentials. Do not commit to public repositories.

---

## 📥 Step 3: Install the Package

```powershell
# Install latest version
dotnet add package SqlMermaidErdTools

# Install specific version
dotnet add package SqlMermaidErdTools --version 0.2.8
```

---

## 🚀 Quick Start - Usage Examples

### Add Using Statement

```csharp
using SqlMermaidErdTools;
using SqlMermaidErdTools.Models;
```

### SQL → Mermaid ERD

Convert SQL DDL to a Mermaid entity-relationship diagram:

```csharp
var sqlDdl = @"
CREATE TABLE Customer (
    id INT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE
);

CREATE TABLE Order (
    id INT PRIMARY KEY,
    customer_id INT NOT NULL,
    order_date DATE,
    FOREIGN KEY (customer_id) REFERENCES Customer(id)
);
";

// Synchronous
var mermaid = SqlMermaidErdTools.ToMermaid(sqlDdl);
Console.WriteLine(mermaid);

// Asynchronous
var mermaid = await SqlMermaidErdTools.ToMermaidAsync(sqlDdl);
```

**Output:**
```mermaid
erDiagram
    Customer {
        int id PK
        varchar name "NOT NULL"
        varchar email UK
    }
    Order {
        int id PK
        int customer_id FK "NOT NULL"
        date order_date
    }
    Customer ||--o{ Order : customer_id
```

### Mermaid → SQL

Convert a Mermaid ERD diagram back to SQL DDL:

```csharp
var mermaidErd = @"
erDiagram
    Users {
        int id PK
        varchar username UK
        varchar email
    }
";

// Generate SQL for different dialects
var ansiSql = SqlMermaidErdTools.ToSql(mermaidErd, SqlDialect.AnsiSql);
var postgres = SqlMermaidErdTools.ToSql(mermaidErd, SqlDialect.PostgreSql);
var sqlServer = SqlMermaidErdTools.ToSql(mermaidErd, SqlDialect.SqlServer);
var mysql = SqlMermaidErdTools.ToSql(mermaidErd, SqlDialect.MySql);

// Async version
var sql = await SqlMermaidErdTools.ToSqlAsync(mermaidErd, SqlDialect.PostgreSql);
```

### SQL Dialect Translation

Translate SQL from one dialect to another:

```csharp
var sqlServerSql = "SELECT TOP 10 * FROM Users WHERE IsActive = 1";

var postgresSql = SqlMermaidErdTools.TranslateDialect(
    sqlServerSql,
    SqlDialect.SqlServer,
    SqlDialect.PostgreSql
);
// Output: SELECT * FROM Users WHERE IsActive = TRUE LIMIT 10
```

### Schema Diff (Mermaid → ALTER Statements)

Generate ALTER statements from changes between two Mermaid diagrams:

```csharp
var beforeDiagram = @"
erDiagram
    Users {
        int id PK
        varchar name
    }
";

var afterDiagram = @"
erDiagram
    Users {
        int id PK
        varchar name
        varchar email UK
    }
";

var alterStatements = SqlMermaidErdTools.GenerateDiffAlterStatements(
    beforeDiagram,
    afterDiagram,
    SqlDialect.PostgreSql
);
// Output: ALTER TABLE Users ADD COLUMN email VARCHAR(255) UNIQUE;
```

---

## 🎯 Supported SQL Dialects

### Input (SQL → Mermaid)

Supports **31+ SQL dialects** including:
- ANSI SQL, SQL Server (T-SQL), PostgreSQL, MySQL, SQLite, Oracle
- Snowflake, BigQuery, Redshift, Databricks, DuckDB
- ClickHouse, Apache Spark, Presto, Trino, and more

### Output (Mermaid → SQL)

Generates SQL for **4 dialects**:

| Dialect | Enum Value |
|---------|------------|
| ANSI SQL | `SqlDialect.AnsiSql` |
| SQL Server | `SqlDialect.SqlServer` |
| PostgreSQL | `SqlDialect.PostgreSql` |
| MySQL | `SqlDialect.MySql` |

---

## 🔧 Dependency Injection

For DI-friendly usage:

```csharp
using SqlMermaidErdTools.Converters;

// Register services
services.AddSingleton<ISqlToMmdConverter, SqlToMmdConverter>();
services.AddSingleton<IMmdToSqlConverter, MmdToSqlConverter>();

// Inject and use
public class MyService
{
    private readonly ISqlToMmdConverter _sqlToMmd;
    private readonly IMmdToSqlConverter _mmdToSql;

    public MyService(ISqlToMmdConverter sqlToMmd, IMmdToSqlConverter mmdToSql)
    {
        _sqlToMmd = sqlToMmd;
        _mmdToSql = mmdToSql;
    }

    public async Task<string> ConvertToMermaid(string sql)
    {
        return await _sqlToMmd.ConvertAsync(sql);
    }
}
```

---

## 📊 API Reference

### Static Methods (SqlMermaidErdTools class)

| Method | Description |
|--------|-------------|
| `ToMermaid(sql)` | Convert SQL DDL to Mermaid ERD |
| `ToMermaidAsync(sql)` | Async version |
| `ToSql(mermaid, dialect)` | Convert Mermaid to SQL |
| `ToSqlAsync(mermaid, dialect)` | Async version |
| `TranslateDialect(sql, from, to)` | Translate between SQL dialects |
| `TranslateDialectAsync(sql, from, to)` | Async version |
| `GenerateDiffAlterStatements(before, after, dialect)` | Generate ALTER from diagram diff |
| `GenerateDiffAlterStatementsAsync(before, after, dialect)` | Async version |

### SqlDialect Enum

```csharp
public enum SqlDialect
{
    AnsiSql,    // Standard ANSI SQL
    SqlServer,  // Microsoft SQL Server (T-SQL)
    PostgreSql, // PostgreSQL
    MySql,      // MySQL
    Sqlite,     // SQLite
    Oracle      // Oracle Database
}
```

---

## ⚠️ Requirements

- **.NET 10.0** or later
- **Python 3.8+** must be installed on the system with `sqlglot` package
  - Or the package will use bundled Python runtime if available

### Install Python Dependency (if needed)

```bash
pip install sqlglot
```

---

## 🐛 Troubleshooting

### "Package not found"

Ensure the NuGet source is configured:
```powershell
dotnet nuget list source
```

If `github-stagei` is not listed, add it (see Step 2).

### "401 Unauthorized"

- Check your PAT token hasn't expired
- Verify PAT has `read:packages` scope
- Ensure username is correct

### "Python not found"

Install Python and SQLGlot:
```bash
pip install sqlglot
```

---

## 📚 More Information

- **Package Source**: https://github.com/stagei?tab=packages
- **Documentation**: Contact package owner
- **Support**: geir@starholm.net

---

## 📝 Example Project Setup

### 1. Create new project

```powershell
dotnet new console -n MyDatabaseTool
cd MyDatabaseTool
```

### 2. Add NuGet source (if not already done)

```powershell
dotnet nuget add source "https://nuget.pkg.github.com/stagei/index.json" `
    --name "github-stagei" `
    --username "stagei" `
    --password "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" `
    --store-password-in-clear-text
```

### 3. Install package

```powershell
dotnet add package SqlMermaidErdTools
```

### 4. Use in code

```csharp
// Program.cs
using SqlMermaidErdTools;

var sql = @"
CREATE TABLE Products (
    id INT PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    price DECIMAL(10,2)
);
";

var mermaid = await SqlMermaidErdTools.ToMermaidAsync(sql);
Console.WriteLine(mermaid);
```

### 5. Run

```powershell
dotnet run
```

---

*Last updated: December 2025*

