using System;
using System.Collections.Generic;
using System.Linq;
using NLog;

namespace DbExplorer.Services;

/// <summary>
/// Model for SQL completion item
/// </summary>
public class SqlCompletionItem
{
    public string Text { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty; // TABLE, COLUMN, KEYWORD, FUNCTION
    public double Priority { get; set; }
}

/// <summary>
/// Provider for SQL IntelliSense completion data
/// </summary>
public class SqlCompletionDataProvider
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly MetadataLoaderService _metadataLoader;
    private List<SqlCompletionItem> _cachedCompletions = new();
    
    public SqlCompletionDataProvider(MetadataLoaderService metadataLoader)
    {
        _metadataLoader = metadataLoader;
        Logger.Debug("SqlCompletionDataProvider initialized");
    }
    
    /// <summary>
    /// Get SQL keyword completions
    /// </summary>
    public List<SqlCompletionItem> GetKeywordCompletions()
    {
        Logger.Debug("Getting keyword completions");
        
        var keywords = new[]
        {
            "SELECT", "FROM", "WHERE", "JOIN", "INNER JOIN", "LEFT JOIN", "RIGHT JOIN",
            "ORDER BY", "GROUP BY", "HAVING", "INSERT INTO", "UPDATE", "DELETE FROM",
            "CREATE TABLE", "ALTER TABLE", "DROP TABLE", "UNION", "UNION ALL",
            "AS", "ON", "AND", "OR", "NOT", "IN", "EXISTS", "BETWEEN", "LIKE",
            "COUNT", "SUM", "AVG", "MIN", "MAX", "DISTINCT", "FETCH FIRST", "ROWS ONLY"
        };
        
        return keywords.Select(kw => new SqlCompletionItem
        {
            Text = kw,
            Description = "SQL Keyword",
            Category = "KEYWORD",
            Priority = 0.5
        }).ToList();
    }
    
    /// <summary>
    /// Get DB2 system function completions
    /// </summary>
    public List<SqlCompletionItem> GetSystemFunctionCompletions()
    {
        Logger.Debug("Getting system function completions");
        
        var functions = new[]
        {
            "CURRENT DATE", "CURRENT TIME", "CURRENT TIMESTAMP",
            "CURRENT USER", "SESSION_USER", "SYSTEM_USER",
            "LENGTH", "SUBSTR", "TRIM", "UPPER", "LOWER",
            "COALESCE", "NULLIF", "CAST", "DECIMAL", "VARCHAR",
            "DAYS", "MONTHS", "YEARS", "TIMESTAMP", "DATE"
        };
        
        return functions.Select(fn => new SqlCompletionItem
        {
            Text = fn,
            Description = "DB2 Function",
            Category = "FUNCTION",
            Priority = 0.7
        }).ToList();
    }
    
    /// <summary>
    /// Get SYSCAT table completions
    /// </summary>
    public List<SqlCompletionItem> GetSyscatTableCompletions()
    {
        Logger.Debug("Getting SYSCAT table completions");
        
        var syscatTables = new[]
        {
            "SYSCAT.TABLES", "SYSCAT.COLUMNS", "SYSCAT.INDEXES",
            "SYSCAT.KEYCOLUSE", "SYSCAT.REFERENCES", "SYSCAT.VIEWS",
            "SYSCAT.ROUTINES", "SYSCAT.TRIGGERS", "SYSCAT.SCHEMATA",
            "SYSCAT.PACKAGES", "SYSCAT.STATEMENTS", "SYSCAT.TABDEP"
        };
        
        return syscatTables.Select(tbl => new SqlCompletionItem
        {
            Text = tbl,
            Description = "System Catalog Table",
            Category = "TABLE",
            Priority = 0.8
        }).ToList();
    }
    
    /// <summary>
    /// Get all completions (keywords + functions + cached schema objects)
    /// </summary>
    public List<SqlCompletionItem> GetAllCompletions()
    {
        Logger.Debug("Getting all completions");
        
        var completions = new List<SqlCompletionItem>();
        
        completions.AddRange(GetKeywordCompletions());
        completions.AddRange(GetSystemFunctionCompletions());
        completions.AddRange(GetSyscatTableCompletions());
        completions.AddRange(_cachedCompletions);
        
        Logger.Debug("Total completions: {Count}", completions.Count);
        return completions;
    }
    
    /// <summary>
    /// Cache schema and table names for completion
    /// </summary>
    public void CacheSchemaObjects(List<TableMetadata> tables)
    {
        Logger.Info("Caching {Count} tables for completion", tables.Count);
        
        _cachedCompletions.Clear();
        
        foreach (var table in tables)
        {
            _cachedCompletions.Add(new SqlCompletionItem
            {
                Text = $"{table.Schema}.{table.Name}",
                Description = $"Table: {table.Type}",
                Category = "TABLE",
                Priority = 1.0
            });
        }
        
        Logger.Info("Cached {Count} completion items", _cachedCompletions.Count);
    }
}

