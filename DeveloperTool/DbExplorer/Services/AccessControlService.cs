using System;
using System.Data;
using System.Linq;
using System.Threading.Tasks;
using NLog;
using DbExplorer.Data;
using DbExplorer.Models;

namespace DbExplorer.Services;

/// <summary>
/// Service for determining user access levels based on DB2 DBAUTH
/// </summary>
public class AccessControlService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly MetadataHandler? _metadataHandler;
    
    public AccessControlService(MetadataHandler? metadataHandler = null)
    {
        _metadataHandler = metadataHandler ?? App.MetadataHandler;
        Logger.Debug("AccessControlService initialized with MetadataHandler: {HasHandler}", _metadataHandler != null);
    }
    
    /// <summary>
    /// Determine user's access level by querying SYSCAT.DBAUTH
    /// </summary>
    public async Task<UserPermissions> DetermineAccessLevelAsync(
        IConnectionManager connectionManager,
        string fullUsername)
    {
        Logger.Info("Determining access level for user: {User}", fullUsername);
        
        try
        {
            // Parse username (remove domain prefix)
            var username = ParseUsernameWithoutDomain(fullUsername);
            Logger.Debug("Username without domain: {Username}", username);
            
            // Get SQL from MetadataHandler
            string sql;
            if (_metadataHandler != null)
            {
                try
                {
                    var provider = connectionManager.ConnectionInfo.ProviderType?.ToUpperInvariant() ?? "DB2";
                    var version = provider == "POSTGRESQL" ? "18" : "12.1";
                    var sqlTemplate = _metadataHandler.GetQuery(provider, version, "GetUserAccessLevel");
                    sql = sqlTemplate.Replace("?", $"'{username}'"); // Replace parameter placeholder
                    Logger.Debug("Using SQL from MetadataHandler: GetUserAccessLevel (parameter replaced)");
                }
                catch (Exception ex)
                {
                    Logger.Warn(ex, "Failed to get SQL from MetadataHandler, using fallback");
                    sql = $"SELECT TRIM(GRANTEE) AS USERNAME, DBADMAUTH, SECURITYADMAUTH AS SECADMAUTH FROM SYSCAT.DBAUTH WHERE TRIM(GRANTEE) = '{username}'";
                }
            }
            else
            {
                Logger.Warn("MetadataHandler not available, using fallback SQL");
                sql = $"SELECT TRIM(GRANTEE) AS USERNAME, DBADMAUTH, SECURITYADMAUTH AS SECADMAUTH FROM SYSCAT.DBAUTH WHERE TRIM(GRANTEE) = '{username}'";
            }
            
            Logger.Debug("Querying DBAUTH for user: {Username}", username);
            var result = await connectionManager.ExecuteQueryAsync(sql);
            
            var permissions = new UserPermissions { Username = username };
            
            if (result.Rows.Count == 0)
            {
                // User not in DBAUTH - LOW level (read-only)
                permissions.AccessLevel = UserAccessLevel.Standard;
                permissions.CanExecuteDDL = false;
                permissions.CanExecuteDML = false;
                permissions.CanForceDisconnect = false;
                permissions.CanModifyStatistics = false;
                permissions.CanModifyCDC = false;
                permissions.CanDropObjects = false;
                
                Logger.Info("User {Username} assigned LOW access level (not in DBAUTH)", username);
                Logger.Warn("User {Username} has READ-ONLY access (not in DBAUTH table)", username);
            }
            else
            {
                var row = result.Rows[0];
                var dbAdmAuth = row["DBADMAUTH"]?.ToString();
                
                Logger.Debug("DBAUTH row found for {Username} - DBADMAUTH: {Auth}", username, dbAdmAuth);
                
                if (dbAdmAuth == "Y")
                {
                    // DBA level - full access
                    permissions.AccessLevel = UserAccessLevel.DBA;
                    permissions.CanExecuteDDL = true;
                    permissions.CanExecuteDML = true;
                    permissions.CanForceDisconnect = true;
                    permissions.CanModifyStatistics = true;
                    permissions.CanModifyCDC = true;
                    permissions.CanDropObjects = true;
                    
                    Logger.Info("User {Username} assigned DBA access level (DBADMAUTH = Y)", username);
                }
                else
                {
                    // Middle level - standard user
                    permissions.AccessLevel = UserAccessLevel.Advanced;
                    permissions.CanExecuteDDL = false;
                    permissions.CanExecuteDML = true;  // Can do DML but not DDL
                    permissions.CanForceDisconnect = false;
                    permissions.CanModifyStatistics = false;
                    permissions.CanModifyCDC = false;
                    permissions.CanDropObjects = false;
                    
                    Logger.Info("User {Username} assigned MIDDLE access level (in DBAUTH, not DBA)", username);
                }
                
                // Log all granted authorities
                Logger.Debug("Checking granted authorities for {Username}", username);
                foreach (DataColumn col in result.Columns)
                {
                    if (col.ColumnName.EndsWith("AUTH"))
                    {
                        var value = row[col]?.ToString();
                        if (value == "Y")
                        {
                            permissions.GrantedAuthorities.Add(col.ColumnName);
                            Logger.Debug("Authority granted: {Authority} = Y", col.ColumnName);
                        }
                    }
                }
                
                Logger.Info("User {Username} has {Count} granted authorities", 
                    username, permissions.GrantedAuthorities.Count);
            }
            
            return permissions;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to determine access level for user: {User}", fullUsername);
            Logger.Warn("SECURITY: Defaulting to LOW (read-only) access level due to error");
            
            // Default to LOW (read-only) on error for security
            return new UserPermissions
            {
                Username = fullUsername,
                AccessLevel = UserAccessLevel.Standard,
                CanExecuteDDL = false,
                CanExecuteDML = false,
                CanForceDisconnect = false,
                CanModifyStatistics = false,
                CanModifyCDC = false,
                CanDropObjects = false
            };
        }
    }
    
    /// <summary>
    /// Parse username to remove domain prefix
    /// </summary>
    /// <param name="fullUsername">Full username (may include domain)</param>
    /// <returns>Username without domain prefix</returns>
    /// <example>
    /// "DOMAIN\username" -> "username"
    /// "username@domain.com" -> "username"
    /// "username" -> "username"
    /// </example>
    public string ParseUsernameWithoutDomain(string fullUsername)
    {
        Logger.Debug("Parsing username: {FullUsername}", fullUsername);
        
        if (string.IsNullOrWhiteSpace(fullUsername))
        {
            Logger.Warn("Empty username provided");
            return string.Empty;
        }
        
        // Remove Windows domain prefix: "DOMAIN\username" -> "username"
        if (fullUsername.Contains("\\"))
        {
            var parsed = fullUsername.Split('\\')[1];
            Logger.Debug("Removed domain prefix: {FullUsername} -> {Parsed}", fullUsername, parsed);
            return parsed;
        }
        
        // Remove email domain: "username@domain.com" -> "username"
        if (fullUsername.Contains("@"))
        {
            var parsed = fullUsername.Split('@')[0];
            Logger.Debug("Removed email domain: {FullUsername} -> {Parsed}", fullUsername, parsed);
            return parsed;
        }
        
        // No domain found, return as-is
        Logger.Debug("No domain found, using as-is: {Username}", fullUsername);
        return fullUsername;
    }
    
    /// <summary>
    /// Validate if user can perform an operation
    /// </summary>
    public bool CanUserPerformOperation(UserPermissions permissions, string operationType)
    {
        Logger.Debug("Checking if user {Username} ({Level}) can perform: {Operation}",
            permissions.Username, permissions.AccessLevel, operationType);
        
        var canPerform = operationType.ToUpperInvariant() switch
        {
            "DDL" => permissions.CanExecuteDDL,
            "DML" => permissions.CanExecuteDML,
            "FORCE_DISCONNECT" => permissions.CanForceDisconnect,
            "RUNSTATS" => permissions.CanModifyStatistics,
            "CDC" => permissions.CanModifyCDC,
            "DROP" => permissions.CanDropObjects,
            "SELECT" => true, // Everyone can SELECT
            _ => false
        };
        
        Logger.Debug("Can perform {Operation}: {CanPerform}", operationType, canPerform);
        return canPerform;
    }
}

