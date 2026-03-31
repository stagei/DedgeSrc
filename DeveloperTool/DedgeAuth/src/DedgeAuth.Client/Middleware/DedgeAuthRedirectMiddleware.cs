using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Options;
using DedgeAuth.Client.Options;

namespace DedgeAuth.Client.Middleware;

/// <summary>
/// Middleware that redirects unauthenticated users to the DedgeAuth login page.
/// Skips API endpoints, static files, and paths matching SkipPathPrefixes.
/// Must run AFTER UseAuthentication()/UseAuthorization().
/// </summary>
public class DedgeAuthRedirectMiddleware
{
    private readonly RequestDelegate _next;
    private readonly DedgeAuthOptions _options;

    public DedgeAuthRedirectMiddleware(RequestDelegate next, IOptions<DedgeAuthOptions> options)
    {
        _next = next;
        _options = options.Value;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        if (!_options.Enabled)
        {
            await _next(context);
            return;
        }

        var path = context.Request.Path.Value?.ToLower() ?? "";

        // Skip paths that should not trigger redirect (API, scalar, health, etc.)
        if (ShouldSkipPath(path))
        {
            await _next(context);
            return;
        }

        // Skip non-HTML static files (css, js, images, etc.)
        if (path.Contains('.') && !path.EndsWith(".html"))
        {
            await _next(context);
            return;
        }

        // If user is not authenticated, redirect to DedgeAuth login.
        // Strip any existing "token" query param from the returnUrl to prevent
        // accumulation loops (token in returnUrl → login adds new token → repeat → 404.15).
        if (context.User.Identity?.IsAuthenticated != true)
        {
            var cleanQuery = string.Join("&",
                context.Request.Query
                    .Where(q => !q.Key.Equals("token", StringComparison.OrdinalIgnoreCase)
                             && !q.Key.Equals("code", StringComparison.OrdinalIgnoreCase))
                    .Select(q => $"{Uri.EscapeDataString(q.Key)}={Uri.EscapeDataString(q.Value.ToString())}"));
            var qs = string.IsNullOrEmpty(cleanQuery) ? "" : $"?{cleanQuery}";
            var basePath = $"{context.Request.Scheme}://{context.Request.Host}{context.Request.PathBase}{context.Request.Path}";
            // Ensure trailing slash on directory paths so DedgeAuth redirects back to a URL
            // where relative CSS/JS paths resolve correctly under IIS virtual apps.
            if (!basePath.EndsWith('/') && string.IsNullOrEmpty(Path.GetExtension(context.Request.Path.Value ?? "")))
                basePath += "/";
            var returnUrl = Uri.EscapeDataString($"{basePath}{qs}");
            context.Response.Redirect($"{_options.GetClientFacingAuthUrl(context)}/login.html?returnUrl={returnUrl}");
            return;
        }

        await _next(context);
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
