# Phase 1: ConfigFiles Foundation - Task List

**Goal:** Create ConfigFiles infrastructure and load metadata at startup  
**Estimated Duration:** 2 weeks  
**Priority:** 🔴 CRITICAL

---

## Status Summary
- **Total Tasks:** 25
- **Completed:** 0
- **In Progress:** 0
- **Pending:** 25

---

## Tasks

### Week 1: Directory Structure and Initial Files

#### 1.1 Create ConfigFiles Directory
- [ ] Create `ConfigFiles/` directory in project root
- [ ] Add to `.csproj` with `<CopyToOutputDirectory>Always</CopyToOutputDirectory>`
- [ ] Verify files copy to `bin/Debug/net10.0-windows/ConfigFiles/`
- [ ] Test build succeeds

#### 1.2 Create supported_providers.json
- [ ] Create `ConfigFiles/supported_providers.json`
- [ ] Add DB2 provider entry with all metadata
  - [ ] provider_code: "DB2"
  - [ ] display_name: "IBM DB2 Database"
  - [ ] icon: "🗄️"
  - [ ] vendor: "IBM"
  - [ ] supported_versions: ["12.1", "11.5"]
  - [ ] default_port: 50000
  - [ ] connection_string_template
  - [ ] system_catalog_schema: "SYSCAT"
- [ ] Validate JSON syntax
- [ ] Test file loads successfully

#### 1.3 Create db2_12.1_system_metadata.json
- [ ] Move existing metadata from AppData to ConfigFiles
- [ ] Rename to `db2_12.1_system_metadata.json`
- [ ] Add provider and version fields
- [ ] Document SYSCAT.TABLES metadata
- [ ] Document SYSCAT.COLUMNS metadata
- [ ] Document SYSCAT.VIEWS metadata (with join requirement notes)
- [ ] Document SYSCAT.INDEXES metadata
- [ ] Document SYSCAT.PACKAGES metadata
- [ ] Document SYSCAT.STATEMENTS metadata
- [ ] Add all table relationships
- [ ] Add query patterns (how to find FKs, check if FK indexed, etc.)
- [ ] Validate JSON syntax
- [ ] Test file loads successfully

#### 1.4 Extract All SQL Statements
- [ ] Read `Services/ObjectBrowserService.cs` and extract all SQL queries
- [ ] Read all property dialog files and extract SQL queries
- [ ] Review `OBJECT_BROWSER_SQL_QUERIES.md` for verified patterns
- [ ] Review `PROPERTY_DIALOGS_SQL_QUERIES.md` for verified patterns
- [ ] Review `k:\fkavd\dba\Db2CreateDBQA_NonRelated.sql` for proven patterns
- [ ] Create master list of 80+ SQL statements with keys

#### 1.5 Create db2_12.1_sql_statements.json
- [ ] Create `ConfigFiles/db2_12.1_sql_statements.json`
- [ ] Add provider and version fields
- [ ] Add GetSchemasStatement
- [ ] Add GetTablesForSchema
- [ ] Add GetViewsForSchema (with CRITICAL notes)
- [ ] Add GetColumnsForTable
- [ ] Add GetPrimaryKeysForTable
- [ ] Add GetForeignKeysForTable
- [ ] Add GetIndexesForTable
- [ ] Add GetPackagesForSchema
- [ ] Add GetPackageStatements (with join requirement)
- [ ] Add GetFunctionsForSchema
- [ ] Add GetProceduresForSchema
- [ ] Add GetTriggersForTable
- [ ] Add GetSequencesForSchema
- [ ] Add GetUDTsForSchema
- [ ] Add all remaining 60+ queries with plain English descriptions
- [ ] Ensure all CHAR columns have TRIM()
- [ ] Add source references (Db2CreateDBQA_NonRelated.sql line numbers)
- [ ] Validate JSON syntax
- [ ] Test file loads successfully

### Week 2: Text Extraction and MetadataHandler

#### 1.6 Extract All UI Text Elements
- [ ] Scan all XAML files for hardcoded text
- [ ] Scan MainWindow.xaml for menu items
- [ ] Scan all dialog XAML for labels and buttons
- [ ] Scan all UserControl XAML for text
- [ ] Create inventory of 472+ text keys
- [ ] Categorize by: ui.menu, ui.toolbar, ui.object_browser, messages.errors, common.buttons

#### 1.7 Create db2_12.1_en-US_texts.json
- [ ] Create `ConfigFiles/db2_12.1_en-US_texts.json`
- [ ] Add provider, version, language fields
- [ ] Add MainFormTitle: "DbExplorer"
- [ ] Add all ui.menu.* entries
- [ ] Add all ui.toolbar.* entries
- [ ] Add all ui.object_browser.* entries
- [ ] Add all messages.errors.* entries
- [ ] Add all messages.warnings.* entries
- [ ] Add all messages.success.* entries
- [ ] Add all common.buttons.* entries
- [ ] Validate JSON syntax
- [ ] Test file loads successfully

#### 1.8 Implement MetadataHandler Service
- [ ] Create `Services/MetadataHandler.cs`
- [ ] Add NLog logger
- [ ] Implement constructor with ConfigFiles path
- [ ] Implement LoadSupportedProviders()
- [ ] Implement LoadSystemMetadata(provider, version)
- [ ] Implement LoadSqlStatements(provider, version)
- [ ] Implement LoadTexts(provider, version, language)
- [ ] Add caching dictionaries for all metadata
- [ ] Implement GetQuery(provider, version, statementKey)
- [ ] Implement GetText(provider, version, textKey) with fallback
- [ ] Implement GetText with parameter replacement
- [ ] Implement GetAllDistinctLanguages()
- [ ] Implement ChangeLanguage(languageCode)
- [ ] Add comprehensive DEBUG logging
- [ ] Add error handling for missing files
- [ ] Add error handling for missing keys

#### 1.9 Create Data Models
- [ ] Create Models/Provider.cs
- [ ] Create Models/SystemMetadata.cs
- [ ] Create Models/SystemTable.cs
- [ ] Create Models/TableRelationship.cs
- [ ] Create Models/SqlStatement.cs
- [ ] Create Models/TextsFile.cs
- [ ] Add JSON serialization attributes
- [ ] Add XML documentation

#### 1.10 Integration and Testing
- [ ] Update App.xaml.cs to initialize MetadataHandler at startup
- [ ] Add MetadataHandler to DI container
- [ ] Test loading all ConfigFiles
- [ ] Test GetQuery() returns correct SQL
- [ ] Test GetText() with en-US language
- [ ] Test GetText() fallback to English
- [ ] Verify CLI execution with "ILOGTST" profile still works
- [ ] Test build succeeds
- [ ] Test application starts without errors

---

**Status:** ⏳ NOT STARTED  
**Next Milestone:** MetadataHandler loads all ConfigFiles successfully  
**Blockers:** None

---

**Last Updated:** 2025-11-20

