using SqlMermaidErdTools.Exceptions;
using SqlMermaidErdTools.Runtime;
using SqlMermaidErdTools.ErrorHandling;
using System.Text.RegularExpressions;

namespace SqlMermaidErdTools.Converters;

/// <summary>
/// Base class for all converters providing common functionality.
/// </summary>
public abstract class BaseConverter
{
    /// <summary>
    /// Optional export folder path for debugging and auditing.
    /// If set, all intermediate files will be saved to this folder.
    /// </summary>
    public string? ExportFolderPath { get; set; }
    /// <summary>
    /// Cleans SQL by removing T-SQL/MS SQL Server/MS Access syntax issues.
    /// This makes the SQL more compatible with SQLGlot's parser.
    /// </summary>
    /// <param name="sql">SQL DDL to clean</param>
    /// <returns>Cleaned SQL with brackets removed and syntax normalized</returns>
    protected static string CleanSqlBrackets(string sql)
    {
        // Remove T-SQL brackets: [TableName] -> TableName
        sql = Regex.Replace(
            sql,
            @"\[([^\]]+)\]",
            "$1"
        );
        
        // Fix MS Access DEFAULT =Function() to DEFAULT Function()
        sql = Regex.Replace(
            sql,
            @"DEFAULT\s*=\s*",
            "DEFAULT ",
            RegexOptions.IgnoreCase
        );
        
        return sql;
    }

    /// <summary>
    /// Executes a Python script with a temporary file as input.
    /// </summary>
    /// <param name="scriptName">Name of the Python script to execute</param>
    /// <param name="inputContent">Content to write to the temp file</param>
    /// <param name="additionalArgs">Additional arguments to pass to the script</param>
    /// <returns>Output from the Python script</returns>
    /// <exception cref="ConversionException">Thrown when conversion fails</exception>
    protected static string ExecutePythonWithTempFile(
        string scriptName,
        string inputContent,
        string additionalArgs = "")
    {
        var tempFile = Path.GetTempFileName();
        
        try
        {
            File.WriteAllText(tempFile, inputContent);
            
            var args = $"\"{tempFile}\"";
            if (!string.IsNullOrEmpty(additionalArgs))
            {
                args += $" {additionalArgs}";
            }

            var result = RuntimeManager.ExecutePythonScript(scriptName, args);

            if (string.IsNullOrWhiteSpace(result))
            {
                throw new ConversionException($"{scriptName} produced no output");
            }

            return result.Trim();
        }
        finally
        {
            if (File.Exists(tempFile))
            {
                File.Delete(tempFile);
            }
        }
    }

    /// <summary>
    /// Executes a Python script with a temporary file as input asynchronously.
    /// </summary>
    /// <param name="scriptName">Name of the Python script to execute</param>
    /// <param name="inputContent">Content to write to the temp file</param>
    /// <param name="additionalArgs">Additional arguments to pass to the script</param>
    /// <param name="cancellationToken">Cancellation token</param>
    /// <param name="functionName">Function name for export file naming (optional)</param>
    /// <param name="inputSuffix">Suffix for input file (default: .sql)</param>
    /// <param name="outputSuffix">Suffix for output file (default: .sql)</param>
    /// <returns>Output from the Python script</returns>
    /// <exception cref="ConversionException">Thrown when conversion fails</exception>
    protected async Task<string> ExecutePythonWithTempFileAsync(
        string scriptName,
        string inputContent,
        string additionalArgs = "",
        CancellationToken cancellationToken = default,
        string? functionName = null,
        string inputSuffix = ".sql",
        string outputSuffix = ".sql")
    {
        var tempFile = Path.GetTempFileName();
        var astTempFile = Path.GetTempFileName();
        
        try
        {
            await File.WriteAllTextAsync(tempFile, inputContent, cancellationToken);
            
            // Export original input if folder is configured
            if (!string.IsNullOrWhiteSpace(ExportFolderPath) && !string.IsNullOrEmpty(functionName))
            {
                await ExportToFileAsync(
                    inputContent,
                    $"{functionName}-In{inputSuffix}",
                    $"Input to {functionName}",
                    cancellationToken
                );
                
                // Also export the content sent to SQLGlot (might be cleaned/modified)
                var timestamp = GetTimestamp();
                await ExportToFileAsync(
                    inputContent,
                    $"{functionName}-InToSqlGlot{timestamp}{inputSuffix}",
                    $"Input to SQLGlot for {functionName}",
                    cancellationToken
                );
            }
            
            var args = $"\"{tempFile}\"";
            if (!string.IsNullOrEmpty(additionalArgs))
            {
                args += $" {additionalArgs}";
            }
            
            // Add AST output file if export folder is configured
            if (!string.IsNullOrWhiteSpace(ExportFolderPath) && !string.IsNullOrEmpty(functionName))
            {
                args += $" \"{astTempFile}\"";
            }

            string result;
            try
            {
                result = await RuntimeManager.ExecutePythonScriptAsync(
                    scriptName,
                    args,
                    cancellationToken
                );
            }
            catch (Exception ex)
            {
                // FATAL ERROR: Python script execution failed - ALWAYS create error dump
                if (!string.IsNullOrEmpty(functionName))
                {
                    await ErrorDumpManager.CreateErrorDumpAsync(
                        functionName,
                        ExportFolderPath,
                        $"Python script '{scriptName}' execution failed",
                        ex,
                        inputContent,
                        inputSuffix
                    );
                }
                throw new ConversionException($"Python script '{scriptName}' execution failed: {ex.Message}", ex);
            }

            if (string.IsNullOrWhiteSpace(result))
            {
                // FATAL ERROR: SQLGlot produced no output - ALWAYS create error dump
                var errorMsg = $"{scriptName} produced no output - SQLGlot processing failed";
                
                if (!string.IsNullOrEmpty(functionName))
                {
                    await ErrorDumpManager.CreateErrorDumpAsync(
                        functionName,
                        ExportFolderPath,
                        errorMsg,
                        null,
                        inputContent,
                        inputSuffix
                    );
                }
                
                throw new ConversionException(errorMsg);
            }

            var trimmedResult = result.Trim();
            
            // Export output from SQLGlot, AST, and final result
            if (!string.IsNullOrWhiteSpace(ExportFolderPath) && !string.IsNullOrEmpty(functionName))
            {
                var timestamp = GetTimestamp();
                
                // Export AST if it was created (matching output file name)
                if (File.Exists(astTempFile) && new FileInfo(astTempFile).Length > 0)
                {
                    var astContent = await File.ReadAllTextAsync(astTempFile, cancellationToken);
                    await ExportToFileAsync(
                        astContent,
                        $"{functionName}-Out.ast",
                        $"SQLGlot AST for {functionName}",
                        cancellationToken
                    );
                }
                
                await ExportToFileAsync(
                    trimmedResult,
                    $"{functionName}-OutFromSqlGlot{timestamp}{outputSuffix}",
                    $"Output from SQLGlot for {functionName}",
                    cancellationToken
                );
                
                await ExportToFileAsync(
                    trimmedResult,
                    $"{functionName}-Out{outputSuffix}",
                    $"Final output from {functionName}",
                    cancellationToken
                );
                
                // If output is MMD, also create markdown file for VS Code preview
                if (outputSuffix.Equals(".mmd", StringComparison.OrdinalIgnoreCase))
                {
                    var markdownContent = WrapMmdInMarkdown(trimmedResult, functionName);
                    await ExportToFileAsync(
                        markdownContent,
                        $"{functionName}-Out.md",
                        $"Markdown preview for {functionName}",
                        cancellationToken
                    );
                }
            }

            return trimmedResult;
        }
        finally
        {
            if (File.Exists(tempFile))
            {
                File.Delete(tempFile);
            }
            if (File.Exists(astTempFile))
            {
                File.Delete(astTempFile);
            }
        }
    }

    /// <summary>
    /// Wraps Mermaid diagram content in Markdown for VS Code preview.
    /// </summary>
    /// <param name="mermaidContent">The Mermaid diagram content</param>
    /// <param name="title">Title for the markdown document</param>
    /// <returns>Markdown-formatted document with embedded Mermaid diagram</returns>
    private static string WrapMmdInMarkdown(string mermaidContent, string title)
    {
        var markdown = new System.Text.StringBuilder();
        
        markdown.AppendLine($"# {title}");
        markdown.AppendLine();
        markdown.AppendLine("Generated by SqlMermaidErdTools");
        markdown.AppendLine();
        markdown.AppendLine("```mermaid");
        markdown.AppendLine(mermaidContent);
        markdown.AppendLine("```");
        markdown.AppendLine();
        
        return markdown.ToString();
    }

    /// <summary>
    /// Validates that input is not null or empty.
    /// </summary>
    /// <param name="input">Input string to validate</param>
    /// <param name="paramName">Parameter name for exception message</param>
    /// <exception cref="ArgumentException">Thrown when input is null or empty</exception>
    protected static void ValidateInput(string input, string paramName)
    {
        if (string.IsNullOrWhiteSpace(input))
        {
            throw new ArgumentException($"{paramName} cannot be null or empty", paramName);
        }
    }

    /// <summary>
    /// Exports content to a file if export folder is configured.
    /// </summary>
    /// <param name="content">Content to export</param>
    /// <param name="fileName">File name</param>
    /// <param name="description">Optional description for logging</param>
    protected void ExportToFile(string content, string fileName, string? description = null)
    {
        if (string.IsNullOrWhiteSpace(ExportFolderPath))
        {
            return;
        }

        try
        {
            Directory.CreateDirectory(ExportFolderPath);
            
            // Sanitize file name - replace invalid characters
            var sanitizedFileName = fileName
                .Replace("<", "[")
                .Replace(">", "]")
                .Replace(":", "_")
                .Replace("\"", "'")
                .Replace("|", "_")
                .Replace("?", "_")
                .Replace("*", "_");
            
            var filePath = Path.Combine(ExportFolderPath, sanitizedFileName);
            File.WriteAllText(filePath, content);
            
            if (!string.IsNullOrEmpty(description))
            {
                Console.WriteLine($"[EXPORT] {description}: {sanitizedFileName}");
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[EXPORT WARNING] Failed to export {fileName}: {ex.Message}");
        }
    }

    /// <summary>
    /// Exports content to a file asynchronously if export folder is configured.
    /// </summary>
    /// <param name="content">Content to export</param>
    /// <param name="fileName">File name</param>
    /// <param name="description">Optional description for logging</param>
    /// <param name="cancellationToken">Cancellation token</param>
    protected async Task ExportToFileAsync(
        string content, 
        string fileName, 
        string? description = null,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(ExportFolderPath))
        {
            return;
        }

        try
        {
            Directory.CreateDirectory(ExportFolderPath);
            
            // Sanitize file name - replace invalid characters
            var sanitizedFileName = fileName
                .Replace("<", "[")
                .Replace(">", "]")
                .Replace(":", "_")
                .Replace("\"", "'")
                .Replace("|", "_")
                .Replace("?", "_")
                .Replace("*", "_");
            
            var filePath = Path.Combine(ExportFolderPath, sanitizedFileName);
            await File.WriteAllTextAsync(filePath, content, cancellationToken);
            
            if (!string.IsNullOrEmpty(description))
            {
                Console.WriteLine($"[EXPORT] {description}: {sanitizedFileName}");
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[EXPORT WARNING] Failed to export {fileName}: {ex.Message}");
        }
    }

    /// <summary>
    /// Gets a timestamp string for unique file naming.
    /// </summary>
    /// <returns>Timestamp in yyyyMMdd_HHmmss_fff format</returns>
    protected static string GetTimestamp()
    {
        return DateTime.Now.ToString("yyyyMMdd_HHmmss_fff");
    }

    /// <summary>
    /// Maps SqlDialect enum to SQLGlot dialect string.
    /// </summary>
    /// <param name="dialect">The SQL dialect enum</param>
    /// <returns>The SQLGlot dialect name</returns>
    protected static string MapDialectToSqlGlot(Models.SqlDialect dialect)
    {
        return dialect switch
        {
            Models.SqlDialect.AnsiSql => "",  // Empty string for standard SQL in SQLGlot
            Models.SqlDialect.SqlServer => "tsql",
            Models.SqlDialect.PostgreSql => "postgres",
            Models.SqlDialect.MySql => "mysql",
            Models.SqlDialect.Sqlite => "sqlite",
            Models.SqlDialect.Oracle => "oracle",
            _ => ""
        };
    }
}

