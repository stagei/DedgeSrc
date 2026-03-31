using System.Diagnostics;
using System.Reflection;
using System.Runtime.InteropServices;
using SqlMmdConverter.Exceptions;

namespace SqlMmdConverter.Runtime;

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

        if (!Directory.Exists(runtimePath))
        {
            throw new ConversionException(
                $"Runtime directory not found at {runtimePath}. " +
                "Please ensure the NuGet package was installed correctly.");
        }

        return runtimePath;
    }

    private static string InitializePythonPath()
    {
        var pythonExe = RuntimeInformation.IsOSPlatform(OSPlatform.Windows)
            ? "python.exe"
            : "bin/python3";

        var pythonPath = Path.Combine(RuntimePath, "python", pythonExe);

        if (!File.Exists(pythonPath))
        {
            throw new ConversionException(
                $"Python runtime not found at {pythonPath}. " +
                "Please ensure the NuGet package was installed correctly.");
        }

        return pythonPath;
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
        var scriptPath = Path.Combine(RuntimePath, "scripts", scriptName);

        if (!File.Exists(scriptPath))
        {
            throw new ConversionException($"Python script not found: {scriptPath}");
        }

        var psi = new ProcessStartInfo
        {
            FileName = PythonPath,
            Arguments = $"\"{scriptPath}\" {arguments}",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            WorkingDirectory = Path.Combine(RuntimePath, "python")
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
        var scriptPath = Path.Combine(RuntimePath, "scripts", scriptName);

        if (!File.Exists(scriptPath))
        {
            throw new ConversionException($"Python script not found: {scriptPath}");
        }

        var psi = new ProcessStartInfo
        {
            FileName = PythonPath,
            Arguments = $"\"{scriptPath}\" {arguments}",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            WorkingDirectory = Path.Combine(RuntimePath, "python")
        };

        return await ExecuteProcessAsync(psi, "Python", cancellationToken);
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

