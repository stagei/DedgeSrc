using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using AutoDocNew.Core;
using AutoDocNew.Parsers;

namespace AutoDocNew.Tests;

/// <summary>
/// C# implementation of Test-AutoDocGeneration.ps1.
/// Reads test file list from TestFileList.json (no recompile needed to change files).
/// Generates docs, validates HTML, writes Test-AutoDocGeneration.results.json and log.
/// </summary>
public static class TestAutoDocGeneration
{
    public const string DefaultConfigFileName = "TestFileList.json";
    public const string ResultsFileName = "Test-AutoDocGeneration.results.json";
    public const string LogFileName = "Test-AutoDocGeneration.log";

    /// <summary>
    /// Resolve config file path: same directory as assembly, then current directory.
    /// </summary>
    public static string FindConfigPath(string? configFileName = null)
    {
        configFileName ??= DefaultConfigFileName;
        string? assemblyDir = Path.GetDirectoryName(typeof(TestAutoDocGeneration).Assembly.Location);
        if (!string.IsNullOrEmpty(assemblyDir))
        {
            string path = Path.Combine(assemblyDir, configFileName);
            if (File.Exists(path))
                return path;
        }
        if (File.Exists(configFileName))
            return Path.GetFullPath(configFileName);
        return Path.Combine(assemblyDir ?? ".", configFileName);
    }

    /// <summary>
    /// Load config from JSON. Uses OptPath defaults for empty repoRoot/outputFolder/tmpRootFolder.
    /// </summary>
    public static TestGenerationConfig LoadConfig(string configPath)
    {
        string json = File.ReadAllText(configPath, Encoding.UTF8);
        var config = JsonSerializer.Deserialize<TestGenerationConfig>(json)
            ?? new TestGenerationConfig();

        string optPath = Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt";
        if (string.IsNullOrWhiteSpace(config.RepoRoot))
            config.RepoRoot = Path.Combine(optPath, "data", "AutoDocJson", "tmp", "DedgeRepository");
        if (string.IsNullOrWhiteSpace(config.OutputFolder))
            config.OutputFolder = Path.Combine(optPath, "Webs", "AutoDocJson");
        if (string.IsNullOrWhiteSpace(config.TmpRootFolder))
            config.TmpRootFolder = Path.Combine(optPath, "data", "AutoDocJson", "tmp");

        return config;
    }

    /// <summary>
    /// Run test generation: load config, process each file, validate HTML, write results.
    /// Returns 0 on full success, 1 if any file failed.
    /// </summary>
    public static int Run(string? configPath = null)
    {
        configPath ??= FindConfigPath();
        if (!File.Exists(configPath))
        {
            Logger.LogMessage($"Config not found: {configPath}. Create TestFileList.json or pass a path.", LogLevel.ERROR);
            return 1;
        }

        TestGenerationConfig config = LoadConfig(configPath);
        string logPath = Path.Combine(Path.GetDirectoryName(configPath) ?? ".", LogFileName);
        string resultsPath = Path.Combine(Path.GetDirectoryName(configPath) ?? ".", ResultsFileName);

        var results = new TestGenerationResults
        {
            StartTime = DateTime.Now,
            TotalFiles = config.Files.Count,
            FileResults = new List<TestGenerationFileResult>()
        };

        void WriteLog(string message, string level = "INFO")
        {
            string line = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] [{level}] {message}";
            try { File.AppendAllText(logPath, line + Environment.NewLine, Encoding.UTF8); } catch { }
            Logger.LogMessage(message, level == "ERROR" || level == "FAIL" ? LogLevel.ERROR : LogLevel.INFO);
        }

        WriteLog("========================================");
        WriteLog("Test-AutoDocGeneration (C#)");
        WriteLog($"Config: {configPath}");
        WriteLog($"Output: {config.OutputFolder}");
        WriteLog($"Files: {config.Files.Count}");
        WriteLog("========================================");

        Directory.CreateDirectory(config.OutputFolder);
        Directory.CreateDirectory(config.TmpRootFolder);
        Directory.CreateDirectory(Path.GetDirectoryName(config.RepoRoot) ?? config.TmpRootFolder);

        int successCount = 0;
        int failedCount = 0;

        for (int i = 0; i < config.Files.Count; i++)
        {
            var entry = config.Files[i];
            var fileResult = new TestGenerationFileResult
            {
                Index = i,
                Type = entry.Type,
                FileName = entry.FileName,
                Status = "Running",
                HtmlPath = null,
                MmdCount = 0,
                SvgCount = 0,
                Error = null
            };

            WriteLog($"[{i + 1}/{config.Files.Count}] {entry.Type} - {entry.FileName}");

            try
            {
                string? fullPath = null;
                if (!entry.IsTable)
                {
                    fullPath = string.IsNullOrWhiteSpace(entry.Path)
                        ? Path.Combine(config.RepoRoot, entry.FileName)
                        : Path.Combine(config.RepoRoot, entry.Path.Replace('/', Path.DirectorySeparatorChar));
                    if (!File.Exists(fullPath))
                    {
                        fileResult.Status = "Failed";
                        fileResult.Error = "File not found: " + fullPath;
                        results.FileResults.Add(fileResult);
                        failedCount++;
                        WriteLog($"  File not found: {fullPath}", "FAIL");
                        continue;
                    }
                }

                string? htmlPath = null;
                var sw = Stopwatch.StartNew();

                if (entry.IsTable)
                {
                    htmlPath = SqlParser.StartSqlParse(
                        entry.FileName,
                        show: false,
                        outputFolder: config.OutputFolder,
                        tmpRootFolder: config.TmpRootFolder,
                        srcRootFolder: config.RepoRoot
                    );
                }
                else
                {
                    switch (entry.Type.ToUpperInvariant())
                    {
                        case "CBL":
                            htmlPath = CblParser.StartCblParse(fullPath!, show: false, outputFolder: config.OutputFolder, tmpRootFolder: config.TmpRootFolder, srcRootFolder: config.RepoRoot, clientSideRender: true, saveMmdFiles: true);
                            break;
                        case "REX":
                            htmlPath = RexParser.StartRexParse(fullPath!, show: false, outputFolder: config.OutputFolder, tmpRootFolder: config.TmpRootFolder, srcRootFolder: config.RepoRoot, clientSideRender: true, saveMmdFiles: true);
                            break;
                        case "BAT":
                            htmlPath = BatParser.StartBatParse(fullPath!, show: false, outputFolder: config.OutputFolder, tmpRootFolder: config.TmpRootFolder, srcRootFolder: config.RepoRoot, clientSideRender: true, saveMmdFiles: true);
                            break;
                        case "PS1":
                            htmlPath = Ps1Parser.StartPs1Parse(fullPath!, show: false, outputFolder: config.OutputFolder, tmpRootFolder: config.TmpRootFolder, srcRootFolder: config.RepoRoot, clientSideRender: true, saveMmdFiles: true);
                            break;
                        case "CSHARP":
                            htmlPath = CSharpParser.StartCSharpParse(Path.GetDirectoryName(fullPath!) ?? "", solutionFile: fullPath!, outputFolder: config.OutputFolder, tmpRootFolder: config.TmpRootFolder, srcRootFolder: config.RepoRoot, clientSideRender: true);
                            break;
                        default:
                            fileResult.Status = "Failed";
                            fileResult.Error = "Unknown type: " + entry.Type;
                            results.FileResults.Add(fileResult);
                            failedCount++;
                            WriteLog($"  Unknown type: {entry.Type}", "FAIL");
                            continue;
                    }
                }

                sw.Stop();

                if (string.IsNullOrEmpty(htmlPath) || !File.Exists(htmlPath))
                {
                    fileResult.Status = "Failed";
                    fileResult.Error = "HTML not generated";
                    results.FileResults.Add(fileResult);
                    failedCount++;
                    WriteLog("  HTML not generated", "FAIL");
                    continue;
                }

                fileResult.HtmlPath = htmlPath;

                // Validate HTML (mirror PS1: CSS, icon, image, Mermaid)
                var validation = ValidateHtml(htmlPath);
                if (!validation.CssIncluded)
                {
                    fileResult.Status = "Failed";
                    fileResult.Error = "CSS validation failed";
                    results.FileResults.Add(fileResult);
                    failedCount++;
                    WriteLog("  CSS validation failed", "FAIL");
                    continue;
                }

                fileResult.Status = "Success";
                fileResult.MmdCount = validation.MermaidFound ? 1 : 0;
                successCount++;
                results.FileResults.Add(fileResult);
                WriteLog($"  OK ({sw.Elapsed.TotalSeconds:F1}s) {htmlPath}", "OK");
            }
            catch (Exception ex)
            {
                fileResult.Status = "Failed";
                fileResult.Error = ex.Message;
                results.FileResults.Add(fileResult);
                failedCount++;
                WriteLog($"  Error: {ex.Message}", "ERROR");
            }
        }

        results.EndTime = DateTime.Now;
        results.SuccessCount = successCount;
        results.FailedCount = failedCount;
        results.Status = failedCount == 0 ? "Success" : "Failed";
        results.LastIndex = config.Files.Count - 1;

        var options = new JsonSerializerOptions { WriteIndented = true, PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
        File.WriteAllText(resultsPath, JsonSerializer.Serialize(results, options), Encoding.UTF8);

        WriteLog("========================================");
        WriteLog($"Status: {results.Status}");
        WriteLog($"Success: {successCount}  Failed: {failedCount}");
        WriteLog($"Results: {resultsPath}");
        WriteLog("========================================");

        return failedCount == 0 ? 0 : 1;
    }

    /// <summary>
    /// Validate generated HTML: CSS, icon, image, Mermaid (mirror Test-AutoDocGeneration.ps1 Test-HtmlValidation).
    /// </summary>
    internal static (bool CssIncluded, bool IconIncluded, bool ImageIncluded, bool MermaidFound) ValidateHtml(string htmlPath)
    {
        string content = File.ReadAllText(htmlPath, Encoding.UTF8);
        bool css = content.Contains("autodoc-shared.css", StringComparison.OrdinalIgnoreCase) || content.Contains(":root") && content.Contains("--bg-primary");
        bool icon = content.Contains("rel=\"icon\"", StringComparison.OrdinalIgnoreCase) || content.Contains("dedge.ico", StringComparison.OrdinalIgnoreCase);
        bool image = content.Contains("dedge.svg", StringComparison.OrdinalIgnoreCase) || Regex.IsMatch(content, @"<img[^>]+src=", RegexOptions.IgnoreCase);
        bool mermaid = content.Contains("class=\"mermaid\"", StringComparison.OrdinalIgnoreCase) || content.Contains("<div class=\"mermaid\">", StringComparison.OrdinalIgnoreCase);
        return (css, icon, image, mermaid);
    }
}

public class TestGenerationResults
{
    public int SuccessCount { get; set; }
    public DateTime? EndTime { get; set; }
    public string? Error { get; set; }
    public DateTime StartTime { get; set; }
    public int LastIndex { get; set; }
    public int TotalFiles { get; set; }
    public int FailedCount { get; set; }
    public int StartFromIndex { get; set; }
    public string Status { get; set; } = "Running";
    public List<TestGenerationFileResult> FileResults { get; set; } = new List<TestGenerationFileResult>();
}

public class TestGenerationFileResult
{
    public string Type { get; set; } = "";
    public string FileName { get; set; } = "";
    public string? Error { get; set; }
    public int Index { get; set; }
    public int MmdCount { get; set; }
    public int SvgCount { get; set; }
    public string Status { get; set; } = "";
    public string? HtmlPath { get; set; }
}
