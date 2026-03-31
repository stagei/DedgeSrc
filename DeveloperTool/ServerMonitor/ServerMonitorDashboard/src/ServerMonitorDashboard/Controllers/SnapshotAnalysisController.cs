using DedgeAuth.Client.Authorization;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ServerMonitorDashboard.Models;
using ServerMonitorDashboard.Services;

namespace ServerMonitorDashboard.Controllers;

[ApiController]
[Route("api/analysis")]
[Produces("application/json")]
[Authorize]
[RequireAppPermission(AppRoles.ReadOnly, AppRoles.User, AppRoles.PowerUser, AppRoles.Admin)]
public class SnapshotAnalysisController : ControllerBase
{
    private readonly SnapshotAnalysisService _analysisService;
    private readonly ILogger<SnapshotAnalysisController> _logger;

    public SnapshotAnalysisController(SnapshotAnalysisService analysisService, ILogger<SnapshotAnalysisController> logger)
    {
        _analysisService = analysisService;
        _logger = logger;
    }

    [HttpGet("servers")]
    public async Task<Microsoft.AspNetCore.Mvc.ActionResult<List<AnalysisServerInfo>>> GetServers()
    {
        var servers = await _analysisService.GetAvailableServersAsync();
        return Ok(servers);
    }

    [HttpPost("jobs")]
    public Microsoft.AspNetCore.Mvc.ActionResult StartJob([FromBody] StartAnalysisRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Server))
            return BadRequest(new { error = "Server name is required" });

        var jobId = _analysisService.StartJob(request.Server, request.From, request.To);
        _logger.LogInformation("Started analysis job {JobId} for {Server} from {From} to {To}",
            jobId, request.Server, request.From, request.To);

        return Ok(new { jobId });
    }

    [HttpGet("jobs/{jobId}")]
    public Microsoft.AspNetCore.Mvc.ActionResult GetJobStatus(string jobId)
    {
        var job = _analysisService.GetJobStatus(jobId);
        if (job == null)
            return NotFound(new { error = "Job not found" });

        return Ok(job);
    }
}
