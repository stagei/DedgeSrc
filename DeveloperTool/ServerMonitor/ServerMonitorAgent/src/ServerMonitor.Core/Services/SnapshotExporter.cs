using System.IO.Compression;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;
using ServerMonitor.Core.Interfaces;
using ServerMonitor.Core.Models;

namespace ServerMonitor.Core.Services;

/// <summary>
/// Exports system snapshots to JSON files with retention management
/// </summary>
public class SnapshotExporter : ISnapshotExporter
{
    private readonly ILogger<SnapshotExporter> _logger;
    private readonly IOptionsMonitor<SurveillanceConfiguration> _config;
    private readonly SnapshotHtmlExporter _htmlExporter;
    private readonly object _lock = new();
    private SystemSnapshot? _lastExportedSnapshot;
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        // Serialize enums as strings (e.g., "Critical" instead of 2)
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) }
    };

    public SnapshotExporter(
        ILogger<SnapshotExporter> logger,
        IOptionsMonitor<SurveillanceConfiguration> config,
        SnapshotHtmlExporter htmlExporter)
    {
        _logger = logger;
        _config = config;
        _htmlExporter = htmlExporter;
    }

    public async Task ExportAsync(SystemSnapshot snapshot, CancellationToken cancellationToken = default)
    {
        try
        {
            // Always cache the snapshot for API access, even if file export is disabled
            lock (_lock)
            {
                _lastExportedSnapshot = snapshot;
            }

            var settings = _config.CurrentValue.ExportSettings;

            if (!settings.Enabled)
            {
                _logger.LogDebug("Snapshot export to file is disabled, but cached for API access");
                return;
            }

            // Get all output directories
            var outputDirs = GetOutputDirectories(settings);

            if (outputDirs.Count == 0)
            {
                _logger.LogWarning("No output directories configured for snapshot export");
                return;
            }

            // Generate filename
            var fileName = GenerateFileName(settings.FileNamePattern, snapshot.Metadata);

            // Serialize snapshot to JSON (once, reuse for all directories)
            var json = JsonSerializer.Serialize(snapshot, JsonOptions);

            // Write to all output directories
            var exportedPaths = new List<string>();
            foreach (var outputDir in outputDirs)
            {
                try
                {
                    // Ensure output directory exists
                    Directory.CreateDirectory(outputDir);

                    var filePath = Path.Combine(outputDir, fileName);

                    // Write JSON to file
                    await File.WriteAllTextAsync(filePath, json, cancellationToken).ConfigureAwait(false);
                    exportedPaths.Add(filePath);

                    _logger.LogInformation("Snapshot exported to {FilePath} ({Size} bytes)", 
                        filePath, json.Length);

                    // Export HTML version
                    try
                    {
                        var htmlPath = Path.ChangeExtension(filePath, ".html");
                        await _htmlExporter.ExportToHtmlAsync(snapshot, htmlPath, saveToServerShare: false, autoOpen: false, cancellationToken).ConfigureAwait(false);
                    }
                    catch (Exception ex)
                    {
                        _logger.LogWarning(ex, "Failed to export HTML snapshot to {Path} - continuing", outputDir);
                    }

                    // Compress JSON if enabled
                    if (settings.Retention.CompressionEnabled)
                    {
                        await CompressSnapshotAsync(filePath, cancellationToken).ConfigureAwait(false);
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Failed to export snapshot to {Directory} - continuing with other directories", outputDir);
                    // Continue with other directories even if one fails
                }
            }

            if (exportedPaths.Count > 0)
            {
                _logger.LogInformation("Snapshot exported to {Count} directory/directories", exportedPaths.Count);
                
                // Cache the last exported snapshot for fast API access
                lock (_lock)
                {
                    _lastExportedSnapshot = snapshot;
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to export snapshot");
            throw;
        }
    }

    /// <inheritdoc />
    public SystemSnapshot? GetLastExportedSnapshot()
    {
        lock (_lock)
        {
            return _lastExportedSnapshot;
        }
    }

    /// <summary>
    /// Gets all output directories from configuration.
    /// Combines OutputDirectory (for backward compatibility) and OutputDirectories.
    /// </summary>
    private List<string> GetOutputDirectories(ExportSettings settings)
    {
        var directories = new List<string>();

        // If OutputDirectories is specified, use it (ignore OutputDirectory)
        if (settings.OutputDirectories != null && settings.OutputDirectories.Count > 0)
        {
            directories.AddRange(settings.OutputDirectories);
        }
        // Otherwise, use OutputDirectory for backward compatibility
        else if (!string.IsNullOrWhiteSpace(settings.OutputDirectory))
        {
            directories.Add(settings.OutputDirectory);
        }

        // Expand environment variables and remove duplicates
        return directories
            .Select(d => Environment.ExpandEnvironmentVariables(d))
            .Where(d => !string.IsNullOrWhiteSpace(d))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    public async Task CleanupOldSnapshotsAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            var settings = _config.CurrentValue.ExportSettings;

            if (!settings.Enabled)
            {
                return;
            }

            // Get all output directories
            var outputDirs = GetOutputDirectories(settings);

            var totalDeleted = 0;
            var maxAge = TimeSpan.FromHours(settings.Retention.MaxAgeHours);
            var cutoffDate = DateTime.UtcNow - maxAge;

            // Cleanup each directory
            foreach (var outputDir in outputDirs)
            {
                try
                {
                    if (!Directory.Exists(outputDir))
                    {
                        continue;
                    }

                    var files = Directory.GetFiles(outputDir, "*.json")
                        .Concat(Directory.GetFiles(outputDir, "*.json.gz"))
                        .Select(f => new FileInfo(f))
                        .OrderByDescending(f => f.LastWriteTimeUtc)
                        .ToList();

                    var deleted = 0;

                    // Delete files older than max age
                    foreach (var file in files.Where(f => f.LastWriteTimeUtc < cutoffDate))
                    {
                        try
                        {
                            file.Delete();
                            deleted++;
                            _logger.LogDebug("Deleted old snapshot: {FileName} from {Directory}", file.Name, outputDir);
                        }
                        catch (Exception ex)
                        {
                            _logger.LogWarning(ex, "Failed to delete file {FileName} from {Directory}", file.Name, outputDir);
                        }
                    }

                    // Delete excess files if count exceeds maximum
                    var remainingFiles = files.Where(f => f.LastWriteTimeUtc >= cutoffDate).ToList();
                    if (remainingFiles.Count > settings.Retention.MaxFileCount)
                    {
                        var excessFiles = remainingFiles.Skip(settings.Retention.MaxFileCount);
                        foreach (var file in excessFiles)
                        {
                            try
                            {
                                file.Delete();
                                deleted++;
                                _logger.LogDebug("Deleted excess snapshot: {FileName} from {Directory}", file.Name, outputDir);
                            }
                            catch (Exception ex)
                            {
                                _logger.LogWarning(ex, "Failed to delete file {FileName} from {Directory}", file.Name, outputDir);
                            }
                        }
                    }

                    if (deleted > 0)
                    {
                        _logger.LogInformation("Cleaned up {Count} old snapshots from {Directory}", 
                            deleted, outputDir);
                        totalDeleted += deleted;
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Failed to cleanup old snapshots from {Directory}", outputDir);
                    // Continue with other directories even if one fails
                }
            }

            if (totalDeleted > 0)
            {
                _logger.LogInformation("Total cleanup: {Count} old snapshots deleted from {DirectoryCount} directory/directories", 
                    totalDeleted, outputDirs.Count);
            }

            await Task.CompletedTask;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to cleanup old snapshots");
        }
    }

    private string GenerateFileName(string pattern, SnapshotMetadata metadata)
    {
        var fileName = pattern
            .Replace("{ServerName}", metadata.ServerName)
            .Replace("{Timestamp:yyyyMMdd_HHmmss}", metadata.Timestamp.ToString("yyyyMMdd_HHmmss"))
            .Replace("{Timestamp:yyyyMMdd}", metadata.Timestamp.ToString("yyyyMMdd"))
            .Replace("{SnapshotId}", metadata.SnapshotId.ToString());

        // Ensure .json extension
        if (!fileName.EndsWith(".json", StringComparison.OrdinalIgnoreCase))
        {
            fileName += ".json";
        }

        return fileName;
    }

    private async Task CompressSnapshotAsync(string filePath, CancellationToken cancellationToken)
    {
        try
        {
            var compressedPath = filePath + ".gz";

            using (var originalStream = File.OpenRead(filePath))
            using (var compressedStream = File.Create(compressedPath))
            using (var gzipStream = new GZipStream(compressedStream, CompressionLevel.Optimal))
            {
                await originalStream.CopyToAsync(gzipStream, cancellationToken).ConfigureAwait(false);
            }

            // Delete original file after successful compression
            File.Delete(filePath);

            var originalSize = new FileInfo(filePath).Length;
            var compressedSize = new FileInfo(compressedPath).Length;
            var ratio = (1 - (double)compressedSize / originalSize) * 100;

            _logger.LogDebug("Compressed snapshot: {OriginalSize} -> {CompressedSize} bytes ({Ratio:F1}% reduction)",
                originalSize, compressedSize, ratio);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to compress snapshot {FilePath}", filePath);
        }
    }
}

