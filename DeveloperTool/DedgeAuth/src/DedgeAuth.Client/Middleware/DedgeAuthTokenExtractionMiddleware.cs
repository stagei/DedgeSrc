using System.Net.Http.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using DedgeAuth.Client.Options;

namespace DedgeAuth.Client.Middleware;

/// <summary>
/// Middleware that extracts JWT tokens from the query string and sets the Authorization header.
/// Supports two modes:
///   1. ?code=  – Short auth code from DedgeAuth redirect. Exchanged server-to-server for a JWT,
///                stored in a cookie, then the browser is redirected to a clean URL.
///   2. ?token= – Legacy direct JWT. Sets the Authorization header and stores in cookie.
///   3. Cookie  – If no query param, reads the JWT from the DedgeAuth_access_token cookie.
/// Must run BEFORE UseAuthentication().
/// </summary>
public class DedgeAuthTokenExtractionMiddleware
{
    private readonly RequestDelegate _next;
    private readonly DedgeAuthOptions _options;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly ILogger<DedgeAuthTokenExtractionMiddleware> _logger;

    internal const string CookieName = "DedgeAuth_access_token";

    public DedgeAuthTokenExtractionMiddleware(
        RequestDelegate next,
        IOptions<DedgeAuthOptions> options,
        IHttpClientFactory httpClientFactory,
        ILogger<DedgeAuthTokenExtractionMiddleware> logger)
    {
        _next = next;
        _options = options.Value;
        _httpClientFactory = httpClientFactory;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        if (!_options.Enabled)
        {
            await _next(context);
            return;
        }

        // 1. Auth code exchange: ?code=<short_code> → exchange server-to-server for JWT → cookie → redirect
        var code = context.Request.Query["code"].FirstOrDefault();
        if (!string.IsNullOrEmpty(code))
        {
            _logger.LogDebug("Auth code detected in query string, exchanging for JWT");
            var jwt = await ExchangeAuthCodeAsync(code);
            if (!string.IsNullOrEmpty(jwt))
            {
                SetAccessTokenCookie(context, jwt);
                var cleanUrl = RemoveQueryParam(context, "code");
                _logger.LogDebug("Auth code exchanged successfully, redirecting to clean URL");
                context.Response.Redirect(cleanUrl, permanent: false);
                return;
            }
            _logger.LogWarning("Auth code exchange failed, falling through");
        }

        // 2. Direct token: ?token=<jwt> → store in cookie → redirect to clean URL.
        //    The redirect ensures (a) the long JWT is removed from the URL bar and
        //    (b) the URL has the correct trailing-slash for relative CSS/JS paths.
        var token = context.Request.Query["token"].FirstOrDefault();
        if (!string.IsNullOrEmpty(token))
        {
            _logger.LogDebug("Token detected in query string, storing in cookie and redirecting to clean URL");
            SetAccessTokenCookie(context, token);
            var cleanUrl = RemoveQueryParam(context, "token");
            context.Response.Redirect(cleanUrl, permanent: false);
            return;
        }

        // 3. Trailing-slash enforcement: redirect directory paths (no file extension)
        //    to the same URL with a trailing slash. Without the slash, relative CSS/JS/link
        //    paths (e.g. "css/dashboard.css") resolve from the parent directory instead of
        //    the virtual application root, breaking stylesheets and navigation links.
        //    Skip API endpoints, scalar docs, health checks, etc. – these are not pages.
        var reqPath = $"{context.Request.PathBase}{context.Request.Path}";
        var localPath = (context.Request.Path.Value ?? "").ToLower();
        if (!reqPath.EndsWith('/')
            && string.IsNullOrEmpty(Path.GetExtension(context.Request.Path.Value ?? ""))
            && context.Request.Method == "GET"
            && !_options.SkipPathPrefixes.Any(p => localPath.StartsWith(p, StringComparison.OrdinalIgnoreCase)))
        {
            var redirectUrl = $"{reqPath}/{context.Request.QueryString}";
            _logger.LogDebug("Redirecting to trailing-slash URL: {Url}", redirectUrl);
            context.Response.Redirect(redirectUrl, permanent: false);
            return;
        }

        // 4. Cookie-based auth: read JWT from cookie set by a previous code exchange
        var cookieToken = context.Request.Cookies[CookieName];
        if (!string.IsNullOrEmpty(cookieToken)
            && !context.Request.Headers.ContainsKey("Authorization"))
        {
            context.Request.Headers["Authorization"] = $"Bearer {cookieToken}";
        }

        await _next(context);
    }

    /// <summary>
    /// Exchange a short-lived auth code with the DedgeAuth server for a JWT.
    /// </summary>
    private async Task<string?> ExchangeAuthCodeAsync(string code)
    {
        try
        {
            var authServerUrl = _options.AuthServerUrl.TrimEnd('/');
            var client = _httpClientFactory.CreateClient("DedgeAuth");
            var response = await client.PostAsJsonAsync(
                $"{authServerUrl}/api/auth/exchange",
                new { code });

            if (response.IsSuccessStatusCode)
            {
                var result = await response.Content.ReadFromJsonAsync<ExchangeResponse>();
                return result?.AccessToken;
            }

            _logger.LogWarning("Auth code exchange HTTP failed: {Status}", response.StatusCode);
            return null;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during auth code exchange");
            return null;
        }
    }

    private static void SetAccessTokenCookie(HttpContext context, string jwt)
    {
        context.Response.Cookies.Append(CookieName, jwt, new CookieOptions
        {
            HttpOnly = false,
            SameSite = SameSiteMode.Lax,
            Secure = context.Request.IsHttps,
            Path = context.Request.PathBase.HasValue ? context.Request.PathBase.Value : "/",
            Expires = DateTimeOffset.UtcNow.AddHours(1)
        });
    }

    /// <summary>
    /// Build the current request URL with a specific query parameter removed.
    /// Ensures directory paths (no file extension) end with a trailing slash
    /// so that relative CSS/JS paths resolve correctly under IIS virtual apps.
    /// </summary>
    private static string RemoveQueryParam(HttpContext context, string paramName)
    {
        var request = context.Request;
        var queryItems = request.Query
            .Where(q => !q.Key.Equals(paramName, StringComparison.OrdinalIgnoreCase))
            .Select(q => $"{Uri.EscapeDataString(q.Key)}={Uri.EscapeDataString(q.Value.ToString())}");
        var qs = string.Join("&", queryItems);
        var path = $"{request.PathBase}{request.Path}";
        // Ensure trailing slash on directory paths so relative asset paths resolve correctly
        if (!path.EndsWith('/') && string.IsNullOrEmpty(Path.GetExtension(request.Path.Value ?? "")))
            path += "/";
        return string.IsNullOrEmpty(qs) ? path : $"{path}?{qs}";
    }

    private sealed record ExchangeResponse(bool Success, string? AccessToken);
}
