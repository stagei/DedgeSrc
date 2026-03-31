using System.Security.Claims;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using DedgeAuth.Client.Options;

namespace DedgeAuth.Client.Middleware;

/// <summary>
/// Middleware that validates authenticated sessions with the DedgeAuth server.
/// Ensures tokens have not been revoked. Uses IMemoryCache with configurable TTL
/// to reduce validation calls. Gracefully degrades if DedgeAuth is unreachable.
/// Must run AFTER UseAuthentication()/UseAuthorization() and BEFORE RedirectMiddleware.
/// </summary>
public class DedgeAuthSessionValidationMiddleware
{
    private readonly RequestDelegate _next;
    private readonly DedgeAuthOptions _options;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly IMemoryCache _cache;
    private readonly ILogger<DedgeAuthSessionValidationMiddleware> _logger;

    public DedgeAuthSessionValidationMiddleware(
        RequestDelegate next,
        IOptions<DedgeAuthOptions> options,
        IHttpClientFactory httpClientFactory,
        IMemoryCache cache,
        ILogger<DedgeAuthSessionValidationMiddleware> logger)
    {
        _next = next;
        _options = options.Value;
        _httpClientFactory = httpClientFactory;
        _cache = cache;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        if (!_options.Enabled)
        {
            await _next(context);
            return;
        }

        var path = context.Request.Path.Value?.ToLower() ?? "";

        // Skip paths that should not be session-validated (API, scalar, health, etc.)
        if (ShouldSkipPath(path))
        {
            await _next(context);
            return;
        }

        // Skip non-HTML static files
        if (path.Contains('.') && !path.EndsWith(".html"))
        {
            await _next(context);
            return;
        }

        // Only validate authenticated users
        if (context.User.Identity?.IsAuthenticated != true)
        {
            await _next(context);
            return;
        }

        var userId = context.User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        if (string.IsNullOrEmpty(userId))
        {
            await _next(context);
            return;
        }

        // Check cache first
        var cacheKey = $"DedgeAuth_Session_{userId}";
        if (_cache.TryGetValue(cacheKey, out bool _))
        {
            await _next(context);
            return;
        }

        // Validate with DedgeAuth server
        try
        {
            var client = _httpClientFactory.CreateClient("DedgeAuth");
            var bearerToken = context.Request.Headers["Authorization"]
                .FirstOrDefault()?.Replace("Bearer ", "");

            if (!string.IsNullOrEmpty(bearerToken))
            {
                client.DefaultRequestHeaders.Authorization =
                    new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", bearerToken);
            }

            var response = await client.GetAsync($"{_options.AuthServerUrl}/api/auth/validate");

            if (response.IsSuccessStatusCode)
            {
                // Cache successful validation
                _cache.Set(cacheKey, true, TimeSpan.FromSeconds(_options.SessionValidationCacheTtlSeconds));

                // Fire-and-forget: record this visit on the DedgeAuth server
                FireAndForgetVisitRecord(bearerToken, context, userId);

                await _next(context);
                return;
            }

            // Session invalid or expired — redirect to login
            _cache.Remove(cacheKey);
            var returnUrl = Uri.EscapeDataString(
                $"{context.Request.Scheme}://{context.Request.Host}{context.Request.PathBase}{context.Request.Path}");
            context.Response.Redirect(
                $"{_options.AuthServerUrl}/login.html?returnUrl={returnUrl}&error=session_expired");
            return;
        }
        catch (Exception ex)
        {
            // Graceful degradation: allow access if DedgeAuth is unreachable
            _logger.LogWarning("Could not validate session with DedgeAuth: {Error}", ex.Message);
            await _next(context);
            return;
        }
    }

    private void FireAndForgetVisitRecord(string? bearerToken, HttpContext context, string userId)
    {
        if (string.IsNullOrEmpty(_options.AppId))
            return;

        var appId = _options.AppId;
        var requestPath = context.Request.Path.Value;
        var ipAddress = context.Connection.RemoteIpAddress?.ToString();
        var userAgent = context.Request.Headers["User-Agent"].FirstOrDefault();

        _ = Task.Run(async () =>
        {
            try
            {
                var visitClient = _httpClientFactory.CreateClient("DedgeAuth");
                if (!string.IsNullOrEmpty(bearerToken))
                {
                    visitClient.DefaultRequestHeaders.Authorization =
                        new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", bearerToken);
                }

                var payload = JsonSerializer.Serialize(new
                {
                    appId,
                    path = requestPath,
                    ipAddress,
                    userAgent
                });

                var content = new StringContent(payload, Encoding.UTF8, "application/json");
                await visitClient.PostAsync($"{_options.AuthServerUrl}/api/visits/record", content);
            }
            catch (Exception ex)
            {
                _logger.LogDebug("Failed to record visit for user {UserId}: {Error}", userId, ex.Message);
            }
        });
    }

    private bool ShouldSkipPath(string path)
    {
        foreach (var prefix in _options.SkipPathPrefixes)
        {
            if (path.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                return true;
        }
        return false;
    }
}
