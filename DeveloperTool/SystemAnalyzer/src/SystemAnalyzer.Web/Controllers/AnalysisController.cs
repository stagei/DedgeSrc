using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using SystemAnalyzer.Core.Models;
using SystemAnalyzer.Core.Services;

namespace SystemAnalyzer.Web.Controllers;

[Authorize]
[ApiController]
[Route("api/analysis")]
public sealed class AnalysisController : ControllerBase
{
    private readonly AnalysisIndexService _analysisIndexService;
    private readonly SystemAnalyzerOptions _options;

    public AnalysisController(AnalysisIndexService analysisIndexService, IOptions<SystemAnalyzerOptions> options)
    {
        _analysisIndexService = analysisIndexService;
        _options = options.Value;
    }

    [HttpGet("list")]
    public IActionResult List()
    {
        var index = _analysisIndexService.Load(_options.AnalysisResultsRoot);
        var analyses = index.Analyses
            .OrderBy(a => a.Alias, StringComparer.OrdinalIgnoreCase)
            .Select(a => new
            {
                alias = a.Alias,
                areas = a.Areas,
                lastRun = a.LastRun,
                latestFolder = a.LatestFolder
            });
        return Ok(new { analyses });
    }
}
