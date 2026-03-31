using Microsoft.AspNetCore.Authorization;
using Microsoft.Extensions.Options;

namespace DedgeAuth.Client.Authorization;

/// <summary>
/// Policy provider that dynamically creates policies for [RequireAppPermission] attribute
/// </summary>
public class AppRolePolicyProvider : IAuthorizationPolicyProvider
{
    private readonly DefaultAuthorizationPolicyProvider _fallbackPolicyProvider;
    private const string PolicyPrefix = "AppRole_";

    public AppRolePolicyProvider(IOptions<AuthorizationOptions> options)
    {
        _fallbackPolicyProvider = new DefaultAuthorizationPolicyProvider(options);
    }

    public Task<AuthorizationPolicy?> GetPolicyAsync(string policyName)
    {
        if (policyName.StartsWith(PolicyPrefix))
        {
            // Parse roles from policy name: "AppRole_Admin,PowerUser"
            var rolesString = policyName[PolicyPrefix.Length..];
            var roles = rolesString.Split(',', StringSplitOptions.RemoveEmptyEntries);

            var policy = new AuthorizationPolicyBuilder()
                .AddRequirements(new AppRoleRequirement(roles))
                .Build();

            return Task.FromResult<AuthorizationPolicy?>(policy);
        }

        return _fallbackPolicyProvider.GetPolicyAsync(policyName);
    }

    public Task<AuthorizationPolicy> GetDefaultPolicyAsync()
    {
        return _fallbackPolicyProvider.GetDefaultPolicyAsync();
    }

    public Task<AuthorizationPolicy?> GetFallbackPolicyAsync()
    {
        return _fallbackPolicyProvider.GetFallbackPolicyAsync();
    }
}
