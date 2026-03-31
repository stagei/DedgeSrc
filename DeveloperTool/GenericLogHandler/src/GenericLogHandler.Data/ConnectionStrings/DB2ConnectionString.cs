using Microsoft.Extensions.Configuration;

namespace GenericLogHandler.Data.ConnectionStrings;

/// <summary>
/// DB2 12.1 Community Edition connection string configuration
/// </summary>
public class DB2ConnectionString
{
    public string Server { get; set; } = string.Empty;
    public string Database { get; set; } = string.Empty;
    public string UserId { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
    public int Port { get; set; } = 50000;
    public string Security { get; set; } = "SSL";
    public int CommandTimeout { get; set; } = 30;
    public int ConnectionTimeout { get; set; } = 15;
    public string CurrentSchema { get; set; } = string.Empty;

    public string GetConnectionString()
    {
        var connectionString = $"Server={Server}:{Port};Database={Database};UID={UserId};PWD={Password};Security={Security};Connection Timeout={ConnectionTimeout};Command Timeout={CommandTimeout};";
        
        if (!string.IsNullOrEmpty(CurrentSchema))
        {
            connectionString += $"CurrentSchema={CurrentSchema};";
        }
        
        return connectionString;
    }

    public static DB2ConnectionString FromConfiguration(IConfiguration configuration)
    {
        return new DB2ConnectionString
        {
            Server = configuration["DB2:Server"] ?? throw new InvalidOperationException("DB2:Server is required"),
            Database = configuration["DB2:Database"] ?? throw new InvalidOperationException("DB2:Database is required"),
            UserId = configuration["DB2:UserId"] ?? throw new InvalidOperationException("DB2:UserId is required"),
            Password = configuration["DB2:Password"] ?? throw new InvalidOperationException("DB2:Password is required"),
            Port = configuration.GetValue<int>("DB2:Port", 50000),
            Security = configuration["DB2:Security"] ?? "SSL",
            CommandTimeout = configuration.GetValue<int>("DB2:CommandTimeout", 30),
            ConnectionTimeout = configuration.GetValue<int>("DB2:ConnectionTimeout", 15),
            CurrentSchema = configuration["DB2:CurrentSchema"] ?? string.Empty
        };
    }
}
