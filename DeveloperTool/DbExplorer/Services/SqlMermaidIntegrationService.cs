using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using NLog;
using SqlMermaidErdTools;
using SqlMermaidErdTools.Models;
using DbExplorer.Data;
using DbExplorer.Models;

namespace DbExplorer.Services;

/// <summary>
/// Integration service that bridges DB2 metadata with SqlMermaidErdTools package.
/// Provides bidirectional SQL ↔ Mermaid conversion, dialect translation, and schema diff.
/// </summary>
public class SqlMermaidIntegrationService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    /// <summary>
    /// Generates SQL DDL CREATE TABLE statements from database table metadata.
    /// This DDL can then be converted to Mermaid using ToMermaid() or translated to other dialects.
    /// </summary>
    public async Task<string> GenerateDdlFromDb2TablesAsync(
        IConnectionManager connectionManager,
        List<string> selectedTables)
    {
        Logger.Info("Generating SQL DDL for {Count} tables", selectedTables.Count);
        Logger.Debug("Selected tables: {Tables}", string.Join(", ", selectedTables));
        
        var ddl = new StringBuilder();
        
        foreach (var fullTableName in selectedTables)
        {
            var parts = fullTableName.Split('.');
            var schema = parts.Length == 2 ? parts[0].Trim() : "SYSCAT";
            var tableName = parts.Length == 2 ? parts[1].Trim() : fullTableName?.Trim() ?? string.Empty;
            
            Logger.Debug("Processing table: {Schema}.{Table}", schema, tableName);
            var tableDdl = await GenerateTableDdlAsync(connectionManager, schema, tableName);
            
            if (!string.IsNullOrEmpty(tableDdl))
            {
                ddl.AppendLine(tableDdl);
                ddl.AppendLine();
            }
        }
        
        Logger.Info("DDL generation complete - {Length} characters", ddl.Length);
        return ddl.ToString();
    }
    
    /// <summary>
    /// Generates CREATE TABLE DDL for a single DB2 table.
    /// </summary>
    private async Task<string> GenerateTableDdlAsync(
        IConnectionManager connectionManager,
        string schema,
        string tableName)
    {
        try
        {
            // Trim schema and table name to ensure clean concatenation
            var trimmedSchema = schema?.Trim() ?? string.Empty;
            var trimmedTableName = tableName?.Trim() ?? string.Empty;
            
            // Get table columns with metadata
            var sql = $@"
                SELECT 
                    c.COLNAME, c.TYPENAME, c.LENGTH, c.SCALE, c.NULLS, c.REMARKS,
                    CASE WHEN k.COLNAME IS NOT NULL THEN 1 ELSE 0 END AS IS_PK
                FROM SYSCAT.COLUMNS c
                LEFT JOIN SYSCAT.KEYCOLUSE k 
                    ON c.TABSCHEMA = k.TABSCHEMA 
                    AND c.TABNAME = k.TABNAME 
                    AND c.COLNAME = k.COLNAME
                WHERE c.TABSCHEMA = '{trimmedSchema}' 
                  AND c.TABNAME = '{trimmedTableName}'
                ORDER BY c.COLNO
            ";
            
            var result = await connectionManager.ExecuteQueryAsync(sql);
            
            if (result.Rows.Count == 0)
            {
                Logger.Warn("No columns found for {Schema}.{Table}", trimmedSchema, trimmedTableName);
                return string.Empty;
            }
            
            var ddl = new StringBuilder();
            ddl.AppendLine($"CREATE TABLE {trimmedSchema}.{trimmedTableName} (");
            
            var columns = new List<string>();
            var pkColumns = new List<string>();
            
            foreach (DataRow row in result.Rows)
            {
                var colName = row["COLNAME"]?.ToString() ?? string.Empty;
                var dataType = FormatDb2DataType(
                    row["TYPENAME"]?.ToString() ?? string.Empty,
                    row["LENGTH"],
                    row["SCALE"]);
                var isNullable = row["NULLS"]?.ToString() == "Y";
                var isPk = Convert.ToInt32(row["IS_PK"]) == 1;
                
                var columnDef = $"    {colName} {dataType}";
                if (!isNullable) columnDef += " NOT NULL";
                
                columns.Add(columnDef);
                
                if (isPk) pkColumns.Add(colName);
            }
            
            ddl.AppendLine(string.Join(",\n", columns));
            
            // Add PRIMARY KEY constraint
            if (pkColumns.Any())
            {
                ddl.AppendLine($",    PRIMARY KEY ({string.Join(", ", pkColumns)})");
            }
            
            ddl.AppendLine(");");
            
            // Get foreign keys
            var fkDdl = await GenerateForeignKeyDdlAsync(connectionManager, schema, tableName);
            if (!string.IsNullOrEmpty(fkDdl))
            {
                ddl.AppendLine();
                ddl.Append(fkDdl);
            }
            
            // Get indexes
            var indexDdl = await GenerateIndexDdlAsync(connectionManager, schema, tableName);
            if (!string.IsNullOrEmpty(indexDdl))
            {
                ddl.AppendLine();
                ddl.Append(indexDdl);
            }
            
            Logger.Debug("Generated DDL for {Schema}.{Table} - {Columns} columns, {PKs} PKs",
                schema, tableName, result.Rows.Count, pkColumns.Count);
            
            return ddl.ToString();
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to generate DDL for {Schema}.{Table}", schema, tableName);
            return string.Empty;
        }
    }
    
    /// <summary>
    /// Generates ALTER TABLE statements for foreign keys.
    /// </summary>
    private async Task<string> GenerateForeignKeyDdlAsync(
        IConnectionManager connectionManager,
        string schema,
        string tableName)
    {
        try
        {
            var sql = $@"
                SELECT 
                    CONSTNAME, FK_COLNAMES, REFTABSCHEMA, REFTABNAME, PK_COLNAMES
                FROM SYSCAT.REFERENCES
                WHERE TABSCHEMA = '{schema}' AND TABNAME = '{tableName}'
            ";
            
            var result = await connectionManager.ExecuteQueryAsync(sql);
            
            if (result.Rows.Count == 0)
                return string.Empty;
            
            var ddl = new StringBuilder();
            
            foreach (DataRow row in result.Rows)
            {
                var fkName = row["CONSTNAME"]?.ToString() ?? string.Empty;
                var fkCols = row["FK_COLNAMES"]?.ToString()?.Replace(" ", "") ?? string.Empty;
                var refSchema = row["REFTABSCHEMA"]?.ToString() ?? string.Empty;
                var refTable = row["REFTABNAME"]?.ToString() ?? string.Empty;
                var refCols = row["PK_COLNAMES"]?.ToString()?.Replace(" ", "") ?? string.Empty;
                
                ddl.AppendLine($"ALTER TABLE {schema}.{tableName}");
                ddl.AppendLine($"    ADD CONSTRAINT {fkName}");
                ddl.AppendLine($"    FOREIGN KEY ({fkCols})");
                ddl.AppendLine($"    REFERENCES {refSchema}.{refTable}({refCols});");
            }
            
            Logger.Debug("Generated {Count} foreign key constraints for {Schema}.{Table}",
                result.Rows.Count, schema, tableName);
            
            return ddl.ToString();
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to generate FK DDL for {Schema}.{Table}", schema, tableName);
            return string.Empty;
        }
    }
    
    /// <summary>
    /// Generates CREATE INDEX statements for a DB2 table.
    /// </summary>
    private async Task<string> GenerateIndexDdlAsync(
        IConnectionManager connectionManager,
        string schema,
        string tableName)
    {
        try
        {
            var sql = $@"
                SELECT 
                    INDNAME, UNIQUERULE, COLNAMES
                FROM SYSCAT.INDEXES
                WHERE TABSCHEMA = '{schema}' 
                  AND TABNAME = '{tableName}'
                  AND UNIQUERULE <> 'P'
                ORDER BY INDNAME
            ";
            
            var result = await connectionManager.ExecuteQueryAsync(sql);
            
            if (result.Rows.Count == 0)
                return string.Empty;
            
            var ddl = new StringBuilder();
            
            foreach (DataRow row in result.Rows)
            {
                var indexName = row["INDNAME"]?.ToString() ?? string.Empty;
                var uniqueRule = row["UNIQUERULE"]?.ToString() ?? string.Empty;
                var colNames = row["COLNAMES"]?.ToString()?.Replace("+", ", ").Replace("-", " DESC, ") ?? string.Empty;
                
                // Clean up column names (remove trailing DESC markers)
                colNames = colNames.TrimEnd(',', ' ', 'D', 'E', 'S', 'C').Trim();
                
                var uniqueClause = uniqueRule == "U" ? "UNIQUE " : "";
                
                ddl.AppendLine($"CREATE {uniqueClause}INDEX {indexName}");
                ddl.AppendLine($"    ON {schema}.{tableName} ({colNames});");
            }
            
            Logger.Debug("Generated {Count} index DDL statements for {Schema}.{Table}",
                result.Rows.Count, schema, tableName);
            
            return ddl.ToString();
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to generate index DDL for {Schema}.{Table}", schema, tableName);
            return string.Empty;
        }
    }
    
    /// <summary>
    /// Converts SQL DDL to Mermaid ERD using SqlMermaidErdTools.
    /// Supports 31+ SQL dialects including DB2.
    /// </summary>
    public async Task<string> ConvertSqlToMermaidAsync(string sqlDdl)
    {
        Logger.Info("=== ConvertSqlToMermaidAsync START ===");
        Logger.Debug("SQL DDL length: {Length} characters", sqlDdl.Length);
        Logger.Debug("SQL DDL preview: {Preview}", sqlDdl.Length > 300 ? sqlDdl.Substring(0, 300) : sqlDdl);
        
        try
        {
            Logger.Debug("Calling SqlMermaidErdTools.ToMermaidAsync...");
            var mermaid = await SqlMermaidErdTools.SqlMermaidErdTools.ToMermaidAsync(sqlDdl);
            Logger.Info("SqlMermaidErdTools.ToMermaidAsync returned {Length} characters", mermaid.Length);
            Logger.Debug("Raw Mermaid from SqlMermaidErdTools (first 500 chars): {Preview}",
                mermaid.Length > 500 ? mermaid.Substring(0, 500) : mermaid);
            
            // Check for problematic types BEFORE PostProcess
            var hasDecimalParen = mermaid.Contains("DECIMAL(");
            var hasVarcharParen = mermaid.Contains("VARCHAR(");
            Logger.Debug("BEFORE PostProcess - Has DECIMAL(: {HasDecimal}, Has VARCHAR(: {HasVarchar}", 
                hasDecimalParen, hasVarcharParen);
            
            // Post-process to fix Mermaid ERD syntax issues (remove complex data types)
            Logger.Debug("Running PostProcessMermaidErd...");
            mermaid = PostProcessMermaidErd(mermaid);
            
            // Check AFTER PostProcess
            hasDecimalParen = mermaid.Contains("DECIMAL(");
            hasVarcharParen = mermaid.Contains("VARCHAR(");
            Logger.Debug("AFTER PostProcess - Has DECIMAL(: {HasDecimal}, Has VARCHAR(: {HasVarchar}", 
                hasDecimalParen, hasVarcharParen);
            
            Logger.Info("=== ConvertSqlToMermaidAsync COMPLETE ===");
            return mermaid;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to convert SQL to Mermaid");
            Logger.Debug("Exception details - Type: {Type}, Message: {Message}", ex.GetType().Name, ex.Message);
            Logger.Debug("Stack trace: {Stack}", ex.StackTrace);
            throw new InvalidOperationException("Failed to convert SQL to Mermaid ERD. Check SQL syntax.", ex);
        }
    }
    
    /// <summary>
    /// Converts Mermaid ERD to SQL DDL for specified dialect.
    /// Supports: ANSI SQL, SQL Server, PostgreSQL, MySQL.
    /// </summary>
    public async Task<string> ConvertMermaidToSqlAsync(string mermaidErd, SqlDialect targetDialect = SqlDialect.AnsiSql)
    {
        Logger.Info("Converting Mermaid ERD to SQL DDL - Dialect: {Dialect}", targetDialect);
        Logger.Debug("Mermaid ERD length: {Length} characters", mermaidErd.Length);
        
        try
        {
            var sql = await SqlMermaidErdTools.SqlMermaidErdTools.ToSqlAsync(mermaidErd, targetDialect);
            Logger.Info("SQL DDL generated - {Length} characters, Dialect: {Dialect}", sql.Length, targetDialect);
            return sql;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to convert Mermaid to SQL");
            throw new InvalidOperationException($"Failed to convert Mermaid ERD to {targetDialect} SQL. Check Mermaid syntax.", ex);
        }
    }
    
    /// <summary>
    /// Translates SQL from one dialect to another.
    /// Example: DB2 → PostgreSQL, SQL Server → MySQL, etc.
    /// </summary>
    public async Task<string> TranslateSqlDialectAsync(
        string sourceSql,
        SqlDialect sourceDialect,
        SqlDialect targetDialect)
    {
        Logger.Info("Translating SQL: {Source} → {Target}", sourceDialect, targetDialect);
        Logger.Debug("Source SQL length: {Length} characters", sourceSql.Length);
        
        try
        {
            var translated = await SqlMermaidErdTools.SqlMermaidErdTools.TranslateDialectAsync(
                sourceSql,
                sourceDialect,
                targetDialect);
            
            Logger.Info("SQL translation complete - {Length} characters", translated.Length);
            return translated;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to translate SQL from {Source} to {Target}", sourceDialect, targetDialect);
            throw new InvalidOperationException($"Failed to translate SQL from {sourceDialect} to {targetDialect}.", ex);
        }
    }
    
    /// <summary>
    /// Generates ALTER statements from Mermaid diagram changes.
    /// Compares two Mermaid diagrams and produces migration DDL.
    /// </summary>
    public async Task<string> GenerateMigrationFromMermaidDiffAsync(
        string beforeMermaid,
        string afterMermaid,
        SqlDialect targetDialect = SqlDialect.AnsiSql)
    {
        Logger.Info("Generating migration DDL from Mermaid diff - Dialect: {Dialect}", targetDialect);
        Logger.Debug("Before Mermaid: {BeforeLength} chars, After Mermaid: {AfterLength} chars",
            beforeMermaid.Length, afterMermaid.Length);
        
        try
        {
            var alterStatements = await SqlMermaidErdTools.SqlMermaidErdTools.GenerateDiffAlterStatementsAsync(
                beforeMermaid,
                afterMermaid,
                targetDialect);
            
            Logger.Info("Migration DDL generated - {Length} characters", alterStatements.Length);
            return alterStatements;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to generate migration DDL from Mermaid diff");
            throw new InvalidOperationException("Failed to generate migration DDL. Check Mermaid syntax.", ex);
        }
    }
    
    /// <summary>
    /// Complete workflow: DB2 Tables → SQL DDL → Mermaid ERD.
    /// This is the primary method for generating Mermaid diagrams from live DB2 databases.
    /// </summary>
    public async Task<string> GenerateMermaidFromDb2TablesAsync(
        IConnectionManager connectionManager,
        List<string> selectedTables)
    {
        Logger.Info("=== SqlMermaidIntegration: GenerateMermaidFromDb2TablesAsync START ===");
        Logger.Info("Processing {Count} tables", selectedTables.Count);
        Logger.Debug("Tables to process: {Tables}", string.Join(", ", selectedTables));
        
        // Step 1: Generate DDL from DB2
        Logger.Debug("Step 1: Generating DDL from DB2 tables...");
        var ddl = await GenerateDdlFromDb2TablesAsync(connectionManager, selectedTables);
        
        if (string.IsNullOrWhiteSpace(ddl))
        {
            Logger.Warn("No DDL generated, returning empty Mermaid diagram");
            return "erDiagram\n    -- No tables found";
        }
        
        Logger.Debug("DDL generated successfully - {Length} chars", ddl.Length);
        Logger.Debug("DDL preview (first 500 chars): {Preview}", 
            ddl.Length > 500 ? ddl.Substring(0, 500) : ddl);
        
        // Step 2: Convert DDL to Mermaid (this also calls PostProcessMermaidErd internally)
        Logger.Debug("Step 2: Converting DDL to Mermaid via SqlMermaidErdTools...");
        var mermaid = await ConvertSqlToMermaidAsync(ddl);
        
        Logger.Debug("ConvertSqlToMermaidAsync returned {Length} chars", mermaid.Length);
        Logger.Debug("Mermaid after ConvertSqlToMermaidAsync (first 500 chars): {Preview}",
            mermaid.Length > 500 ? mermaid.Substring(0, 500) : mermaid);
        
        // Step 3: Post-process AGAIN to ensure all data types are fixed
        Logger.Debug("Step 3: Running PostProcessMermaidErd (second pass)...");
        var beforeLength = mermaid.Length;
        mermaid = PostProcessMermaidErd(mermaid);
        Logger.Debug("PostProcess changed length: {Before} -> {After} chars", beforeLength, mermaid.Length);
        
        // Verify no problematic types remain
        if (mermaid.Contains("(") && (mermaid.Contains("DECIMAL") || mermaid.Contains("VARCHAR")))
        {
            Logger.Warn("STILL CONTAINS PARENTHESES after PostProcess - searching for issues...");
            var lines = mermaid.Split('\n');
            for (int i = 0; i < lines.Length; i++)
            {
                if (lines[i].Contains("(") && !lines[i].Contains("erDiagram"))
                {
                    Logger.Warn("Line {LineNum}: {Line}", i + 1, lines[i]);
                }
            }
        }
        
        Logger.Info("=== SqlMermaidIntegration: GenerateMermaidFromDb2TablesAsync COMPLETE ===");
        return mermaid;
    }
    
    /// <summary>
    /// Post-processes Mermaid ERD to fix syntax issues.
    /// 1. Removes data type parameters like DECIMAL(10,2) → DECIMAL
    /// 2. Replaces Norwegian/special characters (Ø, Æ, Å) with ASCII equivalents
    /// </summary>
    private string PostProcessMermaidErd(string mermaid)
    {
        if (string.IsNullOrWhiteSpace(mermaid))
            return mermaid;
        
        Logger.Info("=== PostProcessMermaidErd START ===");
        Logger.Debug("Input length: {Length} chars", mermaid.Length);
        
        var result = mermaid;
        var typeChangesMade = 0;
        
        // Step 1: AGGRESSIVE data type stripping - remove ALL parentheses from type names
        // Match ANY word followed by parentheses containing numbers/commas
        // This is more aggressive than before to catch all cases
        
        // Pattern 1: Match TYPE(number) or TYPE(number,number) patterns
        var pattern1 = @"\b([A-Z_][A-Z0-9_]*)\s*\(\s*\d+\s*(?:,\s*\d+\s*)?\)";
        var beforeCount = System.Text.RegularExpressions.Regex.Matches(result, pattern1, 
            System.Text.RegularExpressions.RegexOptions.IgnoreCase).Count;
        
        result = System.Text.RegularExpressions.Regex.Replace(
            result,
            pattern1,
            match =>
            {
                typeChangesMade++;
                var simplified = match.Groups[1].Value;
                Logger.Debug("Pattern1: '{Original}' -> '{Simple}'", match.Value, simplified);
                return simplified;
            },
            System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        
        // Pattern 2: Also catch any remaining TYPE(...) patterns where ... might contain other chars
        var pattern2 = @"\b(VARCHAR|CHAR|CHARACTER|DECIMAL|NUMERIC|DEC|NUMBER|INTEGER|INT|BIGINT|SMALLINT|TINYINT|FLOAT|DOUBLE|REAL|TIMESTAMP|DATETIME|DATE|TIME|BLOB|CLOB|TEXT|NVARCHAR|NCHAR|BOOLEAN|BOOL|UUID|BINARY|VARBINARY|BIT|MONEY|CURRENCY)\s*\([^)]*\)";
        
        result = System.Text.RegularExpressions.Regex.Replace(
            result,
            pattern2,
            match =>
            {
                typeChangesMade++;
                var simplified = match.Groups[1].Value;
                Logger.Debug("Pattern2: '{Original}' -> '{Simple}'", match.Value, simplified);
                return simplified;
            },
            System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        
        Logger.Info("Data type post-processing: {Count} types simplified", typeChangesMade);
        
        // Step 2: Replace Norwegian/Scandinavian characters (database often uses ANSI 1252)
        var originalLength = result.Length;
        result = result.Replace("Æ", "AE").Replace("æ", "ae");
        result = result.Replace("Ø", "O").Replace("ø", "o");
        result = result.Replace("Å", "AA").Replace("å", "aa");
        
        // German characters
        result = result.Replace("Ü", "UE").Replace("ü", "ue");
        result = result.Replace("Ö", "OE").Replace("ö", "oe");
        result = result.Replace("Ä", "AE").Replace("ä", "ae");
        result = result.Replace("ß", "ss");
        
        // French accents
        result = result.Replace("É", "E").Replace("é", "e");
        result = result.Replace("È", "E").Replace("è", "e");
        result = result.Replace("Ê", "E").Replace("ê", "e");
        result = result.Replace("À", "A").Replace("à", "a");
        result = result.Replace("Ç", "C").Replace("ç", "c");
        
        // Spanish
        result = result.Replace("Ñ", "N").Replace("ñ", "n");
        
        // Step 3: Remove any remaining problematic characters in identifiers
        // But keep quoted strings intact (for comments)
        var lines = result.Split('\n');
        var processedLines = new List<string>();
        
        foreach (var line in lines)
        {
            var processedLine = line;
            
            // For lines that define table/column (not relationships or erDiagram header)
            // Replace any non-ASCII chars that might have slipped through
            if (!line.TrimStart().StartsWith("erDiagram") && 
                !line.Contains("||") && !line.Contains("}o") && !line.Contains("o{"))
            {
                // Split by quotes to preserve quoted strings
                var parts = System.Text.RegularExpressions.Regex.Split(processedLine, @"(""[^""]*"")");
                for (int i = 0; i < parts.Length; i++)
                {
                    // Only process non-quoted parts
                    if (!parts[i].StartsWith("\""))
                    {
                        // Replace any remaining non-ASCII chars with underscore
                        parts[i] = System.Text.RegularExpressions.Regex.Replace(
                            parts[i], @"[^\x00-\x7F]", "_");
                    }
                }
                processedLine = string.Join("", parts);
            }
            
            processedLines.Add(processedLine);
        }
        
        result = string.Join("\n", processedLines);
        
        if (result.Length != originalLength || typeChangesMade > 0)
        {
            Logger.Info("Post-processing complete - {TypeChanges} type fixes, length change: {LenChange} chars",
                typeChangesMade, result.Length - mermaid.Length);
        }
        
        Logger.Debug("Output Mermaid (first 500 chars): {Preview}", 
            result.Length > 500 ? result.Substring(0, 500) : result);
        
        return result;
    }
    
    /// <summary>
    /// Formats DB2 data types to SQL standard format.
    /// </summary>
    private string FormatDb2DataType(string typeName, object? length, object? scale)
    {
        var type = typeName.ToUpperInvariant();
        
        switch (type)
        {
            case "VARCHAR":
            case "CHAR":
            case "CHARACTER":
                return $"{type}({length})";
            
            case "DECIMAL":
            case "NUMERIC":
            case "DEC":
                return $"DECIMAL({length},{scale})";
            
            case "INTEGER":
                return "INT";
            
            case "BIGINT":
            case "SMALLINT":
            case "REAL":
            case "DOUBLE":
            case "FLOAT":
            case "DATE":
            case "TIME":
            case "TIMESTAMP":
            case "BLOB":
            case "CLOB":
                return type;
            
            default:
                return type;
        }
    }
}

