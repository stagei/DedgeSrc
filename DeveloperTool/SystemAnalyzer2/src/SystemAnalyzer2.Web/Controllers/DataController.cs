using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using SystemAnalyzer2.Core.Models;
using SystemAnalyzer2.Core.Services;

namespace SystemAnalyzer2.Web.Controllers;

[Authorize]
[ApiController]
[Route("api/data")]
public sealed class DataController : ControllerBase
{
    private readonly JsonDataService _jsonDataService;
    private readonly SystemAnalyzerOptions _options;

    public DataController(JsonDataService jsonDataService, IOptions<SystemAnalyzerOptions> options)
    {
        _jsonDataService = jsonDataService;
        _options = options.Value;
    }

    [HttpGet("{alias}/{fileName}")]
    public IActionResult GetFile(string alias, string fileName)
    {
        try
        {
            var text = _jsonDataService.ReadAnalysisFile(_options.AnalysisResultsRoot, alias, fileName);
            if (fileName.EndsWith(".json", StringComparison.OrdinalIgnoreCase))
            {
                return Content(text, "application/json; charset=utf-8");
            }

            return Content(text, "text/plain; charset=utf-8");
        }
        catch (FileNotFoundException)
        {
            return NotFound(new { error = "File not found." });
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpGet("{alias}/business-area-overrides")]
    public IActionResult GetBusinessAreaOverrides(string alias)
    {
        try
        {
            var safe = JsonDataService.SanitizeAlias(alias);
            var overridePath = Path.Combine(_options.AnalysisOverridePath, "BusinessAreas", $"{safe}_overrides.json");
            var overrides = BusinessAreaMergeService.LoadOverrides(overridePath);
            return Content(overrides.ToJsonString(new JsonSerializerOptions { WriteIndented = true }), "application/json; charset=utf-8");
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpPost("{alias}/save-node-positions")]
    public IActionResult SaveNodePositions(string alias, [FromBody] NodePositionsPayload payload)
    {
        try
        {
            var safe = JsonDataService.SanitizeAlias(alias);
            var writeOpts = new JsonSerializerOptions
            {
                WriteIndented = true,
                Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping
            };

            var posNode = JsonSerializer.SerializeToNode(payload.NodePositions) ?? new JsonObject();

            int updated = 0;
            var aliasDir = Path.Combine(_options.AnalysisResultsRoot, safe);
            var masterPath = Path.Combine(aliasDir, "dependency_master.json");

            if (System.IO.File.Exists(masterPath))
            {
                PatchMasterWithPositions(masterPath, posNode, writeOpts);
                updated++;
            }

            var historyDir = Path.Combine(aliasDir, "_History");
            if (Directory.Exists(historyDir))
            {
                var latestRun = Directory.GetDirectories(historyDir, $"{safe}_*")
                    .OrderByDescending(d => d)
                    .FirstOrDefault();
                if (latestRun != null)
                {
                    var historyMaster = Path.Combine(latestRun, "dependency_master.json");
                    if (System.IO.File.Exists(historyMaster))
                    {
                        PatchMasterWithPositions(historyMaster, posNode, writeOpts);
                        updated++;
                    }
                }
            }

            return Ok(new { saved = updated, nodeCount = payload.NodePositions?.Count ?? 0 });
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    private static void PatchMasterWithPositions(string masterPath, JsonNode posNode, JsonSerializerOptions writeOpts)
    {
        var text = System.IO.File.ReadAllText(masterPath);
        var master = JsonNode.Parse(text)?.AsObject();
        if (master == null) return;

        master["nodePositions"] = posNode.DeepClone();
        master["nodePositionsSavedAt"] = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
        System.IO.File.WriteAllText(masterPath, master.ToJsonString(writeOpts));
    }

    [HttpPost("{alias}/business-area-override")]
    public IActionResult PostBusinessAreaOverride(string alias, [FromBody] BusinessAreaOverrideRequest request)
    {
        try
        {
            var safe = JsonDataService.SanitizeAlias(alias);
            var overridePath = Path.Combine(_options.AnalysisOverridePath, "BusinessAreas", $"{safe}_overrides.json");
            var overrides = BusinessAreaMergeService.LoadOverrides(overridePath);
            overrides["analysisAlias"] = safe;

            if (request.NewArea != null)
            {
                var additional = overrides["additionalAreas"]?.AsArray() ?? new JsonArray();
                var exists = false;
                foreach (var a in additional)
                {
                    if (string.Equals(a?["id"]?.GetValue<string>(), request.NewArea.Id, StringComparison.OrdinalIgnoreCase))
                    {
                        exists = true;
                        break;
                    }
                }
                if (!exists)
                {
                    additional.Add(new JsonObject
                    {
                        ["id"] = request.NewArea.Id,
                        ["name"] = request.NewArea.Name,
                        ["description"] = request.NewArea.Description ?? ""
                    });
                }
                overrides["additionalAreas"] = additional;
            }

            var progOverrides = overrides["programOverrides"]?.AsObject() ?? new JsonObject();
            progOverrides[request.Program] = request.AreaId;
            overrides["programOverrides"] = progOverrides;

            BusinessAreaMergeService.SaveOverrides(overridePath, overrides);

            var commonPath = Path.Combine(_options.AnalysisResultsRoot, safe, "business_areas.json");
            var commonBasePath = Path.Combine(_options.AnalysisCommonPath, "BusinessAreas", $"{safe}_business_areas.json");
            var sourcePath = System.IO.File.Exists(commonBasePath) ? commonBasePath : commonPath;
            var merged = BusinessAreaMergeService.Merge(sourcePath, overridePath);

            var outputPath = Path.Combine(_options.AnalysisResultsRoot, safe, "business_areas.json");
            Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
            System.IO.File.WriteAllText(outputPath, merged.ToJsonString(new JsonSerializerOptions
            {
                WriteIndented = true,
                Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping
            }));

            return Content(merged.ToJsonString(new JsonSerializerOptions { WriteIndented = true }), "application/json; charset=utf-8");
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }
}

public sealed class BusinessAreaOverrideRequest
{
    public string Program { get; set; } = "";
    public string AreaId { get; set; } = "";
    public NewAreaInfo? NewArea { get; set; }
}

public sealed class NewAreaInfo
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public string? Description { get; set; }
}

public sealed class NodePositionsPayload
{
    public Dictionary<string, NodePosition>? NodePositions { get; set; }
}

public sealed class NodePosition
{
    public double X { get; set; }
    public double Y { get; set; }
}
