using System.Collections.Generic;

namespace DbExplorer.Models;

/// <summary>
/// Ignore JSON model for Missing FK Discovery.
/// Defines tables, columns, and patterns to exclude from analysis.
/// </summary>
public class MissingFKIgnoreModel
{
    /// <summary>
    /// Tables to ignore. Supports wildcards (*) in schema and name.
    /// Example: { "schema": "SYSIBM", "name": "*" } ignores all tables in SYSIBM schema.
    /// </summary>
    public List<TableReference> IgnoreTables { get; set; } = new();
    
    /// <summary>
    /// Columns to ignore. Supports wildcards (*) in schema, table, and name.
    /// Example: { "schema": "*", "table": "*", "name": "CREATED_BY" } ignores CREATED_BY in all tables.
    /// </summary>
    public List<MissingFKIgnoreColumn> IgnoreColumns { get; set; } = new();
    
    /// <summary>
    /// Regex patterns for column names to ignore.
    /// Patterns are applied to column names only (not schema.table.column).
    /// Example: "^TMP_" ignores columns starting with TMP_.
    /// </summary>
    public List<string> IgnoreColumnPatterns { get; set; } = new();
    
    /// <summary>
    /// Data types to ignore during analysis.
    /// Example: ["BLOB", "CLOB", "XML"] excludes these data types.
    /// </summary>
    public List<string> IgnoreDataTypes { get; set; } = new();
}

/// <summary>
/// Column reference for ignore rules.
/// </summary>
public class MissingFKIgnoreColumn
{
    public string Schema { get; set; } = string.Empty;
    public string Table { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
}
