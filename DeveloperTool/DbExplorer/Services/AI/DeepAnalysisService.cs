using NLog;
using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using DbExplorer.Data;
using DbExplorer.Services.Interfaces;

namespace DbExplorer.Services.AI;

/// <summary>
/// Deep Analysis Service - extracts comprehensive context for AI analysis.
/// Fetches: table/column comments, data samples, column profiling, relationships.
/// PROVIDER-AGNOSTIC: Uses IMetadataProvider for all queries.
/// </summary>
public class DeepAnalysisService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly IConnectionManager _connectionManager;
    private readonly IMetadataProvider _metadataProvider;
    
    public DeepAnalysisService(IConnectionManager connectionManager, IMetadataProvider metadataProvider)
    {
        _connectionManager = connectionManager;
        _metadataProvider = metadataProvider;
        Logger.Debug("DeepAnalysisService initialized with provider: {Provider}", metadataProvider.GetCurrentProvider());
    }
    
    /// <summary>
    /// Perform deep analysis on a single table.
    /// </summary>
    public async Task<TableDeepAnalysis> AnalyzeTableAsync(string schema, string tableName, int sampleSize = 100)
    {
        Logger.Info("Starting deep analysis: {Schema}.{Table}", schema, tableName);
        
        var analysis = new TableDeepAnalysis
        {
            Schema = schema,
            TableName = tableName,
            AnalysisTimestamp = DateTime.Now
        };
        
        try
        {
            // 1. Extract table comment
            analysis.TableComment = await GetTableCommentAsync(schema, tableName);
            
            // 2. Extract column comments
            analysis.ColumnComments = await GetColumnCommentsAsync(schema, tableName);
            
            // 3. Get column metadata
            analysis.Columns = await GetColumnMetadataAsync(schema, tableName);
            
            // 4. Sample data (limited rows)
            analysis.DataSample = await GetDataSampleAsync(schema, tableName, sampleSize);
            
            // 5. Column profiling (data types, nulls, unique values)
            analysis.ColumnProfiles = await ProfileColumnsAsync(schema, tableName);
            
            // 6. Relationships (foreign keys)
            analysis.Relationships = await GetRelationshipsAsync(schema, tableName);
            
            Logger.Info("Deep analysis complete: {Schema}.{Table} - {ColumnCount} columns, {SampleRows} sample rows",
                schema, tableName, analysis.Columns.Count, analysis.DataSample.Rows.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Deep analysis failed for {Schema}.{Table}", schema, tableName);
            analysis.ErrorMessage = ex.Message;
        }
        
        return analysis;
    }
    
    /// <summary>
    /// Perform group analysis on multiple tables.
    /// </summary>
    public async Task<GroupDeepAnalysis> AnalyzeGroupAsync(List<(string schema, string table)> tables, int sampleSize = 50)
    {
        Logger.Info("Starting group analysis: {Count} tables", tables.Count);
        
        var groupAnalysis = new GroupDeepAnalysis
        {
            AnalysisTimestamp = DateTime.Now
        };
        
        foreach (var (schema, table) in tables)
        {
            var tableAnalysis = await AnalyzeTableAsync(schema, table, sampleSize);
            groupAnalysis.TableAnalyses.Add(tableAnalysis);
        }
        
        // Find cross-table relationships
        groupAnalysis.CrossTableRelationships = await GetCrossTableRelationshipsAsync(tables);
        
        Logger.Info("Group analysis complete: {Count} tables analyzed", tables.Count);
        return groupAnalysis;
    }
    
    /// <summary>
    /// Get table comment from SYSCAT.TABLES.
    /// </summary>
    private async Task<string> GetTableCommentAsync(string schema, string tableName)
    {
        Logger.Debug("Fetching table comment: {Schema}.{Table}", schema, tableName);
        
        var result = await _metadataProvider.ExecuteScalarAsync("GetTableComment", 
            new Dictionary<string, object>
            {
                { "TABSCHEMA", schema },
                { "TABNAME", tableName }
            });
        
        return result?.ToString()?.Trim() ?? string.Empty;
    }
    
    /// <summary>
    /// Get column comments from SYSCAT.COLUMNS.
    /// </summary>
    private async Task<Dictionary<string, string>> GetColumnCommentsAsync(string schema, string tableName)
    {
        Logger.Debug("Fetching column comments: {Schema}.{Table}", schema, tableName);
        
        var comments = new Dictionary<string, string>();
        
        var dataTable = await _metadataProvider.ExecuteMetadataQueryAsync("GetColumnComments",
            new Dictionary<string, object>
            {
                { "TABSCHEMA", schema },
                { "TABNAME", tableName }
            });
        
        foreach (DataRow row in dataTable.Rows)
        {
            var colName = row["COLNAME"].ToString() ?? string.Empty;
            var remarks = row["REMARKS"].ToString()?.Trim() ?? string.Empty;
            
            if (!string.IsNullOrWhiteSpace(remarks))
            {
                comments[colName] = remarks;
            }
        }
        
        Logger.Debug("Found {Count} column comments", comments.Count);
        return comments;
    }
    
    /// <summary>
    /// Get column metadata (names, types, nullable).
    /// </summary>
    private async Task<List<ColumnMetadata>> GetColumnMetadataAsync(string schema, string tableName)
    {
        Logger.Debug("Fetching column metadata: {Schema}.{Table}", schema, tableName);
        
        var columns = new List<ColumnMetadata>();
        
        var dataTable = await _metadataProvider.ExecuteMetadataQueryAsync("GetColumnMetadata",
            new Dictionary<string, object>
            {
                { "TABSCHEMA", schema },
                { "TABNAME", tableName }
            });
        
        foreach (DataRow row in dataTable.Rows)
        {
            columns.Add(new ColumnMetadata
            {
                Name = row["COLNAME"].ToString() ?? string.Empty,
                DataType = row["TYPENAME"].ToString() ?? string.Empty,
                Length = Convert.ToInt32(row["LENGTH"]),
                Scale = Convert.ToInt32(row["SCALE"]),
                IsNullable = row["NULLS"].ToString() == "Y",
                IsIdentity = row["IDENTITY"].ToString() == "Y",
                DefaultValue = row["DEFAULT"]?.ToString()
            });
        }
        
        Logger.Debug("Found {Count} columns", columns.Count);
        return columns;
    }
    
    /// <summary>
    /// Get sample data from table (limited rows).
    /// </summary>
    private async Task<DataTable> GetDataSampleAsync(string schema, string tableName, int sampleSize)
    {
        Logger.Debug("Fetching data sample: {Schema}.{Table} (limit {Size})", schema, tableName, sampleSize);
        
        var sql = $"SELECT * FROM {schema}.{tableName} FETCH FIRST {sampleSize} ROWS ONLY";
        
        try
        {
            var dataTable = await _connectionManager.ExecuteQueryAsync(sql);
            Logger.Debug("Retrieved {Count} sample rows", dataTable.Rows.Count);
            return dataTable;
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "Failed to fetch data sample - may not have SELECT permission");
            return new DataTable();
        }
    }
    
    /// <summary>
    /// Profile columns (count, distinct, nulls, min/max).
    /// </summary>
    private async Task<Dictionary<string, ColumnProfile>> ProfileColumnsAsync(string schema, string tableName)
    {
        Logger.Debug("Profiling columns: {Schema}.{Table}", schema, tableName);
        
        var profiles = new Dictionary<string, ColumnProfile>();
        
        try
        {
            var columns = await GetColumnMetadataAsync(schema, tableName);
            
            foreach (var col in columns)
            {
                var profile = new ColumnProfile { ColumnName = col.Name };
                
                // Count total and nulls
                var sql = $@"
SELECT 
    COUNT(*) as TOTAL_COUNT,
    COUNT({col.Name}) as NON_NULL_COUNT,
    COUNT(DISTINCT {col.Name}) as DISTINCT_COUNT
FROM {schema}.{tableName}";
                
                var result = await _connectionManager.ExecuteQueryAsync(sql);
                if (result.Rows.Count > 0)
                {
                    var row = result.Rows[0];
                    profile.TotalCount = Convert.ToInt64(row["TOTAL_COUNT"]);
                    profile.NonNullCount = Convert.ToInt64(row["NON_NULL_COUNT"]);
                    profile.DistinctCount = Convert.ToInt64(row["DISTINCT_COUNT"]);
                    profile.NullCount = profile.TotalCount - profile.NonNullCount;
                }
                
                profiles[col.Name] = profile;
            }
            
            Logger.Debug("Profiled {Count} columns", profiles.Count);
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "Column profiling failed - may not have SELECT permission");
        }
        
        return profiles;
    }
    
    /// <summary>
    /// Get relationships (foreign keys).
    /// </summary>
    private async Task<List<TableRelationship>> GetRelationshipsAsync(string schema, string tableName)
    {
        Logger.Debug("Fetching relationships: {Schema}.{Table}", schema, tableName);
        
        var relationships = new List<TableRelationship>();
        
        var dataTable = await _metadataProvider.ExecuteMetadataQueryAsync("GetTableRelationships",
            new Dictionary<string, object>
            {
                { "TABSCHEMA", schema },
                { "TABNAME", tableName },
                { "REFTABSCHEMA", schema },
                { "REFTABNAME", tableName }
            });
        
        var grouped = dataTable.AsEnumerable()
            .GroupBy(r => r["CONSTNAME"].ToString());
        
        foreach (var group in grouped)
        {
            var firstRow = group.First();
            relationships.Add(new TableRelationship
            {
                ConstraintName = firstRow["CONSTNAME"].ToString() ?? string.Empty,
                FromSchema = firstRow["TABSCHEMA"].ToString() ?? string.Empty,
                FromTable = firstRow["TABNAME"].ToString() ?? string.Empty,
                ToSchema = firstRow["REFTABSCHEMA"].ToString() ?? string.Empty,
                ToTable = firstRow["REFTABNAME"].ToString() ?? string.Empty,
                Columns = group.Select(r => r["COLNAME"].ToString() ?? string.Empty).ToList()
            });
        }
        
        Logger.Debug("Found {Count} relationships", relationships.Count);
        return relationships;
    }
    
    /// <summary>
    /// Get cross-table relationships for group analysis.
    /// </summary>
    private async Task<List<TableRelationship>> GetCrossTableRelationshipsAsync(List<(string schema, string table)> tables)
    {
        Logger.Debug("Fetching cross-table relationships");
        
        var allRelationships = new List<TableRelationship>();
        
        foreach (var (schema, table) in tables)
        {
            var rels = await GetRelationshipsAsync(schema, table);
            allRelationships.AddRange(rels);
        }
        
        // Deduplicate
        var uniqueRels = allRelationships
            .GroupBy(r => r.ConstraintName)
            .Select(g => g.First())
            .ToList();
        
        Logger.Debug("Found {Count} cross-table relationships", uniqueRels.Count);
        return uniqueRels;
    }
}

// Analysis result models
public class TableDeepAnalysis
{
    public string Schema { get; set; } = string.Empty;
    public string TableName { get; set; } = string.Empty;
    public DateTime AnalysisTimestamp { get; set; }
    public string TableComment { get; set; } = string.Empty;
    public Dictionary<string, string> ColumnComments { get; set; } = new();
    public List<ColumnMetadata> Columns { get; set; } = new();
    public DataTable DataSample { get; set; } = new();
    public Dictionary<string, ColumnProfile> ColumnProfiles { get; set; } = new();
    public List<TableRelationship> Relationships { get; set; } = new();
    public string? ErrorMessage { get; set; }
}

public class GroupDeepAnalysis
{
    public DateTime AnalysisTimestamp { get; set; }
    public List<TableDeepAnalysis> TableAnalyses { get; set; } = new();
    public List<TableRelationship> CrossTableRelationships { get; set; } = new();
}

public class ColumnMetadata
{
    public string Name { get; set; } = string.Empty;
    public string DataType { get; set; } = string.Empty;
    public int Length { get; set; }
    public int Scale { get; set; }
    public bool IsNullable { get; set; }
    public bool IsIdentity { get; set; }
    public string? DefaultValue { get; set; }
}

public class ColumnProfile
{
    public string ColumnName { get; set; } = string.Empty;
    public long TotalCount { get; set; }
    public long NonNullCount { get; set; }
    public long NullCount { get; set; }
    public long DistinctCount { get; set; }
    public double NullPercentage => TotalCount > 0 ? (NullCount * 100.0 / TotalCount) : 0;
    public double UniquenessPercentage => TotalCount > 0 ? (DistinctCount * 100.0 / TotalCount) : 0;
}

public class TableRelationship
{
    public string ConstraintName { get; set; } = string.Empty;
    public string FromSchema { get; set; } = string.Empty;
    public string FromTable { get; set; } = string.Empty;
    public string ToSchema { get; set; } = string.Empty;
    public string ToTable { get; set; } = string.Empty;
    public List<string> Columns { get; set; } = new();
}
