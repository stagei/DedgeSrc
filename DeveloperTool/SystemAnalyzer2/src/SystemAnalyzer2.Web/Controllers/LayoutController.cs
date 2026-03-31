using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using SystemAnalyzer2.Core.Models;

namespace SystemAnalyzer2.Web.Controllers;

[Authorize]
[ApiController]
[Route("api/layout")]
public sealed class LayoutController : ControllerBase
{
    private readonly SystemAnalyzerOptions _options;

    public LayoutController(IOptions<SystemAnalyzerOptions> options)
    {
        _options = options.Value;
    }

    private string GetLayoutDir(string alias)
    {
        var safe = Core.Services.JsonDataService.SanitizeAlias(alias);
        return Path.Combine(_options.DataRoot, "SavedLayouts", safe);
    }

    [HttpGet("{alias}/list")]
    public IActionResult List(string alias)
    {
        var dir = GetLayoutDir(alias);
        if (!Directory.Exists(dir))
            return Ok(new { layouts = Array.Empty<object>() });

        var files = Directory.GetFiles(dir, "*.json")
            .Select(f => new FileInfo(f))
            .OrderByDescending(f => f.LastWriteTimeUtc)
            .Select(f =>
            {
                var parts = Path.GetFileNameWithoutExtension(f.Name).Split('_', 3);
                return new
                {
                    fileName = f.Name,
                    savedBy = parts.Length > 0 ? parts[0] : "unknown",
                    timestamp = parts.Length > 1 ? parts[1] : "",
                    comment = parts.Length > 2 ? parts[2] : "",
                    size = f.Length,
                    lastModified = f.LastWriteTimeUtc
                };
            })
            .ToArray();

        return Ok(new { layouts = files });
    }

    [HttpGet("{alias}/load")]
    public IActionResult Load(string alias, [FromQuery] string file)
    {
        if (string.IsNullOrWhiteSpace(file))
            return BadRequest(new { error = "file parameter required" });

        var dir = GetLayoutDir(alias);
        var safeName = Path.GetFileName(file);
        var fullPath = Path.Combine(dir, safeName);

        if (!System.IO.File.Exists(fullPath))
            return NotFound(new { error = "Layout not found" });

        var text = System.IO.File.ReadAllText(fullPath);
        return Content(text, "application/json; charset=utf-8");
    }

    [HttpPost("{alias}/save")]
    public async Task<IActionResult> Save(string alias)
    {
        var dir = GetLayoutDir(alias);
        Directory.CreateDirectory(dir);

        using var reader = new StreamReader(Request.Body);
        var body = await reader.ReadToEndAsync();

        string comment;
        try
        {
            var doc = System.Text.Json.JsonDocument.Parse(body);
            comment = doc.RootElement.TryGetProperty("comment", out var c) ? c.GetString() ?? "" : "";
        }
        catch
        {
            comment = "";
        }

        var user = User.Identity?.Name ?? Environment.UserName;
        var safeUser = new string(user.Where(ch => char.IsLetterOrDigit(ch) || ch == '_').ToArray());
        var ts = DateTime.Now.ToString("yyyyMMdd_HHmmss");
        var safeComment = new string(comment.Take(60).Where(ch => char.IsLetterOrDigit(ch) || ch == '-' || ch == '_' || ch == ' ').ToArray())
            .Trim().Replace(' ', '-');
        if (string.IsNullOrEmpty(safeComment)) safeComment = "layout";

        var fileName = $"{safeUser}_{ts}_{safeComment}.json";
        var fullPath = Path.Combine(dir, fileName);

        await System.IO.File.WriteAllTextAsync(fullPath, body);

        return Ok(new { fileName, path = fullPath });
    }

    [HttpDelete("{alias}/{fileName}")]
    public IActionResult Delete(string alias, string fileName)
    {
        var dir = GetLayoutDir(alias);
        var safeName = Path.GetFileName(fileName);
        var fullPath = Path.Combine(dir, safeName);

        if (!System.IO.File.Exists(fullPath))
            return NotFound(new { error = "Layout not found" });

        System.IO.File.Delete(fullPath);
        return Ok(new { deleted = safeName });
    }
}
