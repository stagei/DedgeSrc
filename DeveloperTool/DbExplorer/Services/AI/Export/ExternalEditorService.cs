using NLog;
using System;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;

namespace DbExplorer.Services.AI.Export;

/// <summary>
/// Service for opening exported files in external editors (Cursor/VS Code).
/// </summary>
public class ExternalEditorService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    public enum ExternalEditor
    {
        Cursor,
        VSCode,
        SystemDefault
    }
    
    /// <summary>
    /// Open a file in the specified external editor.
    /// </summary>
    public async Task<bool> OpenInEditorAsync(string filePath, ExternalEditor editor, string? editorPath = null)
    {
        Logger.Info("Opening file in {Editor}: {Path}", editor, filePath);
        
        if (!File.Exists(filePath))
        {
            Logger.Error("File does not exist: {Path}", filePath);
            return false;
        }
        
        try
        {
            var editorCommand = GetEditorCommand(editor, editorPath);
            
            if (string.IsNullOrWhiteSpace(editorCommand))
            {
                Logger.Warn("Editor command not found, using system default");
                return await OpenWithSystemDefaultAsync(filePath);
            }
            
            var processInfo = new ProcessStartInfo
            {
                FileName = editorCommand,
                Arguments = $"\"{filePath}\"",
                UseShellExecute = false,
                CreateNoWindow = true
            };
            
            var process = Process.Start(processInfo);
            
            if (process != null)
            {
                Logger.Info("✅ Opened file in {Editor}", editor);
                return true;
            }
            else
            {
                Logger.Error("Failed to start editor process");
                return false;
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to open file in external editor");
            
            // Fallback to system default
            return await OpenWithSystemDefaultAsync(filePath);
        }
    }
    
    /// <summary>
    /// Open with system default application.
    /// </summary>
    private async Task<bool> OpenWithSystemDefaultAsync(string filePath)
    {
        Logger.Info("Opening with system default: {Path}", filePath);
        
        try
        {
            var processInfo = new ProcessStartInfo
            {
                FileName = filePath,
                UseShellExecute = true
            };
            
            Process.Start(processInfo);
            
            Logger.Info("✅ Opened with system default");
            return true;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to open with system default");
            return false;
        }
    }
    
    /// <summary>
    /// Get editor command path.
    /// </summary>
    private string? GetEditorCommand(ExternalEditor editor, string? customPath)
    {
        // If custom path provided, use it
        if (!string.IsNullOrWhiteSpace(customPath) && File.Exists(customPath))
        {
            Logger.Debug("Using custom editor path: {Path}", customPath);
            return customPath;
        }
        
        // Otherwise, try to find the editor
        return editor switch
        {
            ExternalEditor.Cursor => FindCursorPath(),
            ExternalEditor.VSCode => FindVSCodePath(),
            _ => null
        };
    }
    
    /// <summary>
    /// Find Cursor installation path.
    /// </summary>
    private string? FindCursorPath()
    {
        Logger.Debug("Searching for Cursor installation");
        
        // Common Cursor installation paths
        var possiblePaths = new[]
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), 
                "Programs", "Cursor", "Cursor.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), 
                "Cursor", "Cursor.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), 
                "Cursor", "Cursor.exe"),
            @"C:\Users\" + Environment.UserName + @"\AppData\Local\Programs\Cursor\Cursor.exe"
        };
        
        foreach (var path in possiblePaths)
        {
            if (File.Exists(path))
            {
                Logger.Info("Found Cursor at: {Path}", path);
                return path;
            }
        }
        
        // Try 'cursor' command (if in PATH)
        try
        {
            var processInfo = new ProcessStartInfo
            {
                FileName = "where",
                Arguments = "cursor",
                RedirectStandardOutput = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            
            using var process = Process.Start(processInfo);
            if (process != null)
            {
                var output = process.StandardOutput.ReadToEnd().Trim();
                process.WaitForExit();
                
                if (!string.IsNullOrWhiteSpace(output) && File.Exists(output))
                {
                    Logger.Info("Found Cursor in PATH: {Path}", output);
                    return output;
                }
            }
        }
        catch (Exception ex)
        {
            Logger.Debug(ex, "Failed to search for Cursor in PATH");
        }
        
        Logger.Warn("Cursor not found");
        return null;
    }
    
    /// <summary>
    /// Find VS Code installation path.
    /// </summary>
    private string? FindVSCodePath()
    {
        Logger.Debug("Searching for VS Code installation");
        
        // Common VS Code installation paths
        var possiblePaths = new[]
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), 
                "Programs", "Microsoft VS Code", "Code.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), 
                "Microsoft VS Code", "Code.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), 
                "Microsoft VS Code", "Code.exe"),
            @"C:\Users\" + Environment.UserName + @"\AppData\Local\Programs\Microsoft VS Code\Code.exe"
        };
        
        foreach (var path in possiblePaths)
        {
            if (File.Exists(path))
            {
                Logger.Info("Found VS Code at: {Path}", path);
                return path;
            }
        }
        
        // Try 'code' command (if in PATH)
        try
        {
            var processInfo = new ProcessStartInfo
            {
                FileName = "where",
                Arguments = "code",
                RedirectStandardOutput = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            
            using var process = Process.Start(processInfo);
            if (process != null)
            {
                var output = process.StandardOutput.ReadToEnd().Trim();
                process.WaitForExit();
                
                if (!string.IsNullOrWhiteSpace(output) && File.Exists(output))
                {
                    Logger.Info("Found VS Code in PATH: {Path}", output);
                    return output;
                }
            }
        }
        catch (Exception ex)
        {
            Logger.Debug(ex, "Failed to search for VS Code in PATH");
        }
        
        Logger.Warn("VS Code not found");
        return null;
    }
    
    /// <summary>
    /// Check if an editor is available.
    /// </summary>
    public bool IsEditorAvailable(ExternalEditor editor, string? customPath = null)
    {
        var command = GetEditorCommand(editor, customPath);
        var available = !string.IsNullOrWhiteSpace(command);
        
        Logger.Debug("{Editor} availability: {Available}", editor, available);
        return available;
    }
}

