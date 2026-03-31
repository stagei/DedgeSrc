using System.Collections.Generic;

namespace DbExplorer.Models;

/// <summary>
/// User access level based on DB2 DBAUTH privileges
/// </summary>
public enum UserAccessLevel
{
    Standard = 1,  // Standard user - read-only, minimal complexity
    Advanced = 2,  // Advanced user - full DBA operations
    DBA = 3        // Database administrator - all features and security
}

/// <summary>
/// User permissions determined from SYSCAT.DBAUTH
/// </summary>
public class UserPermissions
{
    public UserAccessLevel AccessLevel { get; set; }
    public string Username { get; set; } = string.Empty;
    public bool CanExecuteDDL { get; set; }
    public bool CanExecuteDML { get; set; }
    public bool CanForceDisconnect { get; set; }
    public bool CanModifyStatistics { get; set; }
    public bool CanModifyCDC { get; set; }
    public bool CanDropObjects { get; set; }
    public List<string> GrantedAuthorities { get; set; } = new();
    
    /// <summary>
    /// Access level badge text for UI
    /// </summary>
    public string AccessLevelBadge
    {
        get
        {
            return AccessLevel switch
            {
                UserAccessLevel.DBA => "🛡️ DBA",
                UserAccessLevel.Advanced => "👤 ADVANCED",
                UserAccessLevel.Standard => "🔒 STANDARD",
                _ => "❓ UNKNOWN"
            };
        }
    }
    
    /// <summary>
    /// Badge color for UI
    /// </summary>
    public string BadgeColor
    {
        get
        {
            return AccessLevel switch
            {
                UserAccessLevel.DBA => "Green",
                UserAccessLevel.Advanced => "Orange",
                UserAccessLevel.Standard => "Blue",
                _ => "Gray"
            };
        }
    }
    
    /// <summary>
    /// Tooltip explaining user's permissions
    /// </summary>
    public string PermissionsTooltip
    {
        get
        {
            return AccessLevel switch
            {
                UserAccessLevel.DBA => "Full database administrator access - All operations allowed",
                UserAccessLevel.Advanced => "Advanced user access - DML/DDL allowed, full DBA features",
                UserAccessLevel.Standard => "Standard user access - Read-only operations, simplified interface",
                _ => "Unknown access level"
            };
        }
    }
}

