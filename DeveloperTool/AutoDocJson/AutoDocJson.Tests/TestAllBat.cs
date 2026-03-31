using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using AutoDocNew.Core;
using AutoDocNew.Parsers;

namespace AutoDocNew.Tests;

/// <summary>
/// Test all 10 BAT files from the plan
/// </summary>
public class TestAllBat
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

            // Test files from plan
            var testFiles = new List<string>
            {
                Path.Combine(repoBase, "DB2Scripts", "db2_forsprang_restore", "RESTDB_MIG_B.BAT"),
                Path.Combine(repoBase, "DedgePsh", "GHS_TEMP.PS2 copy 2.bat"),
                Path.Combine(repoBase, "DedgePsh", "DevTools", "DatabaseTools", "Db2-GeneratedGrants_srv_datavarehus_fkmprd_kerberos.bat"),
                Path.Combine(repoBase, "DedgePsh", "DevTools", "DatabaseTools", "Db2-GeneratedGrants_srv_datavarehus_fkmprd_ntlm.bat"),
                Path.Combine(repoBase, "DedgePsh", "GHS_TEMP.PS2.bat"),
                Path.Combine(repoBase, "Dedge", "bat_prod", "FKATAB_BASISPRO.BAT"),
                Path.Combine(repoBase, "Dedge", "bat_prod", "FKATAB.BAT"),
                Path.Combine(repoBase, "DedgePsh", "DevTools", "DatabaseTools", "919_generated_db2_drop_existing_nicknames.bat"),
                Path.Combine(repoBase, "DB2Scripts", "db2_restore", "restdb_vft_til_db2dev.bat"),
                Path.Combine(repoBase, "Dedge", "bat", "RESTDB_VFT_TIL_DB2DEV.BAT")
            };

            Logger.LogMessage($"Testing {testFiles.Count} BAT files", LogLevel.INFO);

            int successCount = 0;
            int failCount = 0;
            var results = new List<(string file, bool success, string? error)>();

            foreach (var testFile in testFiles)
            {
                string fileName = Path.GetFileName(testFile);
                Logger.LogMessage($"\n{new string('=', 80)}", LogLevel.INFO);
                Logger.LogMessage($"Testing: {fileName}", LogLevel.INFO);
                Logger.LogMessage($"{new string('=', 80)}", LogLevel.INFO);

                try
                {
                    if (!File.Exists(testFile))
                    {
                        Logger.LogMessage($"File not found: {testFile}", LogLevel.WARN);
                        results.Add((fileName, false, "File not found"));
                        failCount++;
                        continue;
                    }

                    var startTime = DateTime.Now;
                    string? htmlPath = BatParser.StartBatParse(
                        testFile,
                        show: false,
                        outputFolder: outputFolder,
                        tmpRootFolder: tmpRootFolder,
                        srcRootFolder: srcRootFolder,
                        clientSideRender: true,
                        saveMmdFiles: true
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
            Console.WriteLine($"BAT Test Summary: {successCount} succeeded, {failCount} failed out of {testFiles.Count}");
            Console.WriteLine($"{new string('=', 80)}");
            
            if (failCount > 0)
            {
                Console.WriteLine("\nFailed files:");
                foreach (var (file, success, error) in results.Where(r => !r.success))
                {
                    Console.WriteLine($"  - {file}: {error}");
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
