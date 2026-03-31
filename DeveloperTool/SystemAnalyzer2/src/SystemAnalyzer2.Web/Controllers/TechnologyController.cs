using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using SystemAnalyzer2.Core.Models;
using SystemAnalyzer2.Core.Services;

namespace SystemAnalyzer2.Web.Controllers;

/// <summary>
/// Exposes <c>supported-technologies.json</c> merged with the active analysis profile from <c>all.json</c>.
/// </summary>
[Authorize]
[ApiController]
[Route("api/technology")]
public sealed class TechnologyController : ControllerBase
{
    private readonly JsonDataService _jsonDataService;
    private readonly SystemAnalyzerOptions _options;
    private readonly IWebHostEnvironment _env;

    public TechnologyController(
        JsonDataService jsonDataService,
        IOptions<SystemAnalyzerOptions> options,
        IWebHostEnvironment env)
    {
        _jsonDataService = jsonDataService;
        _options = options.Value;
        _env = env;
    }

    [HttpGet("analysis/{alias}")]
    public IActionResult GetAnalysisTechnology(string alias)
    {
        try
        {
            var allText = _jsonDataService.ReadAnalysisFile(_options.AnalysisResultsRoot, alias, "all.json");
            var allV2 = AllJsonReader.Parse(allText, alias);

            var catalog = LoadSupportedCatalogNode();
            if (catalog is null)
            {
                return NotFound(new { error = "supported-technologies.json not found under wwwroot/data." });
            }

            var profileTechnologies = new JsonArray();
            foreach (var kv in allV2.Technologies)
            {
                if (kv.Value.Entries.Count == 0) continue;
                var match = FindCatalogProduct(catalog, kv.Key, kv.Value);
                profileTechnologies.Add(new JsonObject
                {
                    ["technologyId"] = kv.Key,
                    ["vendor"] = kv.Value.Vendor ?? "",
                    ["product"] = kv.Value.Product ?? "",
                    ["version"] = kv.Value.Version ?? "",
                    ["platform"] = kv.Value.Platform ?? "",
                    ["database"] = kv.Value.Database ?? "",
                    ["entryCount"] = kv.Value.Entries.Count,
                    ["matchedCatalogProduct"] = match?.DeepClone()
                });
            }

            var payload = new JsonObject
            {
                ["supportedCatalog"] = catalog.DeepClone(),
                ["profileTechnologies"] = profileTechnologies,
                ["profileDatabases"] = JsonSerializer.SerializeToNode(allV2.Databases) ?? new JsonArray()
            };

            return Content(
                payload.ToJsonString(new JsonSerializerOptions { WriteIndented = true }),
                "application/json; charset=utf-8");
        }
        catch (FileNotFoundException)
        {
            return NotFound(new { error = "Analysis data or all.json not found." });
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    private JsonNode? LoadSupportedCatalogNode()
    {
        var webRoot = _env.WebRootPath ?? Path.Combine(_env.ContentRootPath, "wwwroot");
        var path = Path.Combine(webRoot, "data", "supported-technologies.json");
        if (!System.IO.File.Exists(path))
        {
            return null;
        }

        return JsonNode.Parse(System.IO.File.ReadAllText(path));
    }

    private static JsonObject? FindCatalogProduct(JsonNode catalog, string technologyId, TechnologySection section)
    {
        var techs = catalog["technologies"]?.AsArray();
        if (techs == null) return null;

        var vendorId = section.Vendor ?? "";
        var productId = section.Product ?? "";

        foreach (var t in techs)
        {
            if (!string.Equals(t?["technologyId"]?.GetValue<string>(), technologyId, StringComparison.OrdinalIgnoreCase))
                continue;

            foreach (var v in t!["vendors"]?.AsArray() ?? [])
            {
                if (!string.Equals(v?["vendorId"]?.GetValue<string>(), vendorId, StringComparison.OrdinalIgnoreCase))
                    continue;

                foreach (var p in v!["products"]?.AsArray() ?? [])
                {
                    if (string.Equals(p?["productId"]?.GetValue<string>(), productId, StringComparison.OrdinalIgnoreCase))
                        return p as JsonObject;
                }
            }
        }

        return null;
    }
}
