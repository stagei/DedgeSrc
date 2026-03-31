using System.IO.Compression;
using Microsoft.Extensions.Options;
using AiDoc.WebNew.Models;
using AiDoc.WebNew.Options;

namespace AiDoc.WebNew.Services;

public class BackupService
{
    private readonly ILogger<BackupService> _logger;
    private readonly AiDocOptions _options;

    public BackupService(ILogger<BackupService> logger, IOptions<AiDocOptions> options)
    {
        _logger = logger;
        _options = options.Value;
    }

    private string OptPath => Environment.GetEnvironmentVariable("OptPath") ?? @"E:\opt";

    private string BackupDir
    {
        get
        {
            var dir = string.IsNullOrEmpty(_options.BackupDir)
                ? Path.Combine(OptPath, "data", "AiDoc.Backup")
                : Path.IsPathRooted(_options.BackupDir)
                    ? _options.BackupDir
                    : Path.Combine(OptPath, _options.BackupDir);
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    private string LibraryRoot
    {
        get
        {
            var val = _options.LibraryRoot;
            if (!string.IsNullOrEmpty(val))
            {
                if (Path.IsPathRooted(val)) return val;
                var joined = Path.Combine(OptPath, val);
                if (Directory.Exists(joined)) return joined;
            }
            return Path.Combine(OptPath, "data", "AiDoc.Library");
        }
    }

    public async Task<BackupInfo> TriggerBackupAsync()
    {
        if (!Directory.Exists(LibraryRoot))
            throw new DirectoryNotFoundException($"Library root not found: {LibraryRoot}");

        var timestamp = DateTime.Now.ToString("yyyyMMdd-HHmmss");
        var fileName = $"AiDoc-Library-{timestamp}.zip";
        var filePath = Path.Combine(BackupDir, fileName);

        _logger.LogInformation("Creating backup: {Path}", filePath);

        var ragDirs = Directory.GetDirectories(LibraryRoot)
            .Where(d => !Path.GetFileName(d).StartsWith('.'))
            .ToList();

        await Task.Run(() =>
        {
            using var zip = ZipFile.Open(filePath, ZipArchiveMode.Create);
            foreach (var ragDir in ragDirs)
            {
                var ragName = Path.GetFileName(ragDir);
                foreach (var file in Directory.GetFiles(ragDir, "*", SearchOption.AllDirectories))
                {
                    // Skip .index directories (large, can be rebuilt)
                    var relPath = Path.GetRelativePath(LibraryRoot, file);
                    if (relPath.Contains($"{Path.DirectorySeparatorChar}.index{Path.DirectorySeparatorChar}")
                        || relPath.Contains($"{Path.DirectorySeparatorChar}.index"))
                        continue;

                    zip.CreateEntryFromFile(file, relPath, CompressionLevel.Optimal);
                }
            }

            // Include registry if it exists
            var registryFile = Path.Combine(LibraryRoot, "rag-registry.json");
            if (File.Exists(registryFile))
                zip.CreateEntryFromFile(registryFile, "rag-registry.json", CompressionLevel.Optimal);
        });

        var info = new FileInfo(filePath);
        var result = new BackupInfo
        {
            FileName = fileName,
            Date = info.CreationTime,
            SizeBytes = info.Length,
            RagCount = ragDirs.Count,
            FilePath = filePath
        };

        _logger.LogInformation("Backup created: {File} ({Size} bytes, {Rags} RAGs)",
            fileName, result.SizeBytes, result.RagCount);

        // Enforce retention
        await EnforceRetentionAsync();

        return result;
    }

    public Task<List<BackupInfo>> GetHistoryAsync()
    {
        var backups = new List<BackupInfo>();

        if (!Directory.Exists(BackupDir))
            return Task.FromResult(backups);

        foreach (var file in Directory.GetFiles(BackupDir, "AiDoc-Library-*.zip")
            .OrderByDescending(f => f))
        {
            var fi = new FileInfo(file);
            backups.Add(new BackupInfo
            {
                FileName = fi.Name,
                Date = fi.CreationTime,
                SizeBytes = fi.Length,
                FilePath = fi.FullName
            });
        }

        return Task.FromResult(backups);
    }

    public Task<bool> DeleteBackupAsync(string fileName)
    {
        if (fileName.Contains("..") || Path.IsPathRooted(fileName))
            throw new ArgumentException("Invalid file name");

        var path = Path.Combine(BackupDir, fileName);
        if (!File.Exists(path))
            return Task.FromResult(false);

        File.Delete(path);
        _logger.LogInformation("Deleted backup: {File}", fileName);
        return Task.FromResult(true);
    }

    private Task EnforceRetentionAsync()
    {
        var cutoff = DateTime.Now.AddDays(-_options.BackupRetainDays);
        var deleted = 0;

        foreach (var file in Directory.GetFiles(BackupDir, "AiDoc-Library-*.zip"))
        {
            if (new FileInfo(file).CreationTime < cutoff)
            {
                File.Delete(file);
                deleted++;
            }
        }

        if (deleted > 0)
            _logger.LogInformation("Retention cleanup: removed {Count} old backups", deleted);

        return Task.CompletedTask;
    }
}
