using Azure.Identity;
using Azure.Security.KeyVault.Secrets;
using NLog;

namespace DedgeCommon
{
    /// <summary>
    /// Provides secure database credential management using Azure Key Vault.
    /// This class handles the retrieval and storage of sensitive connection information
    /// while maintaining security best practices.
    /// </summary>
    /// <remarks>
    /// Features:
    /// - Secure credential storage in Azure Key Vault
    /// - Automatic credential rotation support
    /// - Environment-specific secret management
    /// - Integration with Azure managed identities
    /// - Credential validation and verification
    /// - Fallback mechanisms for credential retrieval
    /// </remarks>
    /// <author>Geir Helge Starholm</author>
    internal static class DedgeConnectionAzureKeyVault
    {
        private static SecretClient _secretClient;
        private static readonly string KeyVaultUri = Environment.GetEnvironmentVariable("FK_KEYVAULT_URI")
            ?? "https://fk-keyvault.vault.azure.net/";

        static DedgeConnectionAzureKeyVault()
        {
            try
            {
                // Initialize Azure Key Vault client
                var credential = new DefaultAzureCredential();
                _secretClient = new SecretClient(new Uri(KeyVaultUri), credential);
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Failed to initialize Azure Key Vault client");
                throw;
            }
        }

        /// <summary>
        /// Gets a database credential from Azure Key Vault
        /// </summary>
        private static async Task<(string username, string password)> GetDatabaseCredentialsAsync(
            DedgeConnection.ConnectionKey key)
        {
            try
            {
                string secretName = $"db-{key.Application}-{key.Environment}-{key.Version}"
                    .Replace(".", "-")
                    .ToLower();

                var secret = await _secretClient.GetSecretAsync(secretName);
                var credentials = secret.Value.Value.Split(':');

                if (credentials.Length != 2)
                {
                    throw new FormatException($"Invalid credential format in Key Vault for {secretName}");
                }

                return (credentials[0], credentials[1]);
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Failed to get credentials for {key.Application}-{key.Environment}");
                throw;
            }
        }

        /// <summary>
        /// Generates a connection string with credentials from Azure Key Vault
        /// </summary>
        public static async Task<string> GetConnectionStringAsync(
            DedgeConnection.FkEnvironment environment,
            DedgeConnection.FkApplication application = DedgeConnection.FkApplication.FKM,
            string version = "2.0")
        {
            try
            {
                var key = new DedgeConnection.ConnectionKey(application, environment, version);
                var accessPoint = DedgeConnection.GetConnectionStringInfo(key);
                var credentials = await GetDatabaseCredentialsAsync(key);

                // Use GenerateConnectionString with credential overrides from Azure Key Vault
                return DedgeConnection.GenerateConnectionString(accessPoint, credentials.username, credentials.password);
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Failed to generate connection string");
                throw;
            }
        }

        /// <summary>
        /// Updates database credentials in Azure Key Vault
        /// </summary>
        public static async Task UpdateDatabaseCredentialsAsync(
            DedgeConnection.ConnectionKey key,
            string username,
            string password)
        {
            try
            {
                string secretName = $"db-{key.Application}-{key.Environment}-{key.Version}"
                    .Replace(".", "-")
                    .ToLower();

                string secretValue = $"{username}:{password}";
                await _secretClient.SetSecretAsync(secretName, secretValue);

                DedgeNLog.Info($"Updated credentials for {key.Application}-{key.Environment}");
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Failed to update credentials for {key.Application}-{key.Environment}");
                throw;
            }
        }

        /// <summary>
        /// Validates that all required credentials exist in Azure Key Vault
        /// </summary>
        public static async Task ValidateCredentialsAsync()
        {
            var missingCredentials = new List<string>();

            foreach (var accessPoint in DedgeConnection.AccessPoints)
            {
                try
                {
                    string secretName = $"db-{accessPoint.ApplicationEnum}-{accessPoint.EnvironmentEnum}-{accessPoint.Version}"
                        .Replace(".", "-")
                        .ToLower();

                    var secret = await _secretClient.GetSecretAsync(secretName);
                    if (string.IsNullOrEmpty(secret.Value.Value))
                    {
                        missingCredentials.Add(secretName);
                    }
                }
                catch
                {
                    missingCredentials.Add($"{accessPoint.ApplicationEnum}-{accessPoint.EnvironmentEnum}-{accessPoint.Version}");
                }
            }

            if (missingCredentials.Any())
            {
                throw new InvalidOperationException(
                    $"Missing credentials in Key Vault for: {string.Join(", ", missingCredentials)}");
            }
        }

        /// <summary>
        /// Gets a database handler with credentials from Azure Key Vault
        /// </summary>
        public static async Task<IDbHandler> CreateDatabaseHandlerAsync(
            DedgeConnection.ConnectionKey key,
            Logger? logger = null)
        {
            try
            {
                var connectionString = await GetConnectionStringAsync(
                    key.Environment,
                    key.Application,
                    key.Version);

                var accessPoint = DedgeConnection.GetConnectionStringInfo(key);

                return accessPoint.ProviderEnum switch
                {
                    DedgeConnection.DatabaseProvider.DB2 => new Db2Handler(key) { ConnectionString = connectionString },
                    DedgeConnection.DatabaseProvider.SQLSERVER => new SqlServerHandler(key) { ConnectionString = connectionString },
                    _ => throw new ArgumentException($"Unsupported database provider: {accessPoint.ProviderEnum}")
                };
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Failed to create database handler");
                throw;
            }
        }
    }
}