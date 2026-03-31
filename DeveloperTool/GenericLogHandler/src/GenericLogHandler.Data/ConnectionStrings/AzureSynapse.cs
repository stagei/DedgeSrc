using Microsoft.Extensions.Configuration;

namespace GenericLogHandler.Data.ConnectionStrings;

/// <summary>
/// Azure Synapse Analytics connection string configuration
/// </summary>
public class AzureSynapseConnectionString
{
    public string Server { get; set; } = string.Empty;
    public string Database { get; set; } = string.Empty;
    public string UserId { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
    public int Port { get; set; } = 1433;
    public bool UseSSL { get; set; } = true;
    public int CommandTimeout { get; set; } = 30;
    public int ConnectionTimeout { get; set; } = 15;

    public string GetConnectionString()
    {
        return $"Server={Server},{Port};Database={Database};User Id={UserId};Password={Password};Encrypt={UseSSL};TrustServerCertificate=false;Connection Timeout={ConnectionTimeout};Command Timeout={CommandTimeout};";
    }

    public static AzureSynapseConnectionString FromConfiguration(IConfiguration configuration)
    {
        return new AzureSynapseConnectionString
        {
            Server = configuration["AzureSynapse:Server"] ?? throw new InvalidOperationException("AzureSynapse:Server is required"),
            Database = configuration["AzureSynapse:Database"] ?? throw new InvalidOperationException("AzureSynapse:Database is required"),
            UserId = configuration["AzureSynapse:UserId"] ?? throw new InvalidOperationException("AzureSynapse:UserId is required"),
            Password = configuration["AzureSynapse:Password"] ?? throw new InvalidOperationException("AzureSynapse:Password is required"),
            Port = configuration.GetValue<int>("AzureSynapse:Port", 1433),
            UseSSL = configuration.GetValue<bool>("AzureSynapse:UseSSL", true),
            CommandTimeout = configuration.GetValue<int>("AzureSynapse:CommandTimeout", 30),
            ConnectionTimeout = configuration.GetValue<int>("AzureSynapse:ConnectionTimeout", 15)
        };
    }
}
