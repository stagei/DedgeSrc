using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using AutoDocNew.Core;
using AutoDocNew.Parsers;

namespace AutoDocNew.Tests;

/// <summary>
/// Comparative tester - runs both PowerShell and C# solutions on same files and compares outputs
/// </summary>
public class ComparativeTester
{
    private readonly string _psOutputFolder;
    private readonly string _csOutputFolder;
    private readonly string _tmpRootFolder;
    private readonly string _srcRootFolder;

    public ComparativeTester()
    {
        string optPath = Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt";
        _psOutputFolder = Path.Combine(optPath, "Webs", "AutoDoc");
        _csOutputFolder = Path.Combine(optPath, "Webs", "AutoDocJson");
        _tmpRootFolder = Path.Combine(optPath, "data", "AutoDocJson", "tmp");
        _srcRootFolder = Path.Combine(optPath, "data", "AutoDocJson", "tmp", "DedgeRepository");
    }

    /// <summary>
    /// Run comparative tests on all file types
    /// </summary>
    public async Task<ComparisonReportData> RunComparativeTests()
    {
        var report = new ComparisonReportData
        {
            TestRun = new TestRunInfo
            {
                StartTime = DateTime.Now
            },
            FileTypes = new Dictionary<string, FileTypeStats>(),
            Summary = new SummaryStats()
        };

        // Test CBL files
        var cblResults = await TestFileType("CBL", new[]
        {
            "BSAUTOS.CBL", "AABELMA.CBL", "AAAM005.CBL", "AAAKUN2.CBL", "AAAKUND.CBL",
            "AAAM024.CBL", "AAAM006.CBL", "AAAM046.CBL", "AAAKCSV.CBL", "AAADATO.CBL"
        });
        report.FileTypes["CBL"] = cblResults;

        // Test REX files
        var rexResults = await TestFileType("REX", new[]
        {
            "WKMONIT.REX", "COPYMON.REX", "DIRBIND.REX", "D3BD3FIL.REX", "FKSNAPDB.REX",
            "COBREPL.REX", "D3BD3TAB.REX", "E02REST.REX", "RESTDB_BASISTST.REX", "RESTDB_MIG_B.rex"
        });
        report.FileTypes["REX"] = rexResults;

        // Test BAT files
        var batResults = await TestFileType("BAT", new[]
        {
            "RESTDB_MIG_B.BAT", "GHS_TEMP.PS2 copy 2.bat", "Db2-GeneratedGrants_srv_datavarehus_fkmprd_kerberos.bat",
            "Db2-GeneratedGrants_srv_datavarehus_fkmprd_ntlm.bat", "GHS_TEMP.PS2.bat",
            "FKATAB_BASISPRO.BAT", "FKATAB.BAT", "919_generated_db2_drop_existing_nicknames.bat",
            "restdb_vft_til_db2dev.bat", "RESTDB_VFT_TIL_DB2DEV.BAT"
        });
        report.FileTypes["BAT"] = batResults;

        // Test PS1 files
        var ps1Results = await TestFileType("PS1", new[]
        {
            "Db2-DiagTracker.ps1", "Db2-AnalyzeMemoryConfig.ps1", "RunExportImportAD.ps1",
            "Db2-CreateInitialDatabases.ps1", "Db2-SelectHelper.ps1", "AvtalegiroImport.ps1",
            "AzureDevOpsGitCheckIn.ps1", "DeploySHR.ps1", "Deploy-NuGetPackage.ps1", "MoveInventoryToEDI.ps1"
        });
        report.FileTypes["PS1"] = ps1Results;

        // Test SQL tables
        var sqlResults = await TestSqlTables(new[]
        {
            "DBM.AH_ORDREHODE", "DBM.AH_ORDRELINJER", "CRM.A_ORDREHODE_MASKIN", "CRM.A_ORDREHODE_NY",
            "CRM.A_ORDRELINJER", "CRM.A_ORDREHODE", "CRM.A_ORDREHODE_U",
            "TV.V_DBQA_VIEWS_NOT_ACCESSED_INTERNALLY", "TV.V_DBQA_MIGRATION_TABLES_DB2_115", "DBM.DRBIDRSALG99K_SUMF"
        });
        report.FileTypes["SQL"] = sqlResults;

        // Test CSharp solutions
        var csharpResults = await TestCSharpSolutions(new[]
        {
            "GenericLogHandler.sln", "DevTools.sln", "D365InvVisService.sln", "EntraMenuManager.sln",
            "ExternalIntegrations.sln", "FKMAccessAdmin.sln", "BRREGRefresh.sln", "DB2ExportCSV.sln",
            "GetPeppolDirectory.sln", "AgriProd.sln"
        });
        report.FileTypes["CSharp"] = csharpResults;

        // Calculate summary
        report.TestRun.EndTime = DateTime.Now;
        TimeSpan totalDuration = report.TestRun.EndTime - report.TestRun.StartTime;
        report.TestRun.TotalDuration = totalDuration.ToString(@"hh\:mm\:ss");

        int totalFiles = report.FileTypes.Values.Sum(ft => ft.TestCount);
        int perfectMatches = report.FileTypes.Values.Sum(ft => ft.Matches);
        int showStoppers = report.FileTypes.Values.Sum(ft => ft.ShowStoppers);
        double totalSimilarity = report.FileTypes.Values.Sum(ft => ft.AvgSimilarity * ft.TestCount);

        TimeSpan totalPsDuration = report.FileTypes.Values
            .Where(ft => !string.IsNullOrEmpty(ft.PowershellAvgDuration))
            .Select(ft => TimeSpan.Parse(ft.PowershellAvgDuration))
            .Aggregate(TimeSpan.Zero, (sum, d) => sum.Add(d));
        
        TimeSpan totalCsDuration = report.FileTypes.Values
            .Where(ft => !string.IsNullOrEmpty(ft.CsharpAvgDuration))
            .Select(ft => TimeSpan.Parse(ft.CsharpAvgDuration))
            .Aggregate(TimeSpan.Zero, (sum, d) => sum.Add(d));

        report.Summary.TotalFiles = totalFiles;
        report.Summary.PerfectMatches = perfectMatches;
        report.Summary.ShowStoppers = showStoppers;
        report.Summary.OverallSimilarity = totalFiles > 0 ? totalSimilarity / totalFiles : 0;
        report.Summary.PowershellTotalDuration = totalPsDuration.ToString(@"hh\:mm\:ss");
        report.Summary.CsharpTotalDuration = totalCsDuration.ToString(@"hh\:mm\:ss");

        return report;
    }

    private async Task<FileTypeStats> TestFileType(string fileType, string[] fileNames)
    {
        var stats = new FileTypeStats
        {
            TestCount = fileNames.Length,
            Files = new List<FileComparisonResult>()
        };

        List<TimeSpan> psDurations = new List<TimeSpan>();
        List<TimeSpan> csDurations = new List<TimeSpan>();

        foreach (var fileName in fileNames)
        {
            string filePath = GetFilePath(fileType, fileName);
            if (!File.Exists(filePath) && fileType != "SQL")
            {
                continue;
            }

            var result = new FileComparisonResult { FileName = fileName, Type = fileType };
            string? psHtmlPath = null;

            // Run PowerShell version
            try
            {
                var psStopwatch = Stopwatch.StartNew();
                psHtmlPath = await RunPowerShellParser(fileType, filePath, fileName);
                psStopwatch.Stop();
                result.PowershellDuration = psStopwatch.Elapsed;
                psDurations.Add(psStopwatch.Elapsed);
            }
            catch (Exception ex)
            {
                Logger.LogMessage($"PowerShell test failed for {fileName}: {ex.Message}", LogLevel.ERROR);
            }

            // Run C# version
            try
            {
                var csStopwatch = Stopwatch.StartNew();
                string? csHtmlPath = await RunCSharpParser(fileType, filePath, fileName);
                csStopwatch.Stop();
                result.CsharpDuration = csStopwatch.Elapsed;
                csDurations.Add(csStopwatch.Elapsed);

                // Compare HTML files
                if (!string.IsNullOrEmpty(psHtmlPath) && !string.IsNullOrEmpty(csHtmlPath))
                {
                    if (File.Exists(psHtmlPath) && File.Exists(csHtmlPath))
                    {
                        var comparison = HtmlComparer.CompareHtmlFiles(psHtmlPath, csHtmlPath);
                        result.Similarity = comparison.Similarity;
                        result.Status = comparison.Similarity >= 98.0 && comparison.ShowStoppers.Count == 0 ? "Match" 
                            : comparison.ShowStoppers.Count > 0 ? "ShowStopper" : "Acceptable";
                        result.ShowStoppers = comparison.ShowStoppers;
                        result.Differences = comparison.AcceptableDifferences;

                        if (comparison.Similarity >= 98.0 && comparison.ShowStoppers.Count == 0)
                        {
                            stats.Matches++;
                        }
                        else if (comparison.ShowStoppers.Count > 0)
                        {
                            stats.ShowStoppers++;
                        }
                        else
                        {
                            stats.AcceptableDifferences++;
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Logger.LogMessage($"C# test failed for {fileName}: {ex.Message}", LogLevel.ERROR);
                result.Status = "Error";
            }

            stats.Files.Add(result);
        }

        // Calculate averages
        stats.PowershellAvgDuration = psDurations.Count > 0 ? TimeSpan.FromMilliseconds(psDurations.Average(d => d.TotalMilliseconds)).ToString(@"hh\:mm\:ss") : "00:00:00";
        stats.CsharpAvgDuration = csDurations.Count > 0 ? TimeSpan.FromMilliseconds(csDurations.Average(d => d.TotalMilliseconds)).ToString(@"hh\:mm\:ss") : "00:00:00";
        stats.AvgSimilarity = stats.Files.Where(f => f.Similarity.HasValue).Any() ? stats.Files.Where(f => f.Similarity.HasValue).Average(f => f.Similarity!.Value) : 0;

        return stats;
    }

    private async Task<FileTypeStats> TestSqlTables(string[] tableNames)
    {
        var stats = new FileTypeStats
        {
            TestCount = tableNames.Length,
            Files = new List<FileComparisonResult>()
        };

        List<TimeSpan> psDurations = new List<TimeSpan>();
        List<TimeSpan> csDurations = new List<TimeSpan>();

        foreach (var tableName in tableNames)
        {
            var result = new FileComparisonResult { FileName = tableName, Type = "SQL" };

            // Run PowerShell version
            try
            {
                var psStopwatch = Stopwatch.StartNew();
                string? psHtmlPath = await RunPowerShellSqlParser(tableName);
                psStopwatch.Stop();
                result.PowershellDuration = psStopwatch.Elapsed;
                psDurations.Add(psStopwatch.Elapsed);
            }
            catch (Exception ex)
            {
                Logger.LogMessage($"PowerShell SQL test failed for {tableName}: {ex.Message}", LogLevel.ERROR);
            }

            // Run C# version
            try
            {
                var csStopwatch = Stopwatch.StartNew();
                string? csHtmlPath = SqlParser.StartSqlParse(tableName, outputFolder: _csOutputFolder, tmpRootFolder: _tmpRootFolder, srcRootFolder: _srcRootFolder);
                csStopwatch.Stop();
                result.CsharpDuration = csStopwatch.Elapsed;
                csDurations.Add(csStopwatch.Elapsed);

                // Compare HTML files
                string? psHtmlPath = await RunPowerShellSqlParser(tableName);
                if (!string.IsNullOrEmpty(psHtmlPath) && File.Exists(psHtmlPath) && File.Exists(csHtmlPath))
                {
                        var comparison = HtmlComparer.CompareHtmlFiles(psHtmlPath, csHtmlPath);
                        result.Similarity = comparison.Similarity;
                        result.Status = comparison.Similarity >= 98.0 && comparison.ShowStoppers.Count == 0 ? "Match" 
                            : comparison.ShowStoppers.Count > 0 ? "ShowStopper" : "Acceptable";
                        result.ShowStoppers = comparison.ShowStoppers;
                        result.Differences = comparison.AcceptableDifferences;

                    if (comparison.Similarity >= 98.0 && comparison.ShowStoppers.Count == 0)
                    {
                        stats.Matches++;
                    }
                    else if (comparison.ShowStoppers.Count > 0)
                    {
                        stats.ShowStoppers++;
                    }
                    else
                    {
                        stats.AcceptableDifferences++;
                    }
                }
            }
            catch (Exception ex)
            {
                Logger.LogMessage($"C# SQL test failed for {tableName}: {ex.Message}", LogLevel.ERROR);
                result.Status = "Error";
            }

            stats.Files.Add(result);
        }

        stats.PowershellAvgDuration = psDurations.Count > 0 ? TimeSpan.FromMilliseconds(psDurations.Average(d => d.TotalMilliseconds)).ToString(@"hh\:mm\:ss") : "00:00:00";
        stats.CsharpAvgDuration = csDurations.Count > 0 ? TimeSpan.FromMilliseconds(csDurations.Average(d => d.TotalMilliseconds)).ToString(@"hh\:mm\:ss") : "00:00:00";
        stats.AvgSimilarity = stats.Files.Where(f => f.Similarity.HasValue).Any() ? stats.Files.Where(f => f.Similarity.HasValue).Average(f => f.Similarity!.Value) : 0;
        return stats;
    }

    private async Task<FileTypeStats> TestCSharpSolutions(string[] solutionNames)
    {
        var stats = new FileTypeStats
        {
            TestCount = solutionNames.Length,
            Files = new List<FileComparisonResult>()
        };

        List<TimeSpan> psDurations = new List<TimeSpan>();
        List<TimeSpan> csDurations = new List<TimeSpan>();

        foreach (var solutionName in solutionNames)
        {
            string solutionPath = Path.Combine(_srcRootFolder, "DedgePsh", solutionName.Replace(".sln", ""), solutionName);
            if (!File.Exists(solutionPath))
            {
                continue;
            }

            var result = new FileComparisonResult { FileName = solutionName, Type = "CSharp" };
            string sourceFolder = Path.GetDirectoryName(solutionPath) ?? "";
            string? psHtmlPath = null;

            // Run PowerShell version
            try
            {
                var psStopwatch = Stopwatch.StartNew();
                psHtmlPath = await RunPowerShellCSharpParser(sourceFolder, solutionPath, solutionName);
                psStopwatch.Stop();
                result.PowershellDuration = psStopwatch.Elapsed;
                psDurations.Add(psStopwatch.Elapsed);
            }
            catch (Exception ex)
            {
                Logger.LogMessage($"PowerShell CSharp test failed for {solutionName}: {ex.Message}", LogLevel.ERROR);
            }

            // Run C# version
            try
            {
                var csStopwatch = Stopwatch.StartNew();
                string? csHtmlPath = CSharpParser.StartCSharpParse(sourceFolder, solutionFile: solutionPath, outputFolder: _csOutputFolder, tmpRootFolder: _tmpRootFolder, srcRootFolder: _srcRootFolder, clientSideRender: true);
                csStopwatch.Stop();
                result.CsharpDuration = csStopwatch.Elapsed;
                csDurations.Add(csStopwatch.Elapsed);

                // Compare HTML files
                if (!string.IsNullOrEmpty(psHtmlPath) && !string.IsNullOrEmpty(csHtmlPath))
                {
                    if (File.Exists(psHtmlPath) && File.Exists(csHtmlPath))
                    {
                        var comparison = HtmlComparer.CompareHtmlFiles(psHtmlPath, csHtmlPath);
                        result.Similarity = comparison.Similarity;
                        result.Status = comparison.Similarity >= 0.98 && comparison.ShowStoppers.Count == 0 ? "Match" 
                            : comparison.ShowStoppers.Count > 0 ? "ShowStopper" : "Acceptable";
                        result.ShowStoppers = comparison.ShowStoppers;
                        result.Differences = comparison.AcceptableDifferences;

                        if (comparison.Similarity >= 0.98 && comparison.ShowStoppers.Count == 0)
                        {
                            stats.Matches++;
                        }
                        else if (comparison.ShowStoppers.Count > 0)
                        {
                            stats.ShowStoppers++;
                        }
                        else
                        {
                            stats.AcceptableDifferences++;
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Logger.LogMessage($"C# solution test failed for {solutionName}: {ex.Message}", LogLevel.ERROR);
                result.Status = "Error";
            }

            stats.Files.Add(result);
        }

        stats.PowershellAvgDuration = psDurations.Count > 0 ? TimeSpan.FromMilliseconds(psDurations.Average(d => d.TotalMilliseconds)).ToString(@"hh\:mm\:ss") : "00:00:00";
        stats.CsharpAvgDuration = csDurations.Count > 0 ? TimeSpan.FromMilliseconds(csDurations.Average(d => d.TotalMilliseconds)).ToString(@"hh\:mm\:ss") : "00:00:00";
        stats.AvgSimilarity = stats.Files.Where(f => f.Similarity.HasValue).Any() ? stats.Files.Where(f => f.Similarity.HasValue).Average(f => f.Similarity!.Value) : 0;
        return stats;
    }

    private string GetFilePath(string fileType, string fileName)
    {
        return fileType switch
        {
            "CBL" => Path.Combine(_srcRootFolder, "Dedge", "cbl", fileName),
            "REX" => Path.Combine(_srcRootFolder, "Dedge", "rexx_prod", fileName),
            "BAT" => Path.Combine(_srcRootFolder, "Dedge", "bat_prod", fileName),
            "PS1" => Path.Combine(_srcRootFolder, "DedgePsh", fileName),
            _ => Path.Combine(_srcRootFolder, fileName)
        };
    }

    private async Task<string?> RunPowerShellParser(string fileType, string filePath, string fileName)
    {
        try
        {
            // Invoke PowerShell function via Process.Start
            string optPath = Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt";
            string modulePath = Path.Combine(optPath, "src", "DedgePsh", "_Modules", "AutoDocFunctions", "AutoDocFunctions.psm1");
            string globalFunctionsPath = Path.Combine(optPath, "src", "DedgePsh", "_Modules", "GlobalFunctions", "GlobalFunctions.psm1");
            
            string functionName = fileType switch
            {
                "CBL" => "Start-CblParse",
                "REX" => "Start-RexParse",
                "BAT" => "Start-BatParse",
                "PS1" => "Start-Ps1Parse",
                _ => null
            };

            if (functionName == null)
            {
                return null;
            }

            // Build PowerShell command with proper escaping
            string escapedFilePath = filePath.Replace("'", "''");
            string escapedPsOutputFolder = _psOutputFolder.Replace("'", "''");
            string escapedTmpRootFolder = _tmpRootFolder.Replace("'", "''");
            string escapedSrcRootFolder = _srcRootFolder.Replace("'", "''");
            string escapedGlobalFunctionsPath = globalFunctionsPath.Replace("'", "''");
            string escapedModulePath = modulePath.Replace("'", "''");
            
            string psCommand = $@"
try {{
    Import-Module '{escapedGlobalFunctionsPath}' -Force -ErrorAction Stop;
    Import-Module '{escapedModulePath}' -Force -ErrorAction Stop;
    $result = {functionName} -SourceFile '{escapedFilePath}' -OutputFolder '{escapedPsOutputFolder}' -TmpRootFolder '{escapedTmpRootFolder}' -SrcRootFolder '{escapedSrcRootFolder}' -ClientSideRender -SaveMmdFiles;
    if ($result) {{
        Write-Output $result;
    }} else {{
        Write-Output '{escapedPsOutputFolder}\{fileName}.html';
    }}
}} catch {{
    Write-Error $_.Exception.Message;
    exit 1;
}}
";

            var processStartInfo = new ProcessStartInfo
            {
                FileName = "pwsh",
                Arguments = $"-NoProfile -Command \"{psCommand}\"",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            using var process = Process.Start(processStartInfo);
            if (process == null)
            {
                return null;
            }

            string output = await process.StandardOutput.ReadToEndAsync();
            string error = await process.StandardError.ReadToEndAsync();
            await process.WaitForExitAsync();

            // Log warnings but don't fail - HTML may still be generated
            if (!string.IsNullOrEmpty(error))
            {
                Logger.LogMessage($"PowerShell parser warnings for {fileName}: {error}", LogLevel.WARN);
            }

            // Extract HTML path from output - PowerShell functions return the full path
            // The path is typically the last line that ends with .html
            // IMPORTANT: Extract path even if ExitCode != 0, as warnings don't prevent HTML generation
            string? htmlPath = null;
            if (!string.IsNullOrEmpty(output))
            {
                // Try to extract path from output (PowerShell functions typically return the full path)
                // Look for lines ending with .html, prefer the last one that exists
                string[] lines = output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                for (int i = lines.Length - 1; i >= 0; i--)
                {
                    string trimmed = lines[i].Trim();
                    if (trimmed.EndsWith(".html", StringComparison.OrdinalIgnoreCase))
                    {
                        // Check if it's a valid file path
                        if (File.Exists(trimmed))
                        {
                            htmlPath = trimmed;
                            break;
                        }
                        // Also check if it's a relative path in the output folder
                        string relativePath = Path.Combine(_psOutputFolder, Path.GetFileName(trimmed));
                        if (File.Exists(relativePath))
                        {
                            htmlPath = relativePath;
                            break;
                        }
                    }
                }
            }

            // Fallback: construct expected path
            if (string.IsNullOrEmpty(htmlPath))
            {
                string htmlFileName = fileName + ".html";
                htmlPath = Path.Combine(_psOutputFolder, htmlFileName);
            }

            // Check if HTML file exists - this is the real test of success
            if (File.Exists(htmlPath))
            {
                // Success - HTML file was generated, even if there were warnings
                if (process.ExitCode != 0)
                {
                    Logger.LogMessage($"PowerShell parser completed with warnings for {fileName}, but HTML file exists: {htmlPath}", LogLevel.INFO);
                }
                return htmlPath;
            }

            // HTML file doesn't exist - this is a real failure
            if (process.ExitCode != 0)
            {
                Logger.LogMessage($"PowerShell parser failed for {fileName}: ExitCode={process.ExitCode}, HTML file not found. Expected: {htmlPath}. Error={error}, Output={output}", LogLevel.ERROR);
            }
            else
            {
                Logger.LogMessage($"PowerShell HTML file not found for {fileName}. Expected: {htmlPath}. Output was: {output}", LogLevel.WARN);
            }
            return null;
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error running PowerShell parser for {fileName}: {ex.Message}", LogLevel.ERROR, ex);
            return null;
        }
    }

    private async Task<string?> RunCSharpParser(string fileType, string filePath, string fileName)
    {
        return fileType switch
        {
            "CBL" => CblParser.StartCblParse(filePath, outputFolder: _csOutputFolder, tmpRootFolder: _tmpRootFolder, srcRootFolder: _srcRootFolder, clientSideRender: true, saveMmdFiles: true),
            "REX" => RexParser.StartRexParse(filePath, outputFolder: _csOutputFolder, tmpRootFolder: _tmpRootFolder, srcRootFolder: _srcRootFolder, clientSideRender: true, saveMmdFiles: true),
            "BAT" => BatParser.StartBatParse(filePath, outputFolder: _csOutputFolder, tmpRootFolder: _tmpRootFolder, srcRootFolder: _srcRootFolder, clientSideRender: true, saveMmdFiles: true),
            "PS1" => Ps1Parser.StartPs1Parse(filePath, outputFolder: _csOutputFolder, tmpRootFolder: _tmpRootFolder, srcRootFolder: _srcRootFolder, clientSideRender: true, saveMmdFiles: true),
            _ => null
        };
    }

    private async Task<string?> RunPowerShellSqlParser(string tableName)
    {
        try
        {
            // Invoke PowerShell Start-SqlParse function
            string optPath = Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt";
            string modulePath = Path.Combine(optPath, "src", "DedgePsh", "_Modules", "AutoDocFunctions", "AutoDocFunctions.psm1");
            string globalFunctionsPath = Path.Combine(optPath, "src", "DedgePsh", "_Modules", "GlobalFunctions", "GlobalFunctions.psm1");
            
            string escapedPsOutputFolder = _psOutputFolder.Replace("'", "''");
            string escapedTmpRootFolder = _tmpRootFolder.Replace("'", "''");
            string escapedSrcRootFolder = _srcRootFolder.Replace("'", "''");
            string escapedGlobalFunctionsPath = globalFunctionsPath.Replace("'", "''");
            string escapedModulePath = modulePath.Replace("'", "''");
            
            string expectedHtmlFileName = tableName.Replace(".", "_").ToUpper().Replace("Æ", "AE").Replace("Ø", "OE").Replace("Å", "AA").ToLower() + ".sql.html";
            string psCommand = $@"
try {{
    Import-Module '{escapedGlobalFunctionsPath}' -Force -ErrorAction Stop;
    Import-Module '{escapedModulePath}' -Force -ErrorAction Stop;
    $result = Start-SqlParse -SqlTable '{tableName}' -OutputFolder '{escapedPsOutputFolder}' -TmpRootFolder '{escapedTmpRootFolder}' -SrcRootFolder '{escapedSrcRootFolder}';
    if ($result) {{
        Write-Output $result;
    }} else {{
        Write-Output '{escapedPsOutputFolder}\{expectedHtmlFileName}';
    }}
}} catch {{
    Write-Error $_.Exception.Message;
    exit 1;
}}
";

            var processStartInfo = new ProcessStartInfo
            {
                FileName = "pwsh",
                Arguments = $"-NoProfile -Command \"{psCommand}\"",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            using var process = Process.Start(processStartInfo);
            if (process == null)
            {
                return null;
            }

            string output = await process.StandardOutput.ReadToEndAsync();
            string error = await process.StandardError.ReadToEndAsync();
            await process.WaitForExitAsync();

            // Log warnings but don't fail - HTML may still be generated
            if (!string.IsNullOrEmpty(error))
            {
                Logger.LogMessage($"PowerShell SQL parser warnings for {tableName}: {error}", LogLevel.WARN);
            }

            // Extract HTML path from output - try to get from PowerShell output first
            string? htmlPath = null;
            if (!string.IsNullOrEmpty(output))
            {
                string[] lines = output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                for (int i = lines.Length - 1; i >= 0; i--)
                {
                    string trimmed = lines[i].Trim();
                    if (trimmed.EndsWith(".html", StringComparison.OrdinalIgnoreCase) && File.Exists(trimmed))
                    {
                        htmlPath = trimmed;
                        break;
                    }
                }
            }

            // Fallback: construct expected path
            if (string.IsNullOrEmpty(htmlPath))
            {
                string htmlFileName = tableName.Replace(".", "_").ToUpper().Replace("Æ", "AE").Replace("Ø", "OE").Replace("Å", "AA").ToLower() + ".sql.html";
                htmlPath = Path.Combine(_psOutputFolder, htmlFileName);
            }

            // Check if HTML file exists - this is the real test of success
            if (File.Exists(htmlPath))
            {
                if (process.ExitCode != 0)
                {
                    Logger.LogMessage($"PowerShell SQL parser completed with warnings for {tableName}, but HTML file exists: {htmlPath}", LogLevel.INFO);
                }
                return htmlPath;
            }

            // HTML file doesn't exist - this is a real failure
            if (process.ExitCode != 0)
            {
                Logger.LogMessage($"PowerShell SQL parser failed for {tableName}: ExitCode={process.ExitCode}, HTML file not found. Expected: {htmlPath}. Error={error}", LogLevel.ERROR);
            }
            return null;
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error running PowerShell SQL parser for {tableName}: {ex.Message}", LogLevel.ERROR, ex);
            return null;
        }
    }

    private async Task<string?> RunPowerShellCSharpParser(string sourceFolder, string solutionPath, string solutionName)
    {
        try
        {
            // Invoke PowerShell Start-CSharpParse function
            string optPath = Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt";
            string modulePath = Path.Combine(optPath, "src", "DedgePsh", "_Modules", "AutoDocFunctions", "AutoDocFunctions.psm1");
            string globalFunctionsPath = Path.Combine(optPath, "src", "DedgePsh", "_Modules", "GlobalFunctions", "GlobalFunctions.psm1");
            
            string escapedSourceFolder = sourceFolder.Replace("'", "''");
            string escapedSolutionPath = solutionPath.Replace("'", "''");
            string escapedPsOutputFolder = _psOutputFolder.Replace("'", "''");
            string escapedTmpRootFolder = _tmpRootFolder.Replace("'", "''");
            string escapedSrcRootFolder = _srcRootFolder.Replace("'", "''");
            string escapedGlobalFunctionsPath = globalFunctionsPath.Replace("'", "''");
            string escapedModulePath = modulePath.Replace("'", "''");
            
            string expectedHtmlFileName = Path.GetFileNameWithoutExtension(solutionName) + ".html";
            string psCommand = $@"
try {{
    Import-Module '{escapedGlobalFunctionsPath}' -Force -ErrorAction Stop;
    Import-Module '{escapedModulePath}' -Force -ErrorAction Stop;
    $result = Start-CSharpParse -SourceFolder '{escapedSourceFolder}' -SolutionFile '{escapedSolutionPath}' -OutputFolder '{escapedPsOutputFolder}' -TmpRootFolder '{escapedTmpRootFolder}' -SrcRootFolder '{escapedSrcRootFolder}' -ClientSideRender;
    if ($result) {{
        Write-Output $result;
    }} else {{
        Write-Output '{escapedPsOutputFolder}\{expectedHtmlFileName}';
    }}
}} catch {{
    Write-Error $_.Exception.Message;
    exit 1;
}}
";

            var processStartInfo = new ProcessStartInfo
            {
                FileName = "pwsh",
                Arguments = $"-NoProfile -Command \"{psCommand}\"",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            using var process = Process.Start(processStartInfo);
            if (process == null)
            {
                return null;
            }

            string output = await process.StandardOutput.ReadToEndAsync();
            string error = await process.StandardError.ReadToEndAsync();
            await process.WaitForExitAsync();

            // Log warnings but don't fail - HTML may still be generated
            if (!string.IsNullOrEmpty(error))
            {
                Logger.LogMessage($"PowerShell CSharp parser warnings for {solutionName}: {error}", LogLevel.WARN);
            }

            // Extract HTML path from output - try to get from PowerShell output first
            string? htmlPath = null;
            if (!string.IsNullOrEmpty(output))
            {
                string[] lines = output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                for (int i = lines.Length - 1; i >= 0; i--)
                {
                    string trimmed = lines[i].Trim();
                    if (trimmed.EndsWith(".html", StringComparison.OrdinalIgnoreCase) && File.Exists(trimmed))
                    {
                        htmlPath = trimmed;
                        break;
                    }
                }
            }

            // Fallback: construct expected path
            if (string.IsNullOrEmpty(htmlPath))
            {
                string htmlFileName = Path.GetFileNameWithoutExtension(solutionName) + ".html";
                htmlPath = Path.Combine(_psOutputFolder, htmlFileName);
            }

            // Check if HTML file exists - this is the real test of success
            if (File.Exists(htmlPath))
            {
                if (process.ExitCode != 0)
                {
                    Logger.LogMessage($"PowerShell CSharp parser completed with warnings for {solutionName}, but HTML file exists: {htmlPath}", LogLevel.INFO);
                }
                return htmlPath;
            }

            // HTML file doesn't exist - this is a real failure
            if (process.ExitCode != 0)
            {
                Logger.LogMessage($"PowerShell CSharp parser failed for {solutionName}: ExitCode={process.ExitCode}, HTML file not found. Expected: {htmlPath}. Error={error}", LogLevel.ERROR);
            }
            return null;
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error running PowerShell CSharp parser for {solutionName}: {ex.Message}", LogLevel.ERROR, ex);
            return null;
        }
    }
}
