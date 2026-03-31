using System.IO.Compression;

namespace SqlMermaidErdTools.ErrorHandling;

/// <summary>
/// Manages creation of error dump files when SQLGlot processing fails.
/// </summary>
public static class ErrorDumpManager
{
    private static readonly string RuntimeDirectory = AppContext.BaseDirectory;
    private static readonly string LogFileName = "SqlMermaidErdTools.log";
    
    /// <summary>
    /// Gets the workspace/project root directory.
    /// This is where the ErrorDump folder will be created.
    /// </summary>
    private static string GetWorkspaceRoot()
    {
        // Start from runtime directory and navigate up to find workspace root
        var runtimeDir = new DirectoryInfo(RuntimeDirectory);
        var current = runtimeDir;
        
        // Navigate up looking for solution file (.sln) or .git directory
        while (current != null)
        {
            // Check if this is the workspace root (has .sln or .git)
            if (current.GetFiles("*.sln").Any() || current.GetDirectories(".git").Any())
            {
                return current.FullName;
            }
            
            current = current.Parent;
        }
        
        // Fallback: navigate up from bin/Debug|Release/net10.0 structure (typically 3-4 levels)
        current = runtimeDir;
        for (int i = 0; i < 4 && current?.Parent != null; i++)
        {
            current = current.Parent;
            if (current.GetFiles("*.sln").Any() || current.GetDirectories(".git").Any())
            {
                return current.FullName;
            }
        }
        
        // Last resort: use current directory
        return Environment.CurrentDirectory;
    }
    
    /// <summary>
    /// Creates an error dump when SQLGlot fails to produce output.
    /// </summary>
    /// <param name="functionName">Name of the function that failed</param>
    /// <param name="exportFolderPath">Path to export folder with intermediate files (optional)</param>
    /// <param name="errorMessage">Error message from the failure</param>
    /// <param name="exception">Exception that occurred (optional)</param>
    /// <param name="inputContent">Input content sent to SQLGlot (optional)</param>
    /// <param name="inputSuffix">Suffix for input file (optional)</param>
    /// <returns>Path to the created error dump zip file</returns>
    public static async Task<string> CreateErrorDumpAsync(
        string functionName,
        string? exportFolderPath,
        string errorMessage,
        Exception? exception = null,
        string? inputContent = null,
        string? inputSuffix = null)
    {
        var timestamp = DateTime.Now.ToString("yyyyMMdd_HHmmss_fff");
        var tmpFolderName = $"Tmp_{timestamp}";
        var tmpFolderPath = Path.Combine(RuntimeDirectory, tmpFolderName);
        
        // ErrorDump folder is ALWAYS at workspace root level, not in export folder
        var workspaceRoot = GetWorkspaceRoot();
        var errorDumpFolder = Path.Combine(workspaceRoot, "ErrorDump");
        
        var dumpFileName = $"ErrorDump_{functionName}_{timestamp}";
        var dumpZipPath = Path.Combine(errorDumpFolder, $"{dumpFileName}.zip");
        var dumpTxtPath = Path.Combine(errorDumpFolder, $"{dumpFileName}.txt");
        
        try
        {
            // 1. Create ErrorDump folder if it doesn't exist
            Directory.CreateDirectory(errorDumpFolder);
            
            // 2. Create Tmp\<timestamp> folder
            Directory.CreateDirectory(tmpFolderPath);
            
            LogMessage($"FATAL ERROR in {functionName}: {errorMessage}", isError: true);
            if (exception != null)
            {
                LogMessage($"Exception details: {exception}", isError: true);
            }
            
            // 3. Create error details file in tmp folder
            var errorDetailsPath = Path.Combine(tmpFolderPath, "ERROR_DETAILS.txt");
            await File.WriteAllTextAsync(errorDetailsPath, GetErrorDetails(functionName, errorMessage, exception));
            
            // 4. Copy common log file to Tmp folder (if it exists)
            var logFilePath = Path.Combine(RuntimeDirectory, LogFileName);
            if (File.Exists(logFilePath))
            {
                var destLogPath = Path.Combine(tmpFolderPath, LogFileName);
                File.Copy(logFilePath, destLogPath, overwrite: true);
                LogMessage($"Copied log file to dump: {LogFileName}");
            }
            
            // 5. Save SQLGlot input if provided (even without export folder)
            if (!string.IsNullOrWhiteSpace(inputContent) && !string.IsNullOrWhiteSpace(inputSuffix))
            {
                var inputFileName = $"{functionName}-InputToSqlGlot{timestamp}{inputSuffix}";
                var inputFilePath = Path.Combine(tmpFolderPath, inputFileName);
                await File.WriteAllTextAsync(inputFilePath, inputContent);
                LogMessage($"Saved SQLGlot input: {inputFileName}");
            }
            
            // 6. Copy all files from export directory to Tmp folder (if export folder exists)
            if (!string.IsNullOrWhiteSpace(exportFolderPath) && Directory.Exists(exportFolderPath))
            {
                var exportDestPath = Path.Combine(tmpFolderPath, "ExportedFiles");
                Directory.CreateDirectory(exportDestPath);
                CopyDirectory(exportFolderPath, exportDestPath, recursive: true);
                LogMessage($"Copied export files from: {exportFolderPath}");
            }
            
            // 7. Zip the Tmp folder and move to ErrorDump folder
            if (File.Exists(dumpZipPath))
            {
                File.Delete(dumpZipPath);
            }
            ZipFile.CreateFromDirectory(tmpFolderPath, dumpZipPath, CompressionLevel.Optimal, includeBaseDirectory: true);
            LogMessage($"Created error dump zip: {dumpZipPath}");
            
            // 8. Remove the Tmp folder
            Directory.Delete(tmpFolderPath, recursive: true);
            LogMessage($"Cleaned up temporary folder: {tmpFolderName}");
            
            // 9. Add text file with support instructions
            await File.WriteAllTextAsync(dumpTxtPath, GetSupportInstructions(dumpFileName));
            LogMessage($"Created support instructions: {dumpTxtPath}");
            
            // 10. Log that dump has been created
            LogMessage($"ERROR DUMP CREATED: {dumpFileName}.zip and {dumpFileName}.txt in {errorDumpFolder}", isError: true);
            LogMessage($"Please refer to {dumpFileName}.txt for instructions on how to submit this error dump for support.", isError: true);
            
            return dumpZipPath;
        }
        catch (Exception ex)
        {
            LogMessage($"CRITICAL: Failed to create error dump: {ex.Message}", isError: true);
            
            // Cleanup tmp folder if it exists
            try
            {
                if (Directory.Exists(tmpFolderPath))
                {
                    Directory.Delete(tmpFolderPath, recursive: true);
                }
            }
            catch
            {
                // Ignore cleanup errors
            }
            
            throw;
        }
    }
    
    private static string GetErrorDetails(string functionName, string errorMessage, Exception? exception)
    {
        var details = new System.Text.StringBuilder();
        details.AppendLine("═══════════════════════════════════════════════════════════════");
        details.AppendLine("                    SQLGlot Error Dump                        ");
        details.AppendLine("═══════════════════════════════════════════════════════════════");
        details.AppendLine();
        details.AppendLine($"Timestamp: {DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}");
        details.AppendLine($"Function: {functionName}");
        details.AppendLine($"Error: {errorMessage}");
        details.AppendLine();
        
        if (exception != null)
        {
            details.AppendLine("Exception Details:");
            details.AppendLine("───────────────────────────────────────────────────────────────");
            details.AppendLine($"Type: {exception.GetType().FullName}");
            details.AppendLine($"Message: {exception.Message}");
            details.AppendLine();
            details.AppendLine("Stack Trace:");
            details.AppendLine(exception.StackTrace);
            
            if (exception.InnerException != null)
            {
                details.AppendLine();
                details.AppendLine("Inner Exception:");
                details.AppendLine($"Type: {exception.InnerException.GetType().FullName}");
                details.AppendLine($"Message: {exception.InnerException.Message}");
                details.AppendLine(exception.InnerException.StackTrace);
            }
        }
        
        details.AppendLine();
        details.AppendLine("═══════════════════════════════════════════════════════════════");
        details.AppendLine("Environment Information:");
        details.AppendLine("═══════════════════════════════════════════════════════════════");
        details.AppendLine($"OS: {Environment.OSVersion}");
        details.AppendLine($"Machine Name: {Environment.MachineName}");
        details.AppendLine($"User: {Environment.UserName}");
        details.AppendLine($".NET Version: {Environment.Version}");
        details.AppendLine($"Working Directory: {Environment.CurrentDirectory}");
        details.AppendLine($"Runtime Directory: {RuntimeDirectory}");
        details.AppendLine();
        
        return details.ToString();
    }
    
    private static string GetSupportInstructions(string dumpFileName)
    {
        return $@"═══════════════════════════════════════════════════════════════
                  SqlMermaidErdTools Error Dump
═══════════════════════════════════════════════════════════════

An error occurred during SQL/Mermaid conversion processing.

Error Dump File: {dumpFileName}.zip

─────────────────────────────────────────────────────────────

SUPPORT INFORMATION

If you have a support agreement with Dedge Solutions, please:

1. Email the error dump file ({dumpFileName}.zip) to:
   
   SqlMermaidErdTools@dedge.no

2. Include the following information in your email:
   - Brief description of what you were trying to do
   - Input file type (SQL/Mermaid)
   - Target output type
   - Any custom settings or configurations used

3. Our support team will analyze the error dump and respond
   within the agreed support SLA timeframe.

─────────────────────────────────────────────────────────────

NO SUPPORT AGREEMENT?

If you don't have a support agreement but need assistance:
- Visit: https://github.com/dedge-space/SqlMermaidErdTools
- File an issue with details about the error
- Attach the error dump file if possible (check for sensitive data first)

─────────────────────────────────────────────────────────────

PRIVACY NOTE

The error dump contains:
- Input files you provided
- Intermediate processing files
- Application logs
- System environment information

Please review the contents before sharing if your data is sensitive.

═══════════════════════════════════════════════════════════════
Generated: {DateTime.Now:yyyy-MM-dd HH:mm:ss}
Version: SqlMermaidErdTools 0.1.0
═══════════════════════════════════════════════════════════════
";
    }
    
    private static void CopyDirectory(string sourceDir, string destDir, bool recursive)
    {
        var dir = new DirectoryInfo(sourceDir);
        
        if (!dir.Exists)
        {
            return;
        }
        
        Directory.CreateDirectory(destDir);
        
        // Copy files
        foreach (var file in dir.GetFiles())
        {
            var targetFilePath = Path.Combine(destDir, file.Name);
            file.CopyTo(targetFilePath, overwrite: true);
        }
        
        // Copy subdirectories
        if (recursive)
        {
            foreach (var subDir in dir.GetDirectories())
            {
                var newDestDir = Path.Combine(destDir, subDir.Name);
                CopyDirectory(subDir.FullName, newDestDir, recursive);
            }
        }
    }
    
    private static void LogMessage(string message, bool isError = false)
    {
        var timestamp = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff");
        var level = isError ? "ERROR" : "INFO";
        var logEntry = $"[{timestamp}] [{level}] {message}";
        
        // Write to console
        if (isError)
        {
            Console.Error.WriteLine(logEntry);
        }
        else
        {
            Console.WriteLine(logEntry);
        }
        
        // Also write to log file
        try
        {
            var logFilePath = Path.Combine(RuntimeDirectory, LogFileName);
            File.AppendAllText(logFilePath, logEntry + Environment.NewLine);
        }
        catch
        {
            // Ignore log file write errors
        }
    }
}

