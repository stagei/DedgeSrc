using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using AutoDocNew.Core;
using AutoDocNew.Parsers;

namespace AutoDocNew.Tests;

/// <summary>
/// Test Runner - converted from Test-AutoDocGeneration.ps1
/// Tests all file types on C# solution, tracks timing, and reports errors
/// </summary>
public class TestRunner
{
    private readonly string _outputFolder;
    private readonly string _tmpRootFolder;
    private readonly string _srcRootFolder;
    private readonly string _logFile;
    private readonly TestResults _testResults;

    public TestRunner(string outputFolder = "", string tmpRootFolder = "", string srcRootFolder = "")
    {
        string optPath = Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt";
        _outputFolder = string.IsNullOrEmpty(outputFolder) 
            ? Path.Combine(optPath, "Webs", "AutoDocJson") 
            : outputFolder;
        _tmpRootFolder = string.IsNullOrEmpty(tmpRootFolder)
            ? Path.Combine(optPath, "data", "AutoDocJson", "tmp")
            : tmpRootFolder;
        _srcRootFolder = string.IsNullOrEmpty(srcRootFolder)
            ? Path.Combine(optPath, "data", "AutoDocJson", "tmp", "DedgeRepository")
            : srcRootFolder;

        string autoDocFolder = Path.GetDirectoryName(typeof(TestRunner).Assembly.Location) ?? "";
        _logFile = Path.Combine(autoDocFolder, "TestRunner.log");

        _testResults = new TestResults
        {
            StartTime = DateTime.Now,
            FileResults = new List<FileTestResult>()
        };

        // Ensure folders exist
        Directory.CreateDirectory(_outputFolder);
        Directory.CreateDirectory(_tmpRootFolder);
        Directory.CreateDirectory(_srcRootFolder);
    }

    /// <summary>
    /// Get test files list - 10 files per type from plan
    /// </summary>
    public List<TestFile> GetTestFiles()
    {
        var testFiles = new List<TestFile>();
        string optPath = Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt";
        string repoBase = Path.Combine(_srcRootFolder);

        // CBL files (10 files)
        testFiles.Add(new TestFile { Type = "CBL", FileName = "BSAUTOS.CBL", FullPath = Path.Combine(repoBase, "Dedge", "cbl", "BSAUTOS.CBL"), IsTable = false });
        testFiles.Add(new TestFile { Type = "CBL", FileName = "AABELMA.CBL", FullPath = Path.Combine(repoBase, "Dedge", "cbl", "AABELMA.CBL"), IsTable = false });
        testFiles.Add(new TestFile { Type = "CBL", FileName = "AAAM005.CBL", FullPath = Path.Combine(repoBase, "Dedge", "cbl", "AAAM005.CBL"), IsTable = false });
        testFiles.Add(new TestFile { Type = "CBL", FileName = "AAAKUN2.CBL", FullPath = Path.Combine(repoBase, "Dedge", "cbl", "AAAKUN2.CBL"), IsTable = false });
        testFiles.Add(new TestFile { Type = "CBL", FileName = "AAAKUND.CBL", FullPath = Path.Combine(repoBase, "Dedge", "cbl", "AAAKUND.CBL"), IsTable = false });
        testFiles.Add(new TestFile { Type = "CBL", FileName = "AAAM024.CBL", FullPath = Path.Combine(repoBase, "Dedge", "cbl", "AAAM024.CBL"), IsTable = false });
        testFiles.Add(new TestFile { Type = "CBL", FileName = "AAAM006.CBL", FullPath = Path.Combine(repoBase, "Dedge", "cbl", "AAAM006.CBL"), IsTable = false });
        testFiles.Add(new TestFile { Type = "CBL", FileName = "AAAM046.CBL", FullPath = Path.Combine(repoBase, "Dedge", "cbl", "AAAM046.CBL"), IsTable = false });
        testFiles.Add(new TestFile { Type = "CBL", FileName = "AAAKCSV.CBL", FullPath = Path.Combine(repoBase, "Dedge", "cbl", "AAAKCSV.CBL"), IsTable = false });
        testFiles.Add(new TestFile { Type = "CBL", FileName = "AAADATO.CBL", FullPath = Path.Combine(repoBase, "Dedge", "cbl", "AAADATO.CBL"), IsTable = false });

        // REX files (10 files)
        testFiles.Add(new TestFile { Type = "REX", FileName = "WKMONIT.REX", FullPath = Path.Combine(repoBase, "Dedge", "rexx_prod", "WKMONIT.REX"), IsTable = false });
        testFiles.Add(new TestFile { Type = "REX", FileName = "COPYMON.REX", FullPath = Path.Combine(repoBase, "Dedge", "rexx_prod", "COPYMON.REX"), IsTable = false });
        testFiles.Add(new TestFile { Type = "REX", FileName = "DIRBIND.REX", FullPath = Path.Combine(repoBase, "Dedge", "rexx_prod", "DIRBIND.REX"), IsTable = false });
        testFiles.Add(new TestFile { Type = "REX", FileName = "D3BD3FIL.REX", FullPath = Path.Combine(repoBase, "Dedge", "rexx_prod", "D3BD3FIL.REX"), IsTable = false });
        testFiles.Add(new TestFile { Type = "REX", FileName = "FKSNAPDB.REX", FullPath = Path.Combine(repoBase, "Dedge", "rexx_prod", "FKSNAPDB.REX"), IsTable = false });
        testFiles.Add(new TestFile { Type = "REX", FileName = "COBREPL.REX", FullPath = Path.Combine(repoBase, "Dedge", "rexx_prod", "COBREPL.REX"), IsTable = false });
        testFiles.Add(new TestFile { Type = "REX", FileName = "D3BD3TAB.REX", FullPath = Path.Combine(repoBase, "Dedge", "rexx_prod", "D3BD3TAB.REX"), IsTable = false });
        testFiles.Add(new TestFile { Type = "REX", FileName = "E02REST.REX", FullPath = Path.Combine(repoBase, "Dedge", "rexx_prod", "E02REST.REX"), IsTable = false });
        testFiles.Add(new TestFile { Type = "REX", FileName = "RESTDB_BASISTST.REX", FullPath = Path.Combine(repoBase, "DB2Scripts", "db2_forsprang_restore", "RESTDB_BASISTST.REX"), IsTable = false });
        testFiles.Add(new TestFile { Type = "REX", FileName = "RESTDB_MIG_B.rex", FullPath = Path.Combine(repoBase, "DB2Scripts", "db2_forsprang_restore", "RESTDB_MIG_B.rex"), IsTable = false });

        // BAT files (10 files)
        testFiles.Add(new TestFile { Type = "BAT", FileName = "RESTDB_MIG_B.BAT", FullPath = Path.Combine(repoBase, "DB2Scripts", "db2_forsprang_restore", "RESTDB_MIG_B.BAT"), IsTable = false });
        testFiles.Add(new TestFile { Type = "BAT", FileName = "GHS_TEMP.PS2 copy 2.bat", FullPath = Path.Combine(repoBase, "DedgePsh", "GHS_TEMP.PS2 copy 2.bat"), IsTable = false });
        testFiles.Add(new TestFile { Type = "BAT", FileName = "Db2-GeneratedGrants_srv_datavarehus_fkmprd_kerberos.bat", FullPath = Path.Combine(repoBase, "DedgePsh", "DevTools", "DatabaseTools", "Db2-GeneratedGrants_srv_datavarehus_fkmprd_kerberos.bat"), IsTable = false });
        testFiles.Add(new TestFile { Type = "BAT", FileName = "Db2-GeneratedGrants_srv_datavarehus_fkmprd_ntlm.bat", FullPath = Path.Combine(repoBase, "DedgePsh", "DevTools", "DatabaseTools", "Db2-GeneratedGrants_srv_datavarehus_fkmprd_ntlm.bat"), IsTable = false });
        testFiles.Add(new TestFile { Type = "BAT", FileName = "GHS_TEMP.PS2.bat", FullPath = Path.Combine(repoBase, "DedgePsh", "GHS_TEMP.PS2.bat"), IsTable = false });
        testFiles.Add(new TestFile { Type = "BAT", FileName = "FKATAB_BASISPRO.BAT", FullPath = Path.Combine(repoBase, "Dedge", "bat_prod", "FKATAB_BASISPRO.BAT"), IsTable = false });
        testFiles.Add(new TestFile { Type = "BAT", FileName = "FKATAB.BAT", FullPath = Path.Combine(repoBase, "Dedge", "bat_prod", "FKATAB.BAT"), IsTable = false });
        testFiles.Add(new TestFile { Type = "BAT", FileName = "919_generated_db2_drop_existing_nicknames.bat", FullPath = Path.Combine(repoBase, "DedgePsh", "DevTools", "DatabaseTools", "919_generated_db2_drop_existing_nicknames.bat"), IsTable = false });
        testFiles.Add(new TestFile { Type = "BAT", FileName = "restdb_vft_til_db2dev.bat", FullPath = Path.Combine(repoBase, "DB2Scripts", "db2_restore", "restdb_vft_til_db2dev.bat"), IsTable = false });
        testFiles.Add(new TestFile { Type = "BAT", FileName = "RESTDB_VFT_TIL_DB2DEV.BAT", FullPath = Path.Combine(repoBase, "Dedge", "bat", "RESTDB_VFT_TIL_DB2DEV.BAT"), IsTable = false });

        // PS1 files (10 files)
        testFiles.Add(new TestFile { Type = "PS1", FileName = "Db2-DiagTracker.ps1", FullPath = Path.Combine(repoBase, "DedgePsh", "DevTools", "DatabaseTools", "Db2-DiagTracker", "Db2-DiagTracker.ps1"), IsTable = false });
        testFiles.Add(new TestFile { Type = "PS1", FileName = "Db2-AnalyzeMemoryConfig.ps1", FullPath = Path.Combine(repoBase, "DedgePsh", "DevTools", "DatabaseTools", "Db2-AnalyzeMemoryConfig", "Db2-AnalyzeMemoryConfig.ps1"), IsTable = false });
        testFiles.Add(new TestFile { Type = "PS1", FileName = "RunExportImportAD.ps1", FullPath = Path.Combine(repoBase, "DedgePsh", "AD", "RunExportImportAD.ps1"), IsTable = false });
        testFiles.Add(new TestFile { Type = "PS1", FileName = "Db2-CreateInitialDatabases.ps1", FullPath = Path.Combine(repoBase, "DedgePsh", "DevTools", "DatabaseTools", "Db2-CreateInitialDatabases", "Db2-CreateInitialDatabases.ps1"), IsTable = false });
        testFiles.Add(new TestFile { Type = "PS1", FileName = "Db2-SelectHelper.ps1", FullPath = Path.Combine(repoBase, "DedgePsh", "DevTools", "DatabaseTools", "Db2-SelectHelper", "Db2-SelectHelper.ps1"), IsTable = false });
        testFiles.Add(new TestFile { Type = "PS1", FileName = "AvtalegiroImport.ps1", FullPath = Path.Combine(repoBase, "DedgePsh", "AvtalegiroImport", "AvtalegiroImport.ps1"), IsTable = false });
        testFiles.Add(new TestFile { Type = "PS1", FileName = "AzureDevOpsGitCheckIn.ps1", FullPath = Path.Combine(repoBase, "DevTools", "AzureDevOpsGitCheckIn", "AzureDevOpsGitCheckIn.ps1"), IsTable = false });
        testFiles.Add(new TestFile { Type = "PS1", FileName = "DeploySHR.ps1", FullPath = Path.Combine(repoBase, "DedgePOS", "ServiceHostRunner", "DeploySHR.ps1"), IsTable = false });
        testFiles.Add(new TestFile { Type = "PS1", FileName = "Deploy-NuGetPackage.ps1", FullPath = Path.Combine(repoBase, "DedgeCommon", "_old", "Deploy-NuGetPackage.ps1"), IsTable = false });
        testFiles.Add(new TestFile { Type = "PS1", FileName = "MoveInventoryToEDI.ps1", FullPath = Path.Combine(repoBase, "DedgePsh", "Agrideler", "MoveInventoryToEDI.ps1"), IsTable = false });

        // SQL tables (10 tables)
        testFiles.Add(new TestFile { Type = "SQL", FileName = "DBM.AH_ORDREHODE", FullPath = null, IsTable = true });
        testFiles.Add(new TestFile { Type = "SQL", FileName = "DBM.AH_ORDRELINJER", FullPath = null, IsTable = true });
        testFiles.Add(new TestFile { Type = "SQL", FileName = "CRM.A_ORDREHODE_MASKIN", FullPath = null, IsTable = true });
        testFiles.Add(new TestFile { Type = "SQL", FileName = "CRM.A_ORDREHODE_NY", FullPath = null, IsTable = true });
        testFiles.Add(new TestFile { Type = "SQL", FileName = "CRM.A_ORDRELINJER", FullPath = null, IsTable = true });
        testFiles.Add(new TestFile { Type = "SQL", FileName = "CRM.A_ORDREHODE", FullPath = null, IsTable = true });
        testFiles.Add(new TestFile { Type = "SQL", FileName = "CRM.A_ORDREHODE_U", FullPath = null, IsTable = true });
        testFiles.Add(new TestFile { Type = "SQL", FileName = "TV.V_DBQA_VIEWS_NOT_ACCESSED_INTERNALLY", FullPath = null, IsTable = true });
        testFiles.Add(new TestFile { Type = "SQL", FileName = "TV.V_DBQA_MIGRATION_TABLES_DB2_115", FullPath = null, IsTable = true });
        testFiles.Add(new TestFile { Type = "SQL", FileName = "DBM.DRBIDRSALG99K_SUMF", FullPath = null, IsTable = true });

        // CSharp solutions (10 solutions)
        testFiles.Add(new TestFile { Type = "CSharp", FileName = "GenericLogHandler.sln", FullPath = Path.Combine(repoBase, "GenericLogHandler", "GenericLogHandler.sln"), IsTable = false });
        testFiles.Add(new TestFile { Type = "CSharp", FileName = "DevTools.sln", FullPath = Path.Combine(repoBase, "DevTools", "DevTools.sln"), IsTable = false });
        testFiles.Add(new TestFile { Type = "CSharp", FileName = "D365InvVisService.sln", FullPath = Path.Combine(repoBase, "D365InvVisService", "D365InvVisService.sln"), IsTable = false });
        testFiles.Add(new TestFile { Type = "CSharp", FileName = "EntraMenuManager.sln", FullPath = Path.Combine(repoBase, "EntraMenuManager", "EntraMenuManager.sln"), IsTable = false });
        testFiles.Add(new TestFile { Type = "CSharp", FileName = "ExternalIntegrations.sln", FullPath = Path.Combine(repoBase, "ExternalIntegrations", "ExternalIntegrations.sln"), IsTable = false });
        testFiles.Add(new TestFile { Type = "CSharp", FileName = "FKMAccessAdmin.sln", FullPath = Path.Combine(repoBase, "FKMAccessAdmin", "FKMAccessAdmin.sln"), IsTable = false });
        testFiles.Add(new TestFile { Type = "CSharp", FileName = "BRREGRefresh.sln", FullPath = Path.Combine(repoBase, "BRREGRefresh", "BRREGRefresh.sln"), IsTable = false });
        testFiles.Add(new TestFile { Type = "CSharp", FileName = "DB2ExportCSV.sln", FullPath = Path.Combine(repoBase, "DB2ExportCSV", "DB2ExportCSV.sln"), IsTable = false });
        testFiles.Add(new TestFile { Type = "CSharp", FileName = "GetPeppolDirectory.sln", FullPath = Path.Combine(repoBase, "ExternalIntegrations", "GetPeppolDirectory", "GetPeppolDirectory.sln"), IsTable = false });
        testFiles.Add(new TestFile { Type = "CSharp", FileName = "AgriProd.sln", FullPath = Path.Combine(repoBase, "AgriProd", "AgriProd.sln"), IsTable = false });

        return testFiles;
    }

    /// <summary>
    /// Run tests for a specific file type
    /// </summary>
    public async Task<List<FileTestResult>> TestFileType(string fileType, int startFromIndex = 0)
    {
        var testFiles = GetTestFiles().Where(f => f.Type == fileType).ToList();
        var results = new List<FileTestResult>();

        Logger.LogMessage($"Testing {fileType} files: {testFiles.Count} files", LogLevel.INFO);

        for (int i = startFromIndex; i < testFiles.Count; i++)
        {
            var testFile = testFiles[i];
            var result = new FileTestResult
            {
                Index = i,
                Type = testFile.Type,
                FileName = testFile.FileName,
                Status = "Running"
            };

            try
            {
                Logger.LogMessage($"[{i + 1}/{testFiles.Count}] Testing {testFile.Type} - {testFile.FileName}", LogLevel.INFO);

                // Kill processes
                KillProcessHandler.KillOtherAutoDocProcesses();

                // Compile solution
                Logger.LogMessage("Compiling solution...", LogLevel.INFO);
                var compileResult = CompileSolution();
                if (!compileResult.Success)
                {
                    throw new Exception($"Compilation failed: {compileResult.ErrorMessage}");
                }

                // Run parser
                var stopwatch = Stopwatch.StartNew();
                string? htmlPath = null;

                if (testFile.IsTable)
                {
                    // SQL table
                    htmlPath = SqlParser.StartSqlParse(
                        testFile.FileName,
                        show: false,
                        outputFolder: _outputFolder,
                        tmpRootFolder: _tmpRootFolder,
                        srcRootFolder: _srcRootFolder
                    );
                }
                else
                {
                    // Source file
                    if (!File.Exists(testFile.FullPath))
                    {
                        Logger.LogMessage($"Source file not found: {testFile.FullPath}", LogLevel.WARN);
                        result.Status = "Skipped";
                        result.Error = "Source file not found";
                        results.Add(result);
                        continue;
                    }

                    switch (testFile.Type)
                    {
                        case "CBL":
                            htmlPath = CblParser.StartCblParse(
                                testFile.FullPath,
                                show: false,
                                outputFolder: _outputFolder,
                                tmpRootFolder: _tmpRootFolder,
                                srcRootFolder: _srcRootFolder,
                                clientSideRender: true,
                                saveMmdFiles: true
                            );
                            break;
                        case "REX":
                            htmlPath = RexParser.StartRexParse(
                                testFile.FullPath,
                                show: false,
                                outputFolder: _outputFolder,
                                tmpRootFolder: _tmpRootFolder,
                                srcRootFolder: _srcRootFolder,
                                clientSideRender: true,
                                saveMmdFiles: true
                            );
                            break;
                        case "BAT":
                            htmlPath = BatParser.StartBatParse(
                                testFile.FullPath,
                                show: false,
                                outputFolder: _outputFolder,
                                tmpRootFolder: _tmpRootFolder,
                                srcRootFolder: _srcRootFolder,
                                clientSideRender: true,
                                saveMmdFiles: true
                            );
                            break;
                        case "PS1":
                            htmlPath = Ps1Parser.StartPs1Parse(
                                testFile.FullPath,
                                show: false,
                                outputFolder: _outputFolder,
                                tmpRootFolder: _tmpRootFolder,
                                srcRootFolder: _srcRootFolder,
                                clientSideRender: true,
                                saveMmdFiles: true
                            );
                            break;
                        case "CSharp":
                            htmlPath = CSharpParser.StartCSharpParse(
                                Path.GetDirectoryName(testFile.FullPath) ?? "",
                                solutionFile: testFile.FullPath,
                                outputFolder: _outputFolder,
                                tmpRootFolder: _tmpRootFolder,
                                srcRootFolder: _srcRootFolder,
                                clientSideRender: true
                            );
                            break;
                    }
                }

                stopwatch.Stop();
                result.Duration = stopwatch.Elapsed;
                result.HtmlPath = htmlPath ?? "";

                if (string.IsNullOrEmpty(htmlPath) || !File.Exists(htmlPath))
                {
                    throw new Exception($"HTML file not generated: {htmlPath}");
                }

                result.Status = "Success";
                Logger.LogMessage($"Successfully processed {testFile.FileName} in {stopwatch.Elapsed.TotalSeconds:F2}s", LogLevel.INFO);
            }
            catch (Exception ex)
            {
                result.Status = "Failed";
                result.Error = ex.Message;
                Logger.LogMessage($"Failed to process {testFile.FileName}: {ex.Message}", LogLevel.ERROR, ex);
            }

            results.Add(result);
        }

        return results;
    }

    /// <summary>
    /// Compile solution
    /// </summary>
    private CompileResult CompileSolution()
    {
        try
        {
            string solutionPath = Path.Combine(
                Path.GetDirectoryName(typeof(TestRunner).Assembly.Location) ?? "",
                "..", "..", "..", "AutoDocNew.slnx"
            );
            solutionPath = Path.GetFullPath(solutionPath);
            
            if (!File.Exists(solutionPath))
            {
                // Try alternative path
                solutionPath = Path.Combine(
                    Path.GetDirectoryName(typeof(TestRunner).Assembly.Location) ?? "",
                    "..", "..", "AutoDocNew.slnx"
                );
                solutionPath = Path.GetFullPath(solutionPath);
            }

            var processStartInfo = new ProcessStartInfo
            {
                FileName = "dotnet",
                Arguments = $"build \"{solutionPath}\"",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            using var process = Process.Start(processStartInfo);
            if (process == null)
            {
                return new CompileResult { Success = false, ErrorMessage = "Failed to start dotnet build process" };
            }

            string output = process.StandardOutput.ReadToEnd();
            string error = process.StandardError.ReadToEnd();
            process.WaitForExit();

            if (process.ExitCode != 0)
            {
                return new CompileResult
                {
                    Success = false,
                    ErrorMessage = $"Build failed with exit code {process.ExitCode}\n{error}\n{output}"
                };
            }

            return new CompileResult { Success = true };
        }
        catch (Exception ex)
        {
            return new CompileResult { Success = false, ErrorMessage = ex.Message };
        }
    }

    /// <summary>
    /// Save test results to JSON file
    /// </summary>
    public void SaveResults(string outputPath)
    {
        _testResults.EndTime = DateTime.Now;
        _testResults.TotalDuration = (_testResults.EndTime ?? DateTime.Now) - _testResults.StartTime;

        var options = new JsonSerializerOptions
        {
            WriteIndented = true,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        };

        string json = JsonSerializer.Serialize(_testResults, options);
        File.WriteAllText(outputPath, json, Encoding.UTF8);
    }

    public TestResults GetResults() => _testResults;
}

public class TestFile
{
    public string Type { get; set; } = "";
    public string FileName { get; set; } = "";
    public string? FullPath { get; set; }
    public bool IsTable { get; set; }
}

public class FileTestResult
{
    public int Index { get; set; }
    public string Type { get; set; } = "";
    public string FileName { get; set; } = "";
    public string Status { get; set; } = "";
    public string? HtmlPath { get; set; }
    public TimeSpan Duration { get; set; }
    public string? Error { get; set; }
}

public class TestResults
{
    public DateTime StartTime { get; set; }
    public DateTime? EndTime { get; set; }
    public TimeSpan TotalDuration { get; set; }
    public List<FileTestResult> FileResults { get; set; } = new List<FileTestResult>();
}

public class CompileResult
{
    public bool Success { get; set; }
    public string ErrorMessage { get; set; } = "";
}
