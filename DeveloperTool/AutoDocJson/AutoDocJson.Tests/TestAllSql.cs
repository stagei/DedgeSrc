using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using AutoDocNew.Core;
using AutoDocNew.Parsers;

namespace AutoDocNew.Tests;

/// <summary>
/// Test all 10 SQL tables from the plan
/// </summary>
public class TestAllSql
{
    public static async Task<int> RunAllTests(string[] args)
    {
        try
        {
            string optPath = Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt";
            string repoBase = Path.Combine(optPath, "data", "AutoDocJson", "tmp", "DedgeRepository");
            string outputFolder = Path.Combine(optPath, "Webs", "AutoDocJson");
            string tmpRootFolder = Path.Combine(optPath, "data", "AutoDocJson", "tmp");
            string srcRootFolder = Path.Combine(optPath, "data", "AutoDocJson", "tmp", "DedgeRepository");

            // Ensure folders exist
            Directory.CreateDirectory(outputFolder);
            Directory.CreateDirectory(Path.Combine(outputFolder, "_templates"));
            Directory.CreateDirectory(Path.Combine(outputFolder, "_css"));
            Directory.CreateDirectory(Path.Combine(outputFolder, "_js"));
            Directory.CreateDirectory(Path.Combine(outputFolder, "_images"));

            // Copy template and CSS if needed
            string templatePath = Path.Combine(outputFolder, "_templates", "cblmmdtemplate.html");
            if (!File.Exists(templatePath))
            {
                string sharedTemplate = Path.Combine(optPath, "src", "DedgePsh", "DevTools", "LegacyCodeTools", "AutoDoc", "_templates", "cblmmdtemplate.html");
                if (File.Exists(sharedTemplate))
                {
                    File.Copy(sharedTemplate, templatePath, true);
                }
            }

            string cssPath = Path.Combine(outputFolder, "_css", "autodoc-shared.css");
            if (!File.Exists(cssPath))
            {
                string sharedCss = Path.Combine(optPath, "src", "DedgePsh", "DevTools", "LegacyCodeTools", "AutoDoc", "_css", "autodoc-shared.css");
                if (File.Exists(sharedCss))
                {
                    File.Copy(sharedCss, cssPath, true);
                }
            }

            // Test tables from plan (table names, not file paths)
            var testTables = new List<string>
            {
                "DBM.AH_ORDREHODE",
                "DBM.AH_ORDRELINJER",
                "CRM.A_ORDREHODE_MASKIN",
                "CRM.A_ORDREHODE_NY",
                "CRM.A_ORDRELINJER",
                "CRM.A_ORDREHODE",
                "CRM.A_ORDREHODE_U",
                "TV.V_DBQA_VIEWS_NOT_ACCESSED_INTERNALLY",
                "TV.V_DBQA_MIGRATION_TABLES_DB2_115",
                "DBM.DRBIDRSALG99K_SUMF"
            };

            Logger.LogMessage($"Testing {testTables.Count} SQL tables", LogLevel.INFO);

            int successCount = 0;
            int failCount = 0;
            var results = new List<(string table, bool success, string? error)>();

            foreach (var tableName in testTables)
            {
                Logger.LogMessage($"\n{new string('=', 80)}", LogLevel.INFO);
                Logger.LogMessage($"Testing: {tableName}", LogLevel.INFO);
                Logger.LogMessage($"{new string('=', 80)}", LogLevel.INFO);

                try
                {
                    var startTime = DateTime.Now;
                    string? htmlPath = SqlParser.StartSqlParse(
                        tableName,
                        show: false,
                        outputFolder: outputFolder,
                        tmpRootFolder: tmpRootFolder,
                        srcRootFolder: srcRootFolder
                    );
                    var duration = DateTime.Now - startTime;

                    if (!string.IsNullOrEmpty(htmlPath) && File.Exists(htmlPath))
                    {
                        Logger.LogMessage($"SUCCESS: {tableName} - Generated in {duration.TotalSeconds:F2}s", LogLevel.INFO);
                        results.Add((tableName, true, null));
                        successCount++;
                    }
                    else
                    {
                        Logger.LogMessage($"FAILED: {tableName} - HTML not generated", LogLevel.ERROR);
                        results.Add((tableName, false, "HTML not generated"));
                        failCount++;
                    }
                }
                catch (Exception ex)
                {
                    Logger.LogMessage($"FAILED: {tableName} - {ex.Message}", LogLevel.ERROR, ex);
                    results.Add((tableName, false, ex.Message));
                    failCount++;
                }
            }

            // Summary
            Console.WriteLine($"\n{new string('=', 80)}");
            Console.WriteLine($"SQL Test Summary: {successCount} succeeded, {failCount} failed out of {testTables.Count}");
            Console.WriteLine($"{new string('=', 80)}");
            
            if (failCount > 0)
            {
                Console.WriteLine("\nFailed tables:");
                foreach (var (table, success, error) in results.Where(r => !r.success))
                {
                    Console.WriteLine($"  - {table}: {error}");
                }
            }

            return failCount > 0 ? 1 : 0;
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Fatal error: {ex.Message}", LogLevel.FATAL, ex);
            Console.WriteLine($"Fatal error: {ex.Message}");
            return 1;
        }
    }
}
