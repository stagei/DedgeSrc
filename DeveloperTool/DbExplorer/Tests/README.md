# DbExplorer Test Suite

This directory contains all test scripts for the DbExplorer application, organized by category.

## Directory Structure

```
Tests/
├── CLI/              # Command-line interface tests
├── Validation/       # Data validation and comparison tests
├── UI/               # User interface automation tests
└── Mermaid/          # Mermaid diagram functionality tests
```

## Test Output

All test scripts output JSON results to the `CLI_Test_Output/` folder in the project root. This folder is excluded from git via `.gitignore`.

---

## CLI Tests

Tests that verify the command-line interface functionality.

### `Test-Connection.ps1`
**Purpose:** Basic connection test to verify database connectivity (provider-independent).

**What it tests:**
- Establishes connection using the given profile (DB2 or PostgreSQL)
- Lists available schemas
- Verifies connection success

**Usage:**
```powershell
.\Tests\CLI\Test-Connection.ps1
.\Tests\CLI\Test-Connection.ps1 -Profile PostgreSQL_Local -Provider PostgreSQL
```

**Parameters:** `-Profile`, `-Provider` (or set `WDE_TEST_PROFILE`, `WDE_TEST_PROVIDER`)

**Output:** `CLI_Test_Output\test_schemas.json`

---

### `Test-AllCliCommands.ps1`
**Purpose:** Comprehensive testing of all CLI commands with detailed reporting.

**What it tests:**
- All CLI commands organized by category (tables, views, procedures, etc.)
- Generates detailed markdown report with test results
- Tests both list commands and object-specific commands

**Usage:**
```powershell
.\Tests\CLI\Test-AllCliCommands.ps1 -ProfileName "FKKTOTST" -TestSchema "INL" -TestTable "INL.BILAGNR"
```

**Parameters:**
- `ProfileName` - Database connection profile (default: "FKKTOTST")
- `TestSchema` - Schema to use for testing (default: "INL")
- `TestTable` - Table to use for object-specific tests (default: "INL.BILAGNR")

**Output:** `CLI_Test_Output\TEST_REPORT_*.md`

---

### `Test-AllCliCommandsComprehensive.ps1`
**Purpose:** Tests all 119 CLI commands with full I/O capture (input, console output, JSON results).

**What it tests:**
- Every single CLI command available
- Captures CLI input, console output logs, and JSON results
- Generates comprehensive test report with timestamps

**Usage:**
```powershell
.\Tests\CLI\Test-AllCliCommandsComprehensive.ps1 -Profile "FKKTOTST" [-SkipBuild]
```

**Parameters:**
- `Profile` - Database connection profile (default: "FKKTOTST")
- `SkipBuild` - Skip building the application before testing

**Output:** `CLI_Test_Output\COMPLETE_TEST_REPORT_*.md` and `COMPLETE_TEST_REPORT_*.json`

---

### `Test-CliWithIoCapture.ps1`
**Purpose:** Tests CLI commands with detailed I/O capture for debugging.

**What it tests:**
- CLI command execution with full input/output logging
- Captures both stdout and stderr
- Useful for debugging command failures

**Usage:**
```powershell
.\Tests\CLI\Test-CliWithIoCapture.ps1
```

**Output:** `CLI_Test_Output\*_cli_io_test.json`

---

### `Test-Comprehensive.ps1`
**Purpose:** General comprehensive test suite covering core CLI functionality.

**What it tests:**
- Core CLI commands (list-schemas, list-tables, etc.)
- Table-specific commands (table-properties, table-columns, etc.)
- Basic functionality verification

**Usage:**
```powershell
.\Tests\CLI\Test-Comprehensive.ps1
```

**Output:** `CLI_Test_Output\test_output_*.json`, `CLI_Test_Output\test_results.json`

---

## Validation Tests

Tests that validate data accuracy and compare CLI output with GUI forms.

### `Validate-Comprehensive.ps1`
**Purpose:** Comprehensive validation comparing CLI data with GUI form data.

**What it tests:**
- Compares CLI table-props output with GUI table-details form
- Validates all tabs in table details dialog
- Generates detailed validation report

**Usage:**
```powershell
.\Tests\Validation\Validate-Comprehensive.ps1 -Profile "BASISTST" -TestObject "INL.KONTO"
```

**Parameters:**
- `Profile` - Database connection profile (default: "BASISTST")
- `TestObject` - Database object to test (default: "INL.KONTO")

**Output:** `CLI_Test_Output\validation_results_*.json`, `CLI_Test_Output\validation_report_*.md`

---

### `Validate-AllQueries.ps1`
**Purpose:** Validates all 122 SYSCAT queries defined in SQL statements JSON.

**What it tests:**
- All queries from `ConfigFiles\db2_12.1_sql_statements.json`
- Compares CLI vs Form data for each query
- Tests table properties, columns, foreign keys, indexes, DDL, etc.

**Usage:**
```powershell
.\Tests\Validation\Validate-AllQueries.ps1 -Profile "BASISTST" -TestSchema "INL" -TestTable "KONTO"
```

**Parameters:**
- `Profile` - Database connection profile (default: "BASISTST")
- `TestSchema` - Schema for testing (default: "INL")
- `TestTable` - Table name for testing (default: "KONTO")

**Output:** `CLI_Test_Output\validation_*.json`

---

### `Validate-AllQueriesFkktotst.ps1`
**Purpose:** Complete validation of all 129 queries using FKKTOTST profile (DBA access).

**What it tests:**
- All queries with DBA-level access
- AI-powered comparison between CLI and Form data
- Tests queries that require elevated privileges

**Usage:**
```powershell
.\Tests\Validation\Validate-AllQueriesFkktotst.ps1 -Profile "FKKTOTST" [-MaxQueries 129] [-ContinueOnError]
```

**Parameters:**
- `Profile` - Database connection profile (default: "FKKTOTST")
- `MaxQueries` - Maximum number of queries to test (default: 129)
- `ContinueOnError` - Continue testing even if errors occur

**Output:** `CLI_Test_Output\validation_fkktotst_*.json`, `CLI_Test_Output\validation_fkktotst_*.csv`

---

### `Validate-Forms.ps1`
**Purpose:** GUI vs CLI validation framework - compares data from CLI (direct SQL) vs GUI (form extraction).

**What it tests:**
- Columns tab: CLI table-columns vs Form columns tab
- Foreign Keys tab: CLI table-fks vs Form foreign-keys tab
- Indexes tab: CLI table-indexes vs Form indexes tab
- DDL Script tab: CLI ddl vs Form ddl-script tab

**Usage:**
```powershell
.\Tests\Validation\Validate-Forms.ps1
```

**Output:** `CLI_Test_Output\validation_results.json`, `CLI_Test_Output\validation_results.csv`

---

### `Validate-CliVsForm.ps1`
**Purpose:** Validates CLI vs Form data for all tabs in property dialogs.

**What it tests:**
- Compares CLI output with GUI form data across all tabs
- Verifies forms display correct data
- Ensures forms use correct SQL queries

**Usage:**
```powershell
.\Tests\Validation\Validate-CliVsForm.ps1
```

**Output:** `CLI_Test_Output\*_validation.json`

---

### `Validate-AllPropertyForms.ps1`
**Purpose:** Tests ALL tabs in ALL property dialogs to verify data displays correctly.

**What it tests:**
- TableDetailsDialog: columns, foreign-keys, indexes, incoming-fk, packages, views, routines
- ObjectDetailsDialog: properties for views, procedures, functions
- PackageDetailsDialog: statements, dependencies
- UserDetailsDialog: table-privileges

**Usage:**
```powershell
.\Tests\Validation\Validate-AllPropertyForms.ps1
```

**Output:** `CLI_Test_Output\*_form_test.json`

---

### `Validate-AllQueriesComprehensive.ps1`
**Purpose:** Comprehensive validation of all 129 queries defined in SQL statements JSON.

**What it tests:**
- Systematically tests every query in `db2_12.1_sql_statements.json`
- Maps queries to CLI commands
- Tests with real database objects

**Usage:**
```powershell
.\Tests\Validation\Validate-AllQueriesComprehensive.ps1 -Profile "FKKTOTST" [-MaxHours 20]
```

**Parameters:**
- `Profile` - Database connection profile (default: "FKKTOTST")
- `MaxHours` - Maximum time to run validation (default: 20)

**Output:** `CLI_Test_Output\_comprehensive_validation_results.json`

---

### `Test-PostgreSQLStatements.ps1`
**Purpose:** Log every statement in `ConfigFiles/postgresql_18_sql_statements.json` by **alias** with the **actual SQL** and a **Cursor AI–findable tag** for verification or correction.

**What it does:**
- Loads `postgresql_18_sql_statements.json` and iterates over each statement key (alias).
- For each alias: writes **alias**, **description**, **parameters**, and **sql** to a dedicated verification log.
- Tags each block with `[CURSOR_VERIFY_POSTGRESQL_STATEMENT]` so Cursor AI (or an agent) can search the log and verify/correct the corresponding entry in the JSON file.

**Usage:**
```powershell
.\Tests\Validation\Test-PostgreSQLStatements.ps1 -Profile PostgreSQL_Local -Provider PostgreSQL
.\Tests\Run-TestSuite.ps1 -Tests Statements -Profile PostgreSQL_Local -Provider PostgreSQL
```

**Cursor AI / agent:** Search the verification log for `CURSOR_VERIFY_POSTGRESQL_STATEMENT` to get each alias and SQL; use the alias to locate and verify or correct the statement in `ConfigFiles/postgresql_18_sql_statements.json`.

**Output:**
- `CLI_Test_Output/postgresql_statements_verify_YYYYMMDD_HHMMSS.log` – one block per statement (alias, description, parameters, sql, separator).
- Suite log (when run via Run-TestSuite) also contains the tag for grep.

---

### `Validate-Continuous.ps1`
**Purpose:** Continuous validation of 129 queries - runs continuously, fixes issues, rebuilds as needed.

**What it tests:**
- Continuous loop testing all configured queries
- Compares CLI vs Form results
- Tracks passed/failed/fixed tests

**Usage:**
```powershell
.\Tests\Validation\Validate-Continuous.ps1 -Profile "FKKTOTST" [-MaxHours 20]
```

**Parameters:**
- `Profile` - Database connection profile (default: "FKKTOTST")
- `MaxHours` - Maximum time to run (default: 20)

**Output:** `CLI_Test_Output\continuous_validation_results.json`

---

## UI Tests

Tests that automate user interface interactions using FlaUI or other automation frameworks.

### `Test-AllDialogs.ps1`
**Purpose:** Comprehensive dialog testing script - tests all property dialogs with various database objects.

**What it tests:**
- TableDetailsDialog with multiple tables
- Opens dialogs and verifies they display correctly
- Tests various database objects (tables, views, etc.)

**Usage:**
```powershell
.\Tests\UI\Test-AllDialogs.ps1 -Profile "FKKTOTST"
```

**Parameters:**
- `Profile` - Database connection profile (default: "FKKTOTST")

**Output:** Console output with test results

---

### `Test-AllTabs.ps1`
**Purpose:** Comprehensive testing of all tabs in property dialogs.

**What it tests:**
- All tabs in TableDetailsDialog
- All tabs in ObjectDetailsDialog
- All tabs in PackageDetailsDialog
- Verifies data loads correctly in each tab

**Usage:**
```powershell
.\Tests\UI\Test-AllTabs.ps1
```

**Output:** Console output with test results

---

### `Test-AppWithScreenshots.ps1`
**Purpose:** Tests the application and captures screenshots for documentation.

**What it tests:**
- Application startup and basic functionality
- Captures screenshots at key points
- Useful for documentation and visual verification

**Usage:**
```powershell
.\Tests\UI\Test-AppWithScreenshots.ps1
```

**Output:** Screenshots saved to `Screenshots/` folder

---

### `Test-ClickRecentConnection.ps1`
**Purpose:** Tests clicking on recent connections in the UI.

**What it tests:**
- Recent connections list functionality
- Connection selection from UI
- Verifies connection opens correctly

**Usage:**
```powershell
.\Tests\UI\Test-ClickRecentConnection.ps1
```

**Output:** Console output with test results

---

### `Test-PreciseClick.ps1`
**Purpose:** Tests precise clicking functionality for FKKTOTST connection.

**What it tests:**
- Precise UI element clicking
- Connection-specific interactions
- Verifies click accuracy

**Usage:**
```powershell
.\Tests\UI\Test-PreciseClick.ps1
```

**Output:** Console output with test results

---

### `Test-VisualAutomation.ps1`
**Purpose:** Tests visual automation capabilities.

**What it tests:**
- Visual element recognition
- UI automation workflows
- Screen-based interactions

**Usage:**
```powershell
.\Tests\UI\Test-VisualAutomation.ps1
```

**Output:** Console output with test results

---

### `Run-AutomatedUiTests.ps1`
**Purpose:** Main runner for automated UI tests using FlaUI framework.

**What it tests:**
- Builds application
- Launches application
- Runs automated UI test suite
- Handles cleanup and reporting

**Usage:**
```powershell
.\Tests\UI\Run-AutomatedUiTests.ps1 -ProfileName "FKKTOTST" -TestSchema "INL" [-BuildOnly] [-Verbose]
```

**Parameters:**
- `ProfileName` - Database connection profile (default: "FKKTOTST")
- `TestSchema` - Schema for testing (default: "INL")
- `BuildOnly` - Only build, don't run tests
- `Verbose` - Verbose output

**Output:** Console output with test results

---

## Mermaid Tests

Tests specific to Mermaid diagram functionality.

### `Test-MermaidFunctionality.ps1`
**Purpose:** Tests Mermaid diagram generation and display functionality.

**What it tests:**
- Mermaid diagram generation
- Diagram rendering
- ERD (Entity Relationship Diagram) functionality

**Usage:**
```powershell
.\Tests\Mermaid\Test-MermaidFunctionality.ps1
```

**Output:** `CLI_Test_Output\mermaid_test_output.json`

---

### `Test-MermaidDesignerFlaUi.ps1`
**Purpose:** Tests Mermaid Designer using FlaUI automation framework.

**What it tests:**
- Mermaid Designer dialog interactions
- Diagram editing functionality
- UI automation for Mermaid features

**Usage:**
```powershell
.\Tests\Mermaid\Test-MermaidDesignerFlaUi.ps1
```

**Output:** Console output with test results

---

### `Test-MermaidDesignerForm.ps1`
**Purpose:** Tests Mermaid Designer form functionality.

**What it tests:**
- Mermaid Designer form display
- Form data extraction
- Diagram configuration

**Usage:**
```powershell
.\Tests\Mermaid\Test-MermaidDesignerForm.ps1
```

**Output:** `CLI_Test_Output\*_mermaid_designer.json`

---

### `Verify-MermaidComplete.ps1`
**Purpose:** Verifies Mermaid implementation is complete and functional.

**What it tests:**
- All Mermaid features are implemented
- No missing functionality
- Complete feature set verification

**Usage:**
```powershell
.\Tests\Mermaid\Verify-MermaidComplete.ps1
```

**Output:** Console output with verification results

---

## Running Tests Independent of Database Provider

Tests can run with **any supported provider** (DB2 or PostgreSQL). Use a connection profile and optionally specify the provider so DB2-only commands are skipped when using PostgreSQL.

### Environment variables (recommended for CI / scripted runs)

| Variable | Description | Example |
|----------|-------------|---------|
| `WDE_TEST_PROFILE` | Connection profile name | `FKKTOTST`, `PostgreSQL_Local` |
| `WDE_TEST_PROVIDER` | Provider for skip logic | `DB2`, `PostgreSQL` |

### Parameters

Most CLI and validation scripts accept:

- **`-Profile`** – Connection profile (default from `WDE_TEST_PROFILE` or `FKKTOTST`)
- **`-Provider`** – `DB2` or `PostgreSQL`; when `PostgreSQL`, DB2-only commands (packages, lock monitor, CDC, etc.) are skipped

### Examples

**DB2 (default):**
```powershell
.\Tests\CLI\Test-Connection.ps1
.\Tests\CLI\Test-Connection.ps1 -Profile FKKTOTST
.\Tests\CLI\Test-AllCliCommands.ps1 -ProfileName FKKTOTST -TestSchema INL -TestTable "INL.BILAGNR"
```

**PostgreSQL:**
```powershell
$env:WDE_TEST_PROFILE = "PostgreSQL_Local"
$env:WDE_TEST_PROVIDER = "PostgreSQL"
.\Tests\CLI\Test-Connection.ps1
.\Tests\CLI\Test-AllCliCommands.ps1 -Provider PostgreSQL
.\Tests\CLI\Test-AllCliCommandsComprehensive.ps1 -Profile PostgreSQL_Local -Provider PostgreSQL
.\Tests\Validation\Validate-AllQueriesComprehensive.ps1 -Profile PostgreSQL_Local -Provider PostgreSQL
```

**Explicit profile + provider (no env):**
```powershell
.\Tests\CLI\Test-Connection.ps1 -Profile PostgreSQL_Local -Provider PostgreSQL
.\Tests\Validation\Validate-AllQueriesComprehensive.ps1 -Profile MyDB2 -Provider DB2
```

### Shared config

`Tests\TestConfig.ps1` is dot-sourced by CLI and validation scripts. It sets profile/provider from parameters or env and defines which CLI commands are DB2-only (skipped when `-Provider PostgreSQL`).

---

## Standardized Test Runner and Logging

### Run-TestSuite.ps1

Single entry point: kill processes, ensure PostgreSQL_Local profile, build, run tests, check app logs, optionally start the app.

**Usage:**
```powershell
.\Tests\Run-TestSuite.ps1 [-Profile PostgreSQL_Local] [-Provider PostgreSQL] [-Tests Connection|AllCLI|All|Statements] [-SkipKill] [-SkipBuild] [-StartApp] [-EnsurePg18Only]
```

**Steps:** (1) Kill `DbExplorer` / `DbExplorerTray`; (2) Ensure `PostgreSQL_Local` in `Documents\DbExplorer\connections.json`; (3) Build tray then main; (4) Run tests (Connection, AllCLI, or All); (5) Check `bin\Debug\net10.0-windows\logs\db2editor-*.log` for ERROR/FATAL/Exception; (6) If `-StartApp`, launch the app.

**Example (full run with PostgreSQL):**
```powershell
.\Tests\Run-TestSuite.ps1 -Tests All -Profile PostgreSQL_Local -Provider PostgreSQL
```

### TestLogger.ps1 and test logging

- **TestLogger.ps1** provides `Start-TestLog`, `Write-TestLog`, and `Get-TestLogPath` for timestamped, level-based (INFO, WARN, ERROR, DEBUG, PASS, FAIL) logging.
- When run **under Run-TestSuite**, child scripts write to the **same suite log** (`WDE_TEST_LOG_PATH`). When run **standalone**, each script gets its own log in `CLI_Test_Output/` (e.g. `connection_test_YYYYMMDD_HHMMSS.log`).
- **TestConfig.ps1** logs the resolved profile/provider at DEBUG when TestLogger is loaded.
- **Test-Connection.ps1** uses TestLogger for connection attempt, success/failure, and schema count.

**Log location:** `CLI_Test_Output/testsuite_YYYYMMDD_HHMMSS.log` (when using Run-TestSuite).

---

## Running Tests

### Quick Start

To run a specific test:
```powershell
cd C:\opt\src\DbExplorer
.\Tests\CLI\Test-Connection.ps1
```

### Running All CLI Tests

```powershell
Get-ChildItem Tests\CLI\*.ps1 | ForEach-Object { Write-Host "Running $($_.Name)..."; & $_.FullName }
```

### Running All Validation Tests

```powershell
Get-ChildItem Tests\Validation\*.ps1 | ForEach-Object { Write-Host "Running $($_.Name)..."; & $_.FullName }
```

---

## Test Output Location

All test scripts output their results to:
- **JSON files:** `CLI_Test_Output/` (in project root)
- **Reports:** `CLI_Test_Output/*.md` (markdown reports)
- **CSV files:** `CLI_Test_Output/*.csv` (validation results)

The `CLI_Test_Output/` folder is excluded from git via `.gitignore`.

---

## Notes

- All scripts use relative paths and should be run from the project root directory
- Scripts automatically create the `CLI_Test_Output` directory if it doesn't exist
- Most scripts require a database connection profile to be configured (DB2 or PostgreSQL)
- Use `-Provider PostgreSQL` or `WDE_TEST_PROVIDER=PostgreSQL` to run with PostgreSQL; DB2-only commands are skipped automatically
- UI tests require the application to be built before running
- Some tests may take a long time to complete (especially comprehensive validation tests)

---

## Contributing

When adding new test scripts:
1. Place them in the appropriate subdirectory (`CLI/`, `Validation/`, `UI/`, or `Mermaid/`)
2. Use descriptive names following the pattern: `Test-<Feature>.ps1` or `Validate-<Feature>.ps1`
3. Update this README with a description of what the test does
4. Ensure all output goes to `CLI_Test_Output/` directory
5. Use relative paths from the project root
