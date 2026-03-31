using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
using System.Threading.Tasks;
using NLog;
using DbExplorer.Data;
using DbExplorer.Models;

namespace DbExplorer.Services;

/// <summary>
/// Service for collecting table metadata for Missing FK Discovery input JSON.
/// Uses database-agnostic SQL translation to query any provider.
/// </summary>
public class MissingFKMetadataService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly MissingFKSqlTranslationService _sqlTranslationService;
    private readonly IConnectionManager _connectionManager;
    
    public MissingFKMetadataService(
        MissingFKSqlTranslationService sqlTranslationService,
        IConnectionManager connectionManager)
    {
        _sqlTranslationService = sqlTranslationService ?? throw new ArgumentNullException(nameof(sqlTranslationService));
        _connectionManager = connectionManager ?? throw new ArgumentNullException(nameof(connectionManager));
        Logger.Debug("MissingFKMetadataService initialized");
    }
    
    /// <summary>
    /// Collect complete metadata for a list of tables.
    /// </summary>
    public async Task<List<MissingFKTableMetadata>> CollectTableMetadataAsync(List<TableReference> tables)
    {
        Logger.Info("Collecting metadata for {Count} tables", tables.Count);
        var result = new List<MissingFKTableMetadata>();
        
        foreach (var table in tables)
        {
            try
            {
                Logger.Debug("Collecting metadata for {Schema}.{Table}", table.Schema, table.Name);
                var metadata = await CollectSingleTableMetadataAsync(table.Schema, table.Name);
                result.Add(metadata);
                Logger.Debug("Collected metadata for {Schema}.{Table}: {ColumnCount} columns, {PKCount} PK columns, {FKCount} FKs",
                    table.Schema, table.Name, metadata.Columns.Count, metadata.PrimaryKey.Count, metadata.ForeignKeys.Count);
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Failed to collect metadata for {Schema}.{Table}", table.Schema, table.Name);
                // Continue with other tables
            }
        }
        
        Logger.Info("Metadata collection complete: {Count} tables processed", result.Count);
        return result;
    }
    
    /// <summary>
    /// Collect metadata for a single table.
    /// </summary>
    private async Task<MissingFKTableMetadata> CollectSingleTableMetadataAsync(string schema, string tableName)
    {
        Logger.Debug("Collecting metadata for {Schema}.{Table}", schema, tableName);
        
        var metadata = new MissingFKTableMetadata
        {
            Schema = schema,
            Name = tableName
        };
        
        // Get columns
        Logger.Debug("Step 1: Getting columns");
        var columns = await GetColumnsAsync(schema, tableName);
        metadata.Columns = columns;
        
        // Get primary key
        Logger.Debug("Step 2: Getting primary key");
        var primaryKey = await GetPrimaryKeyAsync(schema, tableName);
        metadata.PrimaryKey = primaryKey;
        
        // Get unique keys
        Logger.Debug("Step 3: Getting unique keys");
        var uniqueKeys = await GetUniqueKeysAsync(schema, tableName);
        metadata.UniqueKeys = uniqueKeys;
        
        // Get foreign keys
        Logger.Debug("Step 4: Getting foreign keys");
        var foreignKeys = await GetForeignKeysAsync(schema, tableName);
        metadata.ForeignKeys = foreignKeys;
        
        // Get row count
        Logger.Debug("Step 5: Getting row count");
        var rowCount = await GetRowCountAsync(schema, tableName);
        metadata.RowCount = rowCount;
        
        Logger.Info("Metadata collected for {Schema}.{Table}: {ColumnCount} columns, {RowCount} rows, {PKCount} PK, {FKCount} FK",
            schema, tableName, columns.Count, rowCount, primaryKey.Count, foreignKeys.Count);
        
        return metadata;
    }
    
    /// <summary>
    /// Get columns for a table.
    /// </summary>
    private async Task<List<MissingFKColumnInfo>> GetColumnsAsync(string schema, string tableName)
    {
        Logger.Debug("Getting columns for {Schema}.{Table}", schema, tableName);
        
        var sql = await _sqlTranslationService.GetTranslatedStatementAsync(_connectionManager, "GetTableColumnsForMissingFK");
        sql = ReplaceParameters(sql, schema, tableName);
        
        Logger.Debug("Executing query: {Sql}", sql.Substring(0, Math.Min(100, sql.Length)));
        var result = await _connectionManager.ExecuteQueryAsync(sql);
        
        var columns = new List<MissingFKColumnInfo>();
        foreach (DataRow row in result.Rows)
        {
            columns.Add(new MissingFKColumnInfo
            {
                Name = row["COLUMN_NAME"]?.ToString()?.Trim() ?? string.Empty,
                DataType = row["DATA_TYPE"]?.ToString()?.Trim() ?? string.Empty,
                Length = row["LENGTH"] == DBNull.Value ? null : Convert.ToInt32(row["LENGTH"]),
                Scale = row["SCALE"] == DBNull.Value ? null : Convert.ToInt32(row["SCALE"]),
                Nullable = row["IS_NULLABLE"]?.ToString()?.ToUpperInvariant() == "YES"
            });
        }
        
        Logger.Debug("Retrieved {Count} columns", columns.Count);
        return columns;
    }
    
    /// <summary>
    /// Get primary key columns for a table.
    /// </summary>
    private async Task<List<string>> GetPrimaryKeyAsync(string schema, string tableName)
    {
        Logger.Debug("Getting primary key for {Schema}.{Table}", schema, tableName);
        
        var sql = await _sqlTranslationService.GetTranslatedStatementAsync(_connectionManager, "GetTablePrimaryKey");
        sql = ReplaceParameters(sql, schema, tableName, schema, tableName); // 4 parameters for this query
        
        Logger.Debug("Executing query: {Sql}", sql.Substring(0, Math.Min(100, sql.Length)));
        var result = await _connectionManager.ExecuteQueryAsync(sql);
        
        var pkColumns = new List<string>();
        foreach (DataRow row in result.Rows)
        {
            var colName = row["COLUMN_NAME"]?.ToString()?.Trim() ?? string.Empty;
            if (!string.IsNullOrEmpty(colName))
            {
                pkColumns.Add(colName);
            }
        }
        
        Logger.Debug("Retrieved {Count} primary key columns", pkColumns.Count);
        return pkColumns;
    }
    
    /// <summary>
    /// Get unique key constraints for a table.
    /// </summary>
    private async Task<List<List<string>>> GetUniqueKeysAsync(string schema, string tableName)
    {
        Logger.Debug("Getting unique keys for {Schema}.{Table}", schema, tableName);
        
        var sql = await _sqlTranslationService.GetTranslatedStatementAsync(_connectionManager, "GetTableUniqueKeys");
        sql = ReplaceParameters(sql, schema, tableName, schema, tableName); // 4 parameters
        
        Logger.Debug("Executing query: {Sql}", sql.Substring(0, Math.Min(100, sql.Length)));
        var result = await _connectionManager.ExecuteQueryAsync(sql);
        
        var uniqueKeysDict = new Dictionary<string, List<string>>();
        foreach (DataRow row in result.Rows)
        {
            var constraintName = row["CONSTRAINT_NAME"]?.ToString()?.Trim() ?? string.Empty;
            var columnName = row["COLUMN_NAME"]?.ToString()?.Trim() ?? string.Empty;
            
            if (!string.IsNullOrEmpty(constraintName) && !string.IsNullOrEmpty(columnName))
            {
                if (!uniqueKeysDict.ContainsKey(constraintName))
                {
                    uniqueKeysDict[constraintName] = new List<string>();
                }
                uniqueKeysDict[constraintName].Add(columnName);
            }
        }
        
        var uniqueKeys = uniqueKeysDict.Values.ToList();
        Logger.Debug("Retrieved {Count} unique key constraints", uniqueKeys.Count);
        return uniqueKeys;
    }
    
    /// <summary>
    /// Get foreign keys for a table.
    /// </summary>
    private async Task<List<MissingFKForeignKeyInfo>> GetForeignKeysAsync(string schema, string tableName)
    {
        Logger.Debug("Getting foreign keys for {Schema}.{Table}", schema, tableName);
        
        var sql = await _sqlTranslationService.GetTranslatedStatementAsync(_connectionManager, "GetTableForeignKeysForMissingFK");
        sql = ReplaceParameters(sql, schema, tableName, schema, tableName); // 4 parameters
        
        Logger.Debug("Executing query: {Sql}", sql.Substring(0, Math.Min(100, sql.Length)));
        var result = await _connectionManager.ExecuteQueryAsync(sql);
        
        var fkDict = new Dictionary<string, MissingFKForeignKeyInfo>();
        foreach (DataRow row in result.Rows)
        {
            var constraintName = row["CONSTRAINT_NAME"]?.ToString()?.Trim() ?? string.Empty;
            var columnName = row["COLUMN_NAME"]?.ToString()?.Trim() ?? string.Empty;
            var refSchema = row["REF_SCHEMA"]?.ToString()?.Trim() ?? string.Empty;
            var refTable = row["REF_TABLE"]?.ToString()?.Trim() ?? string.Empty;
            var refColumn = row["REF_COLUMN"]?.ToString()?.Trim() ?? string.Empty;
            
            if (!string.IsNullOrEmpty(constraintName))
            {
                if (!fkDict.ContainsKey(constraintName))
                {
                    fkDict[constraintName] = new MissingFKForeignKeyInfo
                    {
                        Name = constraintName,
                        RefSchema = refSchema,
                        RefTable = refTable
                    };
                }
                
                fkDict[constraintName].Columns.Add(columnName);
                fkDict[constraintName].RefColumns.Add(refColumn);
            }
        }
        
        var foreignKeys = fkDict.Values.ToList();
        Logger.Debug("Retrieved {Count} foreign key constraints", foreignKeys.Count);
        return foreignKeys;
    }
    
    /// <summary>
    /// Get row count for a table.
    /// Note: This query uses {SCHEMA} and {TABLE} placeholders that must be replaced.
    /// </summary>
    private async Task<long> GetRowCountAsync(string schema, string tableName)
    {
        Logger.Debug("Getting row count for {Schema}.{Table}", schema, tableName);
        
        var sql = await _sqlTranslationService.GetTranslatedStatementAsync(_connectionManager, "GetTableRowCount");
        
        // Replace {SCHEMA} and {TABLE} placeholders (not parameterized)
        // Need to properly quote identifiers based on provider
        var provider = _connectionManager.ConnectionInfo.ProviderType?.ToUpperInvariant() ?? "DB2";
        var quotedSchema = QuoteIdentifier(schema, provider);
        var quotedTable = QuoteIdentifier(tableName, provider);
        
        sql = sql.Replace("{SCHEMA}", quotedSchema).Replace("{TABLE}", quotedTable);
        
        Logger.Debug("Executing query: {Sql}", sql.Substring(0, Math.Min(100, sql.Length)));
        var result = await _connectionManager.ExecuteQueryAsync(sql);
        
        if (result.Rows.Count > 0 && result.Rows[0]["ROW_COUNT"] != DBNull.Value)
        {
            var rowCount = Convert.ToInt64(result.Rows[0]["ROW_COUNT"]);
            Logger.Debug("Row count: {Count}", rowCount);
            return rowCount;
        }
        
        Logger.Warn("Row count query returned no results for {Schema}.{Table}", schema, tableName);
        return 0;
    }
    
    /// <summary>
    /// Quote identifier based on provider type.
    /// </summary>
    private string QuoteIdentifier(string identifier, string provider)
    {
        return provider.ToUpperInvariant() switch
        {
            "DB2" => identifier, // DB2 uses unquoted identifiers by default
            "POSTGRESQL" or "POSTGRES" => $"\"{identifier}\"",
            "SQLSERVER" or "MSSQL" => $"[{identifier}]",
            "ORACLE" => $"\"{identifier.ToUpperInvariant()}\"",
            "MYSQL" => $"`{identifier}`",
            _ => identifier // Default: no quoting
        };
    }
    
    /// <summary>
    /// Replace SQL parameter placeholders (?) with quoted values.
    /// </summary>
    private string ReplaceParameters(string sql, params string[] values)
    {
        var result = sql;
        foreach (var value in values)
        {
            var index = result.IndexOf('?');
            if (index >= 0)
            {
                // Quote the value for SQL
                var quotedValue = $"'{value.Replace("'", "''")}'";
                result = result.Substring(0, index) + quotedValue + result.Substring(index + 1);
            }
        }
        return result;
    }
}
