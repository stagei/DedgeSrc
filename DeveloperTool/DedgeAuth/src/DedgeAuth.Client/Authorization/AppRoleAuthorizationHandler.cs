using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using DedgeAuth.Client.Options;

namespace DedgeAuth.Client.Authorization;

/// <summary>
/// Authorization handler that checks app-specific roles from JWT claims
/// </summary>
public class AppRoleAuthorizationHandler : AuthorizationHandler<AppRoleRequirement>
{
    private readonly DedgeAuthOptions _options;
    private readonly ILogger<AppRoleAuthorizationHandler> _logger;

    public AppRoleAuthorizationHandler(
        IOptions<DedgeAuthOptions> options,
        ILogger<AppRoleAuthorizationHandler> logger)
    {
        _options = options.Value;
        _logger = logger;
    }

    protected override Task HandleRequirementAsync(
        AuthorizationHandlerContext context,
        AppRoleRequirement requirement)
    {
        // When DedgeAuth is disabled, auto-allow all requests (standalone mode)
        if (!_options.Enabled)
        {
            context.Succeed(requirement);
            return Task.CompletedTask;
        }

        if (!context.User.Identity?.IsAuthenticated ?? true)
        {
            return Task.CompletedTask;
        }

        // Get app permissions from JWT claim
        var appPermissionsClaim = context.User.FindFirst("appPermissions")?.Value;
        Dictionary<string, string>? appPermissions = null;

        if (!string.IsNullOrEmpty(appPermissionsClaim))
        {
            try
            {
                appPermissions = JsonSerializer.Deserialize<Dictionary<string, string>>(appPermissionsClaim);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to parse appPermissions claim");
            }
        }

        // Check if user has app-specific role
        string? userRole = null;
        if (appPermissions != null && appPermissions.TryGetValue(_options.AppId, out var appRole))
        {
            userRole = appRole;
        }
        else
        {
            // Fallback to global access level mapping
            var globalLevelClaim = context.User.FindFirst("globalAccessLevel")?.Value;
            if (int.TryParse(globalLevelClaim, out var level) &&
                _options.GlobalLevelToAppRole.TryGetValue(level, out var mappedRole))
            {
                userRole = mappedRole;
            }
        }

        if (string.IsNullOrEmpty(userRole))
        {
            _logger.LogDebug("User has no role for app {AppId}", _options.AppId);
            return Task.CompletedTask;
        }

        // Check if user's role meets requirement
        var roleHierarchy = GetRoleHierarchy(userRole);
        if (requirement.AllowedRoles.Any(r => roleHierarchy.Contains(r, StringComparer.OrdinalIgnoreCase)))
        {
            context.Succeed(requirement);
        }

        return Task.CompletedTask;
    }

    /// <summary>
    /// Get role hierarchy - higher roles include permissions of lower roles
    /// </summary>
    private static List<string> GetRoleHierarchy(string role)
    {
        var roles = new List<string> { role };

        // Standard hierarchy: Admin > PowerUser > User > ReadOnly
        switch (role.ToLower())
        {
            case "admin":
                roles.AddRange(new[] { "PowerUser", "Operator", "User", "Viewer", "ReadOnly" });
                break;
            case "poweruser":
            case "operator":
                roles.AddRange(new[] { "User", "Viewer", "ReadOnly" });
                break;
            case "user":
            case "viewer":
                roles.Add("ReadOnly");
                break;
        }

        return roles;
    }
}

/// <summary>
/// Authorization requirement for app roles
/// </summary>
public class AppRoleRequirement : IAuthorizationRequirement
{
    public string[] AllowedRoles { get; }

    public AppRoleRequirement(string[] allowedRoles)
    {
        AllowedRoles = allowedRoles;
    }
}
