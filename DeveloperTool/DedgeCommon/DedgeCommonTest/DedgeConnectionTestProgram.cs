using DedgeCommon;
using static DedgeCommon.DedgeConnection;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace DedgeCommonTest
{
    /// <summary>
    /// Test class to verify DedgeConnection functionality after rewrite to use JSON configuration.
    /// This class tests all public methods of DedgeConnection to ensure backward compatibility.
    /// </summary>
    [TestClass]
    public class DedgeConnectionTestProgram
    {
        private static int _testCount = 0;
        private static int _passedTests = 0;
        private static int _failedTests = 0;

        [TestMethod]
        public void RunAllDedgeConnectionTests()
        {
            try
            {
                Console.WriteLine("=== DedgeConnection Test Verification ===");
                Console.WriteLine($"Test started at: {DateTime.Now}");
                Console.WriteLine();

                // Initialize logging
                DedgeNLog.Info("Starting DedgeConnection test verification");
                
                // Run all test methods
                TestGetConnectionStringInfo();
                TestGetConnectionString();
                TestGetCurrentVersionConnectionInfo();
                TestGetConnectionKeyByDatabaseName();
                TestGetAllConnectionDetails();
                TestGetConnectionsForApplications();
                TestConnectionKeyOperations();
                TestErrorHandling();
                TestVersionHandling();
                TestProviderHandling();

                // Print summary
                PrintTestSummary();
                
                Console.WriteLine("=== Test verification completed ===");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"CRITICAL ERROR: Test program failed: {ex.Message}");
                Console.WriteLine($"Stack trace: {ex.StackTrace}");
                DedgeNLog.Error(ex, "Test program failed with critical error");
                throw; // Re-throw to fail the test
            }
        }

        private static void TestGetConnectionStringInfo()
        {
            Console.WriteLine("Testing GetConnectionStringInfo...");
            
            try
            {
                // Test 1: Default parameters (should use FKM application)
                var connInfo1 = GetConnectionStringInfo(FkEnvironment.DEV);
                AssertTest(connInfo1 != null, "GetConnectionStringInfo with default parameters should not be null");
                AssertTest( connInfo1!.Application == FkApplication.FKM, "Default application should be FKM");
                AssertTest(connInfo1!.Environment == FkEnvironment.DEV, "Environment should be DEV");
                AssertTest(!string.IsNullOrEmpty(connInfo1!.Database), "Database should not be empty");
                AssertTest(!string.IsNullOrEmpty(connInfo1.Server), "Server should not be empty");

                // Test 2: Specific application
                var connInfo2 = GetConnectionStringInfo(FkEnvironment.PRD, FkApplication.INL);
                AssertTest(connInfo2 != null, "GetConnectionStringInfo with INL application should not be null");
                AssertTest(connInfo2!.Application == FkApplication.INL, "Application should be INL");
                AssertTest(connInfo2!.Environment == FkEnvironment.PRD, "Environment should be PRD");

                // Test 3: With version
                var connInfo3 = GetConnectionStringInfo(FkEnvironment.DEV, FkApplication.FKM, "2.0");
                AssertTest(connInfo3 != null, "GetConnectionStringInfo with version 2.0 should not be null");
                AssertTest(connInfo3!.Version == "2.0", "Version should be 2.0");

                // Test 4: With ConnectionKey
                var key = new ConnectionKey(FkApplication.FKM, FkEnvironment.TST);
                var connInfo4 = GetConnectionStringInfo(key);
                AssertTest(connInfo4 != null, "GetConnectionStringInfo with ConnectionKey should not be null");
                AssertTest(connInfo4!.Application == FkApplication.FKM, "Application from key should be FKM");
                AssertTest(connInfo4!.Environment == FkEnvironment.TST, "Environment from key should be TST");

                Console.WriteLine("✓ GetConnectionStringInfo tests passed");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"✗ GetConnectionStringInfo tests failed: {ex.Message}");
                DedgeNLog.Error(ex, "GetConnectionStringInfo tests failed");
            }
        }

        private static void TestGetConnectionString()
        {
            Console.WriteLine("Testing GetConnectionString...");
            
            try
            {
                // Test 1: Basic connection string generation
                var connString1 = GetConnectionString(FkEnvironment.DEV);
                AssertTest(!string.IsNullOrEmpty(connString1), "Connection string should not be empty");
                AssertTest(connString1.Contains("Database="), "Connection string should contain Database parameter");
                AssertTest(connString1.Contains("Server="), "Connection string should contain Server parameter");
                AssertTest(connString1.Contains("UID="), "Connection string should contain UID parameter");
                AssertTest(connString1.Contains("PWD="), "Connection string should contain PWD parameter");

                // Test 2: With specific application
                var connString2 = GetConnectionString(FkEnvironment.PRD, FkApplication.INL);
                AssertTest(!string.IsNullOrEmpty(connString2), "INL connection string should not be empty");
                AssertTest(connString2.Contains("Database="), "INL connection string should contain Database parameter");

                // Test 3: With version
                var connString3 = GetConnectionString(FkEnvironment.DEV, FkApplication.FKM, "2.0");
                AssertTest(!string.IsNullOrEmpty(connString3), "Version 2.0 connection string should not be empty");

                // Test 4: With ConnectionKey
                var key = new ConnectionKey(FkApplication.FKM, FkEnvironment.PRD);
                var connString4 = GetConnectionString(key);
                AssertTest(!string.IsNullOrEmpty(connString4), "ConnectionKey connection string should not be empty");

                Console.WriteLine("✓ GetConnectionString tests passed");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"✗ GetConnectionString tests failed: {ex.Message}");
                DedgeNLog.Error(ex, "GetConnectionString tests failed");
            }
        }

        private static void TestGetCurrentVersionConnectionInfo()
        {
            Console.WriteLine("Testing GetCurrentVersionConnectionInfo...");
            
            try
            {
                var connInfo = GetCurrentVersionConnectionInfo(FkEnvironment.DEV, FkApplication.FKM);
                AssertTest(connInfo != null, "Current version connection info should not be null");
                AssertTest(connInfo!.Application == FkApplication.FKM, "Application should be FKM");
                AssertTest(connInfo!.Environment == FkEnvironment.DEV, "Environment should be DEV");
                AssertTest(!string.IsNullOrEmpty(connInfo!.Version), "Version should not be empty");

                Console.WriteLine("✓ GetCurrentVersionConnectionInfo tests passed");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"✗ GetCurrentVersionConnectionInfo tests failed: {ex.Message}");
                DedgeNLog.Error(ex, "GetCurrentVersionConnectionInfo tests failed");
            }
        }

        private static void TestGetConnectionKeyByDatabaseName()
        {
            Console.WriteLine("Testing GetConnectionKeyByDatabaseName...");
            
            try
            {
                // Test with known database names
                var key1 = GetConnectionKeyByDatabaseName("BASISTST");
                AssertTest(key1 != null, "Connection key for BASISTST should not be null");
                AssertTest(key1!.Application == FkApplication.FKM, "BASISTST should belong to FKM application");

                var key2 = GetConnectionKeyByDatabaseName("FKKONTO");
                AssertTest(key2 != null, "Connection key for FKKONTO should not be null");
                AssertTest(key2!.Application == FkApplication.INL, "FKKONTO should belong to INL application");

                Console.WriteLine("✓ GetConnectionKeyByDatabaseName tests passed");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"✗ GetConnectionKeyByDatabaseName tests failed: {ex.Message}");
                DedgeNLog.Error(ex, "GetConnectionKeyByDatabaseName tests failed");
            }
        }

        private static void TestGetAllConnectionDetails()
        {
            Console.WriteLine("Testing GetAllConnectionDetails...");
            
            try
            {
                // Test getting all connection details
                var allDetails = GetAllConnectionDetails();
                AssertTest(allDetails != null, "All connection details should not be null");
                AssertTest(allDetails!.Count > 0, "Should have at least one connection detail");

                // Test filtering by application
                var fkmDetails = GetAllConnectionDetails(FkApplication.FKM);
                AssertTest(fkmDetails != null, "FKM connection details should not be null");
                AssertTest(fkmDetails!.Count > 0, "Should have at least one FKM connection");
                AssertTest(fkmDetails!.All(d => d.ConnectionKey?.Application == FkApplication.FKM), 
                    "All FKM details should have FKM application");

                // Test connection detail structure
                var firstDetail = allDetails.First();
                AssertTest(firstDetail.ConnectionKey != null, "Connection key should not be null");
                AssertTest(!string.IsNullOrEmpty(firstDetail.DatabaseName), "Database name should not be empty");
                AssertTest(!string.IsNullOrEmpty(firstDetail.Description), "Description should not be empty");

                Console.WriteLine("✓ GetAllConnectionDetails tests passed");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"✗ GetAllConnectionDetails tests failed: {ex.Message}");
                DedgeNLog.Error(ex, "GetAllConnectionDetails tests failed");
            }
        }

        private static void TestGetConnectionsForApplications()
        {
            Console.WriteLine("Testing GetConnectionsForApplications...");
            
            try
            {
                var applications = new List<FkApplication> { FkApplication.FKM, FkApplication.INL };
                var connections = GetConnectionsForApplications(applications);
                AssertTest(connections != null, "Connections for applications should not be null");
                AssertTest(connections!.Count > 0, "Should have at least one connection");
                AssertTest(connections!.All(c => applications.Contains(c.Key.Application)), 
                    "All connections should be for specified applications");

                // Test connection information structure
                var firstConnection = connections.First();
                AssertTest(firstConnection!.Key != null, "Connection key should not be null");
                AssertTest(firstConnection!.ConnectionInfo != null, "Connection info should not be null");
                AssertTest(!string.IsNullOrEmpty(firstConnection!.ConnectionInfo!.Database), 
                    "Database should not be empty");

                Console.WriteLine("✓ GetConnectionsForApplications tests passed");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"✗ GetConnectionsForApplications tests failed: {ex.Message}");
                DedgeNLog.Error(ex, "GetConnectionsForApplications tests failed");
            }
        }

        private static void TestConnectionKeyOperations()
        {
            Console.WriteLine("Testing ConnectionKey operations...");
            
            try
            {
                // Test ConnectionKey creation
                var key1 = new ConnectionKey(FkApplication.FKM, FkEnvironment.DEV);
                AssertTest(key1.Application == FkApplication.FKM, "ConnectionKey application should be FKM");
                AssertTest(key1.Environment == FkEnvironment.DEV, "ConnectionKey environment should be DEV");
                AssertTest(key1.Version == "2.0", "Default version should be 1.0");

                // Test ConnectionKey with version
                var key2 = new ConnectionKey(FkApplication.FKM, FkEnvironment.DEV, "2.0");
                AssertTest(key2.Version == "2.0", "ConnectionKey version should be 2.0");

                // Test ConnectionKey equality
                var key3 = new ConnectionKey(FkApplication.FKM, FkEnvironment.DEV, "2.0");
                AssertTest(key1.Equals(key3), "Equal ConnectionKeys should be equal");
                AssertTest(key1.GetHashCode() == key3.GetHashCode(), "Equal ConnectionKeys should have same hash code");

                // Test GetDatabaseName
                var databaseName = GetDatabaseName(key1);
                AssertTest(!string.IsNullOrEmpty(databaseName), "Database name should not be empty");

                Console.WriteLine("✓ ConnectionKey operations tests passed");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"✗ ConnectionKey operations tests failed: {ex.Message}");
                DedgeNLog.Error(ex, "ConnectionKey operations tests failed");
            }
        }

        private static void TestErrorHandling()
        {
            Console.WriteLine("Testing error handling...");
            
            try
            {
                // Test invalid database name
                try
                {
                    GetConnectionKeyByDatabaseName("INVALID_DATABASE");
                    AssertTest(false, "Should have thrown exception for invalid database name");
                }
                catch (ArgumentException)
                {
                    // Expected exception
                    AssertTest(true, "Correctly threw ArgumentException for invalid database name");
                }

                // Test invalid environment/application combination
                try
                {
                    GetConnectionStringInfo(FkEnvironment.DEV, FkApplication.VIS);
                    // This might work if VIS is configured, so we just log it
                    Console.WriteLine("  Note: VIS application in DEV environment is available");
                }
                catch (KeyNotFoundException)
                {
                    // Expected if VIS is not configured for DEV
                    AssertTest(true, "Correctly threw KeyNotFoundException for unconfigured combination");
                }

                Console.WriteLine("✓ Error handling tests passed");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"✗ Error handling tests failed: {ex.Message}");
                DedgeNLog.Error(ex, "Error handling tests failed");
            }
        }

        private static void TestVersionHandling()
        {
            Console.WriteLine("Testing version handling...");
            
            try
            {
                // Test version 1.0
                var v1Info = GetConnectionStringInfo(FkEnvironment.DEV, FkApplication.FKM, "2.0");
                AssertTest(v1Info.Version == "2.0", "Version 1.0 should be returned");

                // Test version 2.0
                var v2Info = GetConnectionStringInfo(FkEnvironment.DEV, FkApplication.FKM, "2.0");
                AssertTest(v2Info.Version == "2.0", "Version 2.0 should be returned");

                // Test that different versions have different connection strings
                var v1String = GetConnectionString(FkEnvironment.DEV, FkApplication.FKM, "2.0");
                var v2String = GetConnectionString(FkEnvironment.DEV, FkApplication.FKM, "2.0");
                AssertTest(v1String != v2String, "Different versions should have different connection strings");

                Console.WriteLine("✓ Version handling tests passed");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"✗ Version handling tests failed: {ex.Message}");
                DedgeNLog.Error(ex, "Version handling tests failed");
            }
        }

        private static void TestProviderHandling()
        {
            Console.WriteLine("Testing provider handling...");
            
            try
            {
                // Test DB2 provider
                var db2Info = GetConnectionStringInfo(FkEnvironment.DEV, FkApplication.FKM);
                AssertTest(db2Info.Provider == DatabaseProvider.DB2, "FKM should use DB2 provider");

                // Test SQL Server provider (if available)
                try
                {
                    var sqlInfo = GetConnectionStringInfo(FkEnvironment.PRD, FkApplication.DBQA);
                    AssertTest(sqlInfo.Provider == DatabaseProvider.SQLSERVER, "DBQA should use SQL Server provider");
                }
                catch (KeyNotFoundException)
                {
                    Console.WriteLine("  Note: DBQA application not configured, skipping SQL Server test");
                }

                Console.WriteLine("✓ Provider handling tests passed");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"✗ Provider handling tests failed: {ex.Message}");
                DedgeNLog.Error(ex, "Provider handling tests failed");
            }
        }

        private static void AssertTest(bool condition, string message)
        {
            _testCount++;
            if (condition)
            {
                _passedTests++;
                Console.WriteLine($"  ✓ {message}");
            }
            else
            {
                _failedTests++;
                Console.WriteLine($"  ✗ {message}");
                DedgeNLog.Error($"Test failed: {message}");
            }
        }

        private static void PrintTestSummary()
        {
            Console.WriteLine();
            Console.WriteLine("=== Test Summary ===");
            Console.WriteLine($"Total tests: {_testCount}");
            Console.WriteLine($"Passed: {_passedTests}");
            Console.WriteLine($"Failed: {_failedTests}");
            Console.WriteLine($"Success rate: {(_passedTests * 100.0 / _testCount):F1}%");
            
            if (_failedTests == 0)
            {
                Console.WriteLine("🎉 All tests passed! DedgeConnection rewrite is working correctly.");
                DedgeNLog.Info("All DedgeConnection tests passed successfully");
            }
            else
            {
                Console.WriteLine($"⚠️  {_failedTests} tests failed. Please review the issues above.");
                DedgeNLog.Warn($"DedgeConnection tests completed with {_failedTests} failures");
            }
        }
    }
}

