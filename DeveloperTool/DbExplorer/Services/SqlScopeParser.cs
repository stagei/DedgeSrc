using NLog;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace DbExplorer.Services;

/// <summary>
/// Parses SQL into nested scopes based on parentheses depth.
/// Each scope contains its own aliases, tables, and exposed columns.
/// </summary>
public class SqlScopeParser
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    /// <summary>
    /// Parse SQL text into an array of scopes indexed by nesting level.
    /// Index 0 = main query, Index N = Nth level of nesting.
    /// </summary>
    public List<SqlScope> Parse(string sql)
    {
        if (string.IsNullOrWhiteSpace(sql))
            return new List<SqlScope> { CreateEmptyScope(0) };
        
        var scopes = new List<SqlScope>();
        var parenStack = new Stack<ParenInfo>();
        
        // First, create the main scope (level 0)
        var mainScope = new SqlScope
        {
            Level = 0,
            Index = 0,
            StartPosition = 0,
            EndPosition = sql.Length,
            Content = sql
        };
        scopes.Add(mainScope);
        
        // Find all parentheses and identify subselects
        int scopeIndex = 1;
        for (int i = 0; i < sql.Length; i++)
        {
            if (sql[i] == '(')
            {
                parenStack.Push(new ParenInfo { Position = i, Level = parenStack.Count + 1 });
            }
            else if (sql[i] == ')' && parenStack.Count > 0)
            {
                var openParen = parenStack.Pop();
                var content = sql.Substring(openParen.Position + 1, i - openParen.Position - 1).Trim();
                
                // Check if this is a subselect (starts with SELECT)
                if (content.StartsWith("SELECT", StringComparison.OrdinalIgnoreCase))
                {
                    // Find alias after closing paren
                    var alias = FindAliasAfterParen(sql, i);
                    
                    var scope = new SqlScope
                    {
                        Level = openParen.Level,
                        Index = scopeIndex++,
                        StartPosition = openParen.Position,
                        EndPosition = i,
                        Content = content,
                        Alias = alias,
                        ParentIndex = FindParentScopeIndex(scopes, openParen.Position)
                    };
                    
                    // Parse the SQL parts
                    ParseSqlParts(scope);
                    
                    scopes.Add(scope);
                    Logger.Debug("Found subselect at level {Level}, alias: {Alias}, index: {Index}", 
                        scope.Level, scope.Alias ?? "(none)", scope.Index);
                }
            }
        }
        
        // Parse the main scope's SQL parts (excluding subselect content)
        ParseSqlParts(mainScope);
        
        // Build relationships: link derived tables to their scopes
        LinkDerivedTables(scopes);
        
        // Extract exposed columns for each scope
        foreach (var scope in scopes)
        {
            scope.ExposedColumns = ExtractSelectColumns(scope.SelectPart);
        }
        
        Logger.Info("Parsed {Count} scopes from SQL", scopes.Count);
        return scopes;
    }
    
    /// <summary>
    /// Find the scope that contains the given caret position.
    /// Returns the innermost (deepest) scope.
    /// </summary>
    public SqlScope? GetScopeAtPosition(List<SqlScope> scopes, int caretPosition)
    {
        return scopes
            .Where(s => caretPosition >= s.StartPosition && caretPosition <= s.EndPosition)
            .OrderByDescending(s => s.Level)
            .FirstOrDefault();
    }
    
    /// <summary>
    /// Get all aliases and columns visible at the given scope.
    /// </summary>
    public ScopeVisibility GetVisibleItems(List<SqlScope> scopes, SqlScope currentScope)
    {
        Logger.Debug("GetVisibleItems: Scope level {Level}, {TableCount} tables in scope", 
            currentScope.Level, currentScope.Tables.Count);
        
        var visibility = new ScopeVisibility();
        
        // Add aliases from current scope
        foreach (var table in currentScope.Tables)
        {
            var aliasName = table.Alias ?? table.TableName ?? "(unknown)";
            Logger.Debug("  Adding visible alias: '{Alias}' -> Schema={Schema}, Table={Table}, IsDerived={IsDerived}",
                aliasName, table.Schema ?? "(null)", table.TableName ?? "(null)", table.IsDerivedTable);
            
            visibility.Aliases.Add(new VisibleAlias
            {
                Name = aliasName,
                FullTableName = table.FullName,
                IsDerivedTable = table.IsDerivedTable,
                SourceScopeIndex = currentScope.Index
            });
        }
        
        // Add columns from regular tables at current scope
        foreach (var table in currentScope.Tables.Where(t => !t.IsDerivedTable))
        {
            visibility.TableColumns.Add(new TableColumnSet
            {
                Alias = table.Alias ?? table.TableName,
                FullTableName = table.FullName,
                // Columns will be loaded from database
            });
        }
        
        // Add EXPOSED columns from derived tables (subselects)
        foreach (var derivedTable in currentScope.Tables.Where(t => t.IsDerivedTable && t.DerivedTableScopeIndex.HasValue))
        {
            var childScope = scopes.FirstOrDefault(s => s.Index == derivedTable.DerivedTableScopeIndex.Value);
            if (childScope != null)
            {
                visibility.DerivedTableColumns.Add(new DerivedTableColumnSet
                {
                    Alias = derivedTable.Alias ?? childScope.Alias ?? "subquery",
                    ExposedColumns = childScope.ExposedColumns,
                    ScopeIndex = childScope.Index
                });
            }
        }
        
        // For correlated subqueries: add parent scope aliases
        if (currentScope.Level > 0 && currentScope.ParentIndex.HasValue)
        {
            var parentScope = scopes.FirstOrDefault(s => s.Index == currentScope.ParentIndex.Value);
            if (parentScope != null)
            {
                foreach (var table in parentScope.Tables)
                {
                    visibility.ParentAliases.Add(new VisibleAlias
                    {
                        Name = table.Alias ?? table.TableName,
                        FullTableName = table.FullName,
                        IsDerivedTable = table.IsDerivedTable,
                        SourceScopeIndex = parentScope.Index,
                        IsFromParentScope = true
                    });
                }
            }
        }
        
        return visibility;
    }
    
    #region Private Helpers
    
    private SqlScope CreateEmptyScope(int level)
    {
        return new SqlScope
        {
            Level = level,
            Index = 0,
            StartPosition = 0,
            EndPosition = 0,
            Content = string.Empty
        };
    }
    
    private string? FindAliasAfterParen(string sql, int closeParenPos)
    {
        // Look for alias pattern after ) : ") alias" or ") AS alias"
        var afterParen = sql.Substring(closeParenPos + 1).TrimStart();
        
        // Pattern: optional AS followed by identifier, then space or ON or WHERE or comma
        var aliasMatch = Regex.Match(afterParen, @"^(?:AS\s+)?([A-Z_][A-Z0-9_]*)\s*(?:ON|WHERE|,|$|\))", 
            RegexOptions.IgnoreCase);
        
        if (aliasMatch.Success)
        {
            var potentialAlias = aliasMatch.Groups[1].Value;
            
            // Exclude SQL keywords
            if (!IsSqlKeyword(potentialAlias))
            {
                return potentialAlias;
            }
        }
        
        return null;
    }
    
    private int? FindParentScopeIndex(List<SqlScope> scopes, int position)
    {
        // Find the scope that contains this position (but is not this scope)
        var parent = scopes
            .Where(s => position > s.StartPosition && position < s.EndPosition)
            .OrderByDescending(s => s.Level)
            .FirstOrDefault();
        
        return parent?.Index;
    }
    
    private void ParseSqlParts(SqlScope scope)
    {
        var content = scope.Content;
        if (string.IsNullOrWhiteSpace(content))
            return;
        
        // Remove nested subselects for parsing (replace with placeholder)
        var contentWithoutNested = RemoveNestedSubselects(content);
        
        // Extract SELECT part
        var selectMatch = Regex.Match(contentWithoutNested, 
            @"SELECT\s+(DISTINCT\s+)?(.*?)(?=\s+FROM\s+|$)", 
            RegexOptions.IgnoreCase | RegexOptions.Singleline);
        if (selectMatch.Success)
        {
            scope.SelectPart = selectMatch.Groups[2].Value.Trim();
        }
        
        // Extract FROM part (up to WHERE, ORDER, GROUP, HAVING, or end)
        var fromMatch = Regex.Match(contentWithoutNested,
            @"FROM\s+(.*?)(?=\s+WHERE\s+|\s+ORDER\s+|\s+GROUP\s+|\s+HAVING\s+|\s+UNION\s+|\s+INTERSECT\s+|\s+EXCEPT\s+|$)",
            RegexOptions.IgnoreCase | RegexOptions.Singleline);
        if (fromMatch.Success)
        {
            scope.FromPart = fromMatch.Groups[1].Value.Trim();
            scope.Tables = ParseFromClause(scope.FromPart);
            Logger.Debug("Scope {Index}: FromPart='{From}' -> {TableCount} tables parsed",
                scope.Index, scope.FromPart.Substring(0, Math.Min(50, scope.FromPart.Length)), scope.Tables.Count);
        }
        
        // Extract WHERE part
        var whereMatch = Regex.Match(contentWithoutNested,
            @"WHERE\s+(.*?)(?=\s+ORDER\s+|\s+GROUP\s+|\s+HAVING\s+|\s+UNION\s+|$)",
            RegexOptions.IgnoreCase | RegexOptions.Singleline);
        if (whereMatch.Success)
        {
            scope.WherePart = whereMatch.Groups[1].Value.Trim();
        }
    }
    
    private string RemoveNestedSubselects(string sql)
    {
        // Replace nested subselects with placeholder to simplify parsing
        var result = sql;
        int depth = 0;
        int subStart = -1;
        
        for (int i = 0; i < result.Length; i++)
        {
            if (result[i] == '(')
            {
                if (depth == 0)
                {
                    // Check if this starts a subselect
                    var after = result.Substring(i + 1).TrimStart();
                    if (after.StartsWith("SELECT", StringComparison.OrdinalIgnoreCase))
                    {
                        subStart = i;
                    }
                }
                depth++;
            }
            else if (result[i] == ')')
            {
                depth--;
                if (depth == 0 && subStart >= 0)
                {
                    // Replace subselect with placeholder
                    var placeholder = "(__SUBSELECT__)";
                    result = result.Substring(0, subStart) + placeholder + result.Substring(i + 1);
                    i = subStart + placeholder.Length - 1;
                    subStart = -1;
                }
            }
        }
        
        return result;
    }
    
    private List<ScopeTableReference> ParseFromClause(string fromPart)
    {
        var tables = new List<ScopeTableReference>();
        
        // Pattern for table references: schema.table [AS] alias
        // Also handles: (__SUBSELECT__) [AS] alias
        var pattern = @"(?:^|JOIN\s+|,\s*)(?:([A-Z_][A-Z0-9_]*)\.)?([A-Z_][A-Z0-9_]*|\(__SUBSELECT__\))(?:\s+(?:AS\s+)?([A-Z_][A-Z0-9_]*))?";
        var matches = Regex.Matches(fromPart, pattern, RegexOptions.IgnoreCase);
        
        foreach (Match match in matches)
        {
            var schema = match.Groups[1].Success ? match.Groups[1].Value : null;
            var tableName = match.Groups[2].Value;
            var alias = match.Groups[3].Success ? match.Groups[3].Value : null;
            
            // Skip SQL keywords that might be captured
            if (IsSqlKeyword(tableName) || (alias != null && IsSqlKeyword(alias)))
                continue;
            
            var isSubselect = tableName == "(__SUBSELECT__)";
            
            tables.Add(new ScopeTableReference
            {
                Schema = schema,
                TableName = isSubselect ? null : tableName,
                Alias = alias,
                IsDerivedTable = isSubselect
            });
        }
        
        return tables;
    }
    
    private void LinkDerivedTables(List<SqlScope> scopes)
    {
        // Link derived tables in parent scopes to their child scope indices
        foreach (var scope in scopes)
        {
            foreach (var table in scope.Tables.Where(t => t.IsDerivedTable))
            {
                // Find the child scope by matching alias
                var childScope = scopes.FirstOrDefault(s => 
                    s.ParentIndex == scope.Index && 
                    (s.Alias == table.Alias || (s.Alias == null && table.Alias != null)));
                
                if (childScope != null)
                {
                    table.DerivedTableScopeIndex = childScope.Index;
                }
                else if (table.Alias != null)
                {
                    // Try to find by alias match
                    childScope = scopes.FirstOrDefault(s => s.Alias == table.Alias && s.Index != scope.Index);
                    if (childScope != null)
                    {
                        table.DerivedTableScopeIndex = childScope.Index;
                    }
                }
            }
        }
    }
    
    private List<string> ExtractSelectColumns(string? selectPart)
    {
        var columns = new List<string>();
        if (string.IsNullOrWhiteSpace(selectPart))
            return columns;
        
        // Split by comma (but not commas inside functions)
        var parts = SplitSelectColumns(selectPart);
        
        foreach (var part in parts)
        {
            var trimmed = part.Trim();
            if (string.IsNullOrEmpty(trimmed) || trimmed == "*")
                continue;
            
            // Check for "expr AS alias" or "expr alias" pattern
            var aliasMatch = Regex.Match(trimmed, @"\s+(?:AS\s+)?([A-Z_][A-Z0-9_]*)$", RegexOptions.IgnoreCase);
            if (aliasMatch.Success)
            {
                var alias = aliasMatch.Groups[1].Value;
                if (!IsSqlKeyword(alias))
                {
                    columns.Add(alias);
                    continue;
                }
            }
            
            // Check for "table.column" - extract column name
            var qualifiedMatch = Regex.Match(trimmed, @"^[A-Z_][A-Z0-9_]*\.([A-Z_][A-Z0-9_]*)$", RegexOptions.IgnoreCase);
            if (qualifiedMatch.Success)
            {
                columns.Add(qualifiedMatch.Groups[1].Value);
                continue;
            }
            
            // Simple column name
            var simpleMatch = Regex.Match(trimmed, @"^([A-Z_][A-Z0-9_]*)$", RegexOptions.IgnoreCase);
            if (simpleMatch.Success)
            {
                columns.Add(simpleMatch.Groups[1].Value);
            }
        }
        
        return columns;
    }
    
    private List<string> SplitSelectColumns(string selectPart)
    {
        var parts = new List<string>();
        int depth = 0;
        int start = 0;
        
        for (int i = 0; i < selectPart.Length; i++)
        {
            if (selectPart[i] == '(') depth++;
            else if (selectPart[i] == ')') depth--;
            else if (selectPart[i] == ',' && depth == 0)
            {
                parts.Add(selectPart.Substring(start, i - start));
                start = i + 1;
            }
        }
        
        // Add last part
        if (start < selectPart.Length)
        {
            parts.Add(selectPart.Substring(start));
        }
        
        return parts;
    }
    
    private bool IsSqlKeyword(string word)
    {
        var keywords = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "SELECT", "FROM", "WHERE", "JOIN", "INNER", "LEFT", "RIGHT", "FULL", "CROSS", "OUTER",
            "ON", "AND", "OR", "ORDER", "BY", "GROUP", "HAVING", "INSERT", "INTO", "UPDATE", "SET",
            "DELETE", "CREATE", "ALTER", "DROP", "TABLE", "VIEW", "INDEX", "AS", "DISTINCT", "VALUES",
            "UNION", "EXCEPT", "INTERSECT", "FETCH", "FIRST", "ROWS", "ONLY", "FOR", "NULL", "NOT",
            "IN", "EXISTS", "BETWEEN", "LIKE", "IS", "CASE", "WHEN", "THEN", "ELSE", "END", "ASC", "DESC"
        };
        return keywords.Contains(word);
    }
    
    #endregion
    
    private class ParenInfo
    {
        public int Position { get; set; }
        public int Level { get; set; }
    }
}

#region Models

/// <summary>
/// Represents a SQL scope (main query or subselect).
/// </summary>
public class SqlScope
{
    public int Level { get; set; }              // Nesting depth (0 = main)
    public int Index { get; set; }              // Unique index in scope array
    public int StartPosition { get; set; }      // Start position in SQL
    public int EndPosition { get; set; }        // End position in SQL
    public string Content { get; set; } = "";   // Full content of this scope
    public string? Alias { get; set; }          // Alias if derived table
    public int? ParentIndex { get; set; }       // Parent scope index
    
    public string? SelectPart { get; set; }
    public string? FromPart { get; set; }
    public string? WherePart { get; set; }
    
    public List<ScopeTableReference> Tables { get; set; } = new();
    public List<string> ExposedColumns { get; set; } = new();  // Columns exposed to parent scope
}

/// <summary>
/// Table reference within a scope.
/// </summary>
public class ScopeTableReference
{
    public string? Schema { get; set; }
    public string? TableName { get; set; }
    public string? Alias { get; set; }
    public bool IsDerivedTable { get; set; }
    public int? DerivedTableScopeIndex { get; set; }  // For derived tables, index of child scope
    
    public string FullName => Schema != null ? $"{Schema}.{TableName}" : TableName ?? "";
}

/// <summary>
/// What's visible at a given scope.
/// </summary>
public class ScopeVisibility
{
    public List<VisibleAlias> Aliases { get; set; } = new();
    public List<VisibleAlias> ParentAliases { get; set; } = new();  // For correlated subqueries
    public List<TableColumnSet> TableColumns { get; set; } = new();
    public List<DerivedTableColumnSet> DerivedTableColumns { get; set; } = new();
}

public class VisibleAlias
{
    public string Name { get; set; } = "";
    public string FullTableName { get; set; } = "";
    public bool IsDerivedTable { get; set; }
    public int SourceScopeIndex { get; set; }
    public bool IsFromParentScope { get; set; }
}

public class TableColumnSet
{
    public string Alias { get; set; } = "";
    public string FullTableName { get; set; } = "";
    public List<string> Columns { get; set; } = new();  // Loaded from DB
}

public class DerivedTableColumnSet
{
    public string Alias { get; set; } = "";
    public List<string> ExposedColumns { get; set; } = new();
    public int ScopeIndex { get; set; }
}

#endregion
