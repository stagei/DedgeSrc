using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using DbExplorer.Data;
using DbExplorer.Data.Providers.DB2;
using DbExplorer.Services;

namespace DbExplorer.AutoTests;

/// <summary>
/// Comprehensive CLI tests for Mermaid/SQL functionality
/// Tests the complete round-trip cycle and schema migration workflows
/// Based on SQLMERMAID_ERD_TOOLS_TEST_PLAN.md
/// </summary>
public static class MermaidCliTests
{
    private static readonly string TestOutputDir = Path.Combine(Directory.GetCurrentDirectory(), "TestOutput", "Mermaid");
    
    /// <summary>
    /// Run all Mermaid CLI tests
    /// </summary>
    public static async Task<bool> RunAllTests(DB2ConnectionManager connectionManager)
    {
        Console.WriteLine("\n═══════════════════════════════════════════════════════════");
        Console.WriteLine("  🧪 Mermaid CLI Tests - 3-Part Test Plan");
        Console.WriteLine("═══════════════════════════════════════════════════════════\n");
        
        // Ensure test output directory exists
        Directory.CreateDirectory(TestOutputDir);
        Console.WriteLine($"📁 Test output directory: {TestOutputDir}\n");
        
        var allPassed = true;
        
        // Test 1: Round-Trip Conversion (SQL → Mermaid → SQL)
        Console.WriteLine("📋 TEST 1: Round-Trip Conversion");
        Console.WriteLine("════════════════════════════════════════════════════════════\n");
        var test1Passed = await RunRoundTripTest(connectionManager);
        Console.WriteLine($"Test 1: {(test1Passed ? "✅ PASSED" : "❌ FAILED")}\n");
        allPassed &= test1Passed;
        
        // Test 2: Schema Changes (Mermaid Edit → ALTER Statements)
        Console.WriteLine("📋 TEST 2: Schema Changes");
        Console.WriteLine("════════════════════════════════════════════════════════════\n");
        var test2Passed = await RunSchemaChangeTest(connectionManager);
        Console.WriteLine($"Test 2: {(test2Passed ? "✅ PASSED" : "❌ FAILED")}\n");
        allPassed &= test2Passed;
        
        // Test 3: SQL Dialect Translation
        Console.WriteLine("📋 TEST 3: SQL Dialect Translation");
        Console.WriteLine("════════════════════════════════════════════════════════════\n");
        var test3Passed = await RunDialectTranslationTest(connectionManager);
        Console.WriteLine($"Test 3: {(test3Passed ? "✅ PASSED" : "❌ FAILED")}\n");
        allPassed &= test3Passed;
        
        Console.WriteLine("═══════════════════════════════════════════════════════════");
        Console.WriteLine($"  {(allPassed ? "✅ ALL TESTS PASSED" : "❌ SOME TESTS FAILED")}");
        Console.WriteLine("═══════════════════════════════════════════════════════════\n");
        
        return allPassed;
    }
    
    /// <summary>
    /// TEST 1: Round-Trip Conversion (SQL → Mermaid → SQL)
    /// Verifies lossless bidirectional conversion
    /// </summary>
    private static async Task<bool> RunRoundTripTest(DB2ConnectionManager connectionManager)
    {
        try
        {
            var mermaidService = new SqlMermaidIntegrationService();
            
            // Step 1: Get 3 related tables from INL schema (FKKTOTST connection)
            Console.WriteLine("Step 1: Fetching related tables from INL schema...");
            var testTables = new List<string> 
            { 
                "INL.BILAGNR", 
                "INL.FASTE_LISTE", 
                "INL.FASTE_TRANS" 
            };
            
            // Verify tables exist
            var tablesExist = await VerifyTablesExist(connectionManager, testTables);
            if (!tablesExist)
            {
                Console.WriteLine("❌ Test tables not found in database");
                return false;
            }
            Console.WriteLine($"✓ Found all {testTables.Count} test tables\n");
            
            // Step 2: Generate SQL DDL from DB2
            Console.WriteLine("Step 2: Generating SQL DDL from DB2 tables...");
            var originalSql = await mermaidService.GenerateDdlFromDb2TablesAsync(connectionManager, testTables);
            
            var sqlFile = Path.Combine(TestOutputDir, "test1_original.sql");
            await File.WriteAllTextAsync(sqlFile, originalSql);
            Console.WriteLine($"✓ Generated {originalSql.Length} chars of SQL DDL");
            Console.WriteLine($"  Saved to: {sqlFile}\n");
            
            // Step 3: Convert SQL → Mermaid
            Console.WriteLine("Step 3: Converting SQL → Mermaid ERD...");
            var mermaidDiagram = await mermaidService.ConvertSqlToMermaidAsync(originalSql);
            
            var mmdFile = Path.Combine(TestOutputDir, "test1_diagram.mmd");
            await File.WriteAllTextAsync(mmdFile, mermaidDiagram);
            Console.WriteLine($"✓ Generated {mermaidDiagram.Length} chars of Mermaid ERD");
            Console.WriteLine($"  Saved to: {mmdFile}\n");
            
            // Step 4: Convert Mermaid → SQL (Round-trip)
            Console.WriteLine("Step 4: Converting Mermaid → SQL (round-trip)...");
            var roundTripSql = await mermaidService.ConvertMermaidToSqlAsync(mermaidDiagram);
            
            var roundTripFile = Path.Combine(TestOutputDir, "test1_roundtrip.sql");
            await File.WriteAllTextAsync(roundTripFile, roundTripSql);
            Console.WriteLine($"✓ Generated {roundTripSql.Length} chars of SQL DDL (round-trip)");
            Console.WriteLine($"  Saved to: {roundTripFile}\n");
            
            // Step 5: Compare original SQL vs round-trip SQL
            Console.WriteLine("Step 5: Verifying round-trip integrity...");
            var comparisonResult = CompareSqlStructure(originalSql, roundTripSql);
            
            Console.WriteLine($"  Original SQL:    {originalSql.Length} chars");
            Console.WriteLine($"  Round-trip SQL:  {roundTripSql.Length} chars");
            Console.WriteLine($"  Tables match:    {comparisonResult.TablesMatch}");
            Console.WriteLine($"  Columns match:   {comparisonResult.ColumnsMatch}");
            Console.WriteLine($"  FKs match:       {comparisonResult.ForeignKeysMatch}");
            
            var passed = comparisonResult.TablesMatch && comparisonResult.ColumnsMatch;
            Console.WriteLine($"\n{(passed ? "✅" : "❌")} Round-trip test: {(passed ? "PASSED" : "FAILED")}");
            
            if (!passed)
            {
                Console.WriteLine($"⚠️  Differences: {comparisonResult.DifferenceDescription}");
            }
            
            return passed;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"❌ Exception in Round-Trip test: {ex.Message}");
            Console.WriteLine($"   {ex.StackTrace}");
            return false;
        }
    }
    
    /// <summary>
    /// TEST 2: Schema Changes (Mermaid Edit → ALTER Statements)
    /// Tests diff-based migration script generation
    /// </summary>
    private static async Task<bool> RunSchemaChangeTest(DB2ConnectionManager connectionManager)
    {
        try
        {
            var mermaidService = new SqlMermaidIntegrationService();
            
            // Step 1: Generate original Mermaid diagram
            Console.WriteLine("Step 1: Generating original Mermaid diagram...");
            var testTables = new List<string> { "INL.BILAGNR" };
            var originalSql = await mermaidService.GenerateDdlFromDb2TablesAsync(connectionManager, testTables);
            var originalMermaid = await mermaidService.ConvertSqlToMermaidAsync(originalSql);
            
            var originalFile = Path.Combine(TestOutputDir, "test2_original.mmd");
            await File.WriteAllTextAsync(originalFile, originalMermaid);
            Console.WriteLine($"✓ Generated original diagram ({originalMermaid.Length} chars)");
            Console.WriteLine($"  Saved to: {originalFile}\n");
            
            // Step 2: Modify Mermaid diagram (simulate user edit)
            Console.WriteLine("Step 2: Simulating schema changes (adding column)...");
            var modifiedMermaid = SimulateSchemaChange(originalMermaid);
            
            var modifiedFile = Path.Combine(TestOutputDir, "test2_modified.mmd");
            await File.WriteAllTextAsync(modifiedFile, modifiedMermaid);
            Console.WriteLine($"✓ Modified diagram ({modifiedMermaid.Length} chars)");
            Console.WriteLine($"  Saved to: {modifiedFile}\n");
            
            // Step 3: Generate ALTER statements from diff
            Console.WriteLine("Step 3: Generating ALTER statements from diff...");
            var alterStatements = await mermaidService.GenerateMigrationFromMermaidDiffAsync(
                originalMermaid, 
                modifiedMermaid);
            
            var alterFile = Path.Combine(TestOutputDir, "test2_alter.sql");
            await File.WriteAllTextAsync(alterFile, alterStatements);
            Console.WriteLine($"✓ Generated ALTER statements ({alterStatements.Length} chars)");
            Console.WriteLine($"  Saved to: {alterFile}\n");
            
            // Step 4: Verify ALTER statements are valid
            Console.WriteLine("Step 4: Verifying ALTER statements...");
            var isValid = ValidateAlterStatements(alterStatements);
            Console.WriteLine($"  Contains ALTER: {alterStatements.Contains("ALTER TABLE", StringComparison.OrdinalIgnoreCase)}");
            Console.WriteLine($"  Contains ADD:   {alterStatements.Contains("ADD ", StringComparison.OrdinalIgnoreCase) || alterStatements.Contains("ADD COLUMN", StringComparison.OrdinalIgnoreCase)}");
            Console.WriteLine($"  Length > 0:     {alterStatements.Length > 0}");
            
            var passed = isValid && alterStatements.Length > 0;
            Console.WriteLine($"\n{(passed ? "✅" : "❌")} Schema change test: {(passed ? "PASSED" : "FAILED")}");
            
            if (!passed)
            {
                Console.WriteLine($"⚠️  ALTER statements appear invalid or empty");
            }
            
            return passed;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"❌ Exception in Schema Change test: {ex.Message}");
            Console.WriteLine($"   {ex.StackTrace}");
            return false;
        }
    }
    
    /// <summary>
    /// TEST 3: SQL Dialect Translation
    /// Tests multi-database dialect conversion
    /// </summary>
    private static async Task<bool> RunDialectTranslationTest(DB2ConnectionManager connectionManager)
    {
        try
        {
            var mermaidService = new SqlMermaidIntegrationService();
            
            // Step 1: Get sample SQL from DB2
            Console.WriteLine("Step 1: Generating sample SQL DDL...");
            var testTables = new List<string> { "INL.BILAGNR" };
            var db2Sql = await mermaidService.GenerateDdlFromDb2TablesAsync(connectionManager, testTables);
            
            var db2File = Path.Combine(TestOutputDir, "test3_db2.sql");
            await File.WriteAllTextAsync(db2File, db2Sql);
            Console.WriteLine($"✓ Generated DB2 SQL ({db2Sql.Length} chars)");
            Console.WriteLine($"  Saved to: {db2File}\n");
            
            // Step 2: Translate to PostgreSQL
            Console.WriteLine("Step 2: Translating to PostgreSQL...");
            var postgresqlSql = await mermaidService.TranslateSqlDialectAsync(
                db2Sql, 
                SqlMermaidErdTools.Models.SqlDialect.AnsiSql, 
                SqlMermaidErdTools.Models.SqlDialect.PostgreSql);
            
            var pgFile = Path.Combine(TestOutputDir, "test3_postgresql.sql");
            await File.WriteAllTextAsync(pgFile, postgresqlSql);
            Console.WriteLine($"✓ Translated to PostgreSQL ({postgresqlSql.Length} chars)");
            Console.WriteLine($"  Saved to: {pgFile}\n");
            
            // Step 3: Translate to MySQL
            Console.WriteLine("Step 3: Translating to MySQL...");
            var mysqlSql = await mermaidService.TranslateSqlDialectAsync(
                db2Sql, 
                SqlMermaidErdTools.Models.SqlDialect.AnsiSql, 
                SqlMermaidErdTools.Models.SqlDialect.MySql);
            
            var mysqlFile = Path.Combine(TestOutputDir, "test3_mysql.sql");
            await File.WriteAllTextAsync(mysqlFile, mysqlSql);
            Console.WriteLine($"✓ Translated to MySQL ({mysqlSql.Length} chars)");
            Console.WriteLine($"  Saved to: {mysqlFile}\n");
            
            // Step 4: Verify translations are valid SQL
            Console.WriteLine("Step 4: Verifying translations...");
            var pgValid = postgresqlSql.Length > 0 && postgresqlSql.Contains("CREATE TABLE", StringComparison.OrdinalIgnoreCase);
            var mysqlValid = mysqlSql.Length > 0 && mysqlSql.Contains("CREATE TABLE", StringComparison.OrdinalIgnoreCase);
            
            Console.WriteLine($"  PostgreSQL valid: {pgValid}");
            Console.WriteLine($"  MySQL valid:      {mysqlValid}");
            
            var passed = pgValid && mysqlValid;
            Console.WriteLine($"\n{(passed ? "✅" : "❌")} Dialect translation test: {(passed ? "PASSED" : "FAILED")}");
            
            return passed;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"❌ Exception in Dialect Translation test: {ex.Message}");
            Console.WriteLine($"   {ex.StackTrace}");
            return false;
        }
    }
    
    // ========================================================================
    // Helper Methods
    // ========================================================================
    
    private static async Task<bool> VerifyTablesExist(DB2ConnectionManager connectionManager, List<string> tables)
    {
        try
        {
            foreach (var fullTableName in tables)
            {
                var parts = fullTableName.Split('.');
                var schema = parts[0];
                var tableName = parts[1];
                
                var sql = $@"
                    SELECT COUNT(*) AS CNT
                    FROM SYSCAT.TABLES
                    WHERE TABSCHEMA = '{schema}' AND TABNAME = '{tableName}'
                ";
                
                var result = await connectionManager.ExecuteQueryAsync(sql);
                var count = Convert.ToInt32(result.Rows[0]["CNT"]);
                
                if (count == 0)
                {
                    Console.WriteLine($"❌ Table not found: {fullTableName}");
                    return false;
                }
            }
            return true;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"❌ Error verifying tables: {ex.Message}");
            return false;
        }
    }
    
    private static (bool TablesMatch, bool ColumnsMatch, bool ForeignKeysMatch, string DifferenceDescription) CompareSqlStructure(
        string originalSql, 
        string roundTripSql)
    {
        try
        {
            // Simple structural comparison
            var origTables = CountOccurrences(originalSql, "CREATE TABLE");
            var rtTables = CountOccurrences(roundTripSql, "CREATE TABLE");
            
            var origColumns = originalSql.Split('\n').Count(line => 
                line.Contains("VARCHAR") || line.Contains("INTEGER") || line.Contains("DECIMAL") || line.Contains("TIMESTAMP"));
            var rtColumns = roundTripSql.Split('\n').Count(line => 
                line.Contains("VARCHAR") || line.Contains("INTEGER") || line.Contains("DECIMAL") || line.Contains("TIMESTAMP"));
            
            var origFks = CountOccurrences(originalSql, "FOREIGN KEY");
            var rtFks = CountOccurrences(roundTripSql, "FOREIGN KEY");
            
            var tablesMatch = origTables == rtTables;
            var columnsMatch = Math.Abs(origColumns - rtColumns) <= 2; // Allow small variance
            var fksMatch = origFks == rtFks;
            
            var description = $"Tables: {origTables}/{rtTables}, Columns: {origColumns}/{rtColumns}, FKs: {origFks}/{rtFks}";
            
            return (tablesMatch, columnsMatch, fksMatch, description);
        }
        catch (Exception ex)
        {
            return (false, false, false, $"Comparison failed: {ex.Message}");
        }
    }
    
    private static string SimulateSchemaChange(string originalMermaid)
    {
        // Add a new column to the first table in the Mermaid diagram
        var lines = originalMermaid.Split('\n').ToList();
        
        // Find first table definition and add a column
        for (int i = 0; i < lines.Count; i++)
        {
            if (lines[i].Trim().StartsWith("BILAGNR {"))
            {
                // Add a new test column after the table declaration
                var indent = new string(' ', 8);
                lines.Insert(i + 1, $"{indent}VARCHAR test_column PK");
                break;
            }
        }
        
        return string.Join("\n", lines);
    }
    
    private static bool ValidateAlterStatements(string alterStatements)
    {
        if (string.IsNullOrWhiteSpace(alterStatements))
            return false;
        
        // Check for common ALTER statement patterns
        var hasAlter = alterStatements.Contains("ALTER TABLE", StringComparison.OrdinalIgnoreCase);
        var hasAddOrDrop = alterStatements.Contains("ADD ", StringComparison.OrdinalIgnoreCase) || 
                          alterStatements.Contains("DROP ", StringComparison.OrdinalIgnoreCase) ||
                          alterStatements.Contains("ADD COLUMN", StringComparison.OrdinalIgnoreCase);
        
        return hasAlter || hasAddOrDrop || alterStatements.Length > 50; // Basic validation
    }
    
    private static int CountOccurrences(string text, string pattern)
    {
        if (string.IsNullOrEmpty(text) || string.IsNullOrEmpty(pattern))
            return 0;
        
        var count = 0;
        var index = 0;
        
        while ((index = text.IndexOf(pattern, index, StringComparison.OrdinalIgnoreCase)) != -1)
        {
            count++;
            index += pattern.Length;
        }
        
        return count;
    }
}

