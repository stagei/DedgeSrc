using Microsoft.EntityFrameworkCore;
using DedgeAuth.Core.Models;

namespace DedgeAuth.Data;

/// <summary>
/// Entity Framework Core database context for DedgeAuth
/// </summary>
public class AuthDbContext : DbContext
{
    public AuthDbContext(DbContextOptions<AuthDbContext> options) : base(options)
    {
    }

    /// <summary>
    /// User accounts
    /// </summary>
    public DbSet<User> Users { get; set; } = null!;

    /// <summary>
    /// Login tokens (magic links, password reset, email verification)
    /// </summary>
    public DbSet<LoginToken> LoginTokens { get; set; } = null!;

    /// <summary>
    /// Refresh tokens for session management
    /// </summary>
    public DbSet<RefreshToken> RefreshTokens { get; set; } = null!;

    /// <summary>
    /// Registered applications
    /// </summary>
    public DbSet<App> Apps { get; set; } = null!;

    /// <summary>
    /// User permissions per application
    /// </summary>
    public DbSet<AppPermission> AppPermissions { get; set; } = null!;

    /// <summary>
    /// Tenant configurations
    /// </summary>
    public DbSet<Tenant> Tenants { get; set; } = null!;

    /// <summary>
    /// User visit history (populated by DedgeAuthSessionValidationMiddleware)
    /// </summary>
    public DbSet<UserVisit> UserVisits { get; set; } = null!;

    /// <summary>
    /// Access requests (app access, role changes, access level changes)
    /// </summary>
    public DbSet<AccessRequest> AccessRequests { get; set; } = null!;

    /// <summary>
    /// Hierarchical app groups (tenant-isolated, ACL-controlled)
    /// </summary>
    public DbSet<AppGroup> AppGroups { get; set; } = null!;

    /// <summary>
    /// Many-to-many join linking apps into groups
    /// </summary>
    public DbSet<AppGroupItem> AppGroupItems { get; set; } = null!;

    /// <summary>
    /// Cached AD groups synced from LDAP (per tenant)
    /// </summary>
    public DbSet<AdGroupCache> AdGroupsCache { get; set; } = null!;

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        // User configuration
        modelBuilder.Entity<User>(entity =>
        {
            entity.HasIndex(e => e.Email).IsUnique();
            entity.Property(e => e.GlobalAccessLevel).HasConversion<int>();
        });

        // LoginToken configuration
        modelBuilder.Entity<LoginToken>(entity =>
        {
            entity.HasIndex(e => e.Token).IsUnique();
            entity.HasIndex(e => e.UserId);
            entity.HasIndex(e => e.ExpiresAt);
        });

        // RefreshToken configuration
        modelBuilder.Entity<RefreshToken>(entity =>
        {
            entity.HasIndex(e => e.Token).IsUnique();
            entity.HasIndex(e => e.UserId);
            entity.HasIndex(e => e.ExpiresAt);
        });

        // App configuration
        modelBuilder.Entity<App>(entity =>
        {
            entity.HasIndex(e => e.AppId).IsUnique();
        });

        // AppPermission configuration
        modelBuilder.Entity<AppPermission>(entity =>
        {
            entity.HasIndex(e => new { e.UserId, e.AppId }).IsUnique();
        });

        // Tenant configuration
        modelBuilder.Entity<Tenant>(entity =>
        {
            entity.HasIndex(e => e.Domain).IsUnique();
        });

        // UserVisit configuration
        modelBuilder.Entity<UserVisit>(entity =>
        {
            entity.HasIndex(e => new { e.UserId, e.VisitedAt })
                  .IsDescending(false, true)
                  .HasDatabaseName("IX_user_visits_user_id_visited_at");

            entity.HasIndex(e => e.VisitedAt)
                  .IsDescending(true)
                  .HasDatabaseName("IX_user_visits_visited_at");
        });

        // AccessRequest configuration
        modelBuilder.Entity<AccessRequest>(entity =>
        {
            entity.HasIndex(e => new { e.UserId, e.Status })
                  .HasDatabaseName("IX_access_requests_user_id_status");

            entity.HasIndex(e => e.Status)
                  .HasDatabaseName("IX_access_requests_status");
        });

        // AppGroup configuration (adjacency list tree, tenant-isolated)
        modelBuilder.Entity<AppGroup>(entity =>
        {
            entity.HasIndex(e => new { e.TenantId, e.Slug })
                  .IsUnique()
                  .HasDatabaseName("IX_app_groups_tenant_id_slug");

            entity.HasOne(e => e.Parent)
                  .WithMany(e => e.Children)
                  .HasForeignKey(e => e.ParentId)
                  .OnDelete(DeleteBehavior.Restrict);

            entity.HasOne(e => e.Tenant)
                  .WithMany()
                  .HasForeignKey(e => e.TenantId)
                  .OnDelete(DeleteBehavior.Cascade);
        });

        // AppGroupItem configuration (many-to-many join)
        modelBuilder.Entity<AppGroupItem>(entity =>
        {
            entity.HasIndex(e => new { e.AppGroupId, e.AppId })
                  .IsUnique()
                  .HasDatabaseName("IX_app_group_items_group_app");

            entity.HasOne(e => e.AppGroup)
                  .WithMany(e => e.Items)
                  .HasForeignKey(e => e.AppGroupId)
                  .OnDelete(DeleteBehavior.Cascade);

            entity.HasOne(e => e.App)
                  .WithMany()
                  .HasForeignKey(e => e.AppId)
                  .OnDelete(DeleteBehavior.Cascade);
        });

        // AdGroupCache configuration
        modelBuilder.Entity<AdGroupCache>(entity =>
        {
            entity.HasIndex(e => new { e.TenantId, e.SamAccountName })
                  .IsUnique()
                  .HasDatabaseName("IX_ad_groups_cache_tenant_sam");

            entity.HasOne(e => e.Tenant)
                  .WithMany()
                  .HasForeignKey(e => e.TenantId)
                  .OnDelete(DeleteBehavior.Cascade);
        });
    }
}
