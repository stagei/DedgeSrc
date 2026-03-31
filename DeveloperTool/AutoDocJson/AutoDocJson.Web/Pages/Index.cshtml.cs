using System.Diagnostics;
using System.Text.Json;
using AutoDocNew.Models;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace AutoDocNew.Web.Pages;

public class IndexModel : PageModel
{
    private readonly IConfiguration _config;
    private readonly ILogger<IndexModel> _logger;
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true
    };

    public IndexModel(IConfiguration config, ILogger<IndexModel> logger)
    {
        _config = config;
        _logger = logger;
    }

    public List<DocEntry> CblFiles { get; set; } = new();
    public List<DocEntry> BatFiles { get; set; } = new();
    public List<DocEntry> Ps1Files { get; set; } = new();
    public List<DocEntry> RexFiles { get; set; } = new();
    public List<DocEntry> SqlFiles { get; set; } = new();
    public List<DocEntry> CSharpFiles { get; set; } = new();
    public int TotalCount => CblFiles.Count + BatFiles.Count + Ps1Files.Count + RexFiles.Count + SqlFiles.Count + CSharpFiles.Count;

    public void OnGet()
    {
        var sw = Stopwatch.StartNew();

        string outputFolder = _config.GetValue<string>("AutoDocJson:OutputFolder")
            ?? Path.Combine(Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt", "Webs", "AutoDocJson");

        if (!Directory.Exists(outputFolder)) return;

        string searchIndexPath = Path.Combine(outputFolder, "_json", "search-index.json");

        if (System.IO.File.Exists(searchIndexPath))
        {
            LoadFromSearchIndex(searchIndexPath);
        }
        else
        {
            _logger.LogWarning("search-index.json not found at {Path}, falling back to per-file loading", searchIndexPath);
            LoadFromIndividualFiles(outputFolder);
        }

        CblFiles = CblFiles.OrderBy(f => f.FileName).ToList();
        BatFiles = BatFiles.OrderBy(f => f.FileName).ToList();
        Ps1Files = Ps1Files.OrderBy(f => f.FileName).ToList();
        RexFiles = RexFiles.OrderBy(f => f.FileName).ToList();
        SqlFiles = SqlFiles.OrderBy(f => f.FileName).ToList();
        CSharpFiles = CSharpFiles.OrderBy(f => f.FileName).ToList();

        sw.Stop();
        _logger.LogInformation("Index page loaded {Total} files in {Elapsed}ms", TotalCount, sw.ElapsedMilliseconds);
    }

    private void LoadFromSearchIndex(string indexPath)
    {
        try
        {
            string json = System.IO.File.ReadAllText(indexPath);
            var entries = JsonSerializer.Deserialize<List<SearchIndexEntry>>(json, JsonOpts);
            if (entries == null) return;

            foreach (var e in entries)
            {
                var entry = new DocEntry
                {
                    FileName = e.N ?? "",
                    Description = e.D ?? "",
                    Type = e.T ?? "",
                    GeneratedAt = e.G ?? "",
                    JsonFile = e.F ?? ""
                };

                switch (e.T?.ToUpperInvariant())
                {
                    case "CBL": CblFiles.Add(entry); break;
                    case "BAT": BatFiles.Add(entry); break;
                    case "PS1": Ps1Files.Add(entry); break;
                    case "REX": RexFiles.Add(entry); break;
                    case "SQL": SqlFiles.Add(entry); break;
                    case "CSHARP": CSharpFiles.Add(entry); break;
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to load search-index.json");
        }
    }

    private void LoadFromIndividualFiles(string outputFolder)
    {
        foreach (string jsonFile in Directory.EnumerateFiles(outputFolder, "*.json")
            .Where(f => !Path.GetFileName(f).StartsWith("_")))
        {
            try
            {
                string json = System.IO.File.ReadAllText(jsonFile);
                var doc = JsonSerializer.Deserialize<DocFileResult>(json, JsonOpts);
                if (doc == null) continue;

                var entry = new DocEntry
                {
                    FileName = doc.FileName,
                    Description = doc.Description,
                    Type = doc.Type,
                    GeneratedAt = doc.GeneratedAt,
                    JsonFile = Path.GetFileName(jsonFile)
                };

                switch (doc.Type)
                {
                    case "CBL": CblFiles.Add(entry); break;
                    case "BAT": BatFiles.Add(entry); break;
                    case "PS1": Ps1Files.Add(entry); break;
                    case "REX": RexFiles.Add(entry); break;
                    case "SQL": SqlFiles.Add(entry); break;
                    case "CSharp": CSharpFiles.Add(entry); break;
                }
            }
            catch { }
        }
    }

    private class SearchIndexEntry
    {
        public string? F { get; set; }
        public string? T { get; set; }
        public string? N { get; set; }
        public string? D { get; set; }
        public string? G { get; set; }
    }

    public class DocEntry
    {
        public string FileName { get; set; } = "";
        public string Description { get; set; } = "";
        public string Type { get; set; } = "";
        public string GeneratedAt { get; set; } = "";
        public string JsonFile { get; set; } = "";
    }
}
