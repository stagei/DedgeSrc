using DedgeCommon;

namespace TestAccessPoints
{
    class Program
    {
        static void Main(string[] args)
        {
            try
            {
                Console.WriteLine("Testing DedgeConnection with new object array structure and instance name support...");
                
                // Test getting all access points
                var accessPoints = DedgeConnection.AccessPoints;
                Console.WriteLine($"Loaded {accessPoints.Count} access points");
                
                // Test getting current versions
                var currentVersions = DedgeConnection.GetCurrentVersions();
                Console.WriteLine($"\nCurrent versions ({currentVersions.Count}):");
                foreach (var cv in currentVersions.Take(5)) // Show first 5
                {
                    Console.WriteLine($"  {cv.Application} {cv.Environment} v{cv.Version} - {cv.InstanceName} ({cv.Provider})");
                }
                
                // Test getting all connection strings for FKM DEV (this should work with multiple access points)
                Console.WriteLine("\n--- Testing multiple connection strings for FKM DEV ---");
                try
                {
                    var connectionStrings = DedgeConnection.GetConnectionStrings(
                        DedgeConnection.FkEnvironment.DEV, 
                        DedgeConnection.FkApplication.FKM, 
                        "2.0");
                    
                    Console.WriteLine($"Found {connectionStrings.Count} connection strings:");
                    foreach (var cs in connectionStrings)
                    {
                        Console.WriteLine($"  {cs}");
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"Error getting multiple connection strings: {ex.Message}");
                }
                
                // Test getting connection info for FKM DEV with specific instance name
                Console.WriteLine("\n--- Testing FKM DEV with specific instance name ---");
                try
                {
                    var fkmDevConnection = DedgeConnection.GetConnectionStringInfo(
                        DedgeConnection.FkEnvironment.DEV, 
                        DedgeConnection.FkApplication.FKM, 
                        "2.0",
                        "DB2FED"); // Use a specific instance name
                    
                    Console.WriteLine($"FKM DEV Connection (DB2FED):");
                    Console.WriteLine($"  Database: {fkmDevConnection.Database}");
                    Console.WriteLine($"  Server: {fkmDevConnection.Server}");
                    Console.WriteLine($"  Instance: {fkmDevConnection.InstanceName}");
                    Console.WriteLine($"  AccessPointType: {fkmDevConnection.AccessPointType}");
                    Console.WriteLine($"  IsServerActive: {fkmDevConnection.IsServerActive}");
                    Console.WriteLine($"  IsActive: {fkmDevConnection.IsActive}");
                    
                    // Test getting connection string
                    var connectionString = DedgeConnection.GetConnectionString(
                        DedgeConnection.FkEnvironment.DEV, 
                        DedgeConnection.FkApplication.FKM, 
                        "2.0",
                        "DB2FED");
                    
                    Console.WriteLine($"Connection String: {connectionString}");
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"Error getting specific instance: {ex.Message}");
                }
                
                // Test getting all connections for FKM application
                var fkmConnections = DedgeConnection.GetAllConnectionDetails(DedgeConnection.FkApplication.FKM);
                Console.WriteLine($"\nFKM Connections ({fkmConnections.Count}):");
                foreach (var conn in fkmConnections.Take(5)) // Show first 5
                {
                    Console.WriteLine($"  {conn.Description} - {conn.DatabaseName}");
                }
                
                Console.WriteLine("\nTest completed successfully!");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error: {ex.Message}");
                Console.WriteLine($"Stack Trace: {ex.StackTrace}");
            }
        }
    }
}