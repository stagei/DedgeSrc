namespace DedgeAuth.Core.Models;

/// <summary>
/// Global access levels for user authorization.
/// Values 0-3 are the original levels. TenantAdmin (5) is a tenant-scoped admin
/// that can manage users/branding within their own tenant only.
/// </summary>
public enum AccessLevel
{
    /// <summary>
    /// Minimal read-only access
    /// </summary>
    ReadOnly = 0,

    /// <summary>
    /// Standard user access
    /// </summary>
    User = 1,

    /// <summary>
    /// Power user with configuration access
    /// </summary>
    PowerUser = 2,

    /// <summary>
    /// Full administrative access (cross-tenant, global)
    /// </summary>
    Admin = 3,

    /// <summary>
    /// Admin scoped to the user's own tenant — can manage users, permissions,
    /// and branding within their tenant but cannot see other tenants' data.
    /// Numerically higher than Admin but functionally narrower in scope.
    /// </summary>
    TenantAdmin = 5
}
