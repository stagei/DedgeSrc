using System.Diagnostics;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Options;
using AiDoc.WebNew.Models;
using AiDoc.WebNew.Options;

namespace AiDoc.WebNew.Services;

public partial class RagManagementService
{
    private readonly ILogger<RagManagementService> _logger;
    private readonly AiDocOptions _options;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly string _libraryRoot;
    private readonly string _pythonRoot;
    private readonly string _serverScriptsRoot;
    private readonly string _clientScriptsRoot;
    private readonly string _pythonExe;

    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true
    };

    public RagManagementService(
        ILogger<RagManagementService> logger,
        IOptions<AiDocOptions> options,
        IHttpClientFactory httpClientFactory)
    {
        _logger = logger;
        _options = options.Value;
        _httpClientFactory = httpClientFactory;
        _libraryRoot = ResolveLibraryRoot();
        _pythonRoot = ResolvePythonRoot();
        _serverScriptsRoot = ResolveServerScriptsRoot();
        _clientScriptsRoot = ResolveClientScriptsRoot();
        _pythonExe = ResolvePythonExe();
        _logger.LogInformation("Library: {Library}, Python: {Python}, ServerScripts: {Server}, ClientScripts: {Client}, PythonExe: {Exe}",
            _libraryRoot, _pythonRoot, _serverScriptsRoot, _clientScriptsRoot, _pythonExe);
    }

    private string ResolveRoot(string configValue, string appRelativeFallback)
    {
        var optPath = Environment.GetEnvironmentVariable("OptPath") ?? @"E:\opt";

        if (!string.IsNullOrEmpty(configValue))
        {
            if (Path.IsPathRooted(configValue))
                return configValue;

            var joined = Path.Combine(optPath, configValue);
            if (Directory.Exists(joined))
                return joined;
        }

        // Default: relative to the running application directory
        return Path.Combine(AppContext.BaseDirectory, appRelativeFallback);
    }

    private string ResolveLibraryRoot()
    {
        var optPath = Environment.GetEnvironmentVariable("OptPath") ?? @"E:\opt";
        if (!string.IsNullOrEmpty(_options.LibraryRoot))
        {
            if (Path.IsPathRooted(_options.LibraryRoot)) return _options.LibraryRoot;
            var joined = Path.Combine(optPath, _options.LibraryRoot);
            if (Directory.Exists(joined)) return joined;
        }
        return Path.Combine(optPath, "data", "AiDoc.Library");
    }

    private string ResolvePythonRoot()
        => ResolveRoot(_options.PythonRoot, "python");

    private string ResolveServerScriptsRoot()
        => ResolveRoot(_options.ServerScriptsRoot, "scripts");

    private string ResolveClientScriptsRoot()
        => ResolveRoot(_options.ClientScriptsRoot, "scripts");

    private string ResolvePythonExe()
    {
        if (!string.IsNullOrEmpty(_options.PythonExe))
            return _options.PythonExe;

        var venvPython = Path.Combine(_pythonRoot, ".venv", "Scripts", "python.exe");
        if (File.Exists(venvPython))
            return venvPython;

        return "python";
    }

    private string RegistryPath => Path.Combine(_libraryRoot, "rag-registry.json");
    private string LibraryPath => _libraryRoot;
    private string OptPath => Environment.GetEnvironmentVariable("OptPath") ?? @"E:\opt";
    private string RebuildStatusDir => Path.Combine(OptPath, "data", "Rebuild-RagIndex");

    private string ResolveRebuildScript()
        => Path.Combine(_serverScriptsRoot, "Rebuild-RagIndex.ps1");

    private string ResolveConvertScript()
    {
        return Path.Combine(_pythonRoot, "convert_to_md.py");
    }

    private async Task<string> GetUncShareRoot()
    {
        if (!string.IsNullOrEmpty(_options.UncShareRoot))
            return _options.UncShareRoot;

        var registry = await GetRegistryAsync();
        var host = string.IsNullOrEmpty(registry.Host) ? _options.RagHost : registry.Host;
        return $@"\\{host}\opt\data\AiDoc.Library";
    }

    // ── Registry ──────────────────────────────────────────────────

    public async Task<RagRegistry> GetRegistryAsync()
    {
        if (!File.Exists(RegistryPath))
            return new RagRegistry { Host = _options.RagHost };

        var json = await File.ReadAllTextAsync(RegistryPath);
        return JsonSerializer.Deserialize<RagRegistry>(json, JsonOpts)
            ?? new RagRegistry { Host = _options.RagHost };
    }

    public async Task SaveRegistryAsync(RagRegistry registry)
    {
        var json = JsonSerializer.Serialize(registry, JsonOpts);
        await File.WriteAllTextAsync(RegistryPath, json);
        _logger.LogInformation("Registry saved with {Count} RAGs", registry.Rags.Count);
    }

    // ── List / Get ────────────────────────────────────────────────

    public async Task<List<RagIndexInfo>> ListRagsAsync()
    {
        var registry = await GetRegistryAsync();
        var uncRoot = await GetUncShareRoot();

        // Build all RAG infos in parallel - avoids N×serial HTTP timeout waits
        var tasks = registry.Rags.Select(entry => BuildRagInfo(entry, registry.Host, uncRoot));
        var results = await Task.WhenAll(tasks);
        return [.. results];
    }

    public async Task<RagIndexInfo?> GetRagAsync(string name)
    {
        var registry = await GetRegistryAsync();
        var entry = registry.Rags.FirstOrDefault(r =>
            r.Name.Equals(name, StringComparison.OrdinalIgnoreCase));

        if (entry is null) return null;
        var uncRoot = await GetUncShareRoot();
        return await BuildRagInfo(entry, registry.Host, uncRoot);
    }

    private async Task<RagIndexInfo> BuildRagInfo(RagRegistryEntry entry, string host, string uncRoot)
    {
        var ragDir = Path.Combine(LibraryPath, entry.Name);
        var manifestPath = Path.Combine(ragDir, ".index_manifest.json");
        var indexDir = Path.Combine(ragDir, ".index");

        var info = new RagIndexInfo
        {
            Name = entry.Name,
            Description = entry.Description,
            Port = entry.Port,
            UncPath = Path.Combine(uncRoot, entry.Name)
        };

        if (File.Exists(manifestPath))
        {
            try
            {
                var manifestJson = await File.ReadAllTextAsync(manifestPath);
                using var doc = JsonDocument.Parse(manifestJson);
                var root = doc.RootElement;

                if (root.TryGetProperty("builtAt", out var builtAt))
                    info.BuiltAt = DateTime.Parse(builtAt.GetString()!);
                if (root.TryGetProperty("sourceHash", out var hash))
                    info.SourceHash = hash.GetString();
                // Read cached counts from manifest to avoid full directory scan on each list call
                if (root.TryGetProperty("sourceFileCount", out var fc))
                    info.SourceFileCount = fc.GetInt32();
                if (root.TryGetProperty("totalSizeBytes", out var sb))
                    info.TotalSizeBytes = sb.GetInt64();
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Could not read manifest for {Rag}", entry.Name);
            }
        }

        if (Directory.Exists(ragDir))
        {
            // Only do a live scan if the manifest didn't already provide the counts
            if (info.SourceFileCount == 0)
            {
                var mdFiles = Directory.GetFiles(ragDir, "*.md", SearchOption.AllDirectories);
                info.SourceFileCount = mdFiles.Length;
                info.TotalSizeBytes = mdFiles.Sum(f => new FileInfo(f).Length);
            }

            info.SourceFolders = Directory.GetDirectories(ragDir)
                .Where(d => !Path.GetFileName(d).StartsWith('.'))
                .Select(d => Path.GetFileName(d))
                .ToList();
        }

        info.Status = Directory.Exists(indexDir) ? "indexed" : "no-index";

        if (info.BuiltAt is null && Directory.Exists(indexDir))
        {
            try
            {
                info.BuiltAt = Directory.GetLastWriteTimeUtc(indexDir);
            }
            catch { /* best-effort */ }
        }

        var runningFile = Path.Combine(RebuildStatusDir, $"{entry.Name}.running");
        if (File.Exists(runningFile))
        {
            info.Status = "building";
            return info;
        }

        try
        {
            var client = _httpClientFactory.CreateClient("RagProxy");
            var url = $"http://{host}:{entry.Port}/health";
            var response = await client.GetAsync(url);
            if (response.IsSuccessStatusCode)
                info.Status = "online";
        }
        catch
        {
            if (info.Status == "indexed")
                info.Status = "offline";
        }

        return info;
    }

    // ── Create ────────────────────────────────────────────────────

    public async Task<RagIndexInfo> CreateRagAsync(CreateRagRequest request)
    {
        ValidateRagName(request.Name);

        var ragDir = Path.Combine(LibraryPath, request.Name);
        if (Directory.Exists(ragDir))
            throw new InvalidOperationException($"RAG '{request.Name}' already exists");

        Directory.CreateDirectory(ragDir);

        var registry = await GetRegistryAsync();
        registry.Rags.Add(new RagRegistryEntry
        {
            Name = request.Name,
            Port = request.Port,
            Description = request.Description
        });
        await SaveRegistryAsync(registry);

        _logger.LogInformation("Created RAG {Name} on port {Port}", request.Name, request.Port);

        var uncRoot = await GetUncShareRoot();
        return new RagIndexInfo
        {
            Name = request.Name,
            Description = request.Description,
            Port = request.Port,
            Status = "no-index",
            UncPath = Path.Combine(uncRoot, request.Name)
        };
    }

    // ── Rebuild ───────────────────────────────────────────────────

    public async Task<RebuildResult> RebuildRagAsync(string name)
    {
        var registry = await GetRegistryAsync();
        var entry = registry.Rags.FirstOrDefault(r =>
            r.Name.Equals(name, StringComparison.OrdinalIgnoreCase))
            ?? throw new KeyNotFoundException($"RAG '{name}' not found in registry");

        var ragDir = Path.Combine(LibraryPath, entry.Name);
        if (!Directory.Exists(ragDir))
            throw new DirectoryNotFoundException($"Library folder not found: {ragDir}");

        var runningFile = Path.Combine(RebuildStatusDir, $"{entry.Name}.running");
        if (File.Exists(runningFile))
            throw new InvalidOperationException($"Rebuild already in progress for '{entry.Name}'");

        var rebuildScript = ResolveRebuildScript();
        if (!File.Exists(rebuildScript))
            throw new FileNotFoundException($"Rebuild-RagIndex.ps1 not found at {rebuildScript}");

        _logger.LogInformation("Launching async rebuild for RAG: {Name} via {Script}", name, rebuildScript);

        var rebuildLogDir = Path.Combine(AppContext.BaseDirectory, "logs", "rebuild");
        Directory.CreateDirectory(rebuildLogDir);
        var rebuildLogFile = Path.Combine(rebuildLogDir, $"{entry.Name}_{DateTime.UtcNow:yyyyMMdd_HHmmss}.log");

        var psi = new ProcessStartInfo
        {
            FileName = "pwsh.exe",
            Arguments = $"-NoProfile -File \"{rebuildScript}\" -RagName {entry.Name}",
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };

        var process = Process.Start(psi)
            ?? throw new InvalidOperationException("Failed to start pwsh.exe process");

        _logger.LogInformation("Rebuild process started: PID={Pid} for {Name}, log={Log}", process.Id, name, rebuildLogFile);

        _ = Task.Run(async () =>
        {
            try
            {
                await using var logWriter = new StreamWriter(rebuildLogFile, append: false) { AutoFlush = true };
                await logWriter.WriteLineAsync($"[{DateTime.UtcNow:yyyy-MM-dd HH:mm:ss}] Rebuild started for {entry.Name} (PID {process.Id})");
                await logWriter.WriteLineAsync($"[{DateTime.UtcNow:yyyy-MM-dd HH:mm:ss}] Script: {rebuildScript}");
                await logWriter.WriteLineAsync("---");

                var stdoutTask = Task.Run(async () =>
                {
                    while (await process.StandardOutput.ReadLineAsync() is { } line)
                    {
                        await logWriter.WriteLineAsync($"[OUT] {line}");
                    }
                });

                var stderrTask = Task.Run(async () =>
                {
                    while (await process.StandardError.ReadLineAsync() is { } line)
                    {
                        await logWriter.WriteLineAsync($"[ERR] {line}");
                    }
                });

                await Task.WhenAll(stdoutTask, stderrTask);
                await process.WaitForExitAsync();

                await logWriter.WriteLineAsync("---");
                await logWriter.WriteLineAsync($"[{DateTime.UtcNow:yyyy-MM-dd HH:mm:ss}] Process exited with code {process.ExitCode}");
                _logger.LogInformation("Rebuild finished for {Name}: exit={ExitCode}", entry.Name, process.ExitCode);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error capturing rebuild output for {Name}", entry.Name);
                try
                {
                    await File.AppendAllTextAsync(rebuildLogFile, $"\n[FATAL] Log capture error: {ex.Message}\n");
                }
                catch { /* best effort */ }
            }
        });

        return new RebuildResult
        {
            Started = true,
            Pid = process.Id,
            LogFile = Path.GetFileName(rebuildLogFile)
        };
    }

    public async Task<RebuildStatus> GetRebuildStatusAsync(string name)
    {
        var runningFile = Path.Combine(RebuildStatusDir, $"{name}.running");
        if (!File.Exists(runningFile))
            return new RebuildStatus { Building = false };

        try
        {
            var json = await File.ReadAllTextAsync(runningFile);
            var status = JsonSerializer.Deserialize<RebuildStatus>(json, JsonOpts);
            if (status is not null)
            {
                status.Building = true;

                if (status.Pid is > 0)
                {
                    if (!IsRebuildProcessAlive(status.Pid.Value, name))
                    {
                        _logger.LogWarning("Rebuild PID {Pid} for {Name} is dead; cleaning up stale .running file", status.Pid, name);
                        try { File.Delete(runningFile); } catch { /* best effort */ }
                        status.Building = false;
                    }
                }

                return status;
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Could not read rebuild status file for {Name}", name);
        }

        return new RebuildStatus { Building = true, RagName = name };
    }

    public async Task<bool> CancelRebuildAsync(string name)
    {
        var runningFile = Path.Combine(RebuildStatusDir, $"{name}.running");
        if (!File.Exists(runningFile))
            return false;

        int? pid = null;
        try
        {
            var json = await File.ReadAllTextAsync(runningFile);
            var status = JsonSerializer.Deserialize<RebuildStatus>(json, JsonOpts);
            pid = status?.Pid;
        }
        catch { /* best effort */ }

        if (pid is > 0)
        {
            KillRebuildProcessTree(pid.Value, name);
        }

        try { File.Delete(runningFile); } catch { /* best effort */ }

        _logger.LogInformation("Rebuild cancelled for {Name} (PID={Pid})", name, pid);
        return true;
    }

    private bool IsRebuildProcessAlive(int pid, string ragName)
    {
        try
        {
            var proc = Process.GetProcessById(pid);
            if (proc.HasExited)
                return false;

            var cmdLine = GetProcessCommandLine(pid);
            if (cmdLine is not null)
                return cmdLine.Contains("build_index", StringComparison.OrdinalIgnoreCase)
                    || cmdLine.Contains("Rebuild-RagIndex", StringComparison.OrdinalIgnoreCase);

            return !proc.HasExited;
        }
        catch (ArgumentException)
        {
            return false;
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "Could not check process {Pid}", pid);
            return false;
        }
    }

    private void KillRebuildProcessTree(int pid, string ragName)
    {
        try
        {
            var proc = Process.GetProcessById(pid);
            if (proc.HasExited)
            {
                _logger.LogInformation("Rebuild PID {Pid} already exited", pid);
                return;
            }

            using var searcher = new System.Management.ManagementObjectSearcher(
                $"SELECT ProcessId, CommandLine FROM Win32_Process WHERE ParentProcessId = {pid}");
            foreach (var child in searcher.Get())
            {
                var childPid = Convert.ToInt32(child["ProcessId"]);
                var childCmd = child["CommandLine"]?.ToString() ?? "";
                _logger.LogInformation("Killing child process PID={ChildPid} cmd={Cmd}", childPid, childCmd);
                try { Process.GetProcessById(childPid).Kill(entireProcessTree: true); } catch { }
            }

            proc.Kill(entireProcessTree: true);
            _logger.LogInformation("Killed rebuild process PID={Pid} for {Name}", pid, ragName);
        }
        catch (ArgumentException)
        {
            _logger.LogInformation("Rebuild PID {Pid} no longer exists", pid);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Error killing rebuild PID {Pid}", pid);
        }
    }

    private static string? GetProcessCommandLine(int pid)
    {
        try
        {
            using var searcher = new System.Management.ManagementObjectSearcher(
                $"SELECT CommandLine FROM Win32_Process WHERE ProcessId = {pid}");
            foreach (var obj in searcher.Get())
            {
                return obj["CommandLine"]?.ToString();
            }
        }
        catch { }
        return null;
    }

    // ── Upload ────────────────────────────────────────────────────

    private static readonly HashSet<string> AllowedExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".md", ".txt", ".pdf", ".docx"
    };

    public async Task<UploadResult> UploadFilesAsync(string name, List<IFormFile> files)
    {
        var registry = await GetRegistryAsync();
        var entry = registry.Rags.FirstOrDefault(r =>
            r.Name.Equals(name, StringComparison.OrdinalIgnoreCase))
            ?? throw new KeyNotFoundException($"RAG '{name}' not found in registry");

        var ragDir = Path.Combine(LibraryPath, entry.Name);
        if (!Directory.Exists(ragDir))
            throw new DirectoryNotFoundException($"Library folder not found: {ragDir}");

        var uploadDir = Path.Combine(ragDir, "uploaded");
        var originalsDir = Path.Combine(ragDir, ".originals");
        Directory.CreateDirectory(uploadDir);

        var result = new UploadResult();

        foreach (var file in files)
        {
            var ext = Path.GetExtension(file.FileName);
            if (!AllowedExtensions.Contains(ext))
            {
                result.Failed++;
                result.Errors.Add($"Unsupported file type: {file.FileName}");
                continue;
            }

            try
            {
                var baseName = Path.GetFileNameWithoutExtension(file.FileName);
                var safeBaseName = SanitizeFileName(baseName);

                if (ext.Equals(".md", StringComparison.OrdinalIgnoreCase))
                {
                    var targetPath = Path.Combine(uploadDir, $"{safeBaseName}.md");
                    targetPath = GetUniqueFilePath(targetPath);
                    await using var stream = new FileStream(targetPath, FileMode.Create);
                    await file.CopyToAsync(stream);
                    result.Saved++;
                }
                else if (ext.Equals(".txt", StringComparison.OrdinalIgnoreCase))
                {
                    var targetPath = Path.Combine(uploadDir, $"{safeBaseName}.md");
                    targetPath = GetUniqueFilePath(targetPath);
                    await using var stream = new FileStream(targetPath, FileMode.Create);
                    await file.CopyToAsync(stream);
                    result.Saved++;
                }
                else
                {
                    Directory.CreateDirectory(originalsDir);
                    var originalPath = Path.Combine(originalsDir, $"{safeBaseName}{ext}");
                    originalPath = GetUniqueFilePath(originalPath);
                    await using (var stream = new FileStream(originalPath, FileMode.Create))
                    {
                        await file.CopyToAsync(stream);
                    }

                    var mdTargetPath = Path.Combine(uploadDir, $"{safeBaseName}.md");
                    mdTargetPath = GetUniqueFilePath(mdTargetPath);

                    var convertSuccess = await ConvertToMarkdownAsync(originalPath, mdTargetPath);
                    if (convertSuccess)
                    {
                        result.Converted++;
                    }
                    else
                    {
                        result.Failed++;
                        result.Errors.Add($"Conversion failed: {file.FileName}");
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to process uploaded file: {FileName}", file.FileName);
                result.Failed++;
                result.Errors.Add($"Error processing {file.FileName}: {ex.Message}");
            }
        }

        _logger.LogInformation("Upload to {Rag}: saved={Saved}, converted={Converted}, failed={Failed}",
            name, result.Saved, result.Converted, result.Failed);

        return result;
    }

    private async Task<bool> ConvertToMarkdownAsync(string inputPath, string outputPath)
    {
        var convertScript = ResolveConvertScript();
        if (!File.Exists(convertScript))
        {
            _logger.LogWarning("convert_to_md.py not found at {Path}", convertScript);
            return false;
        }

        var psi = new ProcessStartInfo
        {
            FileName = _pythonExe,
            Arguments = $"\"{convertScript}\" --input \"{inputPath}\" --output \"{outputPath}\"",
            WorkingDirectory = _pythonRoot,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        using var process = Process.Start(psi);
        if (process is null) return false;

        await process.WaitForExitAsync();
        if (process.ExitCode != 0)
        {
            var stderr = await process.StandardError.ReadToEndAsync();
            _logger.LogWarning("convert_to_md.py failed for {Input}: {Error}", inputPath, stderr);
            return false;
        }

        return File.Exists(outputPath);
    }

    private static string SanitizeFileName(string name)
    {
        var invalid = Path.GetInvalidFileNameChars();
        var sanitized = new string(name.Select(c => invalid.Contains(c) ? '_' : c).ToArray());
        return string.IsNullOrWhiteSpace(sanitized) ? "file" : sanitized;
    }

    private static string GetUniqueFilePath(string path)
    {
        if (!File.Exists(path)) return path;

        var dir = Path.GetDirectoryName(path)!;
        var name = Path.GetFileNameWithoutExtension(path);
        var ext = Path.GetExtension(path);
        var counter = 1;

        string candidate;
        do
        {
            candidate = Path.Combine(dir, $"{name}_{counter}{ext}");
            counter++;
        } while (File.Exists(candidate));

        return candidate;
    }

    // ── Delete ────────────────────────────────────────────────────

    public async Task DeleteRagAsync(string name, bool deleteFiles = false)
    {
        var registry = await GetRegistryAsync();
        var removed = registry.Rags.RemoveAll(r =>
            r.Name.Equals(name, StringComparison.OrdinalIgnoreCase));

        if (removed == 0)
            throw new KeyNotFoundException($"RAG '{name}' not found in registry");

        await SaveRegistryAsync(registry);

        var indexDir = Path.Combine(LibraryPath, name, ".index");
        if (Directory.Exists(indexDir))
        {
            Directory.Delete(indexDir, true);
            _logger.LogInformation("Deleted index directory for {Name}", name);
        }

        var manifestPath = Path.Combine(LibraryPath, name, ".index_manifest.json");
        if (File.Exists(manifestPath))
            File.Delete(manifestPath);

        if (deleteFiles)
        {
            var ragDir = Path.Combine(LibraryPath, name);
            if (Directory.Exists(ragDir))
            {
                Directory.Delete(ragDir, true);
                _logger.LogInformation("Deleted all files for {Name}", name);
            }
        }
    }

    // ── Sources ───────────────────────────────────────────────────

    public Task<List<RagSourceInfo>> ListSourcesAsync(string ragName)
    {
        var ragDir = Path.Combine(LibraryPath, ragName);
        if (!Directory.Exists(ragDir))
            throw new DirectoryNotFoundException($"RAG directory not found: {ragName}");

        var sources = new List<RagSourceInfo>();

        foreach (var dir in Directory.GetDirectories(ragDir))
        {
            var dirName = Path.GetFileName(dir);
            if (dirName.StartsWith('.')) continue;

            var dirInfo = new DirectoryInfo(dir);
            var files = dirInfo.GetFiles("*.md", SearchOption.AllDirectories);

            sources.Add(new RagSourceInfo
            {
                RelativePath = dirName,
                FileName = dirName,
                SizeBytes = files.Sum(f => f.Length),
                LastModified = files.Any() ? files.Max(f => f.LastWriteTimeUtc) : dirInfo.LastWriteTimeUtc,
                IsDirectory = true
            });
        }

        return Task.FromResult(sources);
    }

    public Task DeleteSourceAsync(string ragName, string relativePath)
    {
        ValidateRelativePath(relativePath);

        var fullPath = Path.Combine(LibraryPath, ragName, relativePath);

        if (Directory.Exists(fullPath))
        {
            Directory.Delete(fullPath, true);
            _logger.LogInformation("Deleted source folder {Path} from {Rag}", relativePath, ragName);
        }
        else if (File.Exists(fullPath))
        {
            File.Delete(fullPath);
            _logger.LogInformation("Deleted source file {Path} from {Rag}", relativePath, ragName);
        }
        else
        {
            throw new FileNotFoundException($"Source not found: {relativePath}");
        }

        return Task.CompletedTask;
    }

    // ── Query (proxy) ─────────────────────────────────────────────

    public async Task<string> QueryRagAsync(string name, string query, int nResults = 6)
    {
        var registry = await GetRegistryAsync();
        var entry = registry.Rags.FirstOrDefault(r =>
            r.Name.Equals(name, StringComparison.OrdinalIgnoreCase))
            ?? throw new KeyNotFoundException($"RAG '{name}' not found");

        var host = string.IsNullOrEmpty(registry.Host) ? _options.RagHost : registry.Host;
        var url = $"http://{host}:{entry.Port}/query?q={Uri.EscapeDataString(query)}&n={nResults}";

        var client = _httpClientFactory.CreateClient("RagProxy");
        var response = await client.GetAsync(url);
        response.EnsureSuccessStatusCode();

        return await response.Content.ReadAsStringAsync();
    }

    // ── Validation ────────────────────────────────────────────────

    [GeneratedRegex(@"^[a-z0-9][a-z0-9\-]*[a-z0-9]$", RegexOptions.IgnoreCase)]
    private static partial Regex RagNamePattern();

    private static void ValidateRagName(string name)
    {
        if (string.IsNullOrWhiteSpace(name))
            throw new ArgumentException("RAG name cannot be empty");
        if (name.Length < 2 || name.Length > 64)
            throw new ArgumentException("RAG name must be 2-64 characters");
        if (!RagNamePattern().IsMatch(name))
            throw new ArgumentException("RAG name must contain only lowercase letters, numbers, and hyphens");
    }

    private static void ValidateRelativePath(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
            throw new ArgumentException("Path cannot be empty");
        if (path.Contains("..") || Path.IsPathRooted(path))
            throw new ArgumentException("Invalid path: must be relative without '..'");
    }
}
