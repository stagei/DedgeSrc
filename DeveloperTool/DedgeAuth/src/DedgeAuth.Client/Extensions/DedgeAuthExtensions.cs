using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;
using DedgeAuth.Client.Authorization;
using DedgeAuth.Client.Options;

namespace DedgeAuth.Client.Extensions;

/// <summary>
/// Extension methods for registering DedgeAuth client services
/// </summary>
public static class DedgeAuthExtensions
{
    /// <summary>
    /// Add DedgeAuth authentication and authorization to the application
    /// </summary>
    /// <param name="services">Service collection</param>
    /// <param name="configureOptions">Action to configure DedgeAuth options</param>
    public static IServiceCollection AddDedgeAuth(
        this IServiceCollection services,
        Action<DedgeAuthOptions> configureOptions)
    {
        var options = new DedgeAuthOptions();
        configureOptions(options);

        services.Configure(configureOptions);

        // Register IMemoryCache for session validation caching
        services.AddMemoryCache();

        // Register named HttpClient for DedgeAuth API calls (session validation, logout proxy)
        services.AddHttpClient("DedgeAuth", client =>
        {
            client.Timeout = TimeSpan.FromSeconds(5);
        });

        if (!options.Enabled)
        {
            // When disabled, allow all requests through (standalone mode).
            // DefaultPolicy covers [Authorize], FallbackPolicy covers unannotated endpoints.
            services.AddAuthentication();
            services.AddAuthorization(auth =>
            {
                auth.DefaultPolicy = new AuthorizationPolicyBuilder()
                    .RequireAssertion(_ => true).Build();
                auth.FallbackPolicy = new AuthorizationPolicyBuilder()
                    .RequireAssertion(_ => true).Build();
            });
            // Still register handlers so [RequireAppPermission] doesn't throw at startup
            services.AddSingleton<IAuthorizationPolicyProvider, AppRolePolicyProvider>();
            services.AddScoped<IAuthorizationHandler, AppRoleAuthorizationHandler>();
            return services;
        }

        // Configure JWT authentication
        services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
            .AddJwtBearer(jwtOptions =>
            {
                jwtOptions.TokenValidationParameters = new TokenValidationParameters
                {
                    ValidateIssuer = true,
                    ValidateAudience = true,
                    ValidateLifetime = true,
                    ValidateIssuerSigningKey = true,
                    ValidIssuer = options.JwtIssuer,
                    ValidAudience = options.JwtAudience,
                    IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(options.JwtSecret)),
                    ClockSkew = TimeSpan.FromMinutes(5)
                };

                // Support token in cookie if configured
                if (!string.IsNullOrEmpty(options.AccessTokenCookieName))
                {
                    jwtOptions.Events = new JwtBearerEvents
                    {
                        OnMessageReceived = context =>
                        {
                            if (context.Request.Cookies.TryGetValue(options.AccessTokenCookieName, out var token))
                            {
                                context.Token = token;
                            }
                            return Task.CompletedTask;
                        }
                    };
                }
            });

        // Register authorization handler
        services.AddSingleton<IAuthorizationPolicyProvider, AppRolePolicyProvider>();
        services.AddScoped<IAuthorizationHandler, AppRoleAuthorizationHandler>();

        return services;
    }

    /// <summary>
    /// Add DedgeAuth with configuration from IConfiguration section
    /// </summary>
    public static IServiceCollection AddDedgeAuth(
        this IServiceCollection services,
        Microsoft.Extensions.Configuration.IConfiguration configuration,
        string sectionName = "DedgeAuth")
    {
        var section = configuration.GetSection(sectionName);
        var options = section.Get<DedgeAuthOptions>() ?? new DedgeAuthOptions();

        services.Configure<DedgeAuthOptions>(section);

        return AddDedgeAuth(services, o =>
        {
            o.Enabled = options.Enabled;
            o.AuthServerUrl = options.AuthServerUrl;
            o.JwtSecret = options.JwtSecret;
            o.JwtIssuer = options.JwtIssuer;
            o.JwtAudience = options.JwtAudience;
            o.AppId = options.AppId;
            o.AccessTokenCookieName = options.AccessTokenCookieName;
            o.LoginPath = options.LoginPath;
            o.SessionValidationCacheTtlSeconds = options.SessionValidationCacheTtlSeconds;
            o.ProxyRoutePrefix = options.ProxyRoutePrefix;
            o.SkipPathPrefixes = options.SkipPathPrefixes;
            // Copy global level to app role mapping (if configured in appsettings.json)
            // Setting to empty dictionary disables global access level fallback
            if (options.GlobalLevelToAppRole != null)
            {
                o.GlobalLevelToAppRole = options.GlobalLevelToAppRole;
            }
        });
    }
}
