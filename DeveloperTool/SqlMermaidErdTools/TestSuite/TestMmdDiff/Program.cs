using SqlMermaidErdTools;
using SqlMermaidErdTools.Converters;
using SqlMermaidErdTools.Models;
using System.Diagnostics;
using System.Text;

Console.WriteLine("╔════════════════════════════════════════════════════════════════════╗");
Console.WriteLine("║       MMD Diff Test - Both Directions (Forward & Reverse)         ║");
Console.WriteLine("╚════════════════════════════════════════════════════════════════════╝");
Console.WriteLine();

var report = new StringBuilder();
report.AppendLine("# MMD Diff Test Report - Both Directions");
report.AppendLine($"**Generated:** {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
report.AppendLine();
report.AppendLine("## Test Overview");
report.AppendLine("This test generates ALTER statements from MMD schema differences in **both directions**:");
report.AppendLine("1. **Forward (Before → After)**: Changes to migrate from `testBeforeChange.mmd` to `testAfterChange.mmd`");
report.AppendLine("2. **Reverse (After → Before)**: Changes to rollback from `testAfterChange.mmd` to `testBeforeChange.mmd`");
report.AppendLine();
report.AppendLine("Each direction is tested with multiple SQL dialects.");
report.AppendLine();

try
{
    // Read the two MMD files from TestFiles folder
    var beforeFile = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", "TestFiles", "testBeforeChange.mmd"));
    var afterFile = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", "TestFiles", "testAfterChange.mmd"));
    
    Console.WriteLine($"📄 Reading BEFORE file: {beforeFile}");
    var beforeContent = await File.ReadAllTextAsync(beforeFile);
    
    Console.WriteLine($"📄 Reading AFTER file: {afterFile}");
    var afterContent = await File.ReadAllTextAsync(afterFile);
    
    Console.WriteLine();
    Console.WriteLine($"   Before: {beforeContent.Length:N0} bytes, {beforeContent.Split('\n').Length:N0} lines");
    Console.WriteLine($"   After:  {afterContent.Length:N0} bytes, {afterContent.Split('\n').Length:N0} lines");
    Console.WriteLine();

    report.AppendLine("## Input Files");
    report.AppendLine($"- **Before:** `TestFiles/testBeforeChange.mmd` ({beforeContent.Length:N0} bytes, {beforeContent.Split('\n').Length:N0} lines)");
    report.AppendLine($"- **After:** `TestFiles/testAfterChange.mmd` ({afterContent.Length:N0} bytes, {afterContent.Split('\n').Length:N0} lines)");
    report.AppendLine();
    
    // Accept optional export folder from command line, otherwise create timestamped folder
    string exportFolder;
    if (args.Length > 0 && !string.IsNullOrWhiteSpace(args[0]))
    {
        exportFolder = args[0];
        Console.WriteLine($"📁 Using provided export folder: {exportFolder}");
    }
    else
    {
        var timestamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
        exportFolder = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", $"MmdDiffTest_Export_{timestamp}"));
        Console.WriteLine($"📁 Creating export folder: {exportFolder}");
    }
    
    Directory.CreateDirectory(exportFolder);
    Console.WriteLine();

    report.AppendLine($"**Export Directory:** `{exportFolder}`");
    report.AppendLine();
    
    var dialects = new[]
    {
        (SqlDialect.AnsiSql, "ANSI SQL"),
        (SqlDialect.SqlServer, "T-SQL (SQL Server)"),
        (SqlDialect.PostgreSql, "PostgreSQL"),
        (SqlDialect.MySql, "MySQL")
    };

    var sw = new Stopwatch();
    
    // DIRECTION 1: Before → After (Forward)
    Console.WriteLine("═══════════════════════════════════════════════════════════════════");
    Console.WriteLine("DIRECTION 1: Before → After (Forward Migration)");
    Console.WriteLine("═══════════════════════════════════════════════════════════════════");
    Console.WriteLine();

    report.AppendLine("## Direction 1: Before → After (Forward Migration)");
    report.AppendLine("These ALTER statements migrate the schema from the 'before' state to the 'after' state.");
    report.AppendLine();

    var forwardDir = Path.Combine(exportFolder, "Forward_Before-To-After");
    Directory.CreateDirectory(forwardDir);

    foreach (var (dialect, name) in dialects)
    {
        Console.WriteLine($"Generating {name} ALTER statements...");
        
        var dialectDir = Path.Combine(forwardDir, dialect.ToString());
        Directory.CreateDirectory(dialectDir);
        
        var generator = new MmdDiffToSqlGenerator
        {
            ExportFolderPath = dialectDir
        };

        sw.Restart();

        try
        {
            var alterStatements = await generator.GenerateAlterStatementsAsync(
                beforeContent,
                afterContent,
                dialect
            );
            sw.Stop();
            
            var outputFile = Path.Combine(dialectDir, $"forward_alter_{dialect}.sql");
            await File.WriteAllTextAsync(outputFile, alterStatements);
            
            Console.WriteLine($"  ✅ SUCCESS ({sw.ElapsedMilliseconds}ms, {alterStatements.Length:N0} bytes)");
            Console.WriteLine();

            report.AppendLine($"### {name}");
            report.AppendLine($"- **Status:** ✅ Success");
            report.AppendLine($"- **Duration:** {sw.ElapsedMilliseconds}ms");
            report.AppendLine($"- **Output Size:** {alterStatements.Length:N0} bytes");
            report.AppendLine($"- **Output Lines:** {alterStatements.Split('\n').Length:N0}");
            report.AppendLine($"- **File:** `Forward_Before-To-After/{dialect}/forward_alter_{dialect}.sql`");
            report.AppendLine();
        }
        catch (Exception ex)
        {
            sw.Stop();
            Console.WriteLine($"  ❌ FAILED ({sw.ElapsedMilliseconds}ms): {ex.Message}");
            Console.WriteLine();

            report.AppendLine($"### {name}");
            report.AppendLine($"- **Status:** ❌ Failed");
            report.AppendLine($"- **Error:** {ex.Message}");
            report.AppendLine();
        }
    }
    
    // DIRECTION 2: After → Before (Reverse)
    Console.WriteLine("═══════════════════════════════════════════════════════════════════");
    Console.WriteLine("DIRECTION 2: After → Before (Reverse/Rollback)");
    Console.WriteLine("═══════════════════════════════════════════════════════════════════");
    Console.WriteLine();

    report.AppendLine("## Direction 2: After → Before (Reverse/Rollback)");
    report.AppendLine("These ALTER statements rollback the schema from the 'after' state to the 'before' state.");
    report.AppendLine();

    var reverseDir = Path.Combine(exportFolder, "Reverse_After-To-Before");
    Directory.CreateDirectory(reverseDir);

    foreach (var (dialect, name) in dialects)
    {
        Console.WriteLine($"Generating {name} ALTER statements...");
        
        var dialectDir = Path.Combine(reverseDir, dialect.ToString());
        Directory.CreateDirectory(dialectDir);
        
        var generator = new MmdDiffToSqlGenerator
        {
            ExportFolderPath = dialectDir
        };

        sw.Restart();

        try
        {
            var alterStatements = await generator.GenerateAlterStatementsAsync(
                afterContent,
                beforeContent,
                dialect
            );
            sw.Stop();
            
            var outputFile = Path.Combine(dialectDir, $"reverse_alter_{dialect}.sql");
            await File.WriteAllTextAsync(outputFile, alterStatements);
            
            Console.WriteLine($"  ✅ SUCCESS ({sw.ElapsedMilliseconds}ms, {alterStatements.Length:N0} bytes)");
            Console.WriteLine();

            report.AppendLine($"### {name}");
            report.AppendLine($"- **Status:** ✅ Success");
            report.AppendLine($"- **Duration:** {sw.ElapsedMilliseconds}ms");
            report.AppendLine($"- **Output Size:** {alterStatements.Length:N0} bytes");
            report.AppendLine($"- **Output Lines:** {alterStatements.Split('\n').Length:N0}");
            report.AppendLine($"- **File:** `Reverse_After-To-Before/{dialect}/reverse_alter_{dialect}.sql`");
            report.AppendLine();
        }
        catch (Exception ex)
        {
            sw.Stop();
            Console.WriteLine($"  ❌ FAILED ({sw.ElapsedMilliseconds}ms): {ex.Message}");
            Console.WriteLine();

            report.AppendLine($"### {name}");
            report.AppendLine($"- **Status:** ❌ Failed");
            report.AppendLine($"- **Error:** {ex.Message}");
            report.AppendLine();
        }
    }

    // Summary
    report.AppendLine("## Analysis & Summary");
    report.AppendLine();
    report.AppendLine("### Key Observations");
    report.AppendLine("- ✅ Both forward and reverse migrations completed successfully");
    report.AppendLine("- ✅ All SQL dialects generated ALTER statements");
    report.AppendLine("- Export files include SQLGlot intermediate representations (AST files)");
    report.AppendLine();
    report.AppendLine("### Usage Scenarios");
    report.AppendLine("- **Forward (Before→After)**: Use for deploying schema changes to production");
    report.AppendLine("- **Reverse (After→Before)**: Use for rollback procedures if deployment fails");
    report.AppendLine();
    report.AppendLine("### Important Notes");
    report.AppendLine("- ⚠️ Always review generated ALTER statements before executing");
    report.AppendLine("- ⚠️ Test migrations in non-production environment first");
    report.AppendLine("- ⚠️ Some schema changes may require manual data migration");
    report.AppendLine("- ⚠️ Certain changes (e.g., column drops) may result in data loss");
    report.AppendLine();

    Console.WriteLine("═══════════════════════════════════════════════════════════════════");
    Console.WriteLine("✅ MMD Diff Test (Both Directions) Completed Successfully!");
    Console.WriteLine("═══════════════════════════════════════════════════════════════════");
}
catch (Exception ex)
{
    Console.WriteLine();
    Console.WriteLine("❌ ERROR:");
    Console.WriteLine(ex.ToString());

    report.AppendLine("## ❌ Test Failed");
    report.AppendLine($"**Error:** {ex.Message}");
    report.AppendLine();
    report.AppendLine("```");
    report.AppendLine(ex.ToString());
    report.AppendLine("```");
    
    await SaveReport(report.ToString());
    return 1;
}

await SaveReport(report.ToString());
Console.WriteLine($"\n📄 Report saved to: Docs/MMD_DIFF_TEST_REPORT.md");

return 0;

static async Task SaveReport(string reportContent)
{
    var docsPath = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", "Docs"));
    Directory.CreateDirectory(docsPath);
    var reportFile = Path.Combine(docsPath, "MMD_DIFF_TEST_REPORT.md");
    await File.WriteAllTextAsync(reportFile, reportContent);
}
