using System.Text;
using Microsoft.Extensions.Configuration;
using NLog;
using SystemAnalyzer.Batch.Models;
using SystemAnalyzer.Batch.Services;
using SystemAnalyzer.Core.Models;

namespace SystemAnalyzer.Batch;

public class Program
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    public static async Task<int> Main(string[] args)
    {
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);

        var config = new ConfigurationBuilder()
            .SetBasePath(AppContext.BaseDirectory)
            .AddJsonFile("appsettings.json", optional: false)
            .AddEnvironmentVariables("SA_")
            .AddCommandLine(args)
            .Build();

        var options = new SystemAnalyzerOptions();
        config.GetSection("SystemAnalyzer").Bind(options);

        var request = ParseArgs(args, options);
        if (request == null)
        {
            PrintUsage();
            return 1;
        }

        Logger.Info("SystemAnalyzer.Batch starting");
        Logger.Info($"  Alias:      {request.Alias}");
        Logger.Info($"  AllJson:    {request.AllJsonPath}");
        Logger.Info($"  DataRoot:   {options.DataRoot}");
        Logger.Info($"  SourceRoot: {options.SourceRoot}");
        Logger.Info($"  Db2Dsn:     {options.Db2Dsn}");

        var httpClient = new HttpClient { Timeout = TimeSpan.FromSeconds(120) };

        var ragClient = new RagClient(httpClient, options.RagUrl ?? "", options.VisualCobolRagUrl ?? "", options.RagResults);
        var db2Client = new Db2Client(options.Db2Dsn ?? "");
        var ollamaClient = new OllamaClient(httpClient, options.OllamaUrl ?? "http://localhost:11434", options.OllamaModel ?? "qwen2.5:7b");
        var sourceIndex = new SourceIndexService(options.SourceRoot ?? "", options.DefaultFilePath ?? "N:\\COBNT");
        var cacheService = new CacheService(options.AnalysisCommonPath ?? "");
        var reportService = new ReportService();
        var catalogExportService = new CatalogExportService(db2Client, httpClient);
        var extractor = new DependencyExtractor(ragClient, ollamaClient, sourceIndex, cacheService);
        var classifier = new ClassificationService(ollamaClient, ragClient, cacheService, options);
        var namingService = new NamingService(ollamaClient, ragClient, cacheService, classifier, options.OllamaModel ?? "qwen2.5:7b");

        var pipeline = new FullAnalysisPipeline(
            options, ragClient, db2Client, ollamaClient,
            sourceIndex, cacheService, extractor, classifier, reportService,
            catalogExportService, namingService, httpClient);

        try
        {
            return await pipeline.RunAsync(request);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Pipeline failed");
            return 1;
        }
    }

    private static AnalysisRunRequest? ParseArgs(string[] args, SystemAnalyzerOptions options)
    {
        string? allJsonPath = null;
        string alias = "";
        bool skipClassification = false;
        bool skipNaming = false;
        bool skipCatalog = false;
        bool refreshCatalogs = false;
        bool generateStats = false;
        var skipPhases = new List<int>();

        for (int i = 0; i < args.Length; i++)
        {
            switch (args[i].ToLowerInvariant())
            {
                case "--all-json" when i + 1 < args.Length:
                    allJsonPath = args[++i];
                    break;
                case "--alias" when i + 1 < args.Length:
                    alias = args[++i];
                    break;
                case "--skip-phases" when i + 1 < args.Length:
                    foreach (var p in args[++i].Split(',', StringSplitOptions.RemoveEmptyEntries))
                    {
                        if (int.TryParse(p.Trim(), out var phase))
                            skipPhases.Add(phase);
                    }
                    break;
                case "--skip-classification":
                    skipClassification = true;
                    break;
                case "--skip-naming":
                    skipNaming = true;
                    break;
                case "--skip-catalog":
                    skipCatalog = true;
                    break;
                case "--refresh-catalogs":
                    refreshCatalogs = true;
                    break;
                case "--generate-stats":
                    generateStats = true;
                    break;
            }
        }

        if (string.IsNullOrWhiteSpace(allJsonPath) || !File.Exists(allJsonPath))
        {
            if (!string.IsNullOrWhiteSpace(allJsonPath))
                Logger.Error($"all.json not found: {allJsonPath}");
            return null;
        }

        return new AnalysisRunRequest
        {
            Alias = alias,
            AllJsonPath = Path.GetFullPath(allJsonPath),
            SkipClassification = skipClassification,
            SkipNaming = skipNaming,
            SkipCatalog = skipCatalog,
            RefreshCatalogs = refreshCatalogs,
            GenerateStats = generateStats,
            SkipPhases = skipPhases,
            Options = options
        };
    }

    private static void PrintUsage()
    {
        Console.WriteLine("Usage: SystemAnalyzer.Batch --all-json <path> [--alias <name>] [--skip-phases 5,6] [--skip-classification] [--skip-naming] [--skip-catalog] [--refresh-catalogs] [--generate-stats]");
    }
}
