using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using SystemAnalyzer2.Core.Models;
using SystemAnalyzer2.Core.Services;

namespace SystemAnalyzer2.Web.Controllers;

[AllowAnonymous]
[ApiController]
[Route("api/autodoc")]
public sealed class AutoDocController : ControllerBase
{
    private readonly SystemAnalyzerOptions _options;

    private static readonly HashSet<string> AllowedIndexFiles = new(StringComparer.OrdinalIgnoreCase)
    {
        "CblParseResult.json",
        "BatParseResult.json",
        "Ps1ParseResult.json",
        "Psm1ParseResult.json",
        "RexParseResult.json",
        "SqlParseResult.json",
        "CSharpParseResult.json",
        "search-index.json",
        "_sql_interactions.json"
    };

    public AutoDocController(IOptions<SystemAnalyzerOptions> options)
    {
        _options = options.Value;
    }

    /// <summary>
    /// Serves a per-program AutoDocJson JSON file (e.g. BSAUTOS.CBL.json).
    /// When <paramref name="alias"/> is set, resolves <c>{AnalysisResultsRoot}/{alias}/autodoc/</c> and <c>{DataRoot}/{alias}/autodoc/</c> before the central <see cref="SystemAnalyzerOptions.AutoDocJsonPath"/>.
    /// </summary>
    [HttpGet("{fileName}")]
    [HttpHead("{fileName}")]
    public IActionResult GetFile(string fileName, [FromQuery] string? alias = null)
    {
        var safeName = Path.GetFileName(fileName);
        if (!safeName.EndsWith(".json", StringComparison.OrdinalIgnoreCase))
        {
            return BadRequest(new { error = "Only .json files are served." });
        }

        string? resolved = TryResolveAutodocPath(safeName, alias);
        if (resolved == null)
        {
            return NotFound(new { error = "File not found." });
        }

        try
        {
            var text = System.IO.File.ReadAllText(resolved);
            return Content(text, "application/json; charset=utf-8");
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { error = ex.Message });
        }
    }

    private string? TryResolveAutodocPath(string safeName, string? alias)
    {
        if (!string.IsNullOrWhiteSpace(alias))
        {
            var safeAlias = JsonDataService.SanitizeAlias(alias);
            if (!string.IsNullOrEmpty(safeAlias))
            {
                foreach (var root in new[] { _options.AnalysisResultsRoot, _options.DataRoot })
                {
                    if (string.IsNullOrWhiteSpace(root)) continue;
                    var local = Path.Combine(root.TrimEnd('\\', '/'), safeAlias, "autodoc", safeName);
                    if (System.IO.File.Exists(local))
                        return local;
                }
            }
        }

        var basePath = _options.AutoDocJsonPath;
        if (!string.IsNullOrEmpty(basePath) && Directory.Exists(basePath))
        {
            var central = Path.Combine(basePath, safeName);
            if (System.IO.File.Exists(central))
                return central;
        }

        return null;
    }

    /// <summary>
    /// Serves an AutoDocJson index file from the _json/ subfolder.
    /// </summary>
    [HttpGet("_index/{fileName}")]
    public IActionResult GetIndex(string fileName)
    {
        var basePath = _options.AutoDocJsonPath;
        if (string.IsNullOrEmpty(basePath) || !Directory.Exists(basePath))
        {
            return NotFound(new { error = "AutoDocJson path not configured or not accessible." });
        }

        var safeName = Path.GetFileName(fileName);
        if (!AllowedIndexFiles.Contains(safeName))
        {
            return BadRequest(new { error = $"Index file not allowed: {safeName}" });
        }

        var fullPath = Path.Combine(basePath, "_json", safeName);
        if (!System.IO.File.Exists(fullPath))
        {
            return NotFound(new { error = "Index file not found." });
        }

        try
        {
            var text = System.IO.File.ReadAllText(fullPath);
            return Content(text, "application/json; charset=utf-8");
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { error = ex.Message });
        }
    }

    /// <summary>
    /// Checks whether the AutoDocJson path is accessible and returns basic stats.
    /// </summary>
    [HttpGet("status")]
    public IActionResult GetStatus()
    {
        var basePath = _options.AutoDocJsonPath;
        if (string.IsNullOrEmpty(basePath))
        {
            return Ok(new { available = false, reason = "Path not configured." });
        }

        if (!Directory.Exists(basePath))
        {
            return Ok(new { available = false, reason = "Path not accessible.", path = basePath });
        }

        try
        {
            var jsonCount = Directory.EnumerateFiles(basePath, "*.json", SearchOption.TopDirectoryOnly).Count();
            var hasIndex = Directory.Exists(Path.Combine(basePath, "_json"));
            return Ok(new { available = true, path = basePath, jsonFileCount = jsonCount, hasIndex });
        }
        catch (Exception ex)
        {
            return Ok(new { available = false, reason = ex.Message });
        }
    }
}
