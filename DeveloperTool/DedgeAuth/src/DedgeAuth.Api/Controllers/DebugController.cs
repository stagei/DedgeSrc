using System.Reflection;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Npgsql;
using DedgeAuth.Data;

namespace DedgeAuth.Api.Controllers;

/// <summary>
/// Debug endpoints for testing and diagnostics (GlobalAdmin only)
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Authorize(Policy = "GlobalAdmin")] // Require GlobalAdmin for all debug endpoints
public class DebugController : ControllerBase
{
    private static readonly DateTime _startedAt = DateTime.UtcNow;

    private readonly AuthDbContext _context;
    private readonly IConfiguration _configuration;
    private readonly ILogger<DebugController> _logger;

    public DebugController(
        AuthDbContext context,
        IConfiguration configuration,
        ILogger<DebugController> logger)
    {
        _context = context;
        _configuration = configuration;
        _logger = logger;
    }

    /// <summary>
    /// Test database connection
    /// </summary>
    [HttpGet("db-connection")]
    public async Task<IActionResult> TestDbConnection()
    {
        var connectionString = _configuration.GetConnectionString("AuthDb");
        
        try
        {
            await using var connection = new NpgsqlConnection(connectionString);
            await connection.OpenAsync();
            
            await using var command = new NpgsqlCommand("SELECT version()", connection);
            var version = await command.ExecuteScalarAsync();

            // Don't expose connection string details - only show status
            return Ok(new
            {
                Status = "Connected",
                PostgreSQLVersion = version?.ToString()
                // ConnectionString removed for security
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Database connection failed");
            return StatusCode(500, new { error = "An error occurred while processing the request." });
        }
    }

    /// <summary>
    /// Get users using raw SQL query
    /// </summary>
    [HttpGet("users-raw")]
    public async Task<IActionResult> GetUsersRaw()
    {
        try
        {
            var connectionString = _configuration.GetConnectionString("AuthDb");
            await using var connection = new NpgsqlConnection(connectionString);
            await connection.OpenAsync();
            
            await using var command = new NpgsqlCommand(
                "SELECT id, email, display_name, is_active FROM users LIMIT 10",
                connection);
            
            await using var reader = await command.ExecuteReaderAsync();
            var users = new List<object>();
            
            while (await reader.ReadAsync())
            {
                users.Add(new
                {
                    Id = reader.GetGuid(0),
                    Email = reader.GetString(1),
                    DisplayName = reader.GetString(2),
                    IsActive = reader.GetBoolean(3)
                });
            }
            
            return Ok(new { Count = users.Count, Users = users });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error in GetUsersRaw");
            return StatusCode(500, new { error = "An error occurred while processing the request." });
        }
    }

    /// <summary>
    /// Get users using Entity Framework Core
    /// </summary>
    [HttpGet("users-ef")]
    public async Task<IActionResult> GetUsersEF()
    {
        try
        {
            var users = await _context.Users
                .Select(u => new
                {
                    u.Id,
                    u.Email,
                    u.DisplayName,
                    u.IsActive
                })
                .Take(10)
                .ToListAsync();
            
            return Ok(new { Count = users.Count, Users = users });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error in GetUsersEF");
            return StatusCode(500, new { error = "An error occurred while processing the request." });
        }
    }

    /// <summary>
    /// Get deployed version, uptime, and authentication statistics
    /// </summary>
    /// <returns>Version info, token counts, user stats, and recent login activity</returns>
    [HttpGet("status")]
    public async Task<IActionResult> GetStatus()
    {
        try
        {
            var assembly = Assembly.GetExecutingAssembly();
            var version = assembly.GetName().Version;
            var fileVersion = assembly.GetCustomAttribute<AssemblyFileVersionAttribute>()?.Version;
            var now = DateTime.UtcNow;

            // Active refresh tokens (not revoked, not expired)
            var activeRefreshTokens = await _context.RefreshTokens
                .CountAsync(t => !t.IsRevoked && t.ExpiresAt > now);

            // Total refresh tokens
            var totalRefreshTokens = await _context.RefreshTokens.CountAsync();

            // Pending (unused, unexpired) magic link tokens
            var pendingMagicLinks = await _context.LoginTokens
                .CountAsync(t => !t.IsUsed && t.ExpiresAt > now && t.TokenType == "Login");

            // Total magic link tokens
            var totalMagicLinks = await _context.LoginTokens
                .CountAsync(t => t.TokenType == "Login");

            // Used magic link tokens (successful logins via magic link)
            var usedMagicLinks = await _context.LoginTokens
                .CountAsync(t => t.IsUsed && t.TokenType == "Login");

            // User stats
            var totalUsers = await _context.Users.CountAsync();
            var activeUsers = await _context.Users.CountAsync(u => u.IsActive);
            var lockedUsers = await _context.Users
                .CountAsync(u => u.LockoutUntil != null && u.LockoutUntil > now);
            var usersWithPassword = await _context.Users
                .CountAsync(u => u.PasswordHash != null);

            // Last login across all users
            var lastLogin = await _context.Users
                .Where(u => u.LastLoginAt != null)
                .OrderByDescending(u => u.LastLoginAt)
                .Select(u => new { u.Email, u.LastLoginAt })
                .FirstOrDefaultAsync();

            // Recent logins (last 24h)
            var recentLoginCount = await _context.Users
                .CountAsync(u => u.LastLoginAt != null && u.LastLoginAt > now.AddHours(-24));

            // Last 5 logins
            var recentLogins = await _context.Users
                .Where(u => u.LastLoginAt != null)
                .OrderByDescending(u => u.LastLoginAt)
                .Take(5)
                .Select(u => new
                {
                    u.Email,
                    u.DisplayName,
                    u.LastLoginAt
                })
                .ToListAsync();

            // Registered apps
            var appCount = await _context.Apps.CountAsync();

            // Tenants
            var tenantCount = await _context.Tenants.CountAsync();

            var uptime = now - _startedAt;

            return Ok(new
            {
                version = new
                {
                    assemblyVersion = version?.ToString(),
                    fileVersion,
                    environment = Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") ?? "Production",
                    machineName = Environment.MachineName,
                    pathBase = Request.PathBase.Value ?? "",
                    dotnetVersion = Environment.Version.ToString()
                },
                uptime = new
                {
                    startedAtUtc = _startedAt,
                    hours = Math.Round(uptime.TotalHours, 1),
                    formatted = $"{(int)uptime.TotalDays}d {uptime.Hours}h {uptime.Minutes}m"
                },
                tokens = new
                {
                    activeRefreshTokens,
                    totalRefreshTokens,
                    pendingMagicLinks,
                    usedMagicLinks,
                    totalMagicLinks
                },
                users = new
                {
                    total = totalUsers,
                    active = activeUsers,
                    locked = lockedUsers,
                    withPassword = usersWithPassword,
                    loggedInLast24h = recentLoginCount
                },
                lastLogin = lastLogin != null ? new
                {
                    lastLogin.Email,
                    lastLoginUtc = lastLogin.LastLoginAt
                } : null,
                recentLogins,
                apps = appCount,
                tenants = tenantCount,
                serverTimeUtc = now
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error in GetStatus");
            return StatusCode(500, new { error = "An error occurred while processing the request." });
        }
    }

    /// <summary>
    /// Get current application configuration (secrets redacted)
    /// </summary>
    /// <returns>Auth settings, SMTP settings, CORS origins, DB connection info, and log file settings</returns>
    [HttpGet("config")]
    public async Task<IActionResult> GetConfig()
    {
        try
        {
            // Auth configuration (redact JwtSecret)
            var authSection = _configuration.GetSection("AuthConfiguration");
            var jwtSecret = authSection["JwtSecret"] ?? "";

            // DB connection - parse host/port/database, redact password
            var connectionString = _configuration.GetConnectionString("AuthDb") ?? "";
            var dbInfo = ParseConnectionString(connectionString);

            // Test DB connectivity
            string dbStatus;
            string? dbVersion = null;
            try
            {
                await using var conn = new NpgsqlConnection(connectionString);
                await conn.OpenAsync();
                await using var cmd = new NpgsqlCommand("SELECT version()", conn);
                dbVersion = (await cmd.ExecuteScalarAsync())?.ToString();
                dbStatus = "Connected";
            }
            catch (Exception ex)
            {
                dbStatus = $"Failed: {ex.Message}";
            }

            // SMTP configuration (redact password)
            var smtpSection = _configuration.GetSection("SmtpConfiguration");

            // CORS origins
            var corsOrigins = _configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? [];

            // Log file settings
            var logSection = _configuration.GetSection("LogFileSettings");

            return Ok(new
            {
                authConfiguration = new
                {
                    jwtIssuer = authSection["JwtIssuer"],
                    jwtAudience = authSection["JwtAudience"],
                    jwtSecretConfigured = !string.IsNullOrEmpty(jwtSecret),
                    jwtSecretLength = jwtSecret.Length,
                    accessTokenExpirationMinutes = authSection["AccessTokenExpirationMinutes"],
                    refreshTokenExpirationDays = authSection["RefreshTokenExpirationDays"],
                    magicLinkExpirationMinutes = authSection["MagicLinkExpirationMinutes"],
                    passwordResetExpirationHours = authSection["PasswordResetExpirationHours"],
                    maxFailedLoginAttempts = authSection["MaxFailedLoginAttempts"],
                    lockoutDurationMinutes = authSection["LockoutDurationMinutes"],
                    baseUrl = authSection["BaseUrl"],
                    allowPasswordLogin = authSection["AllowPasswordLogin"],
                    requireEmailVerification = authSection["RequireEmailVerification"],
                    minPasswordLength = authSection["MinPasswordLength"],
                    requireUppercase = authSection["RequireUppercase"],
                    requireDigit = authSection["RequireDigit"],
                    requireSpecialChar = authSection["RequireSpecialChar"],
                    allowedDomain = authSection["AllowedDomain"],
                    adminEmails = _configuration.GetSection("AuthConfiguration:AdminEmails").Get<string[]>() ?? []
                },
                database = new
                {
                    host = dbInfo.Host,
                    port = dbInfo.Port,
                    database = dbInfo.Database,
                    username = dbInfo.Username,
                    passwordConfigured = !string.IsNullOrEmpty(dbInfo.Password),
                    status = dbStatus,
                    postgresVersion = dbVersion
                },
                smtp = new
                {
                    host = smtpSection["Host"],
                    port = smtpSection["Port"],
                    useSsl = smtpSection["UseSsl"],
                    username = smtpSection["Username"],
                    passwordConfigured = !string.IsNullOrEmpty(smtpSection["Password"]),
                    fromEmail = smtpSection["FromEmail"],
                    fromName = smtpSection["FromName"]
                },
                cors = new
                {
                    allowedOrigins = corsOrigins
                },
                logFileSettings = new
                {
                    logFolder = logSection["LogFolder"],
                    serverName = logSection["ServerName"],
                    uncShareName = logSection["UncShareName"],
                    alertSmsNumber = logSection["AlertSmsNumber"]
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error in GetConfig");
            return StatusCode(500, new { error = "An error occurred while processing the request." });
        }
    }

    /// <summary>
    /// Parse a PostgreSQL connection string into components (redacts password)
    /// </summary>
    private static (string Host, string Port, string Database, string Username, string Password) ParseConnectionString(string connectionString)
    {
        var parts = connectionString.Split(';')
            .Select(p => p.Trim())
            .Where(p => !string.IsNullOrEmpty(p))
            .Select(p =>
            {
                var idx = p.IndexOf('=');
                return idx > 0 ? (Key: p[..idx].Trim(), Value: p[(idx + 1)..].Trim()) : (Key: p, Value: "");
            })
            .ToDictionary(p => p.Key, p => p.Value, StringComparer.OrdinalIgnoreCase);

        return (
            Host: parts.GetValueOrDefault("Host", ""),
            Port: parts.GetValueOrDefault("Port", "5432"),
            Database: parts.GetValueOrDefault("Database", ""),
            Username: parts.GetValueOrDefault("Username", ""),
            Password: parts.GetValueOrDefault("Password", "")
        );
    }

    /// <summary>
    /// Get database info: name, server, port, size, version, and uptime
    /// </summary>
    [HttpGet("db-info")]
    public async Task<IActionResult> GetDatabaseInfo()
    {
        try
        {
            var connectionString = _configuration.GetConnectionString("AuthDb") ?? "";
            var dbInfo = ParseConnectionString(connectionString);

            await using var conn = new NpgsqlConnection(connectionString);
            await conn.OpenAsync();

            // Database size
            await using var sizeCmd = new NpgsqlCommand(
                "SELECT pg_size_pretty(pg_database_size(current_database())), pg_database_size(current_database())", conn);
            await using var sizeReader = await sizeCmd.ExecuteReaderAsync();
            string sizeFormatted = "Unknown";
            long sizeBytes = 0;
            if (await sizeReader.ReadAsync())
            {
                sizeFormatted = sizeReader.GetString(0);
                sizeBytes = sizeReader.GetInt64(1);
            }
            await sizeReader.CloseAsync();

            // PostgreSQL version
            await using var verCmd = new NpgsqlCommand("SELECT version()", conn);
            var pgVersion = (await verCmd.ExecuteScalarAsync())?.ToString() ?? "Unknown";

            // Server uptime
            await using var uptimeCmd = new NpgsqlCommand(
                "SELECT current_timestamp - pg_postmaster_start_time()", conn);
            var uptimeInterval = await uptimeCmd.ExecuteScalarAsync();
            string uptimeFormatted = uptimeInterval is TimeSpan ts
                ? $"{(int)ts.TotalDays}d {ts.Hours}h {ts.Minutes}m"
                : uptimeInterval?.ToString() ?? "Unknown";

            // Table row counts
            await using var tablesCmd = new NpgsqlCommand(@"
                SELECT relname, n_live_tup
                FROM pg_stat_user_tables
                ORDER BY n_live_tup DESC", conn);
            await using var tablesReader = await tablesCmd.ExecuteReaderAsync();
            var tables = new List<object>();
            while (await tablesReader.ReadAsync())
            {
                tables.Add(new
                {
                    name = tablesReader.GetString(0),
                    rows = tablesReader.GetInt64(1)
                });
            }

            return Ok(new
            {
                host = dbInfo.Host,
                port = dbInfo.Port,
                database = dbInfo.Database,
                sizeFormatted,
                sizeBytes,
                postgresVersion = pgVersion,
                serverUptime = uptimeFormatted,
                tables
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error in GetDatabaseInfo");
            return StatusCode(500, new { error = "Failed to retrieve database info: " + ex.Message });
        }
    }

    /// <summary>
    /// Get the current log file path (local and UNC) for today's date
    /// </summary>
    /// <returns>Local path, UNC path, file existence, and size in bytes</returns>
    [HttpGet("logfile")]
    public IActionResult GetLogFile()
    {
        try
        {
            var optPath = Environment.GetEnvironmentVariable("OptPath");
            if (string.IsNullOrEmpty(optPath))
            {
                return StatusCode(500, new { error = "OptPath environment variable is not set. File logging is not configured." });
            }

            var serverName = _configuration["LogFileSettings:ServerName"] ?? Environment.MachineName;
            var uncShareName = _configuration["LogFileSettings:UncShareName"] ?? "Opt";
            var logFolder = _configuration["LogFileSettings:LogFolder"] ?? @"data\DedgeAuth.Api";

            var today = DateTime.Now.ToString("yyyyMMdd");
            var logFileName = $"DedgeAuth-{today}.log";
            var logDirectory = Path.Combine(optPath, logFolder);
            var localPath = Path.Combine(logDirectory, logFileName);
            var uncPath = $@"\\{serverName}\{uncShareName}\{logFolder}\{logFileName}";

            var fileInfo = new FileInfo(localPath);

            return Ok(new
            {
                localPath,
                uncPath,
                exists = fileInfo.Exists,
                sizeBytes = fileInfo.Exists ? fileInfo.Length : 0,
                logDirectory,
                uncDirectory = $@"\\{serverName}\{uncShareName}\{logFolder}"
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error in GetLogFile");
            return StatusCode(500, new { error = "An error occurred while processing the request." });
        }
    }
}
