using Microsoft.EntityFrameworkCore;
using GenericLogHandler.Core.Models;
using GenericLogHandler.Core.Models.Auth;
using GenericLogHandler.Core.Models.Configuration;
using IBM.EntityFrameworkCore;

namespace GenericLogHandler.Data;

/// <summary>
/// Entity Framework DbContext for the Generic Log Handler
/// </summary>
public class LoggingDbContext : DbContext
{
    public LoggingDbContext(DbContextOptions<LoggingDbContext> options) : base(options)
    {
    }

    /// <summary>
    /// Log entries table
    /// </summary>
    public DbSet<LogEntry> LogEntries { get; set; } = null!;

    /// <summary>
    /// Import status tracking table
    /// </summary>
    public DbSet<ImportStatus> ImportStatuses { get; set; } = null!;

    /// <summary>
    /// Saved search filters table
    /// </summary>
    public DbSet<SavedFilter> SavedFilters { get; set; } = null!;

    /// <summary>
    /// Alert history tracking table
    /// </summary>
    public DbSet<AlertHistory> AlertHistories { get; set; } = null!;

    /// <summary>
    /// Audit log table for tracking user actions
    /// </summary>
    public DbSet<AuditLog> AuditLogs { get; set; } = null!;

    /// <summary>
    /// User accounts table (custom authentication)
    /// </summary>
    public DbSet<User> Users { get; set; } = null!;

    /// <summary>
    /// Import level filters for controlling which log levels are imported per file pattern
    /// </summary>
    public DbSet<ImportLevelFilter> ImportLevelFilters { get; set; } = null!;

    /// <summary>
    /// Import sources configuration table (replaces JSON-based config)
    /// </summary>
    public DbSet<ImportSourceEntity> ImportSources { get; set; } = null!;

    /// <summary>
    /// Job executions table for tracking job lifecycle (start/complete/fail/timeout)
    /// </summary>
    public DbSet<JobExecution> JobExecutions { get; set; } = null!;

    /// <summary>
    /// Login tokens table (magic links, password reset)
    /// </summary>
    public DbSet<LoginToken> LoginTokens { get; set; } = null!;

    /// <summary>
    /// Refresh tokens table (session management)
    /// </summary>
    public DbSet<RefreshToken> RefreshTokens { get; set; } = null!;

    /// <summary>
    /// Temporary queue for the log ingest API -- ImportService drains FIFO
    /// </summary>
    public DbSet<IngestQueueEntry> IngestQueue { get; set; } = null!;

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        var provider = Database.ProviderName ?? string.Empty;
        var isPostgres = provider.Contains("Npgsql", StringComparison.OrdinalIgnoreCase);
        var isDb2 = provider.Contains("IBM", StringComparison.OrdinalIgnoreCase)
            || provider.Contains("DB2", StringComparison.OrdinalIgnoreCase);

        // Configure LogEntry entity
        modelBuilder.Entity<LogEntry>(entity =>
        {
            entity.ToTable("log_entries");
            
            entity.HasKey(e => e.Id);
            
            entity.Property(e => e.Id)
                .HasColumnName("id")
                .ValueGeneratedOnAdd();

            entity.Property(e => e.Timestamp)
                .HasColumnName("timestamp")
                .IsRequired();

            entity.Property(e => e.Level)
                .HasColumnName("level")
                .HasConversion<string>()
                .IsRequired();

            entity.Property(e => e.ProcessId)
                .HasColumnName("process_id");

            entity.Property(e => e.Location)
                .HasColumnName("location")
                .HasMaxLength(500);

            entity.Property(e => e.FunctionName)
                .HasColumnName("function_name")
                .HasMaxLength(200);

            entity.Property(e => e.LineNumber)
                .HasColumnName("line_number");

            entity.Property(e => e.ComputerName)
                .HasColumnName("computer_name")
                .HasMaxLength(100)
                .IsRequired();

            entity.Property(e => e.UserName)
                .HasColumnName("user_name")
                .HasMaxLength(200);

            entity.Property(e => e.Message)
                .HasColumnName("message")
                .IsRequired();

            entity.Property(e => e.ConcatenatedSearchString)
                .HasColumnName("concatenated_search_string");

            entity.Property(e => e.ErrorId)
                .HasColumnName("error_id")
                .HasMaxLength(100);

            entity.Property(e => e.AlertId)
                .HasColumnName("alert_id")
                .HasMaxLength(100);

            entity.Property(e => e.Ordrenr)
                .HasColumnName("ordrenr")
                .HasMaxLength(50);

            entity.Property(e => e.Avdnr)
                .HasColumnName("avdnr")
                .HasMaxLength(50);

            entity.Property(e => e.JobName)
                .HasColumnName("job_name")
                .HasMaxLength(200);

            entity.Property(e => e.JobStatus)
                .HasColumnName("job_status")
                .HasMaxLength(50);

            entity.Property(e => e.ExceptionType)
                .HasColumnName("exception_type")
                .HasMaxLength(500);

            entity.Property(e => e.StackTrace)
                .HasColumnName("stack_trace");

            entity.Property(e => e.InnerException)
                .HasColumnName("inner_exception");

            entity.Property(e => e.CommandInvocation)
                .HasColumnName("command_invocation")
                .HasMaxLength(1000);

            entity.Property(e => e.ScriptLineNumber)
                .HasColumnName("script_line_number");

            entity.Property(e => e.ScriptName)
                .HasColumnName("script_name")
                .HasMaxLength(500);

            entity.Property(e => e.Position)
                .HasColumnName("position");

            entity.Property(e => e.SourceFile)
                .HasColumnName("source_file")
                .HasMaxLength(500);

            entity.Property(e => e.SourceType)
                .HasColumnName("source_type")
                .HasMaxLength(50);

            entity.Property(e => e.ImportTimestamp)
                .HasColumnName("import_timestamp")
                .HasDefaultValueSql("NOW()");

            entity.Property(e => e.ImportBatchId)
                .HasColumnName("import_batch_id")
                .HasMaxLength(50);

            entity.Property(e => e.Protected)
                .HasColumnName("protected")
                .HasDefaultValue(false);

            entity.Property(e => e.ProtectionReason)
                .HasColumnName("protection_reason")
                .HasMaxLength(500);

            if (isPostgres)
            {
                entity.Property(e => e.Message).HasColumnType("text");
                entity.Property(e => e.StackTrace).HasColumnType("text");
                entity.Property(e => e.InnerException).HasColumnType("text");
                entity.Property(e => e.ConcatenatedSearchString).HasColumnType("text");
            }
            else if (isDb2)
            {
                entity.Property(e => e.Message).HasColumnType("CLOB");
                entity.Property(e => e.StackTrace).HasColumnType("CLOB");
                entity.Property(e => e.InnerException).HasColumnType("CLOB");
                entity.Property(e => e.ConcatenatedSearchString).HasColumnType("CLOB");
            }

            // Indexes for performance
            entity.HasIndex(e => e.Timestamp)
                .HasDatabaseName("idx_log_entries_timestamp");

            entity.HasIndex(e => new { e.Timestamp, e.ComputerName, e.Level })
                .HasDatabaseName("idx_log_entries_timestamp_computer_level");

            entity.HasIndex(e => e.ComputerName)
                .HasDatabaseName("idx_log_entries_computer_name");

            entity.HasIndex(e => e.Level)
                .HasDatabaseName("idx_log_entries_level");

            entity.HasIndex(e => e.UserName)
                .HasDatabaseName("idx_log_entries_user_name");

            entity.HasIndex(e => e.SourceType)
                .HasDatabaseName("idx_log_entries_source_type");

            entity.HasIndex(e => e.ErrorId)
                .HasDatabaseName("idx_log_entries_error_id")
                .HasFilter("error_id IS NOT NULL");

            entity.HasIndex(e => e.AlertId)
                .HasDatabaseName("idx_log_entries_alert_id")
                .HasFilter("alert_id IS NOT NULL");

            entity.HasIndex(e => e.Ordrenr)
                .HasDatabaseName("idx_log_entries_ordrenr")
                .HasFilter("ordrenr IS NOT NULL");

            entity.HasIndex(e => e.Avdnr)
                .HasDatabaseName("idx_log_entries_avdnr")
                .HasFilter("avdnr IS NOT NULL");

            entity.HasIndex(e => e.JobName)
                .HasDatabaseName("idx_log_entries_job_name")
                .HasFilter("job_name IS NOT NULL");

            entity.HasIndex(e => e.JobStatus)
                .HasDatabaseName("idx_log_entries_job_status")
                .HasFilter("job_status IS NOT NULL");

            entity.HasIndex(e => e.ImportTimestamp)
                .HasDatabaseName("idx_log_entries_import_timestamp");

            // Index for cleanup queries - efficiently find unprotected old entries
            entity.HasIndex(e => new { e.Protected, e.Timestamp })
                .HasDatabaseName("idx_log_entries_protected_timestamp");

            // DB2 full-text search index (using DB2 Text Search)
            entity.HasIndex(e => e.ConcatenatedSearchString)
                .HasDatabaseName("idx_log_entries_search_text");
        });

        // Configure ImportStatus entity
        modelBuilder.Entity<ImportStatus>(entity =>
        {
            entity.ToTable("import_status");
            
            entity.HasKey(e => e.Id);
            
            entity.Property(e => e.Id)
                .HasColumnName("id")
                .ValueGeneratedOnAdd();

            entity.Property(e => e.SourceName)
                .HasColumnName("source_name")
                .HasMaxLength(200)
                .IsRequired();

            entity.Property(e => e.SourceType)
                .HasColumnName("source_type")
                .HasMaxLength(50)
                .IsRequired();

            entity.Property(e => e.FilePath)
                .HasColumnName("file_path")
                .HasMaxLength(1000);

            entity.Property(e => e.LastProcessedTimestamp)
                .HasColumnName("last_processed_timestamp");

            entity.Property(e => e.LastImportTimestamp)
                .HasColumnName("last_import_timestamp")
                .HasDefaultValueSql("NOW()");

            entity.Property(e => e.RecordsProcessed)
                .HasColumnName("records_processed");

            entity.Property(e => e.RecordsFailed)
                .HasColumnName("records_failed");

            entity.Property(e => e.Status)
                .HasColumnName("status")
                .HasConversion<string>();

            entity.Property(e => e.ErrorMessage)
                .HasColumnName("error_message");

            entity.Property(e => e.ProcessingDurationMs)
                .HasColumnName("processing_duration_ms");

            entity.Property(e => e.Metadata)
                .HasColumnName("metadata");

            entity.Property(e => e.LastProcessedByteOffset)
                .HasColumnName("last_processed_byte_offset");

            entity.Property(e => e.FileHash)
                .HasColumnName("file_hash")
                .HasMaxLength(64);

            entity.Property(e => e.LastFileSize)
                .HasColumnName("last_file_size");

            entity.Property(e => e.FileCreationDate)
                .HasColumnName("file_creation_date");

            entity.Property(e => e.LastProcessedLine)
                .HasColumnName("last_processed_line");

            if (isPostgres)
            {
                entity.Property(e => e.ErrorMessage).HasColumnType("text");
                entity.Property(e => e.Metadata).HasColumnType("text");
            }
            else if (isDb2)
            {
                entity.Property(e => e.ErrorMessage).HasColumnType("CLOB");
                entity.Property(e => e.Metadata).HasColumnType("CLOB");
            }

            // Indexes
            entity.HasIndex(e => new { e.SourceName, e.FilePath })
                .HasDatabaseName("idx_import_status_source_file")
                .IsUnique();

            entity.HasIndex(e => e.LastImportTimestamp)
                .HasDatabaseName("idx_import_status_last_import");

            entity.HasIndex(e => e.Status)
                .HasDatabaseName("idx_import_status_status");
        });

        // Configure SavedFilter entity
        modelBuilder.Entity<SavedFilter>(entity =>
        {
            entity.ToTable("saved_filters");
            
            entity.HasKey(e => e.Id);
            
            entity.Property(e => e.Id)
                .HasColumnName("id")
                .ValueGeneratedOnAdd();

            entity.Property(e => e.Name)
                .HasColumnName("name")
                .HasMaxLength(200)
                .IsRequired();

            entity.Property(e => e.Description)
                .HasColumnName("description")
                .HasMaxLength(1000);

            entity.Property(e => e.FilterJson)
                .HasColumnName("filter_json")
                .IsRequired();

            entity.Property(e => e.CreatedBy)
                .HasColumnName("created_by")
                .HasMaxLength(200)
                .IsRequired();

            entity.Property(e => e.CreatedAt)
                .HasColumnName("created_at")
                .HasDefaultValueSql("NOW()");

            entity.Property(e => e.UpdatedAt)
                .HasColumnName("updated_at");

            entity.Property(e => e.IsAlertEnabled)
                .HasColumnName("is_alert_enabled");

            entity.Property(e => e.AlertConfig)
                .HasColumnName("alert_config");

            entity.Property(e => e.LastEvaluatedAt)
                .HasColumnName("last_evaluated_at");

            entity.Property(e => e.LastTriggeredAt)
                .HasColumnName("last_triggered_at");

            entity.Property(e => e.IsShared)
                .HasColumnName("is_shared");

            entity.Property(e => e.Category)
                .HasColumnName("category")
                .HasMaxLength(100);

            if (isPostgres)
            {
                entity.Property(e => e.FilterJson).HasColumnType("text");
                entity.Property(e => e.AlertConfig).HasColumnType("text");
            }
            else if (isDb2)
            {
                entity.Property(e => e.FilterJson).HasColumnType("CLOB");
                entity.Property(e => e.AlertConfig).HasColumnType("CLOB");
            }

            // Indexes
            entity.HasIndex(e => e.Name)
                .HasDatabaseName("idx_saved_filters_name");

            entity.HasIndex(e => e.CreatedBy)
                .HasDatabaseName("idx_saved_filters_created_by");

            entity.HasIndex(e => e.IsAlertEnabled)
                .HasDatabaseName("idx_saved_filters_alert_enabled")
                .HasFilter("is_alert_enabled = true");

            entity.HasIndex(e => e.Category)
                .HasDatabaseName("idx_saved_filters_category")
                .HasFilter("category IS NOT NULL");
        });

        // Configure AlertHistory entity
        modelBuilder.Entity<AlertHistory>(entity =>
        {
            entity.ToTable("alert_history");
            
            entity.HasKey(e => e.Id);
            
            entity.Property(e => e.Id)
                .HasColumnName("id")
                .ValueGeneratedOnAdd();

            entity.Property(e => e.FilterId)
                .HasColumnName("filter_id")
                .IsRequired();

            entity.Property(e => e.FilterName)
                .HasColumnName("filter_name")
                .HasMaxLength(200)
                .IsRequired();

            entity.Property(e => e.TriggeredAt)
                .HasColumnName("triggered_at")
                .HasDefaultValueSql("NOW()");

            entity.Property(e => e.MatchCount)
                .HasColumnName("match_count");

            entity.Property(e => e.ActionType)
                .HasColumnName("action_type")
                .HasMaxLength(50)
                .IsRequired();

            entity.Property(e => e.ActionTaken)
                .HasColumnName("action_taken")
                .HasMaxLength(2000);

            entity.Property(e => e.Success)
                .HasColumnName("success");

            entity.Property(e => e.ErrorMessage)
                .HasColumnName("error_message");

            entity.Property(e => e.ActionResponse)
                .HasColumnName("action_response");

            entity.Property(e => e.ExecutionDurationMs)
                .HasColumnName("execution_duration_ms");

            entity.Property(e => e.SampleEntryIds)
                .HasColumnName("sample_entry_ids");

            if (isPostgres)
            {
                entity.Property(e => e.ErrorMessage).HasColumnType("text");
                entity.Property(e => e.ActionResponse).HasColumnType("text");
                entity.Property(e => e.SampleEntryIds).HasColumnType("text");
            }
            else if (isDb2)
            {
                entity.Property(e => e.ErrorMessage).HasColumnType("CLOB");
                entity.Property(e => e.ActionResponse).HasColumnType("CLOB");
                entity.Property(e => e.SampleEntryIds).HasColumnType("CLOB");
            }

            // Foreign key relationship
            entity.HasOne(e => e.Filter)
                .WithMany()
                .HasForeignKey(e => e.FilterId)
                .OnDelete(DeleteBehavior.Cascade);

            // Indexes
            entity.HasIndex(e => e.FilterId)
                .HasDatabaseName("idx_alert_history_filter_id");

            entity.HasIndex(e => e.TriggeredAt)
                .HasDatabaseName("idx_alert_history_triggered_at");

            entity.HasIndex(e => e.Success)
                .HasDatabaseName("idx_alert_history_success");
        });

        modelBuilder.Entity<IngestQueueEntry>(entity =>
        {
            entity.ToTable("ingest_queue");
            entity.HasIndex(e => e.CreatedAt)
                .HasDatabaseName("ix_ingest_queue_created_at");
        });
    }

    protected override void OnConfiguring(DbContextOptionsBuilder optionsBuilder)
    {
        if (!optionsBuilder.IsConfigured)
        {
            // This will be overridden by dependency injection in production
            // Default DB2 connection string for development
            optionsBuilder.UseDb2("Server=localhost:50000;Database=LOGS;UID=db2admin;PWD=password;Security=SSL;", options => { });
        }
    }
}
