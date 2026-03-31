using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using SystemAnalyzer2.Core.Models;

namespace SystemAnalyzer2.Web.Controllers;

[Authorize]
[ApiController]
[Route("api/profile")]
public sealed class ProfileController : ControllerBase
{
    private readonly SystemAnalyzerOptions _options;
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public ProfileController(IOptions<SystemAnalyzerOptions> options)
    {
        _options = options.Value;
    }

    public sealed class CreateFocusedRequest
    {
        public string SourceAlias { get; set; } = "";
        public string NewAlias { get; set; } = "";
        public string Comment { get; set; } = "";
        public string[] Programs { get; set; } = [];
    }

    [HttpPost("create-focused")]
    public IActionResult CreateFocused([FromBody] CreateFocusedRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.SourceAlias) || string.IsNullOrWhiteSpace(request.NewAlias))
            return BadRequest(new { error = "sourceAlias and newAlias are required" });
        if (request.Programs.Length == 0)
            return BadRequest(new { error = "At least one program is required" });

        var profilesRoot = Path.Combine(Directory.GetCurrentDirectory(), "AnalysisProfiles");
        if (!Directory.Exists(profilesRoot))
            profilesRoot = Path.Combine(_options.DataRoot, "AnalysisProfiles");

        var sourceDir = Path.Combine(profilesRoot, request.SourceAlias);
        var sourceAllJson = Path.Combine(sourceDir, "all.json");
        if (!System.IO.File.Exists(sourceAllJson))
            return NotFound(new { error = $"Source profile not found: {request.SourceAlias}" });

        var safeNew = Core.Services.JsonDataService.SanitizeAlias(request.NewAlias);
        var newDir = Path.Combine(profilesRoot, safeNew);
        if (Directory.Exists(newDir))
            return Conflict(new { error = $"Profile already exists: {safeNew}" });

        var sourceDoc = JsonDocument.Parse(System.IO.File.ReadAllText(sourceAllJson));
        var root = sourceDoc.RootElement;

        var programSet = new HashSet<string>(request.Programs, StringComparer.OrdinalIgnoreCase);

        var newEntries = new List<object>();
        if (root.TryGetProperty("entries", out var entries))
        {
            foreach (var entry in entries.EnumerateArray())
            {
                var prog = entry.TryGetProperty("program", out var p) ? p.GetString() : null;
                if (prog != null && programSet.Remove(prog))
                {
                    newEntries.Add(JsonSerializer.Deserialize<object>(entry.GetRawText())!);
                }
            }
        }

        foreach (var remaining in programSet)
        {
            newEntries.Add(new
            {
                type = "discovered",
                menuChoice = "",
                area = safeNew,
                descriptionNorwegian = "",
                description = $"Discovered via focused profile from {request.SourceAlias}",
                program = remaining,
                filetype = "cbl"
            });
        }

        var database = root.TryGetProperty("database", out var db) ? db.GetString() : null;

        var newAllJson = new
        {
            title = $"Focused profile: {safeNew} (from {request.SourceAlias})",
            database,
            generated = DateTime.Now.ToString("yyyy-MM-dd"),
            analysisNote = request.Comment,
            parentProfile = request.SourceAlias,
            entries = newEntries
        };

        Directory.CreateDirectory(newDir);
        System.IO.File.WriteAllText(
            Path.Combine(newDir, "all.json"),
            JsonSerializer.Serialize(newAllJson, JsonOpts));

        var parentRef = new
        {
            sourceAlias = request.SourceAlias,
            createdAt = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"),
            createdBy = User.Identity?.Name ?? Environment.UserName,
            comment = request.Comment,
            programCount = request.Programs.Length
        };
        System.IO.File.WriteAllText(
            Path.Combine(newDir, "parent.json"),
            JsonSerializer.Serialize(parentRef, JsonOpts));

        return Ok(new
        {
            alias = safeNew,
            path = newDir,
            programCount = newEntries.Count
        });
    }
}
