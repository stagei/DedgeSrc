using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using DedgeAuth.Client.Options;

namespace DedgeAuth.Client.Endpoints;

/// <summary>
/// Extension methods to map DedgeAuth proxy endpoints using minimal APIs.
/// Provides /me (user info) and /logout proxy endpoints so consumer apps
/// don't need to create their own DedgeAuthController.
/// </summary>
public static class DedgeAuthEndpoints
{
    /// <summary>
    /// Maps DedgeAuth proxy endpoints: GET {prefix}/me and POST {prefix}/logout.
    /// The route prefix is configurable via DedgeAuthOptions.ProxyRoutePrefix (default: /api/DedgeAuth).
    /// </summary>
    public static IEndpointRouteBuilder MapDedgeAuthProxy(this IEndpointRouteBuilder endpoints)
    {
        var options = endpoints.ServiceProvider.GetRequiredService<IOptions<DedgeAuthOptions>>().Value;
        var prefix = options.ProxyRoutePrefix.TrimEnd('/');

        endpoints.MapGet($"{prefix}/me", GetCurrentUser)
            .AllowAnonymous()
            .WithName("DedgeAuthGetCurrentUser")
            .WithTags("DedgeAuth");

        endpoints.MapPost($"{prefix}/logout", Logout)
            .RequireAuthorization()
            .WithName("DedgeAuthLogout")
            .WithTags("DedgeAuth");

        endpoints.MapPut($"{prefix}/language", ProxyLanguageUpdate)
            .RequireAuthorization()
            .WithName("DedgeAuthUpdateLanguage")
            .WithTags("DedgeAuth");

        endpoints.MapGet($"{prefix}/app-tree", ProxyAppTree)
            .RequireAuthorization()
            .WithName("DedgeAuthAppTree")
            .WithTags("DedgeAuth");

        // Proxy DedgeAuth UI assets (CSS, JS) so consumer apps use relative paths
        // instead of hardcoded server URLs. Enables server portability.
        endpoints.MapGet($"{prefix}/ui/{{*path}}", ProxyUiAsset)
            .AllowAnonymous()
            .WithName("DedgeAuthProxyUiAsset")
            .WithTags("DedgeAuth");

        // App-local i18n translation endpoints
        endpoints.MapGet("/api/i18n/languages", GetAvailableLanguages)
            .AllowAnonymous()
            .WithName("DedgeAuthI18nLanguages")
            .WithTags("DedgeAuth");

        endpoints.MapGet("/api/i18n/{lang}", GetTranslations)
            .AllowAnonymous()
            .WithName("DedgeAuthI18nTranslations")
            .WithTags("DedgeAuth");

        return endpoints;
    }

    /// <summary>
    /// GET /api/DedgeAuth/me — Returns current user info, applications, and DedgeAuth URL.
    /// Parses JWT claims to build a structured response.
    /// </summary>
    private static IResult GetCurrentUser(HttpContext context, IOptions<DedgeAuthOptions> options)
    {
        var opts = options.Value;

        if (context.User.Identity?.IsAuthenticated != true)
        {
            // Return DedgeAuthUrl even when not authenticated so the client JS
            // can still fetch and inject default tenant CSS (branding is public).
            return Results.Ok(new
            {
                authenticated = false,
                DedgeAuthUrl = opts.GetClientFacingAuthUrl(context)
            });
        }

        var userId = context.User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        var email = context.User.FindFirst(ClaimTypes.Email)?.Value;
        var name = context.User.FindFirst(ClaimTypes.Name)?.Value;
        var globalAccessLevel = context.User.FindFirst("globalAccessLevel")?.Value;
        var globalAccessLevelName = context.User.FindFirst("globalAccessLevelName")?.Value;
        var language = context.User.FindFirst("language")?.Value ?? "nb";
        var appPermissionsJson = context.User.FindFirst("appPermissions")?.Value;
        var tenantJson = context.User.FindFirst("tenant")?.Value;

        // Parse app permissions
        var appPermissions = new Dictionary<string, string>();
        if (!string.IsNullOrEmpty(appPermissionsJson))
        {
            try
            {
                appPermissions = JsonSerializer.Deserialize<Dictionary<string, string>>(appPermissionsJson)
                    ?? new Dictionary<string, string>();
            }
            catch { /* Ignore parse errors */ }
        }

        // Parse tenant info, app routing, and supported languages
        var tenantName = (string?)null;
        var tenantDomain = (string?)null;
        var appRouting = new Dictionary<string, string>();
        var supportedLanguages = new List<string> { "nb", "en" };
        if (!string.IsNullOrEmpty(tenantJson))
        {
            try
            {
                var tenant = JsonSerializer.Deserialize<JsonElement>(tenantJson);
                if (tenant.TryGetProperty("displayName", out var dn)) tenantName = dn.GetString();
                if (tenant.TryGetProperty("domain", out var dom)) tenantDomain = dom.GetString();
                if (tenant.TryGetProperty("appRouting", out var routing))
                {
                    appRouting = JsonSerializer.Deserialize<Dictionary<string, string>>(routing.GetRawText())
                        ?? new Dictionary<string, string>();
                }
                if (tenant.TryGetProperty("supportedLanguages", out var langs))
                {
                    supportedLanguages = JsonSerializer.Deserialize<List<string>>(langs.GetRawText())
                        ?? new List<string> { "nb", "en" };
                }
            }
            catch { /* Ignore parse errors */ }
        }

        // Build applications list from app routing, including per-app role.
        // Transform localhost URLs to use the request's scheme+host so links
        // work from any client machine (not just from the server itself).
        var requestBase = $"{context.Request.Scheme}://{context.Request.Host}";
        var applications = appRouting.Select(kvp => new
        {
            appId = kvp.Key,
            url = TransformLocalhostUrl(kvp.Value, requestBase),
            role = appPermissions.GetValueOrDefault(kvp.Key, ""),
            isCurrent = string.Equals(kvp.Key, opts.AppId, StringComparison.OrdinalIgnoreCase)
        }).ToList();

        // Determine current user's role in this app
        var currentAppRole = appPermissions.GetValueOrDefault(opts.AppId);

        return Results.Ok(new
        {
            authenticated = true,
            language,
            supportedLanguages,
            user = new
            {
                id = userId,
                email,
                name,
                globalAccessLevel,
                globalAccessLevelName
            },
            appPermissions,
            currentAppId = opts.AppId,
            currentAppRole,
            tenant = new
            {
                name = tenantName,
                domain = tenantDomain
            },
            applications,
            DedgeAuthUrl = opts.GetClientFacingAuthUrl(context)
        });
    }

    /// <summary>
    /// GET /api/DedgeAuth/ui/{path} — Proxies UI asset requests (CSS, JS) to the DedgeAuth server.
    /// Supports common.css, user.css, user.js, theme.js.
    /// Caches responses for 1 hour to minimize upstream requests.
    /// </summary>
    private static async Task<IResult> ProxyUiAsset(
        string path,
        HttpContext context,
        IOptions<DedgeAuthOptions> options,
        IHttpClientFactory httpClientFactory,
        IMemoryCache cache)
    {
        var opts = options.Value;

        // Whitelist allowed asset paths to prevent open proxy
        var allowedAssets = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "common.css", "user.css", "user.js", "theme.js",
            "header.js", "tenant-fallback.css", "i18n.js"
        };

        // Also allow i18n/{lang}.json paths for shared translations
        // Regex: i18n/<2-5 letter lang code>.json
        var isI18nFile = path != null
            && path.StartsWith("i18n/", StringComparison.OrdinalIgnoreCase)
            && path.EndsWith(".json", StringComparison.OrdinalIgnoreCase)
            && path.Length <= 15;

        if (string.IsNullOrEmpty(path) || (!allowedAssets.Contains(path) && !isI18nFile))
        {
            return Results.NotFound();
        }

        var cacheKey = $"DedgeAuth_ui_{path}";
        if (cache.TryGetValue(cacheKey, out object? cachedObj) && cachedObj is CachedAsset cached)
        {
            return Results.Bytes(cached.Content, cached.ContentType);
        }

        try
        {
            var client = httpClientFactory.CreateClient("DedgeAuth");
            var response = await client.GetAsync($"{opts.AuthServerUrl}/api/ui/{path}");

            if (!response.IsSuccessStatusCode)
            {
                return Results.StatusCode((int)response.StatusCode);
            }

            var content = await response.Content.ReadAsByteArrayAsync();
            var contentType = response.Content.Headers.ContentType?.ToString() ?? "application/octet-stream";

            // Cache for 1 hour
            var entry = cache.CreateEntry(cacheKey);
            entry.Value = new CachedAsset(content, contentType);
            entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromHours(1);
            entry.Dispose(); // Commits the entry to the cache

            return Results.Bytes(content, contentType);
        }
        catch
        {
            return Results.StatusCode(502);
        }
    }

    /// <summary>
    /// Cached UI asset (content bytes + content type)
    /// </summary>
    private sealed record CachedAsset(byte[] Content, string ContentType);

    /// <summary>
    /// Replaces the scheme+host portion of a localhost URL with the given base.
    /// Preserves the path and query. Non-localhost URLs are returned as-is.
    /// E.g. "http://localhost/DocView" + "http://t-server-app" → "http://t-server-app/DocView"
    /// </summary>
    private static string TransformLocalhostUrl(string url, string requestBase)
    {
        if (string.IsNullOrEmpty(url)) return url;
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri)) return url;
        if (uri.Host is not ("localhost" or "127.0.0.1")) return url;
        return $"{requestBase}{uri.PathAndQuery}";
    }



    /// <summary>
    /// PUT /api/DedgeAuth/language — Proxies language preference update to DedgeAuth server.
    /// </summary>
    private static async Task<IResult> ProxyLanguageUpdate(
        HttpContext context,
        IOptions<DedgeAuthOptions> options,
        IHttpClientFactory httpClientFactory)
    {
        var opts = options.Value;

        try
        {
            var client = httpClientFactory.CreateClient("DedgeAuth");
            var bearerToken = context.Request.Headers["Authorization"]
                .FirstOrDefault()?.Replace("Bearer ", "");

            if (!string.IsNullOrEmpty(bearerToken))
            {
                client.DefaultRequestHeaders.Authorization =
                    new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", bearerToken);
            }

            var body = await new StreamReader(context.Request.Body).ReadToEndAsync();
            var content = new StringContent(body, System.Text.Encoding.UTF8, "application/json");
            var response = await client.PutAsync($"{opts.AuthServerUrl}/api/auth/language", content);

            var responseBody = await response.Content.ReadAsStringAsync();
            return Results.Text(responseBody, "application/json", statusCode: (int)response.StatusCode);
        }
        catch
        {
            return Results.StatusCode(502);
        }
    }

    /// <summary>
    /// GET /api/i18n/languages — Returns available language codes by scanning wwwroot/i18n/*.json
    /// </summary>
    private static IResult GetAvailableLanguages(Microsoft.AspNetCore.Hosting.IWebHostEnvironment env)
    {
        var i18nPath = Path.Combine(env.WebRootPath ?? "", "i18n");
        if (!Directory.Exists(i18nPath))
        {
            return Results.Ok(Array.Empty<string>());
        }

        var languages = Directory.GetFiles(i18nPath, "*.json")
            .Select(f => Path.GetFileNameWithoutExtension(f))
            .Where(name => name.Length >= 2 && name.Length <= 5)
            .OrderBy(name => name)
            .ToArray();

        return Results.Ok(languages);
    }

    /// <summary>
    /// GET /api/i18n/{lang} — Returns translation JSON from wwwroot/i18n/{lang}.json
    /// </summary>
    private static async Task<IResult> GetTranslations(string lang, Microsoft.AspNetCore.Hosting.IWebHostEnvironment env)
    {
        if (string.IsNullOrEmpty(lang) || lang.Length > 5 || lang.Any(c => !char.IsLetterOrDigit(c) && c != '-'))
        {
            return Results.BadRequest();
        }

        var filePath = Path.Combine(env.WebRootPath ?? "", "i18n", $"{lang}.json");
        if (!File.Exists(filePath))
        {
            return Results.NotFound();
        }

        var json = await File.ReadAllTextAsync(filePath);
        return Results.Text(json, "application/json");
    }

    /// <summary>
    /// GET /api/DedgeAuth/app-tree — Proxies the app group tree from DedgeAuth server.
    /// Returns the ACL-filtered tree for the authenticated user.
    /// </summary>
    private static async Task<IResult> ProxyAppTree(
        HttpContext context,
        IOptions<DedgeAuthOptions> options,
        IHttpClientFactory httpClientFactory)
    {
        var opts = options.Value;
        try
        {
            var client = httpClientFactory.CreateClient("DedgeAuth");
            var bearerToken = context.Request.Headers["Authorization"]
                .FirstOrDefault()?.Replace("Bearer ", "");

            if (!string.IsNullOrEmpty(bearerToken))
            {
                client.DefaultRequestHeaders.Authorization =
                    new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", bearerToken);
            }

            var response = await client.GetAsync($"{opts.AuthServerUrl}/api/apps/tree");
            var body = await response.Content.ReadAsStringAsync();
            return Results.Text(body, "application/json", statusCode: (int)response.StatusCode);
        }
        catch
        {
            return Results.Json(new { tree = Array.Empty<object>(), ungrouped = Array.Empty<object>() });
        }
    }

    /// <summary>
    /// POST /api/DedgeAuth/logout — Calls DedgeAuth to revoke the session, returns redirect URL.
    /// </summary>
    private static async Task<IResult> Logout(
        HttpContext context,
        IOptions<DedgeAuthOptions> options,
        IHttpClientFactory httpClientFactory)
    {
        var opts = options.Value;

        try
        {
            var client = httpClientFactory.CreateClient("DedgeAuth");
            var bearerToken = context.Request.Headers["Authorization"]
                .FirstOrDefault()?.Replace("Bearer ", "");

            if (!string.IsNullOrEmpty(bearerToken))
            {
                client.DefaultRequestHeaders.Authorization =
                    new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", bearerToken);
                await client.PostAsync($"{opts.AuthServerUrl}/api/auth/logout", null);
            }
        }
        catch
        {
            // Best-effort logout — proceed even if DedgeAuth is unreachable
        }

        return Results.Ok(new
        {
            success = true,
            redirectUrl = $"{opts.GetClientFacingAuthUrl(context)}/login.html"
        });
    }
}
