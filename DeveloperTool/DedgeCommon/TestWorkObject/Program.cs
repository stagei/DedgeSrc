using DedgeCommon;
using System;
using System.IO;
using Newtonsoft.Json.Linq;

namespace TestWorkObject
{
    /// <summary>
    /// Comprehensive test program for WorkObject functionality.
    /// Tests JSON and HTML export capabilities.
    /// </summary>
    class Program
    {
        static int Main(string[] args)
        {
            Console.WriteLine("═══════════════════════════════════════════════════════════");
            Console.WriteLine("      WorkObject Functionality Test Program");
            Console.WriteLine("═══════════════════════════════════════════════════════════");
            Console.WriteLine();

            string outputFolder = Path.Combine(Path.GetTempPath(), "DedgeCommon_WorkObject_Test");
            string jsonFilePath = Path.Combine(outputFolder, $"TestWorkObject_{DateTime.Now:yyyyMMdd_HHmmss}.json");
            string htmlFilePath = Path.Combine(outputFolder, $"TestWorkObject_{DateTime.Now:yyyyMMdd_HHmmss}.html");

            try
            {
                // ═══════════════════════════════════════════════════════════
                // STEP 1: Create and populate WorkObject
                // ═══════════════════════════════════════════════════════════
                Console.WriteLine("STEP 1: Creating WorkObject...");
                var workObject = new WorkObject();

                // Add various property types
                workObject.SetProperty("ComputerName", Environment.MachineName);
                workObject.SetProperty("UserName", $"{Environment.UserDomainName}\\{Environment.UserName}");
                workObject.SetProperty("OperatingSystem", Environment.OSVersion.ToString());
                workObject.SetProperty("ProcessorCount", Environment.ProcessorCount);
                workObject.SetProperty("IsServer", Environment.MachineName.EndsWith("-APP") || Environment.MachineName.EndsWith("-DB"));
                workObject.SetProperty("TestTimestamp", DateTime.Now);
                workObject.SetProperty("TestArray", new List<string> { "Item1", "Item2", "Item3" });
                workObject.SetProperty("TestBool", true);
                workObject.SetProperty("TestNumber", 42);
                workObject.SetProperty("TestDouble", 3.14159);

                Console.WriteLine("  ✓ Added 10 properties to WorkObject");

                // Add script executions
                workObject.AddScriptExecution("Database Check", 
                    "SELECT * FROM SYSCAT.TABLES FETCH FIRST 5 ROWS ONLY", 
                    "TABSCHEMA  TABNAME    TYPE\nSYSCAT     TABLES     T\nSYSCAT     COLUMNS    T");

                workObject.AddScriptExecution("Server Info",
                    "Get-ComputerInfo | Select-Object CsName, OsName, OsVersion",
                    $"CsName: {Environment.MachineName}\nOsName: {Environment.OSVersion.Platform}\nOsVersion: {Environment.OSVersion.Version}");

                // Add another execution to same script (should append)
                workObject.AddScriptExecution("Database Check",
                    "SELECT COUNT(*) FROM SYSCAT.TABLES",
                    "COUNT(*)\n547");

                Console.WriteLine("  ✓ Added 3 script executions (2 unique scripts)");
                Console.WriteLine("  ✓ WorkObject populated successfully");
                Console.WriteLine();

                // ═══════════════════════════════════════════════════════════
                // STEP 2: Export to JSON
                // ═══════════════════════════════════════════════════════════
                Console.WriteLine("STEP 2: Exporting to JSON...");
                
                var exporter = new WorkObjectExporter();
                exporter.ExportToJson(workObject, jsonFilePath);

                Console.WriteLine($"  ✓ JSON exported to: {jsonFilePath}");
                
                // Verify JSON file exists
                if (!File.Exists(jsonFilePath))
                {
                    throw new Exception("JSON file was not created!");
                }

                long jsonFileSize = new FileInfo(jsonFilePath).Length;
                Console.WriteLine($"  ✓ JSON file size: {jsonFileSize} bytes");

                // ═══════════════════════════════════════════════════════════
                // STEP 3: Verify JSON Content
                // ═══════════════════════════════════════════════════════════
                Console.WriteLine();
                Console.WriteLine("STEP 3: Verifying JSON content...");
                
                string jsonContent = File.ReadAllText(jsonFilePath);
                var jsonObject = JObject.Parse(jsonContent);

                // Verify properties
                Assert("ComputerName in JSON", jsonObject["ComputerName"]?.ToString() == Environment.MachineName);
                Assert("UserName in JSON", !string.IsNullOrEmpty(jsonObject["UserName"]?.ToString()));
                Assert("ProcessorCount in JSON", jsonObject["ProcessorCount"]?.ToObject<int>() == Environment.ProcessorCount);
                Assert("TestBool in JSON", jsonObject["TestBool"]?.ToObject<bool>() == true);
                Assert("TestNumber in JSON", jsonObject["TestNumber"]?.ToObject<int>() == 42);
                Assert("TestArray in JSON", jsonObject["TestArray"] is JArray);
                
                // Verify ScriptArray
                var scriptArray = jsonObject["ScriptArray"] as JArray;
                Assert("ScriptArray exists", scriptArray != null);
                Assert("ScriptArray has 2 entries", scriptArray?.Count == 2);

                if (scriptArray != null && scriptArray.Count > 0)
                {
                    var firstScript = scriptArray[0];
                    Assert("First script has Name", !string.IsNullOrEmpty(firstScript["Name"]?.ToString()));
                    Assert("First script has Script", !string.IsNullOrEmpty(firstScript["Script"]?.ToString()));
                    Assert("First script has Output", !string.IsNullOrEmpty(firstScript["Output"]?.ToString()));
                    Assert("First script has timestamps", !string.IsNullOrEmpty(firstScript["FirstTimestamp"]?.ToString()));
                }

                Console.WriteLine("  ✓ All JSON validations passed!");
                Console.WriteLine();

                // ═══════════════════════════════════════════════════════════
                // STEP 4: Export to HTML
                // ═══════════════════════════════════════════════════════════
                Console.WriteLine("STEP 4: Exporting to HTML...");
                
                exporter.ExportToHtml(
                    workObject,
                    htmlFilePath,
                    title: "WorkObject Test Report",
                    additionalStyle: ".test-class { color: red; }",
                    addToDevToolsWebPath: false,  // Set to true to publish to web
                    autoOpen: false);  // Set to true to open in browser

                Console.WriteLine($"  ✓ HTML exported to: {htmlFilePath}");

                // Verify HTML file exists
                if (!File.Exists(htmlFilePath))
                {
                    throw new Exception("HTML file was not created!");
                }

                long htmlFileSize = new FileInfo(htmlFilePath).Length;
                Console.WriteLine($"  ✓ HTML file size: {htmlFileSize} bytes");

                // ═══════════════════════════════════════════════════════════
                // STEP 5: Verify HTML Content
                // ═══════════════════════════════════════════════════════════
                Console.WriteLine();
                Console.WriteLine("STEP 5: Verifying HTML content...");
                
                string htmlContent = File.ReadAllText(htmlFilePath);

                // Verify HTML structure
                Assert("HTML has DOCTYPE", htmlContent.Contains("<!DOCTYPE html>"));
                Assert("HTML has title", htmlContent.Contains("<title>WorkObject Test Report</title>"));
                Assert("HTML has theme toggle", htmlContent.Contains("Toggle Theme"));
                Assert("HTML has Properties section", htmlContent.Contains("<h2>Properties</h2>"));
                Assert("HTML has tab system", htmlContent.Contains("class='tab-container'"));
                Assert("HTML has tab headers", htmlContent.Contains("class='tab-headers'"));
                Assert("HTML has tab buttons", htmlContent.Contains("class='tab-button'"));
                Assert("HTML has Monaco editor", htmlContent.Contains("monaco-editor-container"));
                Assert("HTML has showTab function", htmlContent.Contains("function showTab"));
                
                // Verify properties are in HTML
                Assert("HTML contains ComputerName", htmlContent.Contains(Environment.MachineName));
                Assert("HTML contains ProcessorCount", htmlContent.Contains(Environment.ProcessorCount.ToString()));
                
                // Verify scripts are in HTML (as tabs)
                Assert("HTML contains Database Check", htmlContent.Contains("Database Check"));
                Assert("HTML contains Server Info", htmlContent.Contains("Server Info"));
                Assert("HTML contains SQL", htmlContent.Contains("SELECT"));
                Assert("HTML contains Monaco script tags", htmlContent.Contains("data-script-"));

                Console.WriteLine("  ✓ All HTML validations passed!");
                Console.WriteLine();

                // ═══════════════════════════════════════════════════════════
                // STEP 6: Summary
                // ═══════════════════════════════════════════════════════════
                Console.WriteLine("═══════════════════════════════════════════════════════════");
                Console.WriteLine("                  TEST RESULTS");
                Console.WriteLine("═══════════════════════════════════════════════════════════");
                Console.WriteLine();
                Console.WriteLine("✅ WorkObject Creation:        PASS");
                Console.WriteLine("✅ Dynamic Properties:         PASS");
                Console.WriteLine("✅ Script Array:               PASS");
                Console.WriteLine("✅ JSON Export:                PASS");
                Console.WriteLine("✅ JSON Validation:            PASS");
                Console.WriteLine("✅ HTML Export:                PASS");
                Console.WriteLine("✅ HTML Validation:            PASS");
                Console.WriteLine();
                Console.WriteLine($"📄 JSON Output: {jsonFilePath}");
                Console.WriteLine($"📄 HTML Output: {htmlFilePath}");
                Console.WriteLine();
                Console.WriteLine("═══════════════════════════════════════════════════════════");
                Console.WriteLine("✅ ALL TESTS PASSED SUCCESSFULLY!");
                Console.WriteLine("═══════════════════════════════════════════════════════════");
                Console.WriteLine();

                // Open HTML in browser
                Console.WriteLine("Opening HTML report in browser...");
                try
                {
                    System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
                    {
                        FileName = htmlFilePath,
                        UseShellExecute = true
                    });
                    Console.WriteLine("✓ Browser opened");
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"⚠ Could not open browser: {ex.Message}");
                }

                return 0; // Success
            }
            catch (Exception ex)
            {
                Console.WriteLine();
                Console.WriteLine("═══════════════════════════════════════════════════════════");
                Console.WriteLine("❌ TEST FAILED");
                Console.WriteLine("═══════════════════════════════════════════════════════════");
                Console.WriteLine($"Error: {ex.Message}");
                Console.WriteLine();
                Console.WriteLine("Stack Trace:");
                Console.WriteLine(ex.StackTrace);
                Console.WriteLine();

                return 1; // Failure
            }
        }

        /// <summary>
        /// Simple assertion helper for test validation.
        /// </summary>
        static void Assert(string testName, bool condition)
        {
            if (!condition)
            {
                throw new Exception($"Assertion failed: {testName}");
            }
            Console.WriteLine($"  ✓ {testName}");
        }
    }
}
