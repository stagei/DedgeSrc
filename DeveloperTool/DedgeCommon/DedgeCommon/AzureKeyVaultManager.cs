using Azure.Identity;
using Azure.Security.KeyVault.Secrets;
using System.Text.Json;
using System.Text;

namespace DedgeCommon
{
    /// <summary>
    /// Comprehensive Azure Key Vault management with full CRUD operations,
    /// import/export functionality, and credential management.
    /// </summary>
    /// <remarks>
    /// Features:
    /// - Full CRUD operations (Create, Read, Update, Delete)
    /// - Batch operations
    /// - Import/Export from/to JSON and CSV
    /// - Credential management (username/password pairs)
    /// - Secret versioning support
    /// - Error handling and logging
    /// - Connection string management
    /// </remarks>
    public class AzureKeyVaultManager
    {
        private readonly SecretClient _secretClient;
        private readonly string _keyVaultUri;

        /// <summary>
        /// Represents a credential pair stored in Key Vault.
        /// </summary>
        public class CredentialPair
        {
            public string Username { get; set; } = string.Empty;
            public string Password { get; set; } = string.Empty;
            public string SecretName { get; set; } = string.Empty;
            public DateTime? CreatedOn { get; set; }
            public DateTime? UpdatedOn { get; set; }
            public bool? Enabled { get; set; }
            public Dictionary<string, string> Tags { get; set; } = new Dictionary<string, string>();
        }

        /// <summary>
        /// Initializes a new instance of the AzureKeyVaultManager.
        /// </summary>
        /// <param name="keyVaultName">The name of the Key Vault (not the full URI)</param>
        /// <param name="tenantId">Optional: Azure tenant ID for authentication</param>
        /// <param name="clientId">Optional: Service principal client ID for authentication</param>
        /// <param name="clientSecret">Optional: Service principal client secret for authentication</param>
        public AzureKeyVaultManager(
            string keyVaultName, 
            string? tenantId = null, 
            string? clientId = null, 
            string? clientSecret = null)
        {
            if (string.IsNullOrWhiteSpace(keyVaultName))
            {
                throw new ArgumentException("Key Vault name cannot be null or empty", nameof(keyVaultName));
            }

            _keyVaultUri = $"https://{keyVaultName}.vault.azure.net/";

            try
            {
                // Use appropriate credential based on what's provided
                if (!string.IsNullOrEmpty(clientId) && !string.IsNullOrEmpty(clientSecret) && !string.IsNullOrEmpty(tenantId))
                {
                    // Service Principal authentication
                    var credential = new ClientSecretCredential(tenantId, clientId, clientSecret);
                    _secretClient = new SecretClient(new Uri(_keyVaultUri), credential);
                    DedgeNLog.Info($"Connected to Key Vault {keyVaultName} using service principal");
                }
                else
                {
                    // Default Azure credential (uses managed identity, Azure CLI, etc.)
                    // TODO: Requires Azure authentication to be configured on the machine
                    var credential = new DefaultAzureCredential();
                    _secretClient = new SecretClient(new Uri(_keyVaultUri), credential);
                    DedgeNLog.Info($"Connected to Key Vault {keyVaultName} using default Azure credential");
                }
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Failed to initialize Azure Key Vault client for {keyVaultName}");
                throw;
            }
        }

        #region CREATE Operations

        /// <summary>
        /// Creates or updates a secret in Key Vault.
        /// </summary>
        /// <param name="secretName">The name of the secret</param>
        /// <param name="secretValue">The value of the secret</param>
        /// <param name="tags">Optional tags for the secret</param>
        /// <returns>The created/updated secret</returns>
        public async Task<KeyVaultSecret> CreateOrUpdateSecretAsync(
            string secretName, 
            string secretValue,
            Dictionary<string, string>? tags = null)
        {
            try
            {
                ValidateSecretName(secretName);

                DedgeNLog.Debug($"Creating/updating secret: {secretName}");

                var secret = new KeyVaultSecret(secretName, secretValue);
                
                if (tags != null)
                {
                    foreach (var tag in tags)
                    {
                        secret.Properties.Tags[tag.Key] = tag.Value;
                    }
                }

                // TODO: Requires Azure Key Vault access permissions
                var response = await _secretClient.SetSecretAsync(secret);
                
                DedgeNLog.Info($"Successfully created/updated secret: {secretName}");
                return response.Value;
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Failed to create/update secret: {secretName}");
                throw;
            }
        }

        /// <summary>
        /// Creates or updates a credential pair (username and password) in Key Vault.
        /// Stores as a single secret in format: "username:password"
        /// </summary>
        /// <param name="credentialName">Base name for the credential (will be used as secret name)</param>
        /// <param name="username">The username</param>
        /// <param name="password">The password</param>
        /// <param name="tags">Optional tags</param>
        /// <returns>The created credential pair</returns>
        public async Task<CredentialPair> CreateOrUpdateCredentialAsync(
            string credentialName,
            string username,
            string password,
            Dictionary<string, string>? tags = null)
        {
            try
            {
                string secretValue = $"{username}:{password}";
                
                if (tags == null)
                {
                    tags = new Dictionary<string, string>();
                }
                tags["Type"] = "Credential";
                tags["Username"] = username;

                var secret = await CreateOrUpdateSecretAsync(credentialName, secretValue, tags);

                return new CredentialPair
                {
                    SecretName = credentialName,
                    Username = username,
                    Password = password,
                    CreatedOn = secret.Properties.CreatedOn?.DateTime,
                    UpdatedOn = secret.Properties.UpdatedOn?.DateTime,
                    Enabled = secret.Properties.Enabled,
                    Tags = tags
                };
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Failed to create/update credential: {credentialName}");
                throw;
            }
        }

        #endregion

        #region READ Operations

        /// <summary>
        /// Retrieves a secret from Key Vault.
        /// </summary>
        /// <param name="secretName">The name of the secret to retrieve</param>
        /// <returns>The secret value</returns>
        public async Task<string> GetSecretAsync(string secretName)
        {
            try
            {
                ValidateSecretName(secretName);

                DedgeNLog.Debug($"Retrieving secret: {secretName}");

                // TODO: Requires Azure Key Vault read permissions
                var response = await _secretClient.GetSecretAsync(secretName);
                
                DedgeNLog.Debug($"Successfully retrieved secret: {secretName}");
                return response.Value.Value;
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Failed to retrieve secret: {secretName}");
                throw;
            }
        }

        /// <summary>
        /// Retrieves a credential pair by secret name.
        /// </summary>
        /// <param name="credentialName">The name of the credential secret</param>
        /// <returns>The credential pair</returns>
        public async Task<CredentialPair> GetCredentialAsync(string credentialName)
        {
            try
            {
                // TODO: Requires Azure Key Vault read permissions
                var response = await _secretClient.GetSecretAsync(credentialName);
                var secret = response.Value;

                string[] parts = secret.Value.Split(':', 2);
                if (parts.Length != 2)
                {
                    throw new FormatException($"Secret {credentialName} is not in username:password format");
                }

                return new CredentialPair
                {
                    SecretName = credentialName,
                    Username = parts[0],
                    Password = parts[1],
                    CreatedOn = secret.Properties.CreatedOn?.DateTime,
                    UpdatedOn = secret.Properties.UpdatedOn?.DateTime,
                    Enabled = secret.Properties.Enabled,
                    Tags = secret.Properties.Tags.ToDictionary(kvp => kvp.Key, kvp => kvp.Value)
                };
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Failed to retrieve credential: {credentialName}");
                throw;
            }
        }

        /// <summary>
        /// Retrieves a credential pair by username.
        /// Searches through all credentials with type=Credential tag to find matching username.
        /// </summary>
        /// <param name="username">The username to search for</param>
        /// <returns>The credential pair, or null if not found</returns>
        public async Task<CredentialPair?> GetCredentialByUsernameAsync(string username)
        {
            try
            {
                DedgeNLog.Debug($"Searching for credential with username: {username}");

                // TODO: Requires Azure Key Vault list permissions
                var allSecrets = _secretClient.GetPropertiesOfSecretsAsync();

                await foreach (var secretProperties in allSecrets)
                {
                    // Check if this is a credential type secret with matching username
                    if (secretProperties.Tags.TryGetValue("Type", out string? type) && type == "Credential")
                    {
                        if (secretProperties.Tags.TryGetValue("Username", out string? tagUsername) && 
                            tagUsername.Equals(username, StringComparison.OrdinalIgnoreCase))
                        {
                            return await GetCredentialAsync(secretProperties.Name);
                        }
                    }
                }

                DedgeNLog.Warn($"Credential not found for username: {username}");
                return null;
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Failed to search for credential by username: {username}");
                throw;
            }
        }

        /// <summary>
        /// Lists all secrets in the Key Vault.
        /// </summary>
        /// <returns>List of secret names</returns>
        public async Task<List<string>> ListSecretNamesAsync()
        {
            try
            {
                var secretNames = new List<string>();

                DedgeNLog.Debug("Listing all secrets in Key Vault");

                // TODO: Requires Azure Key Vault list permissions
                var allSecrets = _secretClient.GetPropertiesOfSecretsAsync();

                await foreach (var secretProperties in allSecrets)
                {
                    secretNames.Add(secretProperties.Name);
                }

                DedgeNLog.Info($"Found {secretNames.Count} secrets in Key Vault");
                return secretNames;
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, "Failed to list secrets");
                throw;
            }
        }

        /// <summary>
        /// Lists all credentials in the Key Vault.
        /// </summary>
        /// <returns>List of credential pairs</returns>
        public async Task<List<CredentialPair>> ListCredentialsAsync()
        {
            try
            {
                var credentials = new List<CredentialPair>();

                DedgeNLog.Debug("Listing all credentials in Key Vault");

                // TODO: Requires Azure Key Vault list and read permissions
                var allSecrets = _secretClient.GetPropertiesOfSecretsAsync();

                await foreach (var secretProperties in allSecrets)
                {
                    // Only process secrets tagged as credentials
                    if (secretProperties.Tags.TryGetValue("Type", out string? type) && type == "Credential")
                    {
                        try
                        {
                            var credential = await GetCredentialAsync(secretProperties.Name);
                            credentials.Add(credential);
                        }
                        catch (Exception ex)
                        {
                            DedgeNLog.Warn($"Failed to retrieve credential {secretProperties.Name}: {ex.Message}");
                        }
                    }
                }

                DedgeNLog.Info($"Found {credentials.Count} credentials in Key Vault");
                return credentials;
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, "Failed to list credentials");
                throw;
            }
        }

        #endregion

        #region UPDATE Operations

        /// <summary>
        /// Updates an existing secret. Creates it if it doesn't exist.
        /// </summary>
        public async Task<KeyVaultSecret> UpdateSecretAsync(
            string secretName, 
            string newValue,
            Dictionary<string, string>? tags = null)
        {
            return await CreateOrUpdateSecretAsync(secretName, newValue, tags);
        }

        /// <summary>
        /// Updates the password for a credential, keeping the username unchanged.
        /// </summary>
        public async Task<CredentialPair> UpdateCredentialPasswordAsync(string credentialName, string newPassword)
        {
            try
            {
                var existing = await GetCredentialAsync(credentialName);
                return await CreateOrUpdateCredentialAsync(credentialName, existing.Username, newPassword, existing.Tags);
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Failed to update password for credential: {credentialName}");
                throw;
            }
        }

        #endregion

        #region DELETE Operations

        /// <summary>
        /// Deletes a secret from Key Vault.
        /// </summary>
        /// <param name="secretName">The name of the secret to delete</param>
        /// <param name="purge">Whether to permanently purge the secret (cannot be recovered)</param>
        /// <returns>True if successful</returns>
        public async Task<bool> DeleteSecretAsync(string secretName, bool purge = false)
        {
            try
            {
                ValidateSecretName(secretName);

                DedgeNLog.Info($"Deleting secret: {secretName} (purge: {purge})");

                // TODO: Requires Azure Key Vault delete permissions
                var deleteOperation = await _secretClient.StartDeleteSecretAsync(secretName);
                await deleteOperation.WaitForCompletionAsync();

                if (purge)
                {
                    // TODO: Requires Azure Key Vault purge permissions
                    await _secretClient.PurgeDeletedSecretAsync(secretName);
                    DedgeNLog.Info($"Successfully purged secret: {secretName}");
                }
                else
                {
                    DedgeNLog.Info($"Successfully deleted secret: {secretName} (can be recovered)");
                }

                return true;
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Failed to delete secret: {secretName}");
                return false;
            }
        }

        /// <summary>
        /// Deletes multiple secrets in batch.
        /// </summary>
        public async Task<Dictionary<string, bool>> DeleteSecretsAsync(List<string> secretNames, bool purge = false)
        {
            var results = new Dictionary<string, bool>();

            foreach (var secretName in secretNames)
            {
                results[secretName] = await DeleteSecretAsync(secretName, purge);
            }

            return results;
        }

        #endregion

        #region IMPORT Operations

        /// <summary>
        /// Imports credentials from a JSON file.
        /// Expected format: [{"SecretName": "name", "Username": "user", "Password": "pass"}, ...]
        /// </summary>
        public async Task<int> ImportFromJsonAsync(string jsonFilePath)
        {
            try
            {
                DedgeNLog.Info($"Importing credentials from JSON file: {jsonFilePath}");

                if (!File.Exists(jsonFilePath))
                {
                    throw new FileNotFoundException($"JSON file not found: {jsonFilePath}");
                }

                string jsonContent = await File.ReadAllTextAsync(jsonFilePath);
                var credentials = JsonSerializer.Deserialize<List<CredentialPair>>(jsonContent);

                if (credentials == null || !credentials.Any())
                {
                    DedgeNLog.Warn("No credentials found in JSON file");
                    return 0;
                }

                int successCount = 0;
                foreach (var cred in credentials)
                {
                    try
                    {
                        await CreateOrUpdateCredentialAsync(cred.SecretName, cred.Username, cred.Password, cred.Tags);
                        successCount++;
                    }
                    catch (Exception ex)
                    {
                        DedgeNLog.Error(ex, $"Failed to import credential: {cred.SecretName}");
                    }
                }

                DedgeNLog.Info($"Successfully imported {successCount} out of {credentials.Count} credentials from JSON");
                return successCount;
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Failed to import from JSON file: {jsonFilePath}");
                throw;
            }
        }

        /// <summary>
        /// Imports credentials from a CSV file.
        /// Expected format: SecretName,Username,Password
        /// </summary>
        public async Task<int> ImportFromCsvAsync(string csvFilePath, bool hasHeader = true)
        {
            try
            {
                DedgeNLog.Info($"Importing credentials from CSV file: {csvFilePath}");

                if (!File.Exists(csvFilePath))
                {
                    throw new FileNotFoundException($"CSV file not found: {csvFilePath}");
                }

                var lines = await File.ReadAllLinesAsync(csvFilePath);
                
                int startIndex = hasHeader ? 1 : 0;
                int successCount = 0;

                for (int i = startIndex; i < lines.Length; i++)
                {
                    var line = lines[i].Trim();
                    if (string.IsNullOrEmpty(line))
                        continue;

                    var parts = line.Split(',');
                    if (parts.Length < 3)
                    {
                        DedgeNLog.Warn($"Invalid CSV line {i + 1}: {line}");
                        continue;
                    }

                    string secretName = parts[0].Trim();
                    string username = parts[1].Trim();
                    string password = parts[2].Trim();

                    try
                    {
                        await CreateOrUpdateCredentialAsync(secretName, username, password);
                        successCount++;
                    }
                    catch (Exception ex)
                    {
                        DedgeNLog.Error(ex, $"Failed to import credential from line {i + 1}: {secretName}");
                    }
                }

                DedgeNLog.Info($"Successfully imported {successCount} out of {lines.Length - startIndex} credentials from CSV");
                return successCount;
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Failed to import from CSV file: {csvFilePath}");
                throw;
            }
        }

        #endregion

        #region EXPORT Operations

        /// <summary>
        /// Exports all credentials to a JSON file.
        /// WARNING: Exports passwords in plain text!
        /// </summary>
        public async Task<int> ExportToJsonAsync(string jsonFilePath, bool includePasswords = false)
        {
            try
            {
                DedgeNLog.Info($"Exporting credentials to JSON file: {jsonFilePath} (includePasswords: {includePasswords})");

                var credentials = await ListCredentialsAsync();

                if (!includePasswords)
                {
                    // Redact passwords
                    credentials.ForEach(c => c.Password = "***REDACTED***");
                }

                var options = new JsonSerializerOptions
                {
                    WriteIndented = true
                };

                string jsonContent = JsonSerializer.Serialize(credentials, options);
                await File.WriteAllTextAsync(jsonFilePath, jsonContent);

                DedgeNLog.Info($"Successfully exported {credentials.Count} credentials to JSON");
                return credentials.Count;
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Failed to export to JSON file: {jsonFilePath}");
                throw;
            }
        }

        /// <summary>
        /// Exports all credentials to a CSV file.
        /// WARNING: Exports passwords in plain text if includePasswords is true!
        /// </summary>
        public async Task<int> ExportToCsvAsync(string csvFilePath, bool includePasswords = false)
        {
            try
            {
                DedgeNLog.Info($"Exporting credentials to CSV file: {csvFilePath} (includePasswords: {includePasswords})");

                var credentials = await ListCredentialsAsync();

                var sb = new StringBuilder();
                sb.AppendLine("SecretName,Username,Password,CreatedOn,UpdatedOn,Enabled");

                foreach (var cred in credentials)
                {
                    string password = includePasswords ? cred.Password : "***REDACTED***";
                    sb.AppendLine($"{cred.SecretName},{cred.Username},{password},{cred.CreatedOn},{cred.UpdatedOn},{cred.Enabled}");
                }

                await File.WriteAllTextAsync(csvFilePath, sb.ToString());

                DedgeNLog.Info($"Successfully exported {credentials.Count} credentials to CSV");
                return credentials.Count;
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Failed to export to CSV file: {csvFilePath}");
                throw;
            }
        }

        #endregion

        #region UTILITY Operations

        /// <summary>
        /// Tests the connection to Key Vault.
        /// </summary>
        /// <returns>True if connection successful</returns>
        public async Task<bool> TestConnectionAsync()
        {
            try
            {
                DedgeNLog.Debug("Testing Key Vault connection");

                // TODO: Requires Azure Key Vault read permissions
                // Try to get properties of secrets (doesn't retrieve values)
                var secrets = _secretClient.GetPropertiesOfSecretsAsync();
                await foreach (var secret in secrets)
                {
                    // Just enumerate one to test connection
                    break;
                }

                DedgeNLog.Info("Key Vault connection test successful");
                return true;
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, "Key Vault connection test failed");
                return false;
            }
        }

        /// <summary>
        /// Validates a secret name according to Azure Key Vault naming rules.
        /// </summary>
        private void ValidateSecretName(string secretName)
        {
            if (string.IsNullOrWhiteSpace(secretName))
            {
                throw new ArgumentException("Secret name cannot be null or empty", nameof(secretName));
            }

            // Azure Key Vault secret names: 1-127 characters, alphanumeric and hyphens only
            if (secretName.Length > 127)
            {
                throw new ArgumentException($"Secret name cannot exceed 127 characters: {secretName}", nameof(secretName));
            }

            if (!System.Text.RegularExpressions.Regex.IsMatch(secretName, @"^[a-zA-Z0-9-]+$"))
            {
                throw new ArgumentException(
                    $"Secret name can only contain alphanumeric characters and hyphens: {secretName}",
                    nameof(secretName));
            }
        }

        /// <summary>
        /// Gets the Key Vault URI being used.
        /// </summary>
        public string GetKeyVaultUri() => _keyVaultUri;

        #endregion

        #region BATCH Operations

        /// <summary>
        /// Creates or updates multiple secrets in batch.
        /// </summary>
        public async Task<Dictionary<string, bool>> BatchCreateOrUpdateSecretsAsync(
            Dictionary<string, string> secrets,
            Dictionary<string, string>? tags = null)
        {
            var results = new Dictionary<string, bool>();

            foreach (var secret in secrets)
            {
                try
                {
                    await CreateOrUpdateSecretAsync(secret.Key, secret.Value, tags);
                    results[secret.Key] = true;
                }
                catch
                {
                    results[secret.Key] = false;
                }
            }

            int successCount = results.Values.Count(v => v);
            DedgeNLog.Info($"Batch operation completed: {successCount}/{secrets.Count} secrets created/updated successfully");

            return results;
        }

        /// <summary>
        /// Creates or updates multiple credentials in batch.
        /// </summary>
        public async Task<Dictionary<string, bool>> BatchCreateOrUpdateCredentialsAsync(
            List<CredentialPair> credentials)
        {
            var results = new Dictionary<string, bool>();

            foreach (var cred in credentials)
            {
                try
                {
                    await CreateOrUpdateCredentialAsync(cred.SecretName, cred.Username, cred.Password, cred.Tags);
                    results[cred.SecretName] = true;
                }
                catch
                {
                    results[cred.SecretName] = false;
                }
            }

            int successCount = results.Values.Count(v => v);
            DedgeNLog.Info($"Batch operation completed: {successCount}/{credentials.Count} credentials created/updated successfully");

            return results;
        }

        #endregion
    }
}
