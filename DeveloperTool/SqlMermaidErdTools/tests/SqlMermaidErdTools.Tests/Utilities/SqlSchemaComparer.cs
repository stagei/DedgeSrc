using System.Text.RegularExpressions;

namespace SqlMermaidErdTools.Tests.Utilities;

/// <summary>
/// Utility for comparing SQL schemas semantically rather than textually.
/// </summary>
public static class SqlSchemaComparer
{
    /// <summary>
    /// Compares two SQL schemas for semantic equivalence.
    /// </summary>
    public static SchemaComparisonResult Compare(string expectedSql, string actualSql)
    {
        var result = new SchemaComparisonResult();
        
        // Normalize both SQL strings
        var normalizedExpected = NormalizeSql(expectedSql);
        var normalizedActual = NormalizeSql(actualSql);
        
        // Extract table definitions
        var expectedTables = ExtractTables(normalizedExpected);
        var actualTables = ExtractTables(normalizedActual);
        
        // Compare table count
        if (expectedTables.Count != actualTables.Count)
        {
            result.Differences.Add($"Table count mismatch: expected {expectedTables.Count}, got {actualTables.Count}");
        }
        
        // Compare each table
        foreach (var expectedTable in expectedTables)
        {
            if (!actualTables.ContainsKey(expectedTable.Key))
            {
                result.Differences.Add($"Missing table: {expectedTable.Key}");
                continue;
            }
            
            var actualTable = actualTables[expectedTable.Key];
            CompareTableDefinitions(expectedTable.Key, expectedTable.Value, actualTable, result);
        }
        
        // Check for extra tables
        foreach (var actualTable in actualTables)
        {
            if (!expectedTables.ContainsKey(actualTable.Key))
            {
                result.Differences.Add($"Extra table: {actualTable.Key}");
            }
        }
        
        // Calculate similarity score
        result.SimilarityScore = CalculateSimilarity(expectedSql, actualSql, result.Differences.Count);
        result.IsMatch = result.Differences.Count == 0;
        
        return result;
    }
    
    private static string NormalizeSql(string sql)
    {
        if (string.IsNullOrWhiteSpace(sql))
            return string.Empty;
        
        // Remove comments
        sql = Regex.Replace(sql, @"--[^\n]*", "");
        sql = Regex.Replace(sql, @"/\*.*?\*/", "", RegexOptions.Singleline);
        
        // Normalize whitespace
        sql = Regex.Replace(sql, @"\s+", " ");
        
        // Normalize to uppercase for comparison
        sql = sql.ToUpperInvariant();
        
        return sql.Trim();
    }
    
    private static Dictionary<string, string> ExtractTables(string sql)
    {
        var tables = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        
        // Match CREATE TABLE statements
        var pattern = @"CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?([`""'\[]?[\w]+[`""'\]]?)\s*\((.*?)\)(?:\s*;)?";
        var matches = Regex.Matches(sql, pattern, RegexOptions.Singleline | RegexOptions.IgnoreCase);
        
        foreach (Match match in matches)
        {
            var tableName = match.Groups[1].Value.Trim('[', ']', '`', '"', '\'');
            var tableDefinition = match.Groups[2].Value;
            tables[tableName] = tableDefinition;
        }
        
        return tables;
    }
    
    private static void CompareTableDefinitions(
        string tableName,
        string expectedDef,
        string actualDef,
        SchemaComparisonResult result)
    {
        // Extract columns from both definitions
        var expectedColumns = ExtractColumns(expectedDef);
        var actualColumns = ExtractColumns(actualDef);
        
        // Compare column count
        if (expectedColumns.Count != actualColumns.Count)
        {
            result.Differences.Add(
                $"Table '{tableName}': column count mismatch (expected {expectedColumns.Count}, got {actualColumns.Count})");
        }
        
        // Compare each column
        foreach (var expectedCol in expectedColumns)
        {
            if (!actualColumns.Contains(expectedCol))
            {
                // Try fuzzy match (allow for minor type differences)
                var fuzzyMatch = actualColumns.FirstOrDefault(c => 
                    c.StartsWith(expectedCol.Split(' ')[0], StringComparison.OrdinalIgnoreCase));
                
                if (fuzzyMatch == null)
                {
                    result.Differences.Add($"Table '{tableName}': missing or different column '{expectedCol}'");
                }
            }
        }
        
        // Check for extra columns
        foreach (var actualCol in actualColumns)
        {
            if (!expectedColumns.Contains(actualCol))
            {
                var fuzzyMatch = expectedColumns.FirstOrDefault(c => 
                    c.StartsWith(actualCol.Split(' ')[0], StringComparison.OrdinalIgnoreCase));
                
                if (fuzzyMatch == null)
                {
                    result.Differences.Add($"Table '{tableName}': extra column '{actualCol}'");
                }
            }
        }
    }
    
    private static List<string> ExtractColumns(string tableDefinition)
    {
        var columns = new List<string>();
        
        // Split by comma (basic approach - could be improved for nested structures)
        var parts = tableDefinition.Split(',');
        
        foreach (var part in parts)
        {
            var trimmed = part.Trim();
            
            // Skip constraint definitions
            if (trimmed.StartsWith("CONSTRAINT", StringComparison.OrdinalIgnoreCase) ||
                trimmed.StartsWith("PRIMARY KEY", StringComparison.OrdinalIgnoreCase) ||
                trimmed.StartsWith("FOREIGN KEY", StringComparison.OrdinalIgnoreCase) ||
                trimmed.StartsWith("UNIQUE", StringComparison.OrdinalIgnoreCase) ||
                trimmed.StartsWith("CHECK", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }
            
            if (!string.IsNullOrWhiteSpace(trimmed))
            {
                columns.Add(trimmed);
            }
        }
        
        return columns;
    }
    
    private static double CalculateSimilarity(string expected, string actual, int differenceCount)
    {
        if (differenceCount == 0)
            return 1.0;
        
        // Simple similarity based on length and difference count
        var maxLength = Math.Max(expected.Length, actual.Length);
        if (maxLength == 0)
            return 1.0;
        
        // Each difference reduces similarity
        var penalty = differenceCount * 0.1;
        var similarity = Math.Max(0.0, 1.0 - penalty);
        
        return similarity;
    }
}

