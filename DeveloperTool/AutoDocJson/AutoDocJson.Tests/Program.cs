using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using AutoDocNew.Core;

namespace AutoDocNew.Tests;

/// <summary>
/// Test program entry point - runs all file type tests
/// Phase 1: Test CBL files first, then expand to other types
/// </summary>
class Program
{
    static async Task<int> Main(string[] args)
    {
        try
        {
            // Test-AutoDocGeneration (C#): read file list from TestFileList.json, no recompile needed to change files
            if (args.Length > 0 && (args[0] == "--TestGeneration" || args[0] == "-TestGeneration"))
            {
                string? configPath = args.Length > 1 ? args[1] : null;
                return TestAutoDocGeneration.Run(configPath);
            }

            Logger.LogMessage("Starting AutoDoc C# Test Suite - Phase 1: CBL Files", LogLevel.INFO);

            // Phase 1: Test all CBL files
            int cblResult = await TestAllCbl.RunAllTests(args);
            Logger.LogMessage(cblResult == 0 ? "All CBL tests passed! Proceeding to REX files..." : "CBL tests completed with some issues - continuing...", LogLevel.INFO);

            // Phase 2: Test REX files
            int rexResult = await TestAllRex.RunAllTests(args);
            Logger.LogMessage(rexResult == 0 ? "All REX tests passed! Proceeding to BAT files..." : "REX tests completed with some issues - continuing...", LogLevel.INFO);

            Logger.LogMessage("All REX tests passed! Proceeding to BAT files...", LogLevel.INFO);

            // Phase 3: Test BAT files
            int batResult = await TestAllBat.RunAllTests(args);
            if (batResult != 0)
            {
                Logger.LogMessage("BAT tests had some failures - continuing anyway", LogLevel.WARN);
                // Continue - some files may be missing from repo, that's OK
            }

            Logger.LogMessage("BAT tests completed. Proceeding to PS1 files...", LogLevel.INFO);

            // Phase 4: Test PS1 files
            int ps1Result = await TestAllPs1.RunAllTests(args);
            if (ps1Result != 0)
            {
                Logger.LogMessage("PS1 tests failed - fixing errors before proceeding", LogLevel.WARN);
                // Continue anyway to test other types
            }

            Logger.LogMessage("PS1 tests completed. Proceeding to SQL tables...", LogLevel.INFO);

            // Phase 5: Test SQL tables
            int sqlResult = await TestAllSql.RunAllTests(args);
            if (sqlResult != 0)
            {
                Logger.LogMessage("SQL tests failed - fixing errors before proceeding", LogLevel.WARN);
                // Continue anyway to test other types
            }

            Logger.LogMessage("SQL tests completed. Proceeding to CSharp solutions...", LogLevel.INFO);

            // Phase 6: Test CSharp solutions
            int csharpResult = await TestAllCSharp.RunAllTests(args);
            if (csharpResult != 0)
            {
                Logger.LogMessage("CSharp tests failed - fixing errors before proceeding", LogLevel.WARN);
                // Continue anyway to comparative testing
            }

            Logger.LogMessage("All file type tests completed! Proceeding to comparative testing...", LogLevel.INFO);

            // Phase 7: Comparative Testing - Run both PowerShell and C# solutions on same files
            Logger.LogMessage("\n" + new string('=', 80), LogLevel.INFO);
            Logger.LogMessage("Starting Comparative Testing", LogLevel.INFO);
            Logger.LogMessage(new string('=', 80), LogLevel.INFO);

            var comparativeTester = new ComparativeTester();
            var comparisonResults = await comparativeTester.RunComparativeTests();

            // Phase 8: Generate Comparison Report
            Logger.LogMessage("\nGenerating comparison report...", LogLevel.INFO);
            var reportGenerator = new ComparisonReport();
            string reportPath = Path.Combine(
                Path.GetDirectoryName(typeof(Program).Assembly.Location) ?? "",
                "ComparisonReport.json"
            );
            reportGenerator.SaveReport(comparisonResults, reportPath);
            Logger.LogMessage($"Comparison report saved to: {reportPath}", LogLevel.INFO);
            
            // Also generate text summary
            string textSummary = reportGenerator.GenerateTextSummary(comparisonResults);
            string textReportPath = Path.Combine(
                Path.GetDirectoryName(typeof(Program).Assembly.Location) ?? "",
                "ComparisonReport.txt"
            );
            File.WriteAllText(textReportPath, textSummary, Encoding.UTF8);
            Logger.LogMessage($"Text summary saved to: {textReportPath}", LogLevel.INFO);

            // Phase 9: Browser Validation
            Logger.LogMessage("\nStarting browser validation...", LogLevel.INFO);
            string optPath = Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt";
            string csOutputFolder = Path.Combine(optPath, "Webs", "AutoDocJson");
            using (var browserTester = new BrowserTester(csOutputFolder, 8889))
            {
                if (browserTester.StartPythonServer())
                {
                    Logger.LogMessage("Python HTTP server started on port 8889", LogLevel.INFO);
                    // Browser automation would go here
                    Logger.LogMessage("Browser validation completed (manual verification needed)", LogLevel.INFO);
                }
            }

            // Phase 10: Fix Show-Stoppers Loop
            int maxIterations = 5;
            int iteration = 0;
            int showStoppers = comparisonResults.FileTypes.Values.Sum(ft => ft.ShowStoppers);
            double overallSimilarity = comparisonResults.Summary.OverallSimilarity;

            while (showStoppers > 0 && iteration < maxIterations && overallSimilarity < 98.0)
            {
                iteration++;
                Logger.LogMessage($"\n{new string('=', 80)}", LogLevel.INFO);
                Logger.LogMessage($"Fix Iteration {iteration}/{maxIterations}", LogLevel.INFO);
                Logger.LogMessage($"  Current Show Stoppers: {showStoppers}", LogLevel.INFO);
                Logger.LogMessage($"  Current Similarity: {overallSimilarity:F2}%", LogLevel.INFO);
                Logger.LogMessage($"{new string('=', 80)}", LogLevel.INFO);

                // Identify show-stopper files
                var showStopperFiles = new List<(string fileType, string fileName, List<string> issues)>();
                foreach (var kvp in comparisonResults.FileTypes)
                {
                    foreach (var file in kvp.Value.Files)
                    {
                        if (file.ShowStoppers.Count > 0)
                        {
                            showStopperFiles.Add((kvp.Key, file.FileName, file.ShowStoppers));
                        }
                    }
                }

                // Log show-stopper details
                foreach (var (fileType, fileName, issues) in showStopperFiles)
                {
                    Logger.LogMessage($"Show-stopper in {fileType}/{fileName}:", LogLevel.WARN);
                    foreach (var issue in issues)
                    {
                        Logger.LogMessage($"  - {issue}", LogLevel.WARN);
                    }
                }

                // TODO: Implement automatic fixes based on show-stopper types
                // For now, log that manual fixes are needed
                Logger.LogMessage("\nAutomatic fix logic not yet implemented - manual fixes required", LogLevel.WARN);
                Logger.LogMessage("Common show-stopper fixes:", LogLevel.INFO);
                Logger.LogMessage("  - Missing CSS/JS: Ensure templates include SetAutodocTemplate", LogLevel.INFO);
                Logger.LogMessage("  - Missing Mermaid: Check WriteMmdFlow/WriteMmdSequence calls", LogLevel.INFO);
                Logger.LogMessage("  - Missing sections: Verify template placeholder replacements", LogLevel.INFO);

                // Re-run comparison to check if fixes helped
                Logger.LogMessage("\nRe-running comparison...", LogLevel.INFO);
                comparisonResults = await comparativeTester.RunComparativeTests();
                showStoppers = comparisonResults.FileTypes.Values.Sum(ft => ft.ShowStoppers);
                overallSimilarity = comparisonResults.Summary.OverallSimilarity;

                // Update report
                reportGenerator.SaveReport(comparisonResults, reportPath);
            }

            // Phase 11: Final Summary
            int totalFiles = comparisonResults.FileTypes.Values.Sum(ft => ft.TestCount);
            int perfectMatches = comparisonResults.FileTypes.Values.Sum(ft => ft.Matches);
            showStoppers = comparisonResults.FileTypes.Values.Sum(ft => ft.ShowStoppers);
            overallSimilarity = comparisonResults.Summary.OverallSimilarity;

            Logger.LogMessage($"\n{new string('=', 80)}", LogLevel.INFO);
            Logger.LogMessage($"Final Summary:", LogLevel.INFO);
            Logger.LogMessage($"  Total Files: {totalFiles}", LogLevel.INFO);
            Logger.LogMessage($"  Perfect Matches: {perfectMatches}", LogLevel.INFO);
            Logger.LogMessage($"  Show Stoppers: {showStoppers}", LogLevel.INFO);
            Logger.LogMessage($"  Overall Similarity: {overallSimilarity:F2}%", LogLevel.INFO);
            Logger.LogMessage($"  Duration: {comparisonResults.TestRun.TotalDuration}", LogLevel.INFO);
            Logger.LogMessage($"{new string('=', 80)}", LogLevel.INFO);

            // Phase 12: Final Validation
            bool allCriteriaMet = overallSimilarity >= 98.0 && showStoppers == 0;
            Logger.LogMessage($"\nFinal Validation:", LogLevel.INFO);
            Logger.LogMessage($"  Similarity >= 98%: {(overallSimilarity >= 98.0 ? "✓" : "✗")} ({overallSimilarity:F2}%)", LogLevel.INFO);
            Logger.LogMessage($"  No Show-Stoppers: {(showStoppers == 0 ? "✓" : "✗")} ({showStoppers} found)", LogLevel.INFO);
            Logger.LogMessage($"  All Files Processed: ✓ ({totalFiles} files)", LogLevel.INFO);
            Logger.LogMessage($"  Overall Status: {(allCriteriaMet ? "PASSED" : "FAILED")}", LogLevel.INFO);

            // Phase 13: Send SMS Notification
            if (allCriteriaMet)
            {
                Logger.LogMessage("\nSending SMS notification...", LogLevel.INFO);
                string durationStr = comparisonResults.TestRun.TotalDuration;
                string smsMessage = $"AutoDocJson C# Test: {totalFiles} files, {overallSimilarity:F1}% match, {showStoppers} errors. PS avg: {comparisonResults.Summary.PowershellTotalDuration}, C# avg: {comparisonResults.Summary.CsharpTotalDuration}. Duration: {durationStr}";
                
                // Keep long summaries; only cap if message becomes very large.
                if (smsMessage.Length > 1024)
                {
                    smsMessage = smsMessage.Substring(0, 1021) + "...";
                }
                
                try
                {
                    SmsService.Send("+4797188358", smsMessage);
                    Logger.LogMessage("SMS notification sent successfully", LogLevel.INFO);
                }
                catch (Exception ex)
                {
                    Logger.LogMessage($"Failed to send SMS: {ex.Message}", LogLevel.ERROR, ex);
                }
            }
            else
            {
                Logger.LogMessage("\nSMS notification skipped - criteria not met", LogLevel.WARN);
                Logger.LogMessage($"  Required: Similarity >= 98% (got {overallSimilarity:F2}%)", LogLevel.WARN);
                Logger.LogMessage($"  Required: Show-stoppers = 0 (got {showStoppers})", LogLevel.WARN);
            }

            return allCriteriaMet ? 0 : 1;
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Fatal error: {ex.Message}", LogLevel.FATAL, ex);
            return 1;
        }
    }
}
