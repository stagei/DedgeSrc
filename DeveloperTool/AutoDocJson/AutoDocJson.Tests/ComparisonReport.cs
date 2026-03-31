using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using AutoDocNew.Core;

namespace AutoDocNew.Tests;

/// <summary>
/// Comparison Report Generator - generates detailed comparison reports
/// </summary>
public class ComparisonReport
{
    public ComparisonReportData GenerateReport(
        Dictionary<string, List<FileComparisonResult>> fileTypeResults,
        TimeSpan totalDuration)
    {
        var report = new ComparisonReportData
        {
            TestRun = new TestRunInfo
            {
                StartTime = DateTime.Now.Add(-totalDuration),
                EndTime = DateTime.Now,
                TotalDuration = totalDuration.ToString(@"hh\:mm\:ss")
            },
            FileTypes = new Dictionary<string, FileTypeStats>(),
            Summary = new SummaryStats()
        };

        int totalFiles = 0;
        int perfectMatches = 0;
        int acceptableDifferences = 0;
        int showStoppers = 0;
        double totalSimilarity = 0.0;
        TimeSpan totalPsDuration = TimeSpan.Zero;
        TimeSpan totalCsDuration = TimeSpan.Zero;

        foreach (var kvp in fileTypeResults)
        {
            string fileType = kvp.Key;
            var results = kvp.Value;

            var stats = new FileTypeStats
            {
                TestCount = results.Count,
                Files = results
            };

            // Calculate averages
            if (results.Count > 0)
            {
                var psDurations = results.Where(r => r.PowershellDuration.HasValue).Select(r => r.PowershellDuration!.Value);
                var csDurations = results.Where(r => r.CsharpDuration.HasValue).Select(r => r.CsharpDuration!.Value);

                if (psDurations.Any())
                {
                    stats.PowershellAvgDuration = TimeSpan.FromMilliseconds(psDurations.Average(d => d.TotalMilliseconds)).ToString(@"hh\:mm\:ss");
                    totalPsDuration = totalPsDuration.Add(psDurations.Aggregate(TimeSpan.Zero, (sum, d) => sum.Add(d)));
                }

                if (csDurations.Any())
                {
                    stats.CsharpAvgDuration = TimeSpan.FromMilliseconds(csDurations.Average(d => d.TotalMilliseconds)).ToString(@"hh\:mm\:ss");
                    totalCsDuration = totalCsDuration.Add(csDurations.Aggregate(TimeSpan.Zero, (sum, d) => sum.Add(d)));
                }

                stats.Matches = results.Count(r => r.Status == "Match");
                stats.AcceptableDifferences = results.Count(r => r.Status == "Acceptable");
                stats.ShowStoppers = results.Count(r => r.Status == "ShowStopper" || r.Status == "Error");

                totalFiles += results.Count;
                perfectMatches += stats.Matches;
                acceptableDifferences += stats.AcceptableDifferences;
                showStoppers += stats.ShowStoppers;

                var similarities = results.Where(r => r.Similarity.HasValue).Select(r => r.Similarity!.Value);
                if (similarities.Any())
                {
                    stats.AvgSimilarity = similarities.Average();
                    totalSimilarity += stats.AvgSimilarity * results.Count;
                }
            }

            report.FileTypes[fileType] = stats;
        }

        // Calculate summary
        report.Summary.TotalFiles = totalFiles;
        report.Summary.PerfectMatches = perfectMatches;
        report.Summary.AcceptableDifferences = acceptableDifferences;
        report.Summary.ShowStoppers = showStoppers;
        report.Summary.OverallSimilarity = totalFiles > 0 ? totalSimilarity / totalFiles : 0.0;
        report.Summary.PowershellTotalDuration = totalPsDuration.ToString(@"hh\:mm\:ss");
        report.Summary.CsharpTotalDuration = totalCsDuration.ToString(@"hh\:mm\:ss");

        return report;
    }

    /// <summary>
    /// Save report to JSON file
    /// </summary>
    public void SaveReport(ComparisonReportData report, string outputPath)
    {
        var options = new JsonSerializerOptions
        {
            WriteIndented = true,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        };

        string json = JsonSerializer.Serialize(report, options);
        File.WriteAllText(outputPath, json, Encoding.UTF8);
        Logger.LogMessage($"Comparison report saved to: {outputPath}", LogLevel.INFO);
    }

    /// <summary>
    /// Generate text summary report
    /// </summary>
    public string GenerateTextSummary(ComparisonReportData report)
    {
        var sb = new StringBuilder();
        sb.AppendLine("=".PadRight(80, '='));
        sb.AppendLine("AutoDoc C# vs PowerShell Comparison Report");
        sb.AppendLine("=".PadRight(80, '='));
        sb.AppendLine($"Duration: {report.TestRun.TotalDuration}");
        sb.AppendLine($"Total Files: {report.Summary.TotalFiles}");
        sb.AppendLine($"Perfect Matches: {report.Summary.PerfectMatches}");
        sb.AppendLine($"Acceptable Differences: {report.Summary.AcceptableDifferences}");
        sb.AppendLine($"Show Stoppers: {report.Summary.ShowStoppers}");
        sb.AppendLine($"Overall Similarity: {report.Summary.OverallSimilarity:P2}");
        sb.AppendLine($"PowerShell Total Duration: {report.Summary.PowershellTotalDuration}");
        sb.AppendLine($"C# Total Duration: {report.Summary.CsharpTotalDuration}");
        sb.AppendLine();

        foreach (var kvp in report.FileTypes)
        {
            string fileType = kvp.Key;
            var stats = kvp.Value;
            sb.AppendLine($"{fileType}:");
            sb.AppendLine($"  Test Count: {stats.TestCount}");
            sb.AppendLine($"  PowerShell Avg: {stats.PowershellAvgDuration}");
            sb.AppendLine($"  C# Avg: {stats.CsharpAvgDuration}");
            sb.AppendLine($"  Matches: {stats.Matches}, Acceptable: {stats.AcceptableDifferences}, Show Stoppers: {stats.ShowStoppers}");
            sb.AppendLine($"  Avg Similarity: {stats.AvgSimilarity:P2}");
            sb.AppendLine();
        }

        return sb.ToString();
    }
}

public class ComparisonReportData
{
    public TestRunInfo TestRun { get; set; } = new TestRunInfo();
    public Dictionary<string, FileTypeStats> FileTypes { get; set; } = new Dictionary<string, FileTypeStats>();
    public SummaryStats Summary { get; set; } = new SummaryStats();
}

public class TestRunInfo
{
    public DateTime StartTime { get; set; }
    public DateTime EndTime { get; set; }
    public string TotalDuration { get; set; } = "";
}

public class FileTypeStats
{
    public int TestCount { get; set; }
    public string PowershellAvgDuration { get; set; } = "";
    public string CsharpAvgDuration { get; set; } = "";
    public int Matches { get; set; }
    public int AcceptableDifferences { get; set; }
    public int ShowStoppers { get; set; }
    public double AvgSimilarity { get; set; }
    public List<FileComparisonResult> Files { get; set; } = new List<FileComparisonResult>();
}

public class SummaryStats
{
    public int TotalFiles { get; set; }
    public int PerfectMatches { get; set; }
    public int AcceptableDifferences { get; set; }
    public int ShowStoppers { get; set; }
    public double OverallSimilarity { get; set; }
    public string PowershellTotalDuration { get; set; } = "";
    public string CsharpTotalDuration { get; set; } = "";
}

public class FileComparisonResult
{
    public string FileName { get; set; } = "";
    public string Type { get; set; } = "";
    public TimeSpan? PowershellDuration { get; set; }
    public TimeSpan? CsharpDuration { get; set; }
    public double? Similarity { get; set; }
    public string Status { get; set; } = "";
    public List<string> Differences { get; set; } = new List<string>();
    public List<string> ShowStoppers { get; set; } = new List<string>();
}
