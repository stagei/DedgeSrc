# PostgreSQL Connection Guide

This document explains how to connect to the Generic Log Handler PostgreSQL database from another project.

## Database Details

| Property | Value |
|----------|-------|
| **Host** | `localhost` |
| **Port** | `5432` |
| **Database** | `loghandler` |
| **Username** | `postgres` |
| **Password** | `postgres` |

> **Note**: For production environments, use a dedicated user with limited permissions and a strong password.

---

## Connection String Format

### Standard Npgsql Format
```
Host=localhost;Port=5432;Database=loghandler;Username=postgres;Password=postgres
```

### With Additional Options
```
Host=localhost;Port=5432;Database=loghandler;Username=postgres;Password=postgres;Timeout=30;Command Timeout=60;Pooling=true;Minimum Pool Size=1;Maximum Pool Size=100
```

### SSL/TLS Connection
```
Host=localhost;Port=5432;Database=loghandler;Username=postgres;Password=postgres;SSL Mode=Require;Trust Server Certificate=true
```

---

## NuGet Packages Required

### For Entity Framework Core (Recommended)
```xml
<PackageReference Include="Npgsql.EntityFrameworkCore.PostgreSQL" Version="10.0.0" />
<PackageReference Include="Microsoft.EntityFrameworkCore" Version="10.0.1" />
```

### For Direct ADO.NET Access
```xml
<PackageReference Include="Npgsql" Version="9.0.3" />
```

---

## Option 1: Entity Framework Core (Recommended)

### 1. Add NuGet Packages
```bash
dotnet add package Npgsql.EntityFrameworkCore.PostgreSQL
dotnet add package Microsoft.EntityFrameworkCore
```

### 2. Create DbContext
```csharp
using Microsoft.EntityFrameworkCore;

public class MyDbContext : DbContext
{
    public MyDbContext(DbContextOptions<MyDbContext> options) : base(options) { }
    
    // Reference the log_entries table from GenericLogHandler
    public DbSet<LogEntry> LogEntries { get; set; }
}

// Entity matching the log_entries table
public class LogEntry
{
    public Guid Id { get; set; }
    public DateTime Timestamp { get; set; }
    public string Level { get; set; } = string.Empty;
    public int ProcessId { get; set; }
    public string ComputerName { get; set; } = string.Empty;
    public string UserName { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
    public string? JobName { get; set; }
    public string? JobStatus { get; set; }
    public string SourceFile { get; set; } = string.Empty;
    public string SourceType { get; set; } = string.Empty;
    public DateTime ImportTimestamp { get; set; }
}
```

### 3. Configure in Program.cs (ASP.NET Core)
```csharp
var builder = WebApplication.CreateBuilder(args);

// Add DbContext with PostgreSQL
builder.Services.AddDbContext<MyDbContext>(options =>
{
    options.UseNpgsql(
        builder.Configuration.GetConnectionString("LogHandler"),
        npgsqlOptions =>
        {
            npgsqlOptions.CommandTimeout(30);
            npgsqlOptions.EnableRetryOnFailure(3);
        });
});
```

### 4. Add Connection String to appsettings.json
```json
{
  "ConnectionStrings": {
    "LogHandler": "Host=localhost;Port=5432;Database=loghandler;Username=postgres;Password=postgres"
  }
}
```

### 5. Query Example
```csharp
public class LogService
{
    private readonly MyDbContext _context;

    public LogService(MyDbContext context)
    {
        _context = context;
    }

    public async Task<List<LogEntry>> GetRecentErrorsAsync(int hours = 24)
    {
        var cutoff = DateTime.UtcNow.AddHours(-hours);
        return await _context.LogEntries
            .Where(e => e.Timestamp >= cutoff && e.Level == "ERROR")
            .OrderByDescending(e => e.Timestamp)
            .Take(100)
            .ToListAsync();
    }

    public async Task<int> GetLogCountAsync()
    {
        return await _context.LogEntries.CountAsync();
    }
}
```

---

## Option 2: Direct ADO.NET (Npgsql)

### 1. Add NuGet Package
```bash
dotnet add package Npgsql
```

### 2. Basic Connection Example
```csharp
using Npgsql;

public class DirectDatabaseAccess
{
    private readonly string _connectionString = 
        "Host=localhost;Port=5432;Database=loghandler;Username=postgres;Password=postgres";

    public async Task<long> GetLogEntryCountAsync()
    {
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync();
        
        await using var command = new NpgsqlCommand("SELECT COUNT(*) FROM log_entries", connection);
        var result = await command.ExecuteScalarAsync();
        return Convert.ToInt64(result);
    }

    public async Task<List<string>> GetRecentMessagesAsync(int limit = 10)
    {
        var messages = new List<string>();
        
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync();
        
        await using var command = new NpgsqlCommand(
            "SELECT message FROM log_entries ORDER BY timestamp DESC LIMIT @limit", 
            connection);
        command.Parameters.AddWithValue("limit", limit);
        
        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            messages.Add(reader.GetString(0));
        }
        
        return messages;
    }
}
```

### 3. Using Connection Pooling (Recommended for High-Load)
```csharp
// Connection pooling is enabled by default in Npgsql
// Configure pool size in connection string:
var connectionString = 
    "Host=localhost;Port=5432;Database=loghandler;Username=postgres;Password=postgres;" +
    "Minimum Pool Size=5;Maximum Pool Size=100;Connection Idle Lifetime=300";
```

---

## Database Schema Reference

### Main Tables

| Table | Description |
|-------|-------------|
| `log_entries` | All imported log entries |
| `import_status` | Import tracking per source/file |
| `saved_filters` | User-saved search filters |
| `alert_history` | Alert agent history |

### log_entries Table Schema

| Column | Type | Description |
|--------|------|-------------|
| `id` | uuid | Primary key |
| `timestamp` | timestamp with time zone | Log entry timestamp |
| `level` | varchar(10) | Log level (TRACE, DEBUG, INFO, WARN, ERROR, FATAL) |
| `process_id` | integer | Process ID |
| `computer_name` | varchar(100) | Source computer name |
| `user_name` | varchar(200) | Username |
| `message` | varchar(8000) | Log message |
| `job_name` | varchar(200) | Job/task name |
| `job_status` | varchar(50) | Job status (Started, Completed, Failed, etc.) |
| `source_file` | varchar(500) | Source file path |
| `source_type` | varchar(50) | Source type (file, json, database, eventlog) |
| `import_timestamp` | timestamp with time zone | When entry was imported |
| `error_id` | varchar(100) | Error identifier |
| `exception_type` | varchar(500) | .NET exception type |
| `stack_trace` | text | Stack trace |

### Useful Indexes

| Index | Columns | Use Case |
|-------|---------|----------|
| `idx_log_entries_timestamp` | timestamp | Date range queries |
| `idx_log_entries_level` | level | Filter by log level |
| `idx_log_entries_computer_name` | computer_name | Filter by computer |
| `idx_log_entries_job_name` | job_name | Filter by job |
| `idx_log_entries_job_status` | job_status | Filter by job status |

---

## Common Queries

### Get Logs by Date Range
```sql
SELECT * FROM log_entries 
WHERE timestamp >= '2026-01-01' AND timestamp < '2026-02-01'
ORDER BY timestamp DESC
LIMIT 1000;
```

### Get Error Summary by Computer
```sql
SELECT computer_name, COUNT(*) as error_count
FROM log_entries
WHERE level = 'ERROR' AND timestamp >= NOW() - INTERVAL '24 hours'
GROUP BY computer_name
ORDER BY error_count DESC;
```

### Get Job Status Summary
```sql
SELECT job_name, job_status, COUNT(*) as count, MAX(timestamp) as last_seen
FROM log_entries
WHERE job_status IS NOT NULL
GROUP BY job_name, job_status
ORDER BY last_seen DESC;
```

### Full-Text Search
```sql
SELECT * FROM log_entries
WHERE concatenated_search_string ILIKE '%error%connection%'
ORDER BY timestamp DESC
LIMIT 100;
```

---

## PowerShell Connection Example

```powershell
# Install module (one-time)
# Install-Module -Name Npgsql -Scope CurrentUser

# Load Npgsql assembly
Add-Type -Path "C:\path\to\Npgsql.dll"

# Connect and query
$connectionString = "Host=localhost;Port=5432;Database=loghandler;Username=postgres;Password=postgres"
$connection = New-Object Npgsql.NpgsqlConnection($connectionString)
$connection.Open()

$command = $connection.CreateCommand()
$command.CommandText = "SELECT COUNT(*) FROM log_entries"
$count = $command.ExecuteScalar()
Write-Host "Total log entries: $count"

$connection.Close()
```

Or using the `psql` CLI:
```powershell
# Ensure PostgreSQL bin is in PATH
$env:PGPASSWORD = "postgres"
psql -h localhost -p 5432 -U postgres -d loghandler -c "SELECT COUNT(*) FROM log_entries"
```

---

## Security Best Practices

1. **Use a Dedicated User**: Create a read-only user for external access:
   ```sql
   CREATE USER external_reader WITH PASSWORD 'strong_password';
   GRANT CONNECT ON DATABASE loghandler TO external_reader;
   GRANT USAGE ON SCHEMA public TO external_reader;
   GRANT SELECT ON ALL TABLES IN SCHEMA public TO external_reader;
   ```

2. **Use SSL/TLS**: Enable encrypted connections:
   ```
   Host=server;Port=5432;Database=loghandler;Username=user;Password=pass;SSL Mode=Require
   ```

3. **Limit Network Access**: Configure `pg_hba.conf` to restrict IP ranges

4. **Use Environment Variables**: Don't hardcode passwords:
   ```csharp
   var password = Environment.GetEnvironmentVariable("LOGHANDLER_DB_PASSWORD");
   ```

---

## Troubleshooting

### Connection Refused
- Check PostgreSQL is running: `Get-Service postgresql*`
- Verify port: `Test-NetConnection localhost -Port 5432`
- Check `pg_hba.conf` allows your IP

### Authentication Failed
- Verify username/password
- Check `pg_hba.conf` authentication method (md5/scram-sha-256)

### Timeout Errors
- Increase timeout in connection string: `Timeout=60`
- Check for long-running queries blocking connections

### DateTime Issues
- Always use UTC: `DateTime.UtcNow`
- Npgsql requires `DateTimeKind.Utc` for `timestamp with time zone` columns
