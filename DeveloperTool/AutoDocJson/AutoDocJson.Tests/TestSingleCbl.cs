using System;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;
using AutoDocNew.Core;
using AutoDocNew.Parsers;

namespace AutoDocNew.Tests;

/// <summary>
/// Test single CBL file - used for iterative testing and error fixing
/// </summary>
public class TestSingleCbl
{
    /// <summary>
    /// Test a single CBL file and return result
    /// </summary>
    public static async Task<TestResult> TestCblFile(string filePath, string outputFolder, string tmpRootFolder, string srcRootFolder)
    {
        var result = new TestResult
        {
            FilePath = filePath,
            StartTime = DateTime.Now
        };

        try
        {
            Logger.LogMessage($"Testing CBL file: {filePath}", LogLevel.INFO);

            // Kill processes
            KillProcessHandler.KillOtherAutoDocProcesses();

            // Compile solution
            Logger.LogMessage("Compiling solution...", LogLevel.INFO);
            var compileResult = CompileSolution();
            if (!compileResult.Success)
            {
                result.Error = $"Compilation failed: {compileResult.ErrorMessage}";
                result.Status = "CompileError";
                return result;
            }

            // Run parser
            var stopwatch = Stopwatch.StartNew();
            string? htmlPath = CblParser.StartCblParse(
                filePath,
                show: false,
                outputFolder: outputFolder,
                tmpRootFolder: tmpRootFolder,
                srcRootFolder: srcRootFolder,
                clientSideRender: true,
                saveMmdFiles: true
            );
            stopwatch.Stop();

            result.Duration = stopwatch.Elapsed;
            result.HtmlPath = htmlPath;

            if (string.IsNullOrEmpty(htmlPath) || !File.Exists(htmlPath))
            {
                result.Error = $"HTML file not generated: {htmlPath}";
                result.Status = "GenerationFailed";
            }
            else
            {
                result.Status = "Success";
                Logger.LogMessage($"Successfully generated HTML in {stopwatch.Elapsed.TotalSeconds:F2}s", LogLevel.INFO);
            }
        }
        catch (Exception ex)
        {
            result.Error = ex.Message;
            result.Status = "Exception";
            result.Exception = ex.ToString();
            Logger.LogMessage($"Error testing file: {ex.Message}", LogLevel.ERROR, ex);
        }
        finally
        {
            result.EndTime = DateTime.Now;
        }

        return result;
    }

    private static CompileResult CompileSolution()
    {
        try
        {
            string solutionPath = Path.Combine(
                Path.GetDirectoryName(typeof(TestSingleCbl).Assembly.Location) ?? "",
                "..", "..", "..", "AutoDocNew.slnx"
            );
            solutionPath = Path.GetFullPath(solutionPath);
            
            if (!File.Exists(solutionPath))
            {
                // Try alternative path
                solutionPath = Path.Combine(
                    Path.GetDirectoryName(typeof(TestSingleCbl).Assembly.Location) ?? "",
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
}

public class TestResult
{
    public string FilePath { get; set; } = "";
    public DateTime StartTime { get; set; }
    public DateTime EndTime { get; set; }
    public TimeSpan Duration { get; set; }
    public string? HtmlPath { get; set; }
    public string Status { get; set; } = "";
    public string? Error { get; set; }
    public string? Exception { get; set; }
}
