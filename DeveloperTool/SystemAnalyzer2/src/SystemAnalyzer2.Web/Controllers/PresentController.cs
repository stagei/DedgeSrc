using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Text.Json;
using SystemAnalyzer2.Core.Services;
using SystemAnalyzer2.Web.Services;

namespace SystemAnalyzer2.Web.Controllers;

[Authorize]
[ApiController]
[Route("api/present")]
public sealed class PresentController : ControllerBase
{
    private readonly BusinessDocsService _businessDocs;
    private static readonly JsonSerializerOptions WriteOpts = new() { WriteIndented = true };

    public PresentController(BusinessDocsService businessDocs) => _businessDocs = businessDocs;

    [HttpGet("{alias}/slides")]
    public IActionResult GetSlides(string alias)
    {
        try
        {
            var json = _businessDocs.BuildSlidesJson(alias);
            return Content(json.ToJsonString(WriteOpts), "application/json; charset=utf-8");
        }
        catch (FileNotFoundException ex)
        {
            return NotFound(new { error = ex.Message });
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpGet("{alias}/markdown")]
    public IActionResult GetMarkdown(string alias)
    {
        try
        {
            var md = _businessDocs.ReadProductMarkdown(alias);
            return Content(md, "text/markdown; charset=utf-8");
        }
        catch (Exception ex)
        {
            return NotFound(new { error = ex.Message });
        }
    }

    [HttpGet("{alias}/images")]
    public IActionResult GetImages(string alias)
    {
        try
        {
            var names = _businessDocs.ListScreenshotFileNames(alias);
            return new JsonResult(names);
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpGet("{alias}/image/{name}")]
    public IActionResult GetImage(string alias, string name)
    {
        try
        {
            var (full, contentType) = _businessDocs.ResolveScreenshot(alias, name);
            return PhysicalFile(full, contentType);
        }
        catch (Exception ex)
        {
            return NotFound(new { error = ex.Message });
        }
    }
}
