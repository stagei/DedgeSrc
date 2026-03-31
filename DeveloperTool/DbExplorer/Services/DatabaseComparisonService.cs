using NLog;
using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using DbExplorer.Data;

namespace DbExplorer.Services;

// MetadataHandler reference for provider-agnostic queries

/// <summary>
/// Service for comparing database objects across multiple databases.
/// Uses IConnectionManager factory methods for database-agnostic operation.
/// </summary>
public class DatabaseComparisonService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly MetadataHandler? _metadataHandler;
    
    public DatabaseComparisonService(MetadataHandler? metadataHandler = null)
    {
        _metadataHandler = metadataHandler ?? App.MetadataHandler;
    }
    
    /// <summary>
    /// Compare table structures across multiple databases.
    /// </summary>
    public async Task<TableComparisonResult> CompareTablesAsync(
        MultiDatabaseConnectionManager connections,
        List<string> databaseAliases,
        string schema,
        string tableName)
    {
        Logger.Info("Comparing table {Schema}.{Table} across {Count} databases",
                   schema, tableName, databaseAliases.Count);
        
        var result = new TableComparisonResult
        {
            Schema = schema,
            TableName = tableName,
            DatabaseAliases = databaseAliases
        };
        
        // Fetch table definitions from each database
        foreach (var alias in databaseAliases)
        {
            var connection = connections.GetConnection(alias);
            if (connection == null)
            {
                Logger.Warn("Connection not found: {Alias}", alias);
                continue;
            }
            
            try
            {
                var tableDef = await FetchTableDefinitionAsync(connection, schema, tableName);
                result.TableDefinitions[alias] = tableDef;
                Logger.Debug("Fetched table definition from {Alias}: {ColumnCount} columns",
                           alias, tableDef.Columns.Count);
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Failed to fetch table definition from {Alias}", alias);
            }
        }
        
        // Analyze differences
        AnalyzeDifferences(result);
        
        return result;
    }
    
    /// <summary>
    /// Fetch table definition from a database.
    /// </summary>
    private async Task<TableDefinition> FetchTableDefinitionAsync(
        IConnectionManager connection,
        string schema,
        string tableName)
    {
        var tableDef = new TableDefinition
        {
            Schema = schema,
            TableName = tableName
        };
        
        // Fetch columns
        var columnsSql = _metadataHandler?.GetStatement("COMPARE_GetTableColumns") 
            ?? @"SELECT COLNAME, TYPENAME, LENGTH, SCALE, NULLS, DEFAULT, IDENTITY
            FROM SYSCAT.COLUMNS
            WHERE TABSCHEMA = ? AND TABNAME = ?
            ORDER BY COLNO";
        
        using (var cmd = connection.CreateCommand(columnsSql))
        {
            cmd.Parameters.Add(connection.CreateParameter("@schema", schema));
            cmd.Parameters.Add(connection.CreateParameter("@table", tableName));
            
            using var adapter = connection.CreateDataAdapter(cmd);
            var dt = new DataTable();
            await Task.Run(() => adapter.Fill(dt));
            
            foreach (DataRow row in dt.Rows)
            {
                tableDef.Columns.Add(new ColumnDefinition
                {
                    Name = row["COLNAME"].ToString()?.Trim() ?? string.Empty,
                    DataType = row["TYPENAME"].ToString()?.Trim() ?? string.Empty,
                    Length = row["LENGTH"] != DBNull.Value ? Convert.ToInt32(row["LENGTH"]) : 0,
                    Scale = row["SCALE"] != DBNull.Value ? Convert.ToInt32(row["SCALE"]) : 0,
                    IsNullable = row["NULLS"].ToString()?.Trim() == "Y",
                    DefaultValue = row["DEFAULT"]?.ToString()?.Trim(),
                    IsIdentity = row["IDENTITY"].ToString()?.Trim() == "Y"
                });
            }
        }
        
        // Fetch primary key
        var pkSql = _metadataHandler?.GetStatement("COMPARE_GetPrimaryKeyColumns") 
            ?? @"SELECT COLNAME
            FROM SYSCAT.KEYCOLUSE
            WHERE TABSCHEMA = ? AND TABNAME = ? AND CONSTNAME LIKE 'PK%'
            ORDER BY COLSEQ";
        
        using (var cmd = connection.CreateCommand(pkSql))
        {
            cmd.Parameters.Add(connection.CreateParameter("@schema", schema));
            cmd.Parameters.Add(connection.CreateParameter("@table", tableName));
            
            using var adapter = connection.CreateDataAdapter(cmd);
            var dt = new DataTable();
            await Task.Run(() => adapter.Fill(dt));
            
            foreach (DataRow row in dt.Rows)
            {
                tableDef.PrimaryKeyColumns.Add(row["COLNAME"].ToString()?.Trim() ?? string.Empty);
            }
        }
        
        // Fetch indexes
        var indexSql = _metadataHandler?.GetStatement("COMPARE_GetTableIndexes") 
            ?? @"SELECT INDNAME, UNIQUERULE, COLNAMES
            FROM SYSCAT.INDEXES
            WHERE TABSCHEMA = ? AND TABNAME = ?";
        
        using (var cmd = connection.CreateCommand(indexSql))
        {
            cmd.Parameters.Add(connection.CreateParameter("@schema", schema));
            cmd.Parameters.Add(connection.CreateParameter("@table", tableName));
            
            using var adapter = connection.CreateDataAdapter(cmd);
            var dt = new DataTable();
            await Task.Run(() => adapter.Fill(dt));
            
            foreach (DataRow row in dt.Rows)
            {
                tableDef.Indexes.Add(new IndexDefinition
                {
                    Name = row["INDNAME"].ToString()?.Trim() ?? string.Empty,
                    IsUnique = row["UNIQUERULE"].ToString()?.Trim() == "U",
                    Columns = row["COLNAMES"].ToString()?.Trim() ?? string.Empty
                });
            }
        }
        
        return tableDef;
    }
    
    /// <summary>
    /// Analyze differences between table definitions.
    /// </summary>
    private void AnalyzeDifferences(TableComparisonResult result)
    {
        if (result.TableDefinitions.Count < 2)
            return;
        
        // Get all unique column names across all databases
        var allColumns = result.TableDefinitions.Values
            .SelectMany(t => t.Columns.Select(c => c.Name))
            .Distinct()
            .ToList();
        
        foreach (var columnName in allColumns)
        {
            var columnDiff = new ColumnDifference { ColumnName = columnName };
            
            foreach (var kvp in result.TableDefinitions)
            {
                var column = kvp.Value.Columns.FirstOrDefault(c => c.Name == columnName);
                columnDiff.Definitions[kvp.Key] = column;
            }
            
            // Determine difference type
            var definedInCount = columnDiff.Definitions.Count(d => d.Value != null);
            
            if (definedInCount == result.TableDefinitions.Count)
            {
                // Check if all definitions are identical
                var firstDef = columnDiff.Definitions.Values.First(d => d != null);
                var allIdentical = columnDiff.Definitions.Values
                    .Where(d => d != null)
                    .All(d => d!.DataType == firstDef!.DataType &&
                             d.Length == firstDef.Length &&
                             d.IsNullable == firstDef.IsNullable);
                
                columnDiff.DifferenceType = allIdentical ?
                    DifferenceType.Identical : DifferenceType.Modified;
            }
            else if (definedInCount == 1)
            {
                columnDiff.DifferenceType = DifferenceType.Added;
            }
            else
            {
                columnDiff.DifferenceType = DifferenceType.Modified;
            }
            
            result.Differences.Add(columnDiff);
        }
        
        Logger.Info("Analyzed {Count} column differences for {Table}",
                   result.Differences.Count, result.TableName);
    }
    
    /// <summary>
    /// Generate ALTER statements to sync target to source.
    /// </summary>
    public string GenerateSyncAlterStatements(
        string targetAlias,
        TableDefinition source,
        TableDefinition target)
    {
        Logger.Debug("Generating sync ALTER statements from source to {Target}", targetAlias);
        
        var sb = new StringBuilder();
        sb.AppendLine($"-- Sync {target.Schema}.{target.TableName} to match source");
        sb.AppendLine();
        
        // Find columns to add
        var columnsToAdd = source.Columns
            .Where(sc => !target.Columns.Any(tc => tc.Name == sc.Name))
            .ToList();
        
        foreach (var col in columnsToAdd)
        {
            var dataTypeDef = $"{col.DataType}";
            if (col.Length > 0)
            {
                dataTypeDef += $"({col.Length})";
            }
            
            var nullableDef = col.IsNullable ? "" : " NOT NULL";
            var defaultDef = !string.IsNullOrEmpty(col.DefaultValue) ?
                $" DEFAULT {col.DefaultValue}" : "";
            
            sb.AppendLine($"ALTER TABLE {target.Schema}.{target.TableName} " +
                         $"ADD COLUMN {col.Name} {dataTypeDef}{nullableDef}{defaultDef};");
        }
        
        // Find columns to modify
        var columnsToModify = source.Columns
            .Where(sc => target.Columns.Any(tc => tc.Name == sc.Name &&
                   (tc.DataType != sc.DataType || tc.Length != sc.Length || tc.IsNullable != sc.IsNullable)))
            .ToList();
        
        foreach (var col in columnsToModify)
        {
            var dataTypeDef = $"{col.DataType}";
            if (col.Length > 0)
            {
                dataTypeDef += $"({col.Length})";
            }
            
            sb.AppendLine($"-- Modify {col.Name}");
            sb.AppendLine($"ALTER TABLE {target.Schema}.{target.TableName} " +
                         $"ALTER COLUMN {col.Name} SET DATA TYPE {dataTypeDef};");
            
            if (col.IsNullable)
            {
                sb.AppendLine($"ALTER TABLE {target.Schema}.{target.TableName} " +
                             $"ALTER COLUMN {col.Name} DROP NOT NULL;");
            }
            else
            {
                sb.AppendLine($"ALTER TABLE {target.Schema}.{target.TableName} " +
                             $"ALTER COLUMN {col.Name} SET NOT NULL;");
            }
        }
        
        // Find columns to drop (commented out for safety)
        var columnsToDrop = target.Columns
            .Where(tc => !source.Columns.Any(sc => sc.Name == tc.Name))
            .ToList();
        
        if (columnsToDrop.Any())
        {
            sb.AppendLine();
            sb.AppendLine("-- Columns to DROP (commented out for safety):");
            foreach (var col in columnsToDrop)
            {
                sb.AppendLine($"-- ALTER TABLE {target.Schema}.{target.TableName} DROP COLUMN {col.Name};");
            }
        }
        
        return sb.ToString();
    }
}

/// <summary>
/// Table comparison result.
/// </summary>
public class TableComparisonResult
{
    public string Schema { get; set; } = string.Empty;
    public string TableName { get; set; } = string.Empty;
    public List<string> DatabaseAliases { get; set; } = new();
    public Dictionary<string, TableDefinition> TableDefinitions { get; set; } = new();
    public List<ColumnDifference> Differences { get; set; } = new();
}

/// <summary>
/// Table definition from a database.
/// </summary>
public class TableDefinition
{
    public string Schema { get; set; } = string.Empty;
    public string TableName { get; set; } = string.Empty;
    public List<ColumnDefinition> Columns { get; set; } = new();
    public List<string> PrimaryKeyColumns { get; set; } = new();
    public List<IndexDefinition> Indexes { get; set; } = new();
}

/// <summary>
/// Column definition.
/// </summary>
public class ColumnDefinition
{
    public string Name { get; set; } = string.Empty;
    public string DataType { get; set; } = string.Empty;
    public int Length { get; set; }
    public int Scale { get; set; }
    public bool IsNullable { get; set; }
    public string? DefaultValue { get; set; }
    public bool IsIdentity { get; set; }
}

/// <summary>
/// Index definition.
/// </summary>
public class IndexDefinition
{
    public string Name { get; set; } = string.Empty;
    public bool IsUnique { get; set; }
    public string Columns { get; set; } = string.Empty;
}

/// <summary>
/// Column difference across databases.
/// </summary>
public class ColumnDifference
{
    public string ColumnName { get; set; } = string.Empty;
    public Dictionary<string, ColumnDefinition?> Definitions { get; set; } = new();
    public DifferenceType DifferenceType { get; set; }
}

/// <summary>
/// Difference types.
/// </summary>
public enum DifferenceType
{
    Identical,
    Added,
    Modified,
    Removed
}

