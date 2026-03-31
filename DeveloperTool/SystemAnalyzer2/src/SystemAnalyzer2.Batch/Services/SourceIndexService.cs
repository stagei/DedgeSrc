using NLog;
using SystemAnalyzer2.Batch.Services.Shared;

namespace SystemAnalyzer2.Batch.Services;

public sealed class SourceIndexService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    private readonly string _sourceRoot;
    private readonly string _defaultFilePath;

    public Dictionary<string, string> CblIndex { get; private set; } = new(StringComparer.OrdinalIgnoreCase);
    public Dictionary<string, FullIndexEntry> FullIndex { get; private set; } = new(StringComparer.OrdinalIgnoreCase);
    public Dictionary<string, string> CopyIndex { get; private set; } = new(StringComparer.OrdinalIgnoreCase);
    public List<UncertainFileEntry> UncertainFiles { get; private set; } = [];
    public int TotalFileCount { get; private set; }

    public SourceIndexService(string sourceRoot, string defaultFilePath)
    {
        _sourceRoot = sourceRoot;
        _defaultFilePath = defaultFilePath;
    }

    public void BuildIndex()
    {
        if (!Directory.Exists(_sourceRoot))
        {
            Logger.Warn($"Source root not found: {_sourceRoot}");
            return;
        }

        // V1 recursively scans the entire source root
        var allFiles = Directory.GetFiles(_sourceRoot, "*.*", SearchOption.AllDirectories);
        TotalFileCount = allFiles.Length;

        // V1 regex patterns: [\\/]cbl([\\/]|$), [\\/]cpy([\\/]|$), [\\/][^\\/]*_uncertain([\\/]|$)
        var cblRx = new System.Text.RegularExpressions.Regex(@"[\\/]cbl([\\/]|$)", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        var cpyRx = new System.Text.RegularExpressions.Regex(@"[\\/]cpy([\\/]|$)", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        var uncRx = new System.Text.RegularExpressions.Regex(@"[\\/][^\\/]*_uncertain([\\/]|$)", System.Text.RegularExpressions.RegexOptions.IgnoreCase);

        foreach (var file in allFiles)
        {
            var dir = Path.GetDirectoryName(file) ?? "";
            var name = Path.GetFileNameWithoutExtension(file).ToUpperInvariant();
            var ext = Path.GetExtension(file).ToUpperInvariant();
            var nameWithExt = Path.GetFileName(file).ToUpperInvariant();

            // V1: uncertain → add to list and CONTINUE (skip cbl/cpy/full processing)
            if (uncRx.IsMatch(dir))
            {
                UncertainFiles.Add(new UncertainFileEntry(name, ext, file));
                continue;
            }

            bool isCblFolder = cblRx.IsMatch(dir);
            bool isCpyFolder = cpyRx.IsMatch(dir);

            if (isCblFolder && ext == ".CBL")
                CblIndex.TryAdd(name, file);

            if (isCblFolder || isCpyFolder)
                FullIndex.TryAdd(name, new FullIndexEntry(file, ext));

            if (isCpyFolder && ext is ".CPY" or ".CPB" or ".DCL")
            {
                CopyIndex.TryAdd(nameWithExt, file);
                CopyIndex.TryAdd(name, file);
            }
        }

        Logger.Info($"Source index: {CblIndex.Count} CBL, {CopyIndex.Count} CPY, {FullIndex.Count} total, {UncertainFiles.Count} uncertain (total files: {TotalFileCount})");
    }

    public SourceResolution ResolveProgramSource(string program)
    {
        var norm = program.ToUpperInvariant();

        if (CblIndex.TryGetValue(norm, out var cblPath))
            return new SourceResolution("local-cbl", cblPath, norm);

        var uvSwapped = norm.Replace('U', 'V');
        if (uvSwapped != norm && CblIndex.TryGetValue(uvSwapped, out var uvPath))
            return new SourceResolution("local-cbl-uv", uvPath, uvSwapped);

        if (FullIndex.TryGetValue(norm, out var fullEntry))
            return new SourceResolution($"local-{fullEntry.Extension.TrimStart('.').ToLowerInvariant()}", fullEntry.Path, norm);

        UncertainFileEntry? uncertainMatch = null;
        foreach (var uf in UncertainFiles)
        {
            if (uf.BaseName.Contains(norm, StringComparison.OrdinalIgnoreCase))
            {
                if (uf.Extension.Equals(".CBL", StringComparison.OrdinalIgnoreCase))
                {
                    uncertainMatch = uf;
                    break;
                }
                uncertainMatch ??= uf;
            }
        }
        if (uncertainMatch != null)
            return new SourceResolution("local-uncertain", uncertainMatch.Path, uncertainMatch.BaseName);

        return new SourceResolution("rag", null, norm);
    }

    public string? GetProgramText(string program, RagClient ragClient, int ragResults)
    {
        var resolution = ResolveProgramSource(program);

        if (resolution.Type.StartsWith("local-") && resolution.Path != null)
        {
            try
            {
                return File.ReadAllText(resolution.Path, System.Text.Encoding.UTF8);
            }
            catch (Exception ex)
            {
                Logger.Warn($"Cannot read {resolution.Path}: {ex.Message}");
            }
        }

        return null;
    }

    public static string ComputeSourceHash(string content)
    {
        var bytes = System.Text.Encoding.UTF8.GetBytes(content);
        var hash = System.Security.Cryptography.SHA256.HashData(bytes);
        return Convert.ToHexStringLower(hash)[..16];
    }
}

public sealed record FullIndexEntry(string Path, string Extension);
public sealed record UncertainFileEntry(string BaseName, string Extension, string Path);
public sealed record SourceResolution(string Type, string? Path, string ActualName);
