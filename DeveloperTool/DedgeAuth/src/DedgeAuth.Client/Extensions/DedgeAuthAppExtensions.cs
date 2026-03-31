using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using DedgeAuth.Client.Middleware;
using DedgeAuth.Client.Options;

namespace DedgeAuth.Client.Extensions;

/// <summary>
/// Convenience extension methods for configuring DedgeAuth middleware in the application pipeline.
/// Call UseDedgeAuth() instead of manually wiring token extraction, authentication,
/// authorization, session validation, and redirect middleware.
/// </summary>
public static class DedgeAuthAppExtensions
{
    /// <summary>
    /// Adds all DedgeAuth middleware to the pipeline in the correct order:
    /// 1. Token extraction (query string → Authorization header)
    /// 2. UseAuthentication()
    /// 3. UseAuthorization()
    /// 4. Session validation (checks with DedgeAuth server, cached)
    /// 5. Redirect (unauthenticated → DedgeAuth login page)
    ///
    /// If DedgeAuthOptions.Enabled is false, only UseAuthentication() and UseAuthorization() are added.
    /// </summary>
    public static IApplicationBuilder UseDedgeAuth(this IApplicationBuilder app)
    {
        var options = app.ApplicationServices.GetRequiredService<IOptions<DedgeAuthOptions>>().Value;

        if (!options.Enabled)
        {
            // Still add standard auth middleware even when DedgeAuth is disabled
            app.UseAuthentication();
            app.UseAuthorization();
            return app;
        }

        app.UseMiddleware<DedgeAuthTokenExtractionMiddleware>();
        app.UseAuthentication();
        app.UseAuthorization();
        app.UseMiddleware<DedgeAuthSessionValidationMiddleware>();
        app.UseMiddleware<DedgeAuthRedirectMiddleware>();

        return app;
    }
}
