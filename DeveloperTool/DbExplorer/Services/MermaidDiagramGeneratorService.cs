using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using NLog;
using DbExplorer.Data;
using DbExplorer.Models;

namespace DbExplorer.Services;

/// <summary>
/// REFACTORED: Now uses SqlMermaidErdTools for Mermaid generation instead of custom implementation.
/// DB2 metadata extraction is preserved, but Mermaid generation uses SqlMermaidErdTools.ToMermaid().
/// </summary>
public class MermaidDiagramGeneratorService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly SqlMermaidIntegrationService _sqlMermaidService;
    
    public MermaidDiagramGeneratorService()
    {
        _sqlMermaidService = new SqlMermaidIntegrationService();
    }
    
    /// <summary>
    /// REFACTORED: Now uses SqlMermaidErdTools for superior Mermaid generation.
    /// Process: Database metadata → SQL DDL → SqlMermaidErdTools.ToMermaid() → Mermaid ERD
    /// </summary>
    public async Task<string> GenerateMermaidDiagramAsync(
        IConnectionManager connectionManager,
        List<string> selectedTables)
    {
        Logger.Info("╔══════════════════════════════════════════════════════════════════╗");
        Logger.Info("║ MERMAID GENERATION START                                          ║");
        Logger.Info("╚══════════════════════════════════════════════════════════════════╝");
        Logger.Info("Table count: {Count}", selectedTables.Count);
        Logger.Debug("Selected tables: {Tables}", string.Join(", ", selectedTables));
        
        string mermaid = string.Empty;
        
        try
        {
            Logger.Debug(">>> Calling SqlMermaidIntegrationService.GenerateMermaidFromDb2TablesAsync...");
            mermaid = await _sqlMermaidService.GenerateMermaidFromDb2TablesAsync(
                connectionManager,
                selectedTables);
            
            Logger.Info("SqlMermaidErdTools returned {Length} chars", mermaid?.Length ?? 0);
            
            if (string.IsNullOrEmpty(mermaid))
            {
                Logger.Error("SqlMermaidErdTools returned NULL or EMPTY!");
                throw new InvalidOperationException("SqlMermaidErdTools returned empty result");
            }
            
            Logger.Debug("Raw output from SqlMermaidErdTools (first 500 chars):\n{Preview}", 
                mermaid.Length > 500 ? mermaid.Substring(0, 500) : mermaid);
            
            // Check for problematic patterns BEFORE stripping
            var hasDecimalBefore = mermaid.Contains("DECIMAL(");
            var hasVarcharBefore = mermaid.Contains("VARCHAR(");
            Logger.Debug("Before FinalSafety - DECIMAL(: {D}, VARCHAR(: {V}", hasDecimalBefore, hasVarcharBefore);
            
            // FINAL SAFETY: Strip any remaining parameterized types
            Logger.Debug(">>> Calling FinalSafetyStripDataTypes...");
            mermaid = FinalSafetyStripDataTypes(mermaid);
            Logger.Debug("<<< FinalSafetyStripDataTypes returned");
            
            // Check for problematic patterns AFTER stripping
            var hasDecimalAfter = mermaid.Contains("DECIMAL(");
            var hasVarcharAfter = mermaid.Contains("VARCHAR(");
            Logger.Debug("After FinalSafety - DECIMAL(: {D}, VARCHAR(: {V}", hasDecimalAfter, hasVarcharAfter);
            
            if (hasDecimalAfter || hasVarcharAfter)
            {
                Logger.Error("!!! CRITICAL: FinalSafetyStripDataTypes FAILED to remove parameterized types !!!");
                Logger.Error("Mermaid still contains: {Content}", mermaid);
            }
            
            Logger.Info("║ MERMAID GENERATION COMPLETE (SqlMermaidErdTools) ║");
            return mermaid;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "SqlMermaidErdTools failed - Type: {Type}, Message: {Message}", 
                ex.GetType().Name, ex.Message);
            Logger.Debug("Stack trace: {Stack}", ex.StackTrace);
            
            if (ex.InnerException != null)
            {
                Logger.Error("Inner exception - Type: {Type}, Message: {Message}",
                    ex.InnerException.GetType().Name, ex.InnerException.Message);
            }
            
            // Fallback to legacy method
            Logger.Info(">>> Attempting legacy Mermaid generation...");
            try
            {
                var legacyMermaid = await GenerateMermaidDiagramLegacyAsync(connectionManager, selectedTables);
                Logger.Info("Legacy generation returned {Length} chars", legacyMermaid?.Length ?? 0);
                
                Logger.Debug(">>> Calling FinalSafetyStripDataTypes on legacy output...");
                var result = FinalSafetyStripDataTypes(legacyMermaid);
                Logger.Debug("<<< FinalSafetyStripDataTypes returned");
                
                Logger.Info("║ MERMAID GENERATION COMPLETE (Legacy) ║");
                return result;
            }
            catch (Exception legacyEx)
            {
                Logger.Error(legacyEx, "Legacy generation also failed!");
                throw new AggregateException("Both SqlMermaidErdTools and legacy generation failed", ex, legacyEx);
            }
        }
    }
    
    /// <summary>
    /// FINAL SAFETY: Aggressively strips any remaining data type parameters.
    /// Mermaid ERD cannot parse types like VARCHAR(50) or DECIMAL(10,2).
    /// </summary>
    private string FinalSafetyStripDataTypes(string mermaid)
    {
        Logger.Debug(">>> FinalSafetyStripDataTypes ENTER - input length: {Len}", mermaid?.Length ?? 0);
        
        if (string.IsNullOrEmpty(mermaid))
        {
            Logger.Debug("<<< FinalSafetyStripDataTypes EXIT - null/empty input");
            return mermaid;
        }
        
        Logger.Debug("Input preview (first 200): {Preview}", 
            mermaid.Length > 200 ? mermaid.Substring(0, 200) : mermaid);
        
        // Check if there are any problematic patterns
        var hasDecimal = mermaid.Contains("DECIMAL(");
        var hasVarchar = mermaid.Contains("VARCHAR(");
        var hasChar = mermaid.Contains("CHAR(");
        var hasAnyParen = Regex.IsMatch(mermaid, @"\b\w+\s*\(\s*\d");
        
        Logger.Debug("Pattern check - DECIMAL(: {D}, VARCHAR(: {V}, CHAR(: {C}, AnyParen: {A}",
            hasDecimal, hasVarchar, hasChar, hasAnyParen);
        
        if (!hasAnyParen && !hasDecimal && !hasVarchar && !hasChar)
        {
            Logger.Debug("<<< FinalSafetyStripDataTypes EXIT - no parenthesized types found");
            return mermaid;
        }
        
        Logger.Warn("!!! FinalSafetyStripDataTypes: FOUND parameterized types - MUST strip them !!!");
        
        var result = mermaid;
        var totalChanges = 0;
        
        // Pattern 1: Match specific known types with parentheses
        var knownTypes = new[] { "VARCHAR", "CHAR", "CHARACTER", "DECIMAL", "NUMERIC", "DEC", "NUMBER", 
            "INTEGER", "INT", "BIGINT", "SMALLINT", "TINYINT", "FLOAT", "DOUBLE", "REAL", 
            "TIMESTAMP", "DATETIME", "DATE", "TIME", "BLOB", "CLOB", "TEXT", "NVARCHAR", "NCHAR" };
        
        foreach (var typeName in knownTypes)
        {
            var pattern = $@"\b{typeName}\s*\([^)]+\)";
            var beforeCount = Regex.Matches(result, pattern, RegexOptions.IgnoreCase).Count;
            
            if (beforeCount > 0)
            {
                Logger.Debug("Stripping {Count} instances of {Type}(...)", beforeCount, typeName);
                result = Regex.Replace(result, pattern, typeName, RegexOptions.IgnoreCase);
                totalChanges += beforeCount;
            }
        }
        
        // Pattern 2: Generic catch-all for any remaining WORD(digits...) patterns
        var genericPattern = @"\b([A-Z_][A-Z0-9_]*)\s*\(\s*\d[^)]*\)";
        var genericMatches = Regex.Matches(result, genericPattern, RegexOptions.IgnoreCase);
        if (genericMatches.Count > 0)
        {
            Logger.Debug("Generic pattern found {Count} additional matches", genericMatches.Count);
            foreach (Match m in genericMatches)
            {
                Logger.Debug("  - '{Match}' will become '{Result}'", m.Value, m.Groups[1].Value);
            }
            result = Regex.Replace(result, genericPattern, "$1", RegexOptions.IgnoreCase);
            totalChanges += genericMatches.Count;
        }
        
        Logger.Info("FinalSafetyStripDataTypes: Stripped {Count} total parameterized types", totalChanges);
        Logger.Debug("Output preview (first 200): {Preview}", 
            result.Length > 200 ? result.Substring(0, 200) : result);
        Logger.Debug("<<< FinalSafetyStripDataTypes EXIT - output length: {Len}", result.Length);
        
        return result;
    }
    
    /// <summary>
    /// LEGACY METHOD: Preserved as fallback in case SqlMermaidErdTools fails.
    /// Uses old custom Mermaid generation logic.
    /// </summary>
    private async Task<string> GenerateMermaidDiagramLegacyAsync(
        IConnectionManager connectionManager,
        List<string> selectedTables)
    {
        Logger.Warn("Using legacy Mermaid generation method (fallback)");
        
        var tables = new List<MermaidTable>();
        
        foreach (var fullTableName in selectedTables)
        {
            var parts = fullTableName.Split('.');
            var schema = parts.Length == 2 ? parts[0] : "SYSCAT";
            var tableName = parts.Length == 2 ? parts[1] : fullTableName;
            
            var table = await GetTableStructureAsync(connectionManager, schema, tableName);
            if (table != null)
            {
                tables.Add(table);
            }
        }
        
        var relationships = await GetRelationshipsAsync(connectionManager, tables);
        
        return BuildMermaidERDiagramLegacy(tables, relationships);
    }
    
    private async Task<MermaidTable?> GetTableStructureAsync(
        IConnectionManager connectionManager,
        string schema,
        string tableName)
    {
        try
        {
            var sql = $@"
                SELECT 
                    c.COLNAME, c.TYPENAME, c.LENGTH, c.SCALE, c.NULLS, c.REMARKS,
                    CASE WHEN k.COLNAME IS NOT NULL THEN 1 ELSE 0 END AS IS_PK
                FROM SYSCAT.COLUMNS c
                LEFT JOIN SYSCAT.KEYCOLUSE k 
                    ON c.TABSCHEMA = k.TABSCHEMA 
                    AND c.TABNAME = k.TABNAME 
                    AND c.COLNAME = k.COLNAME
                WHERE c.TABSCHEMA = '{schema}' 
                  AND c.TABNAME = '{tableName}'
                ORDER BY c.COLNO
            ";
            
            var result = await connectionManager.ExecuteQueryAsync(sql);
            
            var table = new MermaidTable
            {
                Schema = schema,
                Name = tableName
            };
            
            foreach (DataRow row in result.Rows)
            {
                var column = new MermaidColumn
                {
                    Name = row["COLNAME"]?.ToString() ?? string.Empty,
                    DataType = FormatDataType(
                        row["TYPENAME"]?.ToString() ?? string.Empty,
                        row["LENGTH"],
                        row["SCALE"]),
                    IsPrimaryKey = Convert.ToInt32(row["IS_PK"]) == 1,
                    IsNullable = row["NULLS"]?.ToString() == "Y",
                    Comment = row["REMARKS"]?.ToString()
                };
                
                table.Columns.Add(column);
            }
            
            Logger.Debug("Loaded structure for {Schema}.{Table} - {Count} columns", schema, tableName, table.Columns.Count);
            return table;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to get structure for {Schema}.{Table}", schema, tableName);
            return null;
        }
    }
    
    private async Task<List<MermaidRelationship>> GetRelationshipsAsync(
        IConnectionManager connectionManager,
        List<MermaidTable> tables)
    {
        var relationships = new List<MermaidRelationship>();
        var schemas = tables.Select(t => t.Schema).Distinct().ToList();
        var schemaFilter = string.Join("','", schemas);
        
        try
        {
            var sql = $@"
                SELECT 
                    TABSCHEMA, TABNAME,
                    REFTABSCHEMA, REFTABNAME,
                    CONSTNAME, FK_COLNAMES
                FROM SYSCAT.REFERENCES
                WHERE TABSCHEMA IN ('{schemaFilter}')
                  AND REFTABSCHEMA IN ('{schemaFilter}')
            ";
            
            var result = await connectionManager.ExecuteQueryAsync(sql);
            
            foreach (DataRow row in result.Rows)
            {
                var fromTable = row["TABNAME"]?.ToString() ?? string.Empty;
                var toTable = row["REFTABNAME"]?.ToString() ?? string.Empty;
                
                if (tables.Any(t => t.Name == fromTable) && tables.Any(t => t.Name == toTable))
                {
                    relationships.Add(new MermaidRelationship
                    {
                        FromTable = fromTable,
                        ToTable = toTable,
                        Cardinality = "||--o{",
                        Label = row["CONSTNAME"]?.ToString()
                    });
                }
            }
            
            Logger.Info("Found {Count} relationships", relationships.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to get relationships");
        }
        
        return relationships;
    }
    
    /// <summary>
    /// LEGACY: Old custom Mermaid generation logic. Kept as fallback only.
    /// Primary method now uses SqlMermaidErdTools for better quality and compatibility.
    /// </summary>
    private string BuildMermaidERDiagramLegacy(List<MermaidTable> tables, List<MermaidRelationship> relationships)
    {
        Logger.Debug("Using legacy Mermaid ERD builder with identifier sanitization");
        
        var mermaid = new StringBuilder();
        mermaid.AppendLine("erDiagram");
        mermaid.AppendLine();
        
        // Build relationships with sanitized table names
        foreach (var rel in relationships)
        {
            var fromTable = SanitizeMermaidIdentifier(rel.FromTable);
            var toTable = SanitizeMermaidIdentifier(rel.ToTable);
            var line = $"    {fromTable} {rel.Cardinality} {toTable}";
            if (!string.IsNullOrEmpty(rel.Label))
                line += $" : \"{SanitizeMermaidIdentifier(rel.Label)}\"";
            mermaid.AppendLine(line);
        }
        
        if (relationships.Any())
            mermaid.AppendLine();
        
        // Build table definitions with sanitized names
        foreach (var table in tables)
        {
            var sanitizedTableName = SanitizeMermaidIdentifier(table.Name);
            mermaid.AppendLine($"    {sanitizedTableName} {{");
            
            foreach (var col in table.Columns)
            {
                var sanitizedColName = SanitizeMermaidIdentifier(col.Name);
                var sanitizedDataType = SanitizeMermaidIdentifier(col.DataType);
                var marker = col.IsPrimaryKey ? "PK" : col.IsForeignKey ? "FK" : "";
                // Comments can keep special chars since they're quoted
                var comment = !string.IsNullOrEmpty(col.Comment) ? $"\"{col.Comment}\"" : "";
                mermaid.AppendLine($"        {sanitizedDataType} {sanitizedColName} {marker} {comment}".TrimEnd());
            }
            
            mermaid.AppendLine("    }");
        }
        
        Logger.Debug("Generated Mermaid ERD with sanitized identifiers for {Count} tables", tables.Count);
        return mermaid.ToString();
    }
    
    /// <summary>
    /// Sanitizes an identifier (table or column name) for Mermaid ERD compatibility.
    /// Mermaid ERD only supports alphanumeric characters and underscores.
    /// Norwegian/Scandinavian characters (Æ, Ø, Å, æ, ø, å) and other special chars are replaced.
    /// </summary>
    private string SanitizeMermaidIdentifier(string identifier)
    {
        if (string.IsNullOrEmpty(identifier))
            return "UNKNOWN";
        
        var result = identifier.Trim();
        
        // Norwegian/Scandinavian character replacements
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
        result = result.Replace("Ë", "E").Replace("ë", "e");
        result = result.Replace("À", "A").Replace("à", "a");
        result = result.Replace("Â", "A").Replace("â", "a");
        result = result.Replace("Ô", "O").Replace("ô", "o");
        result = result.Replace("Î", "I").Replace("î", "i");
        result = result.Replace("Ï", "I").Replace("ï", "i");
        result = result.Replace("Ù", "U").Replace("ù", "u");
        result = result.Replace("Û", "U").Replace("û", "u");
        result = result.Replace("Ç", "C").Replace("ç", "c");
        
        // Spanish
        result = result.Replace("Ñ", "N").Replace("ñ", "n");
        
        // Remove any remaining non-alphanumeric characters except underscore
        result = Regex.Replace(result, @"[^a-zA-Z0-9_]", "_");
        
        // Ensure it starts with a letter (Mermaid requirement)
        if (result.Length > 0 && char.IsDigit(result[0]))
        {
            result = "T_" + result;
        }
        
        // If empty after sanitization, use default
        if (string.IsNullOrEmpty(result))
        {
            result = "UNKNOWN";
        }
        
        return result;
    }
    
    /// <summary>
    /// Format data type for Mermaid ERD.
    /// IMPORTANT: Mermaid ERD does NOT support data type parameters like VARCHAR(50) or DECIMAL(10,2).
    /// The comma in DECIMAL(10,2) breaks the parser. Return simple type names only.
    /// </summary>
    private string FormatDataType(string typeName, object? length, object? scale)
    {
        // Mermaid ERD syntax does NOT support complex data types with parameters
        // DECIMAL(10,2) causes "Expecting 'ATTRIBUTE_WORD', got 'COMMA'" error
        // Return simple type names only
        return SanitizeMermaidIdentifier(typeName?.Trim().ToUpperInvariant() ?? "VARCHAR");
    }
    
    public Dictionary<string, MermaidTable> ParseMermaidDiagram(string mermaidCode)
    {
        var tables = new Dictionary<string, MermaidTable>();
        var lines = mermaidCode.Split('\n');
        MermaidTable? currentTable = null;
        
        foreach (var line in lines)
        {
            var trimmed = line.Trim();
            
            if (Regex.IsMatch(trimmed, @"^(\w+)\s*\{"))
            {
                var match = Regex.Match(trimmed, @"^(\w+)\s*\{");
                currentTable = new MermaidTable { Name = match.Groups[1].Value };
                tables[currentTable.Name] = currentTable;
            }
            else if (trimmed == "}")
            {
                currentTable = null;
            }
            else if (currentTable != null && !string.IsNullOrWhiteSpace(trimmed))
            {
                var columnMatch = Regex.Match(trimmed, @"^(\S+)\s+(\w+)\s*(PK|FK)?\s*""?([^""]*)""?");
                if (columnMatch.Success)
                {
                    currentTable.Columns.Add(new MermaidColumn
                    {
                        DataType = columnMatch.Groups[1].Value,
                        Name = columnMatch.Groups[2].Value,
                        IsPrimaryKey = columnMatch.Groups[3].Value == "PK",
                        IsForeignKey = columnMatch.Groups[3].Value == "FK",
                        Comment = columnMatch.Groups[4].Value
                    });
                }
            }
        }
        
        return tables;
    }
}

