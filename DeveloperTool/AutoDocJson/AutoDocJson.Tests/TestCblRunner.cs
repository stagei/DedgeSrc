using System;
using System.IO;
using System.Threading.Tasks;
using AutoDocNew.Core;

namespace AutoDocNew.Tests;

/// <summary>
/// Simple test runner for CBL files - tests one file and reports errors
/// </summary>
public class TestCblRunner
{
    public static async Task<int> RunTestCbl(string[] args)
    {
        try
        {
            string optPath = Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt";
            string testFile = args.Length > 0 ? args[0] : Path.Combine(optPath, "data", "AutoDocJson", "tmp", "DedgeRepository", "Dedge", "cbl", "BSAUTOS.CBL");
            string outputFolder = Path.Combine(optPath, "Webs", "AutoDocJson");
            string tmpRootFolder = Path.Combine(optPath, "data", "AutoDocJson", "tmp");
            string srcRootFolder = Path.Combine(optPath, "data", "AutoDocJson", "tmp", "DedgeRepository");

            Logger.LogMessage($"Testing CBL file: {testFile}", LogLevel.INFO);
            Logger.LogMessage($"Output folder: {outputFolder}", LogLevel.INFO);

            // Ensure output folder exists
            Directory.CreateDirectory(outputFolder);
            Directory.CreateDirectory(Path.Combine(outputFolder, "_templates"));
            Directory.CreateDirectory(Path.Combine(outputFolder, "_css"));
            Directory.CreateDirectory(Path.Combine(outputFolder, "_js"));
            Directory.CreateDirectory(Path.Combine(outputFolder, "_images"));

            var result = await TestSingleCbl.TestCblFile(testFile, outputFolder, tmpRootFolder, srcRootFolder);

            Console.WriteLine($"\n{new string('=', 80)}");
            Console.WriteLine($"Test Result: {result.Status}");
            Console.WriteLine($"Duration: {result.Duration.TotalSeconds:F2}s");
            if (!string.IsNullOrEmpty(result.HtmlPath))
            {
                Console.WriteLine($"HTML Path: {result.HtmlPath}");
            }
            if (!string.IsNullOrEmpty(result.Error))
            {
                Console.WriteLine($"Error: {result.Error}");
            }
            if (!string.IsNullOrEmpty(result.Exception))
            {
                Console.WriteLine($"Exception: {result.Exception}");
            }
            Console.WriteLine($"{new string('=', 80)}\n");

            return result.Status == "Success" ? 0 : 1;
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Fatal error: {ex.Message}", LogLevel.FATAL, ex);
            Console.WriteLine($"Fatal error: {ex.Message}");
            Console.WriteLine(ex.ToString());
            return 1;
        }
    }
}
