using System.DirectoryServices;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using DedgeAuth.Core.Models;
using DedgeAuth.Data;

namespace DedgeAuth.Services;

/// <summary>
/// Syncs AD security groups from LDAP into the ad_groups_cache table.
/// One sync per tenant that has an AdDomain configured.
/// </summary>
public class AdGroupSyncService
{
    private readonly AuthDbContext _context;
    private readonly AdGroupSyncOptions _options;
    private readonly ILogger<AdGroupSyncService> _logger;

    public AdGroupSyncService(
        AuthDbContext context,
        IOptions<AdGroupSyncOptions> options,
        ILogger<AdGroupSyncService> logger)
    {
        _context = context;
        _options = options.Value;
        _logger = logger;
    }

    public static DateTime? LastSyncTime { get; private set; }
    public static string? LastSyncStatus { get; private set; }
    public static int LastSyncCount { get; private set; }

    public async Task<int> SyncAllTenantsAsync()
    {
        var tenants = await _context.Tenants
            .Where(t => t.IsActive && !string.IsNullOrEmpty(t.AdDomain))
            .ToListAsync();

        var totalSynced = 0;
        foreach (var tenant in tenants)
        {
            try
            {
                var count = await SyncTenantAsync(tenant);
                totalSynced += count;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "AD group sync failed for tenant {Domain} (AdDomain={AdDomain})",
                    tenant.Domain, tenant.AdDomain);
                LastSyncStatus = $"Failed for {tenant.Domain}: {ex.Message}";
            }
        }

        LastSyncTime = DateTime.UtcNow;
        LastSyncCount = totalSynced;
        if (LastSyncStatus == null || !LastSyncStatus.StartsWith("Failed"))
            LastSyncStatus = $"OK — {totalSynced} groups synced across {tenants.Count} tenant(s)";

        return totalSynced;
    }

    public async Task<int> SyncTenantAsync(Tenant tenant)
    {
        if (string.IsNullOrEmpty(tenant.AdDomain))
            return 0;

        var ldapPath = $"LDAP://{tenant.AdDomain}.{_options.LdapSuffix}";
        _logger.LogInformation("Starting AD group sync: {LdapPath} filter={Filter}", ldapPath, _options.GroupFilter);

        var adGroups = QueryLdapGroups(ldapPath, _options.GroupFilter);
        _logger.LogInformation("Found {Count} AD groups from {LdapPath}", adGroups.Count, ldapPath);

        var existing = await _context.AdGroupsCache
            .Where(g => g.TenantId == tenant.Id)
            .ToListAsync();

        var existingBySam = existing.ToDictionary(g => g.SamAccountName, StringComparer.OrdinalIgnoreCase);
        var seenSams = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var ag in adGroups)
        {
            seenSams.Add(ag.SamAccountName);

            if (existingBySam.TryGetValue(ag.SamAccountName, out var cached))
            {
                cached.DistinguishedName = ag.DistinguishedName;
                cached.Description = ag.Description;
                cached.GroupCategory = ag.GroupCategory;
                cached.MemberCount = ag.MemberCount;
                cached.LastSyncedAt = DateTime.UtcNow;
            }
            else
            {
                ag.TenantId = tenant.Id;
                ag.LastSyncedAt = DateTime.UtcNow;
                _context.AdGroupsCache.Add(ag);
            }
        }

        // Remove groups no longer in AD
        var toRemove = existing.Where(e => !seenSams.Contains(e.SamAccountName)).ToList();
        if (toRemove.Count > 0)
        {
            _context.AdGroupsCache.RemoveRange(toRemove);
            _logger.LogInformation("Removed {Count} stale AD groups for tenant {Domain}", toRemove.Count, tenant.Domain);
        }

        await _context.SaveChangesAsync();
        _logger.LogInformation("AD group sync complete for tenant {Domain}: {Synced} groups, {Removed} removed",
            tenant.Domain, adGroups.Count, toRemove.Count);

        return adGroups.Count;
    }

    private List<AdGroupCache> QueryLdapGroups(string ldapPath, string filter)
    {
        var results = new List<AdGroupCache>();

        try
        {
            using var entry = new DirectoryEntry(ldapPath);
            using var searcher = new DirectorySearcher(entry)
            {
                Filter = filter,
                PageSize = 1000,
                SizeLimit = 0
            };

            searcher.PropertiesToLoad.AddRange(new[]
            {
                "sAMAccountName", "distinguishedName", "description",
                "groupType", "member"
            });

            using var searchResults = searcher.FindAll();
            foreach (SearchResult sr in searchResults)
            {
                var sam = sr.Properties["sAMAccountName"]?.Count > 0
                    ? sr.Properties["sAMAccountName"][0]?.ToString() ?? ""
                    : "";
                if (string.IsNullOrEmpty(sam)) continue;

                var dn = sr.Properties["distinguishedName"]?.Count > 0
                    ? sr.Properties["distinguishedName"][0]?.ToString()
                    : null;
                var desc = sr.Properties["description"]?.Count > 0
                    ? sr.Properties["description"][0]?.ToString()
                    : null;
                var memberCount = sr.Properties["member"]?.Count ?? 0;

                var groupType = sr.Properties["groupType"]?.Count > 0
                    ? Convert.ToInt32(sr.Properties["groupType"][0])
                    : 0;
                var category = (groupType & unchecked((int)0x80000000)) != 0 ? "Security" : "Distribution";

                results.Add(new AdGroupCache
                {
                    SamAccountName = sam,
                    DistinguishedName = dn,
                    Description = desc,
                    GroupCategory = category,
                    MemberCount = memberCount
                });
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "LDAP query failed: {LdapPath}", ldapPath);
            throw;
        }

        return results;
    }
}
