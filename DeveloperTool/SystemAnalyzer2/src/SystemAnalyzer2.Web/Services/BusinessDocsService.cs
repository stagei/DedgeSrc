using System.Net;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Options;
using SystemAnalyzer2.Core.Models;
using SystemAnalyzer2.Core.Services;

namespace SystemAnalyzer2.Web.Services;

public sealed class BusinessDocsService
{
    private readonly SystemAnalyzerOptions _opt;

    public BusinessDocsService(IOptions<SystemAnalyzerOptions> options) => _opt = options.Value;

    public string? ResolveAllJsonPath(string alias)
    {
        var safe = JsonDataService.SanitizeAlias(alias);
        var root = _opt.AnalysisResultsRoot;
        var direct = Path.Combine(root, safe, "all.json");
        if (File.Exists(direct)) return direct;

        var historyDir = Path.Combine(root, safe, "_History");
        if (!Directory.Exists(historyDir)) return null;

        var latest = Directory.GetDirectories(historyDir, $"{safe}_*")
            .OrderByDescending(d => d)
            .FirstOrDefault();
        if (latest == null) return null;

        var p = Path.Combine(latest, "all.json");
        return File.Exists(p) ? p : null;
    }

    public AllJsonV2 LoadAllJson(string alias)
    {
        var path = ResolveAllJsonPath(alias) ?? throw new FileNotFoundException("all.json not found for alias.", alias);
        return AllJsonReader.Load(path);
    }

    public string ReadProductMarkdown(string alias)
    {
        var doc = LoadAllJson(alias);
        var bd = doc.BusinessDocs ?? throw new InvalidOperationException("Profile has no businessDocs section.");
        var rel = bd.ProductDoc ?? throw new InvalidOperationException("businessDocs.productDoc is not set.");
        var path = ResolveBusinessFilePath(bd, rel);
        return File.ReadAllText(path);
    }

    public IReadOnlyList<string> ListScreenshotFileNames(string alias)
    {
        var doc = LoadAllJson(alias);
        var bd = doc.BusinessDocs;
        if (bd?.ScreenshotsDir == null) return Array.Empty<string>();
        var dir = ResolveBusinessFilePath(bd, bd.ScreenshotsDir);
        if (!Directory.Exists(dir)) return Array.Empty<string>();

        return Directory.EnumerateFiles(dir)
            .Select(f => Path.GetFileName(f))
            .Where(n => !string.IsNullOrEmpty(n) && IsSafeImageFileName(n!))
            .OrderBy(s => s, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    public (string FullPath, string ContentType) ResolveScreenshot(string alias, string name)
    {
        if (!IsSafeImageFileName(name))
            throw new InvalidOperationException("Invalid image name.");

        var doc = LoadAllJson(alias);
        var bd = doc.BusinessDocs ?? throw new InvalidOperationException("Profile has no businessDocs section.");
        if (bd.ScreenshotsDir == null)
            throw new DirectoryNotFoundException("Screenshots directory not configured.");

        var dir = ResolveBusinessFilePath(bd, bd.ScreenshotsDir);
        var full = Path.GetFullPath(Path.Combine(dir, name));
        var rootFull = Path.GetFullPath(dir);
        var sep = Path.DirectorySeparatorChar.ToString();
        var underRoot = full.Equals(rootFull, StringComparison.OrdinalIgnoreCase)
            || full.StartsWith(rootFull.TrimEnd(Path.DirectorySeparatorChar) + sep, StringComparison.OrdinalIgnoreCase);
        if (!underRoot || !File.Exists(full))
            throw new FileNotFoundException("Image not found.", name);

        var ext = Path.GetExtension(name).ToLowerInvariant();
        var ct = ext == ".png" ? "image/png"
            : ext == ".jpg" || ext == ".jpeg" ? "image/jpeg"
            : ext == ".gif" ? "image/gif"
            : "application/octet-stream";
        return (full, ct);
    }

    public JsonObject BuildSlidesJson(string alias)
    {
        var doc = LoadAllJson(alias);
        var slides = new JsonArray();

        slides.Add(new JsonObject
        {
            ["id"] = "title",
            ["html"] = $"<h1>{WebUtility.HtmlEncode(doc.Title)}</h1>" +
                       (string.IsNullOrWhiteSpace(doc.AnalysisNote)
                           ? ""
                           : $"<p class=\"sub\">{WebUtility.HtmlEncode(doc.AnalysisNote)}</p>")
        });

        if (doc.BusinessDocs?.ProductDoc is { } prodRel)
        {
            try
            {
                var mdPath = ResolveBusinessFilePath(doc.BusinessDocs, prodRel);
                if (File.Exists(mdPath))
                {
                    var md = File.ReadAllText(mdPath);
                    var idx = 0;
                    foreach (var chunk in SplitMarkdownSections(md))
                    {
                        slides.Add(new JsonObject
                        {
                            ["id"] = $"md-{idx++}",
                            ["markdown"] = chunk
                        });
                    }
                }
            }
            catch
            {
                /* optional path */
            }
        }

        if (doc.BusinessDocs?.CompetitorDoc is { } compRel)
        {
            try
            {
                var p = ResolveBusinessFilePath(doc.BusinessDocs, compRel);
                if (File.Exists(p))
                {
                    slides.Add(new JsonObject
                    {
                        ["id"] = "competitors",
                        ["markdown"] = "## Competitors\n\n" + File.ReadAllText(p)
                    });
                }
            }
            catch { /* optional */ }
        }

        foreach (var shot in ListScreenshotFileNames(alias))
        {
            slides.Add(new JsonObject
            {
                ["id"] = "img-" + shot,
                ["imageUrl"] = $"api/present/{Uri.EscapeDataString(JsonDataService.SanitizeAlias(alias))}/image/{Uri.EscapeDataString(shot)}"
            });
        }

        return new JsonObject
        {
            ["alias"] = JsonDataService.SanitizeAlias(alias),
            ["title"] = doc.Title,
            ["slides"] = slides
        };
    }

    private static string ResolveBusinessFilePath(BusinessDocsRef bd, string relativeOrAbsolute)
    {
        if (Path.IsPathRooted(relativeOrAbsolute))
            return relativeOrAbsolute;

        var port = bd.PortfolioPath?.Trim();
        if (string.IsNullOrEmpty(port))
            throw new InvalidOperationException("businessDocs.portfolioPath is required when using relative document paths.");
        return Path.GetFullPath(Path.Combine(port, relativeOrAbsolute.TrimStart('/', '\\')));
    }

    private static bool IsSafeImageFileName(string name) =>
        name.Length > 0
        && name.IndexOfAny(Path.GetInvalidFileNameChars()) < 0
        && !name.Contains("..", StringComparison.Ordinal)
        && (name.EndsWith(".png", StringComparison.OrdinalIgnoreCase)
            || name.EndsWith(".jpg", StringComparison.OrdinalIgnoreCase)
            || name.EndsWith(".jpeg", StringComparison.OrdinalIgnoreCase)
            || name.EndsWith(".gif", StringComparison.OrdinalIgnoreCase));

    private static IEnumerable<string> SplitMarkdownSections(string md)
    {
        /*
         * Regex: (?m)^##\s+
         * (?m)     — multiline: ^ matches start of each line
         * ^##\s+   — markdown H2 heading starts a new section
         */
        var parts = Regex.Split(md, @"(?m)^##\s+");
        if (parts.Length == 0) yield break;
        if (parts[0].Trim().Length > 0)
            yield return parts[0].TrimEnd();
        for (var i = 1; i < parts.Length; i++)
        {
            var body = parts[i].TrimEnd();
            if (body.Length > 0) yield return "## " + body;
        }
    }
}
