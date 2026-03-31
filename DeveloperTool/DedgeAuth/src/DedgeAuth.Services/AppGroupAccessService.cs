using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using DedgeAuth.Core.Models;
using DedgeAuth.Data;

namespace DedgeAuth.Services;

/// <summary>
/// Resolves the visible app group tree for a user based on tenant and AD group memberships.
/// Implements narrowing inheritance: child ACLs can only restrict, never broaden parent access.
/// </summary>
public class AppGroupAccessService
{
    private readonly AuthDbContext _context;
    private readonly ILogger<AppGroupAccessService> _logger;

    public AppGroupAccessService(AuthDbContext context, ILogger<AppGroupAccessService> logger)
    {
        _context = context;
        _logger = logger;
    }

    /// <summary>
    /// Returns the full tree for a tenant (admin view, no ACL pruning).
    /// </summary>
    public async Task<List<TreeNode>> GetFullTreeAsync(Guid tenantId)
    {
        var groups = await _context.AppGroups
            .Where(g => g.TenantId == tenantId)
            .Include(g => g.Items)
                .ThenInclude(i => i.App)
            .OrderBy(g => g.SortOrder)
            .ThenBy(g => g.Name)
            .ToListAsync();

        return BuildTree(groups, parentId: null);
    }

    /// <summary>
    /// Returns the pruned tree visible to a user based on their AD group memberships.
    /// Empty branches (groups with no visible apps in subtree) are removed.
    /// </summary>
    public async Task<List<TreeNode>> GetVisibleTreeAsync(
        Guid tenantId,
        IEnumerable<string> userAdGroups,
        Dictionary<string, string> userAppRoles)
    {
        var adGroupSet = new HashSet<string>(userAdGroups, StringComparer.OrdinalIgnoreCase);

        var groups = await _context.AppGroups
            .Where(g => g.TenantId == tenantId)
            .Include(g => g.Items)
                .ThenInclude(i => i.App)
            .OrderBy(g => g.SortOrder)
            .ThenBy(g => g.Name)
            .ToListAsync();

        var tree = BuildTree(groups, parentId: null);
        var pruned = PruneByAcl(tree, adGroupSet, parentAclGroups: null);

        return pruned;
    }

    /// <summary>
    /// Returns ungrouped apps (apps not assigned to any group for this tenant).
    /// </summary>
    public async Task<List<App>> GetUngroupedAppsAsync(Guid tenantId)
    {
        var groupedAppIds = await _context.AppGroupItems
            .Where(i => i.AppGroup.TenantId == tenantId)
            .Select(i => i.AppId)
            .Distinct()
            .ToListAsync();

        return await _context.Apps
            .Where(a => a.IsActive && !groupedAppIds.Contains(a.Id))
            .OrderBy(a => a.DisplayName)
            .ToListAsync();
    }

    private List<TreeNode> BuildTree(List<AppGroup> allGroups, Guid? parentId)
    {
        var nodes = new List<TreeNode>();
        var children = allGroups
            .Where(g => g.ParentId == parentId)
            .OrderBy(g => g.SortOrder)
            .ThenBy(g => g.Name);

        foreach (var group in children)
        {
            var node = new TreeNode
            {
                Type = "group",
                Id = group.Id,
                Name = group.Name,
                Slug = group.Slug,
                Description = group.Description,
                IconUrl = group.IconUrl,
                AclGroupsJson = group.AclGroupsJson,
                SortOrder = group.SortOrder,
                Children = BuildTree(allGroups, group.Id)
            };

            var appItems = group.Items
                .OrderBy(i => i.SortOrder)
                .ThenBy(i => i.App.DisplayName)
                .Select(i => new TreeNode
                {
                    Type = "app",
                    AppId = i.App.AppId,
                    Name = i.App.DisplayName,
                    Url = i.App.BaseUrl,
                    IconUrl = i.App.IconUrl,
                    Description = i.App.Description
                });
            node.Children.AddRange(appItems);

            nodes.Add(node);
        }

        return nodes;
    }

    /// <summary>
    /// Prunes the tree based on ACL groups with narrowing inheritance.
    /// </summary>
    private List<TreeNode> PruneByAcl(
        List<TreeNode> nodes,
        HashSet<string> userAdGroups,
        List<string>? parentAclGroups)
    {
        var result = new List<TreeNode>();

        foreach (var node in nodes)
        {
            if (node.Type == "app")
            {
                result.Add(node);
                continue;
            }

            var nodeAcl = ParseAclGroups(node.AclGroupsJson);
            var effectiveAcl = ResolveEffectiveAcl(nodeAcl, parentAclGroups);

            if (effectiveAcl != null && effectiveAcl.Count > 0)
            {
                if (!effectiveAcl.Any(g => userAdGroups.Contains(g)))
                {
                    _logger.LogDebug("ACL denied for group {GroupName}: user lacks {RequiredGroups}",
                        node.Name, string.Join(", ", effectiveAcl));
                    continue;
                }
            }

            var prunedChildren = PruneByAcl(node.Children, userAdGroups, effectiveAcl);
            if (prunedChildren.Count == 0)
                continue;

            result.Add(new TreeNode
            {
                Type = node.Type,
                Id = node.Id,
                Name = node.Name,
                Slug = node.Slug,
                Description = node.Description,
                IconUrl = node.IconUrl,
                SortOrder = node.SortOrder,
                Children = prunedChildren
            });
        }

        return result;
    }

    /// <summary>
    /// Narrowing inheritance: if node has ACL, intersect with parent; if null, inherit parent.
    /// </summary>
    private static List<string>? ResolveEffectiveAcl(List<string>? nodeAcl, List<string>? parentAcl)
    {
        if (nodeAcl == null || nodeAcl.Count == 0)
            return parentAcl;

        if (parentAcl == null || parentAcl.Count == 0)
            return nodeAcl;

        var intersection = nodeAcl
            .Intersect(parentAcl, StringComparer.OrdinalIgnoreCase)
            .ToList();

        return intersection.Count > 0 ? intersection : nodeAcl;
    }

    private static List<string>? ParseAclGroups(string? json)
    {
        if (string.IsNullOrEmpty(json))
            return null;

        try
        {
            var groups = JsonSerializer.Deserialize<List<string>>(json);
            return groups?.Count > 0 ? groups : null;
        }
        catch
        {
            return null;
        }
    }
}

/// <summary>
/// Serializable tree node for app group hierarchy responses.
/// </summary>
public class TreeNode
{
    public string Type { get; set; } = "group";
    public Guid? Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Slug { get; set; }
    public string? AppId { get; set; }
    public string? Url { get; set; }
    public string? Role { get; set; }
    public string? Description { get; set; }
    public string? IconUrl { get; set; }
    public int SortOrder { get; set; }

    [System.Text.Json.Serialization.JsonIgnore(Condition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull)]
    public string? AclGroupsJson { get; set; }

    public List<TreeNode> Children { get; set; } = new();
}
