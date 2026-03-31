using NLog;
using System;
using System.Collections.Generic;
using System.Data.Common;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using DbExplorer.Data;
using DbExplorer.Models;
using ICSharpCode.AvalonEdit.CodeCompletion;

namespace DbExplorer.Services;

/// <summary>
/// Database-agnostic SQL IntelliSense provider.
/// Loads keywords, functions, and data types from provider-specific JSON files.
/// </summary>
public class SqlIntelliSenseProvider : IIntelliSenseProvider
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly IntelliSenseDataLoader _dataLoader = new();
    
    // Current provider metadata
    private IntelliSenseMetadata? _metadata;
    private string _currentProvider = "DB2";
    private string _currentVersion = "12.1";
    
    // Cached lists from metadata
    private List<string> _keywords = new();
    private List<string> _dataTypes = new();
    private List<string> _functions = new();
    private List<string> _systemTables = new();
    private Dictionary<string, SnippetDefinition> _snippets = new();
    
    // Live schema metadata (loaded from database)
    private Dictionary<string, List<ColumnInfo>> _tableColumns = new();
    private List<string> _tableNames = new();
    private List<string> _viewNames = new();
    private List<string> _procedureNames = new();
    private List<string> _functionNames = new();
    private List<string> _schemaNames = new();
    
    // Table reference with alias information parsed from query
    private class TableReference
    {
        public string FullName { get; set; } = string.Empty;  // SCHEMA.TABLE
        public string SchemaName { get; set; } = string.Empty;
        public string TableName { get; set; } = string.Empty;
        public string? Alias { get; set; }  // null if no alias
        
        /// <summary>
        /// Gets the identifier to use (alias if present, otherwise table name)
        /// </summary>
        public string Identifier => Alias ?? TableName;
    }
    
    // Callback for triggering completion after schema/alias selection
    private Action? _triggerCompletionCallback;
    
    // Current connection for on-demand column loading
    private IConnectionManager? _currentConnection;
    
    // Scope-aware parser for nested subselects
    private readonly SqlScopeParser _scopeParser = new();
    
    /// <summary>
    /// Set the callback to trigger completion window (called after schema/alias selection)
    /// </summary>
    public void SetCompletionCallback(Action? callback)
    {
        _triggerCompletionCallback = callback;
    }
    
    /// <summary>
    /// Current database provider (e.g., "DB2", "PostgreSQL").
    /// </summary>
    public string Provider => _currentProvider;
    
    /// <summary>
    /// Current provider version.
    /// </summary>
    public string Version => _currentVersion;
    
    public async Task LoadMetadataAsync(string keywordsFile, string statementsFile, string metadataFile)
    {
        Logger.Debug("Loading metadata - Provider: {Provider}, Version: {Version}", _currentProvider, _currentVersion);
        
        try
        {
            // Try to load from JSON first
            _metadata = await _dataLoader.LoadAsync(_currentProvider, _currentVersion);
            
            if (_metadata != null)
            {
                // Populate cached lists from metadata
                _keywords = _metadata.GetAllKeywords();
                _dataTypes = _metadata.GetAllDataTypes();
                _functions = _metadata.GetAllFunctions();
                _systemTables = _metadata.GetAllSystemTables();
                _snippets = _metadata.Snippets ?? new Dictionary<string, SnippetDefinition>();
                
                Logger.Info("Loaded IntelliSense from JSON: {Keywords} keywords, {DataTypes} data types, " +
                           "{Functions} functions, {SystemTables} system tables, {Snippets} snippets",
                           _keywords.Count, _dataTypes.Count, _functions.Count, _systemTables.Count, _snippets.Count);
            }
            else
            {
                // Fall back to legacy file loading
                await LoadLegacyMetadataAsync(keywordsFile, statementsFile, metadataFile);
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load metadata");
            LoadDefaultKeywords();
        }
    }
    
    /// <summary>
    /// Set the active provider and version.
    /// </summary>
    public async Task SetProviderAsync(string provider, string version)
    {
        if (_currentProvider == provider && _currentVersion == version)
            return;
        
        _currentProvider = provider;
        _currentVersion = version;
        
        Logger.Info("Switching IntelliSense to {Provider} {Version}", provider, version);
        
        // Reload metadata for new provider
        await LoadMetadataAsync(string.Empty, string.Empty, string.Empty);
    }
    
    /// <summary>
    /// Legacy metadata loading for backward compatibility.
    /// </summary>
    private async Task LoadLegacyMetadataAsync(string keywordsFile, string statementsFile, string metadataFile)
    {
        Logger.Debug("Loading legacy metadata from files");
        
        try
        {
            // Load keywords from db2_12.1_keywords.json (old format)
            if (File.Exists(keywordsFile))
            {
                var keywordsJson = await File.ReadAllTextAsync(keywordsFile);
                var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
                var keywordsData = JsonSerializer.Deserialize<LegacyKeywordsMetadata>(keywordsJson, options);
                
                if (keywordsData?.Keywords != null)
                {
                    _keywords = keywordsData.GetAllKeywords();
                    _dataTypes = keywordsData.Keywords.Datatypes ?? new List<string>();
                    _functions = keywordsData.Keywords.Functions ?? new List<string>();
                    _systemTables = keywordsData.Keywords.SystemTables ?? new List<string>();
                    
                    Logger.Info("Loaded legacy keywords: {Count} total", _keywords.Count);
                }
                else
                {
                    LoadDefaultKeywords();
                }
            }
            else
            {
                LoadDefaultKeywords();
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load legacy metadata");
            LoadDefaultKeywords();
        }
    }
    
    /// <summary>
    /// Load default SQL keywords when JSON file is not available.
    /// </summary>
    private void LoadDefaultKeywords()
    {
        Logger.Info("Loading default SQL keywords");
        
        _keywords = new List<string>
        {
            "SELECT", "INSERT", "UPDATE", "DELETE", "MERGE",
            "CREATE", "ALTER", "DROP", "TRUNCATE",
            "BEGIN", "END", "COMMIT", "ROLLBACK",
            "FROM", "WHERE", "GROUP BY", "HAVING", "ORDER BY",
            "JOIN", "INNER JOIN", "LEFT JOIN", "RIGHT JOIN", "FULL JOIN",
            "ON", "AND", "OR", "NOT", "IN", "EXISTS",
            "BETWEEN", "LIKE", "IS NULL", "IS NOT NULL",
            "DISTINCT", "ALL", "AS", "UNION", "INTERSECT", "EXCEPT",
            "FETCH FIRST", "ROWS ONLY", "WITH", "VALUES",
            "SET", "DECLARE", "CALL", "RETURN"
        };
        
        _dataTypes = new List<string>
        {
            "INTEGER", "INT", "SMALLINT", "BIGINT",
            "DECIMAL", "NUMERIC", "REAL", "DOUBLE", "FLOAT",
            "CHAR", "VARCHAR", "CLOB", "BLOB",
            "DATE", "TIME", "TIMESTAMP",
            "BOOLEAN", "XML"
        };
        
        _functions = new List<string>
        {
            "COUNT", "SUM", "AVG", "MIN", "MAX",
            "SUBSTR", "TRIM", "UPPER", "LOWER", "LENGTH",
            "COALESCE", "NULLIF", "CAST",
            "CURRENT DATE", "CURRENT TIME", "CURRENT TIMESTAMP",
            "ROW_NUMBER", "RANK", "DENSE_RANK"
        };
        
        _systemTables = new List<string>
        {
            "SYSCAT.TABLES", "SYSCAT.COLUMNS", "SYSCAT.INDEXES",
            "SYSCAT.VIEWS", "SYSCAT.ROUTINES", "SYSCAT.TRIGGERS"
        };
    }
    
    public async Task LoadLiveSchemaMetadataAsync(IConnectionManager connection)
    {
        Logger.Debug("Loading live schema metadata from database");
        
        try
        {
            // Load table names
            var tablesSql = GetSystemTableQuery("tables");
            using (var tableCmd = connection.CreateCommand(tablesSql))
            {
                using var adapter = connection.CreateDataAdapter(tableCmd);
                var tablesTable = new System.Data.DataTable();
                await Task.Run(() => adapter.Fill(tablesTable));
                
                foreach (System.Data.DataRow row in tablesTable.Rows)
                {
                    var schema = GetColumnValue(row, "TABSCHEMA", "SchemaName")?.Trim() ?? string.Empty;
                    var name = GetColumnValue(row, "TABNAME", "TableName")?.Trim() ?? string.Empty;
                    _tableNames.Add($"{schema}.{name}");
                }
                Logger.Debug("Loaded {Count} table names", _tableNames.Count);
            }
            
            // Load view names
            var viewsSql = GetSystemTableQuery("views");
            using (var viewCmd = connection.CreateCommand(viewsSql))
            {
                using var adapter = connection.CreateDataAdapter(viewCmd);
                var viewsTable = new System.Data.DataTable();
                await Task.Run(() => adapter.Fill(viewsTable));
                
                foreach (System.Data.DataRow row in viewsTable.Rows)
                {
                    var schema = GetColumnValue(row, "TABSCHEMA", "SchemaName")?.Trim() ?? string.Empty;
                    var name = GetColumnValue(row, "TABNAME", "TableName")?.Trim() ?? string.Empty;
                    _viewNames.Add($"{schema}.{name}");
                }
                Logger.Debug("Loaded {Count} view names", _viewNames.Count);
            }
            
            // Load procedure names
            var proceduresSql = GetSystemTableQuery("procedures");
            using (var procCmd = connection.CreateCommand(proceduresSql))
            {
                using var adapter = connection.CreateDataAdapter(procCmd);
                var procTable = new System.Data.DataTable();
                await Task.Run(() => adapter.Fill(procTable));
                
                foreach (System.Data.DataRow row in procTable.Rows)
                {
                    var schema = GetColumnValue(row, "ROUTINESCHEMA", "RoutineSchema")?.Trim() ?? string.Empty;
                    var name = GetColumnValue(row, "ROUTINENAME", "RoutineName")?.Trim() ?? string.Empty;
                    _procedureNames.Add($"{schema}.{name}");
                }
                Logger.Debug("Loaded {Count} procedure names", _procedureNames.Count);
            }
            
            // Extract unique schema names from all loaded objects
            _schemaNames = _tableNames
                .Concat(_viewNames)
                .Concat(_procedureNames)
                .Where(obj => obj.Contains('.'))
                .Select(obj => obj.Split('.')[0])
                .Distinct()
                .OrderBy(s => s)
                .ToList();
            Logger.Debug("Extracted {Count} unique schema names", _schemaNames.Count);
            
            // Load column information for tables (limited to most common tables for performance)
            await LoadTableColumnsAsync(connection, _tableNames.Take(100).ToList());
            
            // Load function names
            var functionsSql = GetSystemTableQuery("functions");
            using (var funcCmd = connection.CreateCommand(functionsSql))
            {
                using var adapter = connection.CreateDataAdapter(funcCmd);
                var funcTable = new System.Data.DataTable();
                await Task.Run(() => adapter.Fill(funcTable));
                
                foreach (System.Data.DataRow row in funcTable.Rows)
                {
                    var schema = GetColumnValue(row, "ROUTINESCHEMA", "RoutineSchema")?.Trim() ?? string.Empty;
                    var name = GetColumnValue(row, "ROUTINENAME", "RoutineName")?.Trim() ?? string.Empty;
                    _functionNames.Add($"{schema}.{name}");
                }
                Logger.Debug("Loaded {Count} function names", _functionNames.Count);
            }
            
            Logger.Info("Live schema metadata loaded - {Tables} tables, {Views} views, {Procedures} procedures, {Functions} functions",
                        _tableNames.Count, _viewNames.Count, _procedureNames.Count, _functionNames.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load live schema metadata");
        }
    }
    
    /// <summary>
    /// Load column information for specified tables.
    /// </summary>
    private async Task LoadTableColumnsAsync(IConnectionManager connection, List<string> tableNames)
    {
        Logger.Debug("Loading columns for {Count} tables", tableNames.Count);
        _tableColumns.Clear();
        
        try
        {
            foreach (var fullTableName in tableNames)
            {
                await LoadColumnsForTableAsync(connection, fullTableName);
            }
            
            Logger.Info("Loaded column metadata for {Count} tables", _tableColumns.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load column metadata");
        }
    }
    
    /// <summary>
    /// Load columns for a single table (can be called on-demand).
    /// </summary>
    private async Task LoadColumnsForTableAsync(IConnectionManager connection, string fullTableName)
    {
        // Skip if already loaded
        if (_tableColumns.ContainsKey(fullTableName))
            return;
        
        var parts = fullTableName.Split('.');
        if (parts.Length != 2) return;
        
        var schema = parts[0].Trim();
        var table = parts[1].Trim();
        
        try
        {
            // Use inline SQL with parameter substitution for simpler handling
            var columnsSql = _currentProvider.ToUpperInvariant() switch
            {
                "POSTGRESQL" or "POSTGRES" => 
                    $"SELECT column_name AS COLNAME, data_type AS TYPENAME, is_nullable AS NULLS, " +
                    $"CASE WHEN column_name IN (SELECT column_name FROM information_schema.key_column_usage " +
                    $"WHERE table_schema = '{schema}' AND table_name = '{table}') THEN 1 ELSE 0 END AS KEYSEQ " +
                    $"FROM information_schema.columns WHERE table_schema = '{schema}' AND table_name = '{table}' " +
                    $"ORDER BY ordinal_position",
                _ => // DB2
                    $"SELECT TRIM(COLNAME) AS COLNAME, TRIM(TYPENAME) AS TYPENAME, NULLS, KEYSEQ " +
                    $"FROM SYSCAT.COLUMNS WHERE TABSCHEMA = '{schema}' AND TABNAME = '{table}' ORDER BY COLNO"
            };
            
            using var cmd = connection.CreateCommand(columnsSql);
            using var adapter = connection.CreateDataAdapter(cmd);
            var columnsTable = new System.Data.DataTable();
            await Task.Run(() => adapter.Fill(columnsTable));
            
            var columns = new List<ColumnInfo>();
            foreach (System.Data.DataRow row in columnsTable.Rows)
            {
                var colName = GetColumnValue(row, "COLNAME", "column_name")?.Trim() ?? string.Empty;
                var dataType = GetColumnValue(row, "TYPENAME", "data_type")?.Trim() ?? "UNKNOWN";
                var nulls = GetColumnValue(row, "NULLS", "is_nullable")?.Trim();
                var keySeq = GetColumnValue(row, "KEYSEQ", "keyseq");
                
                if (!string.IsNullOrEmpty(colName))
                {
                    columns.Add(new ColumnInfo
                    {
                        Name = colName,
                        DataType = dataType,
                        IsNullable = nulls == "Y" || nulls?.ToUpperInvariant() == "YES",
                        IsPrimaryKey = !string.IsNullOrEmpty(keySeq) && keySeq != "0"
                    });
                }
            }
            
            if (columns.Count > 0)
            {
                _tableColumns[fullTableName] = columns;
                Logger.Debug("Loaded {Count} columns for {Table}", columns.Count, fullTableName);
            }
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "Failed to load columns for {Table}", fullTableName);
        }
    }
    
    /// <summary>
    /// Get provider-specific system table query.
    /// </summary>
    private string GetSystemTableQuery(string objectType)
    {
        // These queries will be moved to JSON in a future update
        return _currentProvider.ToUpperInvariant() switch
        {
            "POSTGRESQL" or "POSTGRES" => objectType switch
            {
                "tables" => "SELECT schemaname AS TABSCHEMA, tablename AS TABNAME FROM pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema') LIMIT 500",
                "views" => "SELECT schemaname AS TABSCHEMA, viewname AS TABNAME FROM pg_views WHERE schemaname NOT IN ('pg_catalog', 'information_schema') LIMIT 500",
                "procedures" => "SELECT routine_schema AS ROUTINESCHEMA, routine_name AS ROUTINENAME FROM information_schema.routines WHERE routine_type = 'PROCEDURE' LIMIT 500",
                "functions" => "SELECT routine_schema AS ROUTINESCHEMA, routine_name AS ROUTINENAME FROM information_schema.routines WHERE routine_type = 'FUNCTION' LIMIT 500",
                _ => string.Empty
            },
            _ => objectType switch // Default to DB2
            {
                "tables" => "SELECT TABSCHEMA, TABNAME FROM SYSCAT.TABLES WHERE TYPE = 'T' FETCH FIRST 500 ROWS ONLY",
                "views" => "SELECT TABSCHEMA, TABNAME FROM SYSCAT.TABLES WHERE TYPE = 'V' FETCH FIRST 500 ROWS ONLY",
                "procedures" => "SELECT ROUTINESCHEMA, ROUTINENAME FROM SYSCAT.ROUTINES WHERE ROUTINETYPE = 'P' FETCH FIRST 500 ROWS ONLY",
                "functions" => "SELECT ROUTINESCHEMA, ROUTINENAME FROM SYSCAT.ROUTINES WHERE ROUTINETYPE = 'F' FETCH FIRST 500 ROWS ONLY",
                "columns" => "SELECT TRIM(COLNAME) AS COLNAME, TRIM(TYPENAME) AS TYPENAME, NULLS, KEYSEQ FROM SYSCAT.COLUMNS WHERE TABSCHEMA = ? AND TABNAME = ? ORDER BY COLNO",
                _ => string.Empty
            }
        };
    }
    
    /// <summary>
    /// Get column value with fallback column name.
    /// </summary>
    private string? GetColumnValue(System.Data.DataRow row, string primaryColumn, string fallbackColumn)
    {
        if (row.Table.Columns.Contains(primaryColumn))
            return row[primaryColumn]?.ToString();
        if (row.Table.Columns.Contains(fallbackColumn))
            return row[fallbackColumn]?.ToString();
        return null;
    }
    
    public List<ICompletionData> GetCompletions(CompletionContext context)
    {
        var completions = new List<ICompletionData>();
        
        // Store current connection for on-demand column loading
        _currentConnection = context.Connection;
        
        try
        {
            var sqlContext = DetermineSqlContext(context.Text, context.CaretPosition);
            Logger.Debug("SQL context: {Context}", sqlContext);
            
            completions = sqlContext switch
            {
                SqlContext.Keyword => GetKeywordCompletions(),
                SqlContext.Schema => GetSchemaCompletions(),  // NEW: Schema-first
                SqlContext.TableName => GetTableNameCompletions(),
                SqlContext.ColumnName => GetColumnNameCompletions(context.Text, context.CaretPosition),
                SqlContext.JoinCondition => GetJoinConditionCompletions(context.Text, context.CaretPosition),
                SqlContext.OrderByColumn => GetOrderByCompletions(context.Text, context.CaretPosition),
                SqlContext.Function => GetFunctionCompletions(),
                SqlContext.DataType => GetDataTypeCompletions(),
                SqlContext.SystemCatalog => GetSystemCatalogCompletions(),
                SqlContext.Snippet => GetSnippetCompletions(),
                SqlContext.SchemaObject => GetSchemaObjectCompletions(context.Text, context.CaretPosition),
                SqlContext.Alias => new List<ICompletionData>(), // User types alias themselves
                _ => GetGeneralCompletions()
            };
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to generate completions");
        }
        
        return completions;
    }
    
    /// <summary>
    /// Get schema completions (show schemas first after FROM/JOIN)
    /// </summary>
    private List<ICompletionData> GetSchemaCompletions()
    {
        Logger.Debug("Getting schema completions - {Count} schemas available", _schemaNames.Count);
        
        var completions = new List<ICompletionData>();
        
        // Add schemas with high priority, wire up completion callback
        foreach (var s in _schemaNames)
        {
            completions.Add(new SqlSchemaCompletionData
            {
                Text = s,
                Description = $"Schema: {s}",
                Priority = 10.0,  // Highest priority
                OnCompleted = _triggerCompletionCallback  // Trigger table list after selection
            });
        }
        
        // Also add common system schemas for DB2
        var systemSchemas = new[] { "SYSCAT", "SYSIBM", "SYSIBMADM", "SYSSTAT" };
        foreach (var sysSchema in systemSchemas)
        {
            if (!_schemaNames.Contains(sysSchema, StringComparer.OrdinalIgnoreCase))
            {
                completions.Add(new SqlSchemaCompletionData
                {
                    Text = sysSchema,
                    Description = $"System Schema: {sysSchema}",
                    Priority = 5.0,
                    OnCompleted = _triggerCompletionCallback
                });
            }
        }
        
        Logger.Debug("Returning {Count} schema completions", completions.Count);
        return completions;
    }
    
    /// <summary>
    /// Get completions for JOIN ON conditions
    /// </summary>
    private List<ICompletionData> GetJoinConditionCompletions(string text, int caretPosition)
    {
        // Extract table references from the query for join conditions
        var tableNames = ExtractTableNamesFromQuery(text);
        var completions = new List<ICompletionData>();
        
        foreach (var tableName in tableNames)
        {
            var tableAlias = tableName.Split('.').LastOrDefault() ?? tableName;
            
            if (_tableColumns.TryGetValue(tableName, out var columns))
            {
                completions.AddRange(columns.Select(c => new SqlColumnCompletionData
                {
                    ColumnName = $"{tableAlias}.{c.Name}",  // Include table alias in column name
                    DataType = c.DataType,
                    TableName = tableName,
                    Priority = 3.0
                }));
            }
        }
        
        // If no columns found, show table names for user to qualify
        if (completions.Count == 0)
        {
            completions.AddRange(tableNames.Select(t => new SqlTableCompletionData
            {
                Text = t.Split('.').LastOrDefault() ?? t,
                Description = $"Table: {t}",
                Priority = 2.0
            }));
        }
        
        return completions;
    }
    
    /// <summary>
    /// Get completions for ORDER BY / GROUP BY clauses
    /// </summary>
    private List<ICompletionData> GetOrderByCompletions(string text, int caretPosition)
    {
        // For ORDER BY, show columns from referenced tables
        return GetColumnNameCompletions(text, caretPosition);
    }
    
    public async Task<FunctionSignature?> GetSignatureHintAsync(string functionName)
    {
        Logger.Debug("Getting signature hint for function: {Function}", functionName);
        return await Task.FromResult<FunctionSignature?>(null);
    }
    
    private SqlContext DetermineSqlContext(string text, int caretPosition)
    {
        if (caretPosition == 0 || string.IsNullOrEmpty(text))
            return SqlContext.Keyword;
        
        var textBeforeCaret = text.Substring(0, Math.Min(caretPosition, text.Length));
        
        // PRIORITY 1: Check if we're typing after a schema/table alias followed by a period
        // Case A: "MYSCHEMA." <- caret right after period, or
        // Case B: "MYSCHEMA.par" <- typing partial table name after schema
        
        // Regex to match: "word." at end OR "word.partial" at end
        // Pattern: word followed by period, optionally followed by more word chars (partial name)
        var schemaObjectMatch = Regex.Match(textBeforeCaret, @"(\w+)\.(\w*)$");
        if (schemaObjectMatch.Success)
        {
            var identifier = schemaObjectMatch.Groups[1].Value;
            var partialName = schemaObjectMatch.Groups[2].Value;
            
            // Check if this is a known schema -> show tables/views from that schema
            if (_schemaNames.Contains(identifier, StringComparer.OrdinalIgnoreCase))
            {
                Logger.Debug("Detected schema.object context for schema: {Schema}, partial: {Partial}", 
                    identifier, partialName);
                return SqlContext.SchemaObject;
            }
            
            // Could be a table alias -> show columns (alias.column)
            Logger.Debug("Detected alias.column context for alias: {Alias}, partial: {Partial}", 
                identifier, partialName);
            return SqlContext.ColumnName;
        }
        
        // Extract current statement for better context (multi-statement support)
        var currentStatement = ExtractCurrentStatement(text, caretPosition);
        var statementBeforeCaret = GetStatementBeforeCaret(currentStatement, text, caretPosition);
        
        // Get the previous keyword/token
        var lastWords = GetLastWords(statementBeforeCaret, 5);
        
        if (lastWords.Count > 0)
        {
            var lastWord = lastWords[^1].ToUpperInvariant();
            var secondLastWord = lastWords.Count > 1 ? lastWords[^2].ToUpperInvariant() : string.Empty;
            var thirdLastWord = lastWords.Count > 2 ? lastWords[^3].ToUpperInvariant() : string.Empty;
            
            // Check if lastWord is a SQL keyword (to distinguish from identifiers)
            var sqlKeywords = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            {
                "SELECT", "FROM", "WHERE", "JOIN", "INNER", "LEFT", "RIGHT", "FULL", "CROSS", "OUTER",
                "ON", "AND", "OR", "ORDER", "BY", "GROUP", "HAVING", "INSERT", "INTO", "UPDATE", "SET",
                "DELETE", "CREATE", "ALTER", "DROP", "TABLE", "VIEW", "INDEX", "AS", "DISTINCT", "VALUES",
                "MERGE", "TRUNCATE", "RENAME", "GRANT", "REVOKE", "COMMENT", "LOCK", "UNION", "EXCEPT", "INTERSECT"
            };
            var lastWordIsKeyword = sqlKeywords.Contains(lastWord);
            
            // PRIORITY 2: After FROM, JOIN, INTO, UPDATE -> show SCHEMAS first
            // Case 1: Cursor right after keyword (e.g., "FROM |")
            if (lastWord is "FROM" or "JOIN" or "INTO" or "TABLE" or "UPDATE")
            {
                Logger.Debug("Context: Schema (after {Keyword})", lastWord);
                return SqlContext.Schema;
            }
            
            // Case 2: Already typing identifier after FROM/JOIN (e.g., "FROM db|")
            // lastWord is the partial identifier, secondLastWord is the keyword
            // BUT if lastWord contains a period, it's already a complete schema.table reference
            // In that case, user is typing after the table (likely alias or keyword context)
            if (!lastWordIsKeyword && secondLastWord is "FROM" or "JOIN" or "INTO" or "TABLE" or "UPDATE")
            {
                // If lastWord contains a period, it's a complete table reference (e.g., "DBM.BANKTERM_ID")
                // After a complete table, show keywords (WHERE, AS) or allow alias typing
                if (lastWord.Contains('.'))
                {
                    Logger.Debug("Context: Keyword (after complete table reference: {Table})", lastWord);
                    return SqlContext.Keyword;  // Show WHERE, JOIN, AS, etc.
                }
                
                Logger.Debug("Context: Schema (typing after {Keyword}, partial: {Partial})", secondLastWord, lastWord);
                return SqlContext.Schema;
            }
            
            // Case 3: After comma in FROM clause (e.g., "FROM schema.table, |" or "FROM schema.table, db|")
            // Check if we're in a FROM clause by looking back for FROM
            if (lastWord == ",")
            {
                // Look back to find what clause we're in
                if (IsInFromClause(statementBeforeCaret))
                {
                    Logger.Debug("Context: Schema (comma in FROM clause)");
                    return SqlContext.Schema;
                }
            }
            
            // Typing after comma in FROM clause (e.g., "FROM schema.table, db|")
            if (!lastWordIsKeyword && secondLastWord == "," && !lastWord.Contains('.'))
            {
                if (IsInFromClause(statementBeforeCaret))
                {
                    Logger.Debug("Context: Schema (typing after comma in FROM clause)");
                    return SqlContext.Schema;
                }
            }
            
            // After INNER, LEFT, RIGHT, FULL, CROSS -> likely followed by JOIN
            if (lastWord is "INNER" or "LEFT" or "RIGHT" or "FULL" or "CROSS")
            {
                // If next would be JOIN, wait for that
                return SqlContext.Keyword;
            }
            
            // PRIORITY 3: After ON -> show columns for join condition
            if (lastWord == "ON")
            {
                Logger.Debug("Context: JoinCondition");
                return SqlContext.JoinCondition;
            }
            
            // After ON with partial identifier
            if (!lastWordIsKeyword && secondLastWord == "ON")
            {
                Logger.Debug("Context: JoinCondition (typing after ON)");
                return SqlContext.JoinCondition;
            }
            
            // PRIORITY 4: After SELECT -> show columns, *, functions
            if (lastWord == "SELECT" || (lastWord == "DISTINCT" && secondLastWord == "SELECT"))
            {
                Logger.Debug("Context: ColumnName (SELECT clause)");
                return SqlContext.ColumnName;
            }
            
            // Typing after SELECT
            if (!lastWordIsKeyword && (secondLastWord == "SELECT" || 
                (secondLastWord == "DISTINCT" && thirdLastWord == "SELECT")))
            {
                Logger.Debug("Context: ColumnName (typing in SELECT clause)");
                return SqlContext.ColumnName;
            }
            
            // PRIORITY 5: After WHERE, AND, OR -> show columns
            if (lastWord is "WHERE" or "AND" or "OR" or "HAVING")
            {
                Logger.Debug("Context: ColumnName (predicate)");
                return SqlContext.ColumnName;
            }
            
            // Typing after WHERE/AND/OR
            if (!lastWordIsKeyword && secondLastWord is "WHERE" or "AND" or "OR" or "HAVING")
            {
                Logger.Debug("Context: ColumnName (typing in predicate)");
                return SqlContext.ColumnName;
            }
            
            // After ORDER BY or GROUP BY -> show columns
            if ((lastWord == "BY" && secondLastWord is "ORDER" or "GROUP") ||
                lastWord is "ORDER" or "GROUP")
            {
                Logger.Debug("Context: OrderByColumn");
                return SqlContext.OrderByColumn;
            }
            
            // Typing after ORDER BY / GROUP BY
            if (!lastWordIsKeyword && secondLastWord == "BY" && thirdLastWord is "ORDER" or "GROUP")
            {
                Logger.Debug("Context: OrderByColumn (typing)");
                return SqlContext.OrderByColumn;
            }
            
            // After SET (in UPDATE) -> show columns
            if (lastWord == "SET")
            {
                Logger.Debug("Context: ColumnName (SET clause)");
                return SqlContext.ColumnName;
            }
            
            // Typing after SET
            if (!lastWordIsKeyword && secondLastWord == "SET")
            {
                Logger.Debug("Context: ColumnName (typing in SET clause)");
                return SqlContext.ColumnName;
            }
            
            // After AS -> alias context
            if (lastWord == "AS")
            {
                return SqlContext.Alias;
            }
            
            // Data type context
            if (lastWord == "AS" && secondLastWord == "TYPE")
                return SqlContext.DataType;
            
            // System catalog context
            if (statementBeforeCaret.Contains("SYSCAT.", StringComparison.OrdinalIgnoreCase) ||
                statementBeforeCaret.Contains("pg_catalog.", StringComparison.OrdinalIgnoreCase) ||
                statementBeforeCaret.Contains("information_schema.", StringComparison.OrdinalIgnoreCase))
                return SqlContext.SystemCatalog;
        }
        
        return SqlContext.General;
    }
    
    /// <summary>
    /// Check if the current position is within a FROM clause
    /// </summary>
    private bool IsInFromClause(string textBeforeCaret)
    {
        var upper = textBeforeCaret.ToUpperInvariant();
        
        // Find the last FROM position
        var fromPos = upper.LastIndexOf(" FROM ", StringComparison.Ordinal);
        if (fromPos < 0)
            return false;
        
        // Check if there's a WHERE, ORDER, GROUP, HAVING, JOIN after FROM
        // If so, we're past the FROM clause
        var afterFrom = upper.Substring(fromPos);
        
        // These keywords end the simple FROM clause (though JOIN is still table context)
        if (afterFrom.Contains(" WHERE ") || 
            afterFrom.Contains(" ORDER ") || 
            afterFrom.Contains(" GROUP ") || 
            afterFrom.Contains(" HAVING ") ||
            afterFrom.Contains(" UNION ") ||
            afterFrom.Contains(" EXCEPT ") ||
            afterFrom.Contains(" INTERSECT "))
        {
            return false;
        }
        
        return true;
    }
    
    /// <summary>
    /// Extract the current SQL statement based on caret position (multi-statement support)
    /// </summary>
    private string ExtractCurrentStatement(string text, int caretPosition)
    {
        if (string.IsNullOrEmpty(text))
            return string.Empty;
        
        // Find statement boundaries using semicolons
        var statements = new List<(int start, int end, string text)>();
        var currentStart = 0;
        
        for (int i = 0; i < text.Length; i++)
        {
            if (text[i] == ';')
            {
                statements.Add((currentStart, i, text.Substring(currentStart, i - currentStart)));
                currentStart = i + 1;
            }
        }
        
        // Add last statement (no trailing semicolon)
        if (currentStart < text.Length)
        {
            statements.Add((currentStart, text.Length, text.Substring(currentStart)));
        }
        
        // Find which statement contains the caret
        foreach (var (start, end, stmt) in statements)
        {
            if (caretPosition >= start && caretPosition <= end)
            {
                return stmt.Trim();
            }
        }
        
        return text;
    }
    
    /// <summary>
    /// Get the portion of the current statement before the caret
    /// </summary>
    private string GetStatementBeforeCaret(string currentStatement, string fullText, int caretPosition)
    {
        // Find where the current statement starts in the full text
        var stmtIndex = fullText.IndexOf(currentStatement, StringComparison.Ordinal);
        if (stmtIndex >= 0)
        {
            var offsetInStatement = caretPosition - stmtIndex;
            if (offsetInStatement > 0 && offsetInStatement <= currentStatement.Length)
            {
                return currentStatement.Substring(0, offsetInStatement);
            }
        }
        
        // Fallback to full text before caret
        return fullText.Substring(0, Math.Min(caretPosition, fullText.Length));
    }
    
    private List<string> GetLastWords(string text, int count)
    {
        return Regex.Split(text, @"[^\w\.]+")
            .Where(w => !string.IsNullOrWhiteSpace(w))
            .TakeLast(count)
            .ToList();
    }
    
    private List<ICompletionData> GetKeywordCompletions()
    {
        return _keywords
            .Select(k => new SqlKeywordCompletionData
            {
                Text = k,
                Description = $"SQL Keyword: {k}",
                Priority = 1.0
            })
            .Cast<ICompletionData>()
            .ToList();
    }
    
    private List<ICompletionData> GetTableNameCompletions()
    {
        var completions = new List<ICompletionData>();
        
        completions.AddRange(_tableNames.Select(t => new SqlTableCompletionData
        {
            Text = t,
            Description = $"Table: {t}",
            Priority = 2.0
        }));
        
        completions.AddRange(_viewNames.Select(v => new SqlViewCompletionData
        {
            Text = v,
            Description = $"View: {v}",
            Priority = 2.0
        }));
        
        return completions;
    }
    
    private List<ICompletionData> GetColumnNameCompletions(string text, int caretPosition)
    {
        var completions = new List<ICompletionData>();
        
        Logger.Debug("=== GetColumnNameCompletions START ===");
        Logger.Debug("Text length: {Length}, CaretPosition: {Position}", text.Length, caretPosition);
        
        // Use scope-aware parsing for nested subselect support
        var scopes = _scopeParser.Parse(text);
        Logger.Debug("Parsed {Count} scopes from SQL", scopes.Count);
        
        var currentScope = _scopeParser.GetScopeAtPosition(scopes, caretPosition);
        
        if (currentScope == null)
        {
            Logger.Debug("No scope found at position {Position} - using fallback", caretPosition);
            return GetFallbackColumnCompletions(text, caretPosition);
        }
        
        Logger.Debug("Current scope: Level={Level}, Index={Index}, Tables={TableCount}, FromPart='{From}'", 
            currentScope.Level, currentScope.Index, currentScope.Tables.Count,
            currentScope.FromPart?.Substring(0, Math.Min(50, currentScope.FromPart?.Length ?? 0)) ?? "(null)");
        
        // Get visibility for current scope
        var visibility = _scopeParser.GetVisibleItems(scopes, currentScope);
        Logger.Debug("Visibility: {Aliases} aliases, {ParentAliases} parent aliases, {DerivedColumns} derived table column sets",
            visibility.Aliases.Count, visibility.ParentAliases.Count, visibility.DerivedTableColumns.Count);
        
        foreach (var alias in visibility.Aliases)
        {
            Logger.Debug("  Visible alias: '{Name}' -> {FullTableName} (IsDerived={IsDerived})", 
                alias.Name, alias.FullTableName, alias.IsDerivedTable);
        }
        
        // Check if user is typing after an alias (e.g., "t1.")
        var textBeforeCaret = text.Substring(0, Math.Min(caretPosition, text.Length));
        var aliasMatch = Regex.Match(textBeforeCaret, @"(\w+)\.\w*$");  // Match "alias." or "alias.partial"
        
        if (aliasMatch.Success)
        {
            var typedAlias = aliasMatch.Groups[1].Value;
            Logger.Debug("User typed alias: '{Alias}' at scope level {Level}", typedAlias, currentScope.Level);
            
            // Check if this is a regular table alias
            var tableAlias = visibility.Aliases.FirstOrDefault(a => 
                string.Equals(a.Name, typedAlias, StringComparison.OrdinalIgnoreCase));
            
            if (tableAlias != null)
            {
                if (tableAlias.IsDerivedTable)
                {
                    // Derived table - show only exposed columns from subselect
                    var derivedColumns = visibility.DerivedTableColumns
                        .FirstOrDefault(d => string.Equals(d.Alias, typedAlias, StringComparison.OrdinalIgnoreCase));
                    
                    if (derivedColumns != null)
                    {
                        Logger.Debug("Showing {Count} exposed columns from derived table '{Alias}'", 
                            derivedColumns.ExposedColumns.Count, typedAlias);
                        
                        foreach (var col in derivedColumns.ExposedColumns)
                        {
                            completions.Add(new SqlColumnCompletionData
                            {
                                ColumnName = col,
                                DataType = "EXPOSED",
                                TableName = $"(subselect {typedAlias})",
                                Priority = 3.0
                            });
                        }
                        return completions;
                    }
                }
                else
                {
                    // Regular table - show columns from database
                    return GetColumnsForTable(tableAlias.FullTableName, typedAlias);
                }
            }
            
            // Check parent aliases (for correlated subqueries)
            var parentAlias = visibility.ParentAliases.FirstOrDefault(a =>
                string.Equals(a.Name, typedAlias, StringComparison.OrdinalIgnoreCase));
            
            if (parentAlias != null)
            {
                Logger.Debug("Using parent scope alias: {Alias} -> {Table}", typedAlias, parentAlias.FullTableName);
                return GetColumnsForTable(parentAlias.FullTableName, typedAlias);
            }
        }
        
        // No alias typed - show available aliases if multiple tables/derived tables
        var allAliases = visibility.Aliases.Concat(visibility.ParentAliases).ToList();
        
        if (allAliases.Count > 1 || visibility.DerivedTableColumns.Any())
        {
            Logger.Debug("Multiple sources - showing {Count} aliases", allAliases.Count);
            
            foreach (var alias in visibility.Aliases)
            {
                completions.Add(new SqlAliasCompletionData
                {
                    AliasName = alias.Name,
                    TableName = alias.IsDerivedTable ? "(subselect)" : alias.FullTableName.Split('.').LastOrDefault() ?? "",
                    SchemaName = alias.IsDerivedTable ? "" : alias.FullTableName.Split('.').FirstOrDefault() ?? "",
                    IsSubselectAlias = alias.IsDerivedTable,
                    Priority = 4.0,
                    OnCompleted = _triggerCompletionCallback
                });
            }
            
            // Show parent aliases for correlated subqueries (marked differently)
            foreach (var parentAlias in visibility.ParentAliases)
            {
                completions.Add(new SqlAliasCompletionData
                {
                    AliasName = parentAlias.Name,
                    TableName = parentAlias.FullTableName.Split('.').LastOrDefault() ?? "",
                    SchemaName = $"↑ {parentAlias.FullTableName.Split('.').FirstOrDefault() ?? ""}",
                    Priority = 3.5,  // Slightly lower priority than current scope
                    OnCompleted = _triggerCompletionCallback
                });
            }
            
            return completions;
        }
        
        // Single table - show columns directly
        if (visibility.Aliases.Count == 1 && !visibility.Aliases[0].IsDerivedTable)
        {
            var singleTable = visibility.Aliases[0];
            Logger.Debug("Single table at scope - showing columns for {Table}", singleTable.FullTableName);
            return GetColumnsForTable(singleTable.FullTableName, null);
        }
        
        // Fallback
        return GetFallbackColumnCompletions(text, caretPosition);
    }
    
    /// <summary>
    /// Fallback column completions when scope parsing doesn't find tables.
    /// </summary>
    private List<ICompletionData> GetFallbackColumnCompletions(string text, int caretPosition)
    {
        var completions = new List<ICompletionData>();
        var tableRefs = ExtractTableReferencesWithAliases(text);
        
        Logger.Debug("Fallback: Found {Count} table references in query", tableRefs.Count);
        
        // Check if user is typing after an alias (e.g., "t1.")
        var textBeforeCaret = text.Substring(0, Math.Min(caretPosition, text.Length));
        var aliasMatch = Regex.Match(textBeforeCaret, @"(\w+)\.$");
        
        if (aliasMatch.Success)
        {
            var typedAlias = aliasMatch.Groups[1].Value;
            var matchingRef = tableRefs.FirstOrDefault(t => 
                string.Equals(t.Alias, typedAlias, StringComparison.OrdinalIgnoreCase) ||
                string.Equals(t.TableName, typedAlias, StringComparison.OrdinalIgnoreCase));
            
            if (matchingRef != null)
            {
                return GetColumnsForTable(matchingRef.FullName, typedAlias);
            }
        }
        
        // Multiple tables - show aliases
        if (tableRefs.Count > 1 && tableRefs.Any(t => !string.IsNullOrEmpty(t.Alias)))
        {
            foreach (var tableRef in tableRefs)
            {
                completions.Add(new SqlAliasCompletionData
                {
                    AliasName = tableRef.Identifier,
                    TableName = tableRef.TableName,
                    SchemaName = tableRef.SchemaName,
                    Priority = 4.0,
                    OnCompleted = _triggerCompletionCallback
                });
            }
            return completions;
        }
        
        // Single table - show columns
        if (tableRefs.Count == 1)
        {
            return GetColumnsForTable(tableRefs[0].FullName, null);
        }
        
        // Default: show * 
        completions.Add(new SqlStarCompletionData());
        
        return completions;
    }
    
    /// <summary>
    /// Get columns for a specific table, optionally prefixed with alias/table name.
    /// Loads columns synchronously if not cached (with timeout).
    /// </summary>
    private List<ICompletionData> GetColumnsForTable(string fullTableName, string? prefix)
    {
        var completions = new List<ICompletionData>();
        
        // Try to load columns on-demand if not cached - wait for it to complete
        if (!_tableColumns.ContainsKey(fullTableName) && _currentConnection != null)
        {
            Logger.Debug("Loading columns on-demand (sync) for {Table}", fullTableName);
            
            try
            {
                // Wait for column loading with a reasonable timeout (2 seconds)
                var loadTask = LoadColumnsForTableAsync(_currentConnection, fullTableName);
                if (loadTask.Wait(TimeSpan.FromSeconds(2)))
                {
                    Logger.Debug("Column loading completed for {Table}", fullTableName);
                }
                else
                {
                    Logger.Warn("Column loading timed out for {Table}", fullTableName);
                }
            }
            catch (Exception ex)
            {
                Logger.Warn(ex, "On-demand column loading failed for {Table}", fullTableName);
            }
        }
        
        if (_tableColumns.TryGetValue(fullTableName, out var columns))
        {
            Logger.Debug("Found {Count} columns for {Table}", columns.Count, fullTableName);
            
            completions.AddRange(columns.Select(c => new SqlColumnCompletionData
            {
                ColumnName = c.Name,
                DataType = c.DataType,
                IsNullable = c.IsNullable,
                IsPrimaryKey = c.IsPrimaryKey,
                TableName = fullTableName,
                Priority = 3.0
            }));
        }
        else
        {
            Logger.Debug("No columns available for {Table}", fullTableName);
        }
        
        // Always add * at the end as fallback
        if (completions.Count == 0)
        {
            completions.Add(new SqlStarCompletionData());
        }
        
        return completions;
    }
    
    private List<ICompletionData> GetFunctionCompletions()
    {
        var completions = new List<ICompletionData>();
        
        completions.AddRange(_functions.Select(f => new SqlFunctionCompletionData
        {
            Text = f,
            Description = $"Function: {f}",
            Priority = 2.0
        }));
        
        completions.AddRange(_functionNames.Select(f => new SqlFunctionCompletionData
        {
            Text = f,
            Description = $"User Function: {f}",
            Priority = 2.5
        }));
        
        return completions;
    }
    
    private List<ICompletionData> GetDataTypeCompletions()
    {
        return _dataTypes
            .Select(dt => new SqlDataTypeCompletionData
            {
                Text = dt,
                Description = $"Data Type: {dt}",
                Priority = 1.5
            })
            .Cast<ICompletionData>()
            .ToList();
    }
    
    private List<ICompletionData> GetSystemCatalogCompletions()
    {
        return _systemTables
            .Select(st => new SqlSystemTableCompletionData
            {
                Text = st,
                Description = $"System Table: {st}",
                Priority = 2.0
            })
            .Cast<ICompletionData>()
            .ToList();
    }
    
    private List<ICompletionData> GetSnippetCompletions()
    {
        return _snippets
            .Select(s => new SqlSnippetCompletionData
            {
                Trigger = s.Value.Trigger,
                Template = s.Value.Template,
                Description = s.Value.Description,
                Text = s.Value.Trigger,
                Priority = 1.5
            })
            .Cast<ICompletionData>()
            .ToList();
    }
    
    private List<ICompletionData> GetGeneralCompletions()
    {
        var completions = new List<ICompletionData>();
        
        // Add schemas at the top with highest priority
        completions.AddRange(_schemaNames.Select(s => new SqlSchemaCompletionData
        {
            Text = s,
            Description = $"Schema: {s}",
            Priority = 3.0 // Higher priority than tables/keywords
        }));
        
        completions.AddRange(GetKeywordCompletions().Take(20));
        completions.AddRange(GetSnippetCompletions().Take(10));
        completions.AddRange(GetTableNameCompletions().Take(10));
        return completions;
    }
    
    /// <summary>
    /// Get completions for objects within a specific schema (after schema.period)
    /// </summary>
    private List<ICompletionData> GetSchemaObjectCompletions(string text, int caretPosition)
    {
        var completions = new List<ICompletionData>();
        
        try
        {
            var textBeforeCaret = text.Substring(0, Math.Min(caretPosition, text.Length));
            var schemaObjectMatch = Regex.Match(textBeforeCaret, @"(\w+)\.$");
            
            if (schemaObjectMatch.Success)
            {
                var schemaName = schemaObjectMatch.Groups[1].Value;
                Logger.Debug("Showing objects for schema: {Schema}", schemaName);
                
                // Filter tables by schema
                var schemaTables = _tableNames
                    .Where(t => t.StartsWith($"{schemaName}.", StringComparison.OrdinalIgnoreCase))
                    .Select(t => t.Substring(t.IndexOf('.') + 1)) // Remove schema prefix
                    .Select(t => new SqlTableCompletionData
                    {
                        Text = t,
                        Description = $"Table: {schemaName}.{t}",
                        Priority = 3.0
                    });
                completions.AddRange(schemaTables);
                
                // Filter views by schema
                var schemaViews = _viewNames
                    .Where(v => v.StartsWith($"{schemaName}.", StringComparison.OrdinalIgnoreCase))
                    .Select(v => v.Substring(v.IndexOf('.') + 1)) // Remove schema prefix
                    .Select(v => new SqlViewCompletionData
                    {
                        Text = v,
                        Description = $"View: {schemaName}.{v}",
                        Priority = 2.5
                    });
                completions.AddRange(schemaViews);
                
                // Filter procedures by schema
                var schemaProcedures = _procedureNames
                    .Where(p => p.StartsWith($"{schemaName}.", StringComparison.OrdinalIgnoreCase))
                    .Select(p => p.Substring(p.IndexOf('.') + 1)) // Remove schema prefix
                    .Select(p => new SqlProcedureCompletionData
                    {
                        Text = p,
                        Description = $"Procedure: {schemaName}.{p}",
                        Priority = 2.0
                    });
                completions.AddRange(schemaProcedures);
                
                Logger.Debug("Found {Count} objects in schema {Schema}", completions.Count, schemaName);
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to get schema object completions");
        }
        
        return completions;
    }
    
    private List<string> ExtractTableNamesFromQuery(string sql)
    {
        // Delegate to the new method for backward compatibility
        return ExtractTableReferencesWithAliases(sql)
            .Select(r => r.FullName)
            .Distinct()
            .ToList();
    }
    
    /// <summary>
    /// Extract table references with their aliases from SQL query.
    /// Parses: FROM schema.table alias, schema.table AS alias
    /// Also handles: JOIN schema.table alias ON ...
    /// </summary>
    private List<TableReference> ExtractTableReferencesWithAliases(string sql)
    {
        var tableRefs = new List<TableReference>();
        
        try
        {
            // Normalize the SQL (remove extra whitespace, keep original case for table/alias names)
            var normalizedSql = Regex.Replace(sql, @"\s+", " ");
            
            // Regex explanation for table references:
            // Pattern matches: FROM/JOIN followed by:
            //   - schema.table (captured in group 1 & 2)
            //   - optionally followed by AS? alias (captured in group 3 or 4)
            // 
            // Examples:
            //   FROM DBM.TABLE1 t1           -> schema=DBM, table=TABLE1, alias=t1
            //   FROM DBM.TABLE1 AS t1        -> schema=DBM, table=TABLE1, alias=t1
            //   FROM DBM.TABLE1              -> schema=DBM, table=TABLE1, alias=null
            //   JOIN DBM.TABLE2 t2 ON ...    -> schema=DBM, table=TABLE2, alias=t2
            //   FROM TABLE1, TABLE2          -> tables without schema
            
            // Pattern for: FROM/JOIN schema.table [AS] alias
            // Also handles comma-separated tables: FROM t1, t2
            var tablePattern = @"(?:FROM|JOIN)\s+([A-Z0-9_]+)\.([A-Z0-9_]+)(?:\s+(?:AS\s+)?([A-Z0-9_]+))?";
            var matches = Regex.Matches(normalizedSql, tablePattern, RegexOptions.IgnoreCase);
            
            foreach (Match match in matches)
            {
                var schemaName = match.Groups[1].Value.Trim();
                var tableName = match.Groups[2].Value.Trim();
                var alias = match.Groups[3].Success ? match.Groups[3].Value.Trim() : null;
                
                // Exclude SQL keywords that might be mistaken for aliases
                if (alias != null && IsSqlKeyword(alias))
                {
                    alias = null;
                }
                
                tableRefs.Add(new TableReference
                {
                    FullName = $"{schemaName}.{tableName}",
                    SchemaName = schemaName,
                    TableName = tableName,
                    Alias = alias
                });
                
                Logger.Debug("Extracted table: {Schema}.{Table} AS {Alias}", schemaName, tableName, alias ?? "(none)");
            }
            
            // Also handle comma-separated tables in FROM clause
            // Pattern: , schema.table [AS] alias (within FROM clause)
            var commaPattern = @",\s*([A-Z0-9_]+)\.([A-Z0-9_]+)(?:\s+(?:AS\s+)?([A-Z0-9_]+))?";
            var commaMatches = Regex.Matches(normalizedSql, commaPattern, RegexOptions.IgnoreCase);
            
            foreach (Match match in commaMatches)
            {
                // Verify this is in a FROM clause (basic check - comma before WHERE/JOIN/ORDER etc.)
                var matchPos = match.Index;
                var beforeMatch = normalizedSql.Substring(0, matchPos).ToUpperInvariant();
                
                // Check if we're between FROM and WHERE/JOIN/ORDER/GROUP/HAVING
                var fromPos = beforeMatch.LastIndexOf(" FROM ");
                if (fromPos < 0) continue;
                
                var afterFrom = beforeMatch.Substring(fromPos);
                if (afterFrom.Contains(" WHERE ") || afterFrom.Contains(" ORDER ") || 
                    afterFrom.Contains(" GROUP ") || afterFrom.Contains(" HAVING ") ||
                    afterFrom.Contains(" JOIN "))
                    continue;
                
                var schemaName = match.Groups[1].Value.Trim();
                var tableName = match.Groups[2].Value.Trim();
                var alias = match.Groups[3].Success ? match.Groups[3].Value.Trim() : null;
                
                if (alias != null && IsSqlKeyword(alias))
                {
                    alias = null;
                }
                
                // Check if we already have this table
                var fullName = $"{schemaName}.{tableName}";
                if (!tableRefs.Any(t => t.FullName.Equals(fullName, StringComparison.OrdinalIgnoreCase)))
                {
                    tableRefs.Add(new TableReference
                    {
                        FullName = fullName,
                        SchemaName = schemaName,
                        TableName = tableName,
                        Alias = alias
                    });
                    
                    Logger.Debug("Extracted comma table: {Schema}.{Table} AS {Alias}", schemaName, tableName, alias ?? "(none)");
                }
            }
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "Failed to extract table references from query");
        }
        
        return tableRefs;
    }
    
    /// <summary>
    /// Check if a word is a SQL keyword (to avoid treating keywords as aliases).
    /// </summary>
    private bool IsSqlKeyword(string word)
    {
        var keywords = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "WHERE", "AND", "OR", "ON", "JOIN", "INNER", "LEFT", "RIGHT", "FULL", "CROSS", "OUTER",
            "ORDER", "BY", "GROUP", "HAVING", "UNION", "EXCEPT", "INTERSECT", "FETCH", "FIRST",
            "ROWS", "ONLY", "FOR", "UPDATE", "OF", "SET", "VALUES", "INTO", "SELECT", "FROM",
            "AS", "WITH", "DISTINCT", "ALL", "LIMIT", "OFFSET", "NULL", "NOT", "IN", "EXISTS",
            "BETWEEN", "LIKE", "IS", "CASE", "WHEN", "THEN", "ELSE", "END", "ASC", "DESC"
        };
        
        return keywords.Contains(word);
    }
}

/// <summary>
/// SQL context types for intelligent completion.
/// </summary>
public enum SqlContext
{
    Keyword,
    Schema,           // Show schemas first (after FROM, JOIN, INTO, UPDATE)
    TableName,        // Legacy - use SchemaObject instead
    ColumnName,       // Show columns (after SELECT, WHERE, AND, OR)
    Function,
    DataType,
    SystemCatalog,
    Snippet,
    General,
    SchemaObject,     // Show tables/views in a specific schema (after SCHEMA.)
    JoinCondition,    // Show columns for ON clause
    OrderByColumn,    // Show columns for ORDER BY
    Alias             // Expecting alias name
}

#region Legacy Compatibility

/// <summary>
/// Legacy keywords metadata structure (for backward compatibility with db2_12.1_keywords.json).
/// </summary>
public class LegacyKeywordsMetadata
{
    public string Provider { get; set; } = string.Empty;
    public string Version { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public LegacyKeywordCategories? Keywords { get; set; }
    
    public List<string> GetAllKeywords()
    {
        var all = new List<string>();
        if (Keywords != null)
        {
            if (Keywords.Statements != null) all.AddRange(Keywords.Statements);
            if (Keywords.Clauses != null) all.AddRange(Keywords.Clauses);
            if (Keywords.Operators != null) all.AddRange(Keywords.Operators);
            if (Keywords.Constraints != null) all.AddRange(Keywords.Constraints);
            if (Keywords.Modifiers != null) all.AddRange(Keywords.Modifiers);
        }
        return all.Distinct().ToList();
    }
}

public class LegacyKeywordCategories
{
    public List<string>? Statements { get; set; }
    public List<string>? Clauses { get; set; }
    public List<string>? Datatypes { get; set; }
    public List<string>? Functions { get; set; }
    public List<string>? Operators { get; set; }
    
    [System.Text.Json.Serialization.JsonPropertyName("system_tables")]
    public List<string>? SystemTables { get; set; }
    
    public List<string>? Constraints { get; set; }
    public List<string>? Modifiers { get; set; }
}

/// <summary>
/// Alias for backward compatibility - redirects to SqlIntelliSenseProvider.
/// </summary>
public class Db2IntelliSenseProvider : SqlIntelliSenseProvider
{
    public Db2IntelliSenseProvider() : base()
    {
    }
}

#endregion
