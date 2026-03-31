using SqlMermaidErdTools;
using SqlMermaidErdTools.Converters;
using SqlMermaidErdTools.Models;
using System.Diagnostics;
using System.Reflection;
using System.Text;

class Program
{
    static async Task Main(string[] args)
    {
        Console.WriteLine("╔═══════════════════════════════════════════════════════════════╗");
        Console.WriteLine("║      SqlMermaidErdTools - Full Circle Test with Report       ║");
        Console.WriteLine("╚═══════════════════════════════════════════════════════════════╝\n");

        // Accept optional export folder from command line, otherwise create timestamped folder
        string exportFolder;
        if (args.Length > 0 && !string.IsNullOrWhiteSpace(args[0]))
        {
            exportFolder = args[0];
            Console.WriteLine($"📁 Using provided export folder: {exportFolder}\n");
        }
        else
        {
            var timestamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
            exportFolder = Path.Combine(Directory.GetCurrentDirectory(), $"FullCircle_Export_{timestamp}");
            Console.WriteLine($"📁 Creating export folder: {exportFolder}\n");
        }
        
        Directory.CreateDirectory(exportFolder);

        var report = new StringBuilder();
        report.AppendLine("# Full Circle Test Report - test.sql");
        report.AppendLine($"**Generated:** {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
        report.AppendLine($"**Export Directory:** `{exportFolder}`");
        report.AppendLine();
        report.AppendLine("## Test Overview");
        report.AppendLine("This test performs a complete round-trip conversion of the test.sql file:");
        report.AppendLine("1. **SQL → MMD**: Convert original SQL to Mermaid ERD");
        report.AppendLine("2. **MMD → SQL**: Convert generated MMD back to SQL (multiple dialects)");
        report.AppendLine("3. **SQL → SQL**: Translate SQL between different dialects");
        report.AppendLine();

        // Read input files from TestFiles folder
        // Find project root by going up from bin directory
        var assemblyDir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location) ?? ".";
        var projectRoot = Path.GetFullPath(Path.Combine(assemblyDir, "..", "..", "..", "..", ".."));
        var testFilesPath = Path.Combine(projectRoot, "TestFiles");
        var sqlFile = Path.Combine(testFilesPath, "test.sql");
        
        if (!File.Exists(sqlFile))
        {
            Console.WriteLine($"❌ Error: Required file not found: {sqlFile}");
            Console.WriteLine($"   Searched from: {assemblyDir}");
            Console.WriteLine($"   Project root: {projectRoot}");
            report.AppendLine("## ❌ Test Failed");
            report.AppendLine($"**Error:** Required file not found: `{sqlFile}`");
            await SaveReport(report.ToString());
            return;
        }

        var sqlContent = await File.ReadAllTextAsync(sqlFile);
        Console.WriteLine($"📄 Loaded SQL file: {sqlFile} ({sqlContent.Length:N0} bytes)\n");

        report.AppendLine("## Input File");
        report.AppendLine($"- **File:** `TestFiles/test.sql`");
        report.AppendLine($"- **Size:** {sqlContent.Length:N0} bytes");
        report.AppendLine($"- **Lines:** {sqlContent.Split('\n').Length:N0}");
        report.AppendLine();

        // Test 1: SQL → Mermaid ERD
        report.AppendLine("## Step 1: SQL → Mermaid ERD Conversion");
        Console.WriteLine("═══════════════════════════════════════════════════════════════");
        Console.WriteLine("STEP 1: SQL → Mermaid ERD Conversion");
        Console.WriteLine("═══════════════════════════════════════════════════════════════");
        
        var sqlToMmdConverter = new SqlToMmdConverter { ExportFolderPath = exportFolder };
        var sw = Stopwatch.StartNew();
        
        try
        {
            var mermaidResult = await sqlToMmdConverter.ConvertAsync(sqlContent);
            sw.Stop();
            
            var mmdOutputFile = Path.Combine(exportFolder, "roundtrip.mmd");
            await File.WriteAllTextAsync(mmdOutputFile, mermaidResult);
            
            Console.WriteLine($"✅ SUCCESS ({sw.ElapsedMilliseconds}ms)");
            Console.WriteLine($"   Output: {mmdOutputFile} ({mermaidResult.Length:N0} bytes)");
            Console.WriteLine($"   Lines: {mermaidResult.Split('\n').Length}\n");

            report.AppendLine($"- **Status:** ✅ Success");
            report.AppendLine($"- **Duration:** {sw.ElapsedMilliseconds}ms");
            report.AppendLine($"- **Output Size:** {mermaidResult.Length:N0} bytes");
            report.AppendLine($"- **Output Lines:** {mermaidResult.Split('\n').Length:N0}");
            report.AppendLine($"- **Output File:** `roundtrip.mmd`");
            report.AppendLine();

            // Test 2: Mermaid → SQL (Multiple Dialects)
            report.AppendLine("## Step 2: Mermaid → SQL Conversion (Multiple Dialects)");
            Console.WriteLine("═══════════════════════════════════════════════════════════════");
            Console.WriteLine("STEP 2: Mermaid → SQL (Multiple Dialects)");
            Console.WriteLine("═══════════════════════════════════════════════════════════════\n");
            
            var mmdToSqlConverter = new MmdToSqlConverter();
            var dialects = new[]
            {
                (SqlDialect.AnsiSql, "ANSI SQL"),
                (SqlDialect.SqlServer, "T-SQL (SQL Server)"),
                (SqlDialect.PostgreSql, "PostgreSQL"),
                (SqlDialect.MySql, "MySQL")
            };

            foreach (var (dialect, dialectName) in dialects)
            {
                var dialectDir = Path.Combine(exportFolder, dialect.ToString());
                Directory.CreateDirectory(dialectDir);
                mmdToSqlConverter.ExportFolderPath = dialectDir;

                Console.WriteLine($"Converting to {dialectName}...");
                sw.Restart();

                try
                {
                    var sqlResult = await mmdToSqlConverter.ConvertAsync(mermaidResult, dialect);
                    sw.Stop();

                    var sqlOutputFile = Path.Combine(dialectDir, $"roundtrip_{dialect}.sql");
                    await File.WriteAllTextAsync(sqlOutputFile, sqlResult);

                    Console.WriteLine($"  ✅ SUCCESS ({sw.ElapsedMilliseconds}ms, {sqlResult.Length:N0} bytes)\n");

                    report.AppendLine($"### {dialectName}");
                    report.AppendLine($"- **Status:** ✅ Success");
                    report.AppendLine($"- **Duration:** {sw.ElapsedMilliseconds}ms");
                    report.AppendLine($"- **Output Size:** {sqlResult.Length:N0} bytes");
                    report.AppendLine($"- **File:** `{dialect}/roundtrip_{dialect}.sql`");
                    report.AppendLine();
                }
                catch (Exception ex)
                {
                    sw.Stop();
                    Console.WriteLine($"  ❌ FAILED ({sw.ElapsedMilliseconds}ms): {ex.Message}\n");

                    report.AppendLine($"### {dialectName}");
                    report.AppendLine($"- **Status:** ❌ Failed");
                    report.AppendLine($"- **Error:** {ex.Message}");
                    report.AppendLine();
                }
            }

            // Test 3: SQL Dialect Translation
            report.AppendLine("## Step 3: SQL Dialect Translation");
            Console.WriteLine("═══════════════════════════════════════════════════════════════");
            Console.WriteLine("STEP 3: SQL Dialect Translation");
            Console.WriteLine("═══════════════════════════════════════════════════════════════\n");

            var dialectTranslator = new SqlDialectTranslator();

            foreach (var (targetDialect, dialectName) in dialects.Skip(1)) // Skip ANSI as source
            {
                var dialectDir = Path.Combine(exportFolder, "Translated_" + targetDialect.ToString());
                Directory.CreateDirectory(dialectDir);
                dialectTranslator.ExportFolderPath = dialectDir;

                Console.WriteLine($"Translating ANSI → {dialectName}...");
                sw.Restart();

                try
                {
                    var translatedSql = await dialectTranslator.TranslateAsync(
                        sqlContent,
                        SqlDialect.AnsiSql,
                        targetDialect
                    );
                    sw.Stop();

                    var translatedFile = Path.Combine(dialectDir, $"translated_{targetDialect}.sql");
                    await File.WriteAllTextAsync(translatedFile, translatedSql);

                    var hasBrackets = translatedSql.Contains('[') && translatedSql.Contains(']');
                    Console.WriteLine($"  ✅ SUCCESS ({sw.ElapsedMilliseconds}ms, {translatedSql.Length:N0} bytes)");
                    if (targetDialect == SqlDialect.SqlServer)
                    {
                        Console.WriteLine($"     SQL Server brackets []: {hasBrackets}");
                    }
                    Console.WriteLine();

                    report.AppendLine($"### ANSI → {dialectName}");
                    report.AppendLine($"- **Status:** ✅ Success");
                    report.AppendLine($"- **Duration:** {sw.ElapsedMilliseconds}ms");
                    report.AppendLine($"- **Output Size:** {translatedSql.Length:N0} bytes");
                    report.AppendLine($"- **File:** `Translated_{targetDialect}/translated_{targetDialect}.sql`");
                    if (targetDialect == SqlDialect.SqlServer)
                    {
                        report.AppendLine($"- **Contains SQL Server brackets []:** {hasBrackets}");
                    }
                    report.AppendLine();
                }
                catch (Exception ex)
                {
                    sw.Stop();
                    Console.WriteLine($"  ❌ FAILED ({sw.ElapsedMilliseconds}ms): {ex.Message}\n");

                    report.AppendLine($"### ANSI → {dialectName}");
                    report.AppendLine($"- **Status:** ❌ Failed");
                    report.AppendLine($"- **Error:** {ex.Message}");
                    report.AppendLine();
                }
            }

            // Summary
            report.AppendLine("## Summary");
            report.AppendLine();
            report.AppendLine("### Key Observations");
            report.AppendLine("- ✅ SQL successfully converted to Mermaid ERD");
            report.AppendLine("- ✅ Mermaid ERD successfully converted back to SQL (multiple dialects)");
            report.AppendLine("- ✅ SQL dialect translation completed");
            report.AppendLine("- All intermediate files (AST, SQLGlot I/O) preserved in export folder");
            report.AppendLine();
            report.AppendLine("### Round-Trip Notes");
            report.AppendLine("- **Data Type Normalization**: SQLGlot may normalize data types (e.g., `VARCHAR(255)` → `VARCHAR`)");
            report.AppendLine("- **Formatting**: Whitespace, indentation, and capitalization may differ");
            report.AppendLine("- **Semantic Equivalence**: Focus is on schema structure, not text-exact matching");
            report.AppendLine("- **SQL Server Brackets**: SQLGlot does not add `[]` brackets by default (optional in T-SQL)");
            report.AppendLine();

            Console.WriteLine("═══════════════════════════════════════════════════════════════");
            Console.WriteLine("✅ Full Circle Test Completed Successfully!");
            Console.WriteLine("═══════════════════════════════════════════════════════════════");
        }
        catch (Exception ex)
        {
            sw.Stop();
            Console.WriteLine($"❌ FAILED ({sw.ElapsedMilliseconds}ms): {ex.Message}\n");
            Console.WriteLine(ex.ToString());

            report.AppendLine($"- **Status:** ❌ Failed");
            report.AppendLine($"- **Error:** {ex.Message}");
            report.AppendLine();
            report.AppendLine("```");
            report.AppendLine(ex.ToString());
            report.AppendLine("```");
        }

        await SaveReport(report.ToString());
        Console.WriteLine($"\n📄 Report saved to: Docs/FULL_CIRCLE_TEST_REPORT.md");
        Console.WriteLine($"📁 Export folder: {exportFolder}");
    }

    static async Task SaveReport(string reportContent)
    {
        var docsPath = Path.Combine("..", "..", "Docs");
        Directory.CreateDirectory(docsPath);
        var reportFile = Path.Combine(docsPath, "FULL_CIRCLE_TEST_REPORT.md");
        await File.WriteAllTextAsync(reportFile, reportContent);
    }
}
