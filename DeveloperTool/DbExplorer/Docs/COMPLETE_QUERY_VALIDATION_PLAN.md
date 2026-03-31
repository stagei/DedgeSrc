# Complete Query Validation Plan - ALL 122 SYSCAT Queries

## Objective

Validate **ALL 122 SYSCAT queries** in `db2_12.1_sql_statements.json` by comparing:
1. **CLI execution** (direct SQL via --command)
2. **Form extraction** (GUI display via --test-form)
3. **AI comparison** of results to verify correctness

## Current Status

- **Validated:** 5/122 queries (4.1%)
- **Remaining:** 117 queries (95.9%)

## Strategy: Category-Based Testing

Queries fall into 6 categories:

### Category 1: Table Properties (DONE ✅)
**Status:** 5/9 queries validated (55.6%)

| Query | SYSCAT Table | Test Method | Status |
|-------|--------------|-------------|--------|
| GetTableColumns | COLUMNS | CLI vs TableDetailsDialog:Columns | ✅ DONE |
| GetTablePrimaryKeys | KEYCOLUSE, TABCONST | CLI vs TableDetailsDialog:PKs | ⏳ TODO |
| GetTableForeignKeys | REFERENCES | CLI vs TableDetailsDialog:FKs | ✅ DONE |
| GetTableIndexes | INDEXES, INDEXCOLUSE | CLI vs TableDetailsDialog:Indexes | ✅ DONE |
| GetTableDdlColumns | COLUMNS | CLI vs TableDetailsDialog:DDL | ✅ DONE |
| GetTableStatistics | TABLES | CLI vs TableDetailsDialog:Stats | ⏳ TODO |
| GetIncomingForeignKeys | REFERENCES | CLI vs TableDetailsDialog:IncomingFK | ✅ DONE |
| GetTableUsedByPackages | TABDEP, PACKAGES | CLI vs TableDetailsDialog:Packages | ⏳ TODO |
| GetTableUsedByViews | TABDEP, VIEWS | CLI vs TableDetailsDialog:Views | ⏳ TODO |
| GetTableUsedByRoutines | TABDEP, ROUTINES | CLI vs TableDetailsDialog:Routines | ⏳ TODO |

**Action:** Complete remaining 4 queries

---

### Category 2: View Properties (0/8 queries)
**Status:** 0/8 validated (0%)

| Query | SYSCAT Table | Test Method | Status |
|-------|--------------|-------------|--------|
| GetViewsInSchema | TABLES, VIEWS | CLI vs ObjectBrowser list | ⏳ TODO |
| GetViewSourceCode | VIEWS | CLI vs ObjectDetailsDialog:Source | ⏳ TODO |
| GetViewDependencies | TABDEP | CLI vs ObjectDetailsDialog:Dependencies | ⏳ TODO |
| GetViewColumns | COLUMNS | CLI vs ObjectDetailsDialog:Columns | ⏳ TODO |
| GetViewDdl | VIEWS, COLUMNS | CLI vs ObjectDetailsDialog:DDL | ⏳ TODO |
| GetViewsUsingTable | TABDEP | CLI vs TableDetailsDialog:UsedByViews | ⏳ TODO |
| CountViews | VIEWS | CLI vs count validation | ⏳ TODO |

**Action:** Implement ObjectDetailsDialog testing for Views

---

### Category 3: Routine Properties (0/15 queries)
**Status:** 0/15 validated (0%)

#### Procedures (5 queries)
| Query | SYSCAT Table | Test Method | Status |
|-------|--------------|-------------|--------|
| GetProceduresInSchema | ROUTINES | CLI vs ObjectBrowser list | ⏳ TODO |
| GetProcedureSourceCode | ROUTINES | CLI vs ObjectDetailsDialog:Source | ⏳ TODO |
| GetProcedureDependencies | ROUTINEDEP | CLI vs ObjectDetailsDialog:Dependencies | ⏳ TODO |
| GetProcedureParameters | ROUTINEPARMS | CLI vs ObjectDetailsDialog:Parameters | ⏳ TODO |
| CountProcedures | ROUTINES | CLI vs count validation | ⏳ TODO |

#### Functions (5 queries)
| Query | SYSCAT Table | Test Method | Status |
|-------|--------------|-------------|--------|
| GetFunctionsInSchema | ROUTINES | CLI vs ObjectBrowser list | ⏳ TODO |
| GetFunctionSourceCode | ROUTINES | CLI vs ObjectDetailsDialog:Source | ⏳ TODO |
| GetFunctionDependencies | ROUTINEDEP | CLI vs ObjectDetailsDialog:Dependencies | ⏳ TODO |
| GetFunctionParameters | ROUTINEPARMS | CLI vs ObjectDetailsDialog:Parameters | ⏳ TODO |
| CountFunctions | ROUTINES | CLI vs count validation | ⏳ TODO |

#### Triggers (5 queries)
| Query | SYSCAT Table | Test Method | Status |
|-------|--------------|-------------|--------|
| GetTriggersInSchema | TRIGGERS | CLI vs ObjectBrowser list | ⏳ TODO |
| GetTriggerSourceCode | TRIGGERS | CLI vs ObjectDetailsDialog:Source | ⏳ TODO |
| GetTriggerDependencies | (N/A) | CLI vs ObjectDetailsDialog:Dependencies | ⏳ TODO |
| GetTableTriggers | TRIGGERS | CLI vs TableDetailsDialog:Triggers | ⏳ TODO |
| CountTriggers | TRIGGERS | CLI vs count validation | ⏳ TODO |

**Action:** Implement ObjectDetailsDialog testing for Routines/Triggers

---

### Category 4: Package Properties (0/8 queries)
**Status:** 0/8 validated (0%)

| Query | SYSCAT Table | Test Method | Status |
|-------|--------------|-------------|--------|
| GetPackagesInSchema | PACKAGES | CLI vs ObjectBrowser list | ⏳ TODO |
| GetPackageStatements | STATEMENTS, PACKAGES | CLI vs PackageDetailsDialog:Statements | ⏳ TODO |
| GetPackageProperties | PACKAGES | CLI vs PackageDetailsDialog:Properties | ⏳ TODO |
| GetPackageDependencies | (N/A) | CLI vs PackageDetailsDialog:Dependencies | ⏳ TODO |
| CountPackages | PACKAGES | CLI vs count validation | ⏳ TODO |
| GetPackagesUsingTable | TABDEP, PACKAGES | CLI vs TableDetailsDialog:UsedByPackages | ⏳ TODO |

**Action:** Implement PackageDetailsDialog testing

---

### Category 5: Security & Privileges (0/10 queries)
**Status:** 0/10 validated (0%)

| Query | SYSCAT Table | Test Method | Status |
|-------|--------------|-------------|--------|
| GetUserDatabasePrivileges | DBAUTH | CLI vs UserDetailsDialog:DBPrivs | ⏳ TODO |
| GetGroupDatabasePrivileges | DBAUTH | CLI vs UserDetailsDialog:DBPrivs | ⏳ TODO |
| GetUserTablePrivileges | TABAUTH | CLI vs UserDetailsDialog:TablePrivs | ⏳ TODO |
| GetUserSchemaPrivileges | (custom) | CLI vs UserDetailsDialog:SchemaPrivs | ⏳ TODO |
| GetUserList | DBAUTH | CLI vs ObjectBrowser list | ⏳ TODO |
| GetGroupList | DBAUTH | CLI vs ObjectBrowser list | ⏳ TODO |
| GetRoles | ROLES | CLI vs ObjectBrowser list | ⏳ TODO |
| GetUserAccessLevel | DBAUTH | CLI validation | ⏳ TODO |
| GetTablePrivileges | TABAUTH | CLI validation | ⏳ TODO |

**Action:** Implement UserDetailsDialog testing

---

### Category 6: Other Objects (0/20 queries)
**Status:** 0/20 validated (0%)

#### Indexes (3 queries)
| Query | SYSCAT Table | Test Method | Status |
|-------|--------------|-------------|--------|
| GetIndexesInSchema | INDEXES | CLI vs ObjectBrowser list | ⏳ TODO |
| GetIndexDetails | INDEXES, INDEXCOLUSE | CLI validation | ⏳ TODO |
| CountIndexes | INDEXES | CLI vs count validation | ⏳ TODO |

#### Sequences (2 queries)
| Query | SYSCAT Table | Test Method | Status |
|-------|--------------|-------------|--------|
| GetSequencesInSchema | SEQUENCES | CLI vs ObjectBrowser list | ⏳ TODO |
| CountSequences | SEQUENCES | CLI vs count validation | ⏳ TODO |

#### Types (2 queries)
| Query | SYSCAT Table | Test Method | Status |
|-------|--------------|-------------|--------|
| GetTypesInSchema | DATATYPES | CLI vs ObjectBrowser list | ⏳ TODO |
| CountTypes | DATATYPES | CLI vs count validation | ⏳ TODO |

#### Synonyms (2 queries)
| Query | SYSCAT Table | Test Method | Status |
|-------|--------------|-------------|--------|
| GetSynonymsInSchema | TABLES | CLI vs ObjectBrowser list | ⏳ TODO |
| CountSynonyms | TABLES | CLI vs count validation | ⏳ TODO |

#### Schema & Database (5 queries)
| Query | SYSCAT Table | Test Method | Status |
|-------|--------------|-------------|--------|
| GetSchemasStatement | SCHEMATA | CLI validation | ⏳ TODO |
| CountSchemas | SCHEMATA | CLI validation | ⏳ TODO |
| GetTablespacesStatement | TABLESPACES | CLI validation | ⏳ TODO |
| CountTablespaces | TABLESPACES | CLI validation | ⏳ TODO |

#### Administrative (6 queries)
| Query | SYSCAT Table | Test Method | Status |
|-------|--------------|-------------|--------|
| GetServiceClasses | SERVICECLASSES | CLI validation | ⏳ TODO |
| GetWorkloads | WORKLOADS | CLI validation | ⏳ TODO |
| GetEventMonitors | EVENTMONITORS | CLI validation | ⏳ TODO |
| GetBufferpools | BUFFERPOOLS | CLI validation | ⏳ TODO |
| GetStorageGroups | STOGROUPS | CLI validation | ⏳ TODO |
| GetServers | SERVERS | CLI validation | ⏳ TODO |

**Action:** Create standalone CLI validation for queries not tied to dialogs

---

### Category 7: Count Queries (0/15 queries)
**Status:** 0/15 validated (0%)

All "Count*" queries should be validated by comparing:
1. Direct CLI execution of the count query
2. Count of results from the corresponding list query

**Example:**
```powershell
# Execute count query
$cliCount = (DbExplorer.exe --profile PRODDB --command count-tables --outfile cli_count.json | ConvertFrom-Json).count

# Execute list query and count results
$listResults = (DbExplorer.exe --profile PRODDB --command list-tables --outfile cli_list.json | ConvertFrom-Json).tables
$listCount = $listResults.Count

# Compare
if ($cliCount -eq $listCount) { "✅ PASS" } else { "❌ FAIL" }
```

---

## Implementation Plan

### Phase 1: Complete Table Properties (4 queries)
**Estimated Time:** 30 minutes

- [ ] Add PK validation to TableDetailsDialog testing
- [ ] Add Statistics validation
- [ ] Add "Used By" tabs validation (Packages, Views, Routines)

### Phase 2: View Properties (8 queries)
**Estimated Time:** 1.5 hours

- [ ] Create CLI commands for view operations
- [ ] Add ObjectDetailsDialog testing for Views
- [ ] Validate view source code, DDL, dependencies, columns

### Phase 3: Routine Properties (15 queries)
**Estimated Time:** 2 hours

- [ ] Create CLI commands for procedure/function/trigger operations
- [ ] Add ObjectDetailsDialog testing for Procedures
- [ ] Add ObjectDetailsDialog testing for Functions
- [ ] Add ObjectDetailsDialog testing for Triggers
- [ ] Validate source code, parameters, dependencies

### Phase 4: Package Properties (8 queries)
**Estimated Time:** 1 hour

- [ ] Create CLI commands for package operations
- [ ] Add PackageDetailsDialog testing
- [ ] Validate package statements, properties, dependencies

### Phase 5: Security & Privileges (10 queries)
**Estimated Time:** 1.5 hours

- [ ] Create CLI commands for user/group/privilege operations
- [ ] Add UserDetailsDialog testing
- [ ] Validate database privileges, table privileges, schema privileges

### Phase 6: Other Objects (20 queries)
**Estimated Time:** 2 hours

- [ ] Create CLI commands for indexes, sequences, types, synonyms
- [ ] Create standalone validation for schema/database queries
- [ ] Create standalone validation for administrative queries

### Phase 7: Count Queries (15 queries)
**Estimated Time:** 1 hour

- [ ] Create validation script to compare count queries with list query counts
- [ ] Batch validate all count queries

### Phase 8: Final Validation Report (1 query)
**Estimated Time:** 30 minutes

- [ ] Run comprehensive validation on all 122 queries
- [ ] Generate final report with AI comparison results
- [ ] Document any discrepancies
- [ ] Create remediation plan for failed queries

---

## Total Estimated Time

**~10 hours** to validate all 122 queries

## Testing Workflow

For each query:

1. **Identify test method** (dialog vs standalone CLI)
2. **Create/update CLI command** if needed
3. **Execute CLI version** → save to `cli_{query}.json`
4. **Execute Form version** (if applicable) → save to `form_{query}.json`
5. **AI Comparison:**
   ```powershell
   Compare-CliVsFormWithAI -Query "GetTableColumns" `
     -CliFile "cli_GetTableColumns.json" `
     -FormFile "form_GetTableColumns.json" `
     -Object "INL.KONTO"
   ```
6. **Document result:**
   - ✅ PASS - CLI and Form data match
   - ❌ FAIL - Discrepancy found (document details)
   - ⚠️ WARNING - Minor differences (whitespace, formatting)
7. **Add to validation report**

---

## Validation Output

**Final Report Structure:**
```markdown
# Complete Query Validation Report

## Summary
- Total Queries: 122
- Passed: X
- Failed: Y
- Warnings: Z
- Success Rate: XX.X%

## Category Breakdown
- Table Properties: X/9 (XX%)
- View Properties: X/8 (XX%)
- Routine Properties: X/15 (XX%)
- Package Properties: X/8 (XX%)
- Security: X/10 (XX%)
- Other Objects: X/20 (XX%)
- Count Queries: X/15 (XX%)

## Failed Queries (if any)
- Query: GetXXX
- CLI Result: ...
- Form Result: ...
- Discrepancy: ...
- Recommended Fix: ...

## Conclusion
All 122 SYSCAT queries have been validated...
```

---

## Success Criteria

- **100% execution rate** - All 122 queries must be executed
- **95%+ match rate** - At least 95% of queries must show CLI/Form data match
- **Documented discrepancies** - Any failures must be analyzed and documented
- **Remediation plan** - Fixes identified for any incorrect queries

---

**Status:** Ready to implement  
**Next Action:** Start Phase 1 (Complete Table Properties)  
**Goal:** Achieve 100% validation coverage of all SYSCAT queries

