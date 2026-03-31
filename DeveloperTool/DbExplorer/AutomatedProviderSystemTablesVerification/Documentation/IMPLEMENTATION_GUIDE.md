# Provider Implementation Guide

**Version**: 1.0  
**Target Audience**: Developers implementing new database provider support  
**Est. Time**: 10-20 hours per provider

---

## 🎯 Overview

This guide walks you through implementing and validating a new database provider for DbExplorer using the automated testing framework.

---

## 📋 Prerequisites

### Knowledge Requirements
- Understanding of the target database system
- Familiarity with the database's system catalog/information schema
- Knowledge of database-specific SQL syntax
- Basic PowerShell scripting

### Tools Required
- DbExplorer project (built successfully)
- Target database instance (with test data)
- Database user account with appropriate privileges
- PowerShell 7+

### Permissions Needed
- READ access to system catalog tables
- CREATE privilege (for test objects if needed)
- SELECT/INSERT/UPDATE/DELETE on test tables
- EXECUTE on test procedures/functions

---

## 📊 Implementation Phases

### Phase 1: Configuration (1-2 hours)

#### Step 1.1: Create Provider Config

```powershell
# Copy template
cd AutomatedProviderSystemTablesVerification\ProviderConfigs
Copy-Item "PostgreSQL_Config.json" "PostgreSQL_Production.json"
```

#### Step 1.2: Populate Test Objects

Edit the JSON file and fill in actual object names from your database:

```json
{
  "provider": "PostgreSQL",
  "version": "15.2",
  "profileName": "MyProdPostgres",
  "testObjects": {
    "table": "public.orders",      // Use real table name
    "view": "public.order_summary", // Use real view name
    // ...
  }
}
```

**Tips**:
- Use objects that exist in your test database
- Choose objects with relationships (foreign keys, indexes)
- For missing object types, set to "N/A"
- Document why certain objects are N/A

#### Step 1.3: Verify System Catalog Mapping

Research your provider's system catalog tables:

**PostgreSQL**:
- Tables: `pg_tables` or `information_schema.tables`
- Columns: `information_schema.columns`
- Constraints: `information_schema.table_constraints`

**Oracle**:
- Tables: `ALL_TABLES` or `DBA_TABLES`
- Columns: `ALL_TAB_COLUMNS`
- Constraints: `ALL_CONSTRAINTS`

**SQL Server**:
- Tables: `INFORMATION_SCHEMA.TABLES` or `sys.tables`
- Columns: `INFORMATION_SCHEMA.COLUMNS`
- Constraints: `INFORMATION_SCHEMA.TABLE_CONSTRAINTS`

Update `systemCatalog` section in config JSON.

---

### Phase 2: Object Type Testing (2-4 hours)

#### Step 2.1: Run Object Type Test

```powershell
cd AutomatedProviderSystemTablesVerification\Scripts
.\Test-AllObjectTypes.ps1 -ConfigFile "..\ProviderConfigs\PostgreSQL_Production.json"
```

#### Step 2.2: Analyze Failures

Common failure reasons:
1. **Object Not Found**: Update testObjects in config
2. **Permission Denied**: Grant required privileges
3. **Timeout**: Increase -TimeoutSeconds parameter
4. **App Crash**: Check application logs for errors

#### Step 2.3: Fix Implementation Issues

If object types fail:

**Check C# Code**:
```bash
# Search for object type handler
grep -r "case ObjectType.Views" Dialogs/
```

**Verify SQL Queries**:
```bash
# Check if query exists for this object type
grep "GetViewInfo" ConfigFiles/postgresql_15.0_sql_statements.json
```

#### Step 2.4: Iterate Until 100%

Repeat tests until all configured object types pass.

---

### Phase 3: Tab Selection Testing (1-2 hours)

#### Step 3.1: Run Tab Test

```powershell
.\Test-AllTabs.ps1 -ConfigFile "..\ProviderConfigs\PostgreSQL_Production.json"
```

#### Step 3.2: Verify Tab Activation

Check logs for tab activation messages:

```powershell
# View recent log
Get-Content ..\..\bin\Debug\net10.0-windows\logs\DbExplorer_*.log |
    Select-String "Activated tab" |
    Select-Object -Last 20
```

#### Step 3.3: Fix Tab Issues

If tabs fail to activate:

**Check Dialog Implementation**:
- Does the dialog have `ActivateTab()` method?
- Are all TabItems named with `x:Name`?
- Does tab name match the switch case?

**Example Fix**:
```xaml
<!-- Before -->
<TabItem Header="📋 Properties">

<!-- After -->
<TabItem Header="📋 Properties" x:Name="PropertiesTab">
```

---

### Phase 4: CLI vs Form Validation (4-8 hours)

#### Step 4.1: Run Validation Test

```powershell
.\Test-CliVsForm.ps1 -ConfigFile "..\ProviderConfigs\PostgreSQL_Production.json"
```

#### Step 4.2: Compare Results

The test compares:
- CLI query row counts
- Form display success
- (Future: actual data values)

#### Step 4.3: Fix Query Mismatches

Common issues:

**Column Name Differences**:
```sql
-- DB2 uses: TABSCHEMA, TABNAME
-- PostgreSQL uses: table_schema, table_name
-- SQL Server uses: TABLE_SCHEMA, TABLE_NAME
```

**Solution**: Add aliases in SQL:
```sql
SELECT 
    table_schema AS TABSCHEMA,
    table_name AS TABNAME
FROM information_schema.tables
```

**System Table Differences**:
- DB2: `SYSCAT.TABLES`
- PostgreSQL: `pg_tables` or `information_schema.tables`
- Oracle: `ALL_TABLES`
- SQL Server: `INFORMATION_SCHEMA.TABLES`

#### Step 4.4: Update SQL Queries

Edit `ConfigFiles/[provider]_[version]_sql_statements.json`:

```json
{
  "statements": {
    "GetTableColumns": {
      "sql": "SELECT column_name AS COLNAME, data_type AS TYPENAME...",
      "description": "Get table columns for PostgreSQL",
      "parameters": ["TABSCHEMA", "TABNAME"]
    }
  }
}
```

---

### Phase 5: Report Generation (1 hour)

#### Step 5.1: Generate Report

```powershell
.\Generate-ProviderReport.ps1 -Provider "PostgreSQL" -InputPath "..\TestResults"
```

#### Step 5.2: Review Report

Report includes:
- Overall pass rate
- Failures by category
- Recommendations

#### Step 5.3: Address Failures

Prioritize by impact:
1. **Critical**: Core object types (Tables, Views)
2. **High**: Common operations (Columns, Indexes)
3. **Medium**: Advanced features (Packages, Triggers)
4. **Low**: Edge cases

---

## 🔧 Troubleshooting Guide

### Issue: "Config file not found"

**Cause**: Incorrect path or filename

**Solution**:
```powershell
# Use absolute path
.\Test-AllObjectTypes.ps1 -ConfigFile "C:\full\path\to\config.json"
```

### Issue: "App crashes immediately"

**Cause**: Connection failure or missing dependencies

**Solution**:
1. Test connection manually in GUI
2. Check logs: `bin\Debug\net10.0-windows\logs\`
3. Verify provider DLL is included

### Issue: "Timeout on all tests"

**Cause**: Slow database or network

**Solution**:
```powershell
# Increase timeout
.\Test-AllObjectTypes.ps1 -ConfigFile "..." -TimeoutSeconds 60
```

### Issue: "Column 'X' does not exist"

**Cause**: Provider version mismatch

**Solution**:
1. Web search: "PostgreSQL 15 information_schema columns"
2. Verify exact column names for your version
3. Update SQL query with correct names

### Issue: "Test passes but no data in form"

**Cause**: DataGrid binding issue

**Solution**:
1. Check XAML bindings use bracket notation: `{Binding [ColumnName]}`
2. Verify SQL query returns data with correct column names
3. Check form's ItemsSource is set to `DataTable.DefaultView`

---

## ✅ Success Criteria

### Minimum Pass Rates

| Test Category | Target | Acceptable |
|---------------|--------|------------|
| Object Types | 100% | 90%+ |
| Tab Selection | 100% | 95%+ |
| CLI vs Form | 100% | 95%+ |

### Quality Gates

Before declaring provider "complete":

- [ ] All critical object types work (Tables, Views, Procedures, Functions)
- [ ] All dialog tabs activate correctly
- [ ] CLI queries return expected data
- [ ] Forms display data without crashes
- [ ] No unhandled exceptions in logs
- [ ] Performance acceptable (< 5 seconds for typical operations)
- [ ] Documentation updated
- [ ] Test report generated and reviewed

---

## 📚 Additional Resources

### Provider-Specific Documentation

- **PostgreSQL**: https://www.postgresql.org/docs/current/catalogs.html
- **Oracle**: https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/
- **SQL Server**: https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/

### DbExplorer Documentation

- Main README: `README.md`
- Architecture: `Dialogs/` and `Services/` folders
- SQL Queries: `ConfigFiles/db2_12.1_sql_statements.json` (reference)

### Support

- Check `TESTING_METHODOLOGY.md` for test details
- Review `DB2_EXAMPLE.md` for reference implementation
- Consult project README for general questions

---

## 🎓 Best Practices

### 1. Start Simple
Test Tables and Views first before advanced object types.

### 2. Incremental Progress
Fix one failure at a time, re-test after each fix.

### 3. Document Differences
Note provider-specific quirks in config JSON `notes` array.

### 4. Version Matters
Always specify exact provider version (e.g., PostgreSQL 15.2, not just "15").

### 5. Test with Real Data
Use production-like data for realistic testing.

### 6. Performance Baseline
Record test execution times for future comparison.

### 7. Keep Tests Updated
Re-run tests after provider version upgrades.

---

**Next**: See `TESTING_METHODOLOGY.md` for test internals  
**Reference**: See `DB2_EXAMPLE.md` for complete example

