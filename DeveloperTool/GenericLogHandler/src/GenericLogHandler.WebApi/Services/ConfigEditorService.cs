using System.Text.Json;

namespace GenericLogHandler.WebApi.Services;

/// <summary>
/// Service for loading and saving configuration files with backup support.
/// Mirrors ServerMonitor Dashboard ConfigEditorService pattern.
/// </summary>
public class ConfigEditorService
{
    private readonly ILogger<ConfigEditorService> _logger;
    private readonly IWebHostEnvironment _env;
    private readonly string _contentRoot;
    private readonly string _backupPath;

    public ConfigEditorService(ILogger<ConfigEditorService> logger, IWebHostEnvironment env)
    {
        _logger = logger;
        _env = env;
        _contentRoot = env.ContentRootPath ?? AppContext.BaseDirectory;
        _backupPath = Path.Combine(_contentRoot, "Backup");
    }

    /// <summary>
    /// Path to appsettings.json (local to Web API)
    /// </summary>
    public string AppSettingsPath => Path.Combine(_contentRoot, "appsettings.json");

    /// <summary>
    /// Path to import-config.json. Prefer repo root (parent of src) so it matches Import Service.
    /// </summary>
    public string ImportConfigPath
    {
        get
        {
            var inContentRoot = Path.Combine(_contentRoot, "import-config.json");
            if (File.Exists(inContentRoot))
                return inContentRoot;
            var repoRoot = GetRepositoryRoot("import-config.json");
            return string.IsNullOrEmpty(repoRoot) ? inContentRoot : Path.Combine(repoRoot, "import-config.json");
        }
    }

    private static string? GetRepositoryRoot(string fileName)
    {
        var searchDirs = new[]
        {
            Path.GetDirectoryName(Environment.ProcessPath),
            AppContext.BaseDirectory,
            Directory.GetCurrentDirectory()
        };
        foreach (var start in searchDirs)
        {
            if (string.IsNullOrEmpty(start)) continue;
            var dir = start;
            for (int i = 0; i < 6 && !string.IsNullOrEmpty(dir); i++)
            {
                var candidate = Path.Combine(dir, fileName);
                if (File.Exists(candidate))
                    return dir;
                dir = Path.GetDirectoryName(dir);
            }
        }
        return null;
    }

    public async Task<ConfigFileResult> LoadConfigAsync(ConfigFileType fileType)
    {
        var filePath = GetFilePath(fileType);

        try
        {
            if (!File.Exists(filePath))
            {
                _logger.LogWarning("Config file not found: {Path}", filePath);
                return new ConfigFileResult
                {
                    Success = false,
                    Error = $"Configuration file not found: {Path.GetFileName(filePath)}",
                    FilePath = filePath
                };
            }

            var content = await File.ReadAllTextAsync(filePath);

            try
            {
                using var doc = JsonDocument.Parse(content);
            }
            catch (JsonException ex)
            {
                _logger.LogWarning(ex, "Invalid JSON in config file: {Path}", filePath);
                return new ConfigFileResult
                {
                    Success = false,
                    Error = $"Invalid JSON format: {ex.Message}",
                    FilePath = filePath,
                    Content = content
                };
            }

            var fileInfo = new FileInfo(filePath);

            return new ConfigFileResult
            {
                Success = true,
                Content = content,
                FilePath = filePath,
                LastModified = fileInfo.LastWriteTimeUtc,
                FileSize = fileInfo.Length
            };
        }
        catch (UnauthorizedAccessException ex)
        {
            _logger.LogError(ex, "Access denied to config file: {Path}", filePath);
            return new ConfigFileResult
            {
                Success = false,
                Error = "Access denied. Check file permissions.",
                FilePath = filePath
            };
        }
        catch (IOException ex)
        {
            _logger.LogError(ex, "IO error reading config file: {Path}", filePath);
            return new ConfigFileResult
            {
                Success = false,
                Error = $"Could not read file: {ex.Message}",
                FilePath = filePath
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error loading config file: {Path}", filePath);
            return new ConfigFileResult
            {
                Success = false,
                Error = $"Unexpected error: {ex.Message}",
                FilePath = filePath
            };
        }
    }

    public async Task<ConfigSaveResult> SaveConfigAsync(ConfigFileType fileType, string content, string? editedBy = null)
    {
        var filePath = GetFilePath(fileType);

        try
        {
            try
            {
                using var doc = JsonDocument.Parse(content);
            }
            catch (JsonException ex)
            {
                _logger.LogWarning("Attempted to save invalid JSON: {Error}", ex.Message);
                return new ConfigSaveResult
                {
                    Success = false,
                    Error = $"Invalid JSON format: {ex.Message}"
                };
            }

            if (!Directory.Exists(_backupPath))
            {
                Directory.CreateDirectory(_backupPath);
                _logger.LogInformation("Created backup directory: {Path}", _backupPath);
            }

            string? backupFilePath = null;
            if (File.Exists(filePath))
            {
                var timestamp = DateTime.Now.ToString("yyyy-MM-dd_HHmmss");
                var fileName = Path.GetFileNameWithoutExtension(filePath);
                var extension = Path.GetExtension(filePath);
                var backupFileName = $"{timestamp}_{fileName}{extension}";
                backupFilePath = Path.Combine(_backupPath, backupFileName);

                File.Copy(filePath, backupFilePath, overwrite: true);
                _logger.LogInformation("Created backup: {BackupPath}", backupFilePath);
            }

            string formattedContent;
            try
            {
                using var doc = JsonDocument.Parse(content);
                formattedContent = JsonSerializer.Serialize(doc, new JsonSerializerOptions
                {
                    WriteIndented = true
                });
            }
            catch
            {
                formattedContent = content;
            }

            await File.WriteAllTextAsync(filePath, formattedContent);

            var fileInfo = new FileInfo(filePath);

            _logger.LogInformation("Saved config file: {Path} (backup: {Backup}, editedBy: {EditedBy})",
                filePath, backupFilePath ?? "none", editedBy ?? "unknown");

            return new ConfigSaveResult
            {
                Success = true,
                FilePath = filePath,
                BackupPath = backupFilePath,
                LastModified = fileInfo.LastWriteTimeUtc,
                FileSize = fileInfo.Length
            };
        }
        catch (UnauthorizedAccessException ex)
        {
            _logger.LogError(ex, "Access denied saving config file: {Path}", filePath);
            return new ConfigSaveResult
            {
                Success = false,
                Error = "Access denied. Check file permissions."
            };
        }
        catch (IOException ex)
        {
            _logger.LogError(ex, "IO error saving config file: {Path}", filePath);
            return new ConfigSaveResult
            {
                Success = false,
                Error = $"Could not save file: {ex.Message}"
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error saving config file: {Path}", filePath);
            return new ConfigSaveResult
            {
                Success = false,
                Error = $"Unexpected error: {ex.Message}"
            };
        }
    }

    public List<BackupFileInfo> GetBackupFiles()
    {
        var backups = new List<BackupFileInfo>();

        try
        {
            if (!Directory.Exists(_backupPath))
                return backups;

            var files = Directory.GetFiles(_backupPath, "*.json")
                .OrderByDescending(f => f)
                .Take(50);

            foreach (var file in files)
            {
                var fileInfo = new FileInfo(file);
                backups.Add(new BackupFileInfo
                {
                    FileName = Path.GetFileName(file),
                    FilePath = file,
                    CreatedAt = fileInfo.CreationTimeUtc,
                    FileSize = fileInfo.Length
                });
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error listing backup files");
        }

        return backups;
    }

    public async Task<ConfigSaveResult> RestoreBackupAsync(string backupFileName, ConfigFileType fileType)
    {
        var backupFilePath = Path.Combine(_backupPath, backupFileName);

        try
        {
            if (!File.Exists(backupFilePath))
            {
                return new ConfigSaveResult
                {
                    Success = false,
                    Error = "Backup file not found"
                };
            }

            var content = await File.ReadAllTextAsync(backupFilePath);
            return await SaveConfigAsync(fileType, content, "restore");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error restoring backup: {BackupFile}", backupFileName);
            return new ConfigSaveResult
            {
                Success = false,
                Error = $"Restore failed: {ex.Message}"
            };
        }
    }

    private string GetFilePath(ConfigFileType fileType)
    {
        return fileType switch
        {
            ConfigFileType.AppSettings => AppSettingsPath,
            ConfigFileType.ImportConfig => ImportConfigPath,
            _ => throw new ArgumentException($"Unknown config file type: {fileType}")
        };
    }
}

public enum ConfigFileType
{
    AppSettings,
    ImportConfig
}

public class ConfigFileResult
{
    public bool Success { get; set; }
    public string? Error { get; set; }
    public string? Content { get; set; }
    public string? FilePath { get; set; }
    public DateTime? LastModified { get; set; }
    public long? FileSize { get; set; }
}

public class ConfigSaveResult
{
    public bool Success { get; set; }
    public string? Error { get; set; }
    public string? FilePath { get; set; }
    public string? BackupPath { get; set; }
    public DateTime? LastModified { get; set; }
    public long? FileSize { get; set; }
}

public class BackupFileInfo
{
    public string FileName { get; set; } = string.Empty;
    public string FilePath { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
    public long FileSize { get; set; }
}
