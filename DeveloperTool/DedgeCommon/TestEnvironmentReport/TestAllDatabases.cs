using DedgeCommon;
using System.Text;
using System.Text.Json;

namespace TestEnvironmentReport
{
    /// <summary>
    /// Comprehensive test of FkEnvironmentSettings with all database configurations.
    /// Generates detailed report for manual verification.
    /// </summary>
    public static class TestAllDatabases
    {
        public class DatabaseTestResult
        {
            public string DatabaseName { get; set; } = string.Empty;
            public bool Success { get; set; }
            public string? ErrorMessage { get; set; }
            public FkEnvironmentSettings? Settings { get; set; }
            public string? Application { get; set; }
            public string? Environment { get; set; }
            public string? CatalogName { get; set; }
            public string? CobolObjectPath { get; set; }
            public bool CobolPathExists { get; set; }
            public DateTime TestedAt { get; set; }
        }

        public class AllDatabasesTestReport
        {
            public DateTime ReportTime { get; set; }
            public string ComputerName { get; set; } = string.Empty;
            public int TotalDatabases { get; set; }
            public int SuccessCount { get; set; }
            public int FailureCount { get; set; }
            public List<DatabaseTestResult> Results { get; set; } = new();
            public string TextReport { get; set; } = string.Empty;
        }

        /// <summary>
        /// Gets all unique database names from the configuration.
        /// </summary>
        public static List<string> GetAllDatabaseNames()
        {
            var allDatabases = new List<string>();

            try
            {
                var accessPoints = DedgeConnection.AccessPoints;
                
                // Get all unique database names
                allDatabases.AddRange(accessPoints.Select(ap => ap.DatabaseName).Distinct());
                
                // Also add all unique catalog names (aliases)
                allDatabases.AddRange(accessPoints.Select(ap => ap.CatalogName).Distinct());
                
                // Remove duplicates and sort
                allDatabases = allDatabases.Distinct().OrderBy(d => d).ToList();
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, "Failed to get database names");
            }

            return allDatabases;
        }

        /// <summary>
        /// Tests FkEnvironmentSettings with all database configurations.
        /// </summary>
        public static AllDatabasesTestReport RunTests()
        {
            var report = new AllDatabasesTestReport
            {
                ReportTime = DateTime.Now,
                ComputerName = Environment.MachineName
            };

            var databaseNames = GetAllDatabaseNames();
            report.TotalDatabases = databaseNames.Count;

            Console.WriteLine($"\n╔═══════════════════════════════════════════════════════════╗");
            Console.WriteLine($"║  Testing FkEnvironmentSettings with {databaseNames.Count,3} Databases    ║");
            Console.WriteLine($"╚═══════════════════════════════════════════════════════════╝\n");

            foreach (var dbName in databaseNames)
            {
                var result = TestSingleDatabase(dbName);
                report.Results.Add(result);

                if (result.Success)
                {
                    report.SuccessCount++;
                    Console.Write("✓");
                }
                else
                {
                    report.FailureCount++;
                    Console.Write("✗");
                }
            }

            Console.WriteLine($"\n\n✅ Success: {report.SuccessCount}/{report.TotalDatabases}");
            Console.WriteLine($"✗ Failures: {report.FailureCount}/{report.TotalDatabases}\n");

            // Generate text report
            report.TextReport = GenerateTextReport(report);

            return report;
        }

        private static DatabaseTestResult TestSingleDatabase(string databaseName)
        {
            var result = new DatabaseTestResult
            {
                DatabaseName = databaseName,
                TestedAt = DateTime.Now
            };

            try
            {
                // Test FkEnvironmentSettings with this database
                var settings = FkEnvironmentSettings.GetSettings(force: true, overrideDatabase: databaseName);

                result.Success = true;
                result.Settings = settings;
                result.Application = settings.Application;
                result.Environment = settings.Environment;
                result.CatalogName = settings.Database;
                result.CobolObjectPath = settings.CobolObjectPath;

                // Test if COBOL path exists
                if (!string.IsNullOrEmpty(settings.CobolObjectPath))
                {
                    result.CobolPathExists = Directory.Exists(settings.CobolObjectPath);
                }

                DedgeNLog.Debug($"Test passed for {databaseName}: App={settings.Application}, Env={settings.Environment}, Catalog={settings.Database}");
            }
            catch (Exception ex)
            {
                result.Success = false;
                result.ErrorMessage = ex.Message;
                DedgeNLog.Debug($"Test failed for {databaseName}: {ex.Message}");
            }

            return result;
        }

        private static string GenerateTextReport(AllDatabasesTestReport report)
        {
            var sb = new StringBuilder();

            sb.AppendLine("═══════════════════════════════════════════════════════════");
            sb.AppendLine("   FkEnvironmentSettings - All Databases Test Report");
            sb.AppendLine("═══════════════════════════════════════════════════════════");
            sb.AppendLine();
            sb.AppendLine($"Computer:     {report.ComputerName}");
            sb.AppendLine($"Report Time:  {report.ReportTime:yyyy-MM-dd HH:mm:ss}");
            sb.AppendLine($"Total Tests:  {report.TotalDatabases}");
            sb.AppendLine($"Success:      {report.SuccessCount}");
            sb.AppendLine($"Failures:     {report.FailureCount}");
            sb.AppendLine($"Success Rate: {(report.SuccessCount * 100.0 / report.TotalDatabases):F1}%");
            sb.AppendLine();

            // Group results by success/failure
            var successful = report.Results.Where(r => r.Success).OrderBy(r => r.Application).ThenBy(r => r.Environment).ToList();
            var failed = report.Results.Where(r => !r.Success).ToList();

            // Successful results
            if (successful.Any())
            {
                sb.AppendLine("───────────────────────────────────────────────────────────");
                sb.AppendLine($"  SUCCESSFUL TESTS ({successful.Count})");
                sb.AppendLine("───────────────────────────────────────────────────────────");
                sb.AppendLine();

                // Group by application and environment
                var grouped = successful.GroupBy(r => $"{r.Application}/{r.Environment}");

                foreach (var group in grouped.OrderBy(g => g.Key))
                {
                    sb.AppendLine($"  {group.Key}:");
                    foreach (var result in group.OrderBy(r => r.DatabaseName))
                    {
                        string pathStatus = result.CobolPathExists ? "✓" : "✗";
                        sb.AppendLine($"    {result.DatabaseName,-15} → {result.CatalogName,-15} | Path: {pathStatus} {result.CobolObjectPath}");
                    }
                    sb.AppendLine();
                }
            }

            // Failed results
            if (failed.Any())
            {
                sb.AppendLine("───────────────────────────────────────────────────────────");
                sb.AppendLine($"  FAILED TESTS ({failed.Count})");
                sb.AppendLine("───────────────────────────────────────────────────────────");
                sb.AppendLine();

                foreach (var result in failed.OrderBy(r => r.DatabaseName))
                {
                    sb.AppendLine($"  ✗ {result.DatabaseName}");
                    sb.AppendLine($"    Error: {result.ErrorMessage}");
                    sb.AppendLine();
                }
            }

            // Path accessibility summary
            sb.AppendLine("───────────────────────────────────────────────────────────");
            sb.AppendLine("  COBOL PATH ACCESSIBILITY SUMMARY");
            sb.AppendLine("───────────────────────────────────────────────────────────");
            sb.AppendLine();

            var uniquePaths = successful
                .Select(r => r.CobolObjectPath)
                .Distinct()
                .OrderBy(p => p);

            foreach (var path in uniquePaths)
            {
                if (!string.IsNullOrEmpty(path))
                {
                    var dbsUsingPath = successful.Where(r => r.CobolObjectPath == path).Select(r => r.CatalogName).ToList();
                    bool exists = Directory.Exists(path);
                    string status = exists ? "✓" : "✗";
                    
                    sb.AppendLine($"  {status} {path}");
                    sb.AppendLine($"     Used by: {string.Join(", ", dbsUsingPath)}");
                    sb.AppendLine();
                }
            }

            sb.AppendLine("═══════════════════════════════════════════════════════════");
            sb.AppendLine($"  TEST SUMMARY: {report.SuccessCount}/{report.TotalDatabases} PASSED");
            sb.AppendLine("═══════════════════════════════════════════════════════════");

            return sb.ToString();
        }

        /// <summary>
        /// Saves the report to files (text and JSON).
        /// </summary>
        public static void SaveReport(AllDatabasesTestReport report, string baseFileName = "AllDatabasesTest")
        {
            string timestamp = report.ReportTime.ToString("yyyyMMdd_HHmmss");
            string textFile = $"{baseFileName}_{report.ComputerName}_{timestamp}.txt";
            string jsonFile = $"{baseFileName}_{report.ComputerName}_{timestamp}.json";

            // Save text report
            File.WriteAllText(textFile, report.TextReport);
            Console.WriteLine($"\n📄 Text report saved to: {textFile}");

            // Save JSON report
            var options = new JsonSerializerOptions { WriteIndented = true };
            string json = JsonSerializer.Serialize(report, options);
            File.WriteAllText(jsonFile, json);
            Console.WriteLine($"📄 JSON report saved to: {jsonFile}");
        }
    }
}
