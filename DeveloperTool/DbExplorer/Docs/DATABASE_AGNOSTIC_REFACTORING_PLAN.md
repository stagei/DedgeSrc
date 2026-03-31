# Database-Agnostic Refactoring Plan

This document categorizes all DB2 references into items that should be made database-agnostic vs. those that should remain provider-specific.

## Legend
- ✅ **CHANGE** - Should be renamed/refactored for database-agnostic naming
- 🔒 **KEEP DB2** - Should remain DB2-specific (provider implementation)
- ⚠️ **CONDITIONAL** - Depends on context; may need partial changes

---

## 1. Project/Namespace Naming

### ✅ CHANGE - Project Names
| Current | Proposed | Reason |
|---------|----------|--------|
| `DbExplorer` (namespace) | `DbExplorer` or `DatabaseManager` | Core namespace should be provider-agnostic |
| `DbExplorer.sln` | `DbExplorer.sln` | Solution name |
| `DbExplorer.csproj` | `DbExplorer.csproj` | Project file |
| `DbExplorer.AutoTests` | `DbExplorer.AutoTests` | Test project |

---

## 2. Data Layer (`Data/` folder)

### 🔒 KEEP DB2 - Provider Implementations
These implement `IConnectionManager` interface and contain DB2-specific driver code:

- [ ] `Data/DB2ConnectionManager.cs` - **KEEP** as DB2 provider implementation
  - Uses `IBM.Data.Db2` driver
  - Uses `DB2Conn`, `DB2Command`, `DB2DataAdapter`, `DB2Exception`
  - Should implement `IConnectionManager` interface ✅ (already done)
  
- [ ] `Data/DbConnectionManager.cs` - **KEEP** as multi-provider wrapper
  - Contains provider switch logic

### ✅ CHANGE - Interfaces (Already Done)
- [x] `Data/IConnectionManager.cs` - Created ✅
- [x] Interface is provider-agnostic ✅

---

## 3. Models (`Models/` folder)

### ✅ CHANGE - Already Completed
- [x] `Models/IConnectionInfo.cs` - Created ✅
- [x] `Models/DatabaseConnection.cs` - Created ✅ (replaces DB2Connection)
- [x] `Models/DB2Connection.cs` - Now extends `DatabaseConnection` for backward compatibility

### ✅ CHANGE - Pending Updates
| File | Current Reference | Change To |
|------|-------------------|-----------|
| `Models/SavedConnection.cs` | `ToDb2Connection()` method | `ToDatabaseConnection()` |
| `Models/UserAccessLevel.cs` | Comment mentions "DB2 DBAUTH" | Generic comment |

---

## 4. UI Controls (`Controls/` folder)

### ✅ CHANGE - Should Be Provider-Agnostic

| File | Items to Change |
|------|-----------------|
| `ConnectionTabControl.xaml` | ToolTip "Your DB2 access level" → "Your access level" |
| `ConnectionTabControl.xaml.cs` | `DB2Connection` → `DatabaseConnection` ✅ (done) |
| `ConnectionTabControl.xaml.cs` | `_intellisenseService = new IntellisenseService("DB2", "12.1")` → Get from connection |
| `ConnectionTabControl.xaml.cs` | Comment "Load custom DB2 SQL syntax highlighting" → Generic |
| `ConnectionTabControl.xaml.cs` | `DB2MetadataService` usage → Use interface |
| `WelcomePanel.xaml` | "Professional DB2 Database Manager" → "Professional Database Manager" |
| `WelcomePanel.xaml.cs` | `DB2Connection` references → `DatabaseConnection` |
| `TableDetailsPanel.xaml.cs` | `_metadataHandler.GetQuery("DB2", "12.1", ...)` → Get provider from connection |
| All panel `.xaml.cs` files | `DB2ConnectionManager` parameter types → `IConnectionManager` |

### ✅ CHANGE - Panel InitializeAsync Methods (All should accept IConnectionManager)
- [ ] `ActiveSessionsPanel.xaml.cs`
- [ ] `CdcManagerPanel.xaml.cs`
- [ ] `CommentManagerPanel.xaml.cs` ✅ (partially done)
- [ ] `DatabaseLoadMonitorPanel.xaml.cs`
- [ ] `DependencyGraphPanel.xaml.cs`
- [ ] `LockMonitorPanel.xaml.cs`
- [ ] `MigrationAssistantPanel.xaml.cs`
- [ ] `PackageAnalyzerPanel.xaml.cs`
- [ ] `PackageDetailsPanel.xaml.cs`
- [ ] `RoutineDetailsPanel.xaml.cs`
- [ ] `SourceCodeBrowserPanel.xaml.cs`
- [ ] `StatisticsManagerPanel.xaml.cs`
- [ ] `TableDetailsPanel.xaml.cs`
- [ ] `UnusedObjectsPanel.xaml.cs`
- [ ] `ViewDetailsPanel.xaml.cs`

---

## 5. Dialogs (`Dialogs/` folder)

### ✅ CHANGE - Should Be Provider-Agnostic

| File | Items to Change |
|------|-----------------|
| `ConnectionDialog.xaml` | Title "New DB2 Connection" → "New Connection" |
| `ConnectionDialog.xaml.cs` | `DB2Connection` → `DatabaseConnection` |
| `ConnectionInfoDialog.xaml` | "DB2 Version:" label → "Database Version:" |
| `ObjectDetailsDialog.xaml.cs` | `DB2Connection` parameter → `DatabaseConnection` ✅ (done) |
| `ObjectDetailsDialog.xaml.cs` | `DB2Parameter` usage → abstract parameter |
| All dialog `.xaml.cs` files | `DB2ConnectionManager` → `IConnectionManager` |

### ✅ CHANGE - Dialog Constructors (Should accept interfaces)
- [ ] `AlterStatementReviewDialog.xaml.cs`
- [ ] `CrossDatabaseComparisonDialog.xaml.cs`
- [ ] `DatabaseComparisonDialog.xaml.cs`
- [ ] `DeepAnalysisDialog.xaml.cs`
- [ ] `FunctionDetailsDialog.xaml.cs`
- [ ] `MermaidDesignerWindow.xaml.cs`
- [ ] `ObjectDetailsDialog.xaml.cs` ✅ (partially done)
- [ ] `PackageDetailsDialog.xaml.cs`
- [ ] `ProcedureDetailsDialog.xaml.cs`
- [ ] `SchemaTableSelectionDialog.xaml.cs`
- [ ] `TableDetailsDialog.xaml.cs`
- [ ] `UserDetailsDialog.xaml.cs`
- [ ] `ViewDetailsDialog.xaml.cs`

---

## 6. Services (`Services/` folder)

### 🔒 KEEP DB2 - Provider-Specific Services
These contain DB2-specific SQL or driver code and should stay as-is:

| File | Reason |
|------|--------|
| `Services/DB2MetadataService.cs` | DB2-specific metadata collection |
| `Services/Db2IntelliSenseProvider.cs` | DB2-specific IntelliSense |
| `Services/Db2CompletionData.cs` | DB2-specific completion classes |
| `Services/ObjectBrowserService.cs` | Uses DB2-specific SQL and `DB2Parameter` |
| `Services/DdlGeneratorService.cs` | Uses `DB2Parameter` |
| `Services/DatabaseComparisonService.cs` | Uses `DB2Parameter`, `DB2DataAdapter` |
| `Services/PackageDependencyAnalyzer.cs` | Uses `DB2Parameter`, `DB2DataAdapter` |

### ✅ CHANGE - Should Be Provider-Agnostic

| File | Items to Change |
|------|-----------------|
| `Services/AccessControlService.cs` | `DB2ConnectionManager` → `IConnectionManager` |
| `Services/CommentService.cs` | `DB2ConnectionManager` → `IConnectionManager` |
| `Services/ConnectionProfileService.cs` | `DB2Connection` → `DatabaseConnection` |
| `Services/ConnectionStorageService.cs` | `DB2Connection` → `DatabaseConnection` |
| `Services/DataCaptureService.cs` | `DB2ConnectionManager` → `IConnectionManager` |
| `Services/DatabaseLoadMonitorService.cs` | `DB2ConnectionManager` → `IConnectionManager` |
| `Services/DependencyAnalyzerService.cs` | `DB2ConnectionManager` → `IConnectionManager` |
| `Services/GuiTestingService.cs` | `DB2ConnectionManager` → `IConnectionManager` |
| `Services/IntelliSenseManager.cs` | `DB2ConnectionManager` → `IConnectionManager` |
| `Services/IntellisenseService.cs` | Default `"DB2"` → Get from connection |
| `Services/LockMonitorService.cs` | `DB2ConnectionManager` → `IConnectionManager` |
| `Services/MermaidDiagramGeneratorService.cs` | `DB2ConnectionManager` → `IConnectionManager` |
| `Services/MetadataHandler.cs` | `DB2ConnectionManager` → `IConnectionManager` |
| `Services/MetadataLoaderService.cs` | `DB2ConnectionManager` → `IConnectionManager` |
| `Services/MigrationPlannerService.cs` | `DB2ConnectionManager` → `IConnectionManager` |
| `Services/MultiDatabaseConnectionManager.cs` | `DB2ConnectionManager` → `IConnectionManager` |
| `Services/PackageAnalyzerService.cs` | `DB2ConnectionManager` → `IConnectionManager` |
| `Services/SessionMonitorService.cs` | `DB2ConnectionManager` → `IConnectionManager` |
| `Services/SourceCodeService.cs` | `DB2ConnectionManager` → `IConnectionManager` |
| `Services/SqlMermaidIntegrationService.cs` | `DB2ConnectionManager` → `IConnectionManager` |
| `Services/StatisticsService.cs` | `DB2ConnectionManager` → `IConnectionManager` |
| `Services/TableRelationshipService.cs` | `DB2ConnectionManager` → `IConnectionManager` |
| `Services/UnusedObjectDetectorService.cs` | `DB2ConnectionManager` → `IConnectionManager` |

### ✅ CHANGE - MetadataHandler Calls
All hardcoded `"DB2", "12.1"` calls should derive provider/version from connection:
```csharp
// Current:
_metadataHandler.GetQuery("DB2", "12.1", "QueryName")

// Should be:
_metadataHandler.GetQuery(connection.ProviderType, connection.Version, "QueryName")
```

---

## 7. AI Services (`Services/AI/` folder)

### ✅ CHANGE - Should Be Provider-Agnostic

| File | Items to Change |
|------|-----------------|
| `Services/AI/DeepAnalysisService.cs` | `DB2ConnectionManager` → `IConnectionManager` |
| `Services/AI/ContextBuilders/FunctionContextBuilder.cs` | `DB2ConnectionManager` → `IConnectionManager` |
| `Services/AI/ContextBuilders/PackageContextBuilder.cs` | `DB2ConnectionManager` → `IConnectionManager` |
| `Services/AI/ContextBuilders/ProcedureContextBuilder.cs` | `DB2ConnectionManager` → `IConnectionManager` |
| `Services/AI/ContextBuilders/ViewContextBuilder.cs` | `DB2ConnectionManager` → `IConnectionManager` |

---

## 8. CLI Services (`Services/CliCommandHandlerService.cs`)

### ⚠️ CONDITIONAL - Mixed Content

| Section | Action |
|---------|--------|
| Method signatures (`DB2ConnectionManager`) | ✅ CHANGE to `IConnectionManager` |
| `_metadataHandler.GetQuery("DB2", "12.1", ...)` calls | ✅ CHANGE to use connection's provider |
| Comments mentioning "DB2 12.1 compatibility" | ✅ CHANGE to generic |
| Usage text mentioning "DB2" | ✅ CHANGE to generic or list all providers |
| SQL generation that's inherently DB2 | 🔒 KEEP (but use provider switch) |

---

## 9. Main Application Files

### ✅ CHANGE - MainWindow and App

| File | Items to Change |
|------|-----------------|
| `MainWindow.xaml` | Title "DbExplorer - DB2 Database Manager" → "DbExplorer - Database Manager" |
| `MainWindow.xaml.cs` | `DB2Connection` references → `DatabaseConnection` |
| `MainWindow.xaml.cs` | `DB2ConnectionManager` → Create via factory based on provider |
| `App.xaml.cs` | Log message "DbExplorer" → New app name |
| `App.xaml.cs` | `DB2ConnectionManager` instantiation → Factory pattern |

---

## 10. Configuration Files

### ✅ CHANGE - JSON Files

| File | Items to Change |
|------|-----------------|
| `ConfigFiles/db2_12.1_sql_statements.json` | Stays but accessed via `ProviderType` |
| Folder name `DbExplorer` in AppData | → New app name |
| Log file names | → New app name |

---

## 11. Resources

### 🔒 KEEP DB2 - Syntax Highlighting
| File | Reason |
|------|--------|
| `Resources/DB2SQL.xshd` | DB2-specific syntax - keep but load based on provider |

---

## 12. Test Projects

### ✅ CHANGE - Test Files

| File | Items to Change |
|------|-----------------|
| `DbExplorer.AutoTests/` (entire folder) | Rename to `DbExplorer.AutoTests` |
| `Program.cs` | `DbExplorerTester` → `DbExplorerTester` |
| All test files | `DB2ConnectionManager` → `IConnectionManager` |
| Executable path references | Update to new name |

---

## 13. Documentation Files

### ✅ CHANGE - Markdown Docs
All `.md` files in `Docs/` that reference "DB2" in generic contexts should be updated to be provider-agnostic.

---

## Implementation Priority

### Phase 1: Core Interfaces (COMPLETED ✅)
- [x] Create `IConnectionInfo` interface
- [x] Create `IConnectionManager` interface
- [x] Create `DatabaseConnection` base class
- [x] Update `DB2ConnectionManager` to implement interface

### Phase 2: UI Layer (HIGH PRIORITY)
- [ ] Update all Controls to accept `IConnectionManager`
- [ ] Update all Dialogs to accept `IConnectionManager`
- [ ] Update UI labels/tooltips to be generic

### Phase 3: Service Layer
- [ ] Update services to accept interfaces
- [ ] Create provider factory for connection managers
- [ ] Update MetadataHandler calls to use connection's provider

### Phase 4: Project Naming
- [ ] Rename solution and projects
- [ ] Update namespaces
- [ ] Update AppData folder names

### Phase 5: Future Providers
- [ ] Create `PostgresConnectionManager : IConnectionManager`
- [ ] Create `SqlServerConnectionManager : IConnectionManager`
- [ ] Create provider-specific SQL statement JSON files

---

## Files That Must Stay DB2-Specific

These files contain actual DB2 driver code or DB2-specific implementations:

1. `Data/DB2ConnectionManager.cs` - IBM.Data.Db2 driver usage
2. `Services/DB2MetadataService.cs` - DB2 system catalog queries
3. `Services/Db2IntelliSenseProvider.cs` - DB2 keyword/function lists
4. `Services/Db2CompletionData.cs` - DB2 completion items
5. `Resources/DB2SQL.xshd` - DB2 syntax highlighting
6. `ConfigFiles/db2_12.1_sql_statements.json` - DB2 SQL templates
7. `ConfigFiles/db2_12.1_keywords.json` - DB2 keywords

---

## Summary Statistics

| Category | Count to Change | Count to Keep DB2 |
|----------|-----------------|-------------------|
| Controls | 16 | 0 |
| Dialogs | 14 | 0 |
| Services | 25 | 7 |
| Models | 2 | 0 |
| Main App | 3 | 0 |
| Config | 0 | 3 |
| Resources | 0 | 1 |
| Tests | 10 | 0 |
| **Total** | **~70 files** | **~11 files** |

---

*Last Updated: December 2024*
*Status: Phase 1 Complete, Phase 2 In Progress*
