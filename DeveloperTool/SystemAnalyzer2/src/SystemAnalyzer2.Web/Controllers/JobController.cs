using DedgeAuth.Client.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using SystemAnalyzer2.Core.Models;

namespace SystemAnalyzer2.Web.Controllers;

[ApiController]
[Route("api/job")]
public sealed class JobController : ControllerBase
{
    private readonly SystemAnalyzerJobService _jobService;
    private readonly SystemAnalyzerOptions _options;

    public JobController(SystemAnalyzerJobService jobService, IOptions<SystemAnalyzerOptions> options)
    {
        _jobService = jobService;
        _options = options.Value;
    }

    [RequireAppPermission("Admin")]
    [HttpPost("start")]
    public IActionResult Start([FromBody] StartAnalysisRequest request)
    {
        if (request is null || string.IsNullOrWhiteSpace(request.Alias) || string.IsNullOrWhiteSpace(request.AllJsonPath))
        {
            return BadRequest(new { error = "Alias and allJsonPath are required." });
        }

        var status = _jobService.Start(
            request.Alias,
            request.AllJsonPath,
            request.SkipPhases,
            request.SkipClassification,
            request.SkipNaming,
            request.SkipCatalog,
            request.RefreshCatalogs,
            request.GenerateStats,
            request.GenerateLocally,
            request.AutoDocApiUrl,
            request.CleanBeforeRun);
        return Ok(status);
    }

    /// <summary>
    /// Upload a local all.json file to the server. The file is saved under
    /// DataRoot\_uploads\{alias}_{timestamp}\all.json and the server-side
    /// path is returned so it can be passed to the start endpoint.
    /// </summary>
    [RequireAppPermission("Admin")]
    [HttpPost("upload")]
    [RequestSizeLimit(50 * 1024 * 1024)]
    public async Task<IActionResult> Upload([FromForm] string alias, IFormFile file)
    {
        if (file is null || file.Length == 0)
        {
            return BadRequest(new { error = "No file provided." });
        }

        if (string.IsNullOrWhiteSpace(alias))
        {
            return BadRequest(new { error = "Alias is required." });
        }

        var timestamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
        var folderName = $"{alias.Trim()}_{timestamp}";
        var uploadDir = Path.Combine(_options.DataRoot, "_uploads", folderName);
        Directory.CreateDirectory(uploadDir);

        var destPath = Path.Combine(uploadDir, "all.json");
        await using var stream = new FileStream(destPath, FileMode.Create);
        await file.CopyToAsync(stream);

        return Ok(new { path = destPath, size = file.Length });
    }

    [RequireAppPermission("Admin", "User")]
    [HttpGet("{jobId}/status")]
    public IActionResult Status(string jobId)
    {
        var status = _jobService.Get(jobId);
        if (status is null)
        {
            return NotFound(new { error = "Job not found." });
        }
        return Ok(status);
    }
}

public sealed class StartAnalysisRequest
{
    public string Alias { get; set; } = string.Empty;
    public string AllJsonPath { get; set; } = string.Empty;
    public List<int> SkipPhases { get; set; } = [];
    public bool SkipClassification { get; set; }
    public bool SkipNaming { get; set; }
    public bool SkipCatalog { get; set; }
    public bool RefreshCatalogs { get; set; }
    public bool GenerateStats { get; set; }

    /// <summary>When null, batch uses appsettings. Set false for remote AutoDoc JSON fetch.</summary>
    public bool? GenerateLocally { get; set; }

    /// <summary>Optional override for <c>--autodoc-api-url</c> (remote fetch base).</summary>
    public string? AutoDocApiUrl { get; set; }

    /// <summary>When false, passes <c>--no-clean-before-run</c> to the batch process. Default true.</summary>
    public bool CleanBeforeRun { get; set; } = true;
}
