using System.Diagnostics;
using System.Reflection;
using System.Runtime.InteropServices;
using SqlMermaidErdTools.Exceptions;

namespace SqlMermaidErdTools.Runtime;

/// <summary>
/// Manages execution of bundled Python runtime for SQL parsing and conversion.
/// </summary>
public static class RuntimeManager
{
    private static readonly Lazy<string> _runtimePath = new(() => InitializeRuntimePath());
    private static readonly Lazy<string> _pythonPath = new(() => InitializePythonPath());

    /// <summary>
    /// Gets the runtime base directory path.
    /// </summary>
    public static string RuntimePath => _runtimePath.Value;

    /// <summary>
    /// Gets the Python executable path.
    /// </summary>
    public static string PythonPath => _pythonPath.Value;

    private static string InitializeRuntimePath()
    {
        var assemblyPath = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location)
            ?? throw new ConversionException("Could not determine assembly location");

        var rid = GetRuntimeIdentifier();
        var runtimePath = Path.Combine(assemblyPath, "runtimes", rid);

        // Development mode: If runtime directory doesn't exist, use assembly directory for scripts
        if (!Directory.Exists(runtimePath))
        {
            // Check if scripts directory exists in assembly path (development mode)
            var devScriptsPath = Path.Combine(assemblyPath, "scripts");
            if (Directory.Exists(devScriptsPath))
            {
                // Return assembly path as runtime path for development mode
                return assemblyPath;
            }

            throw new ConversionException(
                $"Runtime directory not found at {runtimePath} and development scripts not found at {devScriptsPath}. " +
                "Please ensure the NuGet package was installed correctly or build the project.");
        }

        return runtimePath;
    }

    private static string InitializePythonPath()
    {
        var pythonExe = RuntimeInformation.IsOSPlatform(OSPlatform.Windows)
            ? "python.exe"
            : "bin/python3";

        var pythonPath = Path.Combine(RuntimePath, "python", pythonExe);

        // Development mode: If bundled Python doesn't exist, try system Python
        if (!File.Exists(pythonPath))
        {
            // Try to find system Python
            var systemPython = FindSystemPython();
            if (systemPython != null)
            {
                return systemPython;
            }

            throw new ConversionException(
                $"Python runtime not found at {pythonPath} and system Python not available. " +
                "Please ensure the NuGet package was installed correctly or install Python.");
        }

        return pythonPath;
    }

    private static string? FindSystemPython()
    {
        var pythonCommands = RuntimeInformation.IsOSPlatform(OSPlatform.Windows)
            ? new[] { "python.exe", "python3.exe", "py.exe" }
            : new[] { "python3", "python" };

        foreach (var cmd in pythonCommands)
        {
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = cmd,
                    Arguments = "--version",
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true
                };

                using var process = Process.Start(psi);
                if (process != null)
                {
                    process.WaitForExit(2000); // 2 second timeout
                    if (process.ExitCode == 0)
                    {
                        return cmd;
                    }
                }
            }
            catch
            {
                // Continue to next command
            }
        }

        return null;
    }


    private static string GetRuntimeIdentifier()
    {
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            return RuntimeInformation.ProcessArchitecture == Architecture.X64
                ? "win-x64"
                : "win-x86";
        }

        if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
        {
            return "linux-x64";
        }

        if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
        {
            return "osx-x64";
        }

        throw new PlatformNotSupportedException(
            $"Unsupported platform: {RuntimeInformation.OSDescription}");
    }

    /// <summary>
    /// Executes a Python script with the bundled Python runtime.
    /// </summary>
    /// <param name="scriptName">Name of the Python script to execute</param>
    /// <param name="arguments">Arguments to pass to the script</param>
    /// <returns>The standard output from the script</returns>
    /// <exception cref="ConversionException">Thrown when script execution fails</exception>
    public static string ExecutePythonScript(string scriptName, string arguments = "")
    {
        var scriptPath = FindScriptPath(scriptName);
        var workingDir = GetWorkingDirectory();

        var psi = new ProcessStartInfo
        {
            FileName = PythonPath,
            Arguments = $"\"{scriptPath}\" {arguments}",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            WorkingDirectory = workingDir
        };

        return ExecuteProcess(psi, "Python");
    }

    /// <summary>
    /// Executes a Python script asynchronously with the bundled Python runtime.
    /// </summary>
    /// <param name="scriptName">Name of the Python script to execute</param>
    /// <param name="arguments">Arguments to pass to the script</param>
    /// <param name="cancellationToken">Cancellation token</param>
    /// <returns>The standard output from the script</returns>
    /// <exception cref="ConversionException">Thrown when script execution fails</exception>
    public static async Task<string> ExecutePythonScriptAsync(
        string scriptName,
        string arguments = "",
        CancellationToken cancellationToken = default)
    {
        var scriptPath = FindScriptPath(scriptName);
        var workingDir = GetWorkingDirectory();

        var psi = new ProcessStartInfo
        {
            FileName = PythonPath,
            Arguments = $"\"{scriptPath}\" {arguments}",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            WorkingDirectory = workingDir
        };

        return await ExecuteProcessAsync(psi, "Python", cancellationToken);
    }

    /// <summary>
    /// Finds the path to a Python script, checking both runtime and development locations.
    /// </summary>
    private static string FindScriptPath(string scriptName)
    {
        // Try runtime scripts directory first (production mode)
        var runtimeScriptPath = Path.Combine(RuntimePath, "scripts", scriptName);
        if (File.Exists(runtimeScriptPath))
        {
            return runtimeScriptPath;
        }

        // Try assembly scripts directory (development mode)
        var assemblyPath = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location)
            ?? throw new ConversionException("Could not determine assembly location");
        var devScriptPath = Path.Combine(assemblyPath, "scripts", scriptName);
        if (File.Exists(devScriptPath))
        {
            return devScriptPath;
        }

        throw new ConversionException(
            $"Python script not found: {scriptName}. " +
            $"Checked: {runtimeScriptPath}, {devScriptPath}");
    }

    /// <summary>
    /// Gets the working directory for Python script execution.
    /// </summary>
    private static string GetWorkingDirectory()
    {
        // In production mode, use the Python runtime directory
        var pythonDir = Path.Combine(RuntimePath, "python");
        if (Directory.Exists(pythonDir))
        {
            return pythonDir;
        }

        // In development mode, use the scripts directory
        var scriptsDir = Path.Combine(RuntimePath, "scripts");
        if (Directory.Exists(scriptsDir))
        {
            return scriptsDir;
        }

        // Fallback to runtime path
        return RuntimePath;
    }


    private static string ExecuteProcess(ProcessStartInfo psi, string runtimeName)
    {
        using var process = Process.Start(psi)
            ?? throw new ConversionException($"Failed to start {runtimeName} process");

        var output = process.StandardOutput.ReadToEnd();
        var error = process.StandardError.ReadToEnd();

        process.WaitForExit();

        if (process.ExitCode != 0)
        {
            throw new ConversionException(
                $"{runtimeName} script execution failed (exit code {process.ExitCode}):\n{error}");
        }

        return output;
    }

    private static async Task<string> ExecuteProcessAsync(
        ProcessStartInfo psi,
        string runtimeName,
        CancellationToken cancellationToken)
    {
        using var process = Process.Start(psi)
            ?? throw new ConversionException($"Failed to start {runtimeName} process");

        var outputTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var errorTask = process.StandardError.ReadToEndAsync(cancellationToken);

        await process.WaitForExitAsync(cancellationToken);

        var output = await outputTask;
        var error = await errorTask;

        if (process.ExitCode != 0)
        {
            throw new ConversionException(
                $"{runtimeName} script execution failed (exit code {process.ExitCode}):\n{error}");
        }

        return output;
    }
}

