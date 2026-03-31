using System;
using System.IO;
using System.Threading.Tasks;
using NLog;

namespace DbExplorer.Services;

/// <summary>
/// Helper class for CLI file I/O operations
/// </summary>
public static class CliFileHelper
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    /// <summary>
    /// Read content from a file
    /// </summary>
    public static async Task<string> ReadFileAsync(string filePath)
    {
        try
        {
            if (!File.Exists(filePath))
            {
                throw new FileNotFoundException($"Input file not found: {filePath}");
            }
            
            Logger.Debug("Reading file: {Path}", filePath);
            var content = await File.ReadAllTextAsync(filePath);
            Logger.Info("Read {Length} characters from: {Path}", content.Length, filePath);
            
            return content;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to read file: {Path}", filePath);
            throw;
        }
    }
    
    /// <summary>
    /// Write content to a file
    /// </summary>
    public static async Task WriteFileAsync(string filePath, string content)
    {
        try
        {
            Logger.Debug("Writing to file: {Path} ({Length} chars)", filePath, content.Length);
            
            // Ensure directory exists
            var directory = Path.GetDirectoryName(filePath);
            if (!string.IsNullOrEmpty(directory) && !Directory.Exists(directory))
            {
                Directory.CreateDirectory(directory);
                Logger.Debug("Created directory: {Directory}", directory);
            }
            
            await File.WriteAllTextAsync(filePath, content);
            Logger.Info("Wrote {Length} characters to: {Path}", content.Length, filePath);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to write file: {Path}", filePath);
            throw;
        }
    }
    
    /// <summary>
    /// Read file if path is provided, otherwise return the content as-is
    /// </summary>
    public static async Task<string> ReadFileOrContentAsync(string contentOrPath, bool isFilePath = false)
    {
        if (isFilePath || File.Exists(contentOrPath))
        {
            return await ReadFileAsync(contentOrPath);
        }
        
        return contentOrPath;
    }
    
    /// <summary>
    /// Generate output filename based on input and operation
    /// </summary>
    public static string GenerateOutputFilename(string baseDir, string operation, string extension)
    {
        var timestamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
        var filename = $"{operation}_{timestamp}.{extension}";
        return Path.Combine(baseDir, filename);
    }
    
    /// <summary>
    /// Ensure file has correct extension
    /// </summary>
    public static string EnsureExtension(string filePath, string expectedExtension)
    {
        var ext = Path.GetExtension(filePath);
        if (string.IsNullOrEmpty(ext))
        {
            return $"{filePath}.{expectedExtension}";
        }
        return filePath;
    }
}

