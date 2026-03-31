using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using GenericLogHandler.Data;
using GenericLogHandler.WebApi.Models;
using GenericLogHandler.WebApi.Services;

namespace GenericLogHandler.WebApi.Controllers;

/// <summary>
/// Maintenance API: import status, health, service control. Used by maintenance UI.
/// </summary>
[ApiController]
[Route("api/maintenance")]
[Produces("application/json")]
public class MaintenanceController : ControllerBase
{
    private readonly LoggingDbContext _context;
    private readonly ILogger<MaintenanceController> _logger;
    private readonly IWindowsServiceControlService _serviceControl;
    private readonly LogSanitationService _sanitationService;

    public MaintenanceController(
        LoggingDbContext context,
        ILogger<MaintenanceController> logger,
        IWindowsServiceControlService serviceControl,
        LogSanitationService sanitationService)
    {
        _context = context;
        _logger = logger;
        _serviceControl = serviceControl;
        _sanitationService = sanitationService;
    }

    /// <summary>
    /// Get status of Import Service and Alert Agent Windows services
    /// </summary>
    [HttpGet("services")]
    [ProducesResponseType(typeof(ApiResponse<ServicesStatusDto>), 200)]
    [ProducesResponseType(503)]
    public IActionResult GetServices()
    {
        try
        {
            var result = new ServicesStatusDto
            {
                Import = _serviceControl.GetServiceStatus(_serviceControl.ImportServiceName),
                Agent = _serviceControl.GetServiceStatus(_serviceControl.AlertAgentServiceName)
            };
            return Ok(ApiResponse<ServicesStatusDto>.CreateSuccess(result));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving service status");
            return StatusCode(503, ApiResponse<ServicesStatusDto>.CreateError("Error: " + ex.Message));
        }
    }

    /// <summary>
    /// Start the Import Service Windows service
    /// </summary>
    [HttpPost("services/import/start")]
    [ProducesResponseType(typeof(ApiResponse<ServiceActionDto>), 200)]
    [ProducesResponseType(403)]
    [ProducesResponseType(404)]
    [ProducesResponseType(503)]
    public IActionResult StartImportService()
    {
        var result = _serviceControl.StartService(_serviceControl.ImportServiceName);
        return ServiceActionResult(result, "Start Import Service");
    }

    /// <summary>
    /// Stop the Import Service Windows service
    /// </summary>
    [HttpPost("services/import/stop")]
    [ProducesResponseType(typeof(ApiResponse<ServiceActionDto>), 200)]
    [ProducesResponseType(403)]
    [ProducesResponseType(404)]
    [ProducesResponseType(503)]
    public IActionResult StopImportService()
    {
        var result = _serviceControl.StopService(_serviceControl.ImportServiceName);
        return ServiceActionResult(result, "Stop Import Service");
    }

    /// <summary>
    /// Start the Alert Agent Windows service
    /// </summary>
    [HttpPost("services/agent/start")]
    [ProducesResponseType(typeof(ApiResponse<ServiceActionDto>), 200)]
    [ProducesResponseType(403)]
    [ProducesResponseType(404)]
    [ProducesResponseType(503)]
    public IActionResult StartAgentService()
    {
        var result = _serviceControl.StartService(_serviceControl.AlertAgentServiceName);
        return ServiceActionResult(result, "Start Alert Agent");
    }

    /// <summary>
    /// Stop the Alert Agent Windows service
    /// </summary>
    [HttpPost("services/agent/stop")]
    [ProducesResponseType(typeof(ApiResponse<ServiceActionDto>), 200)]
    [ProducesResponseType(403)]
    [ProducesResponseType(404)]
    [ProducesResponseType(503)]
    public IActionResult StopAgentService()
    {
        var result = _serviceControl.StopService(_serviceControl.AlertAgentServiceName);
        return ServiceActionResult(result, "Stop Alert Agent");
    }

    private IActionResult ServiceActionResult(ServiceActionResult result, string operation)
    {
        var dto = new ServiceActionDto { Success = result.Success, Message = result.Message };
        if (result.Success)
            return Ok(ApiResponse<ServiceActionDto>.CreateSuccess(dto));
        if (result.IsAccessDenied)
        {
            _logger.LogWarning("{Operation} failed (access denied): {Message}", operation, result.Message);
            return StatusCode(403, ApiResponse<ServiceActionDto>.CreateError(result.Message));
        }
        if (result.IsNotFound)
        {
            _logger.LogWarning("{Operation} failed (service not found): {Message}", operation, result.Message);
            return NotFound(ApiResponse<ServiceActionDto>.CreateError(result.Message));
        }
        if (result.IsUnsupported)
        {
            _logger.LogWarning("{Operation} failed (unsupported): {Message}", operation, result.Message);
            return StatusCode(503, ApiResponse<ServiceActionDto>.CreateError(result.Message));
        }
        _logger.LogWarning("{Operation} failed: {Message}", operation, result.Message);
        return BadRequest(ApiResponse<ServiceActionDto>.CreateError(result.Message));
    }

    /// <summary>
    /// Drop and recreate all app tables from the current EF model (PostgreSQL only).
    /// Preserves import_sources and import_level_filters (configuration data).
    /// </summary>
    [HttpPost("recreate-schema")]
    [ProducesResponseType(typeof(ApiResponse<object>), 200)]
    public async Task<IActionResult> RecreateSchema()
    {
        try
        {
            var provider = _context.Database.ProviderName ?? string.Empty;
            if (!provider.Contains("Npgsql", StringComparison.OrdinalIgnoreCase))
            {
                return BadRequest(ApiResponse<object>.CreateError("Recreate schema is only supported for PostgreSQL."));
            }

            var savedSources = await _context.ImportSources.AsNoTracking().ToListAsync();
            var savedFilters = await _context.ImportLevelFilters.AsNoTracking().ToListAsync();

            await _context.Database.ExecuteSqlRawAsync("DROP SCHEMA public CASCADE");
            await _context.Database.ExecuteSqlRawAsync("CREATE SCHEMA public");
            await _context.Database.ExecuteSqlRawAsync("GRANT ALL ON SCHEMA public TO public");

            await _context.Database.MigrateAsync();

            if (savedSources.Count > 0)
            {
                _context.ImportSources.AddRange(savedSources);
                await _context.SaveChangesAsync();
                _logger.LogInformation("Restored {Count} import sources after schema recreate", savedSources.Count);
            }
            if (savedFilters.Count > 0)
            {
                _context.ImportLevelFilters.AddRange(savedFilters);
                await _context.SaveChangesAsync();
                _logger.LogInformation("Restored {Count} level filters after schema recreate", savedFilters.Count);
            }

            _logger.LogInformation("Schema recreated from migrations. Import configuration preserved.");
            return Ok(ApiResponse<object>.CreateSuccess(new { Message = "Schema recreated. Import sources and level filters preserved." }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error recreating schema");
            return BadRequest(ApiResponse<object>.CreateError("Error: " + ex.Message));
        }
    }

    /// <summary>
    /// Truncate log_entries and optional "files" table.
    /// When resetImportTracking is true, also truncates import_status so the Import Service re-imports all files.
    /// </summary>
    [HttpPost("truncate-log-entries")]
    [ProducesResponseType(typeof(ApiResponse<object>), 200)]
    public async Task<IActionResult> TruncateLogEntries([FromQuery] bool resetImportTracking = false)
    {
        try
        {
            var provider = _context.Database.ProviderName ?? string.Empty;
            if (!provider.Contains("Npgsql", StringComparison.OrdinalIgnoreCase))
            {
                return BadRequest(ApiResponse<object>.CreateError("Truncate is only supported for PostgreSQL."));
            }
            await _context.Database.ExecuteSqlRawAsync("TRUNCATE TABLE log_entries RESTART IDENTITY CASCADE");
            try
            {
                await _context.Database.ExecuteSqlRawAsync("TRUNCATE TABLE files RESTART IDENTITY CASCADE");
            }
            catch (PostgresException ex) when (ex.SqlState == "42P01")
            {
                // 42P01 = undefined_table - files table does not exist, ignore
            }

            if (resetImportTracking)
            {
                await _context.Database.ExecuteSqlRawAsync("TRUNCATE TABLE import_status RESTART IDENTITY CASCADE");
                _logger.LogInformation("Truncated log_entries, import_status (and files if present). Import Service will re-import all files.");
                return Ok(ApiResponse<object>.CreateSuccess(new { Message = "Truncated log_entries and import_status. Import Service will re-import all configured files." }));
            }

            _logger.LogInformation("Truncated log_entries (and files if present). Kept import_status and saved_filters.");
            return Ok(ApiResponse<object>.CreateSuccess(new { Message = "Truncated log_entries (and files if present)." }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error truncating log_entries");
            return BadRequest(ApiResponse<object>.CreateError("Error: " + ex.Message));
        }
    }

    /// <summary>
    /// Get all import status records (per source/file)
    /// </summary>
    [HttpGet("import-status")]
    [ProducesResponseType(typeof(ApiResponse<List<ImportStatusDto>>), 200)]
    public async Task<IActionResult> GetImportStatus()
    {
        try
        {
            var list = await _context.ImportStatuses
                .OrderBy(s => s.SourceName)
                .ThenBy(s => s.FilePath)
                .Select(s => new ImportStatusDto
                {
                    Id = s.Id,
                    SourceName = s.SourceName,
                    SourceType = s.SourceType,
                    FilePath = s.FilePath,
                    LastProcessedTimestamp = s.LastProcessedTimestamp,
                    LastImportTimestamp = s.LastImportTimestamp,
                    RecordsProcessed = s.RecordsProcessed,
                    RecordsFailed = s.RecordsFailed,
                    Status = s.Status.ToString(),
                    ErrorMessage = s.ErrorMessage,
                    ProcessingDurationMs = s.ProcessingDurationMs,
                    LastProcessedByteOffset = s.LastProcessedByteOffset,
                    FileHash = s.FileHash,
                    LastFileSize = s.LastFileSize,
                    FileCreationDate = s.FileCreationDate,
                    LastProcessedLine = s.LastProcessedLine
                })
                .ToListAsync();

            return Ok(ApiResponse<List<ImportStatusDto>>.CreateSuccess(list));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving import status");
            return BadRequest(ApiResponse<List<ImportStatusDto>>.CreateError("Error: " + ex.Message));
        }
    }

    /// <summary>
    /// Run VACUUM ANALYZE on all tables to update statistics and reclaim dead tuples.
    /// PostgreSQL autovacuum handles this automatically, but this allows manual trigger.
    /// </summary>
    [HttpPost("vacuum-analyze")]
    [ProducesResponseType(typeof(ApiResponse<DbMaintenanceResultDto>), 200)]
    public async Task<IActionResult> VacuumAnalyze([FromQuery] bool full = false)
    {
        try
        {
            var provider = _context.Database.ProviderName ?? string.Empty;
            if (!provider.Contains("Npgsql", StringComparison.OrdinalIgnoreCase))
            {
                return BadRequest(ApiResponse<DbMaintenanceResultDto>.CreateError("VACUUM ANALYZE is only supported for PostgreSQL."));
            }

            var sw = System.Diagnostics.Stopwatch.StartNew();
            var connection = _context.Database.GetDbConnection();
            await connection.OpenAsync();
            
            // VACUUM cannot run inside a transaction, so we use a separate command
            using var command = connection.CreateCommand();
            // VACUUM FULL reclaims more space but locks tables; regular VACUUM is less intrusive
            command.CommandText = full ? "VACUUM FULL ANALYZE" : "VACUUM ANALYZE";
            command.CommandTimeout = 600; // 10 minutes timeout for large databases
            await command.ExecuteNonQueryAsync();
            
            sw.Stop();
            _logger.LogInformation("VACUUM ANALYZE completed in {Duration}ms (full={Full})", sw.ElapsedMilliseconds, full);
            
            return Ok(ApiResponse<DbMaintenanceResultDto>.CreateSuccess(new DbMaintenanceResultDto
            {
                Operation = full ? "VACUUM FULL ANALYZE" : "VACUUM ANALYZE",
                Success = true,
                DurationMs = sw.ElapsedMilliseconds,
                Message = $"Statistics updated and dead tuples reclaimed in {sw.ElapsedMilliseconds}ms"
            }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error running VACUUM ANALYZE");
            return BadRequest(ApiResponse<DbMaintenanceResultDto>.CreateError("Error: " + ex.Message));
        }
    }

    /// <summary>
    /// Run REINDEX on the log_entries table to rebuild indexes.
    /// Useful after large bulk inserts or deletes to optimize index performance.
    /// </summary>
    [HttpPost("reindex")]
    [ProducesResponseType(typeof(ApiResponse<DbMaintenanceResultDto>), 200)]
    public async Task<IActionResult> ReindexLogEntries([FromQuery] bool concurrent = true)
    {
        try
        {
            var provider = _context.Database.ProviderName ?? string.Empty;
            if (!provider.Contains("Npgsql", StringComparison.OrdinalIgnoreCase))
            {
                return BadRequest(ApiResponse<DbMaintenanceResultDto>.CreateError("REINDEX is only supported for PostgreSQL."));
            }

            var sw = System.Diagnostics.Stopwatch.StartNew();
            var connection = _context.Database.GetDbConnection();
            await connection.OpenAsync();
            
            using var command = connection.CreateCommand();
            // CONCURRENTLY allows the table to remain accessible during reindex (PostgreSQL 12+)
            command.CommandText = concurrent 
                ? "REINDEX TABLE CONCURRENTLY log_entries" 
                : "REINDEX TABLE log_entries";
            command.CommandTimeout = 1800; // 30 minutes timeout for large tables
            await command.ExecuteNonQueryAsync();
            
            sw.Stop();
            _logger.LogInformation("REINDEX log_entries completed in {Duration}ms (concurrent={Concurrent})", sw.ElapsedMilliseconds, concurrent);
            
            return Ok(ApiResponse<DbMaintenanceResultDto>.CreateSuccess(new DbMaintenanceResultDto
            {
                Operation = concurrent ? "REINDEX CONCURRENTLY" : "REINDEX",
                Success = true,
                DurationMs = sw.ElapsedMilliseconds,
                Message = $"Indexes rebuilt in {sw.ElapsedMilliseconds}ms"
            }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error running REINDEX");
            return BadRequest(ApiResponse<DbMaintenanceResultDto>.CreateError("Error: " + ex.Message));
        }
    }

    /// <summary>
    /// Update table statistics only (ANALYZE without VACUUM).
    /// Lighter than VACUUM ANALYZE - just updates planner statistics.
    /// </summary>
    [HttpPost("analyze")]
    [ProducesResponseType(typeof(ApiResponse<DbMaintenanceResultDto>), 200)]
    public async Task<IActionResult> AnalyzeTables()
    {
        try
        {
            var provider = _context.Database.ProviderName ?? string.Empty;
            if (!provider.Contains("Npgsql", StringComparison.OrdinalIgnoreCase))
            {
                return BadRequest(ApiResponse<DbMaintenanceResultDto>.CreateError("ANALYZE is only supported for PostgreSQL."));
            }

            var sw = System.Diagnostics.Stopwatch.StartNew();
            await _context.Database.ExecuteSqlRawAsync("ANALYZE log_entries");
            await _context.Database.ExecuteSqlRawAsync("ANALYZE import_status");
            
            sw.Stop();
            _logger.LogInformation("ANALYZE completed in {Duration}ms", sw.ElapsedMilliseconds);
            
            return Ok(ApiResponse<DbMaintenanceResultDto>.CreateSuccess(new DbMaintenanceResultDto
            {
                Operation = "ANALYZE",
                Success = true,
                DurationMs = sw.ElapsedMilliseconds,
                Message = $"Statistics updated in {sw.ElapsedMilliseconds}ms"
            }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error running ANALYZE");
            return BadRequest(ApiResponse<DbMaintenanceResultDto>.CreateError("Error: " + ex.Message));
        }
    }

    /// <summary>
    /// Create a PostgreSQL database backup using pg_dump.
    /// Saves to %OptPath%\data\GenericLogHandler\Backups with a timestamped filename.
    /// </summary>
    [HttpPost("backup")]
    [ProducesResponseType(typeof(ApiResponse<BackupResultDto>), 200)]
    public async Task<IActionResult> BackupDatabase()
    {
        try
        {
            var provider = _context.Database.ProviderName ?? string.Empty;
            if (!provider.Contains("Npgsql", StringComparison.OrdinalIgnoreCase))
            {
                return BadRequest(ApiResponse<BackupResultDto>.CreateError("Backup is only supported for PostgreSQL."));
            }

            var connStr = _context.Database.GetConnectionString() ?? string.Empty;
            var csb = new NpgsqlConnectionStringBuilder(connStr);

            var optPath = Environment.GetEnvironmentVariable("OptPath") ?? @"C:\opt";
            var backupDir = Path.Combine(optPath, "data", "GenericLogHandler", "Backups");
            Directory.CreateDirectory(backupDir);

            var timestamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
            var fileName = $"GenericLogHandler_{timestamp}.sql";
            var filePath = Path.Combine(backupDir, fileName);

            var pgDump = FindPgDump();
            if (pgDump == null)
            {
                return BadRequest(ApiResponse<BackupResultDto>.CreateError(
                    "pg_dump not found. Ensure PostgreSQL client tools are installed and on PATH."));
            }

            var sw = System.Diagnostics.Stopwatch.StartNew();

            var psi = new System.Diagnostics.ProcessStartInfo
            {
                FileName = pgDump,
                Arguments = $"--host={csb.Host} --port={csb.Port} --username={csb.Username} --format=plain --no-owner --no-acl --file=\"{filePath}\" {csb.Database}",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            };
            psi.Environment["PGPASSWORD"] = csb.Password;

            using var process = System.Diagnostics.Process.Start(psi);
            if (process == null)
            {
                return BadRequest(ApiResponse<BackupResultDto>.CreateError("Failed to start pg_dump process."));
            }

            var stderr = await process.StandardError.ReadToEndAsync();
            await process.WaitForExitAsync();
            sw.Stop();

            if (process.ExitCode != 0)
            {
                _logger.LogError("pg_dump failed with exit code {ExitCode}: {Error}", process.ExitCode, stderr);
                return BadRequest(ApiResponse<BackupResultDto>.CreateError($"pg_dump failed: {stderr.Trim()}"));
            }

            var fileInfo = new FileInfo(filePath);
            _logger.LogInformation("Database backup created: {Path} ({Size} bytes, {Duration}ms)",
                filePath, fileInfo.Length, sw.ElapsedMilliseconds);

            return Ok(ApiResponse<BackupResultDto>.CreateSuccess(new BackupResultDto
            {
                FileName = fileName,
                FilePath = filePath,
                FileSizeBytes = fileInfo.Length,
                FileSize = FormatBytes(fileInfo.Length),
                DurationMs = sw.ElapsedMilliseconds,
                CreatedAt = DateTime.UtcNow,
                Database = csb.Database ?? "unknown",
                Host = csb.Host ?? "unknown"
            }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating database backup");
            return BadRequest(ApiResponse<BackupResultDto>.CreateError("Error: " + ex.Message));
        }
    }

    /// <summary>
    /// List existing database backup files.
    /// </summary>
    [HttpGet("backups")]
    [ProducesResponseType(typeof(ApiResponse<List<BackupFileDto>>), 200)]
    public IActionResult ListBackups()
    {
        try
        {
            var optPath = Environment.GetEnvironmentVariable("OptPath") ?? @"C:\opt";
            var backupDir = Path.Combine(optPath, "data", "GenericLogHandler", "Backups");

            if (!Directory.Exists(backupDir))
            {
                return Ok(ApiResponse<List<BackupFileDto>>.CreateSuccess(new List<BackupFileDto>()));
            }

            var files = Directory.GetFiles(backupDir, "*.sql")
                .Concat(Directory.GetFiles(backupDir, "*.dump"))
                .Select(f => new FileInfo(f))
                .OrderByDescending(f => f.CreationTimeUtc)
                .Take(20)
                .Select(f => new BackupFileDto
                {
                    FileName = f.Name,
                    FilePath = f.FullName,
                    FileSizeBytes = f.Length,
                    FileSize = FormatBytes(f.Length),
                    CreatedAt = f.CreationTimeUtc
                })
                .ToList();

            return Ok(ApiResponse<List<BackupFileDto>>.CreateSuccess(files));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error listing backups");
            return BadRequest(ApiResponse<List<BackupFileDto>>.CreateError("Error: " + ex.Message));
        }
    }

    /// <summary>
    /// Delete a backup file by filename.
    /// </summary>
    [HttpDelete("backups/{fileName}")]
    [ProducesResponseType(typeof(ApiResponse<object>), 200)]
    public IActionResult DeleteBackup(string fileName)
    {
        try
        {
            if (fileName.Contains("..") || fileName.Contains('/') || fileName.Contains('\\'))
            {
                return BadRequest(ApiResponse<object>.CreateError("Invalid filename."));
            }

            var optPath = Environment.GetEnvironmentVariable("OptPath") ?? @"C:\opt";
            var filePath = Path.Combine(optPath, "data", "GenericLogHandler", "Backups", fileName);

            if (!System.IO.File.Exists(filePath))
            {
                return NotFound(ApiResponse<object>.CreateError("Backup file not found."));
            }

            System.IO.File.Delete(filePath);
            _logger.LogInformation("Deleted backup file: {Path}", filePath);
            return Ok(ApiResponse<object>.CreateSuccess(new { Message = $"Deleted {fileName}" }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting backup {FileName}", fileName);
            return BadRequest(ApiResponse<object>.CreateError("Error: " + ex.Message));
        }
    }

    private static string? FindPgDump()
    {
        var candidates = new[]
        {
            @"C:\Program Files\PostgreSQL\17\bin\pg_dump.exe",
            @"C:\Program Files\PostgreSQL\16\bin\pg_dump.exe",
            @"C:\Program Files\PostgreSQL\15\bin\pg_dump.exe",
            @"C:\Program Files\PostgreSQL\14\bin\pg_dump.exe"
        };

        foreach (var path in candidates)
        {
            if (System.IO.File.Exists(path)) return path;
        }

        // Try PATH
        try
        {
            var psi = new System.Diagnostics.ProcessStartInfo
            {
                FileName = "where",
                Arguments = "pg_dump",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                CreateNoWindow = true
            };
            using var p = System.Diagnostics.Process.Start(psi);
            if (p != null)
            {
                var output = p.StandardOutput.ReadLine();
                p.WaitForExit(5000);
                if (p.ExitCode == 0 && !string.IsNullOrEmpty(output))
                    return output.Trim();
            }
        }
        catch { }

        return null;
    }

    private static string FormatBytes(long bytes)
    {
        if (bytes < 1024) return bytes + " B";
        if (bytes < 1024 * 1024) return (bytes / 1024.0).ToString("F1") + " KB";
        if (bytes < 1024L * 1024 * 1024) return (bytes / (1024.0 * 1024)).ToString("F1") + " MB";
        return (bytes / (1024.0 * 1024 * 1024)).ToString("F2") + " GB";
    }

    /// <summary>
    /// Get database maintenance status including table sizes, dead tuples, and last vacuum/analyze times.
    /// </summary>
    [HttpGet("db-health")]
    [ProducesResponseType(typeof(ApiResponse<DbHealthDto>), 200)]
    public async Task<IActionResult> GetDatabaseHealth()
    {
        try
        {
            var provider = _context.Database.ProviderName ?? string.Empty;
            if (!provider.Contains("Npgsql", StringComparison.OrdinalIgnoreCase))
            {
                return BadRequest(ApiResponse<DbHealthDto>.CreateError("Database health is only supported for PostgreSQL."));
            }

            var connection = _context.Database.GetDbConnection();
            await connection.OpenAsync();
            
            var tables = new List<TableHealthDto>();
            
            // Get table statistics from pg_stat_user_tables
            using (var command = connection.CreateCommand())
            {
                command.CommandText = @"
                    SELECT 
                        schemaname,
                        relname as table_name,
                        n_live_tup as live_tuples,
                        n_dead_tup as dead_tuples,
                        n_tup_ins as inserts_since_vacuum,
                        n_tup_upd as updates_since_vacuum,
                        n_tup_del as deletes_since_vacuum,
                        last_vacuum,
                        last_autovacuum,
                        last_analyze,
                        last_autoanalyze,
                        pg_size_pretty(pg_total_relation_size(schemaname || '.' || relname)) as total_size,
                        pg_total_relation_size(schemaname || '.' || relname) as total_size_bytes
                    FROM pg_stat_user_tables
                    WHERE relname IN ('log_entries', 'import_status', 'saved_filters', 'alert_history')
                    ORDER BY pg_total_relation_size(schemaname || '.' || relname) DESC";
                
                using var reader = await command.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    tables.Add(new TableHealthDto
                    {
                        TableName = reader.GetString(1),
                        LiveTuples = reader.IsDBNull(2) ? 0 : reader.GetInt64(2),
                        DeadTuples = reader.IsDBNull(3) ? 0 : reader.GetInt64(3),
                        InsertsSinceVacuum = reader.IsDBNull(4) ? 0 : reader.GetInt64(4),
                        UpdatesSinceVacuum = reader.IsDBNull(5) ? 0 : reader.GetInt64(5),
                        DeletesSinceVacuum = reader.IsDBNull(6) ? 0 : reader.GetInt64(6),
                        LastVacuum = reader.IsDBNull(7) ? null : reader.GetDateTime(7),
                        LastAutovacuum = reader.IsDBNull(8) ? null : reader.GetDateTime(8),
                        LastAnalyze = reader.IsDBNull(9) ? null : reader.GetDateTime(9),
                        LastAutoanalyze = reader.IsDBNull(10) ? null : reader.GetDateTime(10),
                        TotalSize = reader.IsDBNull(11) ? "0 bytes" : reader.GetString(11),
                        TotalSizeBytes = reader.IsDBNull(12) ? 0 : reader.GetInt64(12)
                    });
                }
            }

            // Get index statistics
            var indexes = new List<IndexHealthDto>();
            using (var command = connection.CreateCommand())
            {
                command.CommandText = @"
                    SELECT 
                        indexrelname as index_name,
                        relname as table_name,
                        idx_scan as scans,
                        idx_tup_read as tuples_read,
                        idx_tup_fetch as tuples_fetched,
                        pg_size_pretty(pg_relation_size(indexrelid)) as size
                    FROM pg_stat_user_indexes
                    WHERE relname IN ('log_entries', 'import_status')
                    ORDER BY idx_scan DESC";
                
                using var reader = await command.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    indexes.Add(new IndexHealthDto
                    {
                        IndexName = reader.GetString(0),
                        TableName = reader.GetString(1),
                        Scans = reader.IsDBNull(2) ? 0 : reader.GetInt64(2),
                        TuplesRead = reader.IsDBNull(3) ? 0 : reader.GetInt64(3),
                        TuplesFetched = reader.IsDBNull(4) ? 0 : reader.GetInt64(4),
                        Size = reader.IsDBNull(5) ? "0 bytes" : reader.GetString(5)
                    });
                }
            }

            // Check autovacuum settings
            string autovacuumEnabled = "unknown";
            using (var command = connection.CreateCommand())
            {
                command.CommandText = "SHOW autovacuum";
                var result = await command.ExecuteScalarAsync();
                autovacuumEnabled = result?.ToString() ?? "unknown";
            }

            var health = new DbHealthDto
            {
                Tables = tables,
                Indexes = indexes,
                AutovacuumEnabled = autovacuumEnabled == "on",
                RetrievedAt = DateTime.UtcNow
            };

            return Ok(ApiResponse<DbHealthDto>.CreateSuccess(health));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving database health");
            return BadRequest(ApiResponse<DbHealthDto>.CreateError("Error: " + ex.Message));
        }
    }

    /// <summary>
    /// Preview what sanitation would delete without actually deleting.
    /// Shows count of entries that would be deleted vs protected entries.
    /// </summary>
    [HttpGet("sanitation/preview")]
    [ProducesResponseType(typeof(ApiResponse<SanitationPreview>), 200)]
    public async Task<IActionResult> PreviewSanitation([FromQuery] int? retentionDays = null)
    {
        try
        {
            var preview = await _sanitationService.PreviewSanitationAsync(retentionDays);
            return Ok(ApiResponse<SanitationPreview>.CreateSuccess(preview));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error previewing sanitation");
            return BadRequest(ApiResponse<SanitationPreview>.CreateError("Error: " + ex.Message));
        }
    }

    /// <summary>
    /// Run sanitation to delete old unprotected log entries.
    /// Protected entries (protected = true) are never deleted.
    /// </summary>
    [HttpPost("sanitation/run")]
    [ProducesResponseType(typeof(ApiResponse<SanitationResult>), 200)]
    public async Task<IActionResult> RunSanitation()
    {
        try
        {
            var result = await _sanitationService.RunSanitationAsync();
            return Ok(ApiResponse<SanitationResult>.CreateSuccess(result));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error running sanitation");
            return BadRequest(ApiResponse<SanitationResult>.CreateError("Error: " + ex.Message));
        }
    }

    /// <summary>
    /// Get count of protected entries in the database
    /// </summary>
    [HttpGet("sanitation/protected-count")]
    [ProducesResponseType(typeof(ApiResponse<ProtectedEntriesDto>), 200)]
    public async Task<IActionResult> GetProtectedCount()
    {
        try
        {
            var total = await _context.LogEntries.CountAsync();
            var protectedCount = await _context.LogEntries.Where(e => e.Protected).CountAsync();
            
            return Ok(ApiResponse<ProtectedEntriesDto>.CreateSuccess(new ProtectedEntriesDto
            {
                TotalEntries = total,
                ProtectedEntries = protectedCount,
                UnprotectedEntries = total - protectedCount
            }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting protected count");
            return BadRequest(ApiResponse<ProtectedEntriesDto>.CreateError("Error: " + ex.Message));
        }
    }
}

/// <summary>
/// Protected entries count DTO
/// </summary>
public class ProtectedEntriesDto
{
    public int TotalEntries { get; set; }
    public int ProtectedEntries { get; set; }
    public int UnprotectedEntries { get; set; }
}

/// <summary>
/// Result of a database maintenance operation
/// </summary>
public class DbMaintenanceResultDto
{
    public string Operation { get; set; } = string.Empty;
    public bool Success { get; set; }
    public long DurationMs { get; set; }
    public string Message { get; set; } = string.Empty;
}

/// <summary>
/// Database health overview
/// </summary>
public class DbHealthDto
{
    public List<TableHealthDto> Tables { get; set; } = new();
    public List<IndexHealthDto> Indexes { get; set; } = new();
    public bool AutovacuumEnabled { get; set; }
    public DateTime RetrievedAt { get; set; }
}

/// <summary>
/// Health info for a single table
/// </summary>
public class TableHealthDto
{
    public string TableName { get; set; } = string.Empty;
    public long LiveTuples { get; set; }
    public long DeadTuples { get; set; }
    public long InsertsSinceVacuum { get; set; }
    public long UpdatesSinceVacuum { get; set; }
    public long DeletesSinceVacuum { get; set; }
    public DateTime? LastVacuum { get; set; }
    public DateTime? LastAutovacuum { get; set; }
    public DateTime? LastAnalyze { get; set; }
    public DateTime? LastAutoanalyze { get; set; }
    public string TotalSize { get; set; } = string.Empty;
    public long TotalSizeBytes { get; set; }
    public double DeadTupleRatio => LiveTuples > 0 ? (double)DeadTuples / LiveTuples * 100 : 0;
}

/// <summary>
/// Health info for a single index
/// </summary>
public class IndexHealthDto
{
    public string IndexName { get; set; } = string.Empty;
    public string TableName { get; set; } = string.Empty;
    public long Scans { get; set; }
    public long TuplesRead { get; set; }
    public long TuplesFetched { get; set; }
    public string Size { get; set; } = string.Empty;
}

/// <summary>
/// DTO for import_status row
/// </summary>
public class ImportStatusDto
{
    public Guid Id { get; set; }
    public string SourceName { get; set; } = string.Empty;
    public string SourceType { get; set; } = string.Empty;
    public string FilePath { get; set; } = string.Empty;
    public DateTime? LastProcessedTimestamp { get; set; }
    public DateTime LastImportTimestamp { get; set; }
    public long RecordsProcessed { get; set; }
    public long RecordsFailed { get; set; }
    public string Status { get; set; } = string.Empty;
    public string ErrorMessage { get; set; } = string.Empty;
    public long ProcessingDurationMs { get; set; }
    public long LastProcessedByteOffset { get; set; }
    public string? FileHash { get; set; }
    public long LastFileSize { get; set; }
    public DateTime? FileCreationDate { get; set; }
    public long LastProcessedLine { get; set; }
}

/// <summary>
/// Result of a database backup operation
/// </summary>
public class BackupResultDto
{
    public string FileName { get; set; } = string.Empty;
    public string FilePath { get; set; } = string.Empty;
    public long FileSizeBytes { get; set; }
    public string FileSize { get; set; } = string.Empty;
    public long DurationMs { get; set; }
    public DateTime CreatedAt { get; set; }
    public string Database { get; set; } = string.Empty;
    public string Host { get; set; } = string.Empty;
}

/// <summary>
/// Backup file info for listing
/// </summary>
public class BackupFileDto
{
    public string FileName { get; set; } = string.Empty;
    public string FilePath { get; set; } = string.Empty;
    public long FileSizeBytes { get; set; }
    public string FileSize { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
}
