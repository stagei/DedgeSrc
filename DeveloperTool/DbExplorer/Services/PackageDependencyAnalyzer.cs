using NLog;
using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using DbExplorer.Data;

namespace DbExplorer.Services;

/// <summary>
/// Analyzes package dependencies by parsing SQL statements.
/// Uses IConnectionManager factory methods for database-agnostic operation.
/// </summary>
public class PackageDependencyAnalyzer
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly MetadataHandler? _metadataHandler;
    
    public PackageDependencyAnalyzer(MetadataHandler? metadataHandler = null)
    {
        _metadataHandler = metadataHandler ?? App.MetadataHandler;
    }
    
    /// <summary>
    /// Analyze dependencies for a specific package.
    /// </summary>
    public async Task<PackageDependencies> AnalyzeDependenciesAsync(
        IConnectionManager connection,
        string schema,
        string packageName)
    {
        Logger.Debug("Analyzing dependencies for package: {Schema}.{Package}", schema, packageName);
        
        var dependencies = new PackageDependencies
        {
            PackageSchema = schema,
            PackageName = packageName
        };
        
        try
        {
            // Fetch all SQL statements from SYSCAT.STATEMENTS
            var statements = await FetchPackageStatementsAsync(connection, schema, packageName);
            Logger.Debug("Fetched {Count} statements for analysis", statements.Count);
            
            // Parse each statement to extract dependencies
            foreach (var stmt in statements)
            {
                try
                {
                    AnalyzeStatement(stmt, dependencies);
                }
                catch (Exception ex)
                {
                    Logger.Warn(ex, "Failed to analyze statement: {StmtNo}", stmt.StmtNo);
                }
            }
            
            // Verify objects exist in database
            await VerifyDependenciesAsync(connection, dependencies);
            
            Logger.Info("Package {Schema}.{Package} has {TableCount} tables, {ViewCount} views, " +
                       "{ProcCount} procedures, {FuncCount} functions used",
                       schema, packageName,
                       dependencies.TablesUsed.Count, dependencies.ViewsUsed.Count,
                       dependencies.ProceduresCalled.Count, dependencies.FunctionsCalled.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to analyze package dependencies");
        }
        
        return dependencies;
    }
    
    /// <summary>
    /// Fetch all SQL statements for a package from SYSCAT.STATEMENTS.
    /// </summary>
    private async Task<List<PackageStatement>> FetchPackageStatementsAsync(
        IConnectionManager connection,
        string schema,
        string packageName)
    {
        var statements = new List<PackageStatement>();
        
        var sql = _metadataHandler?.GetStatement("PACKAGE_GetStatements") 
            ?? @"SELECT STMTNO, TEXT
            FROM SYSCAT.STATEMENTS
            WHERE PKGSCHEMA = ? AND PKGNAME = ?
            ORDER BY STMTNO";
        
        using var command = connection.CreateCommand(sql);
        command.Parameters.Add(connection.CreateParameter("@schema", schema));
        command.Parameters.Add(connection.CreateParameter("@name", packageName));
        
        using var adapter = connection.CreateDataAdapter(command);
        var dataTable = new DataTable();
        await Task.Run(() => adapter.Fill(dataTable));
        
        foreach (DataRow row in dataTable.Rows)
        {
            statements.Add(new PackageStatement
            {
                StmtNo = Convert.ToInt32(row["STMTNO"]),
                Text = row["TEXT"].ToString()?.Trim() ?? string.Empty
            });
        }
        
        return statements;
    }
    
    /// <summary>
    /// Analyze a single SQL statement to extract object references.
    /// </summary>
    private void AnalyzeStatement(PackageStatement stmt, PackageDependencies dependencies)
    {
        var sql = stmt.Text.ToUpperInvariant();
        
        // Extract table references from FROM, JOIN, UPDATE, INSERT, DELETE
        ExtractTableReferences(sql, stmt.StmtNo, dependencies);
        
        // Extract procedure calls from CALL statements
        ExtractProcedureCalls(sql, stmt.StmtNo, dependencies);
        
        // Extract function calls
        ExtractFunctionCalls(sql, stmt.StmtNo, dependencies);
    }
    
    /// <summary>
    /// Extract table/view references from SQL.
    /// </summary>
    private void ExtractTableReferences(string sql, int stmtNo, PackageDependencies dependencies)
    {
        // Patterns for table references:
        // FROM schema.table, FROM table
        // JOIN schema.table, JOIN table
        // UPDATE schema.table, UPDATE table
        // INSERT INTO schema.table, INSERT INTO table
        // DELETE FROM schema.table, DELETE FROM table
        
        var patterns = new[]
        {
            @"FROM\s+([A-Z0-9_]+)\.([A-Z0-9_]+)",       // FROM schema.table
            @"FROM\s+([A-Z0-9_]+)",                     // FROM table (no schema)
            @"JOIN\s+([A-Z0-9_]+)\.([A-Z0-9_]+)",       // JOIN schema.table
            @"JOIN\s+([A-Z0-9_]+)",                     // JOIN table
            @"UPDATE\s+([A-Z0-9_]+)\.([A-Z0-9_]+)",     // UPDATE schema.table
            @"UPDATE\s+([A-Z0-9_]+)",                   // UPDATE table
            @"INSERT\s+INTO\s+([A-Z0-9_]+)\.([A-Z0-9_]+)", // INSERT INTO schema.table
            @"INSERT\s+INTO\s+([A-Z0-9_]+)",            // INSERT INTO table
            @"DELETE\s+FROM\s+([A-Z0-9_]+)\.([A-Z0-9_]+)", // DELETE FROM schema.table
            @"DELETE\s+FROM\s+([A-Z0-9_]+)"             // DELETE FROM table
        };
        
        foreach (var pattern in patterns)
        {
            var matches = Regex.Matches(sql, pattern);
            foreach (Match match in matches)
            {
                string schema, tableName;
                
                if (match.Groups.Count == 3) // schema.table
                {
                    schema = match.Groups[1].Value;
                    tableName = match.Groups[2].Value;
                }
                else // table only (assume same schema as package)
                {
                    schema = dependencies.PackageSchema;
                    tableName = match.Groups[1].Value;
                }
                
                var fullName = $"{schema}.{tableName}";
                
                // Add to list if not already present
                var existingDep = dependencies.TablesUsed.FirstOrDefault(t => 
                    t.FullName.Equals(fullName, StringComparison.OrdinalIgnoreCase));
                
                if (existingDep == null)
                {
                    dependencies.TablesUsed.Add(new ObjectDependency
                    {
                        Schema = schema,
                        Name = tableName,
                        FullName = fullName,
                        UsageCount = 1,
                        StatementsUsedIn = new List<int> { stmtNo }
                    });
                }
                else
                {
                    existingDep.UsageCount++;
                    existingDep.StatementsUsedIn.Add(stmtNo);
                }
            }
        }
    }
    
    /// <summary>
    /// Extract procedure calls from CALL statements.
    /// </summary>
    private void ExtractProcedureCalls(string sql, int stmtNo, PackageDependencies dependencies)
    {
        // Pattern: CALL schema.procedure(...)
        var patterns = new[]
        {
            @"CALL\s+([A-Z0-9_]+)\.([A-Z0-9_]+)",  // CALL schema.proc
            @"CALL\s+([A-Z0-9_]+)"                 // CALL proc
        };
        
        foreach (var pattern in patterns)
        {
            var matches = Regex.Matches(sql, pattern);
            foreach (Match match in matches)
            {
                string schema, procName;
                
                if (match.Groups.Count == 3)
                {
                    schema = match.Groups[1].Value;
                    procName = match.Groups[2].Value;
                }
                else
                {
                    schema = dependencies.PackageSchema;
                    procName = match.Groups[1].Value;
                }
                
                var fullName = $"{schema}.{procName}";
                
                var existingDep = dependencies.ProceduresCalled.FirstOrDefault(p => 
                    p.FullName.Equals(fullName, StringComparison.OrdinalIgnoreCase));
                
                if (existingDep == null)
                {
                    dependencies.ProceduresCalled.Add(new ObjectDependency
                    {
                        Schema = schema,
                        Name = procName,
                        FullName = fullName,
                        UsageCount = 1,
                        StatementsUsedIn = new List<int> { stmtNo }
                    });
                }
                else
                {
                    existingDep.UsageCount++;
                    existingDep.StatementsUsedIn.Add(stmtNo);
                }
            }
        }
    }
    
    /// <summary>
    /// Extract function calls (simple pattern matching).
    /// </summary>
    private void ExtractFunctionCalls(string sql, int stmtNo, PackageDependencies dependencies)
    {
        // Pattern: schema.function(...) or function(...)
        // This is a simplified version - real implementation would need more sophisticated parsing
        var patterns = new[]
        {
            @"([A-Z0-9_]+)\.([A-Z0-9_]+)\s*\(",  // schema.func(
        };
        
        foreach (var pattern in patterns)
        {
            var matches = Regex.Matches(sql, pattern);
            foreach (Match match in matches)
            {
                if (match.Groups.Count == 3)
                {
                    var schema = match.Groups[1].Value;
                    var funcName = match.Groups[2].Value;
                    
                    // Skip system schemas and keywords
                    if (IsSystemSchema(schema) || IsKeyword(funcName))
                        continue;
                    
                    var fullName = $"{schema}.{funcName}";
                    
                    var existingDep = dependencies.FunctionsCalled.FirstOrDefault(f => 
                        f.FullName.Equals(fullName, StringComparison.OrdinalIgnoreCase));
                    
                    if (existingDep == null)
                    {
                        dependencies.FunctionsCalled.Add(new ObjectDependency
                        {
                            Schema = schema,
                            Name = funcName,
                            FullName = fullName,
                            UsageCount = 1,
                            StatementsUsedIn = new List<int> { stmtNo }
                        });
                    }
                    else
                    {
                        existingDep.UsageCount++;
                        existingDep.StatementsUsedIn.Add(stmtNo);
                    }
                }
            }
        }
    }
    
    /// <summary>
    /// Verify that extracted dependencies actually exist in the database.
    /// </summary>
    private async Task VerifyDependenciesAsync(IConnectionManager connection, PackageDependencies dependencies)
    {
        Logger.Debug("Verifying extracted dependencies");
        
        // Verify tables/views exist
        await VerifyObjectsAsync(connection, dependencies.TablesUsed, "SYSCAT.TABLES", "TABSCHEMA", "TABNAME");
        
        // Verify procedures exist
        await VerifyObjectsAsync(connection, dependencies.ProceduresCalled, "SYSCAT.ROUTINES", "ROUTINESCHEMA", "ROUTINENAME");
        
        // Verify functions exist
        await VerifyObjectsAsync(connection, dependencies.FunctionsCalled, "SYSCAT.ROUTINES", "ROUTINESCHEMA", "ROUTINENAME");
    }
    
    /// <summary>
    /// Verify objects exist in system catalog.
    /// </summary>
    private async Task<HashSet<string>> VerifyObjectsAsync(
        IConnectionManager connection,
        List<ObjectDependency> dependencies,
        string catalogTable,
        string schemaColumn,
        string nameColumn)
    {
        var verified = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        
        if (dependencies.Count == 0)
            return verified;
        
        // Build IN clause for all objects
        var objectNames = string.Join(", ", dependencies.Select(d => $"'{d.Name}'"));
        
        var sql = $@"
            SELECT {schemaColumn}, {nameColumn}
            FROM {catalogTable}
            WHERE {nameColumn} IN ({objectNames})
        ";
        
        try
        {
            using var command = connection.CreateCommand(sql);
            using var adapter = connection.CreateDataAdapter(command);
            var dataTable = new DataTable();
            await Task.Run(() => adapter.Fill(dataTable));
            
            foreach (DataRow row in dataTable.Rows)
            {
                var schema = row[schemaColumn].ToString()?.Trim() ?? string.Empty;
                var name = row[nameColumn].ToString()?.Trim() ?? string.Empty;
                var fullName = $"{schema}.{name}";
                verified.Add(fullName);
            }
            
            // Mark dependencies as verified or not
            foreach (var dep in dependencies)
            {
                dep.Verified = verified.Contains(dep.FullName);
            }
            
            Logger.Debug("Verified {Count}/{Total} objects in {Table}",
                        verified.Count, dependencies.Count, catalogTable);
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "Failed to verify objects in {Table}", catalogTable);
        }
        
        return verified;
    }
    
    /// <summary>
    /// Check if a schema is a system schema (to filter out system objects).
    /// </summary>
    private bool IsSystemSchema(string schema)
    {
        var systemSchemas = new[] { "SYSCAT", "SYSIBM", "SYSIBMADM", "SYSPROC", "SYSSTAT", "SYSTOOLS" };
        return systemSchemas.Contains(schema, StringComparer.OrdinalIgnoreCase);
    }
    
    /// <summary>
    /// Check if a word is a SQL keyword (to avoid false positives).
    /// </summary>
    private bool IsKeyword(string word)
    {
        var keywords = new[] { "SELECT", "FROM", "WHERE", "JOIN", "INSERT", "UPDATE", "DELETE", "CREATE", "ALTER", "DROP" };
        return keywords.Contains(word, StringComparer.OrdinalIgnoreCase);
    }
}

/// <summary>
/// Package dependencies data structure.
/// </summary>
public class PackageDependencies
{
    public string PackageSchema { get; set; } = string.Empty;
    public string PackageName { get; set; } = string.Empty;
    public List<ObjectDependency> TablesUsed { get; set; } = new();
    public List<ObjectDependency> ViewsUsed { get; set; } = new();
    public List<ObjectDependency> ProceduresCalled { get; set; } = new();
    public List<ObjectDependency> FunctionsCalled { get; set; } = new();
}

/// <summary>
/// Object dependency information.
/// </summary>
public class ObjectDependency
{
    public string Schema { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public int UsageCount { get; set; }
    public List<int> StatementsUsedIn { get; set; } = new();
    public bool Verified { get; set; }
}

/// <summary>
/// Package SQL statement.
/// </summary>
public class PackageStatement
{
    public int StmtNo { get; set; }
    public string Text { get; set; } = string.Empty;
}

