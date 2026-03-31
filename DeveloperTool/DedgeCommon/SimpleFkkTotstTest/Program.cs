using IBM.Data.Db2;
using System.Data;
using System.Text.Json;
using System.Diagnostics;

namespace SimpleFkkTotstTest
{
    internal class Program
    {
        static void Main(string[] args)
        {
            string outputFile = Path.Combine(Path.GetTempPath(), $"db2_test_result_{DateTime.Now:yyyyMMdd_HHmmss}.txt");
            
            try
            {
                Console.WriteLine("=== DB2 Connection Test ===\n");
                
                // Load DatabasesV2.json
                string jsonPath = @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\DatabasesV2.json";
                Console.WriteLine($"Loading configuration from: {jsonPath}");
                
                string jsonContent = File.ReadAllText(jsonPath);
                var databases = JsonSerializer.Deserialize<List<DatabaseConfig>>(jsonContent);
                
                // Find FKMTST database
                var fkmtstDb = databases?.FirstOrDefault(d => d.Database == "FKMTST");
                if (fkmtstDb == null)
                {
                    throw new Exception("FKMTST database not found in configuration");
                }
                
                Console.WriteLine($"\nFound Database: {fkmtstDb.Database}");
                Console.WriteLine($"  Provider: {fkmtstDb.Provider}");
                Console.WriteLine($"  PrimaryCatalogName: {fkmtstDb.PrimaryCatalogName}");
                Console.WriteLine($"  Environment: {fkmtstDb.Environment}");
                Console.WriteLine($"  IsActive: {fkmtstDb.IsActive}");
                
                // Get the Alias access point
                var aliasAccessPoint = fkmtstDb.AccessPoints?
                    .FirstOrDefault(ap => ap.CatalogName == fkmtstDb.PrimaryCatalogName && 
                                         ap.AccessPointType == "Alias" && 
                                         ap.IsActive);
                
                if (aliasAccessPoint == null)
                {
                    throw new Exception($"No active Alias access point found for PrimaryCatalogName: {fkmtstDb.PrimaryCatalogName}");
                }
                
                Console.WriteLine($"\nFound Alias Access Point:");
                Console.WriteLine($"  CatalogName: {aliasAccessPoint.CatalogName}");
                Console.WriteLine($"  Server: {fkmtstDb.ServerName}:{aliasAccessPoint.Port}");
                Console.WriteLine($"  AuthenticationType: {aliasAccessPoint.AuthenticationType}");
                
                // Build connection string
                string connectionString;
                if (aliasAccessPoint.AuthenticationType?.Equals("Kerberos", StringComparison.OrdinalIgnoreCase) == true)
                {
                    // For Kerberos in DB2, we need Authentication=Kerberos parameter
                    connectionString = $"Database={aliasAccessPoint.CatalogName};Server={fkmtstDb.ServerName}:{aliasAccessPoint.Port};Authentication=Kerberos;";
                    Console.WriteLine($"\nUsing Kerberos/SSO authentication");
                }
                else
                {
                    connectionString = $"Database={aliasAccessPoint.CatalogName};Server={fkmtstDb.ServerName}:{aliasAccessPoint.Port};UID={aliasAccessPoint.UID};PWD={aliasAccessPoint.PWD};";
                    Console.WriteLine($"\nUsing UID/PWD authentication");
                }
                
                Console.WriteLine($"Connection String: {connectionString.Replace($"PWD={aliasAccessPoint.PWD}", "PWD=***")}");
                
                // Test connection
                Console.WriteLine("\nOpening DB2 connection...");
                using var connection = new DB2Connection(connectionString);
                connection.Open();
                Console.WriteLine("✓ Connection opened successfully!");
                
                // Execute test query
                string sql = "SELECT TABNAME FROM SYSCAT.TABLES FETCH FIRST 10 ROWS ONLY";
                Console.WriteLine($"\nExecuting query: {sql}");
                
                using var command = new DB2Command(sql, connection);
                using var adapter = new DB2DataAdapter(command);
                var dataTable = new DataTable();
                adapter.Fill(dataTable);
                
                Console.WriteLine($"✓ Query returned {dataTable.Rows.Count} rows\n");
                
                // Write results to file
                using (var writer = new StreamWriter(outputFile))
                {
                    writer.WriteLine("=== DB2 Connection Test Results ===");
                    writer.WriteLine($"Date: {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
                    writer.WriteLine($"Database: {fkmtstDb.Database}");
                    writer.WriteLine($"CatalogName: {aliasAccessPoint.CatalogName}");
                    writer.WriteLine($"Server: {fkmtstDb.ServerName}:{aliasAccessPoint.Port}");
                    writer.WriteLine($"Authentication: {aliasAccessPoint.AuthenticationType}");
                    writer.WriteLine($"\nQuery: {sql}");
                    writer.WriteLine($"Rows returned: {dataTable.Rows.Count}\n");
                    writer.WriteLine("Results:");
                    writer.WriteLine("========================================");
                    
                    foreach (DataRow row in dataTable.Rows)
                    {
                        writer.WriteLine(row["TABNAME"]);
                    }
                }
                
                Console.WriteLine("Results written to:");
                Console.WriteLine(outputFile);
                
                // Display results
                Console.WriteLine("\nTable Names:");
                Console.WriteLine("========================================");
                foreach (DataRow row in dataTable.Rows)
                {
                    Console.WriteLine(row["TABNAME"]);
                }
                
                Console.WriteLine("\n✓ TEST SUCCESSFUL!");
                Console.WriteLine("\nOpening result file in Cursor...");
                
                // Open in Cursor
                Process.Start(new ProcessStartInfo
                {
                    FileName = "cursor",
                    Arguments = $"\"{outputFile}\"",
                    UseShellExecute = true
                });
                
            }
            catch (Exception ex)
            {
                Console.WriteLine($"\n✗ ERROR: {ex.Message}");
                Console.WriteLine($"\nStack Trace:\n{ex.StackTrace}");
                
                // Write error to file too
                File.WriteAllText(outputFile, $"ERROR: {ex.Message}\n\nStack Trace:\n{ex.StackTrace}");
                Console.WriteLine($"\nError details written to: {outputFile}");
                
                Environment.Exit(1);
            }
        }
    }
    
    // Simple classes to deserialize JSON
    public class DatabaseConfig
    {
        public string Database { get; set; } = "";
        public string Provider { get; set; } = "";
        public string Application { get; set; } = "";
        public string Environment { get; set; } = "";
        public string Version { get; set; } = "";
        public string PrimaryCatalogName { get; set; } = "";
        public bool IsActive { get; set; }
        public string ServerName { get; set; } = "";
        public string Description { get; set; } = "";
        public string NorwegianDescription { get; set; } = "";
        public List<AccessPoint>? AccessPoints { get; set; }
    }
    
    public class AccessPoint
    {
        public string InstanceName { get; set; } = "";
        public string CatalogName { get; set; } = "";
        public string AccessPointType { get; set; } = "";
        public string Port { get; set; } = "";
        public string ServiceName { get; set; } = "";
        public string NodeName { get; set; } = "";
        public string AuthenticationType { get; set; } = "";
        public string UID { get; set; } = "";
        public string PWD { get; set; } = "";
        public bool IsActive { get; set; }
    }
}

