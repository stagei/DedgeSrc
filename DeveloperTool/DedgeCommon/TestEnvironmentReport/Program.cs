using DedgeCommon;
using System.Text;
using System.Text.Json;

namespace TestEnvironmentReport
{
    /// <summary>
    /// Test program to verify FkEnvironmentSettings and generate comprehensive environment report.
    /// Can be deployed to any server to verify auto-detection and configuration.
    /// </summary>
    internal class Program
    {
        private const string ReportFileName = "EnvironmentReport_{0}_{1:yyyyMMdd_HHmmss}.txt";
        private const string JsonFileName = "EnvironmentReport_{0}_{1:yyyyMMdd_HHmmss}.json";

        static async Task Main(string[] args)
        {
            Console.WriteLine("╔═══════════════════════════════════════════════════════════╗");
            Console.WriteLine("║   DedgeCommon Environment Settings Report Generator         ║");
            Console.WriteLine("╚═══════════════════════════════════════════════════════════╝");
            Console.WriteLine();

            string computerName = Environment.MachineName;
            DateTime runTime = DateTime.Now;

            try
            {
                // Parse command line arguments
                bool testAllDatabases = args.Any(a => a.Equals("--test-all-databases", StringComparison.OrdinalIgnoreCase));
                bool mapDrives = args.Any(a => a.Equals("--map-drives", StringComparison.OrdinalIgnoreCase));
                bool sendEmail = args.Any(a => a.Equals("--email", StringComparison.OrdinalIgnoreCase));
                bool testDatabase = !args.Any(a => a.Equals("--no-db-test", StringComparison.OrdinalIgnoreCase));
                
                string? overrideDatabase = args.FirstOrDefault(a => !a.StartsWith("--"));

                // Test all databases mode
                if (testAllDatabases)
                {
                    Console.WriteLine("Mode: Test All Databases\n");
                    var allDbReport = TestAllDatabases.RunTests();
                    
                    Console.WriteLine("\n" + allDbReport.TextReport);
                    
                    TestAllDatabases.SaveReport(allDbReport);
                    
                    Console.WriteLine($"\n✅ All database tests completed!");
                    Console.WriteLine($"   Success: {allDbReport.SuccessCount}/{allDbReport.TotalDatabases}");
                    
                    return;
                }

                // Map drives if requested
                if (mapDrives)
                {
                    Console.WriteLine("Mapping network drives...\n");
                    bool success = NetworkShareManager.MapAllDrives(persist: true);
                    Console.WriteLine(success ? "✓ All drives mapped\n" : "⚠️ Some drives failed to map\n");
                }

                if (!string.IsNullOrEmpty(overrideDatabase))
                {
                    Console.WriteLine($"Override Database: {overrideDatabase}");
                }

                // Generate report
                var report = await GenerateReport(overrideDatabase, testDatabase);

                // Display to console
                Console.WriteLine("\n" + report.TextReport);

                // Save to file
                string reportFilePath = string.Format(ReportFileName, computerName, runTime);
                string jsonFilePath = string.Format(JsonFileName, computerName, runTime);

                File.WriteAllText(reportFilePath, report.TextReport);
                Console.WriteLine($"\n📄 Text report saved to: {reportFilePath}");

                File.WriteAllText(jsonFilePath, report.JsonReport);
                Console.WriteLine($"📄 JSON report saved to: {jsonFilePath}");

                // Send email if requested
                if (sendEmail)
                {
                    await SendReportEmail(report, computerName);
                }

                // Summary
                Console.WriteLine("\n" + new string('═', 60));
                if (report.HasErrors)
                {
                    Console.WriteLine("⚠️  REPORT COMPLETED WITH WARNINGS/ERRORS");
                    Console.WriteLine($"   Check the report for details");
                    Environment.Exit(1);
                }
                else
                {
                    Console.WriteLine("✅ REPORT COMPLETED SUCCESSFULLY");
                    Console.WriteLine($"   All systems operational on {computerName}");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"\n❌ FATAL ERROR: {ex.Message}");
                Console.WriteLine($"\nStack Trace:\n{ex.StackTrace}");
                
                // Save error report
                string errorFile = $"EnvironmentReport_{computerName}_{runTime:yyyyMMdd_HHmmss}_ERROR.txt";
                File.WriteAllText(errorFile, $"Error: {ex.Message}\n\nStack Trace:\n{ex.StackTrace}");
                Console.WriteLine($"\n📄 Error details saved to: {errorFile}");
                
                Environment.Exit(1);
            }
        }

        private static async Task<EnvironmentReport> GenerateReport(string? overrideDatabase, bool testDatabase)
        {
            var report = new EnvironmentReport
            {
                ComputerName = Environment.MachineName,
                UserName = $"{Environment.UserDomainName}\\{Environment.UserName}",
                ReportTime = DateTime.Now,
                OverrideDatabase = overrideDatabase
            };

            var sb = new StringBuilder();

            sb.AppendLine("═══════════════════════════════════════════════════════════");
            sb.AppendLine("       DedgeCommon Environment Settings Report");
            sb.AppendLine("═══════════════════════════════════════════════════════════");
            sb.AppendLine();
            sb.AppendLine($"Computer Name:    {report.ComputerName}");
            sb.AppendLine($"Current User:     {report.UserName}");
            sb.AppendLine($"Report Time:      {report.ReportTime:yyyy-MM-dd HH:mm:ss}");
            sb.AppendLine($"OS Version:       {Environment.OSVersion}");
            sb.AppendLine($".NET Version:     {Environment.Version}");
            sb.AppendLine();

            // Section 1: Environment Settings
            sb.AppendLine("───────────────────────────────────────────────────────────");
            sb.AppendLine("  SECTION 1: ENVIRONMENT SETTINGS");
            sb.AppendLine("───────────────────────────────────────────────────────────");
            
            try
            {
                var settings = FkEnvironmentSettings.GetSettings(overrideDatabase: overrideDatabase);
                report.EnvironmentSettings = settings;

                sb.AppendLine($"✓ Environment detected successfully");
                sb.AppendLine();
                sb.AppendLine($"  Is Server:              {settings.IsServer}");
                sb.AppendLine($"  Application:            {settings.Application}");
                sb.AppendLine($"  Environment:            {settings.Environment}");
                sb.AppendLine($"  Database:               {settings.Database}");
                sb.AppendLine($"  Database Internal Name: {settings.DatabaseInternalName}");
                sb.AppendLine($"  COBOL Version:          {settings.Version}");
                sb.AppendLine();
                sb.AppendLine($"  Database Server:        {settings.DatabaseServerName}");
                sb.AppendLine($"  Database Provider:      {settings.DatabaseProvider}");
                sb.AppendLine($"  Database App:           {settings.DatabaseApplication}");
                sb.AppendLine($"  Database Env:           {settings.DatabaseEnvironment}");
                sb.AppendLine();
                sb.AppendLine($"  COBOL Object Path:      {settings.CobolObjectPath}");
                sb.AppendLine($"  DedgePshApps Path:         {settings.DedgePshAppsPath}");
                sb.AppendLine($"  EDI Standard Path:      {settings.EdiStandardPath}");
                if (!string.IsNullOrEmpty(settings.D365Path))
                {
                    sb.AppendLine($"  D365 Path:              {settings.D365Path}");
                }
                sb.AppendLine();

                // COBOL Executables
                sb.AppendLine("  COBOL Executables:");
                if (!string.IsNullOrEmpty(settings.CobolRuntimeExecutable))
                {
                    sb.AppendLine($"    ✓ Runtime (run.exe):   {settings.CobolRuntimeExecutable}");
                    report.CobolRuntimeFound = File.Exists(settings.CobolRuntimeExecutable);
                }
                else
                {
                    sb.AppendLine($"    ✗ Runtime (run.exe):   NOT FOUND");
                    report.HasErrors = true;
                }

                if (!string.IsNullOrEmpty(settings.CobolWindowsRuntimeExecutable))
                {
                    sb.AppendLine($"    ✓ Windows Runtime:     {settings.CobolWindowsRuntimeExecutable}");
                }
                else
                {
                    sb.AppendLine($"    ✗ Windows Runtime:     NOT FOUND");
                }

                if (!string.IsNullOrEmpty(settings.CobolCompilerExecutable))
                {
                    sb.AppendLine($"    ✓ Compiler:            {settings.CobolCompilerExecutable}");
                }
                else
                {
                    sb.AppendLine($"    - Compiler:            Not found (OK for runtime-only servers)");
                }

                if (!string.IsNullOrEmpty(settings.CobolDsWinExecutable))
                {
                    sb.AppendLine($"    ✓ DialogSystem:        {settings.CobolDsWinExecutable}");
                }
                else
                {
                    sb.AppendLine($"    - DialogSystem:        Not found (OK for runtime-only servers)");
                }
            }
            catch (Exception ex)
            {
                sb.AppendLine($"✗ ERROR: {ex.Message}");
                report.HasErrors = true;
                report.Errors.Add($"Environment Settings: {ex.Message}");
            }

            sb.AppendLine();

            // Section 2: Database Connectivity
            if (testDatabase)
            {
                sb.AppendLine("───────────────────────────────────────────────────────────");
                sb.AppendLine("  SECTION 2: DATABASE CONNECTIVITY TEST");
                sb.AppendLine("───────────────────────────────────────────────────────────");

                try
                {
                    var settings = report.EnvironmentSettings;
                    if (settings != null && !string.IsNullOrEmpty(settings.Database))
                    {
                        sb.AppendLine($"Testing connection to database: {settings.Database}");
                        sb.AppendLine();

                        using var dbHandler = DedgeDbHandler.CreateByDatabaseName(settings.DatabaseInternalName);
                        sb.AppendLine($"✓ Database handler created successfully");

                        // Simple query test
                        string testQuery = "SELECT TABNAME FROM SYSCAT.TABLES FETCH FIRST 1 ROWS ONLY";
                        var data = dbHandler.ExecuteQueryAsDataTable(testQuery, throwException: true);
                        
                        sb.AppendLine($"✓ Database connection successful");
                        sb.AppendLine($"✓ Test query executed successfully ({data.Rows.Count} row)");
                        report.DatabaseConnectivity = true;
                    }
                    else
                    {
                        sb.AppendLine($"⚠️  No database configured, skipping connectivity test");
                    }
                }
                catch (Exception ex)
                {
                    sb.AppendLine($"✗ Database connectivity test FAILED: {ex.Message}");
                    report.DatabaseConnectivity = false;
                    report.HasErrors = true;
                    report.Errors.Add($"Database connectivity: {ex.Message}");
                }

                sb.AppendLine();
            }

            // Section 3: Network Drives
            sb.AppendLine("───────────────────────────────────────────────────────────");
            sb.AppendLine("  SECTION 3: NETWORK DRIVES");
            sb.AppendLine("───────────────────────────────────────────────────────────");

            try
            {
                bool isServer = report.EnvironmentSettings?.IsServer ?? false;
                var mappedDrives = NetworkShareManager.GetMappedDrives();
                
                if (mappedDrives.Any())
                {
                    sb.AppendLine($"Found {mappedDrives.Count} mapped network drives:");
                    foreach (var drive in mappedDrives.OrderBy(d => d.Key))
                    {
                        sb.AppendLine($"  ✓ {drive.Key}: → {drive.Value}");
                    }
                    report.MappedDrives = mappedDrives;
                }
                else
                {
                    if (isServer)
                    {
                        sb.AppendLine($"⚠️  No network drives currently mapped (SERVER - should have drives mapped)");
                    }
                    else
                    {
                        sb.AppendLine($"ℹ️  No network drives currently mapped (WORKSTATION - this is normal)");
                    }
                }

                // Check for standard Dedge drives
                sb.AppendLine();
                sb.AppendLine($"Standard Dedge Drives Status (Required on: {(isServer ? "SERVERS" : "WORKSTATIONS optional")}):");
                CheckDrive(sb, report, "F", NetworkShareManager.StandardDrives.F_Felles, isServer);
                CheckDrive(sb, report, "K", NetworkShareManager.StandardDrives.K_Utvikling, isServer);
                CheckDrive(sb, report, "N", NetworkShareManager.StandardDrives.N_ErrProg, isServer);
                CheckDrive(sb, report, "R", NetworkShareManager.StandardDrives.R_ErpData, isServer);
                CheckDrive(sb, report, "X", NetworkShareManager.StandardDrives.X_DedgeCommon, isServer);

                // Offer to map drives
                if (isServer && report.StandardDrivesMapped.Count < 5)
                {
                    sb.AppendLine();
                    sb.AppendLine($"💡 TIP: Run with --map-drives to automatically map missing drives");
                }
            }
            catch (Exception ex)
            {
                sb.AppendLine($"✗ ERROR checking network drives: {ex.Message}");
                report.HasErrors = true;
                report.Errors.Add($"Network drives: {ex.Message}");
            }

            sb.AppendLine();

            // Section 4: File System Access
            sb.AppendLine("───────────────────────────────────────────────────────────");
            sb.AppendLine("  SECTION 4: FILE SYSTEM ACCESS");
            sb.AppendLine("───────────────────────────────────────────────────────────");

            try
            {
                var settings = report.EnvironmentSettings;
                if (settings != null)
                {
                    // Test COBOL Object Path access
                    if (!string.IsNullOrEmpty(settings.CobolObjectPath))
                    {
                        if (Directory.Exists(settings.CobolObjectPath))
                        {
                            sb.AppendLine($"✓ COBOL Object Path accessible: {settings.CobolObjectPath}");
                            
                            var files = Directory.GetFiles(settings.CobolObjectPath, "*.*", SearchOption.TopDirectoryOnly);
                            sb.AppendLine($"  Contains {files.Length} files");
                            report.CobolPathAccessible = true;
                        }
                        else
                        {
                            sb.AppendLine($"✗ COBOL Object Path NOT accessible: {settings.CobolObjectPath}");
                            report.CobolPathAccessible = false;
                            report.HasErrors = true;
                            report.Errors.Add($"COBOL path not accessible: {settings.CobolObjectPath}");
                        }
                    }

                    // Test DedgePshApps Path
                    if (!string.IsNullOrEmpty(settings.DedgePshAppsPath))
                    {
                        if (Directory.Exists(settings.DedgePshAppsPath))
                        {
                            sb.AppendLine($"✓ DedgePshApps Path accessible: {settings.DedgePshAppsPath}");
                        }
                        else
                        {
                            sb.AppendLine($"⚠️  DedgePshApps Path not accessible: {settings.DedgePshAppsPath}");
                        }
                    }

                    // Test EDI Path
                    if (!string.IsNullOrEmpty(settings.EdiStandardPath))
                    {
                        if (Directory.Exists(settings.EdiStandardPath))
                        {
                            sb.AppendLine($"✓ EDI Standard Path accessible: {settings.EdiStandardPath}");
                        }
                        else
                        {
                            sb.AppendLine($"⚠️  EDI Standard Path not accessible: {settings.EdiStandardPath}");
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                sb.AppendLine($"✗ ERROR checking file system access: {ex.Message}");
                report.HasErrors = true;
                report.Errors.Add($"File system access: {ex.Message}");
            }

            sb.AppendLine();

            // Section 5: Access Point Details
            if (report.EnvironmentSettings?.AccessPoint != null)
            {
                sb.AppendLine("───────────────────────────────────────────────────────────");
                sb.AppendLine("  SECTION 5: DATABASE ACCESS POINT DETAILS");
                sb.AppendLine("───────────────────────────────────────────────────────────");

                var ap = report.EnvironmentSettings.AccessPoint;
                sb.AppendLine($"  Database Name:          {ap.DatabaseName}");
                sb.AppendLine($"  Catalog Name:           {ap.CatalogName}");
                sb.AppendLine($"  Primary Catalog:        {ap.PrimaryCatalogName}");
                sb.AppendLine($"  Access Point Type:      {ap.AccessPointType}");
                sb.AppendLine($"  Instance Name:          {ap.InstanceName}");
                sb.AppendLine($"  Server:                 {ap.ServerName}:{ap.Port}");
                sb.AppendLine($"  Authentication:         {ap.AuthenticationType}");
                sb.AppendLine($"  Service Name:           {ap.ServiceName}");
                sb.AppendLine($"  Node Name:              {ap.NodeName}");
                sb.AppendLine($"  Is Active:              {ap.IsActive}");
                sb.AppendLine($"  Priority Index:         {ap.PriorityIndex}");
                sb.AppendLine();
                sb.AppendLine($"  Description (NO):       {ap.NorwegianDescription}");
                sb.AppendLine($"  Description (EN):       {ap.Description}");
                sb.AppendLine();
            }

            // Section 6: Summary
            sb.AppendLine("───────────────────────────────────────────────────────────");
            sb.AppendLine("  SECTION 6: SUMMARY");
            sb.AppendLine("───────────────────────────────────────────────────────────");

            sb.AppendLine($"  Environment Settings:   {(report.EnvironmentSettings != null ? "✓ OK" : "✗ FAILED")}");
            sb.AppendLine($"  COBOL Runtime:          {(report.CobolRuntimeFound ? "✓ Found" : "✗ Not Found")}");
            sb.AppendLine($"  COBOL Path Access:      {(report.CobolPathAccessible ? "✓ Accessible" : "✗ Not Accessible")}");
            sb.AppendLine($"  Database Connection:    {(report.DatabaseConnectivity ? "✓ OK" : testDatabase ? "✗ FAILED" : "- Skipped")}");
            sb.AppendLine($"  Network Drives:         {report.MappedDrives.Count} mapped");
            sb.AppendLine();

            if (report.Errors.Any())
            {
                sb.AppendLine($"⚠️  ERRORS/WARNINGS ({report.Errors.Count}):");
                foreach (var error in report.Errors)
                {
                    sb.AppendLine($"  - {error}");
                }
            }
            else
            {
                sb.AppendLine($"✅ All checks passed successfully!");
            }

            sb.AppendLine();
            sb.AppendLine("═══════════════════════════════════════════════════════════");

            report.TextReport = sb.ToString();
            report.JsonReport = JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true });

            return report;
        }

        private static void CheckDrive(StringBuilder sb, EnvironmentReport report, string driveLetter, string expectedPath, bool isServer)
        {
            string driveWithColon = $"{driveLetter}:";
            
            if (Directory.Exists(driveWithColon))
            {
                sb.AppendLine($"  ✓ {driveLetter}: drive is mapped");
                if (!report.StandardDrivesMapped.Contains(driveLetter))
                {
                    report.StandardDrivesMapped.Add(driveLetter);
                }
            }
            else
            {
                if (isServer)
                {
                    // On servers, missing drives are errors
                    sb.AppendLine($"  ✗ {driveLetter}: drive NOT mapped (expected: {expectedPath})");
                    report.HasErrors = true;
                    report.Errors.Add($"Drive {driveLetter}: not mapped (required on server)");
                }
                else
                {
                    // On workstations, missing drives are just informational
                    sb.AppendLine($"  ℹ️  {driveLetter}: drive NOT mapped (optional on workstation)");
                }
            }
        }

        private static async Task SendReportEmail(EnvironmentReport report, string computerName)
        {
            try
            {
                Console.WriteLine("\nSending email report...");
                
                string subject = report.HasErrors
                    ? $"[Environment Report] ⚠️ Issues Found on {computerName}"
                    : $"[Environment Report] ✓ All OK on {computerName}";

                string emailBody = $"Environment Settings Report from {computerName}\n\n" +
                                  $"User: {report.UserName}\n" +
                                  $"Time: {report.ReportTime:yyyy-MM-dd HH:mm:ss}\n\n" +
                                  $"{report.TextReport}";

                // Get email from environment variable or use default
                string recipientEmail = Environment.GetEnvironmentVariable("REPORT_EMAIL") 
                                       ?? "geir.helge.starholm@Dedge.no";

                Notification.SendHtmlEmail(recipientEmail, subject, emailBody);
                Console.WriteLine($"✓ Email sent to: {recipientEmail}");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"⚠️  Failed to send email: {ex.Message}");
            }
        }

        class EnvironmentReport
        {
            public string ComputerName { get; set; } = string.Empty;
            public string UserName { get; set; } = string.Empty;
            public DateTime ReportTime { get; set; }
            public string? OverrideDatabase { get; set; }
            
            public FkEnvironmentSettings? EnvironmentSettings { get; set; }
            public bool CobolRuntimeFound { get; set; }
            public bool CobolPathAccessible { get; set; }
            public bool DatabaseConnectivity { get; set; }
            public Dictionary<string, string> MappedDrives { get; set; } = new();
            public List<string> StandardDrivesMapped { get; set; } = new();
            
            public bool HasErrors { get; set; }
            public List<string> Errors { get; set; } = new();
            
            public string TextReport { get; set; } = string.Empty;
            public string JsonReport { get; set; } = string.Empty;
        }
    }
}
