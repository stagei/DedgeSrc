using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text;

namespace SystemAnalyzer2.Batch.Services.Shared;

/// <summary>
/// In-memory source file cache using ConcurrentDictionary.
/// Preloads all searchable source files at startup to eliminate
/// redundant File.ReadAllLines() calls in FindAutodocUsages().
/// </summary>
public static class SourceFileCache
{
    static SourceFileCache()
    {
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
    }

    private static readonly ConcurrentDictionary<string, string[]> _linesCache = new(StringComparer.OrdinalIgnoreCase);
    private static readonly ConcurrentDictionary<string, string> _textCache = new(StringComparer.OrdinalIgnoreCase);
    private static readonly ConcurrentDictionary<string, List<string>> _extensionIndex = new(StringComparer.OrdinalIgnoreCase);

    public static bool IsEnabled { get; private set; }
    public static int CachedFileCount => _linesCache.Count + _textCache.Count;

    private static readonly string[] DefaultSourceExtensions =
    {
        ".cbl", ".rex", ".bat", ".ps1", ".psm1", ".cs", ".xml", ".json",
        ".gs", ".imp", ".config", ".csproj", ".sln"
    };

    private static readonly string[] SkipDirectories = { "\\.git\\", "\\bin\\", "\\obj\\", "\\node_modules\\", "\\.vs\\" };

    public static void PreloadAll(string rootFolder, string[]? extensions = null)
    {
        if (!Directory.Exists(rootFolder))
        {
            AutoDocLogger.LogMessage($"SourceFileCache: Root folder not found: {rootFolder}", LogLevel.WARN);
            return;
        }

        var sw = Stopwatch.StartNew();
        var exts = extensions ?? DefaultSourceExtensions;
        var encoding1252 = Encoding.GetEncoding(1252);

        var files = Directory.EnumerateFiles(rootFolder, "*.*", SearchOption.AllDirectories)
            .Where(f =>
            {
                string ext = Path.GetExtension(f);
                if (string.IsNullOrEmpty(ext)) return false;
                if (!exts.Any(e => ext.Equals(e, StringComparison.OrdinalIgnoreCase))) return false;
                foreach (string skip in SkipDirectories)
                {
                    if (f.Contains(skip, StringComparison.OrdinalIgnoreCase)) return false;
                }
                return true;
            })
            .ToList();

        AutoDocLogger.LogMessage($"SourceFileCache: Found {files.Count} source files to preload from {rootFolder}", LogLevel.INFO);

        long totalBytes = 0;
        int loaded = 0;
        int errors = 0;

        Parallel.ForEach(files, file =>
        {
            try
            {
                string[] lines = File.ReadAllLines(file, encoding1252);
                if (_linesCache.TryAdd(file, lines))
                {
                    Interlocked.Increment(ref loaded);
                    Interlocked.Add(ref totalBytes, new FileInfo(file).Length);

                    string ext = Path.GetExtension(file).ToLowerInvariant();
                    _extensionIndex.AddOrUpdate(ext,
                        _ => new List<string> { file },
                        (_, list) => { lock (list) { list.Add(file); } return list; });
                }
            }
            catch
            {
                Interlocked.Increment(ref errors);
            }
        });

        sw.Stop();
        double sizeMB = totalBytes / (1024.0 * 1024.0);
        AutoDocLogger.LogMessage(
            $"SourceFileCache: Preloaded {loaded} files ({sizeMB:F1} MB) in {sw.Elapsed.TotalSeconds:F1}s. Errors: {errors}",
            LogLevel.INFO);

        IsEnabled = true;
    }

    public static void PreloadCobdok(string cobdokFolder)
    {
        if (!Directory.Exists(cobdokFolder))
        {
            AutoDocLogger.LogMessage($"SourceFileCache: Cobdok folder not found: {cobdokFolder}", LogLevel.WARN);
            return;
        }

        int loaded = 0;

        foreach (string file in Directory.EnumerateFiles(cobdokFolder, "*.csv"))
        {
            try
            {
                string[] lines = File.ReadAllLines(file, Encoding.UTF8);
                if (_linesCache.TryAdd(file, lines))
                    loaded++;
            }
            catch (Exception ex)
            {
                AutoDocLogger.LogMessage($"SourceFileCache: Failed to cache {file}: {ex.Message}", LogLevel.WARN);
            }
        }

        AutoDocLogger.LogMessage($"SourceFileCache: Preloaded {loaded} cobdok CSV files", LogLevel.INFO);
    }

    public static string[]? GetLines(string filePath)
    {
        if (!IsEnabled) return null;
        return _linesCache.TryGetValue(filePath, out var lines) ? lines : null;
    }

    public static string? GetText(string filePath)
    {
        if (!IsEnabled) return null;
        return _textCache.TryGetValue(filePath, out var text) ? text : null;
    }

    public static IEnumerable<string> EnumerateFiles(string rootFolder, string includeFilter)
    {
        if (!IsEnabled)
            return Enumerable.Empty<string>();

        string ext = includeFilter.Replace("*", "", StringComparison.Ordinal);
        if (!ext.StartsWith('.'))
            ext = "." + ext;

        string rootNormalized = rootFolder.TrimEnd('\\') + "\\";

        if (_extensionIndex.TryGetValue(ext, out var fileList))
        {
            lock (fileList)
            {
                return fileList
                    .Where(f => f.StartsWith(rootNormalized, StringComparison.OrdinalIgnoreCase))
                    .Where(f => !f.Contains("\\bin\\", StringComparison.OrdinalIgnoreCase)
                             && !f.Contains("\\obj\\", StringComparison.OrdinalIgnoreCase)
                             && !f.Contains("\\.vs\\", StringComparison.OrdinalIgnoreCase)
                             && !f.Contains("\\.git\\", StringComparison.OrdinalIgnoreCase))
                    .ToList();
            }
        }

        return Enumerable.Empty<string>();
    }

    public static void Clear()
    {
        _linesCache.Clear();
        _textCache.Clear();
        _extensionIndex.Clear();
        IsEnabled = false;
        AutoDocLogger.LogMessage("SourceFileCache: Cache cleared", LogLevel.INFO);
    }
}
