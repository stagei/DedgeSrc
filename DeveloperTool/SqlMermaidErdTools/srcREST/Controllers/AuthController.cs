using Microsoft.AspNetCore.Mvc;
using SqlMermaidApi.Models;
using SqlMermaidApi.Services;

namespace SqlMermaidApi.Controllers;

[ApiController]
[Route("api/v1/[controller]")]
public class AuthController : ControllerBase
{
    private readonly IApiKeyService _apiKeyService;
    private readonly ILogger<AuthController> _logger;

    public AuthController(IApiKeyService apiKeyService, ILogger<AuthController> logger)
    {
        _apiKeyService = apiKeyService;
        _logger = logger;
    }

    /// <summary>
    /// Create a new API key (for testing - in production this would verify the license)
    /// </summary>
    [HttpPost("create-api-key")]
    [ProducesResponseType(typeof(object), 200)]
    [ProducesResponseType(typeof(ApiErrorResponse), 400)]
    public async Task<IActionResult> CreateApiKey([FromBody] ValidateLicenseRequest request)
    {
        try
        {
            // In production, you would validate the license key here
            // For now, we'll create API keys based on a simple pattern
            var tier = DetermineTierFromLicenseKey(request.LicenseKey);
            
            var apiKey = await _apiKeyService.CreateApiKeyAsync(
                request.Email,
                request.LicenseKey,
                tier);

            return Ok(new
            {
                apiKey = apiKey.Key,
                tier = apiKey.Tier.ToString(),
                email = apiKey.Email,
                expiresAt = apiKey.ExpiresAt,
                message = "API key created successfully. Keep this key secure!"
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to create API key");
            return BadRequest(new ApiErrorResponse
            {
                Error = "Failed to create API key",
                Detail = ex.Message,
                StatusCode = 400
            });
        }
    }

    /// <summary>
    /// Get information about your API key
    /// </summary>
    [HttpGet("key-info")]
    [ProducesResponseType(typeof(ApiKeyInfo), 200)]
    [ProducesResponseType(401)]
    public async Task<IActionResult> GetKeyInfo()
    {
        var apiKey = HttpContext.Items["ApiKey"]?.ToString();
        if (apiKey == null)
        {
            return Unauthorized(new ApiErrorResponse 
            { 
                Error = "Unauthorized", 
                StatusCode = 401 
            });
        }

        try
        {
            var info = await _apiKeyService.GetApiKeyInfoAsync(apiKey);
            return Ok(info);
        }
        catch (UnauthorizedAccessException)
        {
            return Unauthorized(new ApiErrorResponse 
            { 
                Error = "Invalid API key", 
                StatusCode = 401 
            });
        }
    }

    private static LicenseTier DetermineTierFromLicenseKey(string licenseKey)
    {
        // Simple pattern matching for demo purposes
        // In production, you'd validate against a database or licensing service
        if (licenseKey.Contains("PRO", StringComparison.OrdinalIgnoreCase))
        {
            return LicenseTier.Pro;
        }
        if (licenseKey.Contains("ENT", StringComparison.OrdinalIgnoreCase) || 
            licenseKey.Contains("ENTERPRISE", StringComparison.OrdinalIgnoreCase))
        {
            return LicenseTier.Enterprise;
        }
        return LicenseTier.Free;
    }
}

