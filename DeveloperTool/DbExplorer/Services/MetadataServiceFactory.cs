using DbExplorer.Data;
using DbExplorer.Services.Providers.DB2;

namespace DbExplorer.Services;

/// <summary>
/// Factory for creating metadata services based on provider type
/// </summary>
public static class MetadataServiceFactory
{
    /// <summary>
    /// Create an appropriate metadata service based on the connection's provider type
    /// </summary>
    public static dynamic CreateMetadataService(IConnectionManager connectionManager)
    {
        var provider = connectionManager.ConnectionInfo.ProviderType?.ToUpperInvariant() ?? "DB2";
        
        return provider switch
        {
            "POSTGRESQL" or "POSTGRES" => throw new NotImplementedException("PostgreSQL metadata service not yet implemented"),
            "SQLSERVER" or "MSSQL" => throw new NotImplementedException("SQL Server metadata service not yet implemented"),
            "ORACLE" => throw new NotImplementedException("Oracle metadata service not yet implemented"),
            "MYSQL" => throw new NotImplementedException("MySQL metadata service not yet implemented"),
            _ => new DB2MetadataService() // Default to DB2
        };
    }
}
