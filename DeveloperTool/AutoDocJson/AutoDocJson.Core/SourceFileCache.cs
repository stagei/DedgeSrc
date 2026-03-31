using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace AutoDocNew.Core;

/// <summary>
/// In-memory source file cache using ConcurrentDictionary.
/// Preloads all searchable source files at startup to eliminate
/// redundant File.ReadAllLines() calls in FindAutodocUsages().
/// The working dataset is ~240 MB (10,000 source files + cobdok CSVs).
/// </summary>
public static class SourceFileCache
{
    static SourceFileCache()
    {
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
    }

    /// <summary>Cache for file lines read with Windows-1252 encoding (source files, CSVs).</summary>
    private static readonly ConcurrentDictionary<string, string[]> _linesCache = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>Cache for file text read with UTF-8 encoding (templates, JSON).</summary>
    private static readonly ConcurrentDictionary<string, string> _textCache = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>Index of cached file paths grouped by extension (lowercase) for fast enumeration.</summary>
    private static readonly ConcurrentDictionary<string, List<string>> _extensionIndex = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>Whether the cache is enabled and populated.</summary>
    public static bool IsEnabled { get; private set; }

    /// <summary>Total number of cached files.</summary>
    public static int CachedFileCount => _linesCache.Count + _textCache.Count;

    /// <summary>Extensions to preload as lines (Windows-1252 encoded source files).</summary>
    private static readonly string[] DefaultSourceExtensions =
    {
        ".cbl", ".rex", ".bat", ".ps1", ".psm1", ".cs", ".xml", ".json",
        ".gs", ".imp", ".config", ".csproj", ".sln"
    };

    /// <summary>Directories to skip during preload.</summary>
    private static readonly string[] SkipDirectories = { "\\.git\\", "\\bin\\", "\\obj\\", "\\node_modules\\", "\\.vs\\" };

    /// <summary>
    /// Preload all source files from the repository root folder.
    /// Uses Parallel.ForEach for concurrent file loading.
    /// </summary>
    /// <param name="rootFolder">Root folder containing all repositories (e.g., DedgeRepository).</param>
    /// <param name="extensions">File extensions to load. Uses defaults if null.</param>
    public static void PreloadAll(string rootFolder, string[]? extensions = null)
    {
        if (!Directory.Exists(rootFolder))
        {
            Logger.LogMessage($"SourceFileCache: Root folder not found: {rootFolder}", LogLevel.WARN);
            return;
        }

        var sw = Stopwatch.StartNew();
        var exts = extensions ?? DefaultSourceExtensions;
        var encoding1252 = Encoding.GetEncoding(1252);

        // Enumerate all matching files, skipping excluded directories
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

        Logger.LogMessage($"SourceFileCache: Found {files.Count} source files to preload from {rootFolder}", LogLevel.INFO);

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
                    System.Threading.Interlocked.Increment(ref loaded);
                    System.Threading.Interlocked.Add(ref totalBytes, new FileInfo(file).Length);

                    // Build extension index
                    string ext = Path.GetExtension(file).ToLower();
                    _extensionIndex.AddOrUpdate(ext,
                        _ => new List<string> { file },
                        (_, list) => { lock (list) { list.Add(file); } return list; });
                }
            }
            catch
            {
                System.Threading.Interlocked.Increment(ref errors);
            }
        });

        sw.Stop();
        double sizeMB = totalBytes / (1024.0 * 1024.0);
        Logger.LogMessage(
            $"SourceFileCache: Preloaded {loaded} files ({sizeMB:F1} MB) in {sw.Elapsed.TotalSeconds:F1}s. Errors: {errors}",
            LogLevel.INFO);

        IsEnabled = true;
    }

    /// <summary>
    /// Preload all cobdok CSV files into the cache.
    /// CSV files are UTF-8 after CobdokExportService converts them from ANSI-1252.
    /// </summary>
    /// <param name="cobdokFolder">Path to the cobdok folder containing CSV files.</param>
    public static void PreloadCobdok(string cobdokFolder)
    {
        if (!Directory.Exists(cobdokFolder))
        {
            Logger.LogMessage($"SourceFileCache: Cobdok folder not found: {cobdokFolder}", LogLevel.WARN);
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
                Logger.LogMessage($"SourceFileCache: Failed to cache {file}: {ex.Message}", LogLevel.WARN);
            }
        }

        Logger.LogMessage($"SourceFileCache: Preloaded {loaded} cobdok CSV files", LogLevel.INFO);
    }

    /// <summary>
    /// Get cached file lines. Returns null if not in cache (caller should fall back to disk).
    /// </summary>
    public static string[]? GetLines(string filePath)
    {
        if (!IsEnabled) return null;
        return _linesCache.TryGetValue(filePath, out var lines) ? lines : null;
    }

    /// <summary>
    /// Get cached file text (UTF-8). Returns null if not in cache.
    /// </summary>
    public static string? GetText(string filePath)
    {
        if (!IsEnabled) return null;
        return _textCache.TryGetValue(filePath, out var text) ? text : null;
    }

    /// <summary>
    /// Enumerate all cached file paths matching a glob filter (e.g., "*.cbl", "*.ps1")
    /// within a specific root folder. Avoids repeated Directory.EnumerateFiles() calls.
    /// Returns (filePath, lines) pairs.
    /// </summary>
    /// <param name="rootFolder">Root folder to scope the enumeration to.</param>
    /// <param name="includeFilter">Glob filter like "*.cbl" or "*.ps1".</param>
    /// <returns>Enumerable of file paths matching the filter under the root folder.</returns>
    public static IEnumerable<string> EnumerateFiles(string rootFolder, string includeFilter)
    {
        if (!IsEnabled)
            return Enumerable.Empty<string>();

        // Extract extension from filter (e.g., "*.cbl" -> ".cbl")
        string ext = includeFilter.Replace("*", "");
        if (!ext.StartsWith("."))
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
                    .ToList(); // Materialize to release lock
            }
        }

        return Enumerable.Empty<string>();
    }

    /// <summary>
    /// Clear all cached data and reset state.
    /// </summary>
    public static void Clear()
    {
        _linesCache.Clear();
        _textCache.Clear();
        _extensionIndex.Clear();
        IsEnabled = false;
        Logger.LogMessage("SourceFileCache: Cache cleared", LogLevel.INFO);
    }
}
