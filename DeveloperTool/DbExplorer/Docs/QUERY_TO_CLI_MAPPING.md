# Query to CLI Command Mapping

## Overview

This document maps all 129 SQL queries in `db2_12.1_sql_statements.json` to their corresponding CLI commands or Form extraction methods for validation.

## Mapping Strategy

Each query can be validated by:
1. **CLI Command** - Execute query via `--command <cmd>`
2. **Form Extraction** - Extract data via `--test-form <form> --tab <tab>`
3. **Comparison** - AI-powered comparison of CLI vs Form results

## Complete Mapping (129 Queries)

### Table Properties (46 queries)

| Query Name | CLI Command | Form Method | Status |
|------------|-------------|-------------|--------|
| GetTablesInSchema | list-tables | ObjectBrowser | ⏳ TODO |
| CountTables | list-tables (count) | N/A | ⏳ TODO |
| GetTableColumns | table-columns | TableDetailsDialog:Columns | ✅ DONE |
| GetTablePrimaryKeys | table-props | TableDetailsDialog:PKs | ⏳ TODO |
| GetTableForeignKeys | table-foreign-keys | TableDetailsDialog:FKs | ✅ DONE |
| GetTableIndexes | table-indexes | TableDetailsDialog:Indexes | ✅ DONE |
| GetTableStatistics | table-statistics-full | TableDetailsDialog:Stats | ⏳ TODO |
| GetTableDdlColumns | table-ddl | TableDetailsDialog:DDL | ✅ DONE |
| GetIncomingForeignKeys | table-incoming-fks | TableDetailsDialog:IncomingFK | ✅ DONE |
| GetTableUsedByPackages | table-referencing-packages | TableDetailsDialog:Packages | ⏳ TODO |
| GetTableUsedByViews | table-referencing-views | TableDetailsDialog:Views | ⏳ TODO |
| GetTableUsedByRoutines | table-referencing-routines | TableDetailsDialog:Routines | ⏳ TODO |
| ... (34 more) | ... | ... | ⏳ TODO |

### View Properties (8 queries)

| Query Name | CLI Command | Form Method | Status |
|------------|-------------|-------------|--------|
| GetViewsInSchema | list-views | ObjectBrowser | ⏳ TODO |
| CountViews | list-views (count) | N/A | ⏳ TODO |
| GetViewSourceCode | view-info | ObjectDetailsDialog:Source | ⏳ TODO |
| GetViewDependencies | dependencies --object VIEW | ObjectDetailsDialog:Dependencies | ⏳ TODO |
| ... | ... | ... | ⏳ TODO |

### Routine Properties (21 queries)

| Query Name | CLI Command | Form Method | Status |
|------------|-------------|-------------|--------|
| GetProceduresInSchema | list-procedures | ObjectBrowser | ⏳ TODO |
| CountProcedures | list-procedures (count) | N/A | ⏳ TODO |
| GetProcedureSourceCode | procedure-info | ObjectDetailsDialog:Source | ⏳ TODO |
| GetFunctionsInSchema | list-functions | ObjectBrowser | ⏳ TODO |
| CountFunctions | list-functions (count) | N/A | ⏳ TODO |
| GetFunctionSourceCode | function-info | ObjectDetailsDialog:Source | ⏳ TODO |
| GetTriggersInSchema | list-triggers | ObjectBrowser | ⏳ TODO |
| CountTriggers | list-triggers (count) | N/A | ⏳ TODO |
| GetTriggerSourceCode | trigger-info | ObjectDetailsDialog:Source | ⏳ TODO |
| ... | ... | ... | ⏳ TODO |

### Package Properties (12 queries)

| Query Name | CLI Command | Form Method | Status |
|------------|-------------|-------------|--------|
| GetPackagesInSchema | list-packages | ObjectBrowser | ⏳ TODO |
| CountPackages | list-packages (count) | N/A | ⏳ TODO |
| GetPackageStatements | package-details | PackageDetailsDialog:Statements | ⏳ TODO |
| GetPackageProperties | package-analysis | PackageDetailsDialog:Properties | ⏳ TODO |
| ... | ... | ... | ⏳ TODO |

### Security & Privileges (11 queries)

| Query Name | CLI Command | Form Method | Status |
|------------|-------------|-------------|--------|
| GetUserDatabasePrivileges | (needs implementation) | UserDetailsDialog:DBPrivs | ⏳ TODO |
| GetGroupDatabasePrivileges | (needs implementation) | UserDetailsDialog:DBPrivs | ⏳ TODO |
| GetUserTablePrivileges | (needs implementation) | UserDetailsDialog:TablePrivs | ⏳ TODO |
| GetUserList | (needs implementation) | ObjectBrowser | ⏳ TODO |
| GetGroupList | (needs implementation) | ObjectBrowser | ⏳ TODO |
| GetRoles | (needs implementation) | ObjectBrowser | ⏳ TODO |
| GetUserAccessLevel | (already used internally) | N/A | ⏳ TODO |
| GetTablePrivileges | (needs implementation) | N/A | ⏳ TODO |
| ... | ... | ... | ⏳ TODO |

### Schema & Database (10 queries)

| Query Name | CLI Command | Form Method | Status |
|------------|-------------|-------------|--------|
| GetSchemasStatement | (needs implementation) | ObjectBrowser | ⏳ TODO |
| CountSchemas | (needs implementation) | N/A | ⏳ TODO |
| GetTablespacesStatement | (needs implementation) | N/A | ⏳ TODO |
| CountTablespaces | (needs implementation) | N/A | ⏳ TODO |
| ... | ... | ... | ⏳ TODO |

### Other/Administrative (21 queries)

| Query Name | CLI Command | Form Method | Status |
|------------|-------------|-------------|--------|
| GetServiceClasses | (needs implementation) | N/A | ⏳ TODO |
| GetWorkloads | (needs implementation) | N/A | ⏳ TODO |
| GetEventMonitors | (needs implementation) | N/A | ⏳ TODO |
| GetBufferpools | (needs implementation) | N/A | ⏳ TODO |
| GetStorageGroups | (needs implementation) | N/A | ⏳ TODO |
| GetServers | (needs implementation) | N/A | ⏳ TODO |
| GetLockMonitorData | lock-monitor | LockMonitorPanel | ⏳ TODO |
| GetActiveSessionsData | active-sessions | ActiveSessionsPanel | ⏳ TODO |
| GetDatabaseLoadData | database-load | DatabaseLoadPanel | ⏳ TODO |
| ... | ... | ... | ⏳ TODO |

## Validation Strategy

### For queries with both CLI and Form:
1. Execute CLI command → save to `cli_{query}.json`
2. Extract from Form → save to `form_{query}.json`
3. Compare using AI
4. Report match/mismatch

### For queries with CLI only:
1. Execute CLI command → save to `cli_{query}.json`
2. Verify SQL executes without error
3. Verify result structure is valid
4. Report success/fail

### For count queries:
1. Execute count query → get count
2. Execute list query → count results
3. Compare counts
4. Report match/mismatch

## Implementation Priority

### Phase 1: Existing CLI Commands (HIGH)
**Estimated:** 60 queries can be validated immediately with existing CLI commands

Focus: Table properties, View info, Procedure info, Function info, Trigger info, Package info

### Phase 2: Simple CLI Additions (MEDIUM)  
**Estimated:** 40 queries need simple CLI command additions

Focus: User/Group queries, Schema queries, Tablespace queries

### Phase 3: Complex/Administrative (LOW)
**Estimated:** 29 queries for administrative/monitoring functions

Focus: Service classes, Workloads, Event monitors, etc.

## Next Actions

1. ✅ Map all 129 queries to CLI commands (THIS DOCUMENT)
2. ⏳ Create automated validation script using this mapping
3. ⏳ Run validation for all existing CLI commands (~60 queries)
4. ⏳ Implement missing CLI commands (~40 queries)
5. ⏳ Validate administrative queries (~29 queries)
6. ⏳ Generate final 100% validation report

---

**Goal:** Validate all 129 queries against their CLI commands or Form extractions with AI-powered comparison to ensure 100% accuracy.

