# MMD Diff Test Report - Both Directions
**Generated:** 2025-12-01 19:46:10

## Test Overview
This test generates ALTER statements from MMD schema differences in **both directions**:
1. **Forward (Before → After)**: Changes to migrate from `testBeforeChange.mmd` to `testAfterChange.mmd`
2. **Reverse (After → Before)**: Changes to rollback from `testAfterChange.mmd` to `testBeforeChange.mmd`

Each direction is tested with multiple SQL dialects.

## Input Files
- **Before:** `TestFiles/testBeforeChange.mmd` (36 903 bytes, 963 lines)
- **After:** `TestFiles/testAfterChange.mmd` (36 913 bytes, 1 177 lines)

**Export Directory:** `D:\opt\src\SqlMermaidErdTools\TestSuite\RegressionTest\Audit\20251201_194553\MmdDiffTest_Export`

## Direction 1: Before → After (Forward Migration)
These ALTER statements migrate the schema from the 'before' state to the 'after' state.

### ANSI SQL
- **Status:** ✅ Success
- **Duration:** 155ms
- **Output Size:** 518 bytes
- **Output Lines:** 14
- **File:** `Forward_Before-To-After/AnsiSql/forward_alter_AnsiSql.sql`

### T-SQL (SQL Server)
- **Status:** ✅ Success
- **Duration:** 133ms
- **Output Size:** 518 bytes
- **Output Lines:** 14
- **File:** `Forward_Before-To-After/SqlServer/forward_alter_SqlServer.sql`

### PostgreSQL
- **Status:** ✅ Success
- **Duration:** 143ms
- **Output Size:** 518 bytes
- **Output Lines:** 14
- **File:** `Forward_Before-To-After/PostgreSql/forward_alter_PostgreSql.sql`

### MySQL
- **Status:** ✅ Success
- **Duration:** 136ms
- **Output Size:** 518 bytes
- **Output Lines:** 14
- **File:** `Forward_Before-To-After/MySql/forward_alter_MySql.sql`

## Direction 2: After → Before (Reverse/Rollback)
These ALTER statements rollback the schema from the 'after' state to the 'before' state.

### ANSI SQL
- **Status:** ✅ Success
- **Duration:** 136ms
- **Output Size:** 602 bytes
- **Output Lines:** 14
- **File:** `Reverse_After-To-Before/AnsiSql/reverse_alter_AnsiSql.sql`

### T-SQL (SQL Server)
- **Status:** ✅ Success
- **Duration:** 135ms
- **Output Size:** 600 bytes
- **Output Lines:** 14
- **File:** `Reverse_After-To-Before/SqlServer/reverse_alter_SqlServer.sql`

### PostgreSQL
- **Status:** ✅ Success
- **Duration:** 139ms
- **Output Size:** 602 bytes
- **Output Lines:** 14
- **File:** `Reverse_After-To-Before/PostgreSql/reverse_alter_PostgreSql.sql`

### MySQL
- **Status:** ✅ Success
- **Duration:** 133ms
- **Output Size:** 600 bytes
- **Output Lines:** 14
- **File:** `Reverse_After-To-Before/MySql/reverse_alter_MySql.sql`

## Analysis & Summary

### Key Observations
- ✅ Both forward and reverse migrations completed successfully
- ✅ All SQL dialects generated ALTER statements
- Export files include SQLGlot intermediate representations (AST files)

### Usage Scenarios
- **Forward (Before→After)**: Use for deploying schema changes to production
- **Reverse (After→Before)**: Use for rollback procedures if deployment fails

### Important Notes
- ⚠️ Always review generated ALTER statements before executing
- ⚠️ Test migrations in non-production environment first
- ⚠️ Some schema changes may require manual data migration
- ⚠️ Certain changes (e.g., column drops) may result in data loss

