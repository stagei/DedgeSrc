using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using DedgeAuth.Core.Models;
using DedgeAuth.Data;
using DedgeAuth.Api.Options;

namespace DedgeAuth.Api.Controllers;

/// <summary>
/// Tenant management controller
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class TenantsController : ControllerBase
{
    private readonly AuthDbContext _context;
    private readonly ILogger<TenantsController> _logger;
    private readonly ThemingOptions _themingOptions;

    public TenantsController(
        AuthDbContext context, 
        ILogger<TenantsController> logger,
        IOptions<ThemingOptions> themingOptions)
    {
        _context = context;
        _logger = logger;
        _themingOptions = themingOptions.Value;
    }
    
    /// <summary>
    /// Get effective CSS for a tenant (tenant's custom CSS or system default)
    /// </summary>
    private string GetEffectiveCss(string? tenantCss)
    {
        return string.IsNullOrWhiteSpace(tenantCss) 
            ? _themingOptions.SystemDefaultCss 
            : tenantCss;
    }

    /// <summary>
    /// Serve tenant-specific CSS as a stylesheet.
    /// Called by DedgeAuth-user.js loadTenantCss() from consumer apps.
    /// Route: GET /tenants/{domain}/theme.css (absolute, bypasses api/ prefix)
    /// </summary>
    [HttpGet("/tenants/{domain}/theme.css")]
    [AllowAnonymous]
    [ResponseCache(Duration = 300)] // Cache for 5 minutes
    public async Task<IActionResult> GetTenantThemeCss(string domain)
    {
        var tenant = await _context.Tenants
            .FirstOrDefaultAsync(t => t.Domain.ToLower() == domain.ToLower() && t.IsActive);

        var css = GetEffectiveCss(tenant?.CssOverrides);
        return Content(css, "text/css");
    }

    /// <summary>
    /// Serve tenant logo from the database.
    /// Route: GET /tenants/{domain}/logo (absolute, bypasses api/ prefix)
    /// </summary>
    [HttpGet("/tenants/{domain}/logo")]
    [AllowAnonymous]
    [ResponseCache(Duration = 300)]
    public async Task<IActionResult> GetTenantLogo(string domain)
    {
        var tenant = await _context.Tenants
            .Where(t => t.Domain.ToLower() == domain.ToLower() && t.IsActive)
            .Select(t => new { t.LogoData, t.LogoContentType })
            .FirstOrDefaultAsync();

        if (tenant?.LogoData == null || tenant.LogoData.Length == 0)
        {
            return NotFound();
        }

        return File(tenant.LogoData, tenant.LogoContentType ?? "image/svg+xml");
    }

    /// <summary>
    /// Serve tenant favicon/icon from the database.
    /// Falls back to the logo endpoint if no dedicated icon is stored.
    /// Route: GET /tenants/{domain}/icon (absolute, bypasses api/ prefix)
    /// </summary>
    [HttpGet("/tenants/{domain}/icon")]
    [AllowAnonymous]
    [ResponseCache(Duration = 300)]
    public async Task<IActionResult> GetTenantIcon(string domain)
    {
        var tenant = await _context.Tenants
            .Where(t => t.Domain.ToLower() == domain.ToLower() && t.IsActive)
            .Select(t => new { t.IconData, t.IconContentType, t.LogoData, t.LogoContentType })
            .FirstOrDefaultAsync();

        if (tenant?.IconData != null && tenant.IconData.Length > 0)
        {
            return File(tenant.IconData, tenant.IconContentType ?? "image/x-icon");
        }

        // Fall back to logo if no dedicated icon
        if (tenant?.LogoData != null && tenant.LogoData.Length > 0)
        {
            return File(tenant.LogoData, tenant.LogoContentType ?? "image/svg+xml");
        }

        return NotFound();
    }

    /// <summary>
    /// Get all tenants
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> GetTenants()
    {
        var tenants = await _context.Tenants
            .Where(t => t.IsActive)
            .Select(t => new
            {
                t.Id,
                t.Domain,
                t.DisplayName,
                t.LogoUrl,
                t.LogoContentType,
                HasLogoData = t.LogoData != null,
                t.IconContentType,
                HasIconData = t.IconData != null,
                t.PrimaryColor,
                t.CssOverrides,
                t.AdDomain,
                t.WindowsSsoEnabled,
                AppRouting = t.GetAppRouting()
            })
            .ToListAsync();

        return Ok(tenants);
    }

    /// <summary>
    /// Get tenant by domain (used for login page branding)
    /// </summary>
    [HttpGet("by-domain/{domain}")]
    [AllowAnonymous]
    public async Task<IActionResult> GetTenantByDomain(string domain)
    {
        var tenant = await _context.Tenants
            .FirstOrDefaultAsync(t => t.Domain.ToLower() == domain.ToLower() && t.IsActive);

        if (tenant == null)
        {
            return NotFound(new { message = "Tenant not found" });
        }

        return Ok(new
        {
            tenant.Id,
            tenant.Domain,
            tenant.DisplayName,
            tenant.LogoUrl,
            tenant.LogoContentType,
            HasLogoData = tenant.LogoData != null,
            tenant.IconContentType,
            HasIconData = tenant.IconData != null,
            tenant.PrimaryColor,
            CssOverrides = GetEffectiveCss(tenant.CssOverrides),
            CssOverridesRaw = tenant.CssOverrides,
            tenant.AdDomain,
            tenant.WindowsSsoEnabled,
            AppRouting = tenant.GetAppRouting()
        });
    }

    /// <summary>
    /// Get default tenant (first active tenant, used when no tenant is specified)
    /// </summary>
    [HttpGet("default")]
    [AllowAnonymous]
    public async Task<IActionResult> GetDefaultTenant()
    {
        var tenant = await _context.Tenants
            .Where(t => t.IsActive)
            .OrderBy(t => t.CreatedAt)
            .FirstOrDefaultAsync();

        if (tenant == null)
        {
            // Return a minimal fallback config when no tenants exist
            return Ok(new
            {
                Id = (Guid?)null,
                Domain = "default",
                DisplayName = "DedgeAuth",
                LogoUrl = (string?)null,
                LogoContentType = (string?)null,
                HasLogoData = false,
                IconContentType = (string?)null,
                HasIconData = false,
                PrimaryColor = "#008942",
                CssOverrides = GetEffectiveCss(null),
                CssOverridesRaw = (string?)null,
                AppRouting = new Dictionary<string, string>()
            });
        }

        return Ok(new
        {
            tenant.Id,
            tenant.Domain,
            tenant.DisplayName,
            tenant.LogoUrl,
            tenant.LogoContentType,
            HasLogoData = tenant.LogoData != null,
            tenant.IconContentType,
            HasIconData = tenant.IconData != null,
            tenant.PrimaryColor,
            CssOverrides = GetEffectiveCss(tenant.CssOverrides),
            CssOverridesRaw = tenant.CssOverrides,
            tenant.AdDomain,
            tenant.WindowsSsoEnabled,
            AppRouting = tenant.GetAppRouting()
        });
    }

    /// <summary>
    /// Create tenant
    /// </summary>
    [HttpPost]
    [Authorize(Policy = "GlobalAdmin")]
    public async Task<IActionResult> CreateTenant([FromBody] CreateTenantRequest request)
    {
        if (await _context.Tenants.AnyAsync(t => t.Domain.ToLower() == request.Domain.ToLower()))
        {
            return BadRequest(new { message = "Tenant with this domain already exists" });
        }

        var tenant = new Tenant
        {
            Domain = request.Domain.ToLower(),
            DisplayName = request.DisplayName,
            LogoUrl = request.LogoUrl,
            PrimaryColor = request.PrimaryColor,
            CssOverrides = request.CssOverrides
        };

        if (!string.IsNullOrEmpty(request.LogoDataBase64))
        {
            tenant.LogoData = Convert.FromBase64String(request.LogoDataBase64);
            tenant.LogoContentType = request.LogoContentType ?? "image/svg+xml";
            tenant.LogoUrl = null;
        }

        if (!string.IsNullOrEmpty(request.IconDataBase64))
        {
            tenant.IconData = Convert.FromBase64String(request.IconDataBase64);
            tenant.IconContentType = request.IconContentType ?? "image/x-icon";
        }

        if (request.AppRouting != null)
        {
            tenant.SetAppRouting(request.AppRouting);
        }

        _context.Tenants.Add(tenant);
        await _context.SaveChangesAsync();

        _logger.LogInformation("Tenant created: {Domain}", request.Domain);
        return Ok(new { message = "Tenant created", id = tenant.Id });
    }

    /// <summary>
    /// Update tenant
    /// </summary>
    [HttpPut("{tenantId:guid}")]
    [Authorize(Policy = "GlobalAdmin")]
    public async Task<IActionResult> UpdateTenant(Guid tenantId, [FromBody] UpdateTenantRequest request)
    {
        var tenant = await _context.Tenants.FindAsync(tenantId);
        if (tenant == null)
        {
            return NotFound(new { message = "Tenant not found" });
        }

        tenant.DisplayName = request.DisplayName ?? tenant.DisplayName;
        tenant.LogoUrl = request.LogoUrl ?? tenant.LogoUrl;
        tenant.PrimaryColor = request.PrimaryColor ?? tenant.PrimaryColor;
        tenant.CssOverrides = request.CssOverrides ?? tenant.CssOverrides;
        if (request.AdDomain != null) tenant.AdDomain = string.IsNullOrWhiteSpace(request.AdDomain) ? null : request.AdDomain;

        if (!string.IsNullOrEmpty(request.LogoDataBase64))
        {
            tenant.LogoData = Convert.FromBase64String(request.LogoDataBase64);
            tenant.LogoContentType = request.LogoContentType ?? "image/svg+xml";
            tenant.LogoUrl = null;
        }

        if (!string.IsNullOrEmpty(request.IconDataBase64))
        {
            tenant.IconData = Convert.FromBase64String(request.IconDataBase64);
            tenant.IconContentType = request.IconContentType ?? "image/x-icon";
        }

        if (request.AppRouting != null)
        {
            tenant.SetAppRouting(request.AppRouting);
        }

        await _context.SaveChangesAsync();
        return Ok(new { message = "Tenant updated" });
    }

    /// <summary>
    /// Delete tenant
    /// </summary>
    [HttpDelete("{tenantId:guid}")]
    [Authorize(Policy = "GlobalAdmin")]
    public async Task<IActionResult> DeleteTenant(Guid tenantId)
    {
        var tenant = await _context.Tenants.FindAsync(tenantId);
        if (tenant == null)
        {
            return NotFound(new { message = "Tenant not found" });
        }

        tenant.IsActive = false;
        await _context.SaveChangesAsync();

        return Ok(new { message = "Tenant deactivated" });
    }
}

public record CreateTenantRequest(
    string Domain, 
    string DisplayName, 
    string? LogoUrl, 
    string? LogoDataBase64,
    string? LogoContentType,
    string? IconDataBase64,
    string? IconContentType,
    string? PrimaryColor, 
    string? CssOverrides,
    string? AdDomain,
    Dictionary<string, string>? AppRouting);

public record UpdateTenantRequest(
    string? DisplayName, 
    string? LogoUrl, 
    string? LogoDataBase64,
    string? LogoContentType,
    string? IconDataBase64,
    string? IconContentType,
    string? PrimaryColor, 
    string? CssOverrides,
    string? AdDomain,
    Dictionary<string, string>? AppRouting);
