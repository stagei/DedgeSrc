using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using ServerMonitor.Core.Configuration;

namespace ServerMonitor.Controllers;

/// <summary>
/// REST API for querying SQL error log files
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public class LogFilesController : ControllerBase
{
    private readonly IOptionsMonitor<SurveillanceConfiguration> _config;
    private readonly ILogger<LogFilesController> _logger;

    public LogFilesController(
        IOptionsMonitor<SurveillanceConfiguration> config,
        ILogger<LogFilesController> logger)
    {
        _config = config;
        _logger = logger;
    }

    /// <summary>
    /// Gets a list of SQL error log files for the current server
    /// </summary>
    /// <returns>List of log file info (name, size, modified date)</returns>
    [HttpGet("sqlerrors")]
    [ProducesResponseType(typeof(List<SqlErrorLogFileInfo>), 200)]
    public IActionResult GetSqlErrorLogFiles()
    {
        try
        {
            var settings = _config.CurrentValue.Db2DiagMonitoring;
            var logPathTemplate = settings.SqlErrorLogPath;
            
            if (string.IsNullOrEmpty(logPathTemplate))
            {
                return Ok(new List<SqlErrorLogFileInfo>());
            }
            
            // Get the directory from the template
            var directory = Path.GetDirectoryName(logPathTemplate);
            if (string.IsNullOrEmpty(directory) || !Directory.Exists(directory))
            {
                _logger.LogDebug("SQL error log directory does not exist: {Directory}", directory);
                return Ok(new List<SqlErrorLogFileInfo>());
            }
            
            // Build pattern to match current server's files
            var serverName = Environment.MachineName;
            var pattern = $"{serverName}_*_sqlerrors.log";
            
            var files = Directory.GetFiles(directory, pattern)
                .Select(f => new FileInfo(f))
                .OrderByDescending(f => f.LastWriteTimeUtc)
                .Take(30) // Limit to last 30 files
                .Select(f => new SqlErrorLogFileInfo
                {
                    FileName = f.Name,
                    FullPath = f.FullName,
                    SizeBytes = f.Length,
                    LastModified = f.LastWriteTimeUtc,
                    LineCount = CountLines(f.FullName)
                })
                .ToList();
            
            _logger.LogDebug("Found {Count} SQL error log files for {Server}", files.Count, serverName);
            return Ok(files);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to list SQL error log files");
            return StatusCode(500, new { error = ex.Message });
        }
    }

    /// <summary>
    /// Gets the contents of a specific SQL error log file
    /// </summary>
    /// <param name="fileName">The log file name (must match current server pattern)</param>
    /// <returns>File contents as text</returns>
    [HttpGet("sqlerrors/{fileName}")]
    [Produces("text/plain")]
    [ProducesResponseType(typeof(string), 200)]
    [ProducesResponseType(404)]
    [ProducesResponseType(403)]
    public IActionResult GetSqlErrorLogContent(string fileName)
    {
        try
        {
            var settings = _config.CurrentValue.Db2DiagMonitoring;
            var logPathTemplate = settings.SqlErrorLogPath;
            
            if (string.IsNullOrEmpty(logPathTemplate))
            {
                return NotFound("SQL error log path not configured");
            }
            
            // Security: Validate filename matches current server pattern
            var serverName = Environment.MachineName;
            if (!fileName.StartsWith($"{serverName}_", StringComparison.OrdinalIgnoreCase))
            {
                _logger.LogWarning("Attempted to access log file for different server: {FileName}", fileName);
                return Forbid();
            }
            
            // Security: Prevent path traversal
            if (fileName.Contains("..") || fileName.Contains("/") || fileName.Contains("\\"))
            {
                _logger.LogWarning("Attempted path traversal in log file request: {FileName}", fileName);
                return BadRequest("Invalid file name");
            }
            
            // Build full path
            var directory = Path.GetDirectoryName(logPathTemplate);
            if (string.IsNullOrEmpty(directory))
            {
                return NotFound("Log directory not configured");
            }
            
            var fullPath = Path.Combine(directory, fileName);
            
            if (!System.IO.File.Exists(fullPath))
            {
                return NotFound($"Log file not found: {fileName}");
            }
            
            // Read file contents
            var contents = System.IO.File.ReadAllText(fullPath);
            
            _logger.LogDebug("Served SQL error log file: {FileName} ({Length} bytes)", fileName, contents.Length);
            return Content(contents, "text/plain");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to read SQL error log file: {FileName}", fileName);
            return StatusCode(500, new { error = ex.Message });
        }
    }

    /// <summary>
    /// Count lines in a file (quick estimate for display)
    /// </summary>
    private static int CountLines(string filePath)
    {
        try
        {
            return System.IO.File.ReadLines(filePath).Count();
        }
        catch
        {
            return 0;
        }
    }
}

/// <summary>
/// Information about a SQL error log file
/// </summary>
public class SqlErrorLogFileInfo
{
    /// <summary>File name only</summary>
    public string FileName { get; set; } = string.Empty;
    
    /// <summary>Full path to the file</summary>
    public string FullPath { get; set; } = string.Empty;
    
    /// <summary>File size in bytes</summary>
    public long SizeBytes { get; set; }
    
    /// <summary>Last modified timestamp (UTC)</summary>
    public DateTime LastModified { get; set; }
    
    /// <summary>Approximate number of lines in the file</summary>
    public int LineCount { get; set; }
}
