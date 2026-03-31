# GUI Validation Framework

## Purpose

This document describes the **GUI Form Testing and Validation Framework** implemented in DbExplorer. This framework is designed to be **database-agnostic** and **reusable for future multi-database support** (PostgreSQL, Oracle, SQL Server, etc.).

## Architecture

### Core Concept

The validation framework compares data retrieved via two paths:
1. **CLI Direct SQL** - Data retrieved by executing SQL queries directly against system tables
2. **GUI Form Extraction** - Data displayed in the application's WPF forms/dialogs

By comparing these two data sources, we can verify:
- Forms display correct data
- Forms use correct SQL queries
- SQL statements in JSON configuration are accurate
- No data transformation bugs in UI layer

### Components

#### 1. CLI Parameters (`--test-form`, `--tab`)

**Added Parameters:**
- `--test-form`: Specifies which form to test (e.g., `table-details`, `view-details`, `procedure-details`)
- `--tab`: Optional. Specifies specific tab to extract (e.g., `columns`, `foreign-keys`, `ddl-script`)
- `--outfile`: Output file for JSON results

**Example:**
```powershell
DbExplorer.exe --profile PRODDB \
  --test-form table-details \
  --object MYSCHEMA.CUSTOMERS \
  --tab columns \
  --outfile form_columns.json
```

#### 2. GuiTestingService

**Location:** `Services/GuiTestingService.cs`

**Responsibilities:**
- Launches WPF dialogs programmatically
- Waits for async data loading
- Extracts data from UI controls (DataGrids, TextBoxes, TextBlocks)
- Returns data as structured JSON

**Key Methods:**
- `TestFormAsync(connectionManager, formName, objectName, tabName)` - Main entry point
- `TestTableDetailsDialogAsync()` - Table-specific testing
- `ExtractTableDetailsData()` - Extracts all tab data from TableDetailsDialog
- `ExtractDataGridData()` - Generic DataGrid extraction
- `ExtractTextBoxData()` - Generic TextBox extraction
- `ExtractStatisticsData()` - Statistics fields extraction

**Design for Multi-Database Support:**
```csharp
// Future expansion example:
public async Task<Dictionary<string, object>> TestFormAsync(
    IDbConnectionManager connectionManager,  // Generic interface
    string formName, 
    string objectName, 
    string? tabName = null)
{
    // Determine database provider from connection manager
    var provider = connectionManager.DatabaseProvider; // e.g., "DB2", "PostgreSQL", "Oracle"
    
    return provider switch
    {
        "DB2" => await TestTableDetailsDialogAsync(connectionManager, objectName, tabName),
        "PostgreSQL" => await TestPgTableDetailsDialogAsync(connectionManager, objectName, tabName),
        "Oracle" => await TestOracleTableDetailsDialogAsync(connectionManager, objectName, tabName),
        "SqlServer" => await TestSqlServerTableDetailsDialogAsync(connectionManager, objectName, tabName),
        _ => throw new NotSupportedException($"Provider '{provider}' not supported for GUI testing")
    };
}
```

#### 3. Form Data Extraction (Dialog Modifications)

**Pattern Applied to TableDetailsDialog:**

Added public accessors for UI controls:
```csharp
// Public accessors for GUI testing
public System.Windows.Controls.DataGrid ColumnsGridPublic => ColumnsGrid;
public System.Windows.Controls.DataGrid ForeignKeysGridPublic => ForeignKeysGrid;
public System.Windows.Controls.DataGrid IndexesGridPublic => IndexesGrid;
public System.Windows.Controls.TextBox DDLTextBoxPublic => DDLTextBox;
// ... and so on
```

**This pattern must be applied to ALL dialogs:**
- TableDetailsDialog ✅ **DONE**
- ViewDetailsDialog ⏳ TODO
- ProcedureDetailsDialog ⏳ TODO
- FunctionDetailsDialog ⏳ TODO
- TriggerDetailsDialog ⏳ TODO
- PackageDetailsDialog ⏳ TODO

#### 4. Validation Script (_validate_forms.ps1)

**Location:** `_validate_forms.ps1`

**Workflow:**
1. Execute CLI command (e.g., `table-props`) → `cli_data.json`
2. Execute GUI extraction (e.g., `--test-form table-details`) → `form_data.json`
3. Compare data structures (row counts, content, field values)
4. Generate validation report (CSV, JSON, console output)

**Design for Multi-Database Support:**

The validation script should be database-agnostic:

```powershell
# _validate_forms.ps1

param(
    [string]$Profile = "BASISTST",
    [string]$TestObject = "INL.KONTO",
    [string]$DatabaseProvider = "DB2"  # Future: PostgreSQL, Oracle, SqlServer
)

# Load provider-specific validation rules
$validationRules = switch ($DatabaseProvider) {
    "DB2" { Get-Content "ValidationRules/DB2_rules.json" | ConvertFrom-Json }
    "PostgreSQL" { Get-Content "ValidationRules/PostgreSQL_rules.json" | ConvertFrom-Json }
    "Oracle" { Get-Content "ValidationRules/Oracle_rules.json" | ConvertFrom-Json }
    "SqlServer" { Get-Content "ValidationRules/SqlServer_rules.json" | ConvertFrom-Json }
}

# Each provider may have different commands/queries
$cliCommand = $validationRules.TablePropsCommand  # e.g., "table-props" for DB2
$formName = $validationRules.TableDetailsForm     # e.g., "table-details"
```

## Database-Agnostic Design Principles

### 1. Abstraction Layers

**SQL Configuration Files:**
- `db2_12.1_sql_statements.json` ← Current
- `postgresql_15_sql_statements.json` ← Future
- `oracle_19c_sql_statements.json` ← Future
- `sqlserver_2022_sql_statements.json` ← Future

**MetadataHandler:**
```csharp
// Already supports provider selection
var sql = _metadataHandler.GetQuery(provider, version, queryName);

// Future usage:
var sql = _metadataHandler.GetQuery("PostgreSQL", "15", "GetTableColumns");
var sql = _metadataHandler.GetQuery("Oracle", "19c", "GetTableColumns");
```

### 2. Semantic Query Naming

**All SQL queries are named by WHAT DATA they retrieve, not WHERE they're used:**

✅ **Good (Semantic):**
- `GetTableColumns` - Retrieves column metadata
- `GetForeignKeys` - Retrieves FK relationships
- `GetIndexes` - Retrieves index information
- `GetTableDdl` - Retrieves DDL statement

❌ **Bad (Context-specific):**
- `CLI_GetTableColumns` - Ties to CLI usage
- `TableDetailsDialog_GetColumns` - Ties to specific dialog
- `Tab1_Query` - Meaningless

**Benefits:**
- Same query name works across all providers
- Easy to find equivalent queries for new databases
- Clear documentation of query purpose
- Reduces duplication

### 3. Interface-Based Connection Management

**Current:** `DB2ConnectionManager`

**Future Design:**
```csharp
public interface IDbConnectionManager
{
    string DatabaseProvider { get; } // "DB2", "PostgreSQL", etc.
    string DatabaseVersion { get; }  // "12.1", "15", etc.
    Task<DataTable> ExecuteQueryAsync(string sql, int? maxRows = null);
    void Close();
}

public class DB2ConnectionManager : IDbConnectionManager { ... }
public class PostgreSqlConnectionManager : IDbConnectionManager { ... }
public class OracleConnectionManager : IDbConnectionManager { ... }
public class SqlServerConnectionManager : IDbConnectionManager { ... }
```

### 4. Validation Rules Configuration

**Future Structure: `ValidationRules/{Provider}_rules.json`**

```json
{
  "provider": "DB2",
  "version": "12.1",
  "tableForms": {
    "cliCommand": "table-props",
    "formName": "table-details",
    "tabs": [
      {
        "name": "columns",
        "cliDataPath": "columns",
        "formDataPath": "data.rows",
        "comparison": "arrayLength",
        "tolerance": 0
      },
      {
        "name": "foreignKeys",
        "cliDataPath": "foreignKeys",
        "formDataPath": "data.rows",
        "comparison": "arrayLength",
        "tolerance": 0
      }
    ]
  }
}
```

## Validation Comparison Logic

### Comparison Types

1. **Array Length** - Compare row counts
   ```powershell
   $cliRows = $cliData.columns.Count
   $formRows = $formData.data.rowCount
   $match = $cliRows -eq $formRows
   ```

2. **String Content** - Compare text (DDL, source code)
   ```powershell
   $cliDdl = $cliData.ddl
   $formDdl = $formData.data.text
   # Normalize whitespace before comparing
   $match = ($cliDdl -replace '\s+', ' ') -eq ($formDdl -replace '\s+', ' ')
   ```

3. **Field Values** - Compare specific fields
   ```powershell
   $cliTable = $cliData.tableName
   $formTable = $formData.fullTableName.Split('.')[1]
   $match = $cliTable -eq $formTable
   ```

4. **Numeric Values** - Compare statistics
   ```powershell
   $cliRowCount = $cliData.statistics.rowCount
   $formRowCount = $formData.data.rowCount
   $match = $cliRowCount -eq $formRowCount
   ```

### Tolerance Levels

Some comparisons may need tolerance:
- **Exact Match** (tolerance = 0): Columns, FKs, Indexes (structural metadata)
- **Close Match** (tolerance = 5%): Row counts, statistics (may change during testing)
- **Format Match** (normalize whitespace): DDL scripts, source code

## Current Implementation Status

### ✅ Completed

1. **CLI Parameters**
   - `--test-form` parameter added
   - `--tab` parameter added
   - CliArgumentParser updated

2. **GuiTestingService**
   - Service created and functional
   - Async/await properly handled
   - Error handling implemented
   - Debug logging comprehensive

3. **TableDetailsDialog**
   - Public accessors added for all controls
   - Data extraction tested and working
   - All 9 tabs extractable

4. **Validation Framework**
   - PowerShell validation script created
   - CLI vs Form comparison logic implemented
   - CSV and JSON output generated

5. **Bug Fixes**
   - DDL Script error fixed (Column COLNAME issue)
   - Parameter replacement bug fixed in AccessControlService
   - Async dispatcher handling fixed

### ⏳ TODO (Next Phases)

1. **Extend to All Property Dialogs**
   - ViewDetailsDialog
   - ProcedureDetailsDialog
   - FunctionDetailsDialog
   - TriggerDetailsDialog
   - PackageDetailsDialog

2. **Enhanced Validation**
   - Deep field-level comparison
   - DDL content validation
   - Statistics accuracy testing
   - Performance benchmarking (CLI vs Form speed)

3. **Multi-Database Preparation**
   - Create IDbConnectionManager interface
   - Abstract SQL configuration loading
   - Define provider-specific validation rules
   - Document provider requirements

4. **Documentation**
   - Create provider implementation guide
   - Document validation rule format
   - Create migration guide for new databases

## Usage Examples

### Test All Tabs of a Table

```powershell
DbExplorer.exe --profile PRODDB \
  --test-form table-details \
  --object MYSCHEMA.CUSTOMERS \
  --outfile all_tabs.json
```

**Output:**
```json
{
  "formName": "TableDetailsDialog",
  "fullTableName": "MYSCHEMA.CUSTOMERS",
  "extractedAt": "2025-12-13T20:00:00",
  "tabs": {
    "columns": { "rowCount": 25, "rows": [...] },
    "foreignKeys": { "rowCount": 5, "rows": [...] },
    "indexes": { "rowCount": 3, "rows": [...] },
    "ddlScript": { "text": "CREATE TABLE ...", "length": 1024 },
    "statistics": { "rowCount": "150000", "tableType": "USER", ... },
    "incomingFK": { "rowCount": 2, "rows": [...] },
    "usedByPackages": { "rowCount": 0, "rows": [] },
    "usedByViews": { "rowCount": 1, "rows": [...] },
    "usedByRoutines": { "rowCount": 0, "rows": [] }
  }
}
```

### Test Specific Tab

```powershell
DbExplorer.exe --profile PRODDB \
  --test-form table-details \
  --object MYSCHEMA.CUSTOMERS \
  --tab columns \
  --outfile columns_only.json
```

**Output:**
```json
{
  "formName": "TableDetailsDialog",
  "fullTableName": "MYSCHEMA.CUSTOMERS",
  "extractedAt": "2025-12-13T20:00:00",
  "tab": "columns",
  "data": {
    "rowCount": 25,
    "rows": [
      {"COLNAME": "CUSTOMER_ID", "TYPENAME": "INTEGER", "LENGTH": 4, ...},
      {"COLNAME": "FIRST_NAME", "TYPENAME": "VARCHAR", "LENGTH": 50, ...},
      ...
    ]
  }
}
```

### Run Validation

```powershell
.\_validate_forms.ps1 -Profile "PRODDB" -TestObject "MYSCHEMA.CUSTOMERS"
```

**Output:**
```
=============================================
   GUI vs CLI VALIDATION FRAMEWORK
=============================================

TEST 1: Columns Tab
✅ PASS: ✅ MATCH: Both have 25 rows

TEST 2: Foreign Keys Tab
✅ PASS: ✅ MATCH: Both have 5 rows

TEST 3: Indexes Tab
✅ PASS: ✅ MATCH: Both have 3 rows

TEST 4: DDL Script Tab
✅ PASS: Both have DDL content

=============================================
   VALIDATION SUMMARY
=============================================

Total Tests: 4
Passed: 4
Failed: 0
Success Rate: 100%
```

## Future Database Provider Implementation Guide

### Step 1: Create SQL Configuration

Create `ConfigFiles/{provider}_{version}_sql_statements.json`:

```json
{
  "provider": "PostgreSQL",
  "version": "15",
  "statements": {
    "GetTableColumns": {
      "sql": "SELECT column_name, data_type, character_maximum_length, is_nullable FROM information_schema.columns WHERE table_schema = ? AND table_name = ?",
      "description": "Get column information",
      "parameters": ["SCHEMA", "TABLE"],
      "returns": "Column metadata"
    }
  }
}
```

### Step 2: Create Connection Manager

```csharp
public class PostgreSqlConnectionManager : IDbConnectionManager
{
    public string DatabaseProvider => "PostgreSQL";
    public string DatabaseVersion => "15";
    
    public async Task<DataTable> ExecuteQueryAsync(string sql, int? maxRows = null)
    {
        // PostgreSQL-specific implementation using Npgsql
    }
}
```

### Step 3: Create Property Dialogs

```csharp
public class PostgreSqlTableDetailsDialog : Window
{
    // Similar structure to TableDetailsDialog
    // Uses PostgreSQL-specific queries via MetadataHandler
}
```

### Step 4: Extend GuiTestingService

```csharp
private async Task<Dictionary<string, object>> TestPgTableDetailsDialogAsync(...)
{
    // PostgreSQL-specific dialog testing
    var dialog = new PostgreSqlTableDetailsDialog(connectionManager, objectName);
    // Extract data similar to DB2 version
}
```

### Step 5: Create Validation Rules

Create `ValidationRules/PostgreSQL_rules.json`:

```json
{
  "provider": "PostgreSQL",
  "version": "15",
  "tableForms": {
    "cliCommand": "pg-table-props",
    "formName": "pg-table-details",
    "tabs": [ ... ]
  }
}
```

### Step 6: Test and Validate

```powershell
.\_validate_forms.ps1 -Profile "PG_PROD" -TestObject "public.customers" -DatabaseProvider "PostgreSQL"
```

## Benefits of This Approach

1. **Automated Verification** - No manual testing required
2. **Regression Detection** - Catch SQL query bugs immediately
3. **Multi-Database Ready** - Framework designed for expansion
4. **Documentation** - Validation results document query accuracy
5. **Confidence** - Prove forms show correct data before deployment
6. **Maintenance** - Easy to add new forms/tabs/providers
7. **Future-Proof** - Prepared for PostgreSQL, Oracle, SQL Server support

## Maintenance Guidelines

### When Adding New Form

1. Add public accessors to dialog (e.g., `MyGridPublic => MyGrid`)
2. Add extraction method to GuiTestingService
3. Add `--test-form` case in TestFormAsync
4. Update validation script with new test
5. Document in this file

### When Adding New Database Provider

1. Create SQL configuration JSON
2. Implement IDbConnectionManager
3. Create provider-specific dialogs
4. Extend GuiTestingService
5. Create validation rules JSON
6. Test and document

### When Modifying SQL Queries

1. Update SQL in JSON configuration
2. Run validation script to verify forms still work
3. Fix any mismatches detected
4. Commit with validation proof

## Conclusion

This GUI Validation Framework is a **critical foundation for multi-database support**. By establishing this pattern now with DB2, we can efficiently expand to PostgreSQL, Oracle, and SQL Server in the future with minimal code duplication and maximum confidence in data accuracy.

The framework ensures that every form, every tab, and every field displays the correct data, regardless of the underlying database provider.

**Next Steps:**
1. Complete validation for all TableDetailsDialog tabs
2. Extend to remaining property dialogs
3. Create provider abstraction interfaces
4. Document provider implementation process

---

**Document Version:** 1.0  
**Last Updated:** 2025-12-13  
**Author:** DbExplorer Development Team  
**Purpose:** Multi-Database GUI Validation Framework Specification

