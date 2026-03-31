# Implementation Roadmap: Database-Agnostic Transformation + Norwegian Support

**Created**: 2025-12-13  
**Status**: Phase 1a Complete (25% done)  
**Battery**: 34% → Approaching stop threshold  
**Remaining Work**: ~9-10 hours continuous implementation

---

## 🎯 Project Goals

1. **Database-Agnostic SQL Abstraction**: Move all hardcoded SQL to JSON files
2. **Multi-Language Support**: Add Norwegian (no-NO) localization
3. **Full DB2 Support**: Verify all 121 SQL statements work with DB2 12.1
4. **Comprehensive Testing**: Test GUI + all 90 CLI commands

---

## ✅ Phase 1a: COMPLETE (25% done)

### What's Done
- ✅ 30/121 SQL queries migrated to JSON (6 dialog + 24 service queries)
- ✅ 6 services refactored to use MetadataHandler
- ✅ 2 dialogs refactored to use MetadataHandler
- ✅ Build successful, committed & pushed
- ✅ JSON structure validated and working

### Files Modified
- `ConfigFiles/db2_12.1_sql_statements.json` - 30 new query entries
- `Dialogs/TableDetailsDialog.xaml.cs` - Uses MetadataHandler
- `Dialogs/SchemaTableSelectionDialog.xaml.cs` - Uses MetadataHandler
- `Data/DB2ConnectionManager.cs` - Uses MetadataHandler
- `Services/DB2MetadataService.cs` - Uses MetadataHandler
- `Services/MetadataLoaderService.cs` - Uses MetadataHandler
- `Services/PackageAnalyzerService.cs` - Uses MetadataHandler
- `Services/SourceCodeService.cs` - Uses MetadataHandler
- `Services/TableRelationshipService.cs` - Uses MetadataHandler

---

## 🔄 Phase 1b: CLI Query Migration (IN PROGRESS - 0% done)

### Goal
Migrate 50 SQL queries from `CliCommandHandlerService.cs` to JSON

### Approach
1. Extract all 50 SQL queries with method names
2. Generate JSON entries with `CLI_` prefix
3. Add to `db2_12.1_sql_statements.json`
4. Update `CliCommandHandlerService.cs` to use MetadataHandler
5. Test all 90 CLI commands (some reuse service queries)

### Estimated Time
~3-4 hours continuous work

### Commands Affected (90 total)
- 16 basic queries (table-props, trigger-info, etc.)
- 9 TableDetailsDialog queries
- 9 Source code queries
- 7 Statistics queries
- 5 Mermaid queries
- 4 Metadata queries
- 8 Advanced monitoring queries
- 13 Dependencies/migration/export queries
- 19 User/privileges/CDC/utility queries

### Implementation Script
`_extract_cli_queries.ps1` - Automates SQL extraction from CliCommandHandlerService

---

## 🔄 Phase 1c: Dynamic Query Refactoring (0% done)

### Goal
Refactor 10 StringBuilder-based SQL queries to use templates/parameters

### Challenge
These services dynamically build SQL based on filters - need architectural changes

### Services Affected
1. **CommentService** - Dynamic column comment queries
2. **DatabaseLoadMonitorService** - MON_GET_TABLE with filters
3. **DependencyAnalyzerService** - Complex dependency traversal
4. **MermaidDiagramGeneratorService** - DDL generation from metadata
5. **MigrationPlannerService** - Migration script generation
6. **SqlMermaidIntegrationService** - Multiple Mermaid operations
7. **UnusedObjectDetectorService** - Queries with date filters

### Estimated Time
~2-3 hours continuous work

### Strategy Options
1. **Template-based**: Create SQL templates with conditional sections
2. **Parameterized**: Convert to parameterized queries where possible
3. **Hybrid**: Mix of JSON templates + runtime concatenation for complex cases

---

## 🌍 Phase 2: Norwegian Localization (0% done)

### Goal
Add complete Norwegian (no-NO) language support

### Tasks

#### B1: Create Norwegian Text File (1 hour)
- Create `ConfigFiles/db2_12.1_no-NO_texts.json`
- Translate 119 text keys from `db2_12.1_en-US_texts.json`
- Add Norwegian menu labels
- Add Norwegian button/tooltip texts
- Add Norwegian error messages

#### B2: Update UI for Localization (2 hours)
- Update 13 Dialogs to use `MetadataHandler.GetText()`
- Update 12 Panels to use `GetText()`
- Update MainWindow menus
- Update all MessageBox calls
- Update all status bar messages
- Replace all hardcoded English strings

#### B3: Language Switching (1 hour)
- Add `Language` property to PreferencesService
- Add language dropdown to SettingsDialog
- Implement `SetLanguage()` in MetadataHandler
- Add runtime language switching without restart
- Persist language preference

### Estimated Time
~2-3 hours continuous work

### Files to Create
- `ConfigFiles/db2_12.1_no-NO_texts.json` (119+ keys)

### Files to Modify
- All 13 Dialog files
- All 12 Panel files
- MainWindow.xaml.cs
- PreferencesService.cs
- SettingsDialog.xaml + .cs
- MetadataHandler.cs (add SetLanguage method)

---

## 🧪 Phase 3: Testing & Verification (0% done)

### Goal
Comprehensive testing of all functionality after abstraction

### T1: Build & Compilation Testing (30 min)
- Build project (must succeed with 0 errors)
- Fix any compilation issues
- Verify all MetadataHandler calls are correct
- Check for missing JSON entries

### T2: GUI Testing (2 hours)
- Test ConnectionDialog (connect to FKKTOTST)
- Test TableDetailsDialog:
  * Tab 1: Columns (verify GUI_GetTableColumns)
  * Tab 2: Foreign Keys (verify GUI_GetTableForeignKeys)
  * Tab 3: Indexes (verify GUI_GetTableIndexes)
  * Tab 4: Statistics (verify GUI_GetTableBasicInfo)
  * Tab 5: DDL (verify GUI_GetTableDdlColumns)
  * Tab 6-9: Other tabs
- Test SchemaTableSelectionDialog (verify GUI_GetAllSelectableTables)
- Test all 11 remaining dialogs
- Test all 12 panels
- Test dark/light theme switching
- Test Norwegian language switching

### T3: CLI Testing (2 hours)
- Test all 90 CLI commands against FKKTOTST database
- Use `FETCH FIRST 5 ROWS ONLY` for data queries
- Verify JSON output format unchanged
- Document any breaking changes
- Create CLI test script for automation

### T4: Service Integration Testing (1 hour)
- Test each service independently
- Verify MetadataHandler queries return correct results
- Test error handling (missing query keys, invalid parameters)
- Test with different providers (future: PostgreSQL prep)

### Estimated Time
~3-4 hours continuous work

### Test Script
Create `test_all_cli_commands.ps1` to automate testing

---

## 📋 Phase 4: Documentation & Cleanup (0% done)

### Tasks
- Update README.md with JSON configuration guide
- Document all query keys in SQL statements JSON
- Document all text keys in texts JSON
- Create migration guide for adding new database providers
- Create localization guide for adding new languages
- Update `.cursorrules` with JSON abstraction patterns

### Estimated Time
~1 hour

---

## 📊 Overall Progress

| Phase | Tasks | Progress | Time Est. | Status |
|-------|-------|----------|-----------|--------|
| 1a: Simple Services | 30 queries | ✅ 100% | 2h | COMPLETE |
| 1b: CLI Queries | 50 queries | ⏳ 0% | 3-4h | NOT STARTED |
| 1c: Dynamic Queries | 10 queries | ⏳ 0% | 2-3h | NOT STARTED |
| 2: Norwegian | 40+ tasks | ⏳ 0% | 2-3h | NOT STARTED |
| 3: Testing | 100+ tests | ⏳ 0% | 3-4h | NOT STARTED |
| 4: Documentation | 6 tasks | ⏳ 0% | 1h | NOT STARTED |
| **TOTAL** | **230+ tasks** | **25%** | **13-17h** | **IN PROGRESS** |

**Actual Completed**: 30/121 queries (25%)  
**Remaining Work**: 91 queries + localization + testing = ~9-10 hours

---

## 🔋 System Constraints

- **Battery**: Started at 79%, currently 34%
- **Battery Threshold**: 10% (stop protocol triggers)
- **Token Usage**: 126K/1M (12%)
- **Time Invested**: ~2 hours
- **Time Remaining** (battery): ~2-3 hours at current rate

---

## 🛑 Stop Protocol

**When to stop**:
1. Battery < 10%
2. User requests stop
3. Context window exhausted
4. Critical error encountered

**Stop procedure**:
1. ✅ Commit all changes (`git commit`)
2. ✅ Push to remote (`git push`)
3. ✅ Send SMS: `Send-Sms "+4797188358" "DbExplorer: Stopped at [X]% complete - Battery [Y]% - Changes committed & pushed - [Reason]"`

---

## 🚀 Resumption Guide

**When resuming**:

1. **Verify current state**:
   ```powershell
   git pull
   dotnet build
   # Check ConfigFiles/db2_12.1_sql_statements.json has 30+ entries
   ```

2. **Continue Phase 1b** (CLI queries):
   ```powershell
   pwsh _extract_cli_queries.ps1
   # Follow extraction, add to JSON, update CliCommandHandlerService
   ```

3. **Monitor progress**:
   - Check PHASE1A_SQL_ABSTRACTION_STATUS.md for detailed status
   - Update progress metrics after each batch
   - Commit every 20-25 queries

4. **Testing checkpoints**:
   - Build after every file modification
   - Test CLI commands in batches of 10-20
   - Commit working state frequently

---

## 📝 Key Files

### Configuration
- `ConfigFiles/db2_12.1_sql_statements.json` - 30+ SQL queries (growing)
- `ConfigFiles/db2_12.1_en-US_texts.json` - 119 English text keys
- `ConfigFiles/db2_12.1_no-NO_texts.json` - TO BE CREATED
- `ConfigFiles/db2_12.1_keywords.json` - 100+ SQL keywords
- `ConfigFiles/supported_providers.json` - Provider definitions

### Services
- `Services/MetadataHandler.cs` - Central metadata service (✅ working)
- `Services/CliCommandHandlerService.cs` - 50 queries to migrate (⏳ pending)
- 6 service files - ✅ Refactored to use MetadataHandler

### Dialogs
- `Dialogs/TableDetailsDialog.xaml.cs` - ✅ Refactored
- `Dialogs/SchemaTableSelectionDialog.xaml.cs` - ✅ Refactored
- 11 dialog files - ⏳ Need localization

### Status & Planning
- `Docs/PHASE1A_SQL_ABSTRACTION_STATUS.md` - Detailed status
- `Docs/IMPLEMENTATION_ROADMAP.md` - This file
- `Docs/FINAL_TRANSFORMATION_TASKLIST.md` - Original task list

---

## ✨ Success Criteria

**Phase 1 Complete** when:
- ✅ All 121 SQL queries in JSON
- ✅ All services/dialogs use MetadataHandler
- ✅ Build succeeds
- ✅ No hardcoded SQL remains

**Phase 2 Complete** when:
- ✅ Norwegian text file created (119+ keys)
- ✅ All UI uses GetText()
- ✅ Language switching works
- ✅ Both EN and NO display correctly

**Phase 3 Complete** when:
- ✅ All GUI forms tested
- ✅ All 90 CLI commands tested
- ✅ No regression bugs
- ✅ Documentation updated

---

**Next Action**: Run `_extract_cli_queries.ps1` to begin Phase 1b CLI migration

**Current Status**: Phase 1a complete, solid foundation established, ready for continuation

