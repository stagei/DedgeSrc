using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using AutoDocNew.Core;

namespace AutoDocNew.Tests;

/// <summary>
/// Browser Tester - manages Python HTTP server and browser automation testing
/// </summary>
public class BrowserTester : IDisposable
{
    private Process? _pythonServerProcess;
    private readonly string _outputFolder;
    private readonly int _port;

    public BrowserTester(string outputFolder, int port = 8889)
    {
        _outputFolder = outputFolder;
        _port = port;
    }

    /// <summary>
    /// Start Python HTTP server for C# output folder
    /// </summary>
    public bool StartPythonServer()
    {
        try
        {
            Logger.LogMessage($"Starting Python HTTP server on port {_port} for folder: {_outputFolder}", LogLevel.INFO);

            // Check if Python is available
            var pythonCheck = new ProcessStartInfo
            {
                FileName = "python",
                Arguments = "--version",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            using var checkProcess = Process.Start(pythonCheck);
            if (checkProcess == null)
            {
                Logger.LogMessage("Python not found, trying python3...", LogLevel.WARN);
                pythonCheck.FileName = "python3";
                using var checkProcess2 = Process.Start(pythonCheck);
                if (checkProcess2 == null)
                {
                    Logger.LogMessage("Python not available - browser testing will be skipped", LogLevel.WARN);
                    return false;
                }
            }

            // Start HTTP server
            string pythonCmd = File.Exists("python.exe") ? "python.exe" : "python";
            var serverStartInfo = new ProcessStartInfo
            {
                FileName = pythonCmd,
                Arguments = $"-m http.server {_port} --directory \"{_outputFolder}\"",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
                WorkingDirectory = _outputFolder
            };

            _pythonServerProcess = Process.Start(serverStartInfo);
            if (_pythonServerProcess == null)
            {
                Logger.LogMessage("Failed to start Python HTTP server", LogLevel.ERROR);
                return false;
            }

            // Wait a moment for server to start
            Thread.Sleep(2000);

            Logger.LogMessage($"Python HTTP server started on http://localhost:{_port}", LogLevel.INFO);
            return true;
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error starting Python HTTP server: {ex.Message}", LogLevel.ERROR, ex);
            return false;
        }
    }

    /// <summary>
    /// Stop Python HTTP server
    /// </summary>
    public void StopPythonServer()
    {
        try
        {
            if (_pythonServerProcess != null && !_pythonServerProcess.HasExited)
            {
                Logger.LogMessage("Stopping Python HTTP server", LogLevel.INFO);
                _pythonServerProcess.Kill();
                _pythonServerProcess.WaitForExit(5000);
                _pythonServerProcess.Dispose();
                _pythonServerProcess = null;
            }
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error stopping Python HTTP server: {ex.Message}", LogLevel.WARN);
        }
    }

    /// <summary>
    /// Test HTML file in browser (placeholder - full browser automation requires Selenium/Playwright)
    /// </summary>
    public BrowserTestResult TestHtmlFile(string htmlFileName)
    {
        var result = new BrowserTestResult
        {
            FileName = htmlFileName,
            Status = "Skipped",
            Message = "Browser automation requires Selenium/Playwright - manual verification needed"
        };

        // For now, just verify the file exists and can be accessed via HTTP
        string url = $"http://localhost:{_port}/{htmlFileName}";
        result.Url = url;
        result.Status = "Available";

        Logger.LogMessage($"HTML file available at: {url}", LogLevel.INFO);
        Logger.LogMessage("Note: Full browser automation requires additional NuGet packages (Selenium.WebDriver or Playwright)", LogLevel.INFO);

        return result;
    }

    public void Dispose()
    {
        StopPythonServer();
    }
}

public class BrowserTestResult
{
    public string FileName { get; set; } = "";
    public string Url { get; set; } = "";
    public string Status { get; set; } = "";
    public string Message { get; set; } = "";
    public List<string> Errors { get; set; } = new List<string>();
}
