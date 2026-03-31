using Microsoft.AspNetCore.Mvc;

namespace DedgeAuth.Api.Controllers;

/// <summary>
/// Controller for serving DedgeAuth UI assets (JS, CSS) that can be consumed by client apps
/// This enables centralized theme and user menu components
/// </summary>
[ApiController]
[Route("api/ui")]
public class UIController : ControllerBase
{
    private readonly IWebHostEnvironment _environment;
    private readonly IConfiguration _configuration;

    public UIController(IWebHostEnvironment environment, IConfiguration configuration)
    {
        _environment = environment;
        _configuration = configuration;
    }

    /// <summary>
    /// Get the shared header component (brand bar, theme toggle, logo injection)
    /// </summary>
    [HttpGet("header.js")]
    [ResponseCache(Duration = 3600)]
    public IActionResult GetHeaderJs()
    {
        var path = Path.Combine(_environment.WebRootPath, "js", "DedgeAuth-header.js");
        if (!System.IO.File.Exists(path))
        {
            return NotFound();
        }
        return PhysicalFile(path, "application/javascript");
    }

    /// <summary>
    /// Get the theme JavaScript file
    /// </summary>
    [HttpGet("theme.js")]
    [ResponseCache(Duration = 3600)] // Cache for 1 hour
    public IActionResult GetThemeJs()
    {
        var path = Path.Combine(_environment.WebRootPath, "js", "DedgeAuth-theme.js");
        if (!System.IO.File.Exists(path))
        {
            return NotFound();
        }
        return PhysicalFile(path, "application/javascript");
    }

    /// <summary>
    /// Get the user menu JavaScript file
    /// </summary>
    [HttpGet("user.js")]
    [ResponseCache(Duration = 3600)]
    public IActionResult GetUserJs()
    {
        var path = Path.Combine(_environment.WebRootPath, "js", "DedgeAuth-user.js");
        if (!System.IO.File.Exists(path))
        {
            return NotFound();
        }
        return PhysicalFile(path, "application/javascript");
    }

    /// <summary>
    /// Get the user menu CSS file
    /// </summary>
    [HttpGet("user.css")]
    [ResponseCache(Duration = 3600)]
    public IActionResult GetUserCss()
    {
        var path = Path.Combine(_environment.WebRootPath, "css", "DedgeAuth-user.css");
        if (!System.IO.File.Exists(path))
        {
            return NotFound();
        }
        return PhysicalFile(path, "text/css");
    }

    /// <summary>
    /// Get the common CSS file (theme toggle, etc.)
    /// </summary>
    [HttpGet("common.css")]
    [ResponseCache(Duration = 3600)]
    public IActionResult GetCommonCss()
    {
        var path = Path.Combine(_environment.WebRootPath, "css", "DedgeAuth-common.css");
        if (!System.IO.File.Exists(path))
        {
            return NotFound();
        }
        return PhysicalFile(path, "text/css");
    }

    /// <summary>
    /// Get the tenant fallback CSS (DedgeAuth default theme when tenant theme is empty or unreachable).
    /// Served to consumer apps via proxy; DedgeAuth-user.js may inject this when theme.css fetch fails.
    /// </summary>
    [HttpGet("tenant-fallback.css")]
    [ResponseCache(Duration = 3600)]
    public IActionResult GetTenantFallbackCss()
    {
        var path = Path.Combine(_environment.WebRootPath, "css", "tenant-fallback.css");
        if (!System.IO.File.Exists(path))
        {
            return NotFound();
        }
        return PhysicalFile(path, "text/css");
    }

    /// <summary>
    /// Get the i18n translation loader JavaScript file
    /// </summary>
    [HttpGet("i18n.js")]
    [ResponseCache(Duration = 3600)]
    public IActionResult GetI18nJs()
    {
        var path = Path.Combine(_environment.WebRootPath, "js", "DedgeAuth-i18n.js");
        if (!System.IO.File.Exists(path))
        {
            return NotFound();
        }
        return PhysicalFile(path, "application/javascript");
    }

    /// <summary>
    /// Get a shared translation file by language code (e.g. i18n/nb.json)
    /// </summary>
    [HttpGet("i18n/{lang}.json")]
    [ResponseCache(Duration = 300)]
    public IActionResult GetI18nFile(string lang)
    {
        if (string.IsNullOrEmpty(lang) || lang.Length > 5 || lang.Any(c => !char.IsLetterOrDigit(c) && c != '-'))
        {
            return BadRequest();
        }

        var path = Path.Combine(_environment.WebRootPath, "i18n", $"{lang}.json");
        if (!System.IO.File.Exists(path))
        {
            return NotFound();
        }
        return PhysicalFile(path, "application/json");
    }

    /// <summary>
    /// Get bundled UI assets info for client apps
    /// Returns URLs and configuration for loading DedgeAuth UI components
    /// </summary>
    [HttpGet("assets")]
    public IActionResult GetAssets()
    {
        var DedgeAuthUrl = _configuration["DedgeAuth:BaseUrl"] ?? $"{Request.Scheme}://{Request.Host}";
        
        return Ok(new
        {
            DedgeAuthUrl,
            scripts = new
            {
                theme = $"{DedgeAuthUrl}/api/ui/theme.js",
                user = $"{DedgeAuthUrl}/api/ui/user.js"
            },
            styles = new
            {
                common = $"{DedgeAuthUrl}/api/ui/common.css",
                user = $"{DedgeAuthUrl}/api/ui/user.css",
                tenantFallback = $"{DedgeAuthUrl}/api/ui/tenant-fallback.css"
            }
        });
    }
}
