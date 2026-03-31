# CLI Parity Audit - UI to CLI Mapping

## Goal
Every tab in every dialog must be accessible via CLI with SQL or JSON output.

## Dialogs to Audit

### 1. TableDetailsDialog (9 tabs)
- [x] Columns → `table-columns`
- [x] Foreign Keys → `table-foreign-keys`
- [x] Indexes → `table-indexes`
- [x] Statistics → `table-statistics-full`
- [x] DDL Script → `table-ddl`
- [x] Incoming FK → `table-incoming-fks`
- [x] Used By Packages → `table-referencing-packages`
- [x] Used By Views → `table-referencing-views`
- [x] Used By Routines → `table-referencing-routines`
- [ ] AI Assistant → `ai-explain-table` (needs enhancement)

### 2. PackageDetailsDialog (3 tabs + new AI tab)
- [ ] Properties → `package-properties` **MISSING**
- [ ] Statements → `package-statements` **MISSING**
- [ ] Dependencies → `package-dependencies` (partial via `package-details`)
- [ ] AI Assistant → `ai-analyze-package` **MISSING**

### 3. ViewDetailsDialog (4 tabs)
- [ ] Definition → `view-definition` **MISSING**
- [ ] Columns → `view-columns` **MISSING**
- [ ] Dependencies → `view-dependencies` **MISSING**
- [ ] AI Assistant → `ai-explain-view` **MISSING**

### 4. ProcedureDetailsDialog (3 tabs)
- [ ] Source Code → `procedure-source` **MISSING**
- [ ] Parameters → `procedure-parameters` **MISSING**
- [ ] AI Assistant → `ai-analyze-procedure` **MISSING**

### 5. FunctionDetailsDialog (3 tabs)
- [ ] Source Code → `function-source` **MISSING**
- [ ] Parameters → `function-parameters` **MISSING**
- [ ] AI Assistant → `ai-analyze-function` **MISSING**

### 6. DeepAnalysisDialog (3 tabs)
- [ ] Analysis Results → `ai-deep-analysis` (exists but needs enhancement)
- [ ] Relationships → `table-relationships` **MISSING**
- [ ] Raw Data Sample → `table-sample-data` **MISSING**

### 7. DatabaseComparisonDialog (5 tabs)
- [ ] Summary → `db-compare` (exists but needs enhancement)
- [ ] Only in Source → `db-compare-source-only` **MISSING**
- [ ] Only in Target → `db-compare-target-only` **MISSING**
- [ ] Different → `db-compare-different` **MISSING**
- [ ] Migration DDL → `db-compare-ddl` **MISSING**

### 8. UserDetailsDialog
- [ ] User properties → `user-properties` **MISSING**
- [ ] Granted privileges → `user-privileges` **MISSING**

### 9. ObjectDetailsDialog
- [ ] Object metadata → `object-metadata` **MISSING**

## Summary
- **Total Tabs**: ~40
- **CLI Commands Exist**: ~15
- **CLI Commands Missing**: ~25
- **Completion**: 37%

## Implementation Plan
1. Add 25 new CLI commands
2. Enhance 4 existing AI CLI commands
3. Test each command
4. Update help documentation
5. Generate comprehensive CLI reference

**Estimated Time**: 4-6 hours continuous work

