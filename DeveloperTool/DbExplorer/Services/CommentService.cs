using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using NLog;
using DbExplorer.Data;

namespace DbExplorer.Services;

/// <summary>
/// Model for object comment information
/// </summary>
public class ObjectComment
{
    public string ObjectType { get; set; } = string.Empty; // TABLE, COLUMN
    public string Schema { get; set; } = string.Empty;
    public string TableName { get; set; } = string.Empty;
    public string? ColumnName { get; set; }
    public string? Comment { get; set; }
    
    /// <summary>
    /// Original comment value when loaded from database (used to track changes)
    /// </summary>
    public string? OriginalComment { get; set; }
    
    public bool HasComment => !string.IsNullOrWhiteSpace(Comment);
    
    /// <summary>
    /// Returns true if the comment has been modified from its original value
    /// </summary>
    public bool IsModified => !string.Equals(Comment ?? string.Empty, OriginalComment ?? string.Empty, StringComparison.Ordinal);
}

/// <summary>
/// Service for managing object comments
/// </summary>
public class CommentService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    /// <summary>
    /// Get table comments
    /// </summary>
    public async Task<List<ObjectComment>> GetTableCommentsAsync(
        IConnectionManager connectionManager,
        string? schemaFilter = null)
    {
        Logger.Info("Getting table comments - Schema: {Schema}", schemaFilter ?? "*");
        
        try
        {
            var sql = new StringBuilder();
            sql.AppendLine("SELECT");
            sql.AppendLine("    'TABLE' AS OBJECT_TYPE,");
            sql.AppendLine("    TABSCHEMA AS SCHEMA,");
            sql.AppendLine("    TABNAME AS TABLE_NAME,");
            sql.AppendLine("    CAST(NULL AS VARCHAR(1)) AS COLUMN_NAME,");
            sql.AppendLine("    REMARKS AS COMMENT");
            sql.AppendLine("FROM SYSCAT.TABLES");
            sql.AppendLine("WHERE TYPE = 'T'");
            
            if (!string.IsNullOrEmpty(schemaFilter) && schemaFilter != "*")
            {
                sql.AppendLine($"  AND TABSCHEMA = '{schemaFilter}'");
            }
            else
            {
                sql.AppendLine("  AND TABSCHEMA NOT IN ('SYSIBM', 'SYSIBMADM', 'SYSCAT', 'SYSPROC')");
            }
            
            sql.AppendLine("ORDER BY TABSCHEMA, TABNAME");
            
            var result = await connectionManager.ExecuteQueryAsync(sql.ToString());
            Logger.Info("Found {Count} table comments", result.Rows.Count);
            
            return ConvertToObjectComments(result);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to get table comments");
            throw;
        }
    }
    
    /// <summary>
    /// Get column comments
    /// </summary>
    public async Task<List<ObjectComment>> GetColumnCommentsAsync(
        IConnectionManager connectionManager,
        string schema,
        string tableName)
    {
        Logger.Info("Getting column comments for {Schema}.{Table}", schema, tableName);
        
        try
        {
            var sql = $@"
                SELECT
                    'COLUMN' AS OBJECT_TYPE,
                    TABSCHEMA AS SCHEMA,
                    TABNAME AS TABLE_NAME,
                    COLNAME AS COLUMN_NAME,
                    REMARKS AS COMMENT
                FROM SYSCAT.COLUMNS
                WHERE TABSCHEMA = '{schema}'
                  AND TABNAME = '{tableName}'
                ORDER BY COLNO
            ";
            
            var result = await connectionManager.ExecuteQueryAsync(sql);
            Logger.Info("Found {Count} column comments for {Schema}.{Table}", result.Rows.Count, schema, tableName);
            
            return ConvertToObjectComments(result);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to get column comments for {Schema}.{Table}", schema, tableName);
            throw;
        }
    }
    
    /// <summary>
    /// Convert DataTable to list of ObjectComment
    /// </summary>
    private List<ObjectComment> ConvertToObjectComments(DataTable dataTable)
    {
        var comments = new List<ObjectComment>();
        
        foreach (DataRow row in dataTable.Rows)
        {
            try
            {
                var commentValue = row["COMMENT"] == DBNull.Value ? null : row["COMMENT"]?.ToString();
                var comment = new ObjectComment
                {
                    ObjectType = row["OBJECT_TYPE"]?.ToString() ?? string.Empty,
                    Schema = row["SCHEMA"]?.ToString() ?? string.Empty,
                    TableName = row["TABLE_NAME"]?.ToString() ?? string.Empty,
                    ColumnName = row["COLUMN_NAME"] == DBNull.Value ? null : row["COLUMN_NAME"]?.ToString(),
                    Comment = commentValue,
                    OriginalComment = commentValue  // Store original for change tracking
                };
                
                comments.Add(comment);
            }
            catch (Exception ex)
            {
                Logger.Warn(ex, "Failed to convert row to ObjectComment");
            }
        }
        
        return comments;
    }
    
    /// <summary>
    /// Generate COMMENT ON statements for all comments
    /// </summary>
    public string GenerateCommentScript(List<ObjectComment> comments)
    {
        return GenerateCommentScript(comments, changedOnly: false);
    }
    
    /// <summary>
    /// Generate COMMENT ON statements, optionally only for changed comments
    /// </summary>
    public string GenerateCommentScript(List<ObjectComment> comments, bool changedOnly)
    {
        var filteredComments = changedOnly 
            ? comments.Where(c => c.IsModified).ToList()
            : comments.Where(c => c.HasComment).ToList();
            
        Logger.Info("Generating COMMENT script for {Count} objects (changedOnly: {ChangedOnly})", 
            filteredComments.Count, changedOnly);
        
        var script = new StringBuilder();
        script.AppendLine("-- Generated COMMENT Script");
        script.AppendLine($"-- Generated: {DateTime.Now}");
        if (changedOnly)
        {
            script.AppendLine("-- Only modified comments are included");
        }
        script.AppendLine();
        
        if (filteredComments.Count == 0)
        {
            script.AppendLine("-- No " + (changedOnly ? "modified " : "") + "comments to export");
            return script.ToString();
        }
        
        foreach (var comment in filteredComments)
        {
            if (comment.ObjectType == "TABLE")
            {
                script.AppendLine($"COMMENT ON TABLE {comment.Schema}.{comment.TableName}");
                script.AppendLine($"  IS '{EscapeSqlString(comment.Comment ?? string.Empty)}';");
            }
            else if (comment.ObjectType == "COLUMN")
            {
                script.AppendLine($"COMMENT ON COLUMN {comment.Schema}.{comment.TableName}.{comment.ColumnName}");
                script.AppendLine($"  IS '{EscapeSqlString(comment.Comment ?? string.Empty)}';");
            }
            script.AppendLine();
        }
        
        Logger.Info("Generated COMMENT script for {Count} objects", filteredComments.Count);
        return script.ToString();
    }
    
    /// <summary>
    /// Escape single quotes in SQL string
    /// </summary>
    private string EscapeSqlString(string input)
    {
        return input.Replace("'", "''");
    }
}

