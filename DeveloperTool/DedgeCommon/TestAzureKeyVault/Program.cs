using DedgeCommon;
using System.Text.Json;

namespace TestAzureKeyVault
{
    /// <summary>
    /// Test program for Azure Key Vault functionality.
    /// Tests CRUD operations, import/export, and credential management.
    /// </summary>
    internal class Program
    {
        private class AppSettings
        {
            public AzureKeyVaultConfig AzureKeyVault { get; set; } = new();
            public TestConfig TestSettings { get; set; } = new();
        }

        private class AzureKeyVaultConfig
        {
            public string KeyVaultName { get; set; } = string.Empty;
            public string TenantId { get; set; } = string.Empty;
            public string ClientId { get; set; } = string.Empty;
            public string ClientSecret { get; set; } = string.Empty;
            public bool UseManagedIdentity { get; set; }
        }

        private class TestConfig
        {
            public string TestSecretName { get; set; } = "test-secret";
            public string TestUsername { get; set; } = "test-user";
            public string TestPassword { get; set; } = "test-password";
            public string ImportJsonPath { get; set; } = "test-import.json";
            public string ImportCsvPath { get; set; } = "test-import.csv";
            public string ExportJsonPath { get; set; } = "test-export.json";
            public string ExportCsvPath { get; set; } = "test-export.csv";
        }

        static async Task Main(string[] args)
        {
            Console.WriteLine("=== Azure Key Vault Manager Test ===\n");

            try
            {
                // Load configuration
                var settings = LoadSettings();

                if (string.IsNullOrEmpty(settings.AzureKeyVault.KeyVaultName) || 
                    settings.AzureKeyVault.KeyVaultName == "your-keyvault-name")
                {
                    Console.WriteLine("ERROR: Please configure appsettings.json with your Azure Key Vault details");
                    Console.WriteLine("\nRequired settings:");
                    Console.WriteLine("  - KeyVaultName: Your Azure Key Vault name");
                    Console.WriteLine("  - TenantId: Your Azure tenant ID");
                    Console.WriteLine("  - ClientId: Your service principal client ID");
                    Console.WriteLine("  - ClientSecret: Your service principal secret or PAT");
                    Console.WriteLine("\nAlternatively, set UseManagedIdentity to true if running on Azure");
                    Environment.Exit(1);
                }

                // Initialize Key Vault Manager
                AzureKeyVaultManager kvManager;
                
                if (settings.AzureKeyVault.UseManagedIdentity)
                {
                    Console.WriteLine("Using Managed Identity for authentication");
                    kvManager = new AzureKeyVaultManager(settings.AzureKeyVault.KeyVaultName);
                }
                else
                {
                    Console.WriteLine("Using Service Principal for authentication");
                    kvManager = new AzureKeyVaultManager(
                        settings.AzureKeyVault.KeyVaultName,
                        settings.AzureKeyVault.TenantId,
                        settings.AzureKeyVault.ClientId,
                        settings.AzureKeyVault.ClientSecret);
                }

                Console.WriteLine($"Key Vault URI: {kvManager.GetKeyVaultUri()}\n");

                // Test connection
                Console.WriteLine("Testing Key Vault connection...");
                bool connected = await kvManager.TestConnectionAsync();
                if (!connected)
                {
                    Console.WriteLine("✗ Failed to connect to Key Vault");
                    Environment.Exit(1);
                }
                Console.WriteLine("✓ Successfully connected to Key Vault\n");

                // Run test suite
                await RunTestSuite(kvManager, settings.TestSettings);

                Console.WriteLine("\n=== All tests completed successfully! ===");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"\n✗ ERROR: {ex.Message}");
                Console.WriteLine($"Stack Trace:\n{ex.StackTrace}");
                Environment.Exit(1);
            }
        }

        private static async Task RunTestSuite(AzureKeyVaultManager kvManager, TestConfig testSettings)
        {
            Console.WriteLine("=== Running Test Suite ===\n");

            // Test 1: Create Secret
            await TestCreateSecret(kvManager, testSettings);

            // Test 2: Read Secret
            await TestReadSecret(kvManager, testSettings);

            // Test 3: Create Credential
            await TestCreateCredential(kvManager, testSettings);

            // Test 4: Read Credential
            await TestReadCredential(kvManager, testSettings);

            // Test 5: Search Credential by Username
            await TestSearchCredentialByUsername(kvManager, testSettings);

            // Test 6: List All Secrets
            await TestListSecrets(kvManager);

            // Test 7: List All Credentials
            await TestListCredentials(kvManager);

            // Test 8: Export to JSON
            await TestExportJson(kvManager, testSettings);

            // Test 9: Export to CSV
            await TestExportCsv(kvManager, testSettings);

            // Test 10: Import from JSON
            await TestImportJson(kvManager, testSettings);

            // Test 11: Import from CSV
            await TestImportCsv(kvManager, testSettings);

            // Test 12: Update Secret
            await TestUpdateSecret(kvManager, testSettings);

            // Test 13: Update Credential Password
            await TestUpdateCredentialPassword(kvManager, testSettings);

            // Test 14: Batch Create Secrets
            await TestBatchCreateSecrets(kvManager);

            // Test 15: Delete Secret
            await TestDeleteSecret(kvManager, testSettings);
        }

        private static async Task TestCreateSecret(AzureKeyVaultManager kvManager, TestConfig settings)
        {
            Console.WriteLine("Test 1: Creating secret...");
            try
            {
                await kvManager.CreateOrUpdateSecretAsync(settings.TestSecretName, "test-value-123");
                Console.WriteLine($"  ✓ Secret '{settings.TestSecretName}' created successfully\n");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"  ✗ Failed: {ex.Message}\n");
                throw;
            }
        }

        private static async Task TestReadSecret(AzureKeyVaultManager kvManager, TestConfig settings)
        {
            Console.WriteLine("Test 2: Reading secret...");
            try
            {
                string value = await kvManager.GetSecretAsync(settings.TestSecretName);
                Console.WriteLine($"  ✓ Retrieved secret value: {value}\n");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"  ✗ Failed: {ex.Message}\n");
                throw;
            }
        }

        private static async Task TestCreateCredential(AzureKeyVaultManager kvManager, TestConfig settings)
        {
            Console.WriteLine("Test 3: Creating credential...");
            try
            {
                await kvManager.CreateOrUpdateCredentialAsync(
                    "test-credential",
                    settings.TestUsername,
                    settings.TestPassword);
                Console.WriteLine($"  ✓ Credential 'test-credential' created successfully\n");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"  ✗ Failed: {ex.Message}\n");
                throw;
            }
        }

        private static async Task TestReadCredential(AzureKeyVaultManager kvManager, TestConfig settings)
        {
            Console.WriteLine("Test 4: Reading credential...");
            try
            {
                var cred = await kvManager.GetCredentialAsync("test-credential");
                Console.WriteLine($"  ✓ Username: {cred.Username}, Password: {cred.Password}\n");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"  ✗ Failed: {ex.Message}\n");
                throw;
            }
        }

        private static async Task TestSearchCredentialByUsername(AzureKeyVaultManager kvManager, TestConfig settings)
        {
            Console.WriteLine("Test 5: Searching credential by username...");
            try
            {
                var cred = await kvManager.GetCredentialByUsernameAsync(settings.TestUsername);
                if (cred != null)
                {
                    Console.WriteLine($"  ✓ Found credential: {cred.SecretName} for user {cred.Username}\n");
                }
                else
                {
                    Console.WriteLine($"  ⚠ No credential found for username: {settings.TestUsername}\n");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"  ✗ Failed: {ex.Message}\n");
                throw;
            }
        }

        private static async Task TestListSecrets(AzureKeyVaultManager kvManager)
        {
            Console.WriteLine("Test 6: Listing all secrets...");
            try
            {
                var secrets = await kvManager.ListSecretNamesAsync();
                Console.WriteLine($"  ✓ Found {secrets.Count} secrets:");
                foreach (var secret in secrets.Take(5))
                {
                    Console.WriteLine($"    - {secret}");
                }
                if (secrets.Count > 5)
                {
                    Console.WriteLine($"    ... and {secrets.Count - 5} more\n");
                }
                else
                {
                    Console.WriteLine();
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"  ✗ Failed: {ex.Message}\n");
                throw;
            }
        }

        private static async Task TestListCredentials(AzureKeyVaultManager kvManager)
        {
            Console.WriteLine("Test 7: Listing all credentials...");
            try
            {
                var credentials = await kvManager.ListCredentialsAsync();
                Console.WriteLine($"  ✓ Found {credentials.Count} credentials:");
                foreach (var cred in credentials.Take(5))
                {
                    Console.WriteLine($"    - {cred.SecretName}: {cred.Username}");
                }
                if (credentials.Count > 5)
                {
                    Console.WriteLine($"    ... and {credentials.Count - 5} more\n");
                }
                else
                {
                    Console.WriteLine();
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"  ✗ Failed: {ex.Message}\n");
                throw;
            }
        }

        private static async Task TestExportJson(AzureKeyVaultManager kvManager, TestConfig settings)
        {
            Console.WriteLine("Test 8: Exporting to JSON...");
            try
            {
                int count = await kvManager.ExportToJsonAsync(settings.ExportJsonPath, includePasswords: false);
                Console.WriteLine($"  ✓ Exported {count} credentials to {settings.ExportJsonPath} (passwords redacted)\n");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"  ✗ Failed: {ex.Message}\n");
                throw;
            }
        }

        private static async Task TestExportCsv(AzureKeyVaultManager kvManager, TestConfig settings)
        {
            Console.WriteLine("Test 9: Exporting to CSV...");
            try
            {
                int count = await kvManager.ExportToCsvAsync(settings.ExportCsvPath, includePasswords: false);
                Console.WriteLine($"  ✓ Exported {count} credentials to {settings.ExportCsvPath} (passwords redacted)\n");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"  ✗ Failed: {ex.Message}\n");
                throw;
            }
        }

        private static async Task TestImportJson(AzureKeyVaultManager kvManager, TestConfig settings)
        {
            Console.WriteLine("Test 10: Importing from JSON...");
            try
            {
                // Create test import file
                var testData = new[]
                {
                    new AzureKeyVaultManager.CredentialPair
                    {
                        SecretName = "import-test-json-1",
                        Username = "json-user-1",
                        Password = "json-pass-1"
                    },
                    new AzureKeyVaultManager.CredentialPair
                    {
                        SecretName = "import-test-json-2",
                        Username = "json-user-2",
                        Password = "json-pass-2"
                    }
                };

                var jsonOptions = new JsonSerializerOptions { WriteIndented = true };
                string jsonContent = JsonSerializer.Serialize(testData, jsonOptions);
                await File.WriteAllTextAsync(settings.ImportJsonPath, jsonContent);

                int count = await kvManager.ImportFromJsonAsync(settings.ImportJsonPath);
                Console.WriteLine($"  ✓ Imported {count} credentials from JSON\n");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"  ✗ Failed: {ex.Message}\n");
                throw;
            }
        }

        private static async Task TestImportCsv(AzureKeyVaultManager kvManager, TestConfig settings)
        {
            Console.WriteLine("Test 11: Importing from CSV...");
            try
            {
                // Create test import file
                var csvContent = "SecretName,Username,Password\n" +
                                "import-test-csv-1,csv-user-1,csv-pass-1\n" +
                                "import-test-csv-2,csv-user-2,csv-pass-2\n";
                await File.WriteAllTextAsync(settings.ImportCsvPath, csvContent);

                int count = await kvManager.ImportFromCsvAsync(settings.ImportCsvPath, hasHeader: true);
                Console.WriteLine($"  ✓ Imported {count} credentials from CSV\n");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"  ✗ Failed: {ex.Message}\n");
                throw;
            }
        }

        private static async Task TestUpdateSecret(AzureKeyVaultManager kvManager, TestConfig settings)
        {
            Console.WriteLine("Test 12: Updating secret...");
            try
            {
                await kvManager.UpdateSecretAsync(settings.TestSecretName, "updated-value-456");
                string newValue = await kvManager.GetSecretAsync(settings.TestSecretName);
                Console.WriteLine($"  ✓ Secret updated, new value: {newValue}\n");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"  ✗ Failed: {ex.Message}\n");
                throw;
            }
        }

        private static async Task TestUpdateCredentialPassword(AzureKeyVaultManager kvManager, TestConfig settings)
        {
            Console.WriteLine("Test 13: Updating credential password...");
            try
            {
                await kvManager.UpdateCredentialPasswordAsync("test-credential", "new-password-789");
                var cred = await kvManager.GetCredentialAsync("test-credential");
                Console.WriteLine($"  ✓ Credential password updated for user: {cred.Username}\n");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"  ✗ Failed: {ex.Message}\n");
                throw;
            }
        }

        private static async Task TestBatchCreateSecrets(AzureKeyVaultManager kvManager)
        {
            Console.WriteLine("Test 14: Batch creating secrets...");
            try
            {
                var secrets = new Dictionary<string, string>
                {
                    { "batch-test-1", "value1" },
                    { "batch-test-2", "value2" },
                    { "batch-test-3", "value3" }
                };

                var results = await kvManager.BatchCreateOrUpdateSecretsAsync(secrets);
                int successCount = results.Values.Count(v => v);
                Console.WriteLine($"  ✓ Batch created {successCount}/{secrets.Count} secrets\n");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"  ✗ Failed: {ex.Message}\n");
                throw;
            }
        }

        private static async Task TestDeleteSecret(AzureKeyVaultManager kvManager, TestConfig settings)
        {
            Console.WriteLine("Test 15: Deleting test secrets...");
            try
            {
                // Delete test secrets (don't purge, so they can be recovered)
                await kvManager.DeleteSecretAsync(settings.TestSecretName, purge: false);
                await kvManager.DeleteSecretAsync("test-credential", purge: false);
                await kvManager.DeleteSecretAsync("import-test-json-1", purge: false);
                await kvManager.DeleteSecretAsync("import-test-json-2", purge: false);
                await kvManager.DeleteSecretAsync("import-test-csv-1", purge: false);
                await kvManager.DeleteSecretAsync("import-test-csv-2", purge: false);
                await kvManager.DeleteSecretAsync("batch-test-1", purge: false);
                await kvManager.DeleteSecretAsync("batch-test-2", purge: false);
                await kvManager.DeleteSecretAsync("batch-test-3", purge: false);

                Console.WriteLine("  ✓ Test secrets deleted (can be recovered from soft-delete)\n");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"  ⚠ Some deletions failed: {ex.Message}\n");
            }
        }

        private static AppSettings LoadSettings()
        {
            try
            {
                string settingsPath = "appsettings.json";
                if (!File.Exists(settingsPath))
                {
                    Console.WriteLine($"ERROR: appsettings.json not found in current directory");
                    Console.WriteLine($"Current directory: {Directory.GetCurrentDirectory()}");
                    Environment.Exit(1);
                }

                string jsonContent = File.ReadAllText(settingsPath);
                var settings = JsonSerializer.Deserialize<AppSettings>(jsonContent);

                if (settings == null)
                {
                    throw new Exception("Failed to deserialize appsettings.json");
                }

                return settings;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"ERROR loading settings: {ex.Message}");
                Environment.Exit(1);
                return null!;
            }
        }
    }
}
