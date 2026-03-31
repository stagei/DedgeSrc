using System;
using System.IO;
using System.Linq;

namespace AutoDocNew.Core;

/// <summary>
/// Command line options - converted from param() block (lines 12-65)
/// </summary>
public class CommandLineOptions
{
    public RegenerateMode Regenerate { get; set; } = RegenerateMode.Incremental;
    public string SingleFile { get; set; } = "";
    public string[] FileTypes { get; set; } = new[] { "All" };
    public int MaxFilesPerType { get; set; } = 0;
    public bool ClientSideRender { get; set; } = true;
    public bool SaveMmdFiles { get; set; } = false;
    public bool Parallel { get; set; } = true;
    public int ThreadPercentage { get; set; } = 75;
    public int ThreadCountMax { get; set; } = 2;
    public string OutputFolder { get; set; } = "";
    public bool SkipExisting { get; set; } = false;
    public bool GenerateHtml { get; set; } = false;
    public bool UseRamDisk { get; set; } = false;
    public int RamDiskSizeGB { get; set; } = 2;
    public bool ShowHelp { get; set; } = false;

    /// <summary>Distributed worker mode: watch server worklist and process files locally.</summary>
    public bool WorkerMode { get; set; } = false;

    /// <summary>Search mode: list of (terms, field) pairs. If non-empty, run search and exit.</summary>
    public List<(string terms, string field)> SearchFilters { get; set; } = new();
    public string[]? SearchTypes { get; set; }
    public string SearchLogic { get; set; } = "AND";
}

/// <summary>
/// Regenerate mode enumeration - converted from ValidateSet (line 22-23)
/// </summary>
public enum RegenerateMode
{
    Incremental,
    All,
    Errors,
    JsonOnly,
    Single,
    Clean
}

/// <summary>
/// Simple command-line parser
/// </summary>
public static class CommandLineParser
{
    public static CommandLineOptions Parse(string[] args)
    {
        var options = new CommandLineOptions();

        // Default output folder (line 54)
        string optPath = Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt";
        options.OutputFolder = Path.Combine(optPath, "Webs", "AutoDocJson");

        // Parse arguments
        for (int i = 0; i < args.Length; i++)
        {
            string arg = args[i].ToLower();
            switch (arg)
            {
                case "-h":
                case "--h":
                case "-help":
                case "--help":
                case "/?":
                case "/h":
                case "/help":
                    options.ShowHelp = true;
                    return options;
                case "-regenerate":
                case "--regenerate":
                    if (i + 1 < args.Length)
                    {
                        string mode = args[++i];
                        options.Regenerate = Enum.Parse<RegenerateMode>(mode, true);
                    }
                    break;
                case "-singlefile":
                case "--singlefile":
                    if (i + 1 < args.Length)
                    {
                        options.SingleFile = args[++i];
                    }
                    break;
                case "-filetypes":
                case "--filetypes":
                    if (i + 1 < args.Length)
                    {
                        options.FileTypes = args[++i].Split(',');
                    }
                    break;
                case "-outputfolder":
                case "--outputfolder":
                    if (i + 1 < args.Length)
                    {
                        options.OutputFolder = args[++i];
                    }
                    break;
                case "-skipexisting":
                case "--skipexisting":
                    options.SkipExisting = true;
                    break;
                case "-clientrender":
                case "--clientrender":
                    options.ClientSideRender = true;
                    break;
                case "-savermmd":
                case "--savermmd":
                    options.SaveMmdFiles = true;
                    break;
                case "-parallel":
                case "--parallel":
                    options.Parallel = true;
                    break;
                case "-maxfilespertype":
                case "--maxfilespertype":
                    if (i + 1 < args.Length && int.TryParse(args[i + 1], out int maxFiles))
                    {
                        i++;
                        options.MaxFilesPerType = maxFiles;
                    }
                    break;
                case "-generatehtml":
                case "--generatehtml":
                    options.GenerateHtml = true;
                    break;
                case "-usramdisk":
                case "--usramdisk":
                    options.UseRamDisk = true;
                    break;
                case "-worker":
                case "--worker":
                    options.WorkerMode = true;
                    break;
                case "-search":
                case "--search":
                    if (i + 1 < args.Length)
                    {
                        string terms = args[++i];
                        string field = "";
                        if (i + 1 < args.Length &&
                            (args[i + 1].Equals("-searchfield", StringComparison.OrdinalIgnoreCase) ||
                             args[i + 1].Equals("--searchfield", StringComparison.OrdinalIgnoreCase)))
                        {
                            i++;
                            if (i + 1 < args.Length) field = args[++i];
                        }
                        options.SearchFilters.Add((terms, field));
                    }
                    break;
                case "-searchtypes":
                case "--searchtypes":
                    if (i + 1 < args.Length)
                        options.SearchTypes = args[++i].Split(',', StringSplitOptions.RemoveEmptyEntries);
                    break;
                case "-searchlogic":
                case "--searchlogic":
                    if (i + 1 < args.Length)
                    {
                        string logic = args[++i].ToUpper();
                        if (logic == "AND" || logic == "OR")
                            options.SearchLogic = logic;
                    }
                    break;
            }
        }

        // Line 80-82: Expand 'All' to include all file types
        if (options.FileTypes.Contains("All"))
        {
            options.FileTypes = new[] { "Cbl", "Rex", "Bat", "Ps1", "Sql", "CSharp", "Gs" };
        }

        Logger.LogMessage($"FileTypes filter: {string.Join(", ", options.FileTypes)}", LogLevel.INFO);

        return options;
    }

    public static void PrintHelp()
    {
        string optPath = Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt";
        string defaultOutput = Path.Combine(optPath, "Webs", "AutoDocJson");

        Console.WriteLine(@"
AutoDocJson - Legacy Source Code Documentation Generator
=========================================================

Parses COBOL, REXX, BAT, PS1, SQL, C# and GS source files and generates
interactive HTML documentation with Mermaid diagrams.

USAGE:
  AutoDocJson [options]

OPTIONS:

  --help, -h, /?           Show this help and exit

  --regenerate <mode>      Regeneration mode (default: Incremental)
                             Incremental  Only files changed since last run
                             All          Regenerate everything
                             Errors       Only files with previous errors
                             JsonOnly     Only regenerate JSON index files
                             Single       Process only the --singlefile path
                             Clean        Full reset then regenerate all

  --singlefile <path>      File path for Single mode

  --filetypes <types>      Comma-separated list of types to process
                             All (default), Cbl, Rex, Bat, Ps1, Sql, CSharp, Gs

  --maxfilespertype <n>    Limit files per type (0 = unlimited, default: 0)

  --outputfolder <path>    HTML output location
                             Default: " + defaultOutput + @"

  --parallel               Enable parallel processing (default: on)
  --skipexisting           Skip files that already have output HTML
  --clientrender           Use Mermaid.js client-side rendering (default: on)
  --savermmd               Save intermediate .mmd diagram files (default: off)
  --generatehtml           Generate HTML output
  --usramdisk              Use RAM disk for work files

  --worker                 Distributed worker mode: watches server for
                             BatchRunnerStarted.json, then processes worklist
                             items from the server's _regenerate_worklist/ folder.
                             Requires AutoDocJson:ServerName in appsettings.json.
                             Cannot run on the server itself.

SEARCH OPTIONS:

  --search <terms>         Search generated documentation for terms
    [--searchfield <fld>]  Restrict search to a specific JSON field
  --searchtypes <types>    Comma-separated file types to search (e.g. Cbl,Ps1)
  --searchlogic <op>       AND (default) or OR for multiple --search filters

EXAMPLES:

  AutoDocJson --regenerate All --parallel
      Regenerate all documentation using parallel processing.

  AutoDocJson --regenerate Single --singlefile C:\src\PROG.CBL
      Parse and generate docs for a single file.

  AutoDocJson --filetypes Cbl,Ps1 --maxfilespertype 10
      Process only COBOL and PS1 files, max 10 each.

  AutoDocJson --search ""ARTIKKELNR"" --searchtypes Cbl
      Search COBOL docs for ARTIKKELNR.

  AutoDocJson --search ""customer"" --search ""order"" --searchlogic OR
      Search for docs mentioning customer OR order.
");
    }
}
