using System;
using System.Linq;
using System.Runtime.Versioning;
using AutoDocNew.Core;
using AutoDocNew.Parsers;

[assembly: SupportedOSPlatform("windows")]

namespace AutoDocNew;

/// <summary>
/// Main program entry point - converted from AutoDocBatchRunner.ps1 param() block (lines 12-65)
/// Author: Geir Helge Starholm, Dedge AS
/// </summary>
class Program
{
    static int Main(string[] args)
    {
        try
        {
            // Parse command-line arguments (equivalent to PowerShell param() block)
            var options = CommandLineParser.Parse(args);

            if (options.ShowHelp)
            {
                CommandLineParser.PrintHelp();
                return 0;
            }

            // Initialize logger
            Logger.ResetLogLevel();

            // Search mode: run search and exit without starting batch runner
            if (options.SearchFilters.Count > 0)
                return RunSearch(options);

            // Distributed worker mode: watch server worklist and process files locally
            if (options.WorkerMode)
                return RunWorker(options);

            // Kill other AutoDoc processes (lines 73-130)
            KillProcessHandler.KillOtherAutoDocProcesses();

            // Build global PSM1 module index for cross-linking (PS1 -> PSM1 function links)
            Ps1Parser.GlobalModuleIndex = Ps1Parser.BuildModuleIndex();

            // Run batch runner with all parser implementations wired up
            var singleFileParser = new SingleFileParserImpl();
            var csharpRunner = new CSharpProjectRunnerImpl();
            var gsRunner = new GsFileRunnerImpl();
            BatchRunner runner = new BatchRunner(options, singleFileParser, csharpRunner, gsRunner);
            return runner.Run();
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Fatal error: {ex.Message}", LogLevel.FATAL, ex);
            return 1;
        }
    }

    static int RunWorker(CommandLineOptions options)
    {
        string? serverName = DistributedWorker.ReadServerName();
        if (string.IsNullOrWhiteSpace(serverName))
        {
            Logger.LogMessage("AutoDocJson:ServerName not configured in appsettings.json. Cannot start worker.", LogLevel.ERROR);
            return 1;
        }

        Logger.LogMessage($"Starting distributed worker (server: {serverName})...", LogLevel.INFO);

        Ps1Parser.GlobalModuleIndex = Ps1Parser.BuildModuleIndex();
        var parser = new SingleFileParserImpl();
        var worker = new DistributedWorker(options, parser, serverName);
        return worker.Run();
    }

    static int RunSearch(CommandLineOptions options)
    {
        var engine = new SearchEngine(options.OutputFolder);
        var request = new SearchRequest();

        if (options.SearchFilters.Count == 1 && string.IsNullOrEmpty(options.SearchFilters[0].field))
        {
            request.Query = options.SearchFilters[0].terms;
        }
        else
        {
            request.Elements = options.SearchFilters.Select(f => new ElementFilter
            {
                Field = string.IsNullOrEmpty(f.field) ? "" : f.field,
                Terms = f.terms.Split(',', StringSplitOptions.RemoveEmptyEntries)
                    .Select(t => t.Trim()).ToArray()
            }).ToList();
        }

        request.Types = options.SearchTypes;
        request.Logic = options.SearchLogic;

        var results = engine.Search(request);

        // Header
        string logicSep = options.SearchLogic == "OR" ? " | " : " + ";
        string searchDesc = string.Join(logicSep,
            options.SearchFilters.Select(f =>
                string.IsNullOrEmpty(f.field)
                    ? $"\"{f.terms}\""
                    : $"\"{f.terms}\" in {f.field}"));
        string typeFilter = options.SearchTypes != null
            ? $" ({string.Join(", ", options.SearchTypes)} only)"
            : "";
        if (options.SearchLogic == "OR")
            typeFilter += " [OR logic]";
        Console.WriteLine($"\nSearch: {searchDesc}{typeFilter}");
        Console.WriteLine($"Found {results.Count} results:\n");

        if (results.Count == 0) return 0;

        // Calculate column widths
        int typeWidth = Math.Max(4, results.Max(r => r.Type.Length));
        int nameWidth = Math.Max(4, Math.Min(40, results.Max(r => r.FileName.Length)));
        int descWidth = Math.Max(11, Math.Min(35, results.Max(r => r.Description.Length)));

        string fmt = $"  {{0,-{typeWidth}}}  {{1,-{nameWidth}}}  {{2,-{descWidth}}}  {{3}}";
        Console.WriteLine(string.Format(fmt, "Type", "File", "Description", "Matched In"));
        Console.WriteLine(string.Format(fmt,
            new string('-', typeWidth), new string('-', nameWidth),
            new string('-', descWidth), "----------"));

        foreach (var r in results)
        {
            string desc = r.Description.Length > descWidth
                ? r.Description.Substring(0, descWidth - 3) + "..."
                : r.Description;
            if (string.IsNullOrWhiteSpace(desc)) desc = "(no description)";
            string matchedIn = string.Join(", ", r.Matches.Select(m => m.Field).Distinct());
            Console.WriteLine(string.Format(fmt, r.Type, r.FileName, desc, matchedIn));
        }

        Console.WriteLine();
        return 0;
    }
}
