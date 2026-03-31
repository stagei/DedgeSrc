using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using DedgeAuth.Client.Authorization;

namespace AiDoc.WebNew.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class LogsController : ControllerBase
{
    private readonly ILogger<LogsController> _logger;

    public LogsController(ILogger<LogsController> logger)
    {
        _logger = logger;
    }

    [HttpGet]
    [RequireAppPermission(AppRoles.Admin)]
    public IActionResult ListLogs()
    {
        var logsDir = Path.Combine(AppContext.BaseDirectory, "logs");
        if (!Directory.Exists(logsDir))
            return Ok(new { files = Array.Empty<object>(), logsDir, uncPath = ToUncPath(logsDir) });

        var files = Directory.GetFiles(logsDir, "*.txt")
            .Concat(Directory.GetFiles(logsDir, "*.log"))
            .Select(f => new FileInfo(f))
            .OrderByDescending(f => f.LastWriteTimeUtc)
            .Select(f => new
            {
                name = f.Name,
                sizeBytes = f.Length,
                lastModified = f.LastWriteTimeUtc,
                sizeFormatted = FormatBytes(f.Length)
            })
            .ToList();

        var rebuildLogsDir = Path.Combine(AppContext.BaseDirectory, "logs", "rebuild");
        var rebuildFiles = new List<object>();
        if (Directory.Exists(rebuildLogsDir))
        {
            rebuildFiles = Directory.GetFiles(rebuildLogsDir, "*.log")
                .Select(f => new FileInfo(f))
                .OrderByDescending(f => f.LastWriteTimeUtc)
                .Select(f => (object)new
                {
                    name = f.Name,
                    sizeBytes = f.Length,
                    lastModified = f.LastWriteTimeUtc,
                    sizeFormatted = FormatBytes(f.Length)
                })
                .ToList();
        }

        return Ok(new
        {
            appLogs = files,
            rebuildLogs = rebuildFiles,
            logsDir,
            uncPath = ToUncPath(logsDir)
        });
    }

    [HttpGet("{fileName}")]
    [RequireAppPermission(AppRoles.Admin)]
    public IActionResult GetLog(string fileName, [FromQuery] int? tail = null)
    {
        if (fileName.Contains("..") || fileName.Contains('/') || fileName.Contains('\\'))
            return BadRequest(new { error = "Invalid filename" });

        var filePath = Path.Combine(AppContext.BaseDirectory, "logs", fileName);
        if (!System.IO.File.Exists(filePath))
        {
            filePath = Path.Combine(AppContext.BaseDirectory, "logs", "rebuild", fileName);
            if (!System.IO.File.Exists(filePath))
                return NotFound(new { error = $"Log file '{fileName}' not found" });
        }

        using var stream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        using var reader = new StreamReader(stream);
        var content = reader.ReadToEnd();

        if (tail.HasValue && tail.Value > 0)
        {
            var lines = content.Split('\n');
            var startIndex = Math.Max(0, lines.Length - tail.Value);
            content = string.Join('\n', lines.Skip(startIndex));
        }

        return Ok(new
        {
            fileName,
            filePath,
            uncPath = ToUncPath(filePath),
            lineCount = content.Split('\n').Length,
            content
        });
    }

    [HttpGet("rebuild/{ragName}")]
    [RequireAppPermission(AppRoles.Admin, AppRoles.User, AppRoles.ReadOnly)]
    public IActionResult GetRebuildLog(string ragName, [FromQuery] int? tail = null)
    {
        var rebuildLogsDir = Path.Combine(AppContext.BaseDirectory, "logs", "rebuild");
        if (!Directory.Exists(rebuildLogsDir))
            return NotFound(new { error = "No rebuild logs directory" });

        var logFiles = Directory.GetFiles(rebuildLogsDir, $"{ragName}*.log")
            .OrderByDescending(f => System.IO.File.GetLastWriteTimeUtc(f))
            .ToList();

        if (logFiles.Count == 0)
            return NotFound(new { error = $"No rebuild logs for '{ragName}'" });

        var filePath = logFiles[0];
        using var stream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        using var reader = new StreamReader(stream);
        var content = reader.ReadToEnd();

        if (tail.HasValue && tail.Value > 0)
        {
            var lines = content.Split('\n');
            var startIndex = Math.Max(0, lines.Length - tail.Value);
            content = string.Join('\n', lines.Skip(startIndex));
        }

        return Ok(new
        {
            ragName,
            fileName = Path.GetFileName(filePath),
            uncPath = ToUncPath(filePath),
            lineCount = content.Split('\n').Length,
            allLogFiles = logFiles.Select(Path.GetFileName).ToList(),
            content
        });
    }

    [HttpGet("paths")]
    [RequireAppPermission(AppRoles.Admin)]
    public IActionResult GetLogPaths()
    {
        var baseDir = AppContext.BaseDirectory;
        var logsDir = Path.Combine(baseDir, "logs");
        var rebuildLogsDir = Path.Combine(logsDir, "rebuild");
        var rebuildStatusDir = Path.Combine(
            Environment.GetEnvironmentVariable("OptPath") ?? @"C:\opt",
            "data", "Rebuild-RagIndex");

        return Ok(new
        {
            appBaseDir = baseDir,
            appBaseDirUnc = ToUncPath(baseDir),
            logsDir,
            logsDirUnc = ToUncPath(logsDir),
            rebuildLogsDir,
            rebuildLogsDirUnc = ToUncPath(rebuildLogsDir),
            rebuildStatusDir,
            rebuildStatusDirUnc = ToUncPath(rebuildStatusDir)
        });
    }

    private static string ToUncPath(string localPath)
    {
        var machineName = Environment.MachineName;
        if (localPath.Length >= 2 && localPath[1] == ':')
        {
            var drive = char.ToLower(localPath[0]);
            var rest = localPath[2..];
            return $@"\\{machineName}\{drive}${rest}";
        }
        return localPath;
    }

    private static string FormatBytes(long bytes) => bytes switch
    {
        < 1024 => $"{bytes} B",
        < 1024 * 1024 => $"{bytes / 1024.0:F1} KB",
        < 1024 * 1024 * 1024 => $"{bytes / (1024.0 * 1024):F1} MB",
        _ => $"{bytes / (1024.0 * 1024 * 1024):F1} GB"
    };
}
