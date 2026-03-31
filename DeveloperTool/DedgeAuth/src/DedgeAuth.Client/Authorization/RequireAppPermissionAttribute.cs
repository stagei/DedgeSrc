using Microsoft.AspNetCore.Authorization;

namespace DedgeAuth.Client.Authorization;

/// <summary>
/// Attribute to require a specific app role for access
/// </summary>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method, AllowMultiple = true)]
public class RequireAppPermissionAttribute : AuthorizeAttribute
{
    public RequireAppPermissionAttribute(params string[] roles)
    {
        // Use custom policy name format: AppRole_Role1,Role2
        Policy = $"AppRole_{string.Join(",", roles)}";
    }
}

/// <summary>
/// Standard app roles (applications can define their own)
/// </summary>
public static class AppRoles
{
    public const string Admin = "Admin";
    public const string PowerUser = "PowerUser";
    public const string User = "User";
    public const string ReadOnly = "ReadOnly";
    
    // ServerMonitorDashboard specific
    public const string Operator = "Operator";
    public const string Viewer = "Viewer";
}
