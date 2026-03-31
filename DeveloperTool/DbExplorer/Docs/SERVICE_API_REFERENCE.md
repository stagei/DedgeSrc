# Service API Quick Reference

**All implemented services ready for use!**

---

## 🎯 How to Use the Services

All services follow the same pattern:

```csharp
using DbExplorer.Services;
using DbExplorer.Data;

// Create connection manager
var connectionManager = new DB2ConnectionManager(connection);
await connectionManager.OpenAsync();

// Use any service
var service = new SomeService();
var result = await service.SomeMethodAsync(connectionManager, parameters);
```

---

## 📊 Database Load Monitoring

```csharp
var loadService = new DatabaseLoadMonitorService();
var filter = new LoadMonitorFilter
{
    SelectedSchema = "FK",
    SelectedTable = "*",
    ExcludeSystemSchemas = true
};

var metrics = await loadService.GetTableActivityAsync(connectionManager, filter);

// Get schemas
var schemas = await loadService.GetAvailableSchemasAsync(connectionManager);

// Get tables for schema
var tables = await loadService.GetTablesForSchemaAsync(connectionManager, "FK");

// Calculate delta between snapshots
var delta = loadService.CalculateDelta(currentSnapshot, previousSnapshot, interval);
```

---

## 🔒 Lock Monitoring

```csharp
var lockService = new LockMonitorService();
var filter = new LockMonitorFilter
{
    SchemaFilter = "FK",
    ShowOnlyBlocked = true
};

var locks = await lockService.GetCurrentLocksAsync(connectionManager, filter);

// Generate termination script
var script = lockService.GenerateForceApplicationScript(locks);
```

---

## 📊 Table Statistics

```csharp
var statsService = new StatisticsService();
var filter = new StatisticsFilter
{
    SchemaFilter = "FK",
    ShowOnlyOutdated = true,
    OutdatedThresholdDays = 30
};

var statistics = await statsService.GetTableStatisticsAsync(connectionManager, filter);

// Generate RUNSTATS script
var script = statsService.GenerateRunstatsScript(statistics, withDistribution: true);

// Execute RUNSTATS for a table
await statsService.ExecuteRunstatsAsync(connectionManager, "FK", "CUSTOMERS");
```

---

## 👥 Session Monitoring

```csharp
var sessionService = new SessionMonitorService();
var filter = new SessionMonitorFilter
{
    UserFilter = "FKUSER",
    ShowOnlyActive = true
};

var sessions = await sessionService.GetActiveSessionsAsync(connectionManager, filter);

// Generate force application script
var script = sessionService.GenerateForceApplicationScript(sessions);
```

---

## 📝 DDL Generation

```csharp
var ddlService = new DdlGeneratorService();

// Generate DDL for single table
var tableDdl = await ddlService.GenerateTableDdlAsync(connectionManager, "FK", "CUSTOMERS");

// Generate DDL for entire schema
var schemaDdl = await ddlService.GenerateSchemaDdlAsync(connectionManager, "FK");
```

---

## 📡 CDC (Change Data Capture) Management

```csharp
var cdcService = new DataCaptureService();
var filter = new CdcMonitorFilter
{
    SchemaFilter = "FK",
    ShowOnlyDisabled = true
};

var cdcInfo = await cdcService.GetDataCaptureInfoAsync(connectionManager, filter);

// Generate enable CDC script
var enableScript = cdcService.GenerateEnableCdcScript(cdcInfo);

// Enable CDC for a table
await cdcService.EnableCdcAsync(connectionManager, "FK", "CUSTOMERS");
```

---

## 🗑️ Unused Object Detection

```csharp
var unusedService = new UnusedObjectDetectorService();

// Find unused tables (not accessed in 1 year)
var unusedTables = await unusedService.FindUnusedTablesAsync(connectionManager, unusedThresholdDays: 365);

// Find unused packages
var unusedPackages = await unusedService.FindUnusedPackagesAsync(connectionManager, unusedThresholdDays: 365);

// Generate DROP script
var script = unusedService.GenerateDropScript(unusedTables, includeComments: true);
```

---

## 💬 Comment Management

```csharp
var commentService = new CommentService();

// Get table comments
var tableComments = await commentService.GetTableCommentsAsync(connectionManager, schemaFilter: "FK");

// Get column comments for a table
var columnComments = await commentService.GetColumnCommentsAsync(connectionManager, "FK", "CUSTOMERS");

// Generate COMMENT ON script
var script = commentService.GenerateCommentScript(tableComments);
```

---

## 📚 Source Code Browsing

```csharp
var sourceService = new SourceCodeService();

// Get all procedures in schema
var procedures = await sourceService.GetProceduresAsync(connectionManager, "FK");

// Get all functions
var functions = await sourceService.GetFunctionsAsync(connectionManager, "FK");

// Get all views
var views = await sourceService.GetViewsAsync(connectionManager, "FK");

// Get triggers for a table
var triggers = await sourceService.GetTriggersAsync(connectionManager, "FK", "CUSTOMERS");

// Export source code to files
await sourceService.ExportSourceToFilesAsync(procedures, @"C:\Export\Procedures");
```

---

## 🔗 Dependency Analysis

```csharp
var depService = new DependencyAnalyzerService();

// Get all dependencies for a table
var dependencies = await depService.GetTableDependenciesAsync(connectionManager, "FK", "CUSTOMERS");

// Generate dependency-ordered DROP script
var script = depService.GenerateDependencyOrderedDropScript(dependencies);
```

---

## 🔄 Migration Planning

```csharp
var migrationService = new MigrationPlannerService();

// Identify migration candidates (active in last 3 years)
var candidates = await migrationService.IdentifyMigrationCandidatesAsync(
    connectionManager, 
    schema: "FK", 
    activeThresholdYears: 3);

// Generate migration plan
var plan = await migrationService.GenerateMigrationScriptAsync(connectionManager, candidates);
```

---

## 📦 Package Analysis

```csharp
var packageService = new PackageAnalyzerService();

// Get all packages in schema
var packages = await packageService.GetPackagesAsync(connectionManager, "FK");

// Get SQL statements in a package
var statements = await packageService.GetPackageStatementsAsync(connectionManager, "FK", "MYPKG");
```

---

## 🗂️ Metadata Loading

```csharp
var metadataService = new MetadataLoaderService();

// Get all schemas
var schemas = await metadataService.GetAllSchemasAsync(connectionManager);

// Get all tables in a schema
var tables = await metadataService.GetTablesAsync(connectionManager, "FK");

// Get detailed table metadata
var tableDetails = await metadataService.GetTableDetailsAsync(connectionManager, "FK", "CUSTOMERS");
```

---

## 💡 IntelliSense Completions

```csharp
var completionProvider = new SqlCompletionDataProvider(metadataLoaderService);

// Get SQL keywords
var keywords = completionProvider.GetKeywordCompletions();

// Get system functions
var functions = completionProvider.GetSystemFunctionCompletions();

// Get SYSCAT tables
var syscatTables = completionProvider.GetSyscatTableCompletions();

// Get all completions
var allCompletions = completionProvider.GetAllCompletions();

// Cache schema objects for completion
completionProvider.CacheSchemaObjects(tables);
```

---

## 📡 Metadata Collection

```csharp
var metadataService = new DB2MetadataService();

// Collect metadata for current connection
await metadataService.CollectMetadataAsync(connectionManager, profileName: "MyDB");

// Collect table-specific metadata
await metadataService.CollectTableMetadataAsync(
    connectionManager,
    tableName: "CUSTOMERS",
    schemaName: "FK",
    version: "11.5",
    profileName: "MyDB");
```

---

## 📂 Connection Profile Management

```csharp
var profileService = new ConnectionProfileService();

// Load all profiles
var profiles = profileService.LoadAllProfiles();

// Get specific profile
var profile = profileService.GetProfile("MyDB");

// Save profile
profileService.SaveProfile(newConnection);

// Delete profile
profileService.DeleteProfile("OldDB");
```

---

## 🎯 CLI Usage

```bash
# Help
DbExplorer.exe -Help

# Execute query and export
DbExplorer.exe -Profile "MyDB" -Sql "SELECT * FROM SYSCAT.TABLES" -Outfile "output.json" -Format json

# Collect metadata
DbExplorer.exe -Profile "MyDB" -CollectMetadata
```

---

## 💾 Output Formats Supported

### CLI Export Formats
- **JSON** - Default format, structured data
- **CSV** - Comma-separated values
- **TSV** - Tab-separated values
- **XML** - XML format

### Service Outputs
- **SQL Scripts** - DDL, RUNSTATS, FORCE APPLICATION, COMMENT ON, DROP, etc.
- **JSON** - Metadata files
- **CSV** - Data exports
- **Source Files** - .sql files for procedures, views, etc.

---

## 🔍 Error Handling

All services use consistent error handling:

```csharp
try
{
    Logger.Info("Starting operation");
    Logger.Debug("Parameters: {Params}", params);
    
    // Operation
    
    Logger.Info("Operation completed successfully");
}
catch (DB2Exception db2Ex)
{
    Logger.Error(db2Ex, "DB2 error - SQL State: {SqlState}", db2Ex.SqlState);
    throw;
}
catch (Exception ex)
{
    Logger.Error(ex, "Operation failed");
    throw;
}
```

**All errors are logged with full context for troubleshooting.**

---

## 📖 Usage Examples

See `FINAL_IMPLEMENTATION_REPORT.md` for comprehensive examples and testing scenarios.

---

*Quick Reference for DbExplorer Services*  
*All 17 services documented and ready for use*  
*Last Updated: November 19, 2025*

