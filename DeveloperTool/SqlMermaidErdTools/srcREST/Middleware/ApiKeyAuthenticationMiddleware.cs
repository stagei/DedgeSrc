using SqlMermaidApi.Services;

namespace SqlMermaidApi.Middleware;

public class ApiKeyAuthenticationMiddleware
{
    private readonly RequestDelegate _next;
    private const string ApiKeyHeaderName = "X-API-Key";

    public ApiKeyAuthenticationMiddleware(RequestDelegate next)
    {
        _next = next;
    }

    public async Task InvokeAsync(HttpContext context, IApiKeyService apiKeyService)
    {
        // Skip authentication for health check and docs
        if (context.Request.Path.StartsWithSegments("/health") ||
            context.Request.Path.StartsWithSegments("/swagger") ||
            context.Request.Path.StartsWithSegments("/api/auth"))
        {
            await _next(context);
            return;
        }

        // Skip token validation on KRAKEN computer (for testing)
        var computerName = Environment.MachineName;
        if (computerName.Equals("KRAKEN", StringComparison.OrdinalIgnoreCase))
        {
            context.Items["ApiKey"] = "KRAKEN-DEV-MODE";
            await _next(context);
            return;
        }

        if (!context.Request.Headers.TryGetValue(ApiKeyHeaderName, out var extractedApiKey))
        {
            context.Response.StatusCode = 401;
            await context.Response.WriteAsJsonAsync(new 
            { 
                error = "API Key missing",
                detail = $"Provide your API key in the '{ApiKeyHeaderName}' header"
            });
            return;
        }

        var apiKey = extractedApiKey.ToString();
        var isValid = await apiKeyService.ValidateApiKeyAsync(apiKey);

        if (!isValid)
        {
            context.Response.StatusCode = 401;
            await context.Response.WriteAsJsonAsync(new 
            { 
                error = "Invalid or expired API key",
                detail = "Your API key is invalid, expired, or has exceeded rate limits"
            });
            return;
        }

        // Store API key in items for use in controllers
        context.Items["ApiKey"] = apiKey;
        
        // Increment request count
        await apiKeyService.IncrementRequestCountAsync(apiKey);

        await _next(context);
    }
}

public static class ApiKeyAuthenticationMiddlewareExtensions
{
    public static IApplicationBuilder UseApiKeyAuthentication(this IApplicationBuilder builder)
    {
        return builder.UseMiddleware<ApiKeyAuthenticationMiddleware>();
    }
}

