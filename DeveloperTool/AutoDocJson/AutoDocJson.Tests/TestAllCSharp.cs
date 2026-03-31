using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using AutoDocNew.Core;
using AutoDocNew.Parsers;

namespace AutoDocNew.Tests;

/// <summary>
/// Test all 10 C# solutions from the plan
/// </summary>
public class TestAllCSharp
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

            // Test solutions from plan
            var testSolutions = new List<string>
            {
                Path.Combine(repoBase, "DedgePsh", "GenericLogHandler", "GenericLogHandler.sln"),
                Path.Combine(repoBase, "DedgePsh", "DevTools", "DevTools.sln"),
                Path.Combine(repoBase, "DedgePsh", "D365InvVisService", "D365InvVisService.sln"),
                Path.Combine(repoBase, "DedgePsh", "EntraMenuManager", "EntraMenuManager.sln"),
                Path.Combine(repoBase, "DedgePsh", "ExternalIntegrations", "ExternalIntegrations.sln"),
                Path.Combine(repoBase, "DedgePsh", "FKMAccessAdmin", "FKMAccessAdmin.sln"),
                Path.Combine(repoBase, "DedgePsh", "BRREGRefresh", "BRREGRefresh.sln"),
                Path.Combine(repoBase, "DedgePsh", "DB2ExportCSV", "DB2ExportCSV.sln"),
                Path.Combine(repoBase, "DedgePsh", "GetPeppolDirectory", "GetPeppolDirectory.sln"),
                Path.Combine(repoBase, "DedgePsh", "AgriProd", "AgriProd.sln")
            };

            Logger.LogMessage($"Testing {testSolutions.Count} C# solutions", LogLevel.INFO);

            int successCount = 0;
            int failCount = 0;
            var results = new List<(string solution, bool success, string? error)>();

            foreach (var solutionFile in testSolutions)
            {
                string fileName = Path.GetFileName(solutionFile);
                Logger.LogMessage($"\n{new string('=', 80)}", LogLevel.INFO);
                Logger.LogMessage($"Testing: {fileName}", LogLevel.INFO);
                Logger.LogMessage($"{new string('=', 80)}", LogLevel.INFO);

                try
                {
                    if (!File.Exists(solutionFile))
                    {
                        Logger.LogMessage($"Solution file not found: {solutionFile}", LogLevel.WARN);
                        results.Add((fileName, false, "File not found"));
                        failCount++;
                        continue;
                    }

                    string sourceFolder = Path.GetDirectoryName(solutionFile) ?? "";
                    if (string.IsNullOrEmpty(sourceFolder))
                    {
                        Logger.LogMessage($"Cannot determine source folder for: {solutionFile}", LogLevel.ERROR);
                        results.Add((fileName, false, "Cannot determine source folder"));
                        failCount++;
                        continue;
                    }

                    var startTime = DateTime.Now;
                    string? htmlPath = CSharpParser.StartCSharpParse(
                        sourceFolder,
                        solutionFile: solutionFile,
                        outputFolder: outputFolder,
                        tmpRootFolder: tmpRootFolder,
                        srcRootFolder: srcRootFolder,
                        clientSideRender: true
                    );
                    var duration = DateTime.Now - startTime;

                    if (!string.IsNullOrEmpty(htmlPath) && File.Exists(htmlPath))
                    {
                        Logger.LogMessage($"SUCCESS: {fileName} - Generated in {duration.TotalSeconds:F2}s", LogLevel.INFO);
                        results.Add((fileName, true, null));
                        successCount++;
                    }
                    else
                    {
                        Logger.LogMessage($"FAILED: {fileName} - HTML not generated", LogLevel.ERROR);
                        results.Add((fileName, false, "HTML not generated"));
                        failCount++;
                    }
                }
                catch (Exception ex)
                {
                    Logger.LogMessage($"FAILED: {fileName} - {ex.Message}", LogLevel.ERROR, ex);
                    results.Add((fileName, false, ex.Message));
                    failCount++;
                }
            }

            // Summary
            Console.WriteLine($"\n{new string('=', 80)}");
            Console.WriteLine($"CSharp Test Summary: {successCount} succeeded, {failCount} failed out of {testSolutions.Count}");
            Console.WriteLine($"{new string('=', 80)}");
            
            if (failCount > 0)
            {
                Console.WriteLine("\nFailed solutions:");
                foreach (var (solution, success, error) in results.Where(r => !r.success))
                {
                    Console.WriteLine($"  - {solution}: {error}");
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
