# Phase 2: DbConnectionManager (Provider-Agnostic Execution) - Task List

**Goal:** Create provider-agnostic database execution layer  
**Estimated Duration:** 2 weeks  
**Priority:** 🔴 CRITICAL

---

## Status Summary
- **Total Tasks:** 20
- **Completed:** 0
- **In Progress:** 0
- **Pending:** 20

---

## Tasks

### Week 3: DbConnectionManager Implementation

#### 2.1 Create DbConnectionInfo Model
- [ ] Create `Models/DbConnectionInfo.cs`
- [ ] Add properties: Name, Server, Port, Database, Username, Password
- [ ] Add ConnectionTimeout, IsReadOnly, AutoCommit properties
- [ ] Implement GetConnectionString(Provider provider) method
- [ ] Add XML documentation
- [ ] Add validation logic

#### 2.2 Create DbConnectionManager Class
- [ ] Create `Data/DbConnectionManager.cs`
- [ ] Add NLog logger
- [ ] Add fields: _connection (DbConnection), _provider, _version, _metadataHandler
- [ ] Implement constructor(Provider, version, DbConnectionInfo, MetadataHandler)
- [ ] Implement CreateConnection(Provider, DbConnectionInfo) with switch statement
  - [ ] Case "DB2": return new DB2Connection
  - [ ] Case "POSTGRESQL": return new NpgsqlConnection (stub for now)
  - [ ] Case "SQLSERVER": return new SqlConnection (stub for now)
  - [ ] Default: throw NotSupportedException
- [ ] Implement OpenAsync()
- [ ] Implement Close()
- [ ] Implement Dispose()
- [ ] Add comprehensive DEBUG logging
- [ ] Add connection state tracking

#### 2.3 Implement Query Execution
- [ ] Implement ExecuteQueryAsync(statementKey, params)
  - [ ] Get SQL from MetadataHandler.GetQuery()
  - [ ] Log SQL (first 100 chars)
  - [ ] Call ExecuteSqlAsync()
- [ ] Implement ExecuteSqlAsync(sql, params)
  - [ ] Create command from _connection
  - [ ] Add parameters with provider-specific naming
  - [ ] Create provider-specific data adapter
  - [ ] Fill DataTable
  - [ ] Return DataTable
  - [ ] Log row count
- [ ] Implement CreateDataAdapter(DbCommand) with switch statement
  - [ ] Case "DB2": return new DB2DataAdapter
  - [ ] Case "POSTGRESQL": stub
  - [ ] Case "SQLSERVER": stub
- [ ] Add timeout handling (30 seconds default)
- [ ] Add cancellation token support

#### 2.4 Implement Non-Query Execution
- [ ] Implement ExecuteNonQueryAsync(statementKey, params)
- [ ] Implement ExecuteScalarAsync(statementKey, params)
- [ ] Add transaction support (BeginTransaction, Commit, Rollback)
- [ ] Add comprehensive error handling
- [ ] Log all DB2Exception with SqlState and ErrorCode

#### 2.5 Testing with Existing Code
- [ ] Keep old DB2ConnectionManager temporarily
- [ ] Create test connection using DbConnectionManager
- [ ] Test OpenAsync() with ILOGTST profile
- [ ] Test ExecuteQueryAsync("GetSchemasStatement")
- [ ] Test ExecuteQueryAsync("GetTablesForSchema", "TV")
- [ ] Test ExecuteQueryAsync("GetViewsForSchema", "TV")
- [ ] Compare results with old DB2ConnectionManager
- [ ] Verify CLI execution still works
- [ ] Test build succeeds

### Week 4: Service Integration

#### 2.6 Update ObjectBrowserService
- [ ] Inject MetadataHandler into constructor
- [ ] Replace all hardcoded SQL with ExecuteQueryAsync(statementKey)
- [ ] Update LoadSchemas() to use "GetSchemasStatement"
- [ ] Update LoadTables() to use "GetTablesForSchema"
- [ ] Update LoadViews() to use "GetViewsForSchema"
- [ ] Update LoadFunctions() to use "GetFunctionsForSchema"
- [ ] Update LoadProcedures() to use "GetProceduresForSchema"
- [ ] Update LoadPackages() to use "GetPackagesForSchema"
- [ ] Update LoadIndexes() to use "GetIndexesForSchema"
- [ ] Update LoadTriggers() to use "GetTriggersForSchema"
- [ ] Update LoadSequences() to use "GetSequencesForSchema"
- [ ] Update LoadUDTs() to use "GetUDTsForSchema"
- [ ] Remove all hardcoded SQL strings
- [ ] Test each method after update
- [ ] Verify CLI execution works

#### 2.7 Update Property Dialogs
- [ ] Update TablePropertiesDialog to use DbConnectionManager
- [ ] Update ViewPropertiesDialog to use DbConnectionManager
- [ ] Update PackageDetailsDialog to use DbConnectionManager
- [ ] Update FunctionDetailsDialog to use DbConnectionManager
- [ ] Update ProcedureDetailsDialog to use DbConnectionManager
- [ ] Replace all hardcoded SQL with statement keys
- [ ] Test each dialog opens and displays data correctly

#### 2.8 Update Connection Management
- [ ] Update ConnectionTabControl to use DbConnectionManager
- [ ] Update connection profile loading
- [ ] Update query execution in editor
- [ ] Test F5 execution
- [ ] Test Ctrl+Enter execution
- [ ] Verify results display correctly

#### 2.9 Final Testing
- [ ] Run full test suite with ILOGTST profile
- [ ] Test all object browser categories
- [ ] Test all property dialogs
- [ ] Test query execution in editor
- [ ] Verify no hardcoded SQL remains (grep for "SELECT.*FROM")
- [ ] Test build succeeds
- [ ] Test application runs without errors

---

**Status:** ⏳ NOT STARTED  
**Next Milestone:** All services use DbConnectionManager with zero hardcoded SQL  
**Blockers:** Phase 1 must be complete

---

**Last Updated:** 2025-11-20

