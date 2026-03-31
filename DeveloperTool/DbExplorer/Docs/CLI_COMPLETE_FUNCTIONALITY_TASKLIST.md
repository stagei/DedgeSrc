# CLI Complete Functionality Implementation - Task List

**Goal**: Implement CLI commands for **ALL** Windows app functionality to enable comprehensive automated testing

**Status**: 50/90 commands complete (55.6%)

**Date Started**: 2025-12-13  
**Last Updated**: 2025-12-13 11:20 (Session 1)

---

## ✅ COMPLETED - Object Listing (5 commands)

- [x] `list-tables` - List all tables in schema
- [x] `list-views` - List all views in schema
- [x] `list-procedures` - List stored procedures
- [x] `list-triggers` - List triggers
- [x] `list-functions` - List functions

## ✅ COMPLETED - Basic Object Information (6 commands)

- [x] `table-props` - Basic table properties (columns, PKs, FKs, indexes)
- [x] `view-info` - View information
- [x] `procedure-info` - Stored procedure details
- [x] `function-info` - Function details
- [x] `trigger-info` - Trigger details
- [x] `trigger-usage` - Find all triggers

## ✅ COMPLETED - Basic Monitoring (5 commands)

- [x] `dependencies` - Dependency analysis
- [x] `lock-monitor` - Database locks (simplified for DB2 12.1 compatibility)
- [x] `active-sessions` - Database sessions (simplified)
- [x] `database-load` - Table load metrics
- [x] `table-stats` - Table statistics
- [x] `cdc-info` - CDC information (simplified)

## ✅ COMPLETED - TableDetailsDialog Complete (9 commands)

- [x] `table-columns` - Complete column metadata with data types, nullable, defaults
- [x] `table-foreign-keys` - Outgoing foreign keys with referenced tables
- [x] `table-indexes` - All indexes with uniqueness, types, cardinality
- [x] `table-statistics-full` - Complete table statistics (rows, pages, last RUNSTATS)
- [x] `table-ddl` - Generate CREATE TABLE DDL
- [x] `table-incoming-fks` - Tables that reference this table
- [x] `table-referencing-packages` - Packages that use this table
- [x] `table-referencing-views` - Views that depend on this table
- [x] `table-referencing-routines` - Procedures/Functions using this table

## ✅ COMPLETED - Source Code Browser (3 commands)

- [x] `list-all-source` - List all source code objects (procedures, functions, views, triggers)
- [x] `source-code-full` - Get complete source code for any object
- [x] `source-search` - Search in source code across schema

## ✅ COMPLETED - Package Analyzer (3 commands)

- [x] `list-packages` - List all packages in schema
- [x] `package-analysis` - Analyze package dependencies
- [x] `package-details` - Detailed package information

## ✅ COMPLETED - Comment Manager (3 commands)

- [x] `list-comments` - List objects with/without comments
- [x] `object-comment` - Get comment for specific object
- [x] `missing-comments` - Find objects without comments

## ✅ COMPLETED - Statistics Manager (3 commands)

- [x] `statistics-overview` - Statistics overview for schema (never/stale/current)
- [x] `statistics-recommendations` - Recommend tables needing RUNSTATS
- [x] `index-statistics` - Detailed index statistics with cardinality, cluster ratio

## ✅ COMPLETED - Unused Objects (4 commands)

- [x] `unused-tables` - Find tables with no dependencies
- [x] `unused-indexes` - Find non-PK indexes (review for usage)
- [x] `unused-views` - Find views not referenced
- [x] `unused-routines` - Find routines not called

## ✅ COMPLETED - Mermaid ERD (5 commands) ⚠️ Complex

- [x] `mermaid-erd` - Generate Mermaid ERD from DB2 tables (uses SqlMermaidErdTools)
- [x] `mermaid-from-sql` - Convert SQL DDL to Mermaid
- [x] `sql-from-mermaid` - Convert Mermaid to SQL DDL
- [x] `mermaid-diff` - Generate ALTER DDL from Mermaid differences (**⚠️ OUTPUT ONLY - DO NOT EXECUTE!**)
- [x] `sql-translate` - Translate SQL between database dialects (DB2 → PostgreSQL/MySQL/Oracle/SQL Server)

## ✅ COMPLETED - Metadata & Connections (4 commands)

- [x] `query-history` - Query execution history (CLI mode: session-based, not available)
- [x] `schema-metadata` - Complete schema metadata (object counts, sizes)
- [x] `database-metadata` - Complete database metadata (DB name, user, schema/table counts)
- [x] `connection-profiles` - List all saved connection profiles

---


---

## 🔲 TODO - ObjectDetailsDialog (Package Details)

**Dialog**: `Dialogs/ObjectDetailsDialog.xaml`  
**Service**: `PackageAnalyzerService`

- [ ] `package-details` - Complete package information
  - Package schema/name
  - Package type
  - Valid status
  - Create time
  - Dependencies
  - Test: NULLID packages

---

## 🔲 TODO - UserDetailsDialog (User Information)

**Dialog**: `Dialogs/UserDetailsDialog.xaml`  
**Service**: `AccessControlService`

- [ ] `user-info` - Complete user information
  - Username, auth ID
  - Granted privileges
  - Schema access
  - Object permissions
  - Test: Current user (FKGEISTA)

- [ ] `user-privileges` - User privilege details
  - Database authorities
  - Schema authorities
  - Table/view/routine permissions
  - Test: Current user

---

## 🔲 TODO - SourceCodeBrowserPanel Commands

**Panel**: `Controls/SourceCodeBrowserPanel.xaml`  
**Service**: `SourceCodeService`

- [ ] `list-all-source` - List all source code objects
  - Procedures, functions, triggers with source
  - Filter by schema
  - Test: SQLJ, SYSPROC schemas

- [ ] `source-code-full` - Get complete source code
  - Full SQL source
  - Object type
  - Created/modified timestamps
  - Test: SQLJ.DB2_INSTALL_JAR

- [ ] `source-search` - Search in source code
  - Search text pattern
  - Filter by object type
  - Return matching objects with line numbers
  - Test: Search for "INSERT" or "UPDATE"

---

## 🔲 TODO - PackageAnalyzerPanel Commands

**Panel**: `Controls/PackageAnalyzerPanel.xaml`  
**Service**: `PackageAnalyzerService`

- [ ] `list-packages` - List all packages
  - Package schema/name
  - Valid status
  - Created time
  - Test: NULLID schema

- [ ] `package-analysis` - Analyze package dependencies
  - Package dependencies
  - Referenced objects
  - Used by routines
  - Test: Specific package

- [ ] `package-invalidation-impact` - Find impact of package changes
  - Dependent packages
  - Affected routines
  - Invalidation cascade
  - Test: Package with dependencies

---

## 🔲 TODO - CommentManagerPanel Commands

**Panel**: `Controls/CommentManagerPanel.xaml`  
**Service**: `CommentService`

- [ ] `list-comments` - List objects with comments
  - Schema filter
  - Object type filter
  - Show objects with/without comments
  - Test: All schemas

- [ ] `object-comment` - Get comment for specific object
  - Object schema/name/type
  - Comment text
  - Test: Tables with remarks

- [ ] `missing-comments` - Find objects without comments
  - Schema filter
  - Object types
  - Return uncommented objects
  - Test: INL schema

---

## 🔲 TODO - StatisticsManagerPanel Commands

**Panel**: `Controls/StatisticsManagerPanel.xaml`  
**Service**: `StatisticsService`

- [ ] `statistics-overview` - Statistics overview for schema
  - All tables with stats
  - Last RUNSTATS time
  - Stale statistics indicators
  - Test: ASK schema

- [ ] `statistics-recommendations` - Recommend RUNSTATS targets
  - Tables needing RUNSTATS
  - Priority ranking
  - Stale threshold
  - Test: All schemas

- [ ] `index-statistics` - Index statistics details
  - Index cardinality
  - Cluster ratio
  - Page counts
  - Test: Indexes on ASK.VASK_KUNDER

---

## 🔲 TODO - UnusedObjectsPanel Commands

**Panel**: `Controls/UnusedObjectsPanel.xaml`  
**Service**: `UnusedObjectDetectorService`

- [ ] `unused-tables` - Find unused tables
  - Tables with no dependencies
  - No referencing views/routines
  - Zero/low activity
  - Test: All schemas

- [ ] `unused-indexes` - Find unused indexes
  - Indexes never used
  - Duplicate indexes
  - Redundant indexes
  - Test: All schemas

- [ ] `unused-views` - Find unused views
  - Views not referenced
  - Invalid views
  - Test: All schemas

- [ ] `unused-routines` - Find unused procedures/functions
  - Not called by other routines
  - Not used in packages
  - Test: All schemas

---

## 🔲 TODO - DatabaseLoadMonitorPanel Commands

**Panel**: `Controls/DatabaseLoadMonitorPanel.xaml`  
**Service**: `DatabaseLoadMonitorService`

- [ ] `database-load-full` - Complete database load metrics
  - Rows read/inserted/updated/deleted per table
  - Lock wait time
  - Sort overflow
  - Buffer pool hit ratio
  - Test: Real-time data

- [ ] `table-activity` - Table activity metrics
  - Read/write operations
  - Lock contention
  - Time metrics
  - Test: High-activity tables

- [ ] `top-active-tables` - Top N most active tables
  - Sort by activity type
  - Limit to N tables
  - Test: Top 10

---

## 🔲 TODO - LockMonitorPanel Commands (Enhanced)

**Panel**: `Controls/LockMonitorPanel.xaml`  
**Service**: `LockMonitorService`

- [ ] `lock-monitor-full` - Complete lock information
  - Agent IDs
  - Lock types (table, row, etc.)
  - Lock modes (S, X, IX, etc.)
  - Lock status (Held, Waiting)
  - Blocking/blocked sessions
  - Test: Real-time locks

- [ ] `lock-chains` - Identify lock wait chains
  - Blocker → Waiter relationships
  - Chain depth
  - Blocking time
  - Test: During contention

- [ ] `deadlock-history` - Recent deadlock information
  - Deadlock events
  - Participating sessions
  - Objects involved
  - Test: Deadlock logs

---

## 🔲 TODO - ActiveSessionsPanel Commands (Enhanced)

**Panel**: `Controls/ActiveSessionsPanel.xaml`  
**Service**: `SessionMonitorService`

- [ ] `active-sessions-full` - Complete session information
  - Application names
  - Auth IDs
  - Client hostnames/IPs
  - Execution IDs
  - Current SQL statements
  - Connection times
  - Test: Real-time sessions

- [ ] `session-details` - Detailed session information
  - Session by ID
  - Current statement
  - Lock information
  - Resource usage
  - Test: Specific session

- [ ] `long-running-sessions` - Sessions running > N seconds
  - Duration threshold
  - Current operations
  - Resource consumption
  - Test: Long queries

---

## 🔲 TODO - CdcManagerPanel Commands (Enhanced)

**Panel**: `Controls/CdcManagerPanel.xaml`  
**Service**: `DataCaptureService`

- [ ] `cdc-status-full` - Complete CDC status
  - Tables with CDC enabled
  - CDC column details
  - Change table names
  - Subscription info
  - Test: CDC-enabled tables

- [ ] `cdc-configuration` - CDC configuration details
  - Capture control tables
  - Replication groups
  - Subscription sets
  - Test: CDC setup

- [ ] `cdc-changes` - Recent CDC changes
  - Change table data
  - Operation types (I/U/D)
  - Timestamps
  - Test: Active CDC tables

---

## 🔲 TODO - DependencyGraphPanel Commands

**Panel**: `Controls/DependencyGraphPanel.xaml`  
**Service**: `DependencyAnalyzerService`

- [ ] `dependency-graph` - Complete dependency graph
  - Object and all dependencies (recursive)
  - Dependency types
  - Dependency levels
  - Circular dependency detection
  - Test: Complex view (DBE.JOBJECT_VIEW)

- [ ] `dependency-impact` - Impact analysis for object changes
  - What breaks if object changes
  - Affected objects list
  - Impact severity
  - Test: Core tables

- [ ] `dependency-chain` - Dependency chain from A to B
  - Path from source to target
  - Intermediate objects
  - Dependency types
  - Test: Table → View → Procedure

---

## 🔲 TODO - MigrationAssistantPanel Commands

**Panel**: `Controls/MigrationAssistantPanel.xaml`  
**Service**: `MigrationPlannerService`

- [ ] `migration-plan` - Generate migration plan
  - Source/target schemas
  - Object ordering (tables → views → routines)
  - Dependency resolution
  - Test: Schema to schema

- [ ] `migration-ddl` - Generate migration DDL
  - CREATE statements
  - Dependency-ordered
  - WITH GRANTS
  - Test: Complete schema

- [ ] `migration-data-script` - Generate data migration scripts
  - INSERT statements
  - Bulk load scripts
  - Referential integrity handling
  - Test: Small tables

---

## 🔲 TODO - Query History & Metadata

**Service**: `QueryHistoryService`, `DB2MetadataService`

- [ ] `query-history` - Query execution history
  - Recent queries
  - Execution times
  - Result counts
  - Test: Session history

- [ ] `schema-metadata` - Complete schema metadata
  - All objects in schema
  - Object counts by type
  - Schema size
  - Test: ASK, INL, DBM schemas

- [ ] `database-metadata` - Complete database metadata
  - Database name, version
  - Codepage, territory
  - Tablespace info
  - Configuration parameters
  - Test: FKKTOTST database

---

## 🔲 TODO - Connection & Configuration

**Services**: `ConnectionProfileService`, `ConnectionStatisticsService`

- [ ] `connection-profiles` - List all saved connection profiles
  - Profile names
  - Server/port/database
  - Last used times
  - Test: Local profiles

- [ ] `connection-stats` - Connection statistics
  - Profile usage counts
  - Average connection times
  - Success/failure rates
  - Test: Historical data

- [ ] `connection-test` - Test connection profile
  - Profile name
  - Test connectivity
  - Return latency
  - Test: All profiles

---

## 🔲 TODO - Export Functionality

**Service**: `ExportService`

- [ ] `export-table-data` - Export table data
  - Format: CSV, TSV, JSON, XML
  - Row limits
  - Column selection
  - Test: ASK.VASK_KUNDER

- [ ] `export-query-results` - Export query results
  - Custom SQL query
  - Format selection
  - Test: Complex queries

- [ ] `export-schema-ddl` - Export complete schema DDL
  - All objects in schema
  - Dependency-ordered
  - Test: Small schema

---

## 🔲 TODO - SQL Safety & Formatting

**Services**: `SqlSafetyValidatorService`, `SqlFormatterService`

- [ ] `sql-validate` - Validate SQL safety
  - Check for dangerous operations
  - Detect missing WHERE clauses
  - Identify mass deletes/updates
  - Test: Various SQL statements

- [ ] `sql-format` - Format SQL statement
  - Apply formatting rules
  - Keyword casing
  - Indentation
  - Test: Unformatted SQL

---

## 🔲 TODO - Schema Comparison & Diff

**Services**: `SchemaDiffAnalyzerService`, `DiffBasedDdlGeneratorService`

- [ ] `schema-compare` - Compare two schemas
  - Source/target schemas
  - Object differences
  - Missing/extra objects
  - Test: ASK vs INL structure

- [ ] `schema-diff-ddl` - Generate diff DDL
  - ALTER statements
  - ADD/DROP/MODIFY
  - Dependency-aware
  - Test: Schema evolution

---

## 🔲 TODO - Mermaid Diagram Generation (SqlMermaidErdTools Package)

**Services**: `MermaidDiagramGeneratorService`, `SqlMermaidIntegrationService`  
**Package**: `SqlMermaidErdTools` v0.2.8  
**⚠️ CRITICAL**: DO NOT execute DML statements from diff generation!

- [ ] `mermaid-erd` - Generate Mermaid ERD diagram from DB2 tables
  - Tables and relationships
  - Mermaid syntax
  - Uses: `SqlMermaidIntegrationService.GenerateMermaidFromDb2TablesAsync()`
  - Test: Related tables (ASK schema)

- [ ] `mermaid-from-sql` - Convert SQL DDL to Mermaid
  - Parse CREATE TABLE statements
  - Generate ERD diagram
  - Uses: `SqlMermaidIntegrationService.ConvertSqlToMermaidAsync()`
  - Test: Sample DDL

- [ ] `sql-from-mermaid` - Convert Mermaid to SQL DDL
  - Parse Mermaid ERD
  - Generate CREATE statements
  - Uses: `SqlMermaidIntegrationService.ConvertMermaidToSqlAsync()`
  - Test: Sample Mermaid

- [ ] `mermaid-diff` - Generate ALTER DDL from Mermaid differences
  - Compare original Mermaid with modified Mermaid
  - Generate ALTER/ADD/DROP statements
  - Uses: `SqlMermaidIntegrationService.GenerateMigrationFromMermaidDiffAsync()`
  - **⚠️ OUTPUT ONLY - DO NOT EXECUTE!**
  - Test: Modified Mermaid schema

- [ ] `sql-translate-dialect` - Translate SQL between database dialects
  - DB2 → PostgreSQL, SQL Server, Oracle, MySQL
  - Uses: `SqlMermaidIntegrationService.TranslateSqlDialectAsync()`
  - Test: DB2 DDL to PostgreSQL

---

## Summary

**Total Commands to Implement**: ~85

**Progress**:
- ✅ Completed: 16 (19%)
- 🔲 TODO: 69 (81%)

**Categories**:
1. ✅ Basic Listing: 5/5 (100%)
2. ✅ Basic Object Info: 6/6 (100%)
3. ✅ Basic Monitoring: 5/5 (100%)
4. 🔲 TableDetailsDialog: 0/9 (0%)
5. 🔲 Advanced Object Info: 0/4 (0%)
6. 🔲 Source Code: 0/3 (0%)
7. 🔲 Package Analysis: 0/3 (0%)
8. 🔲 Comments: 0/3 (0%)
9. 🔲 Statistics: 0/3 (0%)
10. 🔲 Unused Objects: 0/4 (0%)
11. 🔲 Advanced Monitoring: 0/8 (0%)
12. 🔲 CDC: 0/3 (0%)
13. 🔲 Dependencies: 0/3 (0%)
14. 🔲 Migration: 0/3 (0%)
15. 🔲 Metadata: 0/3 (0%)
16. 🔲 Connection: 0/3 (0%)
17. 🔲 Export: 0/3 (0%)
18. 🔲 SQL Tools: 0/2 (0%)
19. 🔲 Schema Diff: 0/2 (0%)
20. 🔲 Mermaid: 0/3 (0%)

---

## Implementation Strategy

**For EACH command:**
1. Read corresponding service/dialog code
2. Identify SQL queries and data transformations
3. Implement CLI command in `CliCommandHandlerService`
4. Add argument parsing in `CliArgumentParser`
5. Update help text in `CliExecutorService`
6. Build project (`dotnet build`)
7. Test command with real data
8. Fix errors (up to 5 retries per command)
9. Verify JSON output structure
10. Move to next command

**Build/Test Cycle**: After EVERY command implementation

**Error Handling**: 5-retry rule for each failing command

**Completion**: Only when all 85 commands working or 5 retries exhausted

